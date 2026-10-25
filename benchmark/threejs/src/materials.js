import * as THREE from 'three';
import { GLSL_COMMON, GLSL_GI, GI } from './shaderlib.js';

// Shared uniforms for planar reflections (set by reflection.js)
export const REFL = {
  uReflTex: { value: null },
  uReflMat: { value: new THREE.Matrix4() },
  uReflOn: { value: 0 },
  uReflY: { value: 0.02 },
};

// Water mirrors: one per water-surface height (lowland river / highland stream)
export const REFLW = [
  { uReflTex: { value: null }, uReflMat: { value: new THREE.Matrix4() } },
  { uReflTex: { value: null }, uReflMat: { value: new THREE.Matrix4() } },
];

// Analytic contact-AO boxes (building footprints) shared by all ground-ish materials
export const MAX_AO_BOXES = 24;
export const AOB = {
  uAoBox: { value: Array.from({ length: MAX_AO_BOXES }, () => new THREE.Vector4()) }, // x0 z0 x1 z1
  uAoBoxY: { value: Array.from({ length: MAX_AO_BOXES }, () => new THREE.Vector2()) }, // y0 y1
  uAoN: { value: 0 },
};
export const GLSL_AOBOX = /* glsl */ `
uniform vec4 uAoBox[${MAX_AO_BOXES}];
uniform vec2 uAoBoxY[${MAX_AO_BOXES}];
uniform int uAoN;
float boxAO(vec3 p, vec3 n){
  float ao = 1.0;
  for(int i=0;i<${MAX_AO_BOXES};i++){
    if(i >= uAoN) break;
    vec4 b = uAoBox[i];
    vec2 c = 0.5*(b.xy+b.zw), h = 0.5*(b.zw-b.xy);
    vec2 q = abs(p.xz - c) - h;
    float d = length(max(q, 0.0)) + min(max(q.x, q.y), 0.0);
    if (d < -0.01) continue;              // on top of / inside the box
    if (p.y > uAoBoxY[i].y + 0.05 || p.y < uAoBoxY[i].x - 0.6) continue;
    float hgt = uAoBoxY[i].y - p.y;
    float r = clamp(0.25 + hgt * 0.25, 0.25, 0.9);
    float k = smoothstep(0.0, r, d);
    ao *= mix(0.45, 1.0, k);
  }
  return ao;
}
`;

/**
 * Patch a MeshStandardMaterial with our common extensions.
 * opts.frag   : GLSL run after map sampling (can modify diffuseColor, roughnessFactor, etc.) -
 *               has vWPos, vWNrm available.
 * opts.fragHead: extra GLSL declarations for the fragment shader
 * opts.emissive: GLSL that sets/adds `totalEmissiveRadiance`
 * opts.post   : GLSL executed just before output (has outgoingLight)
 * opts.uniforms: extra uniforms
 * opts.gi     : strength of emitter GI (default 1)
 * opts.vert   : GLSL in vertex main after world position (can modify `transformed` before - use vertPre)
 */
export function patchMaterial(mat, opts = {}) {
  const giStrength = opts.gi ?? 1.0;
  mat.onBeforeCompile = (shader) => {
    Object.assign(shader.uniforms, GI, AOB, opts.uniforms || {});
    if (opts.reflect) Object.assign(shader.uniforms, REFL);
    shader.vertexShader = shader.vertexShader
      .replace('#include <common>', `#include <common>
varying vec3 vWPos;
varying vec3 vWNrm;
${opts.vertHead || ''}`)
      .replace('#include <begin_vertex>', `#include <begin_vertex>
${opts.vertPre || ''}`)
      .replace('#include <project_vertex>', `#include <project_vertex>
{
  vec4 wp = vec4(transformed, 1.0);
  #ifdef USE_INSTANCING
    wp = instanceMatrix * wp;
  #endif
  wp = modelMatrix * wp;
  vWPos = wp.xyz;
  vWNrm = normalize(mat3(modelMatrix) * objectNormal);
}`);
    shader.fragmentShader = shader.fragmentShader
      .replace('#include <common>', `#include <common>
varying vec3 vWPos;
varying vec3 vWNrm;
${GLSL_COMMON}
${GLSL_GI}
${GLSL_AOBOX}
${opts.reflect ? `uniform sampler2D uReflTex; uniform mat4 uReflMat; uniform float uReflOn; uniform float uReflY;` : ''}
${opts.fragHead || ''}
float gAO = 1.0;
float gWet = 0.0;
float gRough = -1.0;
float gMetal = -1.0;
vec3 gReflN = vec3(0.0,1.0,0.0);
`)
      .replace('#include <map_fragment>', `#include <map_fragment>
${opts.frag || ''}`)
      .replace('#include <roughnessmap_fragment>', `#include <roughnessmap_fragment>
if (gRough >= 0.0) roughnessFactor = gRough;`)
      .replace('#include <metalnessmap_fragment>', `#include <metalnessmap_fragment>
if (gMetal >= 0.0) metalnessFactor = gMetal;`)
      .replace('#include <emissivemap_fragment>', `#include <emissivemap_fragment>
${opts.emissive || ''}`)
      .replace('#include <lights_fragment_end>', `#include <lights_fragment_end>
{
  vec3 nW = normalize(vWNrm);
  ${opts.giNormal || ''}
  reflectedLight.indirectDiffuse += emitterGI(vWPos, nW) * diffuseColor.rgb * ${giStrength.toFixed(3)};
  reflectedLight.indirectDiffuse *= gAO;
  reflectedLight.directDiffuse *= mix(1.0, gAO, 0.6);
  reflectedLight.indirectSpecular *= gAO;
}`)
      .replace('#include <opaque_fragment>', `
${opts.reflect ? GLSL_REFLECT : ''}
${opts.post || ''}
#include <opaque_fragment>`);
    if (opts.onShader) opts.onShader(shader);
  };
  mat.customProgramCacheKey = () => (opts.key || mat.uuid);
  return mat;
}

// Planar reflection lookup used by wet/glossy ground and water.
const GLSL_REFLECT = /* glsl */ `
if (uReflOn > 0.5 && gWet > 0.001) {
  vec3 V = normalize(cameraPosition - vWPos);
  #ifdef REFL_ANY_HEIGHT
  float heightOk = 1.0;
  #else
  float heightOk = 1.0 - smoothstep(0.03, 0.25, abs(vWPos.y - uReflY));
  #endif
  vec4 rc = uReflMat * vec4(vWPos, 1.0);
  vec2 ruv = rc.xy / rc.w;
  ruv += gReflN.xz * 0.035;
  float rough = clamp(roughnessFactor, 0.0, 1.0);
  float lod = rough * 4.0;
  vec3 refl = textureLod(uReflTex, ruv, lod).rgb * 0.5;
  refl += textureLod(uReflTex, ruv + vec2(0.0, 0.006 + rough*0.01), lod + 0.5).rgb * 0.25;
  refl += textureLod(uReflTex, ruv - vec2(0.0, 0.006 + rough*0.01), lod + 0.5).rgb * 0.25;
  // emphasise light sources in reflections, suppress the flat sheen of the night haze
  float rl = dot(refl, vec3(0.2126, 0.7152, 0.0722));
  refl *= mix(0.3, 1.0, smoothstep(0.04, 0.35, rl));
  float cosT = clamp(dot(V, vec3(0.0,1.0,0.0)), 0.0, 1.0);
  float fres = 0.04 + 0.96 * pow(1.0 - cosT, 5.0);
  fres = mix(fres, 1.0, 0.18);
  float edge = smoothstep(0.0, 0.03, ruv.x) * smoothstep(1.0, 0.97, ruv.x) * smoothstep(0.0, 0.03, ruv.y) * smoothstep(1.0, 0.97, ruv.y);
  outgoingLight = mix(outgoingLight, outgoingLight * 0.55, gWet * 0.5) + refl * fres * gWet * heightOk * edge;
}
`;

// ---------------------------------------------------------------------------
// Texture helpers
// ---------------------------------------------------------------------------
const loader = new THREE.TextureLoader();
export function loadPixelTex(url, renderer, { repeat = true, flipY = true } = {}) {
  const t = loader.load(url);
  t.colorSpace = THREE.SRGBColorSpace;
  t.magFilter = THREE.LinearFilter; // pixel-AA sampling in shader keeps hard texel squares
  t.minFilter = THREE.LinearMipmapLinearFilter;
  t.generateMipmaps = true;
  t.anisotropy = Math.min(8, renderer.capabilities.getMaxAnisotropy());
  t.wrapS = t.wrapT = repeat ? THREE.RepeatWrapping : THREE.ClampToEdgeWrapping;
  t.flipY = flipY;
  return t;
}
