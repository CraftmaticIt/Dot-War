// Live smoke test against the deployed backend. Env: SUPABASE_URL, SUPABASE_ANON_KEY.
// node --experimental-strip-types scripts/smoke_backend.ts
import { ColonyState } from "../server/game/colony.ts";

const URL_ = process.env.SUPABASE_URL!, KEY = process.env.SUPABASE_ANON_KEY!;
if (!URL_ || !KEY) throw new Error("SUPABASE_URL / SUPABASE_ANON_KEY missing");

async function call(path: string, body: unknown, token?: string) {
  const r = await fetch(`${URL_}${path}`, {
    method: "POST",
    headers: { "Content-Type": "application/json", apikey: KEY, Authorization: `Bearer ${token ?? KEY}` },
    body: JSON.stringify(body),
  });
  const text = await r.text();
  let data: any = text;
  try { data = JSON.parse(text); } catch { /* keep text */ }
  return { status: r.status, data };
}
function expect(cond: boolean, msg: string, extra?: unknown) {
  if (!cond) { console.error("SMOKE FAIL:", msg, JSON.stringify(extra)); process.exit(1); }
  console.log("ok -", msg);
}

const su = await call("/auth/v1/signup", {});
expect(su.status === 200 && !!su.data.access_token, "anonymous sign-up", su);
const tok = su.data.access_token;
const now = Math.floor(Date.now() / 1000);
const c0 = ColonyState.newDefault(now);
c0.dots = 0; // new colonies start with dots; this account must have none for the few_dots check
const s = await call("/functions/v1/sync_colony", { colony: c0.toDict() }, tok);
expect(s.status === 200 && s.data.accepted === true, "sync_colony accepts first upload", s);
const pr = s.data.profile;
expect(!!pr && pr.quests?.length === 3 && pr.boosters?.split === 1 && typeof pr.league_name === "string",
  "profile: 3 daily quests, start boosters, league", pr);
const b1 = await call("/functions/v1/shop_buy", { item: "split" }, tok);
const b2 = await call("/functions/v1/shop_buy", { item: "split" }, tok);
const b3 = await call("/functions/v1/shop_buy", { item: "split" }, tok);
expect(b1.status === 200 && b2.status === 200 && b3.status === 409 && b3.data.error === "no_crystals",
  "shop: 50 crystals buy two 25-crystal boosters, third refused", [b1.status, b2.status, b3.data]);
expect(b2.data.profile?.boosters?.split === 3 && b2.data.profile?.crystals === 0, "shop updates inventory and crystals", b2.data);
const nb = await call("/functions/v1/find_opponent", { loadout: ["emp", "emp"] }, tok);
expect(nb.status === 409 && nb.data.error === "no_boosters", "loadout beyond inventory refused before matchmaking", nb);
const f = await call("/functions/v1/find_opponent", {}, tok);
expect(f.status === 409 && f.data.error === "few_dots", "find_opponent refuses with 0 dots", f);
const x = await call("/functions/v1/finish_attack", { attack_id: "00000000-0000-0000-0000-000000000000", commands: [] }, tok);
expect(x.status === 404, "finish_attack unknown id -> 404", x);
const u = await call("/functions/v1/sync_colony", { colony: {} });
expect(u.status === 401, "anon key alone is not a user", u);
// Full attack: a second anonymous player whose first upload carries dots (first sync is adopted).
const su2 = await call("/auth/v1/signup", {});
expect(su2.status === 200, "second anonymous sign-up", su2);
const t2 = su2.data.access_token;
const col = ColonyState.newDefault(now);
col.cells["0,1"] = { type: "generator", level: 1, build_end: 0, target_level: 1 };
col.dots = 45;
expect((await call("/functions/v1/sync_colony", { colony: col.toDict() }, t2)).status === 200, "sync with dots");
const op = await call("/functions/v1/find_opponent", { practice: true }, t2);
expect(op.status === 200 && !!op.data.attack_id && op.data.dots === 45 && op.data.bot?.practice === true,
  "practice find_opponent opens a bot attack (never a real player)", op);
const cmds = [1001, 1002, 1003].map((e) => ({ tick: 0, from: e, to: 1, percent: 100 }));
const fin = await call("/functions/v1/finish_attack", { attack_id: op.data.attack_id, commands: cmds, surrender_tick: -1 }, t2);
expect(fin.status === 200 && typeof fin.data.result?.stars === "number" && fin.data.result.trophies === 0,
  "finish_attack replays and scores (practice: no trophies)", fin);
const fin2 = await call("/functions/v1/finish_attack", { attack_id: op.data.attack_id, commands: [] }, t2);
const same = (a: any, b: any) => ["stars", "destroyed_pct", "loot", "trophies"].every((k) => a?.[k] === b?.[k]);
expect(same(fin2.data.result, fin.data.result), "finish_attack is idempotent (jsonb key order ignored)", fin2);
const back = await call("/functions/v1/sync_colony", { colony: col.toDict() }, t2);
expect(back.status === 200 && back.data.accepted === false && back.data.colony.dots === 0, "server refuses re-spending dots", back);
console.log("SMOKE OK");
