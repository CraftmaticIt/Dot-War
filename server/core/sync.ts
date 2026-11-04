// Colony sync with plausibility limits. The client owns layout and timers; the server owns
// trophies, attacks, attack_open, crystals and every server-side energy/dots change, and
// rejects anything the game rules could not have produced since the last accepted sync.
import * as B from "../game/buildings.ts";
import * as Hex from "../game/hex.ts";
import { ColonyState, OFFLINE_CAP_SECS, type Cell } from "../game/colony.ts";
import { idiv } from "../sim/fx.ts";
import type { Player, Repo } from "./repo.ts";

export type SyncResult = {
  colony: Record<string, any>; accepted: boolean; reason?: string; error?: string;
  defenses?: { count: number; loot: number };
};

export const BUILDERS = 2;
export const BUILD_SLACK = 5;        // seconds of clock skew tolerated on build timers
const CAS_RETRIES = 3;

const top = (c?: Cell) => (c ? Math.max(c.level, c.target_level) : 0);
const ceilDiv = (a: number, b: number) => idiv(a + b - 1, b);

/** Energy plus everything already paid for in buildings (target levels count as paid). */
function value(c: ColonyState): number {
  let v = c.energy;
  for (const k in c.cells) for (let l = 1; l <= c.cells[k].target_level; l++) v += B.cost(c.cells[k].type, l);
  return v;
}

function connected(c: ColonyState): boolean {
  const seen = new Set<string>(["0,0"]);
  const todo = ["0,0"];
  while (todo.length) {
    const [q, r] = Hex.parse(todo.pop()!);
    for (const nb of Hex.neighbors(q, r)) {
      const k = Hex.key(...nb);
      if (c.cells[k] && !seen.has(k)) { seen.add(k); todo.push(k); }
    }
  }
  return seen.size === Object.keys(c.cells).length;
}

/** "" when `c` is reachable from `s` (accepted at `syncedAt`) by `now` under the game rules. */
export function plausible(s: ColonyState, c: ColonyState, p: Player, syncedAt: number, now: number): string {
  if (c.cells["0,0"]?.type !== "core" || Object.values(c.cells).filter((x) => x.type === "core").length !== 1) return "core";
  if (Object.keys(c.cells).length > B.maxNodes(c.coreLevel())) return "node_limit";
  if (!connected(c)) return "not_connected";
  for (const k in s.cells) if (!c.cells[k] || c.cells[k].type !== s.cells[k].type) return "missing_cell";
  if (Object.values(c.cells).filter((x) => x.build_end > now).length > BUILDERS) return "builders";

  const elapsed = Math.max(0, now - syncedAt);
  const window = Math.min(elapsed, OFFLINE_CAP_SECS);
  const coreLvl = c.coreLevel();
  let eRate = 0, dRate = 0, required = 0;
  for (const k in c.cells) {
    const cc = c.cells[k], sc = s.cells[k];
    if (sc && (cc.level < sc.level || cc.target_level < sc.target_level)) return "downgrade";
    if (cc.level > cc.target_level) return "bad_level";
    if (cc.type !== "core" && cc.target_level > (sc ? Math.max(top(sc), coreLvl) : coreLvl)) return "core_limit";
    const sTop = top(sc);
    const sBuilding = !!sc && sc.build_end > 0 && sc.target_level > sc.level;
    // Earliest moment each new level can be done: levels are built one after another.
    const base = sBuilding ? Math.max(syncedAt, sc!.build_end) : syncedAt;
    const earliest = (lvl: number): number => {
      if (sBuilding && lvl <= sc!.target_level) return sc!.build_end;
      let t = base;
      for (let l = sTop + 1; l <= lvl; l++) t += B.buildSecs(cc.type, l);
      return t;
    };
    if (cc.build_end > 0 && cc.target_level > cc.level) {
      const minEnd = sBuilding && sc!.target_level === cc.target_level ? sc!.build_end : syncedAt + B.buildSecs(cc.type, cc.target_level);
      if (cc.build_end < minEnd - BUILD_SLACK) return "build_end";
    }
    if (cc.level > (sc?.level ?? 0)) {
      const end = earliest(cc.level);
      if (end > now + BUILD_SLACK) required += Math.max(1, ceilDiv(end - now, 60));
    }
    const t = Math.max(sTop, top(cc));
    eRate += B.energyPerHour(cc.type, t);
    dRate += B.dotsPerHour(cc.type, t);
  }
  if (required > p.crystals - c.crystals) return "build_time";
  const eCap = Math.max(s.energyCap(), c.energyCap());
  if (c.energy > Math.max(s.energy, eCap)) return "energy_cap";
  if (value(c) > value(s) + idiv(eRate * window, 3600) + 1) return "energy";
  const dCap = Math.max(s.dotsCap(), c.dotsCap());
  if (c.dots > Math.max(s.dots, Math.min(dCap, s.dots + idiv(dRate * window, 3600) + 1))) return "dots";
  return "";
}

export async function syncColony(repo: Repo, uid: string, client: unknown, now: number): Promise<SyncResult> {
  const c = ColonyState.fromDict(client);
  if (!c) return { colony: {}, accepted: false, error: "bad_colony" };
  for (let attempt = 0; attempt < CAS_RETRIES; attempt++) {
    const p = await repo.ensurePlayer(uid);
    c.crystals = Math.min(c.crystals, p.crystals);  // server-owned: the client may only spend
    const open = (await repo.openAttacksBy(uid)).length > 0 ? 1 : 0;
    const out = (x: ColonyState) => {
      x.trophies = p.trophies; x.attacks = p.attacks; x.attackOpen = open; x.crystals = Math.min(x.crystals, p.crystals);
      return x.toDict();
    };
    const st = await repo.getColony(uid);
    const defenses = await repo.defensesSince(uid, st ? st.synced_at : 0);
    if (!st) {
      // First contact: the upload must be reachable from a fresh colony within one offline window.
      const since = now - OFFLINE_CAP_SECS;
      const reason = plausible(ColonyState.newDefault(since), c, p, since, now);
      const adopt = reason ? ColonyState.newDefault(now) : c;
      if (!(await repo.createColony(uid, out(adopt), now))) continue;
      if (!reason) await repo.adjustPlayer(uid, 0, 0, null, c.crystals);
      return { colony: out(adopt), accepted: !reason, reason: reason || undefined, defenses };
    }
    const s = ColonyState.fromDict(st.data)!;
    const reason = plausible(s, c, p, st.synced_at, now);
    if (reason) return { colony: out(s), accepted: false, reason, defenses };
    if (!(await repo.casColony(uid, out(c), now, st.rev))) continue;  // changed meanwhile: re-check
    await repo.adjustPlayer(uid, 0, 0, null, c.crystals);
    return { colony: out(c), accepted: true, defenses };
  }
  const st = await repo.getColony(uid);
  const s = st ? ColonyState.fromDict(st.data)! : ColonyState.newDefault(now);
  return { colony: s.toDict(), accepted: false, reason: "busy" };
}
