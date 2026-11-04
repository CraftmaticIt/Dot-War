// Static checks on the SQL schema: RLS everywhere, no client write policies,
// one open attack per defender (race guard for matchmaking).
import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync, readdirSync } from "node:fs";

const DIR = new URL("../../supabase/migrations/", import.meta.url);
const sql = readdirSync(DIR).filter((f) => f.endsWith(".sql")).sort()
  .map((f) => readFileSync(new URL(f, DIR), "utf8")).join("\n").toLowerCase();
const tables = [...sql.matchAll(/create table (?:if not exists )?(?:public\.)?(\w+)/g)].map((m) => m[1]);

test("expected tables exist", () => {
  for (const t of ["players", "colonies", "attacks"]) assert.ok(tables.includes(t), t);
});

test("every table has row level security", () => {
  for (const t of tables) {
    assert.match(sql, new RegExp(`alter table (?:public\\.)?${t} enable row level security`), t);
  }
});

test("no insert/update/delete policies for clients", () => {
  assert.doesNotMatch(sql, /create policy[^;]*for (insert|update|delete|all)/);
});

test("one open attack per defender", () => {
  assert.match(sql, /create unique index[^;]*attacks[^;]*\(defender\)[^;]*where status = 'open'/);
});

test("anonymous sign-ins enabled in config", () => {
  const cfg = readFileSync(new URL("../../supabase/config.toml", import.meta.url), "utf8");
  assert.match(cfg, /enable_anonymous_sign_ins\s*=\s*true/);
});
