// HTTP layer shared by the Edge Functions (Deno) and the Node tests: auth, JSON, status codes.
import type { Repo } from "../core/repo.ts";
import { syncColony } from "../core/sync.ts";
import { findOpponent } from "../core/matchmaking.ts";
import { finishAttack } from "../core/finish.ts";
import { shopBuy } from "../core/shop.ts";
import { profile } from "../core/profile.ts";
import { finishPve, pveRanking } from "../core/pve.ts";

export type Deps = {
  repo: Repo;
  getUser: (jwt: string) => Promise<string | null>;
  now: () => number;
  rand: () => number;
  newId?: () => string;
};

const STATUS: Record<string, number> = {
  bad_colony: 400, bad_level: 400, bad_placement: 400, bad_week: 409, locked: 409, bad_json: 400, bad_item: 400, no_crystals: 409, no_boosters: 409, few_dots: 409, no_colony: 409, abandoned: 409, in_progress: 409, busy: 409, not_found: 404, forbidden: 403,
};
const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });

async function prologue(req: Request, deps: Deps): Promise<{ uid: string; body: any } | Response> {
  if (req.method !== "POST") return json({ error: "method" }, 405);
  const m = /^Bearer (.+)$/.exec(req.headers.get("Authorization") ?? "");
  const uid = m ? await deps.getUser(m[1]) : null;
  if (!uid) return json({ error: "unauthorized" }, 401);
  try {
    const text = await req.text();
    return { uid, body: text ? JSON.parse(text) : {} };
  } catch {
    return json({ error: "bad_json" }, 400);
  }
}

const reply = (r: { error?: string; [k: string]: unknown }) => json(r, r.error ? STATUS[r.error] ?? 400 : 200);

export async function handleSync(req: Request, deps: Deps): Promise<Response> {
  const p = await prologue(req, deps);
  if (p instanceof Response) return p;
  return reply(await syncColony(deps.repo, p.uid, p.body?.colony, deps.now(), deps.rand));
}

export async function handleFind(req: Request, deps: Deps): Promise<Response> {
  const p = await prologue(req, deps);
  if (p instanceof Response) return p;
  const r = await findOpponent(deps.repo, p.uid, deps.now(), deps.rand, deps.newId, p.body?.practice === true, p.body?.loadout);
  return reply(r.error ? r : { ...r, profile: await profile(deps.repo, p.uid, deps.now()) });
}

export async function handleFinish(req: Request, deps: Deps): Promise<Response> {
  const p = await prologue(req, deps);
  if (p instanceof Response) return p;
  const r = await finishAttack(deps.repo, p.uid, p.body?.attack_id, p.body?.commands, p.body?.surrender_tick, deps.now(), deps.rand);
  return reply(r.error ? r : { ...r, profile: await profile(deps.repo, p.uid, deps.now()) });
}

export async function handleShop(req: Request, deps: Deps): Promise<Response> {
  const p = await prologue(req, deps);
  if (p instanceof Response) return p;
  return reply(await shopBuy(deps.repo, p.uid, p.body?.item, deps.now()));
}

export async function handleFinishPve(req: Request, deps: Deps): Promise<Response> {
  const p = await prologue(req, deps);
  if (p instanceof Response) return p;
  return reply(await finishPve(deps.repo, p.uid, p.body, deps.now()));
}

export async function handlePveRanking(req: Request, deps: Deps): Promise<Response> {
  const p = await prologue(req, deps);
  if (p instanceof Response) return p;
  return reply(await pveRanking(deps.repo, p.uid, deps.now()));
}
