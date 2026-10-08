// Bakes the web game's compiled levels and art palettes so the native port plays identical worlds.
//   ../PerspectiveOpus/node_modules/.bin/tsx tools/export_levels.ts
import { mkdirSync, writeFileSync } from 'node:fs';
import { compileLevel } from '../../PerspectiveOpus/src/game/level';
import { EXTRA_LEVELS, LEVELS } from '../../PerspectiveOpus/src/game/levels';
import { PALETTES } from '../../PerspectiveOpus/src/game/palettes';

mkdirSync('assets/data/levels', { recursive: true });
const all = [...LEVELS, EXTRA_LEVELS.title, EXTRA_LEVELS.gallery];
const index: string[] = [];
for (const def of all) {
  const lv = compileLevel(def);
  const out = {
    info: lv.info,
    w: lv.w,
    h: lv.h,
    d: lv.d,
    cells: Buffer.from(lv.cells).toString('base64'),
    spawn: lv.spawn,
    notes: lv.notes,
    checkpoints: lv.checkpoints,
    exit: lv.exit,
    platforms: lv.platforms,
    drums: lv.drums,
    keys: lv.keys,
    gates: lv.gates,
    discords: lv.discords,
    signs: lv.signs,
    decor: lv.decor,
    groupsOn: lv.groupsOn,
  };
  writeFileSync(`assets/data/levels/${lv.info.id}.json`, JSON.stringify(out));
  index.push(lv.info.id);
  console.log(lv.info.id, `${lv.w}x${lv.h}x${lv.d}`, lv.notes.length, 'notes');
}
writeFileSync('assets/data/palettes.json', JSON.stringify(PALETTES, null, 1));
writeFileSync('assets/data/levels/index.json', JSON.stringify({ movements: LEVELS.map((d) => d.info.id), all: index }));
