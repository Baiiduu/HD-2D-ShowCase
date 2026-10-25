import * as THREE from 'three';
import { World } from './layout.js';
import { installFogChunks, FOG, GI, setEmitters } from './shaderlib.js';
import { loadPixelTex, AOB } from './materials.js';
import { buildTerrain } from './terrain.js';
import { buildProps, buildBridges } from './props.js';
import { buildWater } from './water.js';
import { buildLights, updateShadowAssignment } from './lights.js';
import { makeCharacter, makeBlob } from './sprites.js';
import { makeFireflies, makeWaterfallMist, makeDust, PSCALE } from './particles.js';
import { makeSky, makeMountains } from './sky.js';
import { PlanarReflection, LAYER_REFLECTIVE, LAYER_WATER } from './reflection.js';
import { REFLW } from './materials.js';
import { buildPost } from './post.js';

installFogChunks();

// resolves once every texture queued on the default loading manager has arrived
let texturesLoaded = false;
THREE.DefaultLoadingManager.onLoad = () => { texturesLoaded = true; };

const params = new URLSearchParams(location.search);
const SHOTS = [
  { file: 'shot_1_crossroads.png', x: 0, z: 1.4 },
  { file: 'shot_2_city_lamp.png', x: -2.4, z: -0.6 },
  { file: 'shot_3_wild.png', x: 6, z: 3 },
  { file: 'shot_4_waterfall.png', x: 22.4, z: 2.5 },
  { file: 'shot_5_highland.png', x: 28, z: -4.8 },
];
const shotMode = params.has('shot') || params.has('shots');
const FIXED_W = 1280, FIXED_H = 800;

const CAM = { fov: 25, pitch: 10, dist: 11 };

async function main() {
  const json = await (await fetch('layout/scene_layout.json')).json();
  const world = new World(json);

  const renderer = new THREE.WebGLRenderer({ antialias: false, powerPreference: 'high-performance', preserveDrawingBuffer: shotMode });
  renderer.setPixelRatio(shotMode ? 1 : Math.min(window.devicePixelRatio, 1.5));
  renderer.outputColorSpace = THREE.SRGBColorSpace;
  renderer.toneMapping = THREE.NoToneMapping;
  renderer.shadowMap.enabled = true;
  renderer.shadowMap.type = THREE.PCFSoftShadowMap;
  document.body.appendChild(renderer.domElement);

  const tex = {
    city: loadPixelTex('textures/ground_city_cobblestone.png', renderer),
    cyber: loadPixelTex('textures/ground_cyber_metal_panel.png', renderer),
    slate: loadPixelTex('textures/ground_cultivation_slate.png', renderer),
    grass: loadPixelTex('textures/ground_wild_grass.png', renderer),
    cliff: loadPixelTex('textures/cliff_rock_strata.png', renderer),
    water: loadPixelTex('textures/water_shallow.png', renderer),
    wood: loadPixelTex('textures/wood_planks.png', renderer),
    road: loadPixelTex('tilesets/road_cobblestone_dualgrid.png', renderer, { repeat: false, flipY: false }),
    dirt: loadPixelTex('tilesets/dirt_dualgrid.png', renderer, { repeat: false, flipY: false }),
  };

  const scene = new THREE.Scene();
  scene.fog = new THREE.FogExp2(FOG.color.getHex(), FOG.density);
  scene.fog.color.copy(FOG.color);
  scene.background = FOG.color.clone();

  const camera = new THREE.PerspectiveCamera(CAM.fov, FIXED_W / FIXED_H, 0.3, 1500);
  camera.layers.enable(LAYER_REFLECTIVE);
  camera.layers.enable(LAYER_WATER);

  // ---- world ----
  const terrain = buildTerrain(world, tex);
  terrain.topMesh.layers.set(LAYER_REFLECTIVE);
  scene.add(terrain.topMesh, terrain.wallMesh, terrain.far);
  if (params.has('debugFar')) terrain.far.material = new THREE.MeshBasicMaterial({ color: 0xff0000 });
  if (params.has('debugWall')) terrain.wallMesh.material = new THREE.MeshBasicMaterial({ color: 0x00ff00 });
  terrain.far.layers.set(LAYER_REFLECTIVE);

  const props = buildProps(world, tex);
  scene.add(props.group);
  scene.add(buildBridges(world, tex));

  const water = buildWater(world, tex, terrain.cellTex);
  water.mesh.layers.set(LAYER_WATER);
  scene.add(water.mesh, water.falls);

  const lights = buildLights(world, scene);
  scene.add(lights.group);

  // moon (key light) + hemisphere ambient
  const moonJ = json.moon;
  const moonDir = new THREE.Vector3(...moonJ.direction_light_travels).normalize();
  const moon = new THREE.DirectionalLight(new THREE.Color().setRGB(...moonJ.color, THREE.SRGBColorSpace), moonJ.energy * 2.2);
  moon.castShadow = true;
  moon.shadow.mapSize.set(4096, 4096);
  const sc = moon.shadow.camera;
  sc.left = -30; sc.right = 30; sc.top = 30; sc.bottom = -30; sc.near = 1; sc.far = 120;
  moon.shadow.bias = -0.0006;
  moon.shadow.normalBias = 0.035;
  moon.shadow.radius = 3;
  scene.add(moon, moon.target);
  const hemi = new THREE.HemisphereLight(new THREE.Color(0.55, 0.6, 0.78), new THREE.Color(0.36, 0.28, 0.2), 0.7);
  scene.add(hemi);

  // GI emitters & AO boxes
  setEmitters([...props.emitters, ...lights.emitters]);
  AOB.uAoN.value = Math.min(props.aoBoxes.length, AOB.uAoBox.value.length);
  props.aoBoxes.forEach((b, i) => {
    if (i >= AOB.uAoBox.value.length) return;
    AOB.uAoBox.value[i].set(b.x0, b.z0, b.x1, b.z1);
    AOB.uAoBoxY.value[i].set(b.y0, b.y1);
  });

  // ---- characters ----
  const sprites = [];
  let player = null;
  for (const s of json.sprites) {
    const m = makeCharacter(s.texture, renderer);
    m.position.set(...s.center_position);
    scene.add(m);
    const blob = makeBlob();
    scene.add(blob);
    const isPlayer = s.name === 'Player/Sprite';
    const rec = { mesh: m, blob, isPlayer };
    sprites.push(rec);
    if (isPlayer) player = rec;
    else world.colliders.push({ type: 'circle', x: s.center_position[0], z: s.center_position[2], r: 0.28 });
  }

  // ---- particles & atmosphere ----
  for (const p of json.particles) scene.add(makeFireflies(world, p.center, p.amount));
  const wfMist = json.fog_volumes.find((f) => /Waterfall/.test(f.name));
  if (wfMist) scene.add(makeWaterfallMist(wfMist, water.fallInfo));
  const dustSrc = json.lights.filter((l) => l.type === 'OmniLight3D' && /StreetLight|Lantern/.test(l.name))
    .map((l) => ({ p: new THREE.Vector3(...l.position), c: new THREE.Color(...l.color), n: /Street/.test(l.name) ? 22 : 8, r: /Street/.test(l.name) ? 1.1 : 0.7, h: /Street/.test(l.name) ? 2.3 : 1.0 }));
  scene.add(makeDust(dustSrc));
  scene.add(makeSky());
  scene.add(makeMountains(new THREE.Vector3(12, 0, -10)));

  // ---- rendering helpers ----
  const reflection = new PlanarReflection(renderer, 0.5);
  const waterRefl = [
    new PlanarReflection(renderer, 0.4, world.waterY(-1), REFLW[0], [0, LAYER_REFLECTIVE]),
    new PlanarReflection(renderer, 0.4, world.waterY(0), REFLW[1], [0, LAYER_REFLECTIVE]),
  ];
  const post = buildPost(renderer, scene, camera, lights.scatter);

  function resize() {
    const w = shotMode ? FIXED_W : window.innerWidth;
    const h = shotMode ? FIXED_H : window.innerHeight;
    renderer.setSize(w, h);
    camera.aspect = w / h;
    camera.updateProjectionMatrix();
    const pr = renderer.getPixelRatio();
    post.setSize(w, h);
    reflection.setSize(w * pr, h * pr);
    for (const r of waterRefl) r.setSize(w * pr, h * pr);
    PSCALE.value = (h * pr) / (2 * Math.tan(THREE.MathUtils.degToRad(CAM.fov / 2)));
  }
  window.addEventListener('resize', resize);
  resize();

  // ---- player & camera ----
  const P = { x: json.player.spawn[0], z: json.player.spawn[2], y: world.standHeight(json.player.spawn[0], json.player.spawn[2]) ?? 0.02, face: 1, walk: 0 };
  const speed = json.player.speed || 4;
  const camTarget = new THREE.Vector3(P.x, P.y + 0.75, P.z);
  const keys = new Set();
  window.addEventListener('keydown', (e) => { keys.add(e.code); if (e.code.startsWith('Arrow')) e.preventDefault(); });
  window.addEventListener('keyup', (e) => keys.delete(e.code));
  window.addEventListener('blur', () => keys.clear());

  function placePlayer(x, z) {
    P.x = x; P.z = z;
    P.y = world.standHeight(x, z) ?? world.terrainHeight(x, z);
    camTarget.set(P.x, P.y + 0.75, P.z);
    clampTarget(camTarget);
  }
  function clampTarget(t) {
    t.x = THREE.MathUtils.clamp(t.x, world.minX + 2.5, world.maxX - 2.5);
    t.z = THREE.MathUtils.clamp(t.z, world.minZ + 3.0, world.maxZ - 1.0);
  }

  function updatePlayer(dt) {
    let mx = 0, mz = 0;
    if (keys.has('KeyW') || keys.has('ArrowUp')) mz -= 1;
    if (keys.has('KeyS') || keys.has('ArrowDown')) mz += 1;
    if (keys.has('KeyA') || keys.has('ArrowLeft')) mx -= 1;
    if (keys.has('KeyD') || keys.has('ArrowRight')) mx += 1;
    const moving = mx !== 0 || mz !== 0;
    if (moving) {
      const l = Math.hypot(mx, mz);
      const step = speed * dt / l;
      const nx = P.x + mx * step;
      let y = world.canStand(nx, P.z, P.y);
      if (y !== null) { P.x = nx; P.y = y; }
      const nz = P.z + mz * step;
      y = world.canStand(P.x, nz, P.y);
      if (y !== null) { P.z = nz; P.y = y; }
      if (mx !== 0) P.face = mx;
      P.walk += dt * 9;
    } else {
      P.walk = 0;
    }
  }

  function updateCamera(dt, snap) {
    const want = new THREE.Vector3(P.x, P.y + 0.75, P.z);
    const d = want.clone().sub(camTarget);
    const dead = 0.18;
    const len = d.length();
    if (snap) camTarget.copy(want);
    else if (len > dead) camTarget.add(d.multiplyScalar((1 - dead / len) * (1 - Math.exp(-dt * 6))));
    clampTarget(camTarget);
    const pitch = THREE.MathUtils.degToRad(CAM.pitch);
    camera.position.set(camTarget.x, camTarget.y + Math.sin(pitch) * CAM.dist, camTarget.z + Math.cos(pitch) * CAM.dist);
    camera.lookAt(camTarget);
    camera.updateMatrixWorld();
  }

  function updateMoonShadow() {
    // shadow frustum follows the view (centred a bit north of the player), snapped to texels
    const c = new THREE.Vector3(camTarget.x, 0, camTarget.z - 9);
    const size = (sc.right - sc.left) / moon.shadow.mapSize.x;
    const lightRot = new THREE.Matrix4().lookAt(new THREE.Vector3(), moonDir, new THREE.Vector3(0, 1, 0));
    const inv = lightRot.clone().invert();
    const lc = c.clone().applyMatrix4(inv);
    lc.x = Math.round(lc.x / size) * size; lc.y = Math.round(lc.y / size) * size;
    c.copy(lc.applyMatrix4(lightRot));
    moon.target.position.copy(c);
    moon.position.copy(c).addScaledVector(moonDir, -50);
    moon.target.updateMatrixWorld();
  }

  function updateSprites(t) {
    const yaw = Math.atan2(camera.position.x - camTarget.x, camera.position.z - camTarget.z);
    for (const s of sprites) {
      if (s.isPlayer) {
        const bob = P.walk > 0 ? Math.abs(Math.sin(P.walk)) * 0.045 : 0;
        s.mesh.position.set(P.x, P.y + 0.824 + bob, P.z);
        s.mesh.userData.flip.value = P.face < 0 ? 1 : 0;
        const sq = P.walk > 0 ? 1 + Math.sin(P.walk * 2) * 0.02 : 1;
        s.mesh.scale.set(1 / Math.sqrt(sq), sq, 1);
      } else {
        // idle breathing
        s.mesh.scale.y = 1 + Math.sin(t * 2 + s.mesh.position.x) * 0.008;
      }
      s.mesh.rotation.set(0, yaw, 0);
      const gx = s.mesh.position.x, gz = s.mesh.position.z;
      const gy = s.isPlayer ? P.y : world.standHeight(gx, gz) ?? world.terrainHeight(gx, gz);
      s.blob.position.set(gx, gy + 0.012, gz + 0.02);
    }
  }

  // ---- loop ----
  const clock = new THREE.Clock();
  let t = 0, frames = 0, fpsAcc = 0, fpsFrames = 0;
  window.__fps = 0;
  let snapCam = true;

  function frame() {
    const dt = Math.min(clock.getDelta(), 1 / 20);
    t += dt;
    GI.uTime.value = t;
    if (!shotMode) updatePlayer(dt);
    updateCamera(dt, snapCam);
    snapCam = false;
    updateSprites(t);
    updateMoonShadow();
    updateShadowAssignment(lights.points, new THREE.Vector3(P.x, P.y, P.z));
    renderer.shadowMap.needsUpdate = true;
    reflection.render(scene, camera);
    // water mirrors only when the river is in view (it runs along x = 22..24)
    if (Math.abs(camTarget.x - 23) < 13) for (const r of waterRefl) r.render(scene, camera);
    if (params.has('nopost')) renderer.render(scene, camera); else post.render(dt);
    frames++;
    fpsAcc += dt; fpsFrames++;
    if (fpsAcc > 1) { window.__fps = fpsFrames / fpsAcc; fpsAcc = 0; fpsFrames = 0; }
  }

  // ---- screenshot mode ----
  async function waitFrames(n) {
    for (let i = 0; i < n; i++) { frame(); await new Promise((r) => requestAnimationFrame(r)); }
  }
  async function captureAll(list, save) {
    for (const s of list) {
      placePlayer(s.x, s.z);
      snapCam = true;
      await waitFrames(150);
      const url = renderer.domElement.toDataURL('image/png');
      if (save) await fetch('/__save-shot?name=' + encodeURIComponent(s.file), { method: 'POST', body: url });
      window.__lastShot = url;
    }
  }

  if (shotMode) {
    renderer.shadowMap.autoUpdate = true;
    // wait for textures to load
    for (let i = 0; i < 200 && !texturesLoaded; i++) await new Promise((r) => setTimeout(r, 50));
    const which = params.get('shot') ?? params.get('shots');
    let list = SHOTS;
    if (params.has('x')) list = [{ file: params.get('name') || 'shot_custom.png', x: +params.get('x'), z: +params.get('z') }];
    else if (which && which !== 'all') list = [SHOTS[+which - 1]];
    window.__shotList = list;
    window.__captureIndex = async (i) => { await captureAll([list[i]], false); return window.__lastShot; };
    window.__ready = true;
    if (params.get('save') !== '0' && !params.has('external')) {
      await captureAll(list, true);
      window.__done = true;
    }
    // keep rendering so the page stays live for inspection
    const loop = () => { frame(); requestAnimationFrame(loop); };
    if (params.has('live')) loop();
  } else {
    const loop = () => { frame(); requestAnimationFrame(loop); };
    loop();
  }
  window.__placePlayer = placePlayer;
  window.__scene = scene; window.__renderer = renderer; window.__P = P; window.__world = world;
}

main().catch((e) => { console.error(e); document.body.insertAdjacentHTML('beforeend', `<pre style="color:#f88">${e.stack}</pre>`); });
