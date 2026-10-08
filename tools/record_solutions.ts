// Records the web game's movement solutions, input by input, with state snapshots,
// so the native simulation can be checked against the original step for step.
//   ../PerspectiveOpus/node_modules/.bin/tsx tools/record_solutions.ts
import { writeFileSync } from 'node:fs';
import { getLevel } from '../../PerspectiveOpus/src/game/levels';
import { Bot } from '../../PerspectiveOpus/tests/bot';
import { SOLUTIONS } from '../../PerspectiveOpus/tests/solutions';

for (const s of SOLUTIONS) {
  const lv = getLevel(s.level);
  const b = new Bot(lv, '3d');
  const inputs: number[][] = [];
  const snaps: number[][] = [];
  const snap = () => {
    const g = b.game;
    const p = g.player.pos;
    snaps.push([inputs.length, p.x, p.y, p.z, g.mode === '3d' ? 1 : 0, g.notesCount, g.deaths, g.player.grounded ? 1 : 0]);
  };
  snap();
  b.onStep = (f) => {
    inputs.push([f.moveX, f.moveZ, (f.jumpHeld ? 1 : 0) | (f.jumpPressed ? 2 : 0) | (f.switchPressed ? 4 : 0)]);
  };
  // Wrap step so the snapshot is taken after each 60th step completes.
  const step = b.game.step.bind(b.game);
  b.game.step = (dt, f) => {
    step(dt, f);
    if (inputs.length % 60 === 0) snap();
  };
  s.run(b);
  snap();
  const g = b.game;
  writeFileSync(
    `tests/data/${lv.info.id}.json`,
    JSON.stringify({ level: lv.info.id, inputs, snaps, finished: g.finished, notes: g.notesCount, deaths: g.deaths }),
  );
  console.log(lv.info.id, inputs.length, 'steps', snaps.length, 'snapshots', g.finished ? 'finished' : 'NOT finished');
}
