"""Kraken Agent Bridge daemon for Fantasy Grounds. Python 3 standard library only.

Listens on 127.0.0.1:47111 (never on other interfaces).

Each Fantasy Grounds instance running the Kraken Agent Bridge extension polls with a
role: "host" (the GM) or "client" (a connected player on this machine). Each
role has its own command queue, so a command sent to the player never runs on
the GM and the reverse.

Fantasy Grounds side (the extension, GET only):
  /hello?r=<role>&d=<json>             instance info when the extension starts
  /poll?r=<role>&g=<generation>&i=<instance>
                                       held up to POLL_HOLD seconds; returns one
                                       command as JSON, or an empty body
  /result?id=&part=&of=&d=<chunk>      result JSON, possibly in several parts

Client side (the MCP server, or any program: curl, a script, an agent's HTTP tool):
  POST /cmd   {"cmd": "...", "args": {...}, "timeout": 30, "role": "host"}
  GET  /status                                              -> connection state

Old extension builds poll without r=; they count as "host".

Two GM instances on one machine (two campaigns open): each gets its own
channel. The first live one keeps "host"; a second GM copy that says /hello
while "host" is held by a live copy of another campaign is given "host2"
(then "host3", "host4"), and /hello answers "ok host2" so the extension polls
on that channel and reports it in chat. A copy that reloads (new instance id,
same campaign folder) keeps its channel while it is live; a channel whose copy
stopped polling is free again, so a campaign opened later gets the lowest free one. Callers address a copy with "role": "host2". Polls from an
instance that does not own the channel get an empty reply and are listed
under "others" in /status.

Run:  python fgu_bridge_daemon.py
"""
import http.server
import json
import queue
import socket
import threading
import time
import urllib.parse
import uuid

HOST = "127.0.0.1"
PORT = 47111
POLL_HOLD = 25.0
HOST_CHANNELS = ("host", "host2", "host3", "host4")
ROLES = HOST_CHANNELS + ("client",)

lock = threading.Lock()
queues = {r: queue.Queue() for r in ROLES}
results = {}          # id -> result dict
waiters = {}          # id -> threading.Event
parts = {}            # id -> {index: chunk}
cancelled = set()     # ids of commands whose caller gave up (timed out): never delivered later
state = {r: {"last_poll": 0.0, "hello": None, "polls": 0, "port": None, "owner": None, "others": {}} for r in ROLES}
OTHER_HOLD = 10.0     # how long a poll from a non-owning instance is held


def norm_role(r):
    r = (r or "host").lower()
    return r if r in ROLES else "host"


def is_live(s):
    return bool(s["last_poll"]) and time.time() - s["last_poll"] < POLL_HOLD + 15


def pick_host_channel(inst, folder):
    """The channel for a GM copy saying /hello: its own, a free one, or one
    whose copy stopped polling (called with the lock held)."""
    for ch in HOST_CHANNELS:
        s = state[ch]
        mine = bool(inst) and s["owner"] == inst
        # A reload (new instance, same campaign) keeps its channel while that
        # channel is still live; a campaign closed earlier does not hold one.
        same_campaign = bool(folder) and (s["hello"] or {}).get("campaign_folder") == folder and is_live(s)
        if mine or same_campaign:
            return ch
    for ch in HOST_CHANNELS:
        s = state[ch]
        if not s["owner"] or not is_live(s):
            return ch
    return HOST_CHANNELS[-1]


def role_status(r):
    s = state[r]
    age = time.time() - s["last_poll"] if s["last_poll"] else None
    return {
        "connected": age is not None and age < POLL_HOLD + 15,
        "seconds_since_poll": None if age is None else round(age, 1),
        "polls": s["polls"],
        "queued": queues[r].qsize(),
        "poll_port": s["port"],
        "fg": s["hello"],
        "others": {k: round(time.time() - v, 1) for k, v in s["others"].items() if time.time() - v < 120},
    }


def status():
    with lock:
        tRoles = {r: role_status(r) for r in ROLES}
    host = tRoles["host"]
    # Top-level fields describe the host, as before, for older callers. Extra
    # GM copies (host2..) are listed in "roles" only while they poll.
    tRoles = {r: v for r, v in tRoles.items() if r in ("host", "client") or v["fg"] or v["polls"]}
    return dict(host, roles=tRoles)


def run_command(cmd, args, timeout, role):
    role = norm_role(role)
    cid = uuid.uuid4().hex[:12]
    ev = threading.Event()
    with lock:
        waiters[cid] = ev
    queues[role].put({"id": cid, "cmd": cmd, "args": args or {}})
    if not ev.wait(timeout):
        with lock:
            waiters.pop(cid, None)
            # A command still waiting in the queue must not run when an FGU
            # connects later: a fresh FGU would replay old (possibly heavy) work.
            cancelled.add(cid)
            st = role_status(role)
        hint = ""
        if not st["connected"]:
            hint = (f" No {role} Fantasy Grounds instance is polling. Ask the user to open the campaign with Kraken Agent Bridge"
                    " ticked, click Yes To All on FGU's Open URL prompt, or type /agentbridge in FGU's chat; then call fgu_status.")
        return {"ok": False, "error": f"timed out after {timeout}s waiting for the {role}.{hint}"}
    with lock:
        waiters.pop(cid, None)
        return results.pop(cid)


class Handler(http.server.BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.0"

    def log_message(self, *args):
        pass

    def reply(self, body, code=200, ctype="text/plain; charset=utf-8"):
        data = body.encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self):
        url = urllib.parse.urlparse(self.path)
        q = {k: v[0] for k, v in urllib.parse.parse_qs(url.query, keep_blank_values=True).items()}
        role = norm_role(q.get("r"))

        if url.path == "/poll":
            # Initial permission probe must not wait for a command. The Lua
            # client sends /hello after this response to claim its instance.
            if q.get("h") == "1":
                self.reply("")
                return
            inst = q.get("i", "")
            with lock:
                s = state[role]
                foreign = s["owner"] is not None and inst != s["owner"]
                if foreign:
                    s["others"][inst or "(no id)"] = time.time()
            if foreign:
                time.sleep(OTHER_HOLD)
                self.reply("")
                return
            with lock:
                s["last_poll"] = time.time()
                s["polls"] += 1
                s["port"] = self.client_address[1]
            cmd = None
            deadline = time.time() + POLL_HOLD
            while cmd is None:
                try:
                    cmd = queues[role].get(timeout=max(0.1, deadline - time.time()))
                except queue.Empty:
                    self.reply("")
                    return
                with lock:
                    if cmd["id"] in cancelled:
                        cancelled.discard(cmd["id"])
                        cmd = None
            with lock:
                state[role]["last_poll"] = time.time()
            self.reply(json.dumps(cmd))

        elif url.path == "/result":
            cid = q.get("id", "")
            idx, total = int(q.get("part", "1")), int(q.get("of", "1"))
            with lock:
                bucket = parts.setdefault(cid, {})
                bucket[idx] = q.get("d", "")
                if len(bucket) == total:
                    text = "".join(bucket[i] for i in range(1, total + 1))
                    del parts[cid]
                    try:
                        results[cid] = json.loads(text)
                    except ValueError as exc:
                        results[cid] = {"ok": False, "error": f"bad JSON from Fantasy Grounds: {exc}", "raw": text[:2000]}
                    ev = waiters.get(cid)
                    if ev:
                        ev.set()
                    else:
                        results.pop(cid, None)
            self.reply("ok")

        elif url.path == "/hello":
            try:
                info = json.loads(q.get("d", "{}"))
            except ValueError:
                info = {"raw": q.get("d", "")}
            info["time"] = time.strftime("%Y-%m-%d %H:%M:%S")
            role = norm_role(info.get("role") or q.get("r"))
            with lock:
                if role in HOST_CHANNELS:
                    role = pick_host_channel(info.get("instance") or "", info.get("campaign_folder") or "")
                info["channel"] = role
                state[role]["hello"] = info
                state[role]["owner"] = info.get("instance") or None
                state[role]["others"].pop(info.get("instance") or "", None)
                # Until its first real poll, a newly claimed channel counts as live.
                state[role]["last_poll"] = time.time()
            self.reply("ok" if role in ("host", "client") else "ok " + role)

        elif url.path == "/status":
            self.reply(json.dumps(status()), ctype="application/json")

        else:
            self.reply("not found", 404)

    def do_POST(self):
        url = urllib.parse.urlparse(self.path)
        if url.path != "/cmd":
            self.reply("not found", 404)
            return
        length = int(self.headers.get("Content-Length", "0"))
        try:
            body = json.loads(self.rfile.read(length) or b"{}")
        except ValueError:
            self.reply(json.dumps({"ok": False, "error": "request body is not JSON"}), 400, "application/json")
            return
        result = run_command(body.get("cmd", ""), body.get("args"), float(body.get("timeout", 30)), body.get("role"))
        self.reply(json.dumps(result), ctype="application/json")


class Server(http.server.ThreadingHTTPServer):
    """Owns the port alone. Python's HTTP server allows address reuse, which
    on Windows lets a second daemon bind the same port and split the traffic
    (the Windows startup shortcut and an agent session can both start one)."""
    allow_reuse_address = False
    daemon_threads = True

    def server_bind(self):
        if hasattr(socket, "SO_EXCLUSIVEADDRUSE"):
            self.socket.setsockopt(socket.SOL_SOCKET, socket.SO_EXCLUSIVEADDRUSE, 1)
        super().server_bind()


def main():
    try:
        server = Server((HOST, PORT), Handler)
    except OSError:
        return  # another daemon already has the port: nothing to do
    server.serve_forever()


if __name__ == "__main__":
    main()
