import { test } from "node:test";
import assert from "node:assert/strict";
import { MemoryRepo } from "../core/repo.ts";
import { handleSync, handleFind, handleFinish, type Deps } from "../http/handlers.ts";
import { ColonyState } from "../game/colony.ts";

const T0 = 1_800_000_000;
function deps(repo = new MemoryRepo()): Deps {
  return { repo, getUser: async (t) => (t === "good" ? "u1" : null), now: () => T0, rand: () => 0.5, newId: () => repo.newId() };
}
const req = (body: unknown, token: string | null = "good", method = "POST") =>
  new Request("http://x/fn", { method, headers: token ? { Authorization: `Bearer ${token}` } : {},
    body: method === "POST" ? (typeof body === "string" ? body : JSON.stringify(body)) : undefined });

test("401 without or with bad token", async () => {
  for (const h of [handleSync, handleFind, handleFinish]) {
    assert.equal((await h(req({}, null), deps())).status, 401);
    assert.equal((await h(req({}, "bad"), deps())).status, 401);
  }
});

test("405 on GET, 400 on bad json", async () => {
  assert.equal((await handleSync(req(null, "good", "GET"), deps())).status, 405);
  assert.equal((await handleSync(req("{nope"), deps())).status, 400);
});

test("sync 200 then find few_dots 409, finish unknown 404", async () => {
  const d = deps();
  const s = await handleSync(req({ colony: ColonyState.newDefault(T0).toDict() }), d);
  assert.equal(s.status, 200);
  assert.equal((await s.json()).accepted, true);
  const f = await handleFind(req({}), d);
  assert.equal(f.status, 409);
  assert.equal((await f.json()).error, "few_dots");
  const x = await handleFinish(req({ attack_id: "nope", commands: [] }), d);
  assert.equal(x.status, 404);
});

test("sync with garbage colony is 400", async () => {
  assert.equal((await handleSync(req({ colony: 5 }), deps())).status, 400);
});
