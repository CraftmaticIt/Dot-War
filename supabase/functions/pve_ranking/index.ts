// Edge Function: thin wrapper over server/http/handlers.ts (copied into _shared/server by CI).
import { handlePveRanking } from "../_shared/server/http/handlers.ts";
import { makeDeps } from "../_shared/supa_repo.ts";

const deps = makeDeps();
Deno.serve(async (req) => {
  try {
    return await handlePveRanking(req, deps);
  } catch (e) {
    console.error(e);
    return new Response(JSON.stringify({ error: "internal" }), { status: 500, headers: { "Content-Type": "application/json" } });
  }
});
