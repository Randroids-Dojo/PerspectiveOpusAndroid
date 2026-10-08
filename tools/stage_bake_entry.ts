// Runs inside Chrome (bundled by tools/bake_stage.ts). Builds the web build's Stage for a
// level and palette and serialises everything it made: the scene graph, geometry,
// materials, the state each stage module keeps for its per-frame update, the light rig,
// and the generated textures. The native Stage rebuilds the same scene from this.
import * as THREE from 'three';
import { LEVELS, getLevel } from '../../PerspectiveOpus/src/game/levels';
import { PALETTES } from '../../PerspectiveOpus/src/game/palettes';
import { Game } from '../../PerspectiveOpus/src/game/sim';
import { Stage } from '../../PerspectiveOpus/src/render3d/stage';
import { SHARED } from '../../PerspectiveOpus/src/render3d/shared';
import { cloudAtlas, moonTexture, spriteAtlas, surfaceTextures } from '../../PerspectiveOpus/src/render3d/textures';

/* eslint-disable @typescript-eslint/no-explicit-any */

// Remember the render target behind every PMREM so its pixels can be read back.
const pmremTargets = new Map<string, THREE.WebGLRenderTarget>();
const fromScene = THREE.PMREMGenerator.prototype.fromScene;
// The environment is soft studio light; a 128 cube keeps every rough lobe identical and
// only the mirror-smooth clearcoat a little softer, at a quarter of the size.
THREE.PMREMGenerator.prototype.fromScene = function (this: THREE.PMREMGenerator, ...args: any[]) {
  args[2] ??= 0.1;
  args[3] ??= 100;
  args[4] = { ...(args[4] ?? {}), size: 128 };
  const rt = (fromScene as any).apply(this, args) as THREE.WebGLRenderTarget;
  pmremTargets.set(rt.texture.uuid, rt);
  return rt;
};

let stage: any = null;

function getStage(): any {
  if (!stage) {
    stage = new Stage();
    document.body.appendChild(stage.canvas);
    stage.resize(844, 390, 1);
  }
  return stage;
}

/**
 * A binary blob of Godot-encoded packed arrays: each part is what `var_to_bytes` would
 * write (a type word and a count, then the data), so the native side decodes a slice with
 * `bytes_to_var` and gets a PackedVector3Array, PackedInt32Array, ... without a loop.
 */
const GD_TYPE = { f32: 32, i32: 30, v2: 35, v3: 36 } as const;
type GdKind = keyof typeof GD_TYPE;
class Blob4 {
  parts: Uint8Array[] = [];
  size = 0;
  add(a: Float32Array | Int32Array, kind: GdKind = a instanceof Int32Array ? 'i32' : 'f32'): { off: number; len: number } {
    const per = kind === 'v3' ? 3 : kind === 'v2' ? 2 : 1;
    const head = new Uint32Array([GD_TYPE[kind], a.length / per]);
    const off = this.size;
    const bytes = new Uint8Array(8 + a.byteLength);
    bytes.set(new Uint8Array(head.buffer), 0);
    bytes.set(new Uint8Array(a.buffer, a.byteOffset, a.byteLength), 8);
    this.parts.push(bytes);
    this.size += bytes.length;
    return { off, len: bytes.length };
  }
  base64(): string {
    const all = new Uint8Array(this.size);
    let o = 0;
    for (const p of this.parts) {
      all.set(p, o);
      o += p.length;
    }
    let s = '';
    const CH = 0x8000;
    for (let i = 0; i < all.length; i += CH) s += String.fromCharCode(...all.subarray(i, i + CH));
    return btoa(s);
  }
}

function attrFloats(a: THREE.BufferAttribute | THREE.InterleavedBufferAttribute, count = a.count): Float32Array {
  const out = new Float32Array(count * a.itemSize);
  for (let i = 0; i < count; i++) for (let k = 0; k < a.itemSize; k++) out[i * a.itemSize + k] = a.getComponent(i, k);
  return out;
}

const SHADER_IDS: [string, (m: THREE.ShaderMaterial) => boolean][] = [
  ['sky', (m) => m.fragmentShader.includes('uSunSize')],
  ['flat', (m) => m.fragmentShader.includes('uMistRise')],
  ['cloud', (m) => m.vertexShader.includes('aCloud')],
  ['bank', (m) => m.vertexShader.includes('aBank')],
  ['star', (m) => m.vertexShader.includes('gl_PointSize')],
  ['water', (m) => m.fragmentShader.includes('uFogDist')],
  ['shaft', (m) => m.fragmentShader.includes('uSeed')],
  ['veil', (m) => m.fragmentShader.includes('streak')],
  ['ghost', (m) => m.fragmentShader.includes('vC.r')],
  ['billboard', (m) => m.vertexShader.includes('attribute vec4 iA')],
  ['ambient', (m) => m.vertexShader.includes('uBoxMin')],
];

function shaderId(m: THREE.ShaderMaterial): string {
  for (const [id, test] of SHADER_IDS) if (test(m)) return id;
  return 'unknown';
}

interface Ctx {
  bin: Blob4;
  nodes: any[];
  nodeIds: Map<THREE.Object3D, number>;
  geos: any[];
  geoIds: Map<THREE.BufferGeometry, number>;
  mats: any[];
  matIds: Map<THREE.Material, number>;
  texs: Map<string, any>;
  shared: Map<THREE.Texture, string>;
  skip: Set<THREE.Object3D>;
}

function texOf(c: Ctx, t: THREE.Texture): string {
  const known = c.shared.get(t);
  if (known) return known;
  const name = `tex${c.texs.size}`;
  if (!c.texs.has(t.uuid)) {
    const img = t.image as HTMLCanvasElement;
    // Canvas textures are uploaded flipped (uv 0,0 is the bottom left); save them flipped so the
    // native side samples the same texel at the same uv.
    const cv = document.createElement('canvas');
    cv.width = img.width;
    cv.height = img.height;
    const g = cv.getContext('2d')!;
    if (t.flipY) {
      g.translate(0, img.height);
      g.scale(1, -1);
    }
    g.drawImage(img, 0, 0);
    c.texs.set(t.uuid, { name, png: cv.toDataURL('image/png'), srgb: t.colorSpace === THREE.SRGBColorSpace, mip: t.generateMipmaps });
  }
  return c.texs.get(t.uuid).name;
}

function uniformValue(c: Ctx, v: any): any {
  if (v === null || v === undefined) return null;
  if (typeof v === 'number' || typeof v === 'boolean') return v;
  if (v.isColor) return { c: [v.r, v.g, v.b] };
  if (v.isVector2) return { v2: [v.x, v.y] };
  if (v.isVector3) return { v3: [v.x, v.y, v.z] };
  if (v.isVector4) return { v4: [v.x, v.y, v.z, v.w] };
  if (v.isMatrix4) return { m4: v.toArray() };
  if (v.isTexture) return { tex: texOf(c, v) };
  if (Array.isArray(v)) return v.map((x) => uniformValue(c, x));
  return null;
}

function matOf(c: Ctx, m: THREE.Material): number {
  const hit = c.matIds.get(m);
  if (hit !== undefined) return hit;
  const id = c.mats.length;
  c.matIds.set(m, id);
  const a = m as any;
  const d: any = {
    type: m.type,
    key: Object.prototype.hasOwnProperty.call(m, 'customProgramCacheKey') ? a.customProgramCacheKey() : '',
    transparent: m.transparent,
    opacity: m.opacity,
    blending: m.blending,
    side: m.side,
    depthWrite: m.depthWrite,
    depthTest: m.depthTest,
    depthFunc: m.depthFunc,
    vertexColors: m.vertexColors,
    fog: a.fog ?? false,
    toneMapped: m.toneMapped,
    polygonOffset: m.polygonOffset,
    polygonOffsetFactor: m.polygonOffsetFactor,
    alphaTest: m.alphaTest,
    defines: m.defines ?? {},
  };
  for (const k of ['color', 'emissive', 'sheenColor']) if (a[k]?.isColor) d[k] = [a[k].r, a[k].g, a[k].b];
  for (const k of ['roughness', 'metalness', 'emissiveIntensity', 'clearcoat', 'clearcoatRoughness', 'sheen', 'sheenRoughness', 'iridescence', 'iridescenceIOR', 'ior', 'envMapIntensity', 'flatShading', 'specularIntensity'])
    if (k in a) d[k] = a[k];
  if (a.iridescenceThicknessRange) d.iridescenceThicknessRange = [...a.iridescenceThicknessRange];
  if (a.map) d.map = texOf(c, a.map);
  if ((m as THREE.ShaderMaterial).isShaderMaterial) {
    const sm = m as THREE.ShaderMaterial;
    d.shader = shaderId(sm);
    d.uniforms = {};
    for (const [k, u] of Object.entries(sm.uniforms)) d.uniforms[k] = uniformValue(c, u.value);
  }
  c.mats.push(d);
  return id;
}

/**
 * Geometry in the layout the native loader feeds straight to an ArrayMesh: v, n, uv as
 * vector arrays, c0 = colour rgb + heat (aHot), c1 = aWind / aSpin / aSeed, and an index
 * with the winding reversed (Godot's front faces are clockwise). Instanced attributes stay
 * as plain float arrays.
 */
function geoOf(c: Ctx, g: THREE.BufferGeometry, points = false): number {
  const hit = c.geoIds.get(g);
  if (hit !== undefined) return hit;
  const id = c.geos.length;
  c.geoIds.set(g, id);
  const A = g.attributes as Record<string, THREE.BufferAttribute>;
  const n = A.position.count;
  const d: any = { count: n, inst: {}, instanceCount: (g as any).instanceCount ?? null, points };
  const inst = (a: any) => !!a.isInstancedBufferAttribute || !!a.data?.isInstancedInterleavedBuffer;
  d.v = c.bin.add(attrFloats(A.position), 'v3');
  if (A.normal && !inst(A.normal)) d.n = c.bin.add(attrFloats(A.normal), 'v3');
  if (A.uv && !inst(A.uv)) d.uv = c.bin.add(attrFloats(A.uv), 'v2');
  const col = A.color ?? A.aCol;
  if (col && !inst(col)) {
    const c0 = new Float32Array(n * 4);
    for (let i = 0; i < n; i++) {
      c0[i * 4] = col.getComponent(i, 0);
      c0[i * 4 + 1] = col.getComponent(i, 1);
      c0[i * 4 + 2] = col.getComponent(i, 2);
      c0[i * 4 + 3] = A.aHot ? A.aHot.getComponent(i, 0) : 1;
    }
    d.c0 = c.bin.add(c0);
  }
  const extra = A.aWind ?? A.aSpin ?? A.aSeed;
  if (extra && !inst(extra)) {
    const c1 = new Float32Array(n * 4);
    for (let i = 0; i < n; i++) for (let k = 0; k < extra.itemSize; k++) c1[i * 4 + k] = extra.getComponent(i, k);
    d.c1 = c.bin.add(c1);
    if (A.aSeed && !A.aWind && !A.aSpin) d.c1IsSeed = true;
  }
  for (const [name, a] of Object.entries(A)) if (inst(a)) d.inst[name] = { size: a.itemSize, ...c.bin.add(attrFloats(a)) };
  if (!points) {
    let idx: Int32Array;
    if (g.index) idx = Int32Array.from(g.index.array as ArrayLike<number>);
    else {
      idx = new Int32Array(n);
      for (let i = 0; i < n; i++) idx[i] = i;
    }
    for (let i = 0; i + 2 < idx.length; i += 3) {
      const t = idx[i + 1];
      idx[i + 1] = idx[i + 2];
      idx[i + 2] = t;
    }
    d.i = c.bin.add(idx);
  }
  const known = new Set(['position', 'normal', 'uv', 'color', 'aCol', 'aHot', 'aWind', 'aSpin', 'aSeed']);
  const other = Object.keys(A).filter((k) => !known.has(k) && !inst(A[k]));
  if (other.length) d.unhandled = other;
  c.geos.push(d);
  return id;
}

function nodeOf(c: Ctx, o: THREE.Object3D): number {
  const hit = c.nodeIds.get(o);
  if (hit !== undefined) return hit;
  const id = c.nodes.length;
  c.nodeIds.set(o, id);
  const n: any = {
    type: o.type,
    name: o.name,
    p: o.position.toArray(),
    q: o.quaternion.toArray(),
    r: [o.rotation.x, o.rotation.y, o.rotation.z],
    order: o.rotation.order,
    s: o.scale.toArray(),
    vis: o.visible,
    ro: o.renderOrder,
    cast: o.castShadow,
    recv: o.receiveShadow,
    culled: o.frustumCulled,
    children: [] as number[],
  };
  c.nodes.push(n);
  const mesh = o as THREE.Mesh;
  if ((mesh.isMesh || (o as any).isPoints || (o as any).isLine) && mesh.geometry) {
    n.geo = geoOf(c, mesh.geometry, !!(o as any).isPoints);
    n.mat = Array.isArray(mesh.material) ? mesh.material.map((m) => matOf(c, m)) : matOf(c, mesh.material);
  }
  const im = o as THREE.InstancedMesh;
  if (im.isInstancedMesh) {
    // A MultiMesh buffer: 3x4 rows of each instance matrix, then its colour (rgba) if any.
    const cap = im.instanceMatrix.count;
    const m = im.instanceMatrix.array;
    const ic = im.instanceColor?.array;
    const per = ic ? 16 : 12;
    const buf = new Float32Array(cap * per);
    for (let i = 0; i < cap; i++) {
      const o16 = i * 16;
      const ob = i * per;
      for (let r = 0; r < 3; r++) {
        buf[ob + r * 4] = m[o16 + r];
        buf[ob + r * 4 + 1] = m[o16 + 4 + r];
        buf[ob + r * 4 + 2] = m[o16 + 8 + r];
        buf[ob + r * 4 + 3] = m[o16 + 12 + r];
      }
      if (ic) {
        buf[ob + 12] = ic[i * 3];
        buf[ob + 13] = ic[i * 3 + 1];
        buf[ob + 14] = ic[i * 3 + 2];
        buf[ob + 15] = 1;
      }
    }
    n.count = im.count;
    n.capacity = cap;
    n.colors = !!ic;
    n.buffer = c.bin.add(buf);
  }
  for (const ch of o.children) if (!c.skip.has(ch)) n.children.push(nodeOf(c, ch));
  return id;
}

/** Deep copy of a module's state with scene objects replaced by references. */
function state(c: Ctx, v: any, depth = 0, seen = new Set<any>()): any {
  if (v === null || v === undefined) return null;
  const t = typeof v;
  if (t === 'number') return Number.isFinite(v) ? v : v > 0 ? 1e30 : v < 0 ? -1e30 : null;
  if (t === 'string' || t === 'boolean') return v;
  if (t === 'function') return undefined;
  if (v.isObject3D) return c.skip.has(v) ? null : { $node: nodeOf(c, v) };
  if (v.isMaterial) return { $mat: matOf(c, v) };
  if (v.isBufferGeometry) return { $geo: geoOf(c, v) };
  if (v.isTexture) return { $tex: texOf(c, v) };
  if (v.isColor) return { $c: [v.r, v.g, v.b] };
  if (v.isVector2) return { $v2: [v.x, v.y] };
  if (v.isVector3) return { $v3: [v.x, v.y, v.z] };
  if (v.isVector4) return { $v4: [v.x, v.y, v.z, v.w] };
  if (v.isQuaternion) return { $q: [v.x, v.y, v.z, v.w] };
  if (v.isMatrix4) return { $m4: v.toArray() };
  if (ArrayBuffer.isView(v)) return { $bin: c.bin.add(new Float32Array(v as any)) };
  if (v instanceof Map || v instanceof Set) return undefined;
  if (seen.has(v) || depth > 8) return null;
  seen.add(v);
  if (Array.isArray(v)) return v.map((x) => state(c, x, depth + 1, seen) ?? null);
  const o: any = {};
  for (const k of Object.keys(v)) {
    const s = state(c, v[k], depth + 1, seen);
    if (s !== undefined) o[k] = s;
  }
  return o;
}

const pick = (o: any, keys: string[]): any => Object.fromEntries(keys.map((k) => [k, o[k]]));

(window as any).bakeStage = (levelId: string, paletteId: string) => {
  const s = getStage();
  const mi = LEVELS.findIndex((l) => l.info.id === levelId);
  const level = getLevel(mi >= 0 ? mi : levelId);
  const game = new Game(level, '3d');
  s.load(game, PALETTES[paletteId]);
  const c: Ctx = {
    bin: new Blob4(),
    nodes: [],
    nodeIds: new Map(),
    geos: [],
    geoIds: new Map(),
    mats: [],
    matIds: new Map(),
    texs: new Map(),
    shared: new Map(),
    skip: new Set(),
  };
  c.shared.set(spriteAtlas(), 'sprites');
  c.shared.set(cloudAtlas(), 'clouds');
  c.shared.set(moonTexture(), 'moon');
  // Rebuilt natively: the voxel chunks (cheap and exact), effects and the backdrop dome.
  c.skip.add(s.levelGroup);
  c.skip.add(s.effects.group);
  c.skip.add(s.backdrop.dome);
  const world = nodeOf(c, s.sim);
  const backdrop = nodeOf(c, s.backdrop.scene);
  const env = s.envs.get(PALETTES[paletteId].id);
  const fog = s.scene.fog as THREE.Fog;
  const out = {
    level: levelId,
    palette: paletteId,
    roots: { world, backdrop },
    look: s.look,
    // The block material's palette uniforms (texture arrays are shared and baked separately).
    world: Object.fromEntries(
      Object.entries(s.worldMat.u as Record<string, { value: any }>)
        .filter(([k]) => k !== 'uDetail' && k !== 'uNormalArr')
        .map(([k, u]) => [k, uniformValue(c, u.value)]),
    ),
    lights: {
      hemi: { sky: s.hemi.color.toArray(), ground: s.hemi.groundColor.toArray(), intensity: s.hemi.intensity },
      sun: { color: s.sun.color.toArray(), intensity: s.sun.intensity, dir: s.sunDir.toArray(), bias: s.sun.shadow.bias, normalBias: s.sun.shadow.normalBias },
      spot: { color: s.spot.color.toArray(), intensity: s.spot.intensity, angle: s.spot.angle, penumbra: s.spot.penumbra, decay: s.spot.decay, distance: s.spot.distance },
      fog: fog.color.toArray(),
      envIntensity: s.scene.environmentIntensity,
      env: env ? env.uuid : null,
    },
    shared: Object.fromEntries(Object.entries(SHARED).map(([k, u]) => [k, uniformValue(c, (u as { value: unknown }).value)])),
    modules: {
      entities: state(c, pick(s.entities, ['notes', 'checks', 'drums', 'keys', 'gates', 'plats', 'discords', 'veil', 'fermata', 'discordMat', 'coreMat', 'glowCol', 'drumHead'])),
      decor: state(c, pick(s.decor, ['lights', 'anims'])),
      thorns: state(c, pick(s.thorns, ['berryMat', 'hot', 'hotBase', 'clockwork'])),
      flora: state(c, pick(s.flora, ['tufts', 'full'])),
      backdrop: state(c, pick(s.backdrop, ['waterY', 'spinners', 'shafts', 'hands', 'bodyDir', 'skyMat', 'flatMat', 'lightMat', 'cloudMat', 'starMat', 'waterMat', 'bankMat', 'water', 'follow', 'sim'])),
      quaver: state(c, {
        ...pick(s.quaver, ['group', 'root', 'body', 'headPivot', 'eyes', 'legs', 'stemTop', 'neck', 'xray', 'blob', 'landing', 'mats']),
        ribbons: s.quaver.ribbons.map((r: any) => ({ mesh: r.mesh, w0: r.w0, w1: r.w1, align: r.align, n: r.chain.n, seg: r.chain.seg })),
      }),
    },
    nodes: c.nodes,
    geos: c.geos,
    mats: c.mats,
    texs: [...c.texs.values()],
    bin: '',
  };
  out.bin = c.bin.base64();
  return out;
};

(window as any).bakeShared = () => {
  getStage();
  const tex = surfaceTextures();
  const raw = (t: THREE.DataArrayTexture) => {
    const d = t.image.data as Uint8Array;
    let s = '';
    const CH = 0x8000;
    for (let i = 0; i < d.length; i += CH) s += String.fromCharCode(...d.subarray(i, i + CH));
    return { w: t.image.width, h: t.image.height, depth: t.image.depth, b64: btoa(s) };
  };
  const flip = (t: THREE.Texture) => {
    const img = t.image as HTMLCanvasElement;
    const cv = document.createElement('canvas');
    cv.width = img.width;
    cv.height = img.height;
    const g = cv.getContext('2d')!;
    g.translate(0, img.height);
    g.scale(1, -1);
    g.drawImage(img, 0, 0);
    return cv.toDataURL('image/png');
  };
  return { detail: raw(tex.detail), normal: raw(tex.normal), sprites: flip(spriteAtlas()), clouds: flip(cloudAtlas()), moon: flip(moonTexture()) };
};

/** The PMREM of a palette's studio environment as raw half floats, rows in GL order (row 0 is v = 0). */
(window as any).bakeEnv = (paletteId: string) => {
  const s = getStage();
  const t = s.envs.get(paletteId) as THREE.Texture | undefined;
  if (!t) return null;
  const rt = pmremTargets.get(t.uuid);
  if (!rt) return null;
  const w = rt.width;
  const h = rt.height;
  const r = s.renderer as THREE.WebGLRenderer;
  const px = new Uint16Array(w * h * 4);
  r.readRenderTargetPixels(rt, 0, 0, w, h, px);
  let str = '';
  const bytes = new Uint8Array(px.buffer);
  const CH = 0x8000;
  for (let i = 0; i < bytes.length; i += CH) str += String.fromCharCode(...bytes.subarray(i, i + CH));
  return { w, h, type: rt.texture.type, b64: btoa(str) };
};
