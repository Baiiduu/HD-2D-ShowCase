import * as THREE from 'three';
import {
  EffectComposer, RenderPass, EffectPass, BloomEffect, VignetteEffect, ToneMappingEffect, ToneMappingMode,
  DepthOfFieldEffect, Effect, EffectAttribute, BlendFunction, SMAAEffect,
} from 'postprocessing';
import { N8AOPostPass } from 'n8ao';
import { FOG } from './shaderlib.js';

const MAXL = 16;

// Analytic single-scattering of every lamp through the night air (closed-form integral of
// 1/d^2 along each view ray, clipped by scene depth) -> volumetric halos that are occluded
// correctly by geometry in front of the lamp.
class ScatterEffect extends Effect {
  constructor(camera, lights) {
    super('ScatterEffect', /* glsl */`
      uniform vec3 uLP[${MAXL}];
      uniform vec4 uLC[${MAXL}];
      uniform int uN;
      uniform mat4 uInvProj;
      uniform mat4 uCamWorld;
      uniform vec3 uCamPos;
      uniform float uStrength;
      uniform float uExposure;
      void mainImage(const in vec4 inputColor, const in vec2 uv, const in float depth, out vec4 outputColor){
        vec4 ndc = vec4(uv * 2.0 - 1.0, depth * 2.0 - 1.0, 1.0);
        vec4 vp = uInvProj * ndc; vp /= vp.w;
        vec3 wp = (uCamWorld * vec4(vp.xyz, 1.0)).xyz;
        vec3 rd = wp - uCamPos;
        float L = length(rd);
        rd /= max(L, 1e-4);
        if (depth >= 0.99999) L = 200.0;
        vec3 acc = vec3(0.0);
        for (int i = 0; i < ${MAXL}; i++) {
          if (i >= uN) break;
          vec3 m = uLP[i] - uCamPos;
          float tc = dot(m, rd);
          float h2 = max(dot(m, m) - tc * tc, 0.0);
          float h = sqrt(h2 + 0.0025);
          float I = (atan((L - tc) / h) - atan(-tc / h)) / h;
          float range = uLC[i].w;
          float win = exp(-h / (range * 0.22));
          acc += uLC[i].rgb * I * win;
        }
        outputColor = vec4((inputColor.rgb + acc * uStrength) * uExposure, inputColor.a);
      }`, {
      attributes: EffectAttribute.DEPTH,
      blendFunction: BlendFunction.NORMAL,
      uniforms: new Map([
        ['uLP', new THREE.Uniform(Array.from({ length: MAXL }, () => new THREE.Vector3()))],
        ['uLC', new THREE.Uniform(Array.from({ length: MAXL }, () => new THREE.Vector4()))],
        ['uN', new THREE.Uniform(0)],
        ['uInvProj', new THREE.Uniform(new THREE.Matrix4())],
        ['uCamWorld', new THREE.Uniform(new THREE.Matrix4())],
        ['uCamPos', new THREE.Uniform(new THREE.Vector3())],
        ['uStrength', new THREE.Uniform(0.022)],
        ['uExposure', new THREE.Uniform(1.25)],
      ]),
    });
    this.camera = camera;
    const n = Math.min(lights.length, MAXL);
    this.uniforms.get('uN').value = n;
    lights.slice(0, n).forEach((l, i) => {
      this.uniforms.get('uLP').value[i].copy(l.pos);
      this.uniforms.get('uLC').value[i].set(l.color.r * l.intensity * l.mist, l.color.g * l.intensity * l.mist, l.color.b * l.intensity * l.mist, l.range);
    });
  }
  update() {
    const c = this.camera;
    this.uniforms.get('uInvProj').value.copy(c.projectionMatrixInverse);
    this.uniforms.get('uCamWorld').value.copy(c.matrixWorld);
    this.uniforms.get('uCamPos').value.setFromMatrixPosition(c.matrixWorld);
  }
}

// Miniature-style depth of field: strong blur on the near foreground, gentle blur far away,
// a wide sharp band around the player. Golden-angle gather with a dilated near CoC so blurred
// foreground objects soften their own silhouettes.
class TiltDOFEffect extends Effect {
  constructor() {
    super('TiltDOFEffect', /* glsl */`
      uniform float uNearSharp, uNearBlur, uFarSharp, uFarBlur, uFarMax, uMaxR;
      float viewDist(vec2 uv){ return -getViewZ(readDepth(uv)); }
      float nearCoc(float d){ return smoothstep(uNearSharp, uNearBlur, d); }
      float farCoc(float d){ return smoothstep(uFarSharp, uFarBlur, d) * uFarMax; }
      void mainImage(const in vec4 inputColor, const in vec2 uv, const in float depth, out vec4 outputColor){
        float d0 = -getViewZ(depth);
        float cn = nearCoc(d0);
        // dilate near CoC from the neighbourhood
        for (int i = 0; i < 8; i++) {
          float a = float(i) * 0.785398;
          vec2 o = vec2(cos(a), sin(a)) * uMaxR * texelSize;
          cn = max(cn, nearCoc(viewDist(uv + o)) * 0.85);
        }
        float coc = max(cn, farCoc(d0));
        if (coc < 0.02) { outputColor = inputColor; return; }
        float R = coc * uMaxR;
        vec3 acc = inputColor.rgb; float ws = 1.0;
        for (int i = 0; i < 28; i++) {
          float fi = float(i) + 0.5;
          float r = sqrt(fi / 28.0) * R;
          float a = fi * 2.39996;
          vec2 suv = uv + vec2(cos(a), sin(a)) * r * texelSize;
          vec3 c = texture2D(inputBuffer, suv).rgb;
          float sd = viewDist(suv);
          // in-focus samples behind a far-blurred pixel do not leak in, near samples always may
          float sc = max(nearCoc(sd), farCoc(sd));
          float w = (sd < d0 - 0.5) ? 1.0 : clamp(sc * 1.5 + 0.15, 0.0, 1.0);
          acc += c * w; ws += w;
        }
        outputColor = vec4(acc / ws, inputColor.a);
      }`, {
      attributes: EffectAttribute.DEPTH | EffectAttribute.CONVOLUTION,
      uniforms: new Map([
        ['uNearSharp', new THREE.Uniform(7.5)], ['uNearBlur', new THREE.Uniform(3.6)],
        ['uFarSharp', new THREE.Uniform(17.0)], ['uFarBlur', new THREE.Uniform(70.0)],
        ['uFarMax', new THREE.Uniform(0.4)], ['uMaxR', new THREE.Uniform(8.0)],
      ]),
    });
  }
}

// Final colour grade: warm highlights / slightly cool shadows, gentle contrast & saturation.
class GradeEffect extends Effect {
  constructor() {
    super('GradeEffect', /* glsl */`
      uniform float uSat;
      void mainImage(const in vec4 inputColor, const in vec2 uv, out vec4 outputColor){
        vec3 c = max(inputColor.rgb, 0.0);
        float l = dot(c, vec3(0.2126, 0.7152, 0.0722));
        vec3 shadowTint = vec3(0.93, 0.98, 1.06);
        vec3 highTint = vec3(1.06, 1.0, 0.9);
        c *= mix(shadowTint, highTint, smoothstep(0.04, 0.55, l));
        c = mix(vec3(l), c, uSat);
        c = c * 0.98 + vec3(0.010, 0.009, 0.012);
        // soft S-curve
        c = mix(c, c * c * (3.0 - 2.0 * c), 0.18);
        outputColor = vec4(c, inputColor.a);
      }`, { uniforms: new Map([['uSat', new THREE.Uniform(1.06)]]) });
  }
}

export function buildPost(renderer, scene, camera, scatterLights) {
  const composer = new EffectComposer(renderer, { frameBufferType: THREE.HalfFloatType, multisampling: 4 });
  composer.addPass(new RenderPass(scene, camera));

  const ao = new N8AOPostPass(scene, camera, 1280, 800);
  ao.configuration.aoRadius = 1.4;
  ao.configuration.distanceFalloff = 0.8;
  ao.configuration.intensity = 2.6;
  ao.configuration.aoSamples = 16;
  ao.configuration.denoiseSamples = 8;
  ao.configuration.denoiseRadius = 8;
  ao.configuration.halfRes = true;
  ao.configuration.depthAwareUpsampling = true;
  ao.configuration.gammaCorrection = false;
  ao.configuration.color = new THREE.Color(0, 0, 0);
  ao.configuration.transparencyAware = false;
  composer.addPass(ao);

  const scatter = new ScatterEffect(camera, scatterLights);
  composer.addPass(new EffectPass(camera, scatter));

  const dof = new TiltDOFEffect();
  composer.addPass(new EffectPass(camera, dof));

  const bloom = new BloomEffect({
    mipmapBlur: true, luminanceThreshold: 0.95, luminanceSmoothing: 0.35, intensity: 0.85, radius: 0.72, levels: 7,
  });
  const tone = new ToneMappingEffect({ mode: ToneMappingMode.ACES_FILMIC });
  const grade = new GradeEffect();
  const vignette = new VignetteEffect({ offset: 0.32, darkness: 0.5 });
  composer.addPass(new EffectPass(camera, bloom, tone, grade, vignette));

  return {
    composer, ao, scatter, dof, bloom, tone,
    setSize(w, h) { composer.setSize(w, h); },
    render(dt) { scatter.update(); composer.render(dt); },
  };
}
