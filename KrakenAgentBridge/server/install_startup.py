"""Start the bridge daemon when you log into Windows.

    python install_startup.py            # add the shortcut (and start the daemon now)
    python install_startup.py --remove   # take it out again
    python install_startup.py --status   # show whether it is installed and running

Adds "Kraken Agent Bridge daemon.lnk" to your Windows Startup folder
(shell:startup). It runs fgu_bridge_daemon.py with pythonw.exe, so there is no
console window. The daemon then listens on 127.0.0.1:47111 before Fantasy
Grounds starts, so the extension connects on its first try even after a
reboot and with no agent session open. A second copy exits on its own if one
is already listening (the port is taken).
"""
from __future__ import annotations

import os
import subprocess
import sys
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
DAEMON = os.path.join(HERE, "fgu_bridge_daemon.py")
STARTUP = os.path.join(os.environ.get("APPDATA", ""), "Microsoft", "Windows", "Start Menu", "Programs", "Startup")
LINK = os.path.join(STARTUP, "Kraken Agent Bridge daemon.lnk")
# The shortcut the bridge used under its old name (Claude Bridge 0.x).
OLD_LINK = os.path.join(STARTUP, "Claude Bridge daemon.lnk")


def pythonw():
    exe = sys.executable
    candidate = os.path.join(os.path.dirname(exe), "pythonw.exe")
    return candidate if os.path.exists(candidate) else exe


def running():
    try:
        with urllib.request.urlopen("http://127.0.0.1:47111/status", timeout=2):
            return True
    except OSError:
        return False


def powershell(script):
    subprocess.run(["powershell", "-NoProfile", "-ExecutionPolicy", "Bypass", "-Command", script], check=True)


def install():
    target, args = pythonw(), f'"{DAEMON}"'
    ps = (
        "$s = (New-Object -ComObject WScript.Shell).CreateShortcut('{link}');"
        "$s.TargetPath = '{target}'; $s.Arguments = '{args}'; $s.WorkingDirectory = '{wd}';"
        "$s.WindowStyle = 7; $s.Description = 'Kraken Agent Bridge daemon for Fantasy Grounds (127.0.0.1:47111)';"
        "$s.Save()"
    ).format(link=LINK.replace("'", "''"), target=target.replace("'", "''"), args=args.replace("'", "''"),
             wd=HERE.replace("'", "''"))
    powershell(ps)
    print(f"installed: {LINK}")
    if os.path.exists(OLD_LINK):
        # It would start the old copy's daemon from the old folder.
        os.remove(OLD_LINK)
        print(f"removed the old shortcut: {OLD_LINK}")
    print(f"  runs: {target} {args}")
    if not running():
        flags = subprocess.DETACHED_PROCESS | subprocess.CREATE_NEW_PROCESS_GROUP if os.name == "nt" else 0
        subprocess.Popen([target, DAEMON], cwd=HERE, creationflags=flags, stdin=subprocess.DEVNULL,
                         stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, close_fds=True)
        print("  daemon started now")
    else:
        print("  daemon already running")


def remove():
    if os.path.exists(LINK):
        os.remove(LINK)
        print(f"removed: {LINK}")
    else:
        print("not installed")


def status():
    print(f"startup shortcut: {'installed' if os.path.exists(LINK) else 'not installed'} ({LINK})")
    print(f"daemon: {'running' if running() else 'not running'} on 127.0.0.1:47111")


if __name__ == "__main__":
    if "--remove" in sys.argv:
        remove()
    elif "--status" in sys.argv:
        status()
    else:
        install()
