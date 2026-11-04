// Meta rules shared by server logic (definitions live in meta_defs.json, also read by Godot).
import DEFS_JSON from "./meta_defs.json" with { type: "json" };
import { idiv } from "../sim/fx.ts";
import { SimRng } from "../sim/rng.ts";

export type QuestDef = { id: string; text: string; event: string; target: number; reward: number };
export type QuestProgress = { id: string; progress: number; done: boolean };
export type QuestState = { day: number; list: QuestProgress[] };
export const DEFS = DEFS_JSON as {
  boosters: Record<string, { name: string; price: number; info: string }>;
  start_boosters: Record<string, number>;
  max_loadout: number;
  leagues: { name: string; min: number; reward: number }[];
  season: { epoch: number; days: number; reset_above: number };
  quests_per_day: number;
  quests: QuestDef[];
  chest: { boosters_min: number; boosters_max: number; crystals_min: number; crystals_max: number };
};
const SEASON_SECS = DEFS.season.days * 86400;
const QUEST = new Map(DEFS.quests.map((q) => [q.id, q]));

export const dayIndex = (now: number) => Math.floor(now / 86400);
export const seasonIndex = (now: number) => Math.max(0, Math.floor((now - DEFS.season.epoch) / SEASON_SECS));
export const seasonEnds = (now: number) => DEFS.season.epoch + (seasonIndex(now) + 1) * SEASON_SECS;
export function leagueOf(trophies: number): number {
  let i = 0;
  DEFS.leagues.forEach((l, j) => { if (trophies >= l.min) i = j; });
  return i;
}
export function seasonReset(t: number): number {
  const a = DEFS.season.reset_above;
  return t > a ? a + idiv(t - a, 2) : t;
}

function fnv(s: string): number {
  let h = 0x811c9dc5;
  for (const b of new TextEncoder().encode(s)) h = Math.imul(h ^ b, 0x01000193) >>> 0;
  return h;
}

export function dailyQuests(uid: string, day: number): QuestState {
  const rng = new SimRng(fnv(`${uid}:${day}`));
  const pool = DEFS.quests.map((q) => q.id);
  const list: QuestProgress[] = [];
  while (list.length < Math.min(DEFS.quests_per_day, DEFS.quests.length)) {
    const id = pool.splice(rng.rangeI(pool.length), 1)[0];
    list.push({ id, progress: 0, done: false });
  }
  return { day, list };
}

export const questDef = (id: string) => QUEST.get(id);

/** Advances quests listening to `event`. completed = finished by this event; allDone = the
 *  last open quest finished just now (grant the daily chest once). */
export function applyEvent(state: QuestState, event: string, amount: number):
  { state: QuestState; completed: QuestDef[]; allDone: boolean } {
  const wasAll = state.list.every((q) => q.done);
  const completed: QuestDef[] = [];
  const list = state.list.map((q) => {
    const d = QUEST.get(q.id);
    if (!d || q.done || d.event !== event || amount <= 0) return { ...q };
    const progress = Math.min(d.target, q.progress + amount);
    const done = progress >= d.target;
    if (done) completed.push(d);
    return { id: q.id, progress, done };
  });
  return { state: { day: state.day, list }, completed, allDone: !wasAll && list.every((q) => q.done) };
}

export function rollChest(rand: () => number): { boosters: Record<string, number>; crystals: number } {
  const c = DEFS.chest, types = Object.keys(DEFS.boosters);
  const pick = (lo: number, hi: number) => lo + Math.min(hi - lo, Math.floor(rand() * (hi - lo + 1)));
  const n = pick(c.boosters_min, c.boosters_max);
  const boosters: Record<string, number> = {};
  for (let i = 0; i < n; i++) {
    const t = types[Math.min(types.length - 1, Math.floor(rand() * types.length))];
    boosters[t] = (boosters[t] ?? 0) + 1;
  }
  return { boosters, crystals: pick(c.crystals_min, c.crystals_max) };
}

export function cleanLoadout(l: unknown): string[] {
  const out: string[] = [];
  for (const b of Array.isArray(l) ? l : []) {
    if (typeof b === "string" && Object.hasOwn(DEFS.boosters, b) && out.length < DEFS.max_loadout) out.push(b);
  }
  return out;
}

export function loadoutNeeds(l: string[]): Record<string, number> {
  const need: Record<string, number> = {};
  for (const b of l) need[b] = (need[b] ?? 0) + 1;
  return need;
}
