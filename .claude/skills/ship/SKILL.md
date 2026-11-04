---
name: ship
description: Ship the current branch - wait for green CI, deploy the Supabase backend with the live smoke test, push to main, and hand the owner the online APK from the main build.
disable-model-invocation: true
---

# Ship to main

Repo: CraftmaticIt/Dot-War. Working branch is the session's designated branch.

1. Local checks: `./scripts/test.sh`, `cd server && npm test`, `./scripts/prepare_functions.sh` + `deno check` for each
   function in `supabase/functions/*/index.ts`. Stop on any failure.
2. Push the branch; wait for workflows `test`, `server`, `android` on the head SHA (GitHub MCP `actions_list`).
   Never poll with sleep in the foreground: use a background `sleep` and check again.
3. Dispatch `supabase.yml` on the branch (`actions_run_trigger`), wait, require `conclusion: success`
   (the Smoke test step must have run, not skipped). On failure read `get_job_logs` (failed_only) and fix.
4. Push to main only if the owner approved shipping in this conversation: `git push origin <branch>:main`.
5. Wait for the `android` run on main, take its `dot-war-debug-apk` artifact
   (`list_workflow_run_artifacts` → `download_workflow_run_artifact`), download into `build/`, unzip, verify
   `unzip -p build/dot-war-debug.apk assets/net/config.json` has a non-empty url and anon_key, then send the APK
   with SendUserFile.
6. Summarise in Polish: what shipped, CI/smoke results, anything left.
