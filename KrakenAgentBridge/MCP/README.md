# Kraken Agent Bridge: agent setup (start here)

You are an AI agent, and the user wants you connected to Fantasy Grounds Unity (FGU). This folder has everything you need. Work through the steps in order: do what you can yourself, and ask the user for the steps marked **(user)**.

When you're done you'll have the `fgu_*` tools (`fgu_status`, `fgu_db_get`, `fgu_call`, `fgu_window_read`, `fgu_reload`, ...) and can read and drive the user's running campaign, in any ruleset.

| File | What it is |
| --- | --- |
| `README.md` | This setup checklist |
| `AGENT_GUIDE.md` | How to use the bridge once connected: tools, recipes, roles, rules. Read it after setup. |
| `USAGE.md` | Full reference: every tool's arguments, the HTTP API, registering packages |
| `skill/fgu-bridge/SKILL.md` | The guide as a skill, for clients that support skills |

## The paths you need

This folder is `<bridge>\MCP`, where `<bridge>` is the extension folder, normally:

```text
%APPDATA%\SmiteWorks\Fantasy Grounds\extensions\KrakenAgentBridge
```

Use the real, expanded path (for example `C:\Users\<name>\AppData\Roaming\SmiteWorks\Fantasy Grounds\extensions\KrakenAgentBridge`). Clients don't expand `%APPDATA%`. If the folder is somewhere else, the user's FGU data folder is elsewhere: use that location, and set the environment variable `FGU_DATA_FOLDER` to the data folder in the server entry (step 2) so `fgu_console` can find `console.log`.

The MCP server is `<bridge>\server\fgu_mcp.py`.

## 1. Check Python

```text
python --version
python -c "import sys; print(sys.executable)"
```

You need Python 3.9 or newer. The bridge uses only the standard library, so there's nothing to install. Use the **full path** that the second command prints as the server command. Desktop apps often don't have the user's PATH. If Python is missing, ask the user to install it from python.org with *Add python.exe to PATH* ticked.

## 2. Register the MCP server

You need a **stdio** server named **`fgu`**, with command `<python>` and argument `<bridge>\server\fgu_mcp.py`. First check whether one called `fgu` already exists. If it does, check that it points at this folder and fix it if it doesn't.

Use the entry for your client. In JSON, write paths with forward slashes, or double the backslashes.

**Claude Code**

```text
claude mcp add --scope user fgu -- "<python>" "<bridge>\server\fgu_mcp.py"
claude mcp get fgu
```

**OpenAI Codex CLI**: add to `%USERPROFILE%\.codex\config.toml`:

```toml
[mcp_servers.fgu]
command = 'C:\path\to\python.exe'
args = ['C:\Users\<name>\AppData\Roaming\SmiteWorks\Fantasy Grounds\extensions\KrakenAgentBridge\server\fgu_mcp.py']
```

(TOML single quotes keep backslashes as they are.)

**Gemini CLI** (`%USERPROFILE%\.gemini\settings.json`), **Cursor** (`%USERPROFILE%\.cursor\mcp.json`), **Claude Desktop** (`%APPDATA%\Claude\claude_desktop_config.json`): merge this into the file, keeping any other servers:

```json
{
  "mcpServers": {
    "fgu": {
      "command": "C:/path/to/python.exe",
      "args": ["C:/Users/<name>/AppData/Roaming/SmiteWorks/Fantasy Grounds/extensions/KrakenAgentBridge/server/fgu_mcp.py"]
    }
  }
}
```

**VS Code** (`.vscode\mcp.json` or the user MCP configuration): the same, but under `"servers"` and with `"type": "stdio"`.

**Any other MCP client:** transport stdio, the command and argument above. The server speaks plain JSON-RPC MCP and lists 20 tools.

**No MCP at all:** skip this step. Run the same tools from a shell with `"<python>" "<bridge>\tools\fgu.py" <tool> "<json args>"` (for example `fgu_status`), or use HTTP on `http://127.0.0.1:47111`, described in `USAGE.md`.

## 3. Install the skill (if your client has skills)

Copy `skill\fgu-bridge` into your skills folder, for example:
- Claude Code: `%USERPROFILE%\.claude\skills\fgu-bridge\SKILL.md`
- Codex: `%USERPROFILE%\.codex\skills\fgu-bridge\SKILL.md`

Without skills, add `AGENT_GUIDE.md` (or a pointer to it) to the user's project instructions, such as `AGENTS.md`, `CLAUDE.md` or `GEMINI.md`, if the user agrees.

## 4. Start the daemon with Windows (recommended, ask first)

The FGU extension connects only while the local daemon runs. The MCP server starts it on demand, but if FGU opens first it waits until the user types `/agentbridge`. With the user's OK, run:

```text
"<python>" "<bridge>\server\install_startup.py"
```

This adds a "Kraken Agent Bridge daemon" shortcut to the user's Startup folder and starts the daemon. `--status` checks it and `--remove` undoes it. Only one daemon ever runs.

## 5. Reload your tools

Most clients load MCP servers at startup, so you may need a restart or a new session before the `fgu_*` tools appear. Tell the user if so. Until then you can use `tools\fgu.py` from step 2.

## 6. Turn the bridge on in a campaign (user)

Ask the user to:
1. In the FGU launcher, select the campaign and tick **Kraken Agent Bridge** in its extension list. If FGU was running when the extension was installed, they need to restart FGU first so the launcher lists it.
2. Start the campaign.
3. When FGU shows **Open URL** for `http://127.0.0.1:47111/poll...`, click **Yes To All**. FGU asks once per launch. This is the user's consent: never click it for them.
4. FGU's chat should say **Agent bridge: connected (host, localhost:47111)**. If it says nothing, or says *reconnecting*, type `/agentbridge` in chat.

## 7. Verify

Call `fgu_status`. You should see `"connected": true`, the ruleset, the campaign folder and the packages you can call. If it isn't connected, its `how_to_connect` list says what's missing. Go through it with the user, then call `fgu_status` again.

Then read `AGENT_GUIDE.md` before you change anything in the campaign.

## Troubleshooting

| Symptom | Fix |
| --- | --- |
| No `fgu_*` tools after registering | Restart the client or start a new session. Check the command is a full python path and the argument is the right `fgu_mcp.py`. |
| `fgu_status` never connects | Campaign not open, extension not ticked, or Yes To All not clicked (step 6). After a daemon restart, the user types `/agentbridge`. |
| Port 47111 in use | Another program owns the port; the bridge needs it. |
| `fgu_console` can't find the log | Set `FGU_DATA_FOLDER` to the FGU data folder in the server's environment. |
| Upgrading from Claude Bridge | Point the `fgu` server at this folder's `server\fgu_mcp.py`. In each campaign, untick Claude Bridge and tick Kraken Agent Bridge, never both. Rerun `install_startup.py`. |
