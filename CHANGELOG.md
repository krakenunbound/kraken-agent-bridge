# Changelog

## v1.0.3 (2026-10-17)

- **Install with an agent from the download.** Tell your agent: *Unpack `KrakenAgentBridge-v1.0.3.zip`, read AGENT_INSTALL.md, then install it and get set up.*
  - `AGENT_INSTALL.md` sits at the top of the zip.
  - `KrakenAgentBridge/MCP/README.md` is now the one complete document for agents. Its new step 0 finds the FGU data folder, copies the extension in, and handles upgrades (including restarting only the bridge's own daemon). It then sets the agent up, turns the bridge on in a campaign, and verifies.
  - New steps: moving off the old Claude Bridge, cleanup (tell the user the download can be deleted, then a summary), and uninstall.
- **The agent guide and skill are now a full manual** (patched into v1.0.3 the same day). They assume the agent knows nothing about Fantasy Grounds and cover: how FGU is put together, the database and modules, finding anything, looking up rules in the loaded books, reading a ruleset's source, making and levelling characters, items, combat and effects, rolling through the sheet, windows, story and tables, maps, making modules, debugging, and etiquette. Every API it names was checked against CoreRPG and a live campaign.
- **Image formats for agents that build assets:** convert maps, handouts and portraits to WebP before use; tokens PNG or WebP with transparency; module covers must be `thumbnail.png`. Includes a tested Pillow snippet and a `cwebp` line.
- **Lessons from a real build** (Grok making a 3.5e wizard), patched in the same day:
  - a character build order and checklist (scores before race and class, skill specialties, spell level nodes, starting gold, verify on the open sheet);
  - portraits the way FGU's picker does it (`Interface.refreshAssets`, `User.getPortraitFileList`, `CampaignDataManager.setCharPortrait`);
  - maps straight into a campaign (`CampaignDataManager.createImageRecordFromAsset`);
  - finding a module's real record paths (`reference.spells`... in rulebooks), link classes, Lua's truthiness;
  - sequential calls, field types, UTF-8 without a BOM.
  - `RecordManager` and `RecordAssetManager` are now registered (from FGU's next start).
- **`fgu_get` takes `fns`:** which of the named functions a package has, without calling any. FGU packages can't be listed from Lua, so `listPackageFunctions` only ever worked on plain tables. `fgu_get` also returns a field's type.

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
