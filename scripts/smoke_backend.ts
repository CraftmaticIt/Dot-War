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
const s = await call("/functions/v1/sync_colony", { colony: ColonyState.newDefault(now).toDict() }, tok);
expect(s.status === 200 && s.data.accepted === true, "sync_colony accepts first upload", s);
const f = await call("/functions/v1/find_opponent", {}, tok);
expect(f.status === 409 && f.data.error === "few_dots", "find_opponent refuses with 0 dots", f);
const x = await call("/functions/v1/finish_attack", { attack_id: "00000000-0000-0000-0000-000000000000", commands: [] }, tok);
expect(x.status === 404, "finish_attack unknown id -> 404", x);
const u = await call("/functions/v1/sync_colony", { colony: {} });
expect(u.status === 401, "anon key alone is not a user", u);
console.log("SMOKE OK");
