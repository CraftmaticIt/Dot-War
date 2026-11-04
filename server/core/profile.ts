// Player profile: season settlement, daily quests, booster inventory. Also quest events.
import { DEFS, applyEvent, dailyQuests, dayIndex, leagueOf, questDef, rollChest, seasonEnds, seasonIndex,
  type QuestDef, type QuestState } from "../game/meta.ts";
import type { Player, Repo } from "./repo.ts";

export type ProfileView = {
  boosters: Record<string, number>; crystals: number; trophies: number; league: number; league_name: string;
  season: number; season_ends: number; last_reward: any;
  quests: { id: string; text: string; progress: number; target: number; reward: number; done: boolean }[];
};
const RETRIES = 4;

function view(p: Player, now: number): ProfileView {
  const lg = leagueOf(p.trophies);
  return {
    boosters: { ...p.boosters }, crystals: p.crystals, trophies: p.trophies, league: lg, league_name: DEFS.leagues[lg].name,
    season: p.season, season_ends: seasonEnds(now), last_reward: p.last_reward,
    quests: (p.quests?.list ?? []).filter((q) => questDef(q.id)).map((q) => {  // retired quest ids are skipped
      const d = questDef(q.id)!;
      return { id: q.id, text: d.text, progress: q.progress, target: d.target, reward: d.reward, done: q.done };
    }),
  };
}

/** Settles a finished season (atomic, once) and rolls today's quests; returns the view. */
export async function profile(repo: Repo, uid: string, now: number): Promise<ProfileView> {
  let p = await repo.ensurePlayer(uid, now);
  const cur = seasonIndex(now);
  if (p.season < cur) {
    const lg = leagueOf(p.trophies);
    const reward = DEFS.leagues[lg].reward;
    await repo.settleSeason(uid, cur, reward, { season: p.season, league: lg, league_name: DEFS.leagues[lg].name, reward });
    p = (await repo.getPlayer(uid))!;
  }
  const today = dayIndex(now);
  for (let i = 0; i < RETRIES && (!p.quests || p.quests.day !== today); i++) {
    await repo.setQuests(uid, dailyQuests(uid, today), p.quests_rev);
    p = (await repo.getPlayer(uid))!;
  }
  return view(p, now);
}

export type QuestRewards = { completed: QuestDef[]; chest: { boosters: Record<string, number>; crystals: number } | null };

/** Applies verified events to today's quests (CAS on quests_rev) and grants rewards once. */
export async function questEvents(repo: Repo, uid: string, events: [string, number][], now: number,
  rand: () => number): Promise<QuestRewards> {
  for (let i = 0; i < RETRIES; i++) {
    const p = await repo.getPlayer(uid);
    if (!p) return { completed: [], chest: null };
    const today = dayIndex(now);
    let state: QuestState = p.quests && p.quests.day === today ? p.quests : dailyQuests(uid, today);
    const completed: QuestDef[] = [];
    let allDone = false;
    for (const [ev, n] of events) {
      const r = applyEvent(state, ev, n);
      state = r.state;
      completed.push(...r.completed);
      allDone = allDone || r.allDone;
    }
    if (!(await repo.setQuests(uid, state, p.quests_rev))) continue;
    const chest = allDone ? rollChest(rand) : null;
    const crystals = completed.reduce((s, q) => s + q.reward, 0) + (chest?.crystals ?? 0);
    if (crystals > 0 || chest) await repo.grant(uid, crystals, chest?.boosters ?? {});
    return { completed, chest };
  }
  return { completed: [], chest: null };
}
