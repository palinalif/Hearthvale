# Godot AI 3.2.5 development sandbox

The selected bridge is isolated in `dev/mcp`, a separate Godot project beneath a `.gdignore` boundary. The game project and Android exports contain no bridge addon or helper autoload. Install only the tagged release archive pinned in `dependencies.lock.json`; use its [tagged README](https://github.com/hi-godot/godot-ai/blob/v3.2.5/README.md), not the v4 main-branch instructions.

Start the sandbox editor with `GODOT_AI_DISABLE_TELEMETRY=true` in its process environment. The plugin starts the exactly pinned `godot-ai==3.2.5` backend through uvx. Both HTTP 8000 and editor WebSocket 9500 were observed bound to 127.0.0.1 only. No LAN exposure or authentication weakening was used.

The dock's `McpClientConfigurator.manual_command("codex")` generated the actual Windows client entry: Python's consoleless launcher, its hidden-subprocess wrapper, uvx `--link-mode copy --from godot-ai==3.2.5 godot-ai attach --port 8000 --ws-port 9500 --disable-telemetry`, and 60/360 second startup/tool timeouts. Use the generated absolute paths on each host. The tag's Codex generator targets the user config even when its CLI-client scope setting is project; the generated entry was appended without changing any existing configuration values. A semantic before/after comparison, excluding only the added server, passed. Personal paths/configuration remain outside Git. `codex mcp get godot-ai --json` recognised it, and an independent stdio MCP client invoked `editor_state` successfully through that exact command.

## Observed smoke results

| Operation | Result |
| --- | --- |
| Initialize and inspect session | Passed: actual plugin/server 3.2.5, Godot 4.7.2. |
| Create disposable scene and Camera3D | Passed, verified on disk. |
| Save/restart/read scene hierarchy | Passed: `Smoke/SmokeCamera` retained. |
| Create and attach script | Passed; marker ran in editor and game. |
| Inject intentional missing parenthesis | Passed diagnostic: exact script path, line 5, expected closing parenthesis. |
| Fix error and run | Passed: no launch errors and game log marker received. |
| Capture editor viewport | Passed: actual PNG in `reports/screenshots/mcp-viewport.png`. |
| Generated Windows stdio client | Passed against live editor. |
| Persist an overwrite of an already-open script through scene save | **Failed**: `script_create`/`script_patch` reported successful reload, but later `scene_save` restored the old script buffer on disk. Reproduced while adding configuration-printing code to `smoke.gd`. |

The full MCP acceptance check is therefore **partial/failed**, not passed. Creating a fresh `config_generation.gd` retained its contents and produced the generated command after restart, but this does not repair the existing-file overwrite case. Do not trust an MCP success response as proof of a persisted script update; read files after save/restart. No local bridge fork or unpinned upgrade was used to hide this failure.

The MCP protocol initialization reports `serverInfo.version=3.4.7`, the FastMCP framework version; the Godot session and `godot-ai --version` report the actual bridge package version 3.2.5.

Local raw evidence: `reports/logs/mcp-smoke.jsonl`, editor/restart logs, generated-command log, and `mcp-stdio-check.log`. These logs may include local paths and are excluded from source control. This bridge check does not establish any Thor testing.
