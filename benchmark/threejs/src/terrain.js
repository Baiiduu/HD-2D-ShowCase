import * as THREE from 'three';
import { OV_ROAD, OV_DIRT, OV_WATER } from './layout.js';
import { patchMaterial } from './materials.js';

// dual-grid key -> atlas tile (col,row)
const DG_TABLE = [[0, 3], [3, 3], [0, 0], [3, 2], [0, 2], [1, 2], [2, 3], [3, 1], [1, 3], [0, 1], [3, 0], [2, 0], [1, 0], [2, 2], [1, 1], [2, 1]];

export function buildCellTexture(world) {
  const W = world.ew, H = world.eh;
  const data = new Uint8Array(W * H * 4);
  for (let j = 0; j < H; j++)
    for (let i = 0; i < W; i++) {
      const ix = world.eox + i, iz = world.eoz + j;
      const c = world.cell(ix, iz);
      const k = (j * W + i) * 4;
      data[k] = c.biome;
      data[k + 1] = c.level + 4;
      data[k + 2] = c.overlay;
      data[k + 3] = world.inMap(ix, iz) ? 1 : 0;
    }
  const tex = new THREE.DataTexture(data, W, H, THREE.RGBAIntegerFormat, THREE.UnsignedByteType);
  tex.internalFormat = 'RGBA8UI';
  tex.magFilter = tex.minFilter = THREE.NearestFilter;
  tex.needsUpdate = true;
  return tex;
}

const GLSL_CELLS = /* glsl */ `
uniform highp usampler2D uCells;
uniform vec4 uExt;     // eox, eoz, ew, eh
uniform vec4 uMapRect; // minX minZ maxX maxZ
uvec4 cellAt(ivec2 c){
  ivec2 q = clamp(c - ivec2(uExt.xy), ivec2(0), ivec2(uExt.zw) - 1);
  return texelFetch(uCells, q, 0);
}
float levelTop(uvec4 c){ return (float(c.g) - 4.0) * 0.8 + 0.02; }
float mapOutside(vec2 p){
  vec2 q = max(max(uMapRect.xy - p, p - uMapRect.zw), 0.0);
  return length(q);
}
`;

// ---------------------------------------------------------------------------
// Terrain top surfaces (map + margin) and distant land share one material
// ---------------------------------------------------------------------------
export function makeTerrainMaterial(world, tex, cellTex) {
  const mat = new THREE.MeshStandardMaterial({ color: 0xffffff, roughness: 0.8, metalness: 0.0 });
  const uniforms = {
    uCells: { value: cellTex },
    uExt: { value: new THREE.Vector4(world.eox, world.eoz, world.ew, world.eh) },
    uMapRect: { value: new THREE.Vector4(world.minX, world.minZ, world.maxX, world.maxZ) },
    uTexCity: { value: tex.city }, uTexCyber: { value: tex.cyber },
    uTexSlate: { value: tex.slate }, uTexGrass: { value: tex.grass },
    uRoad: { value: tex.road }, uDirt: { value: tex.dirt },
  };
  const tableGLSL = DG_TABLE.map(([c, r]) => `ivec2(${c},${r})`).join(',');
  patchMaterial(mat, {
    key: 'terrain',
    reflect: true,
    uniforms,
    vertHead: `attribute float aKind; varying float vKind;`,
    vertPre: `vKind = aKind;`,
    fragHead: `
varying float vKind;
${GLSL_CELLS}
uniform sampler2D uTexCity, uTexCyber, uTexSlate, uTexGrass, uRoad, uDirt;
const ivec2 DG[16] = ivec2[16](${tableGLSL});
vec4 biomeTex(int b, vec2 uv){
  if (b == 0) return texPixel(uTexCity, uv, vec2(64.0));
  if (b == 1) { vec4 t = texPixel(uTexCyber, uv, vec2(64.0)); t.rgb *= vec3(0.3, 0.35, 0.46) * 1.15; return t; }
  if (b == 2) return texPixel(uTexSlate, uv, vec2(64.0));
  return texPixel(uTexGrass, uv, vec2(64.0));
}
float ovMask(ivec2 c, uint bit){ return (cellAt(c).b & bit) != 0u ? 1.0 : 0.0; }
vec4 dualGrid(sampler2D atlas, uint bit, vec2 p){
  vec2 g = p / 1.6;
  ivec2 d = ivec2(floor(g));
  vec2 L = g - vec2(d);
  int key = int(ovMask(d, bit)) + 2*int(ovMask(d + ivec2(0,1), bit)) + 4*int(ovMask(d + ivec2(1,0), bit)) + 8*int(ovMask(d + ivec2(1,1), bit));
  if (key == 0) return vec4(0.0);
  ivec2 t = DG[key];
  return texPixelTile(atlas, L, vec2(t) * 0.25, vec2(0.25), vec2(256.0), g * 0.25);
}
`,
    frag: `
{
  vec2 p = vWPos.xz;
  vec2 g = p / 1.6;
  ivec2 ci = ivec2(floor(g + 0.5));
  uvec4 C = cellAt(ci);
  float out_d = mapOutside(p);
  vec2 pq = (floor(p * 40.0) + 0.5) / 40.0;   // snapped to the art pixel grid
  // --- biome with a dithered, pixel-stepped border ---
  vec2 jit = (vec2(fbm(pq * 1.7), fbm(pq * 1.7 + 31.7)) - 0.5) * 0.9;
  uvec4 Cj = cellAt(ivec2(floor((pq + jit) / 1.6 + 0.5)));
  int biome = int(Cj.g == C.g ? Cj.r : C.r);
  float farN = fbm(pq * 0.35);
  if (out_d > 1.5 + farN * 5.0 + (biome == 1 ? -1.0 : 3.0)) biome = 3;
  vec2 uv = vec2(p.x, -p.y) / 1.6;
  vec4 base = biomeTex(biome, uv);
  float isBed = step(0.5, vKind);
  float rough = biome == 0 ? 0.6 : biome == 1 ? 0.32 : biome == 2 ? 0.55 : 0.9;
  float wet = biome == 0 ? 0.42 : biome == 1 ? 0.62 : biome == 2 ? 0.34 : 0.04;
  // slightly varied grass + pixel noise to break tiling
  float pn = hash12(floor(p * 40.0));
  float big = fbm(p * 0.18);
  float farK = smoothstep(12.0, 60.0, out_d);
  base.rgb = mix(base.rgb, vec3(dot(base.rgb, vec3(0.3, 0.59, 0.11))) * vec3(0.9, 0.95, 1.0), farK * 0.5) * mix(1.0, 0.45, farK);
  if (biome == 3) { base.rgb *= mix(vec3(0.62, 0.66, 0.58), vec3(0.8, 0.78, 0.66), big); base.rgb = mix(vec3(dot(base.rgb, vec3(0.3,0.59,0.11))), base.rgb, 0.82); }
  base.rgb *= 0.96 + 0.08 * pn;
  // a slow wind wave rolling over the grass
  if (biome == 3) base.rgb *= 1.0 + 0.07 * sin(dot(pq, vec2(0.55, 0.8)) * 1.3 - uTime * 1.1) * smoothstep(0.3, 0.7, fbm(pq * 0.4 + uTime * 0.05));
  vec3 col = base.rgb;
  // --- dual-grid overlays: dirt, then road ---
  if (isBed < 0.5) {
    float fadeR = 1.0 - smoothstep(10.0, 34.0, out_d + farN * 14.0);
    float fadeD = 1.0 - smoothstep(4.0, 16.0, out_d + farN * 8.0);
    vec4 dirt = dualGrid(uDirt, 2u, p);
    dirt.a *= fadeD;
    col = mix(col, dirt.rgb, dirt.a);
    rough = mix(rough, 0.85, dirt.a); wet = mix(wet, 0.12, dirt.a);
    vec4 road = dualGrid(uRoad, 1u, p);
    road.a *= fadeR;
    col = mix(col, road.rgb, road.a);
    rough = mix(rough, 0.55, road.a); wet = mix(wet, 0.45, road.a);
  } else {
    // riverbed: dark wet pebbles
    vec4 bed = texPixel(uTexSlate, uv * 1.3, vec2(64.0));
    col = bed.rgb * vec3(0.42, 0.40, 0.34);
    rough = 0.4;
  }
  // --- puddles (only meaningful on hard ground) ---
  float lum = dot(col, vec3(0.3, 0.59, 0.11));
  float pud = smoothstep(0.58, 0.68, fbm(pq * 0.55 + 3.0));
  float hard = biome == 3 ? 0.15 : 1.0;
  pud *= hard * (1.0 - isBed) * (out_d > 0.5 ? 0.0 : 1.0);
  wet = clamp(wet * mix(0.75, 1.25, lum * 2.0) + pud * 0.7, 0.0, 1.0);
  rough = mix(rough, 0.06, pud);
  col *= mix(1.0, 0.72, max(pud, wet * 0.35));
  gWet = wet * (out_d > 2.0 ? 0.0 : 1.0);
  gReflN = vec3((hash22(floor(p * 40.0)) - 0.5) * (0.25 + rough) * (1.0 - pud), 1.0).xzy;
  gRough = rough;
  // --- ambient occlusion at the foot of cliffs / buildings ---
  vec2 f = g + 0.5 - vec2(ci);
  float myTop = vWPos.y;
  float ao = 1.0;
  for (int dz = -1; dz <= 1; dz++) for (int dx = -1; dx <= 1; dx++) {
    if (dx == 0 && dz == 0) continue;
    uvec4 N = cellAt(ci + ivec2(dx, dz));
    float nt = levelTop(N);
    if ((N.b & 16u) != 0u) nt += 0.4; // ramps: mid height
    float dh = nt - myTop;
    if (dh < 0.25) continue;
    vec2 e = vec2(dx == 0 ? 0.0 : (dx > 0 ? 1.0 - f.x : f.x), dz == 0 ? 0.0 : (dz > 0 ? 1.0 - f.y : f.y)) * 1.6;
    float dist = (dx != 0 && dz != 0) ? length(e) : max(e.x, e.y);
    float r = clamp(0.35 + dh * 0.5, 0.35, 1.2);
    ao *= mix(0.42, 1.0, smoothstep(0.0, r, dist));
  }
  ao *= boxAO(vWPos, vec3(0.0, 1.0, 0.0));
  gAO = ao;
  diffuseColor.rgb = col;
}
`,
  });
  return mat;
}

// ---------------------------------------------------------------------------
// Cliff walls: rock strata texture, grass lip on top, dark foot, lit crest
// ---------------------------------------------------------------------------
export function makeCliffMaterial(world, tex, cellTex) {
  const mat = new THREE.MeshStandardMaterial({ color: 0xffffff, roughness: 0.92, metalness: 0 });
  patchMaterial(mat, {
    key: 'cliff',
    uniforms: {
      uCliff: { value: tex.cliff }, uTexCity: { value: tex.city }, uTexCyber: { value: tex.cyber },
      uTexSlate: { value: tex.slate }, uTexGrass: { value: tex.grass },
    },
    vertHead: `attribute vec4 aWall; varying vec4 vWall;`, // u, top, bottom, biome
    vertPre: `vWall = aWall;`,
    fragHead: `
varying vec4 vWall;
uniform sampler2D uCliff, uTexCity, uTexCyber, uTexSlate, uTexGrass;
vec4 biomeTex(int b, vec2 uv){
  if (b == 0) return texPixel(uTexCity, uv, vec2(64.0));
  if (b == 1) { vec4 t = texPixel(uTexCyber, uv, vec2(64.0)); t.rgb *= vec3(0.3, 0.35, 0.46) * 1.15; return t; }
  if (b == 2) return texPixel(uTexSlate, uv, vec2(64.0));
  return texPixel(uTexGrass, uv, vec2(64.0));
}`,
    frag: `
{
  float u = vWall.x, top = vWall.y, bot = vWall.z;
  int b = int(vWall.w + 0.5);
  vec2 uv = vec2(u / 1.6, (vWPos.y - 0.02) / 1.6);
  vec3 col = texPixel(uCliff, uv, vec2(64.0)).rgb;
  float depth = top - vWPos.y;
  float column = floor(u * 40.0);
  float lip = (b == 3 ? 0.07 : 0.035) + (b == 3 ? 0.09 : 0.03) * hash12(vec2(column, floor(top * 10.0)));
  lip = floor(lip * 40.0) / 40.0;
  float ao = mix(0.38, 1.0, smoothstep(0.0, 0.55, vWPos.y - bot));
  if (depth < lip) {
    col = biomeTex(b, vec2(u / 1.6, (vWPos.y) / 1.6)).rgb * (b == 3 ? 0.95 : 0.85);
  } else {
    // crest catches the moonlight, deeper strata get darker
    col *= 1.0 + 0.22 * (1.0 - smoothstep(0.0, 0.25, depth - lip));
    col *= mix(1.0, 0.82, smoothstep(0.3, 1.6, depth));
    // a dark line of shadow right under the lip
    col *= mix(0.6, 1.0, smoothstep(0.0, 0.05, depth - lip));
  }
  gAO = ao;
  diffuseColor.rgb = col;
}`,
  });
  return mat;
}

// ---------------------------------------------------------------------------
// Geometry
// ---------------------------------------------------------------------------
export function buildTerrain(world, tex) {
  const cellTex = buildCellTexture(world);
  const cs = world.cs;
  const tops = { pos: [], nrm: [], kind: [], idx: [] };
  const walls = { pos: [], nrm: [], wall: [], idx: [] };

  const cornerH = (ix, iz) => {
    const c = world.cell(ix, iz);
    if (c.overlay & OV_WATER) { const y = world.topY(c.level); return [y, y, y, y]; }
    return world.corners(ix, iz);
  };

  for (let j = 0; j < world.eh; j++)
    for (let i = 0; i < world.ew; i++) {
      const ix = world.eox + i, iz = world.eoz + j;
      const c = world.cell(ix, iz);
      const k = cornerH(ix, iz);
      const x0 = (ix - 0.5) * cs, x1 = (ix + 0.5) * cs, z0 = (iz - 0.5) * cs, z1 = (iz + 0.5) * cs;
      // top quad (subdivided 2x2 so lighting / fog interpolate nicely)
      const isW = (c.overlay & OV_WATER) ? 1 : 0;
      const base = tops.pos.length / 3;
      const N = 2;
      const a = new THREE.Vector3(x1 - x0, k[1] - k[0], 0), b = new THREE.Vector3(0, k[2] - k[0], z1 - z0);
      const n = new THREE.Vector3().crossVectors(b, a).normalize();
      for (let vz = 0; vz <= N; vz++)
        for (let vx = 0; vx <= N; vx++) {
          const fx = vx / N, fz = vz / N;
          const y = (k[0] * (1 - fx) + k[1] * fx) * (1 - fz) + (k[2] * (1 - fx) + k[3] * fx) * fz;
          tops.pos.push(x0 + (x1 - x0) * fx, y, z0 + (z1 - z0) * fz);
          tops.nrm.push(n.x, n.y, n.z);
          tops.kind.push(isW);
        }
      for (let vz = 0; vz < N; vz++)
        for (let vx = 0; vx < N; vx++) {
          const q = base + vz * (N + 1) + vx;
          tops.idx.push(q, q + N + 1, q + 1, q + 1, q + N + 1, q + N + 2);
        }
      // walls on the four sides (built by the higher cell, facing the lower neighbour)
      const sides = [
        { d: [0, -1], mine: [0, 1], theirs: [2, 3], p: [[x0, z0], [x1, z0]], u: 'x' },
        { d: [0, 1], mine: [2, 3], theirs: [0, 1], p: [[x0, z1], [x1, z1]], u: 'x' },
        { d: [-1, 0], mine: [0, 2], theirs: [1, 3], p: [[x0, z0], [x0, z1]], u: 'z' },
        { d: [1, 0], mine: [1, 3], theirs: [0, 2], p: [[x1, z0], [x1, z1]], u: 'z' },
      ];
      for (const s of sides) {
        const nx = ix + s.d[0], nz = iz + s.d[1];
        if (nx < world.eox || nx >= world.eox + world.ew || nz < world.eoz || nz >= world.eoz + world.eh) continue;
        const kn = cornerH(nx, nz);
        const t0 = k[s.mine[0]], t1 = k[s.mine[1]];
        const b0 = kn[s.theirs[0]], b1 = kn[s.theirs[1]];
        if (t0 < b0 - 1e-4 || t1 < b1 - 1e-4) continue;
        if (t0 - b0 < 1e-3 && t1 - b1 < 1e-3) continue;
        const wb = walls.pos.length / 3;
        const [[px0, pz0], [px1, pz1]] = s.p;
        const uu0 = s.u === 'x' ? px0 : pz0, uu1 = s.u === 'x' ? px1 : pz1;
        const vtx = [[px0, b0, pz0, uu0, t0, b0], [px1, b1, pz1, uu1, t1, b1], [px1, t1, pz1, uu1, t1, b1], [px0, t0, pz0, uu0, t0, b0]];
        for (const v of vtx) {
          walls.pos.push(v[0], v[1], v[2]);
          walls.nrm.push(s.d[0], 0, s.d[1]);
          walls.wall.push(v[3], v[4], v[5], c.biome);
        }
        // winding: make the face point toward the neighbour
        const e1 = new THREE.Vector3(px1 - px0, 0, pz1 - pz0);
        const up = new THREE.Vector3(0, 1, 0);
        const fn = new THREE.Vector3().crossVectors(e1, up);
        if (fn.x * s.d[0] + fn.z * s.d[1] > 0) walls.idx.push(wb, wb + 1, wb + 2, wb, wb + 2, wb + 3);
        else walls.idx.push(wb, wb + 2, wb + 1, wb, wb + 3, wb + 2);
      }
    }

  const topGeo = new THREE.BufferGeometry();
  topGeo.setAttribute('position', new THREE.Float32BufferAttribute(tops.pos, 3));
  topGeo.setAttribute('normal', new THREE.Float32BufferAttribute(tops.nrm, 3));
  topGeo.setAttribute('aKind', new THREE.Float32BufferAttribute(tops.kind, 1));
  topGeo.setIndex(tops.idx);
  const wallGeo = new THREE.BufferGeometry();
  wallGeo.setAttribute('position', new THREE.Float32BufferAttribute(walls.pos, 3));
  wallGeo.setAttribute('normal', new THREE.Float32BufferAttribute(walls.nrm, 3));
  wallGeo.setAttribute('aWall', new THREE.Float32BufferAttribute(walls.wall, 4));
  wallGeo.setIndex(walls.idx);

  const terrainMat = makeTerrainMaterial(world, tex, cellTex);
  const cliffMat = makeCliffMaterial(world, tex, cellTex);
  const topMesh = new THREE.Mesh(topGeo, terrainMat);
  topMesh.receiveShadow = true;
  topMesh.castShadow = true;
  const wallMesh = new THREE.Mesh(wallGeo, cliffMat);
  wallMesh.receiveShadow = true;
  wallMesh.castShadow = true;

  const far = buildFarLand(world, terrainMat);
  return { topMesh, wallMesh, far, cellTex, terrainMat };
}

// Distant land beyond the margin: continues the edge heights, then rolls into hills.
export function farHeight(world, x, z) {
  const ex0 = (world.eox - 0.5) * world.cs, ex1 = (world.eox + world.ew - 0.5) * world.cs;
  const ez0 = (world.eoz - 0.5) * world.cs, ez1 = (world.eoz + world.eh - 0.5) * world.cs;
  const cx = Math.min(Math.max(x, ex0 + 0.01), ex1 - 0.01), cz = Math.min(Math.max(z, ez0 + 0.01), ez1 - 0.01);
  const d = Math.hypot(x - cx, z - cz);
  const [ix, iz] = world.cellIndex(cx, cz);
  const c = world.cell(ix, iz);
  let h = world.terrainHeight(cx, cz);
  const n = fbm2(x * 0.03, z * 0.03);
  const n2 = fbm2(x * 0.011 + 7.3, z * 0.011 - 2.1);
  const amp = smooth(4, 40, d) * (1.5 + 10.0 * smooth(40, 180, d));
  const north = z < 0 ? 1.0 + smooth(0, 120, -z) * 0.8 : 0.6;
  const ridge = 1 - Math.abs(fbm2(x * 0.018 + 3.3, z * 0.018 + 1.7) * 2 - 1);
  let hill = (n - 0.42) * amp * north + (n2 - 0.4) * amp * 1.2 * north + ridge * ridge * amp * 0.5 * north;
  if (c.overlay & OV_WATER) h = world.topY(c.level);
  return h + hill;
}
function smooth(a, b, x) { const t = Math.min(Math.max((x - a) / (b - a), 0), 1); return t * t * (3 - 2 * t); }
function hash2(x, y) { const s = Math.sin(x * 127.1 + y * 311.7) * 43758.5453; return s - Math.floor(s); }
function vnoise2(x, y) {
  const ix = Math.floor(x), iy = Math.floor(y), fx = x - ix, fy = y - iy;
  const ux = fx * fx * (3 - 2 * fx), uy = fy * fy * (3 - 2 * fy);
  const a = hash2(ix, iy), b = hash2(ix + 1, iy), c = hash2(ix, iy + 1), d = hash2(ix + 1, iy + 1);
  return (a + (b - a) * ux) * (1 - uy) + (c + (d - c) * ux) * uy;
}
export function fbm2(x, y) { let a = 0.5, s = 0; for (let i = 0; i < 5; i++) { s += a * vnoise2(x, y); x = x * 2.03 + 17.1; y = y * 2.03 + 9.2; a *= 0.5; } return s; }

function buildFarLand(world, mat) {
  const cs = world.cs;
  const ex0 = (world.eox - 0.5) * cs, ex1 = (world.eox + world.ew - 0.5) * cs;
  const ez0 = (world.eoz - 0.5) * cs, ez1 = (world.eoz + world.eh - 0.5) * cs;
  const axis = (lo, hi, minV, maxV) => {
    const out = [];
    for (let v = lo; v <= hi + 1e-6; v += cs) out.push(v);
    let step = cs, v = lo;
    const pre = [];
    while (v > minV) { step = Math.min(step * 1.08, 14); v -= step; pre.unshift(v); }
    v = hi; step = cs;
    const post = [];
    while (v < maxV) { step = Math.min(step * 1.08, 14); v += step; post.push(v); }
    return [...pre, ...out, ...post];
  };
  const xs = axis(ex0, ex1, -320, 380);
  const zs = axis(ez0, ez1, -420, 120);
  const pos = [], idx = [], kind = [], nrm = [];
  for (let j = 0; j < zs.length; j++)
    for (let i = 0; i < xs.length; i++) {
      pos.push(xs[i], farHeight(world, xs[i], zs[j]), zs[j]);
      kind.push(0);
    }
  const W = xs.length;
  for (let j = 0; j < zs.length - 1; j++)
    for (let i = 0; i < W - 1; i++) {
      const cx = (xs[i] + xs[i + 1]) / 2, cz = (zs[j] + zs[j + 1]) / 2;
      if (cx > ex0 && cx < ex1 && cz > ez0 && cz < ez1) continue;
      const q = j * W + i;
      idx.push(q, q + W, q + 1, q + 1, q + W, q + W + 1);
    }
  const geo = new THREE.BufferGeometry();
  geo.setAttribute('position', new THREE.Float32BufferAttribute(pos, 3));
  geo.setAttribute('aKind', new THREE.Float32BufferAttribute(kind, 1));
  geo.setIndex(idx);
  geo.computeVertexNormals();
  const mesh = new THREE.Mesh(geo, mat);
  mesh.receiveShadow = true;
  return mesh;
}
