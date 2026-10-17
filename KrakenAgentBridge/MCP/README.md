# Kraken Agent Bridge: install and setup, for agents (start here)

You are an AI agent, and the user wants Kraken Agent Bridge installed and you connected to Fantasy Grounds Unity (FGU). This one document covers everything, from a downloaded zip to a working connection. Work through the steps in order: do what you can yourself, and ask the user for the steps marked **(user)**. Tell the user before you change anything outside the folders named here.

When you're done you'll have the `fgu_*` tools (`fgu_status`, `fgu_db_get`, `fgu_call`, `fgu_window_read`, `fgu_reload`, ...) and can read and drive the user's running campaign, in any ruleset.

| File (in this `MCP` folder) | What it is |
| --- | --- |
| `README.md` | This install and setup checklist |
| `AGENT_GUIDE.md` | How to use the bridge once connected: tools, recipes, roles, rules. Read it after setup. |
| `USAGE.md` | Full reference: every tool's arguments, the HTTP API, registering packages |
| `skill/fgu-bridge/SKILL.md` | The guide as a skill, for clients that support skills |

## The paths you need

- **`<data>`** is the user's FGU data folder. It's normally `%APPDATA%\SmiteWorks\Fantasy Grounds`, and it holds `campaigns`, `rulesets` and `extensions` folders. If that folder doesn't exist or lacks them, ask the user where theirs is: the FGU launcher shows it under **Settings > Data Folder**.
- **`<bridge>`** is `<data>\extensions\KrakenAgentBridge`, the installed extension. It contains this `MCP` folder.
- **`<python>`** is the full path to Python (step 1).

Always use real, expanded paths, such as `C:\Users\<name>\AppData\Roaming\SmiteWorks\Fantasy Grounds`. Clients don't expand `%APPDATA%`. If `<data>` isn't the default, also set the environment variable `FGU_DATA_FOLDER=<data>` in the server entry (step 2), so `fgu_console` can find `console.log`.

The MCP server is `<bridge>\server\fgu_mcp.py`.

## 0. Install the extension (skip if this file is already inside `<data>\extensions\KrakenAgentBridge\MCP`)

You're reading this from a download: a zip, or the folder it was unpacked to.

1. **Unpack** the zip (`KrakenAgentBridge-v<version>.zip`) if it isn't unpacked yet, for example to a folder next to it. It contains a `KrakenAgentBridge` folder (`extension.xml`, `scripts`, `server`, `tools`, `MCP`), plus `README.md`, `CHANGELOG.md`, `docs` and `skills` for people.
2. **Check what's already installed:**
   - If `<bridge>` exists, this is an **upgrade**. Read its `extension.xml` version and tell the user what you're replacing.
   - If `<data>\extensions\ClaudeBridge` exists, that's the old name of the same bridge. Leave it alone for now: step 8 covers it.
3. **Copy** the whole `KrakenAgentBridge` folder into `<data>\extensions\`, merging over any existing copy. For example, in PowerShell:

   ```powershell
   Copy-Item -Recurse -Force "<unpacked>\KrakenAgentBridge" "<data>\extensions\"
   ```

   Then check `<data>\extensions\KrakenAgentBridge\extension.xml` exists. Watch out for `KrakenAgentBridge\KrakenAgentBridge\`: if you see it, fix it.

   Copy the **folder**, never a packed `.ext`, because the MCP server runs from these files.

   When upgrading, a running daemon keeps its old code until it restarts. Find it by its command line (`fgu_bridge_daemon.py`), stop **only that process**, and the next tool call starts the new one. Never stop every Python process: other tools run in Python too.
4. **(user)** If FGU is open, the user restarts it so the launcher lists the extension.
5. From here on, use the installed copy, `<bridge>\MCP`, not the download.

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

## 8. Moving off the old Claude Bridge (only if `<data>\extensions\ClaudeBridge` exists)

It's the same bridge under its old name, using the same port and protocol. With the user's OK:
1. In each campaign, untick **Claude Bridge** and tick **Kraken Agent Bridge**. **Never leave both ticked**: both would poll.

   Each campaign lists its extensions in `<data>\campaigns\<campaign>\extensionstate.xml`. You can swap `<extension name="ClaudeBridge" />` for `<extension name="KrakenAgentBridge" />` there while that campaign isn't open, after backing the file up. If it already lists KrakenAgentBridge, just remove the ClaudeBridge line.
2. Repoint any agent server that runs `ClaudeBridge\server\fgu_mcp.py` to `<bridge>\server\fgu_mcp.py`.
3. Rerun `install_startup.py` (step 4). It removes the old "Claude Bridge daemon" shortcut.
4. When nothing points at it any more, the user can delete or archive `<data>\extensions\ClaudeBridge`. Extensions that call `ClaudeBridge.registerPackage` keep working.

## 9. Clean up and report

- Tell the user the downloaded zip and its unpacked folder are no longer needed and can be deleted. Everything now lives in `<bridge>`. Delete them only if they ask you to.
- Give the user a short summary:
  - the bridge version and where it's installed;
  - which client you registered `fgu` with;
  - whether the skill and the startup shortcut are installed;
  - whether `fgu_status` connected, and anything they still have to do (restart your client, tick the extension, Yes To All).

## Uninstall

1. Untick the extension in each campaign.
2. Run `"<python>" "<bridge>\server\install_startup.py" --remove`.
3. Remove the `fgu` server from your client, and the skill if you installed it.
4. Delete `<bridge>`.

## Troubleshooting

| Symptom | Fix |
| --- | --- |
| No `fgu_*` tools after registering | Restart the client or start a new session. Check the command is a full python path and the argument is the right `fgu_mcp.py`. |
| `fgu_status` never connects | Campaign not open, extension not ticked, or Yes To All not clicked (step 6). After a daemon restart, the user types `/agentbridge`. |
| Port 47111 in use | Another program owns the port; the bridge needs it. |
| `fgu_console` can't find the log | Set `FGU_DATA_FOLDER` to the FGU data folder in the server's environment. |
| Upgrading from Claude Bridge | Step 8. |
| Upgraded, but the tools still behave like the old version | The daemon or MCP server is still the old process. Stop the process running `fgu_bridge_daemon.py` (only that one), and restart your client. |
