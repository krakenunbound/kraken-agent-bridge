"""Kraken Agent Bridge: search and read ruleset and extension source (Lua and
XML) inside .pak/.ext files or unpacked folders. Python 3 standard library only.

A file is named "<container>:<path inside>", e.g.
  "rulesets/CoreRPG.pak:scripts/manager_chat.lua"
  "rulesets/Kraken35E:scripts/manager_char.lua"     (an unpacked folder)
  "extensions/KrakenAgentBridge:scripts/bridge.lua"
"""
import os
import re
import xml.etree.ElementTree as ET
import zipfile

TEXT_EXT = (".lua", ".xml", ".txt", ".json", ".md", ".html", ".css")
MAX_FILE = 4 * 1024 * 1024


class Container:
    """A .pak/.ext/.mod zip or an unpacked folder."""

    def __init__(self, data_folder, rel):
        self.rel = rel.replace("\\", "/")
        self.path = os.path.join(data_folder, rel)
        self.is_zip = os.path.isfile(self.path)
        self._zip = None

    def names(self):
        if self.is_zip:
            try:
                if self._zip is None:
                    self._zip = zipfile.ZipFile(self.path)
                return [n for n in self._zip.namelist() if not n.endswith("/")]
            except (zipfile.BadZipFile, OSError):
                return []
        out = []
        for root, _dirs, files in os.walk(self.path):
            for f in files:
                out.append(os.path.relpath(os.path.join(root, f), self.path).replace("\\", "/"))
        return out

    def read(self, name):
        if self.is_zip:
            if self._zip is None:
                self._zip = zipfile.ZipFile(self.path)
            info = self._zip.getinfo(name)
            if info.file_size > MAX_FILE:
                raise ValueError(f"{name} is larger than {MAX_FILE} bytes")
            data = self._zip.read(name)
        else:
            full = os.path.normpath(os.path.join(self.path, name))
            if not full.startswith(os.path.normpath(self.path)):
                raise ValueError("path leaves the container")
            if os.path.getsize(full) > MAX_FILE:
                raise ValueError(f"{name} is larger than {MAX_FILE} bytes")
            with open(full, "rb") as f:
                data = f.read()
        for enc in ("utf-8-sig", "cp1252", "latin-1"):
            try:
                return data.decode(enc)
            except UnicodeDecodeError:
                continue
        return data.decode("latin-1", "replace")


def find_container(data_folder, kind, name):
    """rulesets/<name>.pak or rulesets/<name>/ (same for extensions .ext)."""
    ext = ".pak" if kind == "rulesets" else ".ext"
    folder = os.path.join(data_folder, kind, name)
    if os.path.isdir(folder):
        return Container(data_folder, f"{kind}/{name}")
    if os.path.isfile(folder + ext):
        return Container(data_folder, f"{kind}/{name}{ext}")
    return None


def ruleset_layers(data_folder, ruleset):
    """The ruleset and every ruleset it imports (base.xml <importruleset>), top first."""
    out, todo, seen = [], [ruleset], set()
    while todo:
        name = todo.pop(0)
        if not name or name.lower() in seen:
            continue
        seen.add(name.lower())
        c = find_container(data_folder, "rulesets", name)
        if not c:
            continue
        out.append(c)
        try:
            root = ET.fromstring(c.read("base.xml").encode("utf-8"))
            for imp in root.iter("importruleset"):
                todo.append(imp.get("source", ""))
        except Exception:
            pass
    return out


def containers(data_folder, ruleset=None, include="ruleset", extensions=None):
    """include: "ruleset" (the ruleset and its layers), "extensions", or "all"."""
    out = []
    if include in ("ruleset", "all") and ruleset:
        out += ruleset_layers(data_folder, ruleset)
    if include in ("extensions", "all"):
        ext_dir = os.path.join(data_folder, "extensions")
        names = extensions
        if not names:
            names = sorted({os.path.splitext(n)[0] for n in os.listdir(ext_dir)}) if os.path.isdir(ext_dir) else []
        for n in names:
            c = find_container(data_folder, "extensions", n)
            if c:
                out.append(c)
    return out


def open_file(data_folder, file_id):
    if ":" not in file_id:
        raise ValueError('name a file as "<container>:<path>", e.g. "rulesets/CoreRPG.pak:scripts/manager_chat.lua"')
    rel, name = file_id.split(":", 1)
    rel = rel.replace("\\", "/").strip("/")
    if not (rel.startswith("rulesets/") or rel.startswith("extensions/")) or ".." in rel:
        raise ValueError("only files under rulesets/ and extensions/ can be read")
    c = Container(data_folder, rel)
    if not os.path.exists(c.path):
        raise ValueError(f"no such ruleset or extension: {rel}")
    return c, name


def search(data_folder, text, ruleset=None, include="ruleset", regex=False, ext=None, path_contains=None,
           max_results=80, ignore_case=True, extensions=None):
    flags = re.IGNORECASE if ignore_case else 0
    pat = re.compile(text if regex else re.escape(text), flags)
    exts = tuple(ext) if ext else (".lua", ".xml")
    results, files_hit, scanned = [], 0, 0
    for c in containers(data_folder, ruleset, include, extensions):
        for name in c.names():
            if not name.lower().endswith(exts):
                continue
            if path_contains and path_contains.lower() not in name.lower():
                continue
            try:
                body = c.read(name)
            except Exception:
                continue
            scanned += 1
            hit = False
            for i, line in enumerate(body.splitlines(), 1):
                if pat.search(line):
                    hit = True
                    results.append(f"{c.rel}:{name}:{i}: {line.strip()[:240]}")
                    if len(results) >= max_results:
                        return {"matches": results, "files_scanned": scanned, "truncated": True,
                                "searched": [x.rel for x in containers(data_folder, ruleset, include, extensions)]}
            files_hit += hit
    return {"matches": results, "files_with_matches": files_hit, "files_scanned": scanned, "truncated": False,
            "searched": [x.rel for x in containers(data_folder, ruleset, include, extensions)]}


def read(data_folder, file_id, start=1, lines=200):
    c, name = open_file(data_folder, file_id)
    body = c.read(name).splitlines()
    start = max(1, int(start or 1))
    lines = max(1, min(int(lines or 200), 1000))
    chunk = body[start - 1:start - 1 + lines]
    return {"file": file_id, "start": start, "end": start + len(chunk) - 1, "total_lines": len(body),
            "text": "\n".join(f"{start + i}: {l}" for i, l in enumerate(chunk))}


def list_files(data_folder, container_rel, contains=None):
    rel = container_rel.replace("\\", "/").strip("/")
    if not (rel.startswith("rulesets/") or rel.startswith("extensions/")) or ".." in rel:
        raise ValueError("only rulesets/ and extensions/ can be listed")
    c = Container(data_folder, rel)
    names = [n for n in c.names() if n.lower().endswith(TEXT_EXT)]
    if contains:
        names = [n for n in names if contains.lower() in n.lower()]
    return {"container": rel, "files": names[:2000], "count": len(names)}
