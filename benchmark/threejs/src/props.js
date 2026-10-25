import * as THREE from 'three';
import { patchMaterial } from './materials.js';
import { OV_BRIDGE, OV_WATER } from './layout.js';

export const EMIT_SCALE = 1.25; // Godot emission energy -> our HDR emissive multiplier

const lin = (c) => new THREE.Color().setRGB(c[0], c[1], c[2], THREE.SRGBColorSpace);

function styleOf(name) {
  if (/City\/Building/.test(name)) return 'plaster';
  if (/City\/Roof/.test(name)) return 'roof';
  if (/City\/Window/.test(name)) return 'window';
  if (/City\/Door/.test(name)) return 'door';
  if (/Lamppost/.test(name)) return 'metal';
  if (/City\/Lantern/.test(name)) return 'lampglass';
  if (/Lantern\d\/Lamp/.test(name)) return 'paperlamp';
  if (/Lantern\d\/(Post|Cap)/.test(name)) return 'darkwood';
  if (/Cyber\/Tower/.test(name)) return 'tower';
  if (/Cyber\/(Strip|Edge)/.test(name)) return 'neon';
  if (/Temple(Base)|Step/.test(name)) return 'slate';
  if (/Pillar/.test(name)) return 'pillar';
  if (/RoofEaves/.test(name)) return 'eaves';
  if (/TempleRoof/.test(name)) return 'tileroof';
  if (/RedLantern/.test(name)) return 'redlantern';
  return 'plain';
}

// Box-projected world UV (axis picked from the normal)
const BOXUV = `
vec3 an = abs(normalize(vWNrm));
vec2 wuv = an.y > 0.5 ? vWPos.xz : (an.x > 0.5 ? vec2(vWPos.z, vWPos.y) : vec2(vWPos.x, vWPos.y));
`;

function makePropMaterial(m, style, tex, size) {
  const M = m.material;
  const mat = new THREE.MeshStandardMaterial({
    color: lin(M.albedo), roughness: M.roughness, metalness: M.metallic,
  });
  if (M.emission) {
    mat.emissive = lin(M.emission);
    mat.emissiveIntensity = M.emission_energy * EMIT_SCALE;
  }
  const half = new THREE.Vector3(...(size || [1, 1, 1])).multiplyScalar(0.5);
  const uniforms = {
    uHalf: { value: half }, uSeed: { value: Math.random() * 100 },
    uWood: { value: tex.wood }, uSlate: { value: tex.slate }, uMetal: { value: tex.cyber },
  };
  const head = `uniform vec3 uHalf; uniform float uSeed; uniform sampler2D uWood, uSlate, uMetal; varying vec3 vLPos;`;
  let frag = '', emissive = '', vertPre = '', gi = 1.0;
  switch (style) {
    case 'plaster':
      frag = BOXUV + `
{
  vec2 px = floor(wuv * 40.0);
  float n = hash12(px) * 0.06 + fbm(wuv * 3.0) * 0.12;
  vec3 c = diffuseColor.rgb * (0.92 + n);
  float y = vWPos.y;
  if (an.y < 0.5) {
    // rough stone plinth with brick courses
    if (y < 0.5) {
      float row = floor(y / 0.125);
      float bx = floor((wuv.x + row * 0.11) / 0.27);
      float mortar = step(fract(y / 0.125), 0.12) + step(fract((wuv.x + row * 0.11) / 0.27), 0.06);
      c = diffuseColor.rgb * vec3(0.7, 0.66, 0.62) * (0.85 + 0.25 * hash12(vec2(bx, row) + uSeed));
      c *= mix(1.0, 0.6, clamp(mortar, 0.0, 1.0));
    }
    // timber string course between floors and under the eaves
    float band = step(abs(y - 1.88), 0.06) + step(uHalf.y * 2.0 - 0.18 + 0.05, y);
    c = mix(c, vec3(0.16, 0.10, 0.07), clamp(band, 0.0, 1.0));
    // corners: darker quoins
    vec3 lp = abs(vLPos) / uHalf;
    float edge = max(an.x > 0.5 ? lp.z : lp.x, 0.0);
    if (edge > 0.93 && y > 0.5) c *= 0.8 + 0.1 * step(0.5, fract(y / 0.3));
  }
  // dark at the foot (contact) and grime streaks
  c *= mix(0.65, 1.0, smoothstep(0.0, 0.6, y));
  diffuseColor.rgb = c;
}`;
      break;
    case 'roof':
      frag = BOXUV + `
{
  vec3 c = diffuseColor.rgb;
  if (an.y > 0.5) {
    float row = floor(vWPos.z / 0.18);
    float t = fract(vWPos.z / 0.18);
    float tile = floor((vWPos.x + row * 0.09) / 0.18);
    c *= 0.8 + 0.3 * hash12(vec2(tile, row) + uSeed);
    c *= mix(0.55, 1.0, smoothstep(0.0, 0.25, t));
    c *= 0.85 + 0.15 * step(0.08, fract((vWPos.x + row * 0.09) / 0.18));
  } else {
    c *= 0.45;
  }
  diffuseColor.rgb = c;
  gRough = 0.6;
}`;
      break;
    case 'window':
      emissive = `
{
  vec2 l = vLPos.xy / uHalf.xy; // -1..1
  float frame = step(0.82, abs(l.x)) + step(0.86, abs(l.y));
  float mull = step(abs(l.x), 0.06) + step(abs(l.y + 0.1), 0.05);
  float glass = 1.0 - clamp(frame + mull, 0.0, 1.0);
  float grad = mix(1.15, 0.7, (l.y * 0.5 + 0.5));
  // a soft silhouette of curtains on the sides
  float curtain = smoothstep(0.45, 0.75, abs(l.x)) * 0.45;
  float flick = 0.96 + 0.04 * sin(uTime * 1.3 + uSeed * 7.0);
  totalEmissiveRadiance *= glass * grad * (1.0 - curtain) * flick;
  if (glass < 0.5) diffuseColor.rgb = vec3(0.12, 0.08, 0.06);
}`;
      gi = 0.0;
      break;
    case 'door':
      frag = `
{
  vec3 w = texPixel(uWood, vec2(vWPos.y, vWPos.x) / 1.6, vec2(64.0)).rgb;
  diffuseColor.rgb *= w * 1.6;
}`;
      break;
    case 'darkwood':
      frag = BOXUV + `
{
  vec3 w = texPixel(uWood, wuv.yx / 1.6, vec2(64.0)).rgb;
  diffuseColor.rgb *= w * 1.5;
}`;
      break;
    case 'metal':
      frag = `
{
  float y = vWPos.y;
  float ring = step(fract(y / 0.6), 0.05);
  diffuseColor.rgb *= 0.55 + 0.25 * ring;
  gRough = 0.35; gMetal = 0.7;
}`;
      break;
    case 'lampglass':
    case 'paperlamp':
      emissive = `
{
  vec3 l = abs(vLPos) / uHalf;
  vec3 an = abs(normalize(vWNrm));
  vec2 f = an.y > 0.5 ? l.xz : (an.x > 0.5 ? l.zy : l.xy);
  float frame = step(0.82, max(f.x, f.y));
  ${style === 'paperlamp' ? 'frame = max(frame, step(abs(f.y - 0.0), 0.06));' : 'frame = max(frame, step(abs(f.x), 0.07));'}
  float flick = 0.94 + 0.06 * sin(uTime * 9.0 + uSeed) * sin(uTime * 3.7 + uSeed * 3.0);
  if (an.y > 0.5) frame = 1.0;
  totalEmissiveRadiance *= (1.0 - frame) * flick * 1.3;
  diffuseColor.rgb = frame > 0.5 ? vec3(0.012, 0.01, 0.008) : diffuseColor.rgb * 0.02;
}`;
      gi = 0.0;
      break;
    case 'tower':
      frag = BOXUV + `
{
  vec3 t = texPixel(uMetal, wuv / 1.6, vec2(64.0)).rgb;
  vec3 c = diffuseColor.rgb * (0.55 + 0.9 * t);
  gRough = mix(0.35, 0.6, t.r);
  gMetal = 0.35;
  diffuseColor.rgb = c;
}`;
      emissive = BOXUV + `
{
  // tiny lit windows in the panel grid (cyan / magenta / warm)
  if (an.y < 0.5) {
    vec2 cell = floor(wuv / vec2(0.2, 0.32));
    vec2 f = fract(wuv / vec2(0.2, 0.32));
    float h = hash12(cell + uSeed);
    float on = step(0.93, h) * step(0.35, f.x) * step(f.x, 0.65) * step(0.38, f.y) * step(f.y, 0.56);
    on *= step(0.3, vWPos.y) * step(vWPos.y, uHalf.y * 2.0 - 0.2);
    float blink = step(0.15, fract(uTime * 0.05 + h * 13.0));
    vec3 wc = h > 0.95 ? vec3(1.0, 0.3, 0.8) : (h > 0.91 ? vec3(0.25, 0.95, 1.0) : vec3(1.0, 0.75, 0.45));
    totalEmissiveRadiance += wc * on * blink * 0.7;
    // roof rim light
    totalEmissiveRadiance += vec3(0.3, 0.9, 1.0) * step(uHalf.y * 2.0 - 0.06, vWPos.y) * 0.6;
  }
}`;
      break;
    case 'neon':
      emissive = `
{
  vec3 l = abs(vLPos) / uHalf;
  float core = 1.0 - min(l.x < 0.99 && uHalf.x < 0.1 ? l.x : l.y, 1.0);
  float flick = 0.92 + 0.08 * sin(uTime * 23.0 + uSeed * 9.0) * step(0.97, fract(uTime * 0.13 + uSeed));
  totalEmissiveRadiance *= (0.85 + 0.6 * core) * flick;
}`;
      gi = 0.0;
      break;
    case 'slate':
      frag = BOXUV + `
{
  vec3 t = texPixel(uSlate, wuv / 1.6, vec2(64.0)).rgb;
  diffuseColor.rgb *= t * 1.45;
  if (an.y < 0.5) diffuseColor.rgb *= 0.82;
  gRough = 0.6;
}`;
      break;
    case 'pillar':
      frag = `
{
  float ang = atan(vLPos.z, vLPos.x);
  vec2 uv = vec2(ang * 0.13 / 1.6, vWPos.y / 1.6);
  vec3 w = texPixel(uWood, uv.yx, vec2(64.0)).rgb;
  vec3 lac = vec3(0.55, 0.12, 0.08);
  diffuseColor.rgb = mix(lac, lac * 1.4, w.r) * (0.75 + 0.5 * w);
  // gilded bands near top and bottom
  float y = vLPos.y / uHalf.y;
  if (abs(y) > 0.9 && abs(y) < 0.96) diffuseColor.rgb = vec3(0.75, 0.55, 0.22);
  gRough = 0.4;
}`;
      break;
    case 'eaves':
    case 'tileroof':
      vertPre = style === 'eaves' ? `
{
  vec3 q = abs(position) / uHalf;
  float up = 0.32 * pow(q.x, 5.0) * pow(q.z, 5.0) + 0.07 * (pow(q.x, 8.0) + pow(q.z, 8.0));
  transformed.y += up;
}` : '';
      frag = `
{
  vec3 an = abs(normalize(vWNrm));
  vec3 c = diffuseColor.rgb;
  if (an.z > 0.9 && an.y < 0.2) {
    // gable: dark timber with a lighter plaster triangle
    c = vec3(0.32, 0.2, 0.14) * (0.8 + 0.2 * hash12(floor(vWPos.xy * 40.0)));
  } else {
    // glazed tile channels running down the slope, rows across
    float ch = fract(vWPos.z / 0.2);
    float along = ${style === 'eaves' ? 'vWPos.x' : 'vWPos.y * 1.6'};
    float row = fract(along / 0.24);
    float shade = mix(0.65, 1.15, smoothstep(0.0, 0.45, ch) * (1.0 - smoothstep(0.55, 1.0, ch)));
    shade *= mix(0.75, 1.0, smoothstep(0.0, 0.2, row));
    c *= shade * (0.92 + 0.12 * hash12(floor(vec2(vWPos.z / 0.2, along / 0.24)) + uSeed));
    ${style === 'eaves' ? 'if (an.y < 0.5) c = vec3(0.55, 0.15, 0.1) * 0.8;' : ''}
  }
  diffuseColor.rgb = c;
  gRough = 0.35;
}`;
      break;
    case 'redlantern':
      emissive = `
{
  float ang = atan(vLPos.z, vLPos.x);
  float rib = abs(fract(ang * 8.0 / 6.2831853) - 0.5) * 2.0;
  float y = vLPos.y / uHalf.y;
  float band = step(0.78, abs(y));
  float bulge = 1.0 - y * y;
  vec3 paper = mix(vec3(1.0, 0.14, 0.05), vec3(1.0, 0.5, 0.2), bulge * bulge * 0.6);
  paper *= mix(0.55, 1.0, smoothstep(0.0, 0.25, rib));
  float flick = 0.95 + 0.05 * sin(uTime * 7.0 + uSeed);
  totalEmissiveRadiance = mix(paper * 1.25 * flick, vec3(0.9, 0.6, 0.2) * 0.4, band);
  // the lamp sits right inside its own omni light: keep the shell nearly unlit (self-lit paper)
  diffuseColor.rgb = mix(vec3(0.02, 0.003, 0.002), vec3(0.03, 0.02, 0.006), band);
}`;
      gi = 0.0;
      break;
  }
  patchMaterial(mat, {
    key: 'prop-' + style,
    uniforms,
    vertHead: `varying vec3 vLPos; uniform vec3 uHalf;`,
    vertPre: `vLPos = position;\n` + vertPre,
    fragHead: head,
    frag: frag ? `{
${frag}
}` : '', emissive: emissive ? `{
${emissive}
}` : '', gi,
  });
  return mat;
}

function geometryFor(m, style) {
  if (m.mesh === 'BoxMesh') {
    const [x, y, z] = m.size;
    if (style === 'eaves') return new THREE.BoxGeometry(x, y, z, 32, 1, 24);
    return new THREE.BoxGeometry(x, y, z);
  }
  if (m.mesh === 'CylinderMesh') {
    const seg = m.top_radius > 0.1 ? 20 : 10;
    return new THREE.CylinderGeometry(m.top_radius, m.bottom_radius, m.height, seg, 1);
  }
  if (m.mesh === 'PrismMesh') {
    const [sx, sy, sz] = m.size;
    const ax = -sx / 2 + sx * m.left_to_right;
    const shape = new THREE.Shape();
    shape.moveTo(-sx / 2, -sy / 2);
    shape.lineTo(sx / 2, -sy / 2);
    shape.lineTo(ax, sy / 2);
    shape.closePath();
    const g = new THREE.ExtrudeGeometry(shape, { depth: sz, bevelEnabled: false });
    g.translate(0, 0, -sz / 2);
    return g.toNonIndexed();
  }
  return new THREE.BoxGeometry(1, 1, 1);
}

export function buildProps(world, tex) {
  const group = new THREE.Group();
  const emitters = [];
  const aoBoxes = [];
  for (const m of world.json.meshes) {
    const style = styleOf(m.name);
    const size = m.mesh === 'BoxMesh' || m.mesh === 'PrismMesh' ? m.size :
      [m.top_radius * 2, m.height, m.top_radius * 2];
    const mat = makePropMaterial(m, style, tex, size);
    const geo = geometryFor(m, style);
    if (style === 'tileroof') geo.computeVertexNormals();
    const mesh = new THREE.Mesh(geo, mat);
    const T = m.transform;
    const basis = new THREE.Matrix4().makeBasis(new THREE.Vector3(...T.basis_x), new THREE.Vector3(...T.basis_y), new THREE.Vector3(...T.basis_z));
    basis.setPosition(...T.origin);
    mesh.matrixAutoUpdate = false;
    mesh.matrix.copy(basis);
    mesh.updateMatrixWorld(true);
    mesh.name = m.name;
    const emissive = !!m.material.emission;
    mesh.castShadow = !emissive;
    mesh.receiveShadow = true;
    mesh.userData.style = style;
    group.add(mesh);

    const o = T.origin;
    // collision / AO / walkable surfaces
    if (/City\/Building|Cyber\/Tower/.test(m.name)) {
      const [sx, , sz] = m.size;
      world.colliders.push({ type: 'box', x0: o[0] - sx / 2, x1: o[0] + sx / 2, z0: o[2] - sz / 2, z1: o[2] + sz / 2 });
      aoBoxes.push({ x0: o[0] - sx / 2, x1: o[0] + sx / 2, z0: o[2] - sz / 2, z1: o[2] + sz / 2, y0: 0, y1: o[1] + m.size[1] / 2 });
    }
    if (/TempleBase|Step\d/.test(m.name)) {
      const [sx, sy, sz] = m.size;
      world.walkBoxes.push({ x0: o[0] - sx / 2, x1: o[0] + sx / 2, z0: o[2] - sz / 2, z1: o[2] + sz / 2, top: o[1] + sy / 2 });
      aoBoxes.push({ x0: o[0] - sx / 2, x1: o[0] + sx / 2, z0: o[2] - sz / 2, z1: o[2] + sz / 2, y0: 0, y1: o[1] + sy / 2 });
    }
    if (/Pillar|Lamppost/.test(m.name)) world.colliders.push({ type: 'circle', x: o[0], z: o[2], r: m.top_radius + 0.04 });
    if (/Lantern\d\/Post/.test(m.name)) world.colliders.push({ type: 'circle', x: o[0], z: o[2], r: 0.08 });

    // emissive geometry acts as an indirect light source
    if (emissive && !/RedLantern|City\/Lantern|Lantern\d\/Lamp/.test(m.name)) {
      const c = lin(m.material.emission);
      const [sx, sy, sz] = m.size;
      const half = sx >= sy ? new THREE.Vector3(sx / 2, 0, 0) : new THREE.Vector3(0, sy / 2, 0);
      const ctr = new THREE.Vector3(...o);
      const isWin = /Window/.test(m.name);
      // window light is pushed slightly outward from the facade
      if (isWin) ctr.z += 0.25;
      emitters.push({
        a: ctr.clone().sub(half), b: ctr.clone().add(half), color: c,
        strength: isWin ? 0.9 : 1.8, radius: isWin ? 3.2 : 4.5, wrap: 0.4,
      });
    }
  }
  return { group, emitters, aoBoxes };
}

// Wooden bridges generated from bridge cells
export function buildBridges(world, tex) {
  const group = new THREE.Group();
  const mat = new THREE.MeshStandardMaterial({ color: 0xffffff, roughness: 0.85 });
  patchMaterial(mat, {
    key: 'bridge-wood',
    uniforms: { uWood: { value: tex.wood } },
    fragHead: 'uniform sampler2D uWood;',
    frag: BOXUV + `
{
  vec2 uv = an.y > 0.5 ? vec2(vWPos.z, vWPos.x) : wuv;
  vec3 w = texPixel(uWood, uv / 1.6, vec2(64.0)).rgb;
  diffuseColor.rgb = w * 1.15;
  gRough = 0.8;
}`,
  });
  for (let iz = world.oz; iz < world.oz + world.h; iz++)
    for (let ix = world.ox; ix < world.ox + world.w; ix++) {
      const c = world.rawCell(ix, iz);
      if (!(c.overlay & OV_BRIDGE)) continue;
      const ew = !world.isWater(ix - 1, iz) && !world.isWater(ix + 1, iz);
      const top = world.deckY(c.level);
      const L = world.cs + 0.7, W = 1.3;
      const cx = ix * world.cs, cz = iz * world.cs;
      const parts = [];
      const add = (sx, sy, sz, x, y, z) => parts.push({ sx, sy, sz, x, y, z });
      // deck & stringers
      add(L, 0.1, W, 0, top - 0.05, 0);
      add(L - 0.1, 0.12, 0.12, 0, top - 0.16, W * 0.32);
      add(L - 0.1, 0.12, 0.12, 0, top - 0.16, -W * 0.32);
      // posts & rails both sides
      for (const s of [-1, 1]) {
        const zr = s * (W / 2 - 0.05);
        for (const px of [-L / 2 + 0.08, 0, L / 2 - 0.08]) add(0.08, 0.62, 0.08, px, top + 0.27, zr);
        add(L - 0.05, 0.06, 0.07, 0, top + 0.56, zr);
        add(L - 0.05, 0.04, 0.05, 0, top + 0.3, zr);
      }
      // piles into the riverbed
      for (const s of [-1, 1]) add(0.12, 1.0, 0.12, 0, top - 0.6, s * W * 0.32);
      for (const p of parts) {
        const g = new THREE.BoxGeometry(ew ? p.sx : p.sz, p.sy, ew ? p.sz : p.sx);
        const mesh = new THREE.Mesh(g, mat);
        mesh.position.set(cx + (ew ? p.x : p.z), p.y, cz + (ew ? p.z : p.x));
        mesh.castShadow = true;
        mesh.receiveShadow = true;
        group.add(mesh);
      }
    }
  return group;
}
