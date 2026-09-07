# Project usage defaults

Applied 2026-09-07 from the player's [article](https://www.reddit.com/r/codex/comments/1w9smrf/astra_token_burn_limited_to_1hour_pro_x20/), adapted to preserve Astra-owned visuals and existing acceptance gates. The author's 1%/hour result is anecdotal, not a promised saving.

`AGENTS.md` is the workflow authority. Project-local `.codex/config.toml` retains Astra, changes reasoning high→medium, and adds:

```toml
[agents]
default_subagent_model = "gpt-5.6-luna"
default_subagent_reasoning_effort = "low"
max_concurrent_threads_per_session = 1
```

The existing `luna_worker.toml` now covers bounded routine work, defaults to low and disables its own agent tools. Explicit spawn briefs use no inherited history and the appropriate model/effort. Terra/medium is available for justified deeper nonvisual review; production visual design remains with Astra. No worker invocation was needed for this configuration-only task.

Codex CLI0.153.4's bundled catalog confirms Astra/medium, Luna/low and Terra/medium support. Settings were checked against the official [configuration reference](https://learn.chatgpt.com/docs/config-file/config-reference) and [subagent documentation](https://learn.chatgpt.com/docs/agent-configuration/subagents). Config defaults do not prove that an already-running desktop task changed its model/effort; explicit task/UI settings can take precedence. Use Medium in the current task's selector if it remains High. No active-session model switch is claimed.

The local config remains ignored because it contains host-specific MCP paths. Its previous bytes are preserved at `.tools/codex-config-before-efficiency.toml`. All unrelated parsed settings, including MCP and permissions, must remain identical. Global settings, caches and permissions are unchanged.

The check runner now executes full M1 acceptance through `--write-fixture` once, followed by `--read-fixture` in a separate process. Inspection of `_initialize()` confirms write mode calls `_run_acceptance()` before writing the expectation; the extra identical ordinary run was redundant. No gameplay code or APK changed. Configuration/TOML and PowerShell syntax checks suffice for this workflow change; the expensive game suite is not repeated merely to confirm removal of a duplicate invocation.

Validation: TOML parse/value assertions and exact preservation of unrelated configuration passed; PowerShell parser passed. `codex doctor --summary --no-color --ascii` reported configuration loaded and desktop initialization successful. Its overall exit was1 because this noninteractive shell uses TERM=dumb; it also reported existing thread-inventory notes. No terminal, thread inventory or security settings were changed to silence those diagnostics. No new model execution or measured savings are claimed.

Reusable game evidence remains in `reports/M1-playtest-iteration-2.md` at commits9c67551/b1173dc/378e6f9. M1 and Thor/visual approval gates remain open as recorded there. Measure actual future usage at meaningful work boundaries; cached input, uncached input, output and shared account allowance are different quantities.
