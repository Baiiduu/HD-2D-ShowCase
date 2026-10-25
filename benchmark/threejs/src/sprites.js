import * as THREE from 'three';
import { patchMaterial } from './materials.js';
import { loadPixelTex } from './materials.js';

// Y-axis billboard character sprites (64x64 px -> 1.5 m), pixel-AA sampled, lit by the scene.
export function makeCharacter(url, renderer) {
  const tex = loadPixelTex(url, renderer, { repeat: false });
  const geo = new THREE.PlaneGeometry(1.5, 1.5);
  // normals tilted upward so overhead lamps light the sprite's face as well as the moon
  const n = geo.attributes.normal;
  const v = new THREE.Vector3(0, 0.55, 1).normalize();
  for (let i = 0; i < n.count; i++) n.setXYZ(i, v.x, v.y, v.z);
  const mat = new THREE.MeshStandardMaterial({
    map: tex, alphaTest: 0.5, alphaToCoverage: true, roughness: 0.9, metalness: 0, side: THREE.DoubleSide,
  });
  const uFlip = { value: 0 };
  patchMaterial(mat, {
    key: 'sprite',
    uniforms: { uFlip },
    fragHead: 'uniform float uFlip;',
    frag: `
{
  vec2 suv = vMapUv;
  if (uFlip > 0.5) suv.x = 1.0 - suv.x;
  vec4 s = texPixel(map, suv, vec2(64.0));
  diffuseColor = vec4(diffuse, opacity) * s;
}`,
    emissive: `totalEmissiveRadiance += diffuseColor.rgb * 0.16;`,
    gi: 1.2,
  });
  const mesh = new THREE.Mesh(geo, mat);
  mesh.castShadow = true;
  mesh.receiveShadow = true;
  mesh.userData.flip = uFlip;
  // dedicated depth material so shadows respect the sprite alpha
  mesh.customDepthMaterial = new THREE.MeshDepthMaterial({ depthPacking: THREE.RGBADepthPacking, map: tex, alphaTest: 0.5 });
  mesh.customDistanceMaterial = new THREE.MeshDistanceMaterial({ map: tex, alphaTest: 0.5 });
  return mesh;
}

// Soft contact shadow / AO blob under a character
let blobMat = null;
export function makeBlob() {
  if (!blobMat) {
    blobMat = new THREE.ShaderMaterial({
      transparent: true, depthWrite: false,
      polygonOffset: true, polygonOffsetFactor: -2, polygonOffsetUnits: -2,
      vertexShader: `varying vec2 vUv; void main(){ vUv = uv; gl_Position = projectionMatrix * modelViewMatrix * vec4(position,1.0); }`,
      fragmentShader: `varying vec2 vUv; void main(){ vec2 d = (vUv - 0.5) * 2.0; float r = dot(d, d);
        float a = exp(-r * 3.2) * 0.62 * smoothstep(1.0, 0.6, r); gl_FragColor = vec4(0.0, 0.0, 0.0, a); }`,
    });
  }
  const m = new THREE.Mesh(new THREE.PlaneGeometry(0.85, 0.42), blobMat);
  m.rotation.x = -Math.PI / 2;
  m.renderOrder = 1;
  return m;
}
