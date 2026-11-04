// Runs a determinism vector {graph, seed, commands, ticks}. Same contract as sim/replay.gd.
import { SimGraph } from "./graph.ts";
import { SimWorld } from "./world.ts";

export const SimReplay = {
  run(v: any, world?: SimWorld): SimWorld {
    const w = world ?? new SimWorld(SimGraph.fromDict(v.graph), Math.trunc(v.seed));
    for (const c of v.commands) w.queue(c);
    for (let i = 0; i < Math.trunc(v.ticks); i++) w.step();
    return w;
  },
};
