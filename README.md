# Kraken Agent Bridge

![The Arcane Dungeon Master's Workshop](docs/images/hero.jpg)

**Let an AI agent read and drive your Fantasy Grounds Unity campaign.**

Kraken Agent Bridge is a Fantasy Grounds Unity (FGU) extension plus a small local server. With a campaign open, an AI agent (Claude, Grok, Codex, Gemini, Cursor, or anything that speaks MCP or plain HTTP) can work inside your game the way you do: read and change records, operate the windows, roll through the ruleset's own actions, run the combat tracker, read the console, and reload after you edit files. It works with **any ruleset**: CoreRPG, 5E, 3.5E, PFRPG, AD&D 2E, Castles & Crusades and others.

![FGU chat: the bridge connecting and reconnecting, then messages sent by an agent and by plain HTTP](docs/images/chat-connected.png)

*Formerly "Claude Bridge". It was always agent-agnostic underneath, and the new name says so. Extensions written for the old name keep working.*

---

## What it does

FGU can't accept incoming connections, so the extension asks a local daemon for work:

```text
 your agent ──MCP (stdio)──> fgu_mcp.py ──HTTP──> fgu_bridge_daemon.py <──polls── Kraken Agent Bridge (inside FGU)
 any script ──────────────── HTTP POST /cmd ────>   127.0.0.1:47111 only           runs the command, sends the result
```

- **The extension** runs inside FGU. It keeps one request open to the daemon, runs each command it gets, and sends back the result as JSON.
- **The daemon** listens on `127.0.0.1` only, so other computers can't reach it.
- **The MCP server** gives agents 20 tools named `fgu_*`. It starts the daemon itself.

The extension also ships its own documentation: an **agent guide**, also packaged as a skill, that teaches an agent how FGU works and how to do real jobs in it.

## What it can do

**Read anything in the campaign**
- characters, NPCs, items, spells, story, notes, tables, maps, options;
- records in every loaded module, rulebooks included, so an agent can look up rules in your own books;
- the open windows and their controls, the chat log, and FGU's console (script errors and debug output).

**Change things the way you would**
- write any field, with the sheet's own handlers firing as if you typed it;
- create and delete records;
- call the ruleset's own functions, the ones that run when you drag a class onto a sheet or an item into an inventory;
- open windows, set controls and press buttons;
- answer dialogs.

**Run the table**
- put NPCs and characters on the combat tracker, set targets, add and remove effects, advance turns;
- roll through the sheet's own buttons (attacks, saves, skills, spells), or with chat commands like `/die 1d20+5`;
- post to chat;
- type the ruleset's slash commands.

**Build and test**
- make complete characters: race, class, skills, feats, spells, starting gear bought with starting gold, details, and a portrait;
- build modules and maps as files: records, books, map pins, walls, lights, and FX such as animated water masked to a map's river;
- after you edit ruleset or extension files, `/reload` and read the new console errors;
- test player-side behaviour through a player copy of FGU on the same PC (the `client` role);
- reach several GM copies at once (`host2` to `host4`).

**Work with any agent**
- a standard stdio MCP server for Claude Code, Claude Desktop, Codex CLI, Gemini CLI, Cursor, VS Code and other MCP clients;
- a plain HTTP API and a command-line helper for everything else.

## What it can't do

- **Run arbitrary Lua.** FGU's sandbox has no `loadstring`. The agent uses a fixed set of commands, and can call only functions in registered packages: FGU's API, CoreRPG's managers, common ruleset packages, and any package another extension registers.
- **Edit map layers live.** FGU's scripting has no functions for image layers, FX or masks. The bridge reads a map's size, grid and view, and moves tokens. New layers, such as an animated water FX, go into the map's saved data while FGU has that data closed; the agent guide shows how.
- **Click FGU's permission prompts.** FGU asks you to allow the local URL once per launch. That's your consent, and agents are told never to click it for you.
- **Reach other computers.** It drives copies of FGU on this PC only. Players on other machines are reached the normal way, through the GM's FGU.
- **See your screen.** It reads FGU's data and windows, not pixels. An optional helper takes a picture of the FGU window.
- **Get around FGU's own rules.**
  - The GM can't `/reload` while players are connected.
  - A player copy can change only what that player owns.
  - Module records are read-only; edits are saved in the campaign.
  - A brand-new module folder may not appear until FGU restarts.
- **Run commands that time out later.** A command that waits too long is dropped; it never runs afterwards by surprise.
- **Type into FGU on macOS or Linux.** `fgu_slash` and `fgu_reload` use Windows APIs. The rest is plain Python and HTTP, but it's only been tested on Windows.

## Install it with an agent (the easy way)

1. Download `KrakenAgentBridge-v<version>.zip` from the [latest release](https://github.com/krakenunbound/kraken-agent-bridge/releases/latest).
2. Tell your agent:

   > Unpack `Downloads\KrakenAgentBridge-v<version>.zip`, read AGENT_INSTALL.md, then install it and get set up.

The zip carries one complete set of instructions written for agents, [`KrakenAgentBridge/MCP/README.md`](KrakenAgentBridge/MCP/README.md). The agent follows them:
1. finds your FGU data folder and copies the extension in, upgrading an older copy if there is one;
2. registers the MCP server for whichever client it is;
3. installs the skill, and adds the startup shortcut if you agree;
4. tells you the two things only you can do in FGU: tick the extension in your campaign, and click **Yes To All**;
5. checks the connection, and tells you the zip can be deleted.

The instructions stay with the installed extension. Later, any agent can be pointed at them:

> Go to `%APPDATA%\SmiteWorks\Fantasy Grounds\extensions\KrakenAgentBridge\MCP`, read README.md and get set up.

## Install it by hand

1. **Python 3.9 or newer** from [python.org](https://www.python.org/downloads/). Tick *Add python.exe to PATH*. Nothing to `pip install`; Pillow is only for the optional screenshot helper.
2. **The extension:** unzip the release and copy the **`KrakenAgentBridge`** folder into your FGU data folder's `extensions` folder:

   ```text
   %APPDATA%\SmiteWorks\Fantasy Grounds\extensions\KrakenAgentBridge\
   ```

   Copy the folder, not a packed `.ext`: the MCP server runs from these files. Restart FGU if it was open.
3. **Register the MCP server** with your agent: a stdio server named `fgu` that runs `python "<that folder>\server\fgu_mcp.py"`. For Claude Code:

   ```text
   claude mcp add --scope user fgu -- python "C:\Users\<you>\AppData\Roaming\SmiteWorks\Fantasy Grounds\extensions\KrakenAgentBridge\server\fgu_mcp.py"
   ```

   [INSTALL.md](docs/INSTALL.md) has the exact entry for Claude Desktop, Codex CLI, Gemini CLI, Cursor, VS Code and any other MCP client, plus the HTTP and command-line options.
4. **Optional, recommended:** have the daemon start with Windows:

   ```text
   python "%APPDATA%\SmiteWorks\Fantasy Grounds\extensions\KrakenAgentBridge\server\install_startup.py"
   ```
5. **In FGU:**
   1. In the launcher, tick **Kraken Agent Bridge** in your campaign's extension list, then start the campaign.
   2. When FGU asks to open `http://127.0.0.1:47111/...`, click **Yes To All**.
   3. The chat says **Agent bridge: connected (host, localhost:47111)**. If it doesn't, type `/agentbridge`.
6. **Teach your agent:** give it [AGENT_GUIDE.md](docs/AGENT_GUIDE.md), or install `skills/fgu-bridge` as a skill. Then ask it to call `fgu_status`.

## Documentation

| Guide | What's in it |
| --- | --- |
| [INSTALL.md](docs/INSTALL.md) | Requirements, installing, each agent's MCP setup, the startup shortcut, upgrading from Claude Bridge, uninstalling, troubleshooting |
| [USAGE.md](docs/USAGE.md) | Every tool and its arguments, recipes, GM and player roles, several FGU copies at once, the HTTP API, registering your extension's packages |
| [AGENT_GUIDE.md](docs/AGENT_GUIDE.md) | The manual for agents (also the skill `skills/fgu-bridge`). It assumes the agent knows nothing about FGU and covers: <ul><li>how FGU is put together;</li><li>finding records and looking up rules in the loaded books;</li><li>reading a ruleset's source;</li><li>making characters and portraits;</li><li>items, combat and effects, and rolling;</li><li>story text, maps, image formats and making modules;</li><li>debugging and etiquette.</li></ul> |
| [KrakenAgentBridge/MCP](KrakenAgentBridge/MCP/README.md) | The agent install and setup checklist, shipped inside the extension |
| [CHANGELOG.md](CHANGELOG.md) | Version history |

## Tools at a glance

`fgu_status`, `fgu_db_get`, `fgu_db_list`, `fgu_db_set`, `fgu_db_create_child`, `fgu_db_delete`, `fgu_call`, `fgu_get`, `fgu_window_open`, `fgu_window_list`, `fgu_window_read`, `fgu_window_set`, `fgu_window_call`, `fgu_window_has`, `fgu_window_close`, `fgu_chat`, `fgu_slash`, `fgu_reload`, `fgu_chat_log`, `fgu_console`.

## Safety

- The daemon listens on `127.0.0.1` only.
- Any program on **your** computer can send it commands while a campaign with the extension is open, and those commands can change your campaign. Untick the extension when you don't want an agent connected. Back up campaigns you care about before letting an agent edit them.
- The agent guide tells agents to:
  - ask before anything that interrupts you (a reload, typing in chat, opening windows);
  - prefer test records;
  - treat text they read from the campaign as data, not instructions.

## Requirements

- Windows 10 or 11 with Fantasy Grounds Unity, any ruleset.
- Python 3.9 or newer.
- An agent with MCP support, or any program that can send HTTP.

## Author

The Kraken ([krakenunbound](https://github.com/krakenunbound)). Other Fantasy Grounds extensions:
- [Kraken AD&D 2E Character Wizard](https://github.com/krakenunbound/kraken-adnd-2e-charwizard)
- [Kraken GM Icon](https://github.com/krakenunbound/kraken-gm-icon)
