#!/usr/bin/env python3
"""Build the Kraken Agent Bridge release zip and publish it as a GitHub Release.

Usage:
    python release.py               # tag = "v" + version from extension.xml
    python release.py v1.1          # explicit tag
    python release.py --build-only  # build the zip, no release
    python release.py --install     # copy KrakenAgentBridge into the local FGU extensions folder

The zip holds the KrakenAgentBridge folder (copy it into FGU's extensions
folder), the README, CHANGELOG, docs and the agent skill. Requires Python 3
and, to publish, the GitHub CLI (`gh`) authenticated.
"""
import os
import shutil
import subprocess
import sys
import zipfile
import xml.etree.ElementTree as ET

REPO = os.path.dirname(os.path.abspath(__file__))
EXT = os.path.join(REPO, "KrakenAgentBridge")
SKIP_DIRS = {"__pycache__"}
SKIP_FILES = {"fgshot.png"}


def version():
    r = ET.parse(os.path.join(EXT, "extension.xml")).getroot()
    return r.findtext("properties/version") or "0.0"


def walk(base):
    for root, dirs, names in os.walk(base):
        dirs[:] = sorted(d for d in dirs if d not in SKIP_DIRS)
        for n in sorted(names):
            if n not in SKIP_FILES and not n.endswith(".pyc"):
                yield os.path.join(root, n)


def sync_mcp():
    """Copy the agent docs into KrakenAgentBridge/MCP and rebuild the skill from AGENT_GUIDE.md,
    so the setup folder that ships with the extension never drifts from docs/."""
    mcp = os.path.join(EXT, "MCP")
    for name in ("AGENT_GUIDE.md", "USAGE.md"):
        shutil.copyfile(os.path.join(REPO, "docs", name), os.path.join(mcp, name))
    skill = os.path.join(REPO, "skills", "fgu-bridge", "SKILL.md")
    with open(skill, encoding="utf-8", newline="") as f:
        front = f.read().split("---\n", 2)[1]
    with open(os.path.join(REPO, "docs", "AGENT_GUIDE.md"), encoding="utf-8", newline="") as f:
        guide = f.read()
    with open(skill, "w", encoding="utf-8", newline="") as f:
        f.write("---\n" + front + "---\n\n" + guide)
    os.makedirs(os.path.join(mcp, "skill", "fgu-bridge"), exist_ok=True)
    shutil.copyfile(skill, os.path.join(mcp, "skill", "fgu-bridge", "SKILL.md"))


def build(tag):
    sync_mcp()
    out = os.path.join(REPO, "build", f"KrakenAgentBridge-{tag}.zip")
    os.makedirs(os.path.dirname(out), exist_ok=True)
    with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as z:
        for path in walk(EXT):
            z.write(path, os.path.relpath(path, REPO).replace("\\", "/"))
        for f in ("AGENT_INSTALL.md", "README.md", "CHANGELOG.md"):
            z.write(os.path.join(REPO, f), f)
        for d in ("docs", "skills"):
            for path in walk(os.path.join(REPO, d)):
                z.write(path, os.path.relpath(path, REPO).replace("\\", "/"))
    with zipfile.ZipFile(out) as z:
        assert "KrakenAgentBridge/extension.xml" in z.namelist()
        print(f"[build] {os.path.basename(out)} ({len(z.namelist())} files)")
    return out


def install():
    data = os.environ.get("FGU_DATA_FOLDER") or os.path.join(os.environ.get("APPDATA", ""), "SmiteWorks", "Fantasy Grounds")
    dest = os.path.join(data, "extensions", "KrakenAgentBridge")
    # Copy over in place: a running daemon holds its server folder open, so it can't be deleted first.
    shutil.copytree(EXT, dest, ignore=shutil.ignore_patterns("__pycache__", "*.pyc", "fgshot.png"), dirs_exist_ok=True)
    print(f"[install] {dest}")


def main():
    args = list(sys.argv[1:])
    if "--install" in args:
        sync_mcp()
        install()
        return
    build_only = "--build-only" in args
    if build_only:
        args.remove("--build-only")
    tag = args[0] if args else "v" + version()
    out = build(tag)
    if build_only:
        return
    title = f"Kraken Agent Bridge {tag}"
    notes = ("Let an AI agent (any MCP client, or anything that speaks HTTP) read and drive your Fantasy Grounds Unity campaign. "
             "Install: unzip, copy the KrakenAgentBridge folder into Fantasy Grounds' extensions folder, register "
             "server/fgu_mcp.py with your agent, tick Kraken Agent Bridge in your campaign. "
             "See docs/INSTALL.md and CHANGELOG.md.")
    exists = subprocess.run(["gh", "release", "view", tag], cwd=REPO,
                            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode == 0
    if exists:
        subprocess.run(["gh", "release", "upload", tag, out, "--clobber"], cwd=REPO, check=True)
    else:
        subprocess.run(["gh", "release", "create", tag, out, "--title", title, "--notes", notes], cwd=REPO, check=True)
    print("[done]", tag)


if __name__ == "__main__":
    main()
