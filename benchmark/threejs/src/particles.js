import * as THREE from 'three';
import { GI, GLSL_COMMON, GLSL_NOISE } from './shaderlib.js';

export const PSCALE = { value: 400 }; // viewport height / (2 tan(fov/2)), set on resize

function pointsMaterial(vert, frag, { additive = true, uniforms = {} } = {}) {
  const m = new THREE.ShaderMaterial({
    transparent: true, depthWrite: false, fog: true,
    blending: additive ? THREE.AdditiveBlending : THREE.NormalBlending,
    defines: additive ? { FOG_ADDITIVE: 1 } : {},
    uniforms: THREE.UniformsUtils.merge([THREE.UniformsLib.fog, uniforms]),
    vertexShader: `
      uniform float uTime; uniform float uScale;
      ${GLSL_NOISE}
      #include <fog_pars_vertex>
      ${vert}`,
    fragmentShader: `
      uniform float uTime;
      ${GLSL_COMMON}
      #include <fog_pars_fragment>
      ${frag}`,
  });
  m.uniforms.uTime = GI.uTime;
  m.uniforms.uScale = PSCALE;
  return m;
}

// Fireflies: wander, blink, glow (HDR so bloom picks them up)
export function makeFireflies(world, center, amount, radius = 3.6) {
  const pos = [], seed = [];
  let tries = 0;
  while (pos.length / 3 < amount && tries++ < amount * 40) {
    const a = Math.random() * Math.PI * 2, r = Math.sqrt(Math.random()) * radius;
    const x = center[0] + Math.cos(a) * r, z = center[2] + Math.sin(a) * r * 0.8;
    const [ix, iz] = world.cellIndex(x, z);
    const c = world.cell(ix, iz);
    const g = world.terrainHeight(x, z);
    if (Math.abs(g - (center[1] - 0.9)) > 1.0 && !(c.overlay & 4)) continue;
    pos.push(x, Math.max(g, (c.overlay & 4) ? world.waterY(c.level) : g) + 0.25 + Math.random() * 1.3, z);
    seed.push(Math.random(), Math.random(), Math.random(), Math.random());
  }
  const geo = new THREE.BufferGeometry();
  geo.setAttribute('position', new THREE.Float32BufferAttribute(pos, 3));
  geo.setAttribute('aSeed', new THREE.Float32BufferAttribute(seed, 4));
  const mat = pointsMaterial(`
    attribute vec4 aSeed; varying float vGlow; varying float vHue;
    void main(){
      float t = uTime;
      vec3 p = position;
      p.x += sin(t * (0.3 + aSeed.x * 0.4) + aSeed.y * 6.28) * 0.55 + sin(t * 1.3 + aSeed.z * 9.0) * 0.1;
      p.z += cos(t * (0.25 + aSeed.y * 0.35) + aSeed.x * 6.28) * 0.5;
      p.y += sin(t * (0.5 + aSeed.z * 0.6) + aSeed.w * 6.28) * 0.22;
      float blink = pow(0.5 + 0.5 * sin(t * (0.9 + aSeed.w * 1.2) + aSeed.x * 40.0), 5.0);
      vGlow = 0.12 + blink;
      vHue = aSeed.z;
      vec3 transformed = p;
      vec4 mv = viewMatrix * modelMatrix * vec4(p, 1.0);
      gl_Position = projectionMatrix * mv;
      gl_PointSize = clamp(0.16 * uScale / -mv.z, 2.0, 24.0);
      #include <fog_vertex>
    }`, `
    varying float vGlow; varying float vHue;
    void main(){
      vec2 d = gl_PointCoord - 0.5;
      float r = length(d) * 2.0;
      float core = smoothstep(0.35, 0.0, r);
      float halo = exp(-r * 3.5) * 0.35;
      vec3 c = mix(vec3(1.0, 0.86, 0.35), vec3(0.75, 1.0, 0.45), vHue);
      gl_FragColor = vec4(c * (core * 3.2 + halo) * vGlow, 1.0);
      #include <fog_fragment>
    }`);
  const pts = new THREE.Points(geo, mat);
  pts.frustumCulled = false;
  pts.renderOrder = 6;
  return pts;
}

// Mist at the waterfall foot: big soft moonlit puffs + spray droplets
export function makeWaterfallMist(vol, fallInfo) {
  const group = new THREE.Group();
  const N = 46;
  const pos = [], seed = [];
  for (let i = 0; i < N; i++) {
    pos.push(vol.center[0] + (Math.random() - 0.5) * vol.size[0], vol.center[1], vol.center[2] + (Math.random() - 0.5) * vol.size[2] * 0.7);
    seed.push(Math.random(), Math.random(), Math.random(), Math.random());
  }
  const geo = new THREE.BufferGeometry();
  geo.setAttribute('position', new THREE.Float32BufferAttribute(pos, 3));
  geo.setAttribute('aSeed', new THREE.Float32BufferAttribute(seed, 4));
  const mat = pointsMaterial(`
    attribute vec4 aSeed; varying float vA;
    void main(){
      float life = fract(uTime * (0.12 + aSeed.x * 0.1) + aSeed.y);
      vec3 p = position;
      p.y += 0.12 + life * ${(vol.size[1] * 0.9).toFixed(2)};
      p.x += sin(uTime * 0.4 + aSeed.z * 6.0) * 0.25 + (aSeed.w - 0.5) * life * 0.8;
      p.z += life * 0.35;
      vA = sin(life * 3.14159) * (0.16 + aSeed.w * 0.1);
      vec3 transformed = p;
      vec4 mv = viewMatrix * modelMatrix * vec4(p, 1.0);
      gl_Position = projectionMatrix * mv;
      gl_PointSize = (0.55 + life * 0.9 + aSeed.z * 0.4) * uScale / -mv.z;
      #include <fog_vertex>
    }`, `
    varying float vA;
    void main(){
      vec2 d = gl_PointCoord - 0.5;
      float r = length(d) * 2.0;
      float a = smoothstep(1.0, 0.0, r);
      a *= a;
      gl_FragColor = vec4(vec3(0.78, 0.82, 0.84) * 0.9, a * vA);
      #include <fog_fragment>
    }`, { additive: false });
  const mist = new THREE.Points(geo, mat);
  mist.frustumCulled = false;
  mist.renderOrder = 7;
  group.add(mist);

  // spray droplets bouncing off the plunge pool
  for (const f of fallInfo) {
    const M = 90;
    const p2 = [], s2 = [];
    for (let i = 0; i < M; i++) {
      p2.push(f.x + (Math.random() - 0.5) * 1.4, f.bot + 0.02, f.z + f.dir[1] * 0.15);
      s2.push(Math.random(), Math.random(), Math.random(), Math.random());
    }
    const g2 = new THREE.BufferGeometry();
    g2.setAttribute('position', new THREE.Float32BufferAttribute(p2, 3));
    g2.setAttribute('aSeed', new THREE.Float32BufferAttribute(s2, 4));
    const m2 = pointsMaterial(`
      attribute vec4 aSeed; varying float vA;
      void main(){
        float T = 0.7 + aSeed.x * 0.5;
        float t = fract(uTime / T + aSeed.y) * T;
        vec3 v = vec3((aSeed.z - 0.5) * 0.9, 1.2 + aSeed.w * 1.3, 0.4 + aSeed.x * 0.9);
        vec3 p = position + v * t + vec3(0.0, -4.9 * t * t, 0.0);
        p.y = max(p.y, position.y);
        vA = (1.0 - t / T);
        vec3 transformed = p;
        vec4 mv = viewMatrix * modelMatrix * vec4(p, 1.0);
        gl_Position = projectionMatrix * mv;
        gl_PointSize = clamp(0.045 * uScale / -mv.z, 1.5, 6.0);
        #include <fog_vertex>
      }`, `
      varying float vA;
      void main(){
        vec2 d = abs(gl_PointCoord - 0.5);
        if (max(d.x, d.y) > 0.5) discard;
        gl_FragColor = vec4(vec3(0.9, 0.95, 1.0) * 0.9 * vA, 1.0);
        #include <fog_fragment>
      }`);
    const spray = new THREE.Points(g2, m2);
    spray.frustumCulled = false;
    spray.renderOrder = 7;
    group.add(spray);
  }
  return group;
}

// Dust motes drifting through lamp light (street lights / lanterns)
export function makeDust(lightsList) {
  const pos = [], seed = [], col = [];
  for (const L of lightsList) {
    const n = L.n;
    for (let i = 0; i < n; i++) {
      const a = Math.random() * Math.PI * 2, r = Math.sqrt(Math.random()) * L.r;
      pos.push(L.p.x + Math.cos(a) * r, L.p.y - Math.random() * L.h, L.p.z + Math.sin(a) * r);
      seed.push(Math.random(), Math.random(), Math.random(), Math.random());
      col.push(L.c.r, L.c.g, L.c.b);
    }
  }
  const geo = new THREE.BufferGeometry();
  geo.setAttribute('position', new THREE.Float32BufferAttribute(pos, 3));
  geo.setAttribute('aSeed', new THREE.Float32BufferAttribute(seed, 4));
  geo.setAttribute('aCol', new THREE.Float32BufferAttribute(col, 3));
  const mat = pointsMaterial(`
    attribute vec4 aSeed; attribute vec3 aCol; varying vec3 vC;
    void main(){
      vec3 p = position;
      p.x += sin(uTime * 0.2 + aSeed.x * 6.28) * 0.3;
      p.y += sin(uTime * 0.13 + aSeed.y * 6.28) * 0.25;
      p.z += cos(uTime * 0.17 + aSeed.z * 6.28) * 0.3;
      float tw = 0.4 + 0.6 * pow(0.5 + 0.5 * sin(uTime * 2.0 + aSeed.w * 30.0), 3.0);
      vC = aCol * tw * 0.45;
      vec3 transformed = p;
      vec4 mv = viewMatrix * modelMatrix * vec4(p, 1.0);
      gl_Position = projectionMatrix * mv;
      gl_PointSize = clamp(0.03 * uScale / -mv.z, 1.0, 3.0);
      #include <fog_vertex>
    }`, `
    varying vec3 vC;
    void main(){
      gl_FragColor = vec4(vC, 1.0);
      #include <fog_fragment>
    }`);
  const pts = new THREE.Points(geo, mat);
  pts.frustumCulled = false;
  return pts;
}
