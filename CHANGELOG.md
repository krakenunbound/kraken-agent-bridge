# Changelog

## v1.0.2 (2026-10-17)

- **Agent setup folder:** `KrakenAgentBridge\MCP` ships inside the extension.
  - Its `README.md` is a step-by-step checklist written for agents: check Python, register the `fgu` MCP server for whichever client the agent is (Claude Code, Codex, Gemini, Cursor, Claude Desktop, VS Code, or none), install the skill, add the startup shortcut, then the steps only the user can do in FGU, and verify.
  - It also holds `AGENT_GUIDE.md`, `USAGE.md` and the skill, copied from `docs/` by `release.py`, so they stay in step.
  - Tell your agent: *Go to `%APPDATA%\SmiteWorks\Fantasy Grounds\extensions\KrakenAgentBridge\MCP`, read README.md, install and get set up.*
- **Agent guide:** an agent without the `fgu_*` tools is pointed at that folder to set itself up.

## v1.0.1 (2026-10-17)

Clearer connection help for agents.

- **`fgu_status` says how to connect.** When FGU isn't polling, its result has a `how_to_connect` list: open the campaign with the extension ticked, click **Yes To All**, or type `/agentbridge`.
- **Fuller MCP instructions.** Agents get the connection steps, the first calls to make and the roles when they connect, before reading any guide.
- **Timeout messages** tell the agent what to ask the user, then to call `fgu_status` again.
- **Agent guide and skill:** a new *Connecting* section, including what to do when the `fgu_*` tools are missing (register the MCP server, or use the command line or HTTP meanwhile).
- README screenshot from a real session.

## v1.0 (2026-10-17)

First public release, under a new name: **Kraken Agent Bridge**. It was "Claude Bridge" 0.5 and used privately. It was never tied to one AI; the name now says so.

- **Works with any agent.**
  - A standard stdio MCP server for any MCP client: Claude Code, Claude Desktop, Codex CLI, Gemini CLI, Cursor, VS Code and others.
  - The HTTP API and a command-line helper for agents and scripts without MCP.
  - The install guide covers each client.
- **New names**, with the same port (47111), protocol and tool names:
  - extension: *Kraken Agent Bridge* (folder `KrakenAgentBridge`);
  - Lua package: `AgentBridge`;
  - chat command: `/agentbridge`, and chat lines say "Agent bridge: ...";
  - MCP server info: `kraken-agent-bridge`;
  - startup shortcut: "Kraken Agent Bridge daemon".
- **The old name still works.** Extensions written for it can still call `ClaudeBridge.registerPackage`, and `/claudebridge` still reconnects. Running `install_startup.py` replaces the old startup shortcut.
- **New tool `fgu_window_has`:** which functions a window or control defines, without calling them.
- **Fix:** a command that reached the extension on its previous poll, just after a reconnect (`/agentbridge`), was dropped and its caller timed out. It now runs.
- **Fix:** two tools declared their `role` argument twice, which strict MCP clients can reject.
- **Docs:** README, INSTALL, USAGE (tools, recipes, roles, HTTP API, registering packages), AGENT_GUIDE, and an agent skill (`skills/fgu-bridge`).

### Before v1.0 (as Claude Bridge)

- **0.5:** one channel per GM copy of FGU (`host`, `host2`...), so several campaigns can be open at once.
- **0.4:**
  - Reconnects by itself when the daemon starts late.
  - The daemon owns its port exclusively.
  - Timed-out commands are dropped.
- **Earlier:**
  - database, window, package-call and chat commands;
  - host and player-client roles;
  - `/reload` and chat commands typed without taking focus;
  - results sent in parts.
