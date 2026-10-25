// Parses scene_layout.json into a terrain grid with height / walkability queries.
// Coordinates: metres, +Y up, north = -Z, east = +X. Terrain cell (ix, iz) is centred at (ix*1.6, iz*1.6).

export const OV_ROAD = 1, OV_DIRT = 2, OV_WATER = 4, OV_BRIDGE = 8, OV_RAMP = 16;
export const MARGIN = 10; // extra cells generated around the map so it melts into the distance

export class World {
  constructor(json) {
    this.json = json;
    const t = json.terrain;
    this.cs = t.cell_size;
    this.lh = t.layer_height;
    this.yoff = t.ground_y_offset;
    this.ox = t.origin_cell[0];
    this.oz = t.origin_cell[1];
    this.w = t.size[0];
    this.h = t.size[1];
    this.cells = t.rows_north_to_south.map((row) => row.map((c) => ({ ...c })));
    // map bounds in world space
    this.minX = (this.ox - 0.5) * this.cs;
    this.maxX = (this.ox + this.w - 0.5) * this.cs;
    this.minZ = (this.oz - 0.5) * this.cs;
    this.maxZ = (this.oz + this.h - 0.5) * this.cs;
    // extended grid (map + margin)
    this.eox = this.ox - MARGIN;
    this.eoz = this.oz - MARGIN;
    this.ew = this.w + MARGIN * 2;
    this.eh = this.h + MARGIN * 2;
    this.buildMargin();
    this.computeRamps();
    this.computeFlow();
    this.colliders = [];
    this.walkBoxes = [];
  }

  inMap(ix, iz) {
    return ix >= this.ox && ix < this.ox + this.w && iz >= this.oz && iz < this.oz + this.h;
  }
  rawCell(ix, iz) {
    return this.cells[iz - this.oz][ix - this.ox];
  }
  // Cell lookup valid everywhere: map cells as authored; the margin around the map is
  // procedurally generated terraced land (continuing roads and the river); beyond the
  // margin we clamp to its edge.
  cell(ix, iz) {
    if (this.inMap(ix, iz)) return this.rawCell(ix, iz);
    const i = Math.min(Math.max(ix - this.eox, 0), this.ew - 1);
    const j = Math.min(Math.max(iz - this.eoz, 0), this.eh - 1);
    return this.ext[j * this.ew + i];
  }
  edgeCell(ix, iz) {
    const cx = Math.min(Math.max(ix, this.ox), this.ox + this.w - 1);
    const cz = Math.min(Math.max(iz, this.oz), this.oz + this.h - 1);
    return this.rawCell(cx, cz);
  }
  buildMargin() {
    this.ext = new Array(this.ew * this.eh);
    const sm = (a, b, x) => { const t = Math.min(Math.max((x - a) / (b - a), 0), 1); return t * t * (3 - 2 * t); };
    const roadAt = (ix, iz) => (this.edgeCell(ix, iz).overlay & OV_ROAD) !== 0;
    // pass 1: levels, biome, roads
    for (let j = 0; j < this.eh; j++)
      for (let i = 0; i < this.ew; i++) {
        const ix = this.eox + i, iz = this.eoz + j;
        if (this.inMap(ix, iz)) { this.ext[j * this.ew + i] = this.rawCell(ix, iz); continue; }
        const e = this.edgeCell(ix, iz);
        const kx = ix < this.ox ? this.ox - ix : ix >= this.ox + this.w ? ix - (this.ox + this.w - 1) : 0;
        const kz = iz < this.oz ? this.oz - iz : iz >= this.oz + this.h ? iz - (this.oz + this.h - 1) : 0;
        const k = Math.max(kx, kz);
        const n = fbmJS(ix * 0.21 + 3.1, iz * 0.21 - 7.4);
        const rise = kz > 0 && iz < this.oz ? k * 0.2 : k * 0.12;
        const proc = e.level + (n - 0.45) * 3.2 + rise;
        let level = Math.round(e.level + (proc - e.level) * sm(1, 5, k));
        let overlay = 0;
        // roads keep running straight out of the map at their own level
        // roads keep running out of the map through a flat valley that widens into terraces
        const road = roadAt(ix, iz);
        if (road) overlay |= OV_ROAD;
        let rd = 99;
        for (let d = -5; d <= 5; d++) {
          if (roadAt(ix + d, iz) || roadAt(ix, iz + d)) rd = Math.min(rd, Math.abs(d));
        }
        const flat = 1 - sm(1.5, 5.5, rd);
        level = Math.round(level + (e.level - level) * flat);
        this.ext[j * this.ew + i] = { biome: e.biome, level, overlay, outside: true, k };
      }
    // pass 2: the river climbs north in steps (cascades) and flows out south
    const riverN = 14, riverS = 15;
    for (let iz = this.oz - 1; iz >= this.eoz; iz--) {
      const k = this.oz - iz;
      const lv = Math.max(0, Math.floor((k - 1) / 4));
      const c = this.cell(riverN, iz);
      if (iz === this.eoz) {
        // spring: the stream pours out of a higher terrace at the far end of the margin
        c.overlay = 0; c.level = Math.max(c.level, lv + 2);
        continue;
      }
      c.overlay = OV_WATER; c.level = lv;
      for (const dx of [-1, 1]) { const b = this.cell(riverN + dx, iz); b.level = Math.max(b.level, lv + 1); }
    }
    for (let iz = this.oz + this.h; iz < this.eoz + this.eh; iz++) {
      const c = this.cell(riverS, iz);
      c.overlay = OV_WATER; c.level = -1;
      for (const dx of [-1, 1]) { const b = this.cell(riverS + dx, iz); b.level = Math.max(b.level, 0); }
    }
  }
  isWater(ix, iz) { return (this.cell(ix, iz).overlay & OV_WATER) !== 0; }

  computeRamps() {
    for (let iz = this.oz; iz < this.oz + this.h; iz++)
      for (let ix = this.ox; ix < this.ox + this.w; ix++) {
        const c = this.rawCell(ix, iz);
        if (!(c.overlay & OV_RAMP)) continue;
        const dirs = [[0, -1], [0, 1], [1, 0], [-1, 0]];
        for (const [dx, dz] of dirs) {
          const n = this.cell(ix + dx, iz + dz);
          if (n.level === c.level + 1 && !(n.overlay & OV_WATER)) { c.rampDir = [dx, dz]; break; }
        }
      }
  }

  // Flow direction for water cells (rivers run south, side-stepping where the channel shifts)
  computeFlow() {
    this.flow = new Map();
    for (let iz = this.eoz; iz < this.eoz + this.eh; iz++)
      for (let ix = this.eox; ix < this.eox + this.ew; ix++) {
        if (!this.isWater(ix, iz)) continue;
        let f = [0, 1];
        if (this.isWater(ix, iz + 1)) f = [0, 1];
        else if (this.isWater(ix + 1, iz)) f = [1, 0];
        else if (this.isWater(ix - 1, iz)) f = [-1, 0];
        this.flow.set(ix + ',' + iz, f);
      }
  }

  topY(level) { return level * this.lh + this.yoff; }
  waterY(level) { return (level + 0.6) * this.lh; }
  deckY(level) { return (level + 1) * this.lh; }

  // Corner heights of a cell's walkable top: [NW, NE, SW, SE]
  corners(ix, iz) {
    const c = this.cell(ix, iz);
    const y = this.topY(c.level);
    if (c.rampDir) {
      const y1 = y + this.lh;
      const [dx, dz] = c.rampDir;
      if (dz === -1) return [y1, y1, y, y];
      if (dz === 1) return [y, y, y1, y1];
      if (dx === 1) return [y, y1, y, y1];
      return [y1, y, y1, y];
    }
    return [y, y, y, y];
  }

  cellIndex(x, z) {
    return [Math.round(x / this.cs), Math.round(z / this.cs)];
  }

  // Terrain surface height (ignores water / bridges)
  terrainHeight(x, z) {
    const [ix, iz] = this.cellIndex(x, z);
    const k = this.corners(ix, iz);
    const fx = x / this.cs - ix + 0.5, fz = z / this.cs - iz + 0.5;
    const n = k[0] + (k[1] - k[0]) * fx, s = k[2] + (k[3] - k[2]) * fx;
    return n + (s - n) * fz;
  }

  // Height the player stands at, or null when not walkable (water, outside map)
  standHeight(x, z) {
    if (x < this.minX + 0.2 || x > this.maxX - 0.2 || z < this.minZ + 0.2 || z > this.maxZ - 0.2) return null;
    const [ix, iz] = this.cellIndex(x, z);
    const c = this.cell(ix, iz);
    let y;
    if (c.overlay & OV_BRIDGE) {
      // bridge runs along the axis whose two ends are not water
      const ew = !this.isWater(ix - 1, iz) && !this.isWater(ix + 1, iz);
      const across = ew ? z - iz * this.cs : x - ix * this.cs;
      if (Math.abs(across) > 0.5) return null; // railings
      y = this.deckY(c.level);
    } else if (c.overlay & OV_WATER) {
      return null;
    } else {
      y = this.terrainHeight(x, z);
    }
    for (const b of this.walkBoxes) {
      if (x > b.x0 && x < b.x1 && z > b.z0 && z < b.z1) y = Math.max(y, b.top);
    }
    return y;
  }

  blocked(x, z, r) {
    for (const c of this.colliders) {
      if (c.type === 'circle') {
        const dx = x - c.x, dz = z - c.z;
        if (dx * dx + dz * dz < (c.r + r) * (c.r + r)) return true;
      } else if (x > c.x0 - r && x < c.x1 + r && z > c.z0 - r && z < c.z1 + r) return true;
    }
    return false;
  }

  // Can the player move from height y0 to (x,z)?
  canStand(x, z, y0, r = 0.22) {
    const pts = [[0, 0], [r, 0], [-r, 0], [0, r * 0.6], [0, -r * 0.6]];
    let yc = null;
    for (const [dx, dz] of pts) {
      const y = this.standHeight(x + dx, z + dz);
      if (y === null) return null;
      if (Math.abs(y - y0) > 0.36) return null;
      if (dx === 0 && dz === 0) yc = y;
    }
    if (this.blocked(x, z, r)) return null;
    return yc;
  }
}

function hashJS(x, y) { const s = Math.sin(x * 127.1 + y * 311.7) * 43758.5453; return s - Math.floor(s); }
function vnoiseJS(x, y) {
  const ix = Math.floor(x), iy = Math.floor(y), fx = x - ix, fy = y - iy;
  const ux = fx * fx * (3 - 2 * fx), uy = fy * fy * (3 - 2 * fy);
  const a = hashJS(ix, iy), b = hashJS(ix + 1, iy), c = hashJS(ix, iy + 1), d = hashJS(ix + 1, iy + 1);
  return (a + (b - a) * ux) * (1 - uy) + (c + (d - c) * ux) * uy;
}
function fbmJS(x, y) { let a = 0.5, s = 0; for (let i = 0; i < 4; i++) { s += a * vnoiseJS(x, y); x = x * 2.03 + 17.1; y = y * 2.03 + 9.2; a *= 0.5; } return s; }
