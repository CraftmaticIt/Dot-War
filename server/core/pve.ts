// PvE results: the placement is the whole replay, so the server re-runs it (anti-cheat).
import type { Repo } from "./repo.ts";
import { profile, type ProfileView } from "./profile.ts";
import { PVE, level, validate, runPve, arenaLevel, weekIndex, type Placement } from "../game/pve.ts";

export const PVE_SEED = 1;
const TOP = 20;

export type PveFinish =
  | { error: string }
  | { stars: number; gained: number; crystals: number; profile: ProfileView }
  | { score: number; best: number; profile: ProfileView };

export async function finishPve(repo: Repo, uid: string, body: any, now: number): Promise<any> {
  await repo.ensurePlayer(uid, now);
  if (body?.week !== undefined) {
    if (!Number.isInteger(body.week) || body.week !== weekIndex(now)) return { error: "bad_week" };
    const lvl = arenaLevel(body.week);
    if (validate(lvl, body.placement, true)) return { error: "bad_placement" };
    const { result } = runPve(lvl, body.placement as Placement, PVE_SEED);
    await repo.pveWeekRecord(uid, body.week, result.score);
    const best = (await repo.pveRank(uid, body.week))?.score ?? result.score;
    return { score: result.score, best, profile: await profile(repo, uid, now) };
  }
  const id = body?.level;
  const lvl = Number.isInteger(id) ? level(id) : null;
  if (!lvl) return { error: "bad_level" };
  if (validate(lvl, body.placement, false)) return { error: "bad_placement" };
  if (id > 1 && ((await repo.pveStars(uid))[String(id - 1)] ?? 0) < 1) return { error: "locked" };
  const { result } = runPve(lvl, body.placement as Placement, PVE_SEED);
  const gained = await repo.pveRecord(uid, id, result.stars, PVE.star_crystals);
  return { stars: result.stars, gained, crystals: gained * PVE.star_crystals, profile: await profile(repo, uid, now) };
}

/** Settles last week (once), then this week's top list and the player's own place. */
export async function pveRanking(repo: Repo, uid: string, now: number) {
  const week = weekIndex(now);
  const w = PVE.weekly;
  if (week > 0) await repo.settlePveWeek(week - 1, w.top_pct, w.reward.crystals, w.reward.boosters);
  const top = (await repo.pveTop(week, TOP)).map((r) => ({ name: `Gracz #${r.player.slice(0, 4)}`, score: r.score }));
  return { week, top, me: await repo.pveRank(uid, week) };
}
