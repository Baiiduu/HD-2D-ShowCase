import * as THREE from 'three';
import { GLSL_COMMON, FOG } from './shaderlib.js';
import { fbm2 } from './terrain.js';

// Night sky: horizon matches the fog colour so the world dissolves into it; stars and a
// faint milky band overhead, warm glow low on the horizon.
export function makeSky() {
  const geo = new THREE.SphereGeometry(900, 48, 24);
  const mat = new THREE.ShaderMaterial({
    side: THREE.BackSide, depthWrite: false, fog: false,
    uniforms: { uFog: { value: FOG.color }, uTime: { value: 0 } },
    vertexShader: `varying vec3 vDir; void main(){ vDir = normalize(position); vec4 p = projectionMatrix * modelViewMatrix * vec4(position, 1.0); gl_Position = p.xyww; }`,
    fragmentShader: `
      uniform vec3 uFog; uniform float uTime; varying vec3 vDir;
      ${GLSL_COMMON}
      void main(){
        vec3 d = normalize(vDir);
        float h = d.y;
        vec3 horizon = uFog * vec3(0.9, 0.92, 1.1);
        vec3 mid = vec3(0.075, 0.07, 0.11);
        vec3 zen = vec3(0.02, 0.025, 0.06);
        vec3 c = mix(horizon, mid, smoothstep(0.0, 0.16, h));
        c = mix(c, zen, smoothstep(0.16, 0.7, h));
        // warm haze glow hugging the horizon
        c += vec3(0.09, 0.055, 0.035) * exp(-abs(h) * 18.0);
        // stars
        vec2 sp = vec2(atan(d.z, d.x) * 180.0, h * 260.0);
        vec2 cell = floor(sp);
        float s = hash12(cell);
        float star = step(0.985, s) * smoothstep(0.03, 0.2, h);
        float tw = 0.6 + 0.4 * sin(uTime * (1.0 + s * 3.0) + s * 50.0);
        c += vec3(0.95, 0.9, 0.85) * star * tw * (s - 0.985) * 60.0 * 0.6;
        // milky band
        float band = exp(-pow((d.x * 0.6 + h - 0.5) * 3.0, 2.0)) * fbm(d.xz * 6.0) * smoothstep(0.08, 0.3, h);
        c += vec3(0.06, 0.055, 0.07) * band;
        gl_FragColor = vec4(c, 1.0);
      }`,
  });
  const m = new THREE.Mesh(geo, mat);
  m.renderOrder = -10;
  m.frustumCulled = false;
  return m;
}

// Distant mountain ridges in layered haze (aerial perspective), all procedural geometry.
export function makeMountains(center) {
  const group = new THREE.Group();
  const layers = [
    { r: 170, h: 18, base: -6, haze: 0.36, seed: 1.3, rough: 0.035 },
    { r: 260, h: 30, base: -10, haze: 0.54, seed: 7.7, rough: 0.025 },
    { r: 400, h: 56, base: -14, haze: 0.7, seed: 3.1, rough: 0.018 },
  ];
  layers.forEach((L, li) => {
    const seg = 360;
    const a0 = -Math.PI * 0.95, a1 = Math.PI * 0.95; // skip the far south (behind camera)
    const pos = [], idx = [], hgt = [];
    for (let i = 0; i <= seg; i++) {
      const a = a0 + (a1 - a0) * (i / seg);
      // angle 0 = north (-Z)
      const x = center.x + Math.sin(a) * L.r, z = center.z - Math.cos(a) * L.r;
      const n = fbm2(i * L.rough * 3 + L.seed * 10, L.seed) ;
      const ridge = 1 - Math.abs(fbm2(i * L.rough * 1.3 + L.seed, 4.2) * 2 - 1);
      const top = L.base + L.h * (0.35 + 0.65 * (n * 0.6 + ridge * 0.6));
      pos.push(x, L.base - 30, z, x, top, z);
      hgt.push(0, 1);
      if (i < seg) { const b = i * 2; idx.push(b, b + 2, b + 1, b + 1, b + 2, b + 3); }
    }
    const geo = new THREE.BufferGeometry();
    geo.setAttribute('position', new THREE.Float32BufferAttribute(pos, 3));
    geo.setAttribute('aTop', new THREE.Float32BufferAttribute(hgt, 1));
    geo.setIndex(idx);
    const mat = new THREE.ShaderMaterial({
      side: THREE.DoubleSide, fog: false, depthWrite: true,
      uniforms: { uFog: { value: FOG.color }, uHaze: { value: L.haze }, uLayer: { value: li } },
      vertexShader: `attribute float aTop; varying float vTop; varying vec3 vW;
        void main(){ vTop = aTop; vec4 w = modelMatrix * vec4(position,1.0); vW = w.xyz; gl_Position = projectionMatrix * viewMatrix * w; }`,
      fragmentShader: `uniform vec3 uFog; uniform float uHaze; uniform float uLayer; varying float vTop; varying vec3 vW;
        ${GLSL_COMMON}
        void main(){
          vec3 rock = vec3(0.028, 0.03, 0.042);
          // moonlit faces and forest texture
          float n = fbm(vW.xz * 0.05 + vW.y * 0.1);
          rock *= 0.8 + 0.5 * n;
          float rim = smoothstep(0.85, 1.0, vTop) * 0.25;
          vec3 c = rock + vec3(0.12, 0.12, 0.13) * rim;
          // valley mist: lower parts sink into the haze
          float low = 1.0 - smoothstep(-10.0, 6.0 + uLayer * 6.0, vW.y);
          float haze = clamp(uHaze + low * 0.22, 0.0, 1.0);
          c = mix(c, uFog * vec3(0.9, 0.92, 1.1), haze);
          gl_FragColor = vec4(c, 1.0);
        }`,
    });
    const mesh = new THREE.Mesh(geo, mat);
    mesh.renderOrder = -5 + li * -1;
    mesh.frustumCulled = false;
    group.add(mesh);
  });
  return group;
}
