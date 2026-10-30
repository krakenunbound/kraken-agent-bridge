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
| `fgu_get` | `package`, `field`, or `package`, `fns` | Read a package field (its value and type), e.g. `DataCommon.abilities`. Or pass `fns`, a list of names, to learn which functions the package has without calling any. FGU packages can't be listed, so check names you found in the ruleset's source. |
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
| `fgu_batch` | `steps`, `continue_on_error` (false), `timeout` (60) | Up to 100 commands in one round trip, in order, stopping at the first failure. A step is `{"cmd": "call", "args": {...}}` (a tool name such as `fgu_call` works too). A later step can use an earlier result with `{"$ref": "1.result.1"}`, as the real Lua value (a table or node, not a JSON copy). |
| `fgu_handles` | none, or `release` / `release_all`, or `keep` | Values kept inside FGU between calls. `fgu_call` or `fgu_window_call` with `keep: true` returns handle ids for the tables and nodes it got back; pass one as `{"$handle": "h3"}`. With no arguments, lists them. Handles end when FGU reloads. |
| `fgu_subscribe` | `path`, `events` (["update"]), `values` | Watch the database. FGU's wildcards work: `charsheet.*.hp.wounds`, `combattracker.list.*`. Events: `update`, `childadded`, `childdeleted`, `childupdate`, `delete`, `add`. Changes arrive through `fgu_events`. |
| `fgu_unsubscribe` | `id` or `all` | Stop watching. With neither, lists the subscriptions. |
| `fgu_chat_events` | `on` (true), `private` (false) | Send every chat message (sender, text, dice total) to `fgu_events`. Whispers and secret rolls only with `private`. |
| `fgu_events` | `since` (0), `wait` (0), `types` | Events after `since`: `db`, `chat`, `query` (an @ai question), `answered`, `plan`, `dropped`. `wait` holds up to 60 s until one arrives. Pass the returned `last` as the next `since`. |
| `fgu_source_search` | `text`, `ruleset`, `include`, `extensions`, `regex`, `ext`, `path_contains`, `max_results` | Search the Lua and XML of the loaded ruleset and every ruleset it builds on (5E, then CoreRPG), inside the `.pak` files or unpacked folders; `include: "extensions"` or `"all"` adds extensions. Finds the function that does something and how it is called. |
| `fgu_source_read` | `file`, `start`, `lines`, or `list` | Read lines of a file named as the search prints it (`rulesets/CoreRPG.pak:scripts/manager_chat.lua`), or `list` a ruleset's or extension's files. |
| `fgu_queries` | `status` | The @ai questions asked at the table: who, player or GM, private or not, and status (`new`, `answered`, `held`, `public`). |
| `fgu_query_context` | `id` | Who asked and what they may see: their characters, the books open to them, the ruleset. |
| `fgu_reply` | `id`, `text`, `public`, `gm_only` | Answer in chat. See [The @ai chat assistant](#the-ai-chat-assistant). |
| `fgu_propose` | `query`, `title`, `steps`, `wait` (120) | Ask to make changes: one plan of up to 50 steps in a Yes/No window. See below. |
| `fgu_plan_status` | `plan`, `wait` | A plan's status (`waiting`, `executed`, `failed`, `denied`) and each step's result. |
| `fgu_listener` | `action` (status, start, stop), `agent` | The local program that answers @ai questions. See below. |

### Special argument values

Inside `args` (for `fgu_call` and `fgu_window_call`), these JSON objects become Fantasy Grounds values:

| JSON | Becomes |
| --- | --- |
| `{"$node": "charsheet.id-00001"}` | a database node |
| `{"$actor": "combattracker.list.id-00002"}` | a CoreRPG actor (`ActorManager.resolveActor`) |
| `{"$nil": true}` | `nil` (use `false` for a leading `draginfo` you don't need) |
| `{"$shortcut": {"class": "npc", "path": "npc.id-00004@Bestiary"}}` | a drag-like shortcut object |
| `{"$handle": "h3"}` | a value kept with `keep: true` (see `fgu_handles`) |
| `{"$ref": "2.result.1"}` | inside `fgu_batch`: step 2's result, field `result`, item 1, as the live Lua value |

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

## The @ai chat assistant

Anyone at the table can ask the AI from FGU's chat:

| Typed in chat | What happens |
| --- | --- |
| `@ai what does prone do?` | The question shows in chat as normal. The answer is whispered to the asker and the GM. |
| `/ai how far can my wizard teleport?` | A private question: nothing shows in chat. Same answer routing. |
| `/ai public 3` (GM) | Repeat answer 3, or the last one, to everyone. |
| `/ai send 3` (GM) | Pass an answer that was held for the GM on to the asker. |
| `/ai list` (GM) | The questions so far and their status. |
| `/agentbridge status` | Bridge, listener-side counts, plans waiting. |
| `/agentbridge permissions reset` | Forget the saved Always / Never answers for this campaign. |
| `/agentbridge stop` | Pause the bridge in this copy; `/agentbridge` starts it again. |

**How a question is answered.** The question goes to the GM's copy, which passes it to the **listener** (`server\fgu_listener.py`) as an event. While nobody asks, the listener holds one local request open: no AI runs and nothing is spent. For each question it starts one run of the agent you chose, with the bridge's tools limited to the asker's **scope**:

- **A player's question** can read only what that player could see in their own copy of FGU: their own characters, what is public or shared with them (the party sheet, the combat tracker's visible entries, without foes' hit points or defences), and the books the GM lets players open. GM-only records (NPCs, encounters, maps, notes, story, adventures) are refused by the bridge itself, not just by the AI's instructions. If the AI is unsure the asker may know something, it holds the answer for the GM (`gm_only`), and the GM can pass it on with `/ai send`.
- **A GM's question** can read anything.
- **Neither can change anything directly.** Changes go in one **plan** (`fgu_propose`): every step listed in plain words in a Yes / No / Always / Never window. A player's plan may change only that player's own characters, and goes to that player's own screen; anything else goes to the GM. On Yes, the steps run in order and stop at the first failure (earlier steps stay: there is no rollback). Always and Never remember the answer for that user and that kind of change.

**Lockdown.** Each run is registered with the daemon and gets a token tied to its scope. While a run is in progress the daemon refuses every command that lacks that token, so the agent can't reach the campaign by some other route (a shell, `curl`). The presets also run each agent with nothing but the bridge's tools: no shell, file, web or other MCP servers.

**Choosing the agent.** There is no default: you pick the agent you already have. The listener supports these presets, or any command line:

| Agent | Preset | How it is locked down |
| --- | --- | --- |
| Claude Code | `claude` | `--strict-mcp-config` (only the bridge), tools limited to `mcp__fgu`, built-in tools removed |
| Codex CLI | `codex` | `--ignore-user-config` (none of your MCP servers or plugins), shell and browser features off, read-only sandbox, only the bridge's tools approved |
| Gemini CLI | `gemini` | only the `fgu` server allowed, shell, file and web tools excluded |
| Grok | `grok` | `dontAsk` (anything not allowed is refused), only `fgu__*` allowed, built-in command tools removed. Uses the `fgu` server from your Grok config, so register it there first |
| anything else | `custom` | your command line, with `{prompt_file}`, `{mcp_config}`, `{python}`, `{mcp}`, `{scope_file}` filled in; you lock it down |

Start it from your agent (`fgu_listener` with `action: "start"`, `agent: "codex"`) or from a shell:

```text
python server\fgu_listener.py --agent claude
```

The choice is saved in `%USERPROFILE%\.kraken-agent-bridge\listener.json`, with the run timeout (300 s) and extra arguments for each agent, for example `"extra_args": {"codex": ["-m", "gpt-5.5"]}` to pick a model. The log is `listener.log` in the same folder. If a run fails or ends without replying, the GM gets a short note instead of silence.

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

To check whether a package has a function, use `fgu_get {"package":"MyManager","fns":["doThing"]}`. FGU's packages (CoreRPG's managers, a ruleset's scripts) can't be listed from Lua, so `AgentBridge.listPackageFunctions` only works for packages that are plain Lua tables.

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
| `get` | `package`, `field` or `fns` | `fgu_get` |
| `window_open`, `window_close`, `window_list`, `window_read`, `window_set`, `window_call`, `window_has` | as the tools | `fgu_window_*` |
| `chat` | `text` | `fgu_chat` |
| `batch` | `steps`, `continue_on_error` | `fgu_batch` |
| `handles`, `release`, `keep` | as the tool | `fgu_handles` |
| `subscribe`, `unsubscribe`, `subscriptions`, `chat_events` | as the tools | `fgu_subscribe`, `fgu_unsubscribe`, `fgu_chat_events` |
| `queries`, `query_context`, `reply`, `propose`, `plan_status` | as the tools | the @ai tools |

A command may carry `"scope": {"kind": "player", "user": "<FGU user name>"}` (or `"kind": "gm"`): the extension then limits it as it would an @ai question. Without a scope a command has full access, as the GM.

### Events

```text
GET /events?r=host&since=<seq>&wait=<seconds>&types=query,chat
```

Returns `{"events": [...], "last": <seq>}`. Pass `last` as the next `since`.

### @ai runs

```text
POST /run {"action": "start", "scope": {...}, "ttl": 360}   -> {"token": "..."}
POST /run {"action": "end", "token": "..."}
```

The listener registers each agent run. A command with `"token"` gets that run's scope, whatever scope it names. While a run is active, `/cmd` and `/events` without a token are refused.

`fgu_slash`, `fgu_reload`, `fgu_chat_log`, `fgu_console`, `fgu_events`, `fgu_source_*` and `fgu_listener` are done by the MCP server on your PC (keystrokes, log files, the daemon, ruleset files), not by FGU. Use `tools\fgu.py` for those, or read the files yourself.

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
