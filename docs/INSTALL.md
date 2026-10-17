# Install Guide

## 1. What you need

- **Windows 10 or 11** with Fantasy Grounds Unity.
- **Python 3.9 or newer** from [python.org](https://www.python.org/downloads/). During setup, tick *Add python.exe to PATH*. Check it in a terminal:

  ```text
  python --version
  ```

  The bridge uses only Python's standard library, so there's nothing to `pip install`. The optional screenshot helper needs Pillow (`python -m pip install pillow`).
- **An agent**, if you want one: any MCP client (section 4), or anything that can send HTTP (section 5).

## 2. Install the extension

1. Download `KrakenAgentBridge-v<version>.zip` from the [latest release](https://github.com/krakenunbound/kraken-agent-bridge/releases/latest) and unzip it.
2. Copy the **`KrakenAgentBridge`** folder into your Fantasy Grounds **data folder**'s `extensions` folder:

   ```text
   %APPDATA%\SmiteWorks\Fantasy Grounds\extensions\KrakenAgentBridge\
     extension.xml
     scripts\bridge.lua
     scripts\compat_claudebridge.lua
     MCP\README.md            (agent setup checklist, plus AGENT_GUIDE.md, USAGE.md, skill\)
     server\fgu_bridge_daemon.py
     server\fgu_mcp.py
     server\install_startup.py
     tools\fgu.py
     tools\fgshot.py
   ```

   Not sure where your data folder is? In the FGU launcher, open **Settings** and look at **Data Folder**. Make sure you don't end up with `extensions\KrakenAgentBridge\KrakenAgentBridge\`.

   Use the folder, not a packed `.ext`: your agent's MCP setup points at `server\fgu_mcp.py` inside this folder.
3. If FGU was open, restart it so the launcher lists the new extension.

## 3. Turn it on in a campaign

1. In the FGU launcher, select your campaign and tick **Kraken Agent Bridge** in its extension list. It works with any ruleset.
2. Start the campaign.
3. When FGU shows **Open URL** for `http://127.0.0.1:47111/poll...`, click **Yes To All**. FGU asks once per launch.
4. The chat shows **Agent bridge: connected (host, localhost:47111)** once the daemon is running. Your agent starts the daemon itself the first time it uses the bridge, and section 6 makes it start with Windows.

If the chat says nothing, type `/agentbridge` after the daemon is up to reconnect.

## 4. Connect your agent (MCP)

**The short way:** an agent that can run commands can do this section itself. Tell it: *Go to `%APPDATA%\SmiteWorks\Fantasy Grounds\extensions\KrakenAgentBridge\MCP`, read README.md, install and get set up.* The rest of this section is the same setup by hand.

Every MCP client needs the same thing: a **stdio** server named `fgu` that runs:

```text
python  "C:\Users\<you>\AppData\Roaming\SmiteWorks\Fantasy Grounds\extensions\KrakenAgentBridge\server\fgu_mcp.py"
```

Replace the path with yours. In JSON files, double each backslash (`\\`) or use forward slashes. If your FGU data folder isn't in `%APPDATA%`, also set the environment variable `FGU_DATA_FOLDER` to it; it's used to read `console.log`.

### Claude Code

```text
claude mcp add --scope user fgu -- python "C:\Users\<you>\AppData\Roaming\SmiteWorks\Fantasy Grounds\extensions\KrakenAgentBridge\server\fgu_mcp.py"
```

### Claude Desktop

Edit `%APPDATA%\Claude\claude_desktop_config.json` and add the server, keeping any others you already have:

```json
{
  "mcpServers": {
    "fgu": {
      "command": "python",
      "args": ["C:/Users/<you>/AppData/Roaming/SmiteWorks/Fantasy Grounds/extensions/KrakenAgentBridge/server/fgu_mcp.py"]
    }
  }
}
```

Restart Claude Desktop.

### OpenAI Codex CLI

Add to `%USERPROFILE%\.codex\config.toml`:

```toml
[mcp_servers.fgu]
command = "python"
args = ["C:/Users/<you>/AppData/Roaming/SmiteWorks/Fantasy Grounds/extensions/KrakenAgentBridge/server/fgu_mcp.py"]
```

Or for one run only, without changing the file:

```text
codex exec -c "mcp_servers.fgu.command=\"python\"" -c "mcp_servers.fgu.args=[\"C:/Users/<you>/.../server/fgu_mcp.py\"]" "Call fgu_status"
```

### Gemini CLI

Add to `%USERPROFILE%\.gemini\settings.json`, or to `.gemini\settings.json` in a project folder:

```json
{
  "mcpServers": {
    "fgu": {
      "command": "python",
      "args": ["C:/Users/<you>/AppData/Roaming/SmiteWorks/Fantasy Grounds/extensions/KrakenAgentBridge/server/fgu_mcp.py"]
    }
  }
}
```

### Cursor

Add to `%USERPROFILE%\.cursor\mcp.json`, or to `.cursor\mcp.json` in a project:

```json
{
  "mcpServers": {
    "fgu": {
      "command": "python",
      "args": ["C:/Users/<you>/AppData/Roaming/SmiteWorks/Fantasy Grounds/extensions/KrakenAgentBridge/server/fgu_mcp.py"]
    }
  }
}
```

### VS Code (Copilot agent mode)

Add to `.vscode\mcp.json` in your workspace, or to your user MCP configuration:

```json
{
  "servers": {
    "fgu": {
      "type": "stdio",
      "command": "python",
      "args": ["C:/Users/<you>/AppData/Roaming/SmiteWorks/Fantasy Grounds/extensions/KrakenAgentBridge/server/fgu_mcp.py"]
    }
  }
}
```

### Any other MCP client

Use the same three facts: transport **stdio**, command **`python`**, argument **the path to `fgu_mcp.py`**. The server speaks plain JSON-RPC MCP and lists 20 tools named `fgu_*`.

### Teach the agent the bridge

Give your agent [AGENT_GUIDE.md](AGENT_GUIDE.md): paste it into your project's `AGENTS.md`, `CLAUDE.md` or `GEMINI.md`, or install `skills/fgu-bridge` as a skill if your agent supports skills. It explains the first steps, the tools and the pitfalls.

## 5. Without MCP: HTTP and the command line

Any program can drive the bridge.

**HTTP.** The daemon must be running. Start it once with `python server\fgu_bridge_daemon.py`, or see section 6.

```text
curl -s http://127.0.0.1:47111/status
curl -s -X POST http://127.0.0.1:47111/cmd -d "{\"cmd\":\"ping\"}"
curl -s -X POST http://127.0.0.1:47111/cmd -d "{\"cmd\":\"db_get\",\"args\":{\"path\":\"charsheet\"},\"timeout\":15}"
```

**Command line.** The same tools the MCP server offers, from any shell. This also starts the daemon if needed:

```text
python tools\fgu.py fgu_status
python tools\fgu.py fgu_db_list "{\"path\":\"charsheet\"}"
```

The HTTP API is described in [USAGE.md](USAGE.md#http-api).

## 6. Start the daemon with Windows (recommended)

The extension connects only while the daemon runs. An agent's MCP server starts it on demand, but if you open FGU first, the extension may wait until you type `/agentbridge`. To have it running from log-in:

```text
python "%APPDATA%\SmiteWorks\Fantasy Grounds\extensions\KrakenAgentBridge\server\install_startup.py"
```

This adds **Kraken Agent Bridge daemon** to your Startup folder (`shell:startup`). It runs the daemon with `pythonw.exe`, so no window opens. Run it with `--status` to check, or `--remove` to take it out. Only one daemon ever runs: a second copy finds port 47111 taken and exits.

## 7. Check it works

1. FGU's chat shows **Agent bridge: connected (host, localhost:47111)**.
2. `curl -s http://127.0.0.1:47111/status` shows `"connected": true`.
3. Ask your agent to call `fgu_status`. It reports the ruleset, the campaign folder and the packages it can call.

## 8. Upgrading from Claude Bridge

Kraken Agent Bridge is the same bridge under a new name, using the same port, protocol and tool names.

1. Install `KrakenAgentBridge` as above. You can delete the old `extensions\ClaudeBridge` folder once nothing points at it.
2. In each campaign, untick **Claude Bridge** and tick **Kraken Agent Bridge**. **Don't enable both** in one campaign: both would poll, and both define the `ClaudeBridge` package.
3. Point your agent's `fgu` MCP server at `KrakenAgentBridge\server\fgu_mcp.py`. In Claude Code: `claude mcp remove fgu --scope user`, then add it again as in section 4.
4. Rerun `install_startup.py` from the new folder. It replaces the old *Claude Bridge daemon* shortcut.
5. Extensions that call `ClaudeBridge.registerPackage(...)` keep working, and `/claudebridge` still reconnects.

## 9. Uninstall

1. Untick the extension in your campaigns.
2. Run `python server\install_startup.py --remove`.
3. Remove the `fgu` server from your agent's MCP settings.
4. Delete the `KrakenAgentBridge` folder.

## 10. Troubleshooting

| Symptom | Fix |
| --- | --- |
| Chat never says *connected* | Is the daemon running? Check `curl http://127.0.0.1:47111/status`. Start it (section 5 or 6), then type `/agentbridge`. |
| No *Open URL* prompt, and no connection | You may have clicked **No** earlier. Restart FGU and click **Yes To All**. |
| Agent says "No host Fantasy Grounds instance is polling" | Campaign not open, extension not ticked, or the URL not allowed. Type `/agentbridge`. |
| `fgu_slash` or `fgu_reload` refuses | It types into the FGU window and only does so while that copy's bridge is connected. Reconnect first. Windows only. |
| "Unable to reload when players are connected" | FGU blocks `/reload` while players are connected. Disconnect them, reload, and let them rejoin. |
| Port 47111 in use by something else | Another program owns the port. The bridge needs it; close that program. |
| `fgu_console` finds no log | Your data folder isn't in `%APPDATA%`. Set `FGU_DATA_FOLDER` for the MCP server. |
| Two campaigns open at once | Each GM copy gets its own channel (`host`, `host2`...). Its chat line names it; pass `"role": "host2"` to reach that copy. |
