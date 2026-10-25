import * as THREE from 'three';
import { patchMaterial, REFLW, REFL } from './materials.js';
import { OV_WATER } from './layout.js';
import { GLSL_COMMON, GLSL_GI, GI } from './shaderlib.js';

// Water surfaces: flow-mapped pixel water texture, bank foam, reflections.
export function buildWater(world, tex, cellTex) {
  const cs = world.cs;
  const pos = [], flow = [], idx = [];
  const quad = (x0, z0, x1, z1, y, f) => {
    const b = pos.length / 3;
    pos.push(x0, y, z0, x1, y, z0, x0, y, z1, x1, y, z1);
    for (let i = 0; i < 4; i++) flow.push(f[0], f[1]);
    idx.push(b, b + 2, b + 1, b + 1, b + 2, b + 3);
  };
  for (let j = 0; j < world.eh; j++)
    for (let i = 0; i < world.ew; i++) {
      const ix = world.eox + i, iz = world.eoz + j;
      const c = world.cell(ix, iz);
      if (!(c.overlay & OV_WATER)) continue;
      const f = world.flow.get(ix + ',' + iz) || [0, 1];
      quad((ix - 0.5) * cs, (iz - 0.5) * cs, (ix + 0.5) * cs, (iz + 0.5) * cs, world.waterY(c.level), f);
    }

  const geo = new THREE.BufferGeometry();
  geo.setAttribute('position', new THREE.Float32BufferAttribute(pos, 3));
  geo.setAttribute('normal', new THREE.Float32BufferAttribute(new Array(pos.length).fill(0).map((_, i) => (i % 3 === 1 ? 1 : 0)), 3));
  geo.setAttribute('aFlow', new THREE.Float32BufferAttribute(flow, 2));
  geo.setIndex(idx);

  const mat = new THREE.MeshStandardMaterial({ color: 0xffffff, roughness: 0.12, metalness: 0.0, transparent: true });
  patchMaterial(mat, {
    key: 'water',
    uniforms: {
      uReflOn: REFL.uReflOn,
      uReflA: REFLW[0].uReflTex, uReflMatA: REFLW[0].uReflMat,
      uReflB: REFLW[1].uReflTex, uReflMatB: REFLW[1].uReflMat,
      uWater: { value: tex.water }, uCells: { value: cellTex },
      uExt: { value: new THREE.Vector4(world.eox, world.eoz, world.ew, world.eh) },
    },
    vertHead: 'attribute vec2 aFlow; varying vec2 vFlow;',
    vertPre: 'vFlow = aFlow;',
    fragHead: `
uniform sampler2D uReflA, uReflB; uniform mat4 uReflMatA, uReflMatB; uniform float uReflOn;
varying vec2 vFlow;
uniform sampler2D uWater;
uniform highp usampler2D uCells;
uniform vec4 uExt;
uvec4 cellAt(ivec2 c){ ivec2 q = clamp(c - ivec2(uExt.xy), ivec2(0), ivec2(uExt.zw) - 1); return texelFetch(uCells, q, 0); }
bool isWater(ivec2 c){ return (cellAt(c).b & 4u) != 0u; }
`,
    frag: `
{
  vec2 p = vWPos.xz;
  vec2 g = p / 1.6;
  ivec2 ci = ivec2(floor(g + 0.5));
  vec2 f = g + 0.5 - vec2(ci);
  // distance (m) to the nearest bank, and turbulence below waterfalls
  float bank = 9.0, fall = 9.0;
  uvec4 me = cellAt(ci);
  for (int dz = -1; dz <= 1; dz++) for (int dx = -1; dx <= 1; dx++) {
    if (dx == 0 && dz == 0) continue;
    ivec2 nc = ci + ivec2(dx, dz);
    vec2 e = vec2(dx == 0 ? 9.0 : (dx > 0 ? 1.0 - f.x : f.x), dz == 0 ? 9.0 : (dz > 0 ? 1.0 - f.y : f.y)) * 1.6;
    float d = (dx != 0 && dz != 0) ? length(vec2(dx > 0 ? 1.0 - f.x : f.x, dz > 0 ? 1.0 - f.y : f.y) * 1.6) : min(e.x, e.y);
    uvec4 n = cellAt(nc);
    if ((n.b & 4u) == 0u) bank = min(bank, d);
    else if (n.g > me.g && dx == 0) fall = min(fall, d);
  }
  // two-phase flow mapping along the river
  vec2 fl = normalize(vFlow + 1e-4) * 0.55;
  float t = uTime * 0.6;
  float ph0 = fract(t), ph1 = fract(t + 0.5);
  float wgt = abs(ph0 - 0.5) * 2.0;
  vec2 uv = vec2(p.x, -p.y) / 1.6;
  vec2 fd = vec2(fl.x, -fl.y);
  vec3 w0 = texPixel(uWater, uv - fd * ph0 * 1.2, vec2(64.0)).rgb;
  vec3 w1 = texPixel(uWater, uv - fd * ph1 * 1.2 + 0.37, vec2(64.0)).rgb;
  vec3 wt = mix(w0, w1, wgt);
  vec3 deep = vec3(0.022, 0.045, 0.055);
  float caus = smoothstep(0.72, 0.95, dot(wt, vec3(0.3, 0.4, 0.3)));
  vec3 col = deep + caus * vec3(0.12, 0.2, 0.21) + wt * 0.025;
  // foam: pixel-stepped bands hugging the banks, moving with the current
  vec2 pq = floor(p * 40.0) / 40.0;
  float fn = vnoise(pq * 6.0 - vFlow * uTime * 2.0) * 0.6 + vnoise(pq * 13.0 + uTime * 0.7) * 0.4;
  float foamB = smoothstep(0.16, 0.0, bank - fn * 0.14);
  float foamF = smoothstep(1.2, 0.0, fall - fn * 0.7) * (0.6 + 0.4 * fn);
  float foam = clamp(max(foamB, foamF * 1.1), 0.0, 1.0);
  float speck = step(0.35, hash12(floor(p * 40.0) + floor(uTime * 6.0)));
  foam = step(0.5, foam) * mix(0.35, 0.9, speck) + foam * 0.1;
  col = mix(col, vec3(0.3, 0.33, 0.34), foam);
  diffuseColor.rgb = col;
  diffuseColor.a = mix(0.86, 0.97, foam) * smoothstep(0.0, 0.05, bank + 0.03);
  gRough = mix(0.08, 0.7, foam);
  gWet = (1.0 - foam) * 0.9;
  gReflN = vec3((wt.r - 0.5) * 0.9 + sin(p.y * 7.0 + uTime * 3.0) * 0.08, 1.0, (wt.g - 0.5) * 0.6).xzy;
}`,
    post: `
if (uReflOn > 0.5) {
  bool hi = vWPos.y > 0.1;
  vec4 rc = (hi ? uReflMatB : uReflMatA) * vec4(vWPos, 1.0);
  vec2 ruv = rc.xy / rc.w + gReflN.xz * 0.03;
  vec3 refl = hi ? textureLod(uReflB, ruv, 0.6).rgb : textureLod(uReflA, ruv, 0.6).rgb;
  float rl = dot(refl, vec3(0.2126, 0.7152, 0.0722));
  refl *= mix(0.35, 1.0, smoothstep(0.04, 0.35, rl));
  vec3 V = normalize(cameraPosition - vWPos);
  float fres = 0.04 + 0.96 * pow(1.0 - clamp(V.y, 0.0, 1.0), 5.0);
  outgoingLight += refl * mix(fres, 1.0, 0.15) * gWet;
}`,
  });
  const mesh = new THREE.Mesh(geo, mat);
  mesh.receiveShadow = true;
  mesh.renderOrder = 1;

  // ---- waterfalls: where two water cells of different level touch ----
  const falls = new THREE.Group();
  const fallInfo = [];
  for (let j = 0; j < world.eh; j++)
    for (let i = 0; i < world.ew; i++) {
      const ix = world.eox + i, iz = world.eoz + j;
      if (!world.isWater(ix, iz)) continue;
      const c = world.cell(ix, iz);
      // spring falls: water fed from a higher terrace just upstream (north)
      if (c.outside && !world.isWater(ix, iz - 1)) {
        const up = world.cell(ix, iz - 1);
        const top = world.topY(up.level), bot = world.waterY(c.level);
        if (top - bot > 0.4) {
          const cx = ix * cs, cz = (iz - 0.5) * cs;
          fallInfo.push({ x: cx, z: cz, top, bot, dir: [0, 1] });
          falls.add(makeFall(cx, cz, top, bot, [0, 1], tex));
        }
      }
      for (const [dx, dz] of [[0, 1], [1, 0], [-1, 0], [0, -1]]) {
        if (!world.isWater(ix + dx, iz + dz)) continue;
        const n = world.cell(ix + dx, iz + dz);
        if (n.level >= c.level) continue;
        const top = world.waterY(c.level), bot = world.waterY(n.level);
        const cx = (ix + dx * 0.5) * cs, cz = (iz + dz * 0.5) * cs;
        fallInfo.push({ x: cx, z: cz, top, bot, dir: [dx, dz] });
        falls.add(makeFall(cx, cz, top, bot, [dx, dz], tex));
      }
    }
  return { mesh, falls, fallInfo };
}

function makeFall(cx, cz, top, bot, dir, tex) {
  const w = 1.6, h = top - bot;
  const segY = 10;
  const geo = new THREE.PlaneGeometry(w, h + 0.12, 16, segY);
  // bend: the sheet bulges out over the lip and drops close to the cliff
  const p = geo.attributes.position;
  for (let i = 0; i < p.count; i++) {
    const y = p.getY(i);
    const t = 1 - (y + (h + 0.12) / 2) / (h + 0.12); // 0 at top, 1 at bottom
    const out = 0.06 + 0.22 * Math.sin(Math.min(t * 1.4, 1) * Math.PI * 0.5) - 0.06 * t;
    p.setZ(i, out);
  }
  geo.computeVertexNormals();
  const mat = new THREE.ShaderMaterial({
    transparent: true, depthWrite: false, fog: true,
    uniforms: THREE.UniformsUtils.merge([THREE.UniformsLib.fog, { uWater: { value: null }, uH: { value: h } }]),
    vertexShader: `
      varying vec2 vUv; varying vec3 vW;
      #include <fog_pars_vertex>
      void main(){ vUv = uv; vec3 transformed = position; vec4 wp = modelMatrix * vec4(position,1.0); vW = wp.xyz;
        vec4 mvPosition = viewMatrix * wp; gl_Position = projectionMatrix * mvPosition;
        #include <fog_vertex>
      }`,
    fragmentShader: `
      uniform sampler2D uWater; uniform float uH;
      varying vec2 vUv; varying vec3 vW;
      ${GLSL_COMMON}
      ${GLSL_GI}
      #include <fog_pars_fragment>
      void main(){
        vec2 px = floor(vec2(vUv.x * 64.0, vW.y * 40.0));
        float col = px.x;
        float speed = 2.6 + hash12(vec2(col, 1.0)) * 1.4;
        float s = vnoise(vec2(col * 0.37, (vW.y + uTime * speed) * 4.0));
        float s2 = vnoise(vec2(col * 0.9 + 4.0, (vW.y + uTime * speed * 1.3) * 9.0));
        float streak = smoothstep(0.35, 0.8, s * 0.6 + s2 * 0.5);
        float topFoam = smoothstep(0.82, 1.0, vUv.y);
        float botFoam = smoothstep(0.35, 0.0, vUv.y);
        vec3 base = vec3(0.16, 0.26, 0.3);
        vec3 c = mix(base, vec3(0.85, 0.9, 0.92), clamp(streak * 0.75 + topFoam * 0.8 + botFoam * 0.7, 0.0, 1.0));
        float edge = smoothstep(0.0, 0.06, vUv.x) * smoothstep(1.0, 0.94, vUv.x);
        float a = (0.62 + 0.38 * streak) * edge;
        a = max(a, botFoam * edge);
        // light: moonlight + warm lantern spill
        // moon + sky ambient, plus the lantern light it passes (emitter GI, wrap-lit)
        vec3 light = vec3(0.13, 0.13, 0.15) + emitterGI(vW, vec3(0.0, 0.0, 1.0)) * 0.9;
        c *= light;
        gl_FragColor = vec4(c, a);
        #include <fog_fragment>
      }`,
  });
  Object.assign(mat.uniforms, GI);
  mat.uniforms.uWater.value = tex.water;
  const mesh = new THREE.Mesh(geo, mat);
  mesh.position.set(cx, (top + bot) / 2, cz);
  // face down-stream
  mesh.rotation.y = Math.atan2(dir[0], dir[1]);
  mesh.renderOrder = 2;
  return mesh;
}
