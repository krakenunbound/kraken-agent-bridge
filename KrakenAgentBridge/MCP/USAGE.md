# Usage Guide

Install first: [INSTALL.md](INSTALL.md). This guide covers what the bridge can do and how to call it, through MCP tools (any MCP agent), the command line (`tools\fgu.py`), or plain HTTP.

## The tools

Every tool takes an optional `role` (see [Roles](#roles-gm-players-and-several-copies)). The default is `host`, the GM.

| Tool | Arguments | What it does |
| --- | --- | --- |
| `fgu_status` | | Whether FGU is polling, the ruleset, campaign folder, channels, and the packages each copy can call. **Call it first.** Starts the daemon if needed. |
| `fgu_db_get` | `path`, `depth` (2), `max` (500) | Read a node or value: `charsheet`, `charsheet.id-00001`, `combattracker.list`, `options`, `npc.id-00003@Module Name`. Subtrees go `depth` levels down. |
| `fgu_db_list` | `path` | The children of a node, with each one's `name` field. Use it to find ids. |
| `fgu_db_set` | `path`, `type`, `value` | Write a value (`number`, `string`, `formattedtext`). Fires the same handlers as typing on a sheet. |
| `fgu_db_create_child` | `path`, `name`?, `type`? | Create a node. Without `name`, FGU assigns an id. Returns the path. |
| `fgu_db_delete` | `path` | Delete a node and everything under it. |
| `fgu_call` | `package`, `fn`, `args` ([]), `timeout` (30) | Call `package.fn(args...)` inside FGU: `CombatRecordManager.onRecordTypeEvent`, `OptionsManager.setOption`, a ruleset's own packages. Only registered packages are reachable; `fgu_status` lists them. |
| `fgu_get` | `package`, `field` | Read a non-function field of a package, e.g. `DataCommon.abilities`. |
| `fgu_window_open` | `class`, `path` | Open a window: class `charsheet`, path `charsheet.id-00001`. |
| `fgu_window_list` | | The open windows (class and path). |
| `fgu_window_read` | `class`, `path`, `sub`, `row` / `list_control` + `row_index` / `list_path` | A window's controls: name, visible, value, subwindow class, list rows and their paths. |
| `fgu_window_set` | the same, plus `control`, `value` | Set a control's value as if typed. Its scripts run. |
| `fgu_window_call` | the same, plus `control`?, `fn`, `args` | Call a function on a window or control. `fn: "onButtonPress"` presses a button. |
| `fgu_window_has` | the same, plus `control`?, `fns` | Which of the named functions a window or control defines, without calling any. Useful when a ruleset's source can't be read. |
| `fgu_window_close` | `class`, `path` | Close a window. |
| `fgu_chat` | `text` | Post a system message in chat. |
| `fgu_slash` | `command` | Type a chat line into FGU: `/die 1d20+3`, `/reload`, a ruleset's own commands. Posts keystrokes to that FGU window without taking focus. Windows only. |
| `fgu_reload` | `wait` (90) | `/reload` the ruleset and extensions, wait for the bridge to reconnect, and return new console errors. Use it after editing files. |
| `fgu_chat_log` | `lines` (20) | The last chat lines, read from the campaign's `chatlog.html`. |
| `fgu_console` | `lines` (60), `errors_only`, `contains`, `since_marker` | The tail of FGU's `console.log`: script errors, `Debug.console` output. Works even when FGU is closed. |

### Special argument values

Inside `args` (for `fgu_call` and `fgu_window_call`), these JSON objects become Fantasy Grounds values:

| JSON | Becomes |
| --- | --- |
| `{"$node": "charsheet.id-00001"}` | a database node |
| `{"$actor": "combattracker.list.id-00002"}` | a CoreRPG actor (`ActorManager.resolveActor`) |
| `{"$nil": true}` | `nil` (use `false` for a leading `draginfo` you don't need) |
| `{"$shortcut": {"class": "npc", "path": "npc.id-00004@Bestiary"}}` | a drag-like shortcut object |

Nodes in results come back as `{"$node": "path"}`, dice as `{"$dice": "2d6"}`, links as `{"$link": {"class": ..., "record": ...}}`. Module records end in `@<module name>`.

### Windows: finding controls and rows

- `sub: ["main", "abilities"]` walks into subwindows, by control name.
- `row: "charsheet.id-00001.weaponlist.id-00002"` picks a list row by its database path, found anywhere in the window.
- `list_control: "list", row_index: 3` picks the 3rd row of a list control (1-based). `list_path` chains several such steps through nested lists.
- `fgu_window_read` shows names, values and rows, so read before you set or call.

## Recipes

```text
Who is in the campaign:      fgu_db_list   {"path": "charsheet"}
Read a character:            fgu_db_get    {"path": "charsheet.id-00001", "depth": 3}
Put an NPC on the tracker:   fgu_call      {"package": "CombatRecordManager", "fn": "onRecordTypeEvent",
                                            "args": ["npc", {"sRecord": "npc.id-00005@Bestiary"}]}
Add a PC to the tracker:     the same with "charsheet" and "charsheet.id-00001"
Target something (GM):       fgu_call      {"package": "TargetingManager", "fn": "addCTTarget",
                                            "args": [{"$node": "<source CT path>"}, {"$node": "<target CT path>"}]}
Roll a plain die:            fgu_slash     {"command": "/die 1d20+3"}
Press a sheet button:        fgu_window_call {"class": "charsheet", "path": "charsheet.id-00001",
                                              "sub": ["main"], "control": "<button>", "fn": "onButtonPress"}
Set an option:               fgu_call      {"package": "OptionsManager", "fn": "setOption", "args": ["<option key>", "<value>"]}
What just happened:          fgu_chat_log  {"lines": 10}   then   fgu_console {"errors_only": true}
After editing Lua or XML:    fgu_reload    then check its console_errors
```

## Roles: GM, players and several copies

| Role | Who |
| --- | --- |
| `host` | The GM's copy of FGU (default) |
| `host2`, `host3`, `host4` | More GM copies on the same PC, each with another campaign open. The first live copy keeps `host`; each extra copy's chat names its channel ("Agent bridge: connected (host2, ...)"). `fgu_status` lists the live ones. |
| `client` | A player copy of FGU on the same PC, joined to the game. It can only change what that player owns, like a real player, so use it to test player-side behaviour. That copy shows its own allow-URL prompt. |

The bridge reaches copies of FGU on **this** computer only; it never connects to a player's computer.

## Things to know

- **Back up first.** Agents change real campaign data. Use test characters and a test campaign for experiments.
- **`fgu_slash` and `fgu_reload` type into the FGU window.** They refuse unless that copy's bridge is connected: the bridge focuses the chat box first, because keystrokes go wherever focus is.
- **The GM can't `/reload` while players are connected.** That's FGU's rule.
- **Players can't write the combat tracker or other players' records.** Result handlers run on the machine that rolled.
- **Don't delete list nodes that an open window shows,** such as `combattracker.list`. The window keeps the old binding until a reload.
- **Big results come back in parts** and are joined for you. `fgu_db_get` caps a read at `max` nodes.
- **A command that times out is dropped.** It never runs later on an FGU that connects afterwards.

## Reaching your own packages (extension and ruleset authors)

The bridge can call only packages it knows about: FGU's API, CoreRPG's managers, and a list of common ruleset and extension packages (registered when present). To make your own package callable, register it from your extension or ruleset, for example in an `onInit`:

```lua
function onInit()
	if AgentBridge then
		AgentBridge.registerPackage("MyManager", MyManager);
	end
end
```

`ClaudeBridge.registerPackage` (the old name) works too. Registering costs nothing when the bridge isn't loaded: the `if` skips it.

`AgentBridge.listPackageFunctions("MyManager")` lists a package's functions without reading its source.

## HTTP API

The daemon (`server\fgu_bridge_daemon.py`) listens on `http://127.0.0.1:47111` only. Any program can use it while the daemon runs; the MCP server and `tools\fgu.py` are thin layers over it.

### Send a command

```text
POST /cmd
{"cmd": "<command>", "args": {...}, "timeout": 30, "role": "host"}
```

The reply is JSON, either `{"ok": true, "data": ...}` or `{"ok": false, "error": "..."}`. A timeout says whether FGU is polling at all.

| `cmd` | `args` | Matches tool |
| --- | --- | --- |
| `ping` | | (part of `fgu_status`) |
| `db_get` | `path`, `depth`, `max` | `fgu_db_get` |
| `db_list` | `path` | `fgu_db_list` |
| `db_set` | `path`, `type`, `value` | `fgu_db_set` |
| `db_create_child` | `path`, `name`, `type` | `fgu_db_create_child` |
| `db_delete` | `path` | `fgu_db_delete` |
| `call` | `package`, `fn`, `args` | `fgu_call` |
| `get` | `package`, `field` | `fgu_get` |
| `window_open`, `window_close`, `window_list`, `window_read`, `window_set`, `window_call`, `window_has` | as the tools | `fgu_window_*` |
| `chat` | `text` | `fgu_chat` |

`fgu_slash`, `fgu_reload`, `fgu_chat_log` and `fgu_console` are done by the MCP server on your PC (keystrokes and log files), not by FGU. Use `tools\fgu.py` for those, or read the files yourself.

### Status

```text
GET /status
```

Returns `connected`, `seconds_since_poll`, the host copy's `fg` details (ruleset, campaign folder, version), and a `roles` map with every channel.

### Python example

```python
import json, urllib.request

def bridge(cmd, args=None, timeout=30, role="host"):
    body = json.dumps({"cmd": cmd, "args": args or {}, "timeout": timeout, "role": role}).encode()
    req = urllib.request.Request("http://127.0.0.1:47111/cmd", data=body, method="POST")
    with urllib.request.urlopen(req, timeout=timeout + 10) as r:
        return json.load(r)

print(bridge("db_list", {"path": "charsheet"}))
print(bridge("call", {"package": "ChatManager", "fn": "SystemMessage", "args": ["Hello from Python"]}))
```

## Command-line helpers

```text
python tools\fgu.py <tool> "<json args>"      the MCP tools from a shell
python tools\fgshot.py [--role client] [x0 y0 x1 y1]
                                              picture of the FGU window itself, even when it's covered
                                              (saved as tools\fgshot.png; needs Pillow)
```
