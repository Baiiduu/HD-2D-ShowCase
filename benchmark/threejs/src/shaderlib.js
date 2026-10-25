import * as THREE from 'three';

// ---------------------------------------------------------------------------
// Shared GLSL helpers
// ---------------------------------------------------------------------------
export const GLSL_NOISE = /* glsl */ `
float hash12(vec2 p){ vec3 p3 = fract(vec3(p.xyx) * .1031); p3 += dot(p3, p3.yzx + 33.33); return fract((p3.x + p3.y) * p3.z); }
vec2 hash22(vec2 p){ vec3 p3 = fract(vec3(p.xyx) * vec3(.1031, .1030, .0973)); p3 += dot(p3, p3.yzx+33.33); return fract((p3.xx+p3.yz)*p3.zy); }
float vnoise(vec2 p){ vec2 i = floor(p), f = fract(p); vec2 u = f*f*(3.0-2.0*f);
  return mix(mix(hash12(i), hash12(i+vec2(1,0)), u.x), mix(hash12(i+vec2(0,1)), hash12(i+vec2(1,1)), u.x), u.y); }
float fbm(vec2 p){ float a = 0.5, s = 0.0; for(int i=0;i<4;i++){ s += a*vnoise(p); p = p*2.03 + 17.1; a *= 0.5; } return s; }
`;
export const GLSL_COMMON = GLSL_NOISE + /* glsl */ `

// Pixel-art sampling: texels stay hard squares when magnified, but the one-screen-pixel
// transition between texels is antialiased (no shimmer while the camera moves).
// Mip level is chosen from the continuous uv so minification is stable too.
vec4 texPixel(sampler2D t, vec2 uv, vec2 size){
  vec2 px = uv * size;
  vec2 fw = max(fwidth(px), vec2(1e-4));
  vec2 seam = floor(px + 0.5);
  vec2 p2 = seam + clamp((px - seam) / fw, -0.5, 0.5);
  return textureGrad(t, p2 / size, dFdx(uv), dFdy(uv));
}
// Same, but for a sub-rectangle (atlas tile). local in [0,1], tile origin & size in uv units.
vec4 texPixelTile(sampler2D t, vec2 local, vec2 tileOrigin, vec2 tileSize, vec2 texSize, vec2 gradUv){
  vec2 tilePx = tileSize * texSize;
  vec2 px = local * tilePx;
  vec2 fw = max(fwidth(gradUv * texSize), vec2(1e-4));
  vec2 seam = floor(px + 0.5);
  vec2 p2 = seam + clamp((px - seam) / fw, -0.5, 0.5);
  p2 = clamp(p2, vec2(0.5), tilePx - 0.5);
  return textureGrad(t, tileOrigin + p2 / texSize, dFdx(gradUv), dFdy(gradUv));
}
// Snap a world position to the 40 px/m art grid (for procedural pixel detail)
vec2 artPix(vec2 p){ return floor(p * 40.0); }
`;

// ---------------------------------------------------------------------------
// Global atmospheric fog: exponential distance fog + height fog pooling in low ground.
// Replaces three's fog chunks for every built-in material, so reflections & transparents match.
// ---------------------------------------------------------------------------
export const FOG = {
  color: new THREE.Color(0.105, 0.092, 0.1),
  density: 0.012,
  heightDensity: 0.04,
  heightFalloff: 0.55,
  heightBase: -0.6,
};

export const GLSL_FOG_FN = /* glsl */ `
uniform vec3 fogColor;
uniform float fogDensity;
vec3 fogTint(vec3 base, vec3 dir, float f){
  // warm haze close by, a slightly cooler lavender in the far distance (aerial perspective)
  float up = clamp(dir.y * 4.0, 0.0, 1.0);
  vec3 c = base * mix(vec3(1.1, 1.0, 0.88), vec3(0.9, 0.92, 1.1), smoothstep(0.45, 1.0, f));
  return c * mix(1.0, 0.85, up);
}
float fogAmount(vec3 camPos, vec3 wpos){
  vec3 rd = wpos - camPos;
  float dist = length(rd);
  rd /= max(dist, 1e-4);
  // distance fog starts a little away from the camera so the play area stays crisp
  float d = max(dist - 9.0, 0.0);
  float fd = 1.0 - exp(-fogDensity * d * (1.0 + d * 0.012));
  // analytic height fog (Quilez) - thick in valleys, thin on high ground
  float b = ${FOG.heightFalloff.toFixed(3)};
  float a = ${FOG.heightDensity.toFixed(3)};
  float oy = camPos.y - (${FOG.heightBase.toFixed(3)});
  float ry = abs(rd.y) < 1e-3 ? 1e-3 : rd.y;
  float fh = a * exp(-oy * b) * (1.0 - exp(-d * ry * b)) / ry;
  fh = 1.0 - exp(-max(fh, 0.0));
  return clamp(1.0 - (1.0 - fd) * (1.0 - fh), 0.0, 1.0);
}
`;

export function installFogChunks() {
  THREE.ShaderChunk.fog_pars_vertex = `
#ifdef USE_FOG
  varying vec3 vFogWorld;
#endif`;
  THREE.ShaderChunk.fog_vertex = `
#ifdef USE_FOG
  {
    vec4 fw = vec4(transformed, 1.0);
    #ifdef USE_INSTANCING
      fw = instanceMatrix * fw;
    #endif
    vFogWorld = (modelMatrix * fw).xyz;
  }
#endif`;
  THREE.ShaderChunk.fog_pars_fragment = `
#ifdef USE_FOG
  varying vec3 vFogWorld;
  ${GLSL_FOG_FN}
#endif`;
  THREE.ShaderChunk.fog_fragment = `
#ifdef USE_FOG
  {
    float fogF = fogAmount(cameraPosition, vFogWorld);
    #ifdef FOG_ADDITIVE
      gl_FragColor.rgb *= (1.0 - fogF);
    #else
      gl_FragColor.rgb = mix(gl_FragColor.rgb, fogTint(fogColor, normalize(vFogWorld - cameraPosition), fogF), fogF);
    #endif
  }
#endif`;
}

// ---------------------------------------------------------------------------
// "Emitter GI": cheap indirect light. Every emissive strip / window / lamp and every real light
// contributes a soft, wrap-around diffuse term (no hard N.L cut-off) so neon and lamp colours
// bleed onto nearby ground and walls, like one bounce of indirect light.
// ---------------------------------------------------------------------------
export const MAX_EMITTERS = 40;
export const GI = {
  uEmA: { value: Array.from({ length: MAX_EMITTERS }, () => new THREE.Vector4()) }, // segment start xyz, radius
  uEmB: { value: Array.from({ length: MAX_EMITTERS }, () => new THREE.Vector4()) }, // segment end xyz, wrap
  uEmC: { value: Array.from({ length: MAX_EMITTERS }, () => new THREE.Vector3()) }, // colour * strength
  uEmN: { value: 0 },
  uTime: { value: 0 },
};

export const GLSL_GI = /* glsl */ `
uniform vec4 uEmA[${MAX_EMITTERS}];
uniform vec4 uEmB[${MAX_EMITTERS}];
uniform vec3 uEmC[${MAX_EMITTERS}];
uniform int uEmN;
uniform float uTime;
vec3 emitterGI(vec3 p, vec3 n){
  vec3 acc = vec3(0.0);
  for(int i = 0; i < ${MAX_EMITTERS}; i++){
    if(i >= uEmN) break;
    vec3 a = uEmA[i].xyz, b = uEmB[i].xyz;
    vec3 ab = b - a;
    float t = clamp(dot(p - a, ab) / max(dot(ab, ab), 1e-5), 0.0, 1.0);
    vec3 q = a + ab * t;
    vec3 l = q - p;
    float d = length(l);
    float r = uEmA[i].w;
    if(d > r) continue;
    l /= max(d, 1e-4);
    float wrap = uEmB[i].w;
    float ndl = clamp((dot(n, l) + wrap) / (1.0 + wrap), 0.0, 1.0);
    float x = d / r;
    float win = (1.0 - x*x); win *= win;
    acc += uEmC[i] * ndl * win / (1.0 + d*d*1.6);
  }
  return acc;
}
`;

export function setEmitters(list) {
  GI.uEmN.value = Math.min(list.length, MAX_EMITTERS);
  list.slice(0, MAX_EMITTERS).forEach((e, i) => {
    GI.uEmA.value[i].set(e.a.x, e.a.y, e.a.z, e.radius);
    GI.uEmB.value[i].set(e.b.x, e.b.y, e.b.z, e.wrap ?? 0.6);
    GI.uEmC.value[i].set(e.color.r * e.strength, e.color.g * e.strength, e.color.b * e.strength);
  });
}
