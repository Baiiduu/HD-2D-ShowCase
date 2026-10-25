import * as THREE from 'three';
import { REFL } from './materials.js';

// Planar reflection of the scene about the ground plane (y = 0.02). Wet ground and water
// sample it with roughness-driven blur (mip chain), distortion and Fresnel.
export const LAYER_REFLECTIVE = 1; // ground tops: hidden from the ground mirror only
export const LAYER_WATER = 2;      // water: hidden from every mirror

export class PlanarReflection {
  constructor(renderer, scale = 0.5, y = 0.02, uniforms = REFL, layers = [0]) {
    this.renderer = renderer;
    this.uniforms = uniforms;
    this.scale = scale;
    this.rt = new THREE.WebGLRenderTarget(4, 4, {
      type: THREE.HalfFloatType, samples: 0,
      minFilter: THREE.LinearMipmapLinearFilter, magFilter: THREE.LinearFilter, generateMipmaps: true,
    });
    this.cam = new THREE.PerspectiveCamera();
    this.cam.layers.disableAll();
    for (const l of layers) this.cam.layers.enable(l);
    this.planeY = y;
    uniforms.uReflTex.value = this.rt.texture;
    if (uniforms.uReflY) uniforms.uReflY.value = this.planeY;
    REFL.uReflOn.value = 1;
  }
  setSize(w, h) {
    this.rt.setSize(Math.max(2, Math.floor(w * this.scale)), Math.max(2, Math.floor(h * this.scale)));
  }
  render(scene, camera) {
    const c = this.cam;
    const y = this.planeY;
    camera.updateMatrixWorld();
    const camPos = new THREE.Vector3().setFromMatrixPosition(camera.matrixWorld);
    const dir = new THREE.Vector3(0, 0, -1).applyQuaternion(camera.quaternion);
    const target = camPos.clone().add(dir);
    c.position.set(camPos.x, 2 * y - camPos.y, camPos.z);
    c.up.set(0, -1, 0).applyQuaternion(new THREE.Quaternion()); // mirrored up
    const up = new THREE.Vector3(0, 1, 0).applyQuaternion(camera.quaternion);
    c.up.set(up.x, -up.y, up.z);
    c.lookAt(target.x, 2 * y - target.y, target.z);
    c.fov = camera.fov; c.aspect = camera.aspect; c.near = camera.near; c.far = camera.far;
    c.updateProjectionMatrix();
    c.updateMatrixWorld();
    // oblique near plane = reflection plane (clip everything under the ground)
    const plane = new THREE.Plane(new THREE.Vector3(0, 1, 0), -(y + 0.005));
    plane.applyMatrix4(c.matrixWorldInverse);
    const clip = new THREE.Vector4(plane.normal.x, plane.normal.y, plane.normal.z, plane.constant);
    const P = c.projectionMatrix;
    const q = new THREE.Vector4(
      (Math.sign(clip.x) + P.elements[8]) / P.elements[0],
      (Math.sign(clip.y) + P.elements[9]) / P.elements[5],
      -1.0,
      (1.0 + P.elements[10]) / P.elements[14]);
    clip.multiplyScalar(2.0 / clip.dot(q));
    P.elements[2] = clip.x; P.elements[6] = clip.y; P.elements[10] = clip.z + 1.0; P.elements[14] = clip.w;
    c.projectionMatrixInverse.copy(P).invert();
    // texture matrix: world -> reflection uv
    this.uniforms.uReflMat.value.set(0.5, 0, 0, 0.5, 0, 0.5, 0, 0.5, 0, 0, 0.5, 0.5, 0, 0, 0, 1)
      .multiply(P).multiply(c.matrixWorldInverse);

    const r = this.renderer;
    const prevRT = r.getRenderTarget();
    const prevAuto = r.shadowMap.autoUpdate;
    r.shadowMap.autoUpdate = false;
    REFL.uReflOn.value = 0;
    r.setRenderTarget(this.rt);
    r.clear();
    r.render(scene, c);
    r.setRenderTarget(prevRT);
    REFL.uReflOn.value = 1;
    r.shadowMap.autoUpdate = prevAuto;
  }
}
