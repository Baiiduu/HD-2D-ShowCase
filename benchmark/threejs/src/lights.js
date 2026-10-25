import * as THREE from 'three';
import { GI } from './shaderlib.js';

export const LIGHT_SCALE = 2.4;   // Godot omni energy -> three candela-ish
export const MAX_POINT_SHADOWS = 4;

const lin = (c) => new THREE.Color().setRGB(c[0], c[1], c[2], THREE.SRGBColorSpace);

export function buildLights(world, scene) {
  const group = new THREE.Group();
  const points = [];
  const scatter = [];
  const emitters = [];
  const glowMat = makeGlowMaterial();
  for (const L of world.json.lights) {
    const color = lin(L.color);
    const p = new THREE.Vector3(...L.position);
    if (L.type === 'OmniLight3D') {
      const light = new THREE.PointLight(color, L.energy * LIGHT_SCALE, L.range * 1.15, 1.7);
      light.position.copy(p);
      light.castShadow = false;
      light.shadow.mapSize.set(512, 512);
      light.shadow.bias = -0.004;
      light.shadow.normalBias = 0.03;
      light.shadow.radius = 4;
      light.shadow.camera.near = 0.15;
      light.shadow.camera.far = L.range * 1.15;
      light.userData = { name: L.name, wantsShadow: L.shadows };
      group.add(light);
      points.push(light);
      // which lights have a visible source body (wash / spirit / glade lights are ambient fills)
      const hasBody = /Lantern|StreetLight/.test(L.name);
      const isFill = /Wash|Spirit|Glade/.test(L.name);
      const redLantern = /Cultivation\/Lantern/.test(L.name);
      scatter.push({
        pos: redLantern ? new THREE.Vector3(p.x, 2.35, p.z - 0.1) : p,
        color: redLantern ? new THREE.Color(1.0, 0.32, 0.14) : color, intensity: L.energy * (hasBody ? 1.0 : 0.45), range: L.range,
        mist: /StreetLight/.test(L.name) ? 1.7 : /Lantern\d/.test(L.name) ? 1.2 : isFill ? 0.1 : 1.0,
      });
      emitters.push({ a: p, b: p, color, strength: L.energy * (isFill ? 0.55 : 0.32), radius: L.range * 1.1, wrap: 1.0 });
      if (hasBody) {
        const size = /StreetLight/.test(L.name) ? 1.6 : /Cultivation/.test(L.name) ? 1.5 : 1.15;
        const glowColor = /Cultivation/.test(L.name) ? new THREE.Color(1.0, 0.22, 0.08).multiplyScalar(0.45) : color;
        const glow = new THREE.Mesh(new THREE.PlaneGeometry(1, 1), glowMat.clone());
        glow.material.uniforms.uColor.value = glowColor.clone().multiplyScalar(L.energy * 0.55);
        glow.material.uniforms.uSize.value = size;
        glow.material.uniforms.uTime = GI.uTime;
        glow.material.uniforms.uSeed.value = Math.random() * 10;
        glow.position.copy(p);
        // lanterns hang slightly above their omni light; centre the glow on the body
        if (/Cultivation/.test(L.name)) glow.position.set(p.x, 2.35, p.z - 0.1);
        if (/StreetLight/.test(L.name)) glow.position.y = 2.55;
        glow.frustumCulled = false;
        glow.renderOrder = 5;
        group.add(glow);
      }
    } else if (L.type === 'SpotLight3D') {
      const light = new THREE.SpotLight(color, L.energy * LIGHT_SCALE * 1.6, L.range * 1.2, THREE.MathUtils.degToRad(L.angle_deg), 0.6, 1.5);
      light.position.copy(p);
      light.target.position.set(p.x, p.y - 3, p.z);
      group.add(light, light.target);
      group.add(makeCone(p, L.range, L.angle_deg, color));
    }
  }
  return { group, points, scatter, emitters };
}

function makeGlowMaterial() {
  return new THREE.ShaderMaterial({
    transparent: true, depthWrite: false, blending: THREE.AdditiveBlending, fog: true,
    defines: { FOG_ADDITIVE: 1 },
    uniforms: THREE.UniformsUtils.merge([THREE.UniformsLib.fog, {
      uColor: { value: new THREE.Color() }, uSize: { value: 1 }, uSeed: { value: 0 }, uTime: { value: 0 },
    }]),
    vertexShader: `
      uniform float uSize; varying vec2 vUv;
      #include <fog_pars_vertex>
      void main(){
        vUv = uv;
        vec4 mv = modelViewMatrix * vec4(0.0, 0.0, 0.0, 1.0);
        vec3 toCam = normalize(-mv.xyz);
        mv.xyz += toCam * 0.35;             // sit in front of the lamp body
        mv.xy += position.xy * uSize;
        vec3 transformed = vec3(0.0);
        gl_Position = projectionMatrix * mv;
        #include <fog_vertex>
      }`,
    fragmentShader: `
      uniform vec3 uColor; uniform float uTime; uniform float uSeed; varying vec2 vUv;
      #include <fog_pars_fragment>
      void main(){
        vec2 d = vUv - 0.5;
        float r = length(d) * 2.0;
        float core = exp(-r * r * 28.0) * 1.6;
        float halo = exp(-r * 4.2) * 0.42;
        float flick = 0.95 + 0.05 * sin(uTime * 8.0 + uSeed * 5.0);
        float a = (core + halo) * smoothstep(1.0, 0.7, r) * flick;
        gl_FragColor = vec4(uColor * a, 1.0);
        #include <fog_fragment>
      }`,
  });
}

// Visible light cone under the street lights (soft, additive)
function makeCone(p, range, angleDeg, color) {
  const h = 2.45;
  const r = Math.tan(THREE.MathUtils.degToRad(angleDeg)) * h * 0.9;
  const geo = new THREE.CylinderGeometry(0.12, r, h, 32, 8, true);
  geo.translate(0, -h / 2, 0);
  const mat = new THREE.ShaderMaterial({
    transparent: true, depthWrite: false, blending: THREE.AdditiveBlending, side: THREE.DoubleSide, fog: true,
    defines: { FOG_ADDITIVE: 1 },
    uniforms: THREE.UniformsUtils.merge([THREE.UniformsLib.fog, { uColor: { value: color.clone() }, uH: { value: h } }]),
    vertexShader: `
      varying float vT; varying vec3 vN; varying vec3 vV; varying vec3 vW;
      uniform float uH;
      #include <fog_pars_vertex>
      void main(){
        vec3 transformed = position;
        vT = -position.y / uH;
        vec4 wp = modelMatrix * vec4(position, 1.0);
        vW = wp.xyz;
        vN = normalize(mat3(modelMatrix) * normal);
        vV = normalize(cameraPosition - wp.xyz);
        gl_Position = projectionMatrix * viewMatrix * wp;
        #include <fog_vertex>
      }`,
    fragmentShader: `
      uniform vec3 uColor; varying float vT; varying vec3 vN; varying vec3 vV; varying vec3 vW;
      uniform float uTime;
      #include <fog_pars_fragment>
      void main(){
        float facing = abs(dot(normalize(vN), normalize(vV)));
        float body = pow(facing, 1.6);
        float fall = (1.0 - vT) * (1.0 - vT) * 0.85 + 0.15;
        float ground = smoothstep(1.0, 0.85, vT);
        float a = body * fall * ground * 0.22;
        gl_FragColor = vec4(uColor * a, 1.0);
        #include <fog_fragment>
      }`,
  });
  mat.uniforms.uTime = GI.uTime;
  const m = new THREE.Mesh(geo, mat);
  m.position.set(p.x, 2.42, p.z);
  m.renderOrder = 4;
  return m;
}

// Give the N closest shadow-casting omni lights an actual shadow map
export function updateShadowAssignment(points, playerPos) {
  const cand = points.filter((l) => l.userData.wantsShadow)
    .map((l) => ({ l, d: l.position.distanceToSquared(playerPos) }))
    .sort((a, b) => a.d - b.d);
  const keep = new Set(cand.slice(0, MAX_POINT_SHADOWS).map((c) => c.l));
  let changed = false;
  for (const l of points) {
    const want = keep.has(l);
    if (l.castShadow !== want) { l.castShadow = want; changed = true; }
  }
  return changed;
}
