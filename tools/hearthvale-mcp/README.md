# Hearthvale local MCP

Development-only stdio MCP server for the canonical checkout. It exposes structured, repo-contained file, Godot, and Git operations—never arbitrary shell execution. It does not read credentials, environment variables, or paths outside the checkout.

## Start

```powershell
cd 'E:\Voxel Game Project\Hearthvale\tools\hearthvale-mcp'
npm install
$env:HEARTHVALE_REPO_ROOT = 'E:\Voxel Game Project\Hearthvale'
npm start
```

Use the resulting stdio command with OpenAI Secure MCP Tunnel. Keep the server bound to the local stdio process; do **not** publish a port. Tunnel setup changes over time, so follow current OpenAI documentation for the exact tunnel command and authentication flow.

## Secure MCP Tunnel setup

1. In [OpenAI Platform Tunnels](https://platform.openai.com/settings/organization/tunnels), create or select a tunnel and copy its `tunnel_...` identifier.
2. Create a separate runtime API key whose principal has **Tunnels Read + Use** for that tunnel. Do not use an admin key for the daemon.
3. In a PowerShell session that will run the tunnel, set the runtime key only for that process:

```powershell
$env:CONTROL_PLANE_API_KEY = '<runtime key>'
tunnel-client init --sample sample_mcp_stdio_local --profile hearthvale-local --tunnel-id 'tunnel_...' --mcp-command "cmd.exe /d /s /c call E:\Voxel Game Project\Hearthvale\tools\hearthvale-mcp\start-server.cmd"
tunnel-client doctor --profile hearthvale-local --explain
tunnel-client run --profile hearthvale-local
```

4. While it is running, confirm its local readiness endpoint and then add the OpenAI-hosted tunnel URL in ChatGPT **Settings → Connectors**. Keep the daemon running for discovery and calls.

The server itself remains stdio-only; the tunnel client makes the outbound connection and exposes only local operator endpoints such as `/readyz` and `/ui`.

## Tools and safeguards

Repository: `repo_info`, `read_file`, `list_files`, `write_file`, `git_status`, `git_branches`, `git_diff`, `git_log`, `git_rev_parse`.

Godot: `run_godot_check`, `run_test`, `run_tests` (pinned editor from `.tools/godot-4.7.2`).

Git mutation: `git_fetch`, `git_switch_branch`, `git_create_branch`, `git_commit`, `git_push`, `git_sync_with_default`.

All paths are canonicalized below the Git root. Writes are restricted to development paths. Switching and sync refuse a dirty tree by default. Sync fetches first and uses `origin/<dynamically-determined-default>` instead of a possibly stale local default branch. Push never happens implicitly; default-branch push requires `allow_default_branch_push: true`, and force is limited to explicit `force-with-lease`.

`tools/test-cottage-shard.ps1` was not present in this checkout, so no unsafe substitute is provided.
