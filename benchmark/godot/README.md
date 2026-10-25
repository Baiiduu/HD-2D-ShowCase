# 四境 · Four Realms (HD-2D, Godot 4.7.2)

A playable HD-2D night scene. Everything (terrain, cliffs, water, bridges, props, lights, particles, backdrop) is generated at runtime from `assets/layout/scene_layout.json`. That file and all textures and sprites are unmodified copies of `D:\Project\godot\games\Asserts`. No other images or models are used. Everything else is procedural (shaders, geometry, particles).

## Running

Engine: `D:\Project\godot\Godot_v4.7.2\Godot_v4.7.2-stable_win64.exe` (Forward+). There are no plugins and no import step for the art: PNGs are loaded directly from `assets/`, which is excluded from the importer by `.gdignore`.

**Play** (from this folder, or open `project.godot` in the editor and press F5):

```
Godot_v4.7.2-stable_win64.exe --path D:\Project\godot\games\benchmark\godot
```

Controls: WASD / arrow keys move the player at 4 m/s. The player can walk up ramps, stand on the highland, tableland, bridges and temple platform. Cliffs, buildings, posts, rails and water block movement.

**Screenshot mode** (no interaction needed; it quits when done):

```
Godot_v4.7.2-stable_win64_console.exe --path D:\Project\godot\games\benchmark\godot -- --screenshots
```

- The window is forced to 1280×800. For each shot the player is teleported to the given (x, z), and the height is taken from the terrain. The camera snaps into place, then the run waits ≥150 frames and ≥3 s so temporal volumetric fog, SDFGI cascades and particles settle before grabbing the frame.
- Output goes to `screenshots/shot_1_crossroads.png … shot_5_highland.png`.
- Extra options:
  - `--shot=x,z,name` captures a custom position.
  - `--fps` also prints a 5-second average FPS at each shot position, with vsync off.
- `run_shots.sh` is a Git-Bash shortcut for the same command.

**Logic test:** `Godot_v4.7.2-stable_win64_console.exe --headless --path . --script res://tests/walk_test.gd` walks the controller through ramps, cliffs, bridges, water, buildings and the temple steps, and prints where it ends up.

## Project layout

| Path | Contents |
|---|---|
| `scripts/main.gd` | Reads the layout. Builds terrain, cliffs, water, waterfalls, bridges, layout meshes, lights, halos, fog volumes, particles, sprites, environment and post-processing. |
| `scripts/terrain_data.gd` | Terrain grid plus queries: ramp direction, corner heights, water surface, bridge deck, walkable height, dual-grid flags. |
| `scripts/player.gd`, `scripts/camera_rig.gd` | Grid-terrain character controller; follow camera with a dead zone. |
| `scripts/backdrop.gd` | Distant scenery: lowland, hills, ridge mountains, forest silhouettes, far village lights, ground-mist sheet. |
| `scripts/screenshot_runner.gd` | Unattended capture and FPS benchmark. |
| `shaders/*.gdshader` | Terrain (biomes + dual-grid), cliff, water, waterfall, props, Y-billboard sprites, halos, fireflies, spray, sky, ground mist, post-processing. |

## Self-assessment

### What is implemented, and how

| Goal | Technique |
|---|---|
| **Pixel crispness** | Every pixel texture goes through a "fat-pixel" sampler (`shaders/pixel.gdshaderinc`): texel cells stay square, and only the border between two texels is anti-aliased over exactly one screen pixel, using `fwidth` with `textureGrad` and box-filtered mipmaps. Magnified texels have hard edges with no blur; minified ones fall back to mipmaps, so there's no shimmer. Sprites use the same sampler plus alpha-scissor, and texture colour is bled into transparent texels before mipmapping to avoid dark fringes. Characters are Y-axis billboards built in the vertex shader; in shadow passes they turn toward the light, so the moon casts a proper silhouette. Sprites are 1.5 m tall (0.0234 m per pixel). |
| **Terrain transitions** | One terrain shader reads a 30×13 data texture (biome, level, overlay, path flags). Road and dirt use the dual-grid exactly as documented: the display cell is offset half a cell, the key is NW·1+SW·2+NE·4+SE·8, and the tile comes from the given table. It is evaluated per fragment in world space with continuous derivatives, so there is no seam at tile borders. Map borders clamp, so roads run off the edge. Bridges continue the path they carry. Biome borders without a road (cyber ↔ grass) get a texel-quantised noisy edge. Road edges get a 2–3 texel drop shadow on the moon-ward side so the cobble road reads as raised. Each texel also gets a bevel normal from its luminance gradient. |
| **Height layers** | Cell tops (including sloped ramps) and every vertical face between a higher and a lower cell are generated, including ramp-side triangles and the map skirt down to level −2. Cliffs use `cliff_rock_strata` tiled along the wall and by world height. They have a ragged grass or stone lip at the crest, a lit rim under it with a thin cast line, darkening toward the foot, and a wet glossy band at the waterline. The ground at the foot of every higher cell and building gets analytic contact occlusion, on top of SSAO. |
| **Key light & shadows** | Moon `DirectionalLight3D` uses the layout's direction, colour and energy, with 2-split PSSM at 4096 and PCSS soft shadows (angular size 1.6°). SSAO adds contact AO. |
| **Light sources** | Every layout light is created with its exact position, colour, energy, range and shadow flag. Spotlights point down. Light housings don't cast shadows, so they don't swallow their own light. Each lamp has an emissive body with a procedural frame, mullions or ribs, a camera-facing additive halo with depth-fade, a volumetric-fog glow, and a pool on the ground from the light itself. Reflections come from SSR on wet surfaces: cobble puddles at roughness 0.03, damp road, glossy metal floor, and the water surface. Lights with no mesh get an air glow; the spirit light also gets an orb and wisps. |
| **Indirect light** | SDFGI with occlusion, plus SSIL. Emissive windows, neon strips and lanterns also feed an analytic "spill" term in the terrain, cliff, water and prop shaders: a window throws a warm patch on the cobbles, and the neon tints the metal floor cyan and magenta. |
| **Atmosphere & depth** | Exponential fog in a cool violet-grey with height fog, and low-density volumetric fog with temporal reprojection. The layout's fog volumes (waterfall mist, street-lamp haze) are ellipsoid `FogVolume`s. Around the map there is a procedural landscape: a lowland with drifting depth-tested ground mist that the map's skirt sinks into, pine silhouettes, rolling hills, ridged mountains, a few twinkling far village lights, and a night sky with blocky stars, thin clouds and a moon glow. Depth-of-field adds a gentle far/near blur, and the post shader softens the top and bottom bands for a tilt-shift miniature feel. |
| **Water** | Opaque, low-roughness stream, so SSR reflects lanterns and lamp posts. It uses two scrolling layers of `water_shallow` sampled crisply and stretched along the flow, with per-texel ripple normals and glints. Analytic bank distance from the data texture drives shallow colour, broken animated foam lace and inner-corner rounding. A churning foam field sits under the waterfall. The waterfall is a curved sheet with an accelerating pixel streak animation, a bright lip and foot, spray particles, and the layout's mist `FogVolume`. Smaller sheets close the stream where it leaves the map. |
| **Accents & post** | GPU fireflies with per-particle blink and turbulence wander (counts and centres from the layout). Bloom (HDR threshold 0.9, mid levels only), filmic tonemapping, and a post shader with gentle saturation, warm-highlight/cool-shadow split toning, a mild contrast curve and a vignette. |
| **Camera & control** | Perspective camera, vertical FOV 25°, pitch 10°, 11 m to a target 0.75 m above the player's feet, from the south. Exponential smoothing with a 0.3 m dead zone, clamped so the view never drifts far off the map. The controller handles ramps, ledges, water, bridge rails, building and post footprints, and 0.3 m steps (temple stairs). The sprite flips to face the walking direction and hops slightly while moving. |

### Shortfalls and deviations (honest)

- **Camera FOV:** `scene_layout.json` lists `fov_vertical_deg: 30`, but the brief requires 25°, so 25° is used.
- **Shot 4 position:** (22.4, 2.5) falls inside water cell (14, 2). As specified, the player is placed there, and "height from terrain" is taken as the water surface, so the player appears to stand in the stream. In normal play, water can't be entered.
- **Sprite height:** Sprites are placed at the layout's x/z. Their height is computed so the drawn feet (3 transparent rows above the bottom of the art) touch the ground. Using the raw layout `center_position.y` would make them float about 7–14 cm.
- **Red lanterns:** Their layout material is warm yellow. The shader tints the paper red-orange with a warm core to match the brief's "红灯笼"; the geometry, position and light are unchanged.
- **Backdrop trees:** Pine silhouettes, hills and village lights are placed only outside the map, at least 7 m beyond its edge. They are treated as 远景 scenery, not props. Inside the map nothing was added beyond the layout. Halos, orbs and wisps are effects, not geometry.
- **Waterfall framing in shot 4:** With the fixed camera, the main waterfall sits 2.4 m behind the lower bridge, whose railings hide its lower half. Its top, foam and spray are visible, but it's less prominent than from an oblique angle.
- **SDFGI** is soft at this scale; most of the visible colour bleed comes from the explicit emissive-spill term, which approximates one bounce rather than computing it.
- **Volumetric fog** is kept thin (0.007) because denser settings showed froxel banding and an over-bright "fog wall" at distance. Light shafts are therefore subtle.
- **DOF on bright sprites:** Godot's built-in DOF slightly squares off very close bright additive sprites, such as the spirit wisps when they are near the camera.
- **Waterfall details:** There's no true refraction, and the water is opaque by design so it gets SSR. The waterfall is alpha-blended, so it doesn't appear in SSR.

### Performance

Measured with `--fps` (vsync off, 1280×800, 5 s average at each screenshot position):

| Shot | FPS |
|---|---|
| 1 crossroads | ~66 |
| 2 city lamp | ~64 |
| 3 wild | ~64 |
| 4 waterfall | ~100 |
| 5 highland | ~95 |

Test machine: Intel Core i5-13400F, NVIDIA GeForce RTX 3050, Windows 11 Pro, Godot 4.7.2 Forward+ (Vulkan). The scene's main rendering loads are 13 omni lights with cube shadows, SDFGI, SSR, SSIL and volumetric fog. I didn't profile these individually.
