// Booster shop: atomic purchase for crystals.
import { DEFS } from "../game/meta.ts";
import type { Repo } from "./repo.ts";
import { profile, type ProfileView } from "./profile.ts";

export async function shopBuy(repo: Repo, uid: string, item: unknown, now: number): Promise<{ error?: string; profile?: ProfileView }> {
  if (typeof item !== "string" || !Object.hasOwn(DEFS.boosters, item)) return { error: "bad_item" };
  await repo.ensurePlayer(uid, now);
  if (!(await repo.buy(uid, item, DEFS.boosters[item].price))) return { error: "no_crystals" };
  return { profile: await profile(repo, uid, now) };
}
