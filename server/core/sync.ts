// Colony sync with plausibility limits. The client owns its colony layout and timers;
// the server owns trophies, attacks, attack_open and crystals, and rejects impossible jumps.
import * as B from "../game/buildings.ts";
import { ColonyState, OFFLINE_CAP_SECS } from "../game/colony.ts";
import { idiv } from "../sim/fx.ts";
import type { Player, Repo } from "./repo.ts";

export type SyncResult = { colony: Record<string, any>; accepted: boolean; reason?: string; error?: string };

const top = (c?: { level: number; target_level: number }) => (c ? Math.max(c.level, c.target_level) : 0);
const ceilDiv = (a: number, b: number) => idiv(a + b - 1, b);

/** Energy plus everything already paid for in buildings (target levels count as paid). */
function value(c: ColonyState): number {
  let v = c.energy;
  for (const k in c.cells) for (let l = 1; l <= c.cells[k].target_level; l++) v += B.cost(c.cells[k].type, l);
  return v;
}

export function plausible(s: ColonyState, c: ColonyState, p: Player, syncedAt: number, now: number): string {
  if (c.crystals > p.crystals) return "crystals";
  const cores = Object.values(c.cells).filter((x) => x.type === "core").length;
  if (cores !== 1) return "core";
  if (Object.keys(c.cells).length > B.maxNodes(c.coreLevel())) return "node_limit";
  for (const k in s.cells) if (!c.cells[k] || c.cells[k].type !== s.cells[k].type) return "missing_cell";
  const window = Math.min(Math.max(0, now - syncedAt), OFFLINE_CAP_SECS);
  let eRate = 0, dRate = 0, required = 0;
  for (const k in c.cells) {
    const cc = c.cells[k], sc = s.cells[k];
    const sTop = top(sc);
    if (cc.level > sTop + 1 || cc.target_level > sTop + 1) return "level_jump";
    const t = Math.max(sTop, top(cc));
    eRate += B.energyPerHour(cc.type, t);
    dRate += B.dotsPerHour(cc.type, t);
    if (cc.level > (sc?.level ?? 0)) {
      // A level finished since the last sync: either its timer ran out or crystals paid for it.
      const end = sc && sc.build_end > 0 && sc.target_level >= cc.level
        ? sc.build_end
        : syncedAt + B.buildSecs(cc.type, cc.level);
      if (end > now) required += Math.max(1, ceilDiv(end - now, 60));
    }
  }
  if (required > p.crystals - c.crystals) return "build_time";
  if (value(c) > value(s) + idiv(eRate * window, 3600) + 1) return "energy";
  if (c.dots > s.dots + idiv(dRate * window, 3600) + 1) return "dots";
  return "";
}

export async function syncColony(repo: Repo, uid: string, client: unknown, now: number): Promise<SyncResult> {
  const c = ColonyState.fromDict(client);
  if (!c) return { colony: {}, accepted: false, error: "bad_colony" };
  const p = (await repo.getPlayer(uid)) ?? { id: uid, trophies: 0, attacks: 0, crystals: 50, shield_until: null };
  const open = (await repo.openAttacksBy(uid)).length > 0 ? 1 : 0;
  const serverFields = (x: ColonyState) => {
    x.trophies = p.trophies; x.attacks = p.attacks; x.attackOpen = open;
    return x;
  };
  const stored = await repo.getColony(uid);
  if (!stored) {
    // First contact: adopt the local colony (players had offline saves before the backend existed).
    c.crystals = p.crystals;
    await repo.putPlayer(p);
    await repo.putColony(uid, { data: serverFields(c).toDict(), synced_at: now });
    return { colony: c.toDict(), accepted: true };
  }
  const s = ColonyState.fromDict(stored.data)!;
  const reason = plausible(s, c, p, stored.synced_at, now);
  if (reason) {
    s.crystals = p.crystals;
    return { colony: serverFields(s).toDict(), accepted: false, reason };
  }
  p.crystals = c.crystals;
  await repo.putPlayer(p);
  await repo.putColony(uid, { data: serverFields(c).toDict(), synced_at: now });
  return { colony: c.toDict(), accepted: true };
}
