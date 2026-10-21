#!/usr/bin/env python3
"""arcade.py: a shelf of offline browser games for the SolarWinds console. Separate from the DOOM bundle.

Every game lives UNMODIFIED in games/<id>/, next to a game.json that pins each file's sha256 and records what the game
needs. The launcher is one page with a game bar; the chosen game plays in a frame below it. `build` turns games/ +
launcher/ into dist/, which is served from C:\\CustomDash\\arcade\\ at /customdash/arcade/.

  python3 arcade.py add <id> <folder|.zip|.tar.gz> --title "Name" [--keys "..."] [--entry index.html] [--root sub/dir]
                       [--license "..."] [--source URL] [--exclude GLOB ...] [--allow-eval] [--allow-inline] [--replace]
  python3 arcade.py list
  python3 arcade.py remove <id>
  python3 arcade.py default <id>          the game the Arcade opens with
  python3 arcade.py repin <id>            after you deliberately changed a game's files
  python3 arcade.py build                 games/ + launcher/ -> dist/ and dashboard.json (offline, any machine)
  python3 arcade.py deploy                build, publish to the lab VM, import the dashboard once, verify (lab kit host)
  python3 arcade.py verify                server and browser checks only (lab kit host)

Swap the game while playing: click it in the bar. Pin a widget to one game: set its URL to
/customdash/arcade/index.html?game=<id>&bar=0 (widget pencil, or the dashboard JSON).
"""
import argparse, base64, fnmatch, hashlib, json, os, re, shutil, subprocess, sys, tarfile, tempfile, time, uuid, zipfile
from xml.dom import minidom

HERE = os.path.dirname(os.path.abspath(__file__))
GAMES = os.path.join(HERE, "games")
LAUNCHER = os.path.join(HERE, "launcher")
DIST = os.path.join(HERE, "dist")
CFG = os.path.join(HERE, "arcade.json")
HUD = os.path.expanduser("~/solarwinds-hud")
BASE = os.environ.get("ARCADE_CONSOLE", "https://localhost")
NAME = "arcade"
ID_RE = re.compile(r"^[a-z0-9][a-z0-9-]{0,30}$")

DEFAULT_EXCLUDES = [".*", "*.md", "*.markdown", "*.scss", "*.sass", "*.less", "*.ts", "*.map", "Rakefile", "Gemfile*",
                    "package.json", "package-lock.json", "yarn.lock", "node_modules", "*.config", "*.yml", "*.yaml",
                    "Makefile", "CMakeLists.txt", "*.c", "*.h", "*.cpp", "*.rs", "*.toml", "Cargo.lock", "*.sh", "*.bat",
                    "*.cmd", "*.ps1", "*.py", "*.sha256", "*.sha1", "*.md5", "game.json"]
NEVER_SERVE = {".config", ".cs", ".asax", ".ascx", ".asmx", ".aspx", ".ashx", ".dll", ".exe", ".ps1", ".bat", ".cmd", ".sh", ".py", ".md"}
IIS_HIDDEN = {"bin", "app_code", "app_data", "app_globalresources", "app_localresources", "app_webreferences", "app_browsers", "web.config"}
MIME = {".wasm": "application/wasm", ".json": "application/json", ".data": "application/octet-stream",
        ".mem": "application/octet-stream", ".wad": "application/octet-stream", ".pak": "application/octet-stream",
        ".zip": "application/zip", ".jsdos": "application/zip", ".woff": "font/woff", ".woff2": "font/woff2",
        ".ttf": "font/ttf", ".otf": "font/otf", ".ogg": "audio/ogg", ".oga": "audio/ogg", ".mp3": "audio/mpeg",
        ".wav": "audio/wav", ".m4a": "audio/mp4", ".webp": "image/webp", ".mjs": "text/javascript", ".txt": "text/plain"}

LOAD_TAG = re.compile(r"<(script|link|img|audio|video|source|iframe|embed|object|track|input)\b([^>]*)>", re.I)
ATTR = re.compile(r"""\b(src|href|data|poster)\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s>]+))""", re.I)
ABS = re.compile(r"^\s*(https?:)?//", re.I)
CSS_URL = re.compile(r"""url\(\s*['"]?([^'")\s]+)""", re.I)
CSS_IMPORT = re.compile(r"""@import\s+(?:url\()?\s*['"]?([^'");\s]+)""", re.I)
JS_ABS = re.compile(r"""["'`](https?://[^"'`\s]{4,})""")
INLINE_HANDLER = re.compile(r"<[a-z][^>]*?\son[a-z]+\s*=", re.I)


def die(msg, code=2):
    print("FAIL " + msg)
    sys.exit(code)


def sha256(p):
    h = hashlib.sha256()
    with open(p, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def xmlesc(s):
    return s.replace("&", "&amp;").replace('"', "&quot;").replace("<", "&lt;").replace(">", "&gt;")


def cfg():
    c = json.load(open(CFG)) if os.path.exists(CFG) else {}
    c.setdefault("name", NAME)
    c.setdefault("title", "Arcade")
    c.setdefault("rows", 7)
    c.setdefault("order", [])
    c.setdefault("default", None)
    c.setdefault("dashboard_key", "arcade_" + uuid.uuid4().hex[:8])
    c.setdefault("widget_key", str(uuid.uuid4()))
    return c


def save_cfg(c):
    with open(CFG, "w") as f:
        json.dump(c, f, indent=1)
        f.write("\n")


def game_files(root):
    out = []
    for d, dirs, files in os.walk(root):
        dirs.sort()
        for f in sorted(files):
            p = os.path.join(d, f)
            rel = os.path.relpath(p, root).replace(os.sep, "/")
            if rel != "game.json":
                out.append(rel)
    return out


def scan(root, entry):
    r = {"external": [], "maybe_external": [], "inline_hashes": [], "inline_handlers": [], "wasm": [], "workers": [],
         "eval": [], "sab": [], "exts": set(), "size": 0, "files": 0, "problems": []}
    for rel in game_files(root):
        p = os.path.join(root, rel)
        r["files"] += 1
        r["size"] += os.path.getsize(p)
        ext = os.path.splitext(rel)[1].lower()
        if ext:
            r["exts"].add(ext)
        if any(s.lower() in IIS_HIDDEN for s in rel.split("/")):
            r["problems"].append(rel + ": IIS never serves this path segment (bin, App_Data, web.config...)")
        if re.search(r"[+%#?]", rel):
            r["problems"].append(rel + ": '+', '%', '#' or '?' in a file name is blocked by IIS request filtering")
        if ext in NEVER_SERVE:
            r["problems"].append(rel + ": " + ext + " files are never served by IIS; exclude it")
        if ext == ".wasm":
            r["wasm"].append(rel)
        if ext in (".html", ".htm"):
            raw = open(p, "rb").read()
            t = raw.decode("utf-8", "replace")
            for m in LOAD_TAG.finditer(t):
                for a in ATTR.finditer(m.group(2)):
                    v = a.group(2) or a.group(3) or a.group(4) or ""
                    if ABS.match(v):
                        r["external"].append("%s: <%s %s=%s>" % (rel, m.group(1), a.group(1), v[:90]))
            for m in list(CSS_URL.finditer(t)) + list(CSS_IMPORT.finditer(t)):
                if ABS.match(m.group(1)):
                    r["external"].append("%s: css %s" % (rel, m.group(1)[:90]))
            for m in re.finditer(rb"<script\b([^>]*)>", raw, re.I):          # CSP hash = raw bytes, as csp_regen.py
                attrs = m.group(1)
                if re.search(rb"\bsrc\s*=", attrs, re.I):
                    continue
                if re.search(rb"type\s*=\s*['\"]?\s*(application/(json|ld\+json)|text/(x-|template|html))", attrs, re.I):
                    continue
                end = raw.lower().find(b"</script>", m.end())
                body = raw[m.end():end] if end != -1 else b""
                if body.strip():
                    r["inline_hashes"].append(base64.b64encode(hashlib.sha256(body).digest()).decode())
            for m in INLINE_HANDLER.finditer(t):
                if not re.match(r"<a\b", m.group(0), re.I) or "javascript:" in m.group(0).lower():
                    r["inline_handlers"].append("%s: %s" % (rel, m.group(0)[:70]))
        if ext == ".css":
            t = open(p, encoding="utf-8", errors="replace").read()
            for m in list(CSS_URL.finditer(t)) + list(CSS_IMPORT.finditer(t)):
                if ABS.match(m.group(1)):
                    r["external"].append("%s: css %s" % (rel, m.group(1)[:90]))
        if ext in (".js", ".mjs"):
            t = open(p, encoding="utf-8", errors="replace").read()
            for m in JS_ABS.finditer(t):
                r["maybe_external"].append("%s: %s" % (rel, m.group(1)[:90]))
            if re.search(r"\bnew\s+Worker\s*\(|importScripts\s*\(", t):
                r["workers"].append(rel)
            if re.search(r"(?<![\w.$])eval\s*\(|\bnew\s+Function\s*\(", t):
                r["eval"].append(rel)
            if "SharedArrayBuffer" in t:
                r["sab"].append(rel)
    if not os.path.isfile(os.path.join(root, entry)):
        r["problems"].append("entry page " + entry + " not found")
    r["exts"] = sorted(r["exts"])
    return r


def excluded(name, pats):
    return any(fnmatch.fnmatch(name, p) for p in pats)


def stage_copy(src_root, dst, pats):
    for d, dirs, files in os.walk(src_root):
        dirs[:] = [x for x in dirs if not excluded(x, pats)]
        for f in files:
            if excluded(f, pats):
                continue
            s = os.path.join(d, f)
            rel = os.path.relpath(s, src_root)
            t = os.path.join(dst, rel)
            os.makedirs(os.path.dirname(t), exist_ok=True)
            shutil.copy2(s, t)


def unpack(src, tmp):
    if os.path.isdir(src):
        return src
    if zipfile.is_zipfile(src):
        with zipfile.ZipFile(src) as z:
            for n in z.namelist():
                if n.startswith("/") or ".." in n.split("/"):
                    die("refusing archive with unsafe path: " + n)
            z.extractall(tmp)
        return tmp
    if tarfile.is_tarfile(src):
        with tarfile.open(src) as t:
            for m in t.getmembers():
                if m.name.startswith("/") or ".." in m.name.split("/") or m.issym() or m.islnk():
                    die("refusing archive with unsafe member: " + m.name)
            t.extractall(tmp)
        return tmp
    die("source must be a folder, a .zip or a .tar(.gz): " + src)


def find_root(base, entry, explicit):
    if explicit:
        r = os.path.join(base, explicit)
        if not os.path.isdir(r):
            die("--root %s not found inside the source" % explicit)
        return r
    if os.path.isfile(os.path.join(base, entry)):
        return base
    for d, dirs, files in os.walk(base):
        if os.path.relpath(d, base).count(os.sep) > 2:
            continue
        if entry in files:
            return d
    die("could not find %s in the source; pass --root <folder> or --entry <file>" % entry)


def report(r):
    print("  files %d, %.1f MB, extensions %s" % (r["files"], r["size"] / 1048576, " ".join(r["exts"])))
    for k, label in (("wasm", "WebAssembly"), ("workers", "web workers"), ("eval", "eval/new Function"),
                     ("sab", "mentions SharedArrayBuffer (threads will NOT work in the console; browser check decides)")):
        if r[k]:
            print("  %s: %s" % (label, ", ".join(r[k][:5])))
    if r["inline_hashes"]:
        print("  inline scripts: %d (hashed into this game's CSP)" % len(r["inline_hashes"]))
    for x in r["maybe_external"][:8]:
        print("  note, absolute URL in a script (check it is not loaded at runtime): " + x)
    if len(r["maybe_external"]) > 8:
        print("  note, %d more absolute URLs in scripts" % (len(r["maybe_external"]) - 8))


def cmd_add(a):
    if not ID_RE.match(a.id):
        die("id must be lower-case letters, digits and dashes, at most 31 characters")
    dest = os.path.join(GAMES, a.id)
    if os.path.exists(dest) and not a.replace:
        die("game '%s' already exists; use --replace to overwrite it" % a.id)
    tmp = tempfile.mkdtemp(prefix="arcade-add-")
    try:
        base = unpack(os.path.abspath(a.source_path), os.path.join(tmp, "src"))
        root = find_root(base, a.entry, a.root)
        stage = os.path.join(tmp, "stage")
        os.makedirs(stage)
        stage_copy(root, stage, DEFAULT_EXCLUDES + (a.exclude or []))
        r = scan(stage, a.entry)
        print("scan of %s (%s)" % (a.id, os.path.relpath(root, base) if root != base else "archive root"))
        report(r)
        bad = []
        if r["problems"]:
            bad += r["problems"]
        if r["external"]:
            bad += ["loads something from another host (the game must be fully offline): " + x for x in r["external"]]
        if r["eval"] and not a.allow_eval:
            bad.append("uses eval/new Function in %s; add --allow-eval to accept 'unsafe-eval' for this game only" % ", ".join(r["eval"][:3]))
        if r["inline_handlers"] and not a.allow_inline:
            bad.append("inline event handlers (%s); add --allow-inline to accept 'unsafe-inline' scripts for this game only" % r["inline_handlers"][0])
        if bad:
            for b in bad:
                print("  REFUSED: " + b)
            die("game not added; nothing changed")
        meta = {"id": a.id, "title": a.title, "entry": a.entry, "keys": a.keys or "", "license": a.license or "",
                "source": a.source or "", "added": time.strftime("%Y-%m-%d"),
                "files": {rel: sha256(os.path.join(stage, rel)) for rel in game_files(stage)},
                "size": r["size"], "csp": {"eval": bool(a.allow_eval), "inline": bool(a.allow_inline)},
                "notes": (["uses web workers"] if r["workers"] else []) + (["mentions SharedArrayBuffer"] if r["sab"] else [])}
        with open(os.path.join(stage, "game.json"), "w") as f:
            json.dump(meta, f, indent=1)
            f.write("\n")
        if os.path.exists(dest):
            shutil.rmtree(dest)
        os.makedirs(GAMES, exist_ok=True)
        shutil.move(stage, dest)
    finally:
        shutil.rmtree(tmp, ignore_errors=True)
    c = cfg()
    if a.id not in c["order"]:
        c["order"].append(a.id)
    if not c["default"]:
        c["default"] = a.id
    save_cfg(c)
    print("OK added %s (%d files). Next: python3 arcade.py build, then deploy." % (a.id, len(meta["files"])))


def load_game(gid):
    p = os.path.join(GAMES, gid, "game.json")
    if not os.path.isfile(p):
        die("no game '%s' (games/%s/game.json missing)" % (gid, gid))
    return json.load(open(p))


def check_pins(g):
    root = os.path.join(GAMES, g["id"])
    have = set(game_files(root))
    want = set(g["files"])
    errs = ["missing " + x for x in sorted(want - have)] + ["unexpected " + x for x in sorted(have - want)]
    for rel in sorted(want & have):
        if sha256(os.path.join(root, rel)) != g["files"][rel]:
            errs.append("changed " + rel)
    return errs


def cmd_list(a):
    c = cfg()
    if not c["order"]:
        print("no games yet: python3 arcade.py add <id> <folder|zip> --title \"Name\"")
        return
    print("%-12s %-24s %8s %6s  %s" % ("id", "title", "MB", "files", "notes"))
    for gid in c["order"]:
        g = load_game(gid)
        errs = check_pins(g)
        notes = ("default " if gid == c["default"] else "") + ("CHANGED SINCE ADD " if errs else "") + " ".join(g.get("notes", []))
        print("%-12s %-24s %8.1f %6d  %s" % (gid, g["title"][:24], g["size"] / 1048576, len(g["files"]), notes))


def cmd_remove(a):
    c = cfg()
    if a.id not in c["order"] and not os.path.isdir(os.path.join(GAMES, a.id)):
        die("no game '%s'" % a.id)
    shutil.rmtree(os.path.join(GAMES, a.id), ignore_errors=True)
    c["order"] = [x for x in c["order"] if x != a.id]
    if c["default"] == a.id:
        c["default"] = c["order"][0] if c["order"] else None
    save_cfg(c)
    print("OK removed %s. Build and deploy to take it off the console." % a.id)


def cmd_default(a):
    c = cfg()
    if a.id not in c["order"]:
        die("no game '%s'" % a.id)
    c["default"] = a.id
    save_cfg(c)
    print("OK default game is now %s (build and deploy to apply)" % a.id)


def cmd_repin(a):
    g = load_game(a.id)
    root = os.path.join(GAMES, a.id)
    r = scan(root, g["entry"])
    if r["external"]:
        die("refusing to repin: the changed files load something from another host: " + r["external"][0])
    g["files"] = {rel: sha256(os.path.join(root, rel)) for rel in game_files(root)}
    g["size"] = r["size"]
    with open(os.path.join(root, "game.json"), "w") as f:
        json.dump(g, f, indent=1)
        f.write("\n")
    print("OK repinned %s (%d files)" % (a.id, len(g["files"])))


CSP_COMMON = ["style-src 'self' 'unsafe-inline'", "img-src 'self' data: blob:", "font-src 'self' data:",
              "media-src 'self' data: blob:", "connect-src 'self' data: blob:", "worker-src 'self' blob:",
              "object-src 'none'", "frame-src 'self'", "frame-ancestors 'self'", "base-uri 'self'", "form-action 'none'"]
NOSTORE = """      <httpProtocol>
        <customHeaders>
          <remove name="Cache-Control" />
          <add name="Cache-Control" value="no-cache, no-store, must-revalidate" />
          <remove name="Pragma" />
          <add name="Pragma" value="no-cache" />
          <remove name="Expires" />
          <add name="Expires" value="0" />
        </customHeaders>
      </httpProtocol>"""


def game_csp(g, r):
    script = ["'self'"]
    if g["csp"].get("inline"):
        script.append("'unsafe-inline'")
    else:
        script += ["'sha256-%s'" % h for h in r["inline_hashes"]]
    if r["wasm"]:
        script.append("'wasm-unsafe-eval'")
    if g["csp"].get("eval"):
        script.append("'unsafe-eval'")
    return "; ".join(["default-src 'self'", "script-src " + " ".join(script)] + CSP_COMMON)


def game_webconfig(g, r):
    locs = []
    for w in r["wasm"]:
        locs.append("""  <location path="%s">
    <system.webServer>
      <handlers>
        <remove name="Arcade-StaticViaAspNet" />
        <remove name="CustomDash-StaticViaAspNet" />
        <remove name="Arcade-WasmNative" />
        <add name="Arcade-WasmNative" path="*.wasm" verb="GET,HEAD" modules="StaticFileModule" resourceType="File" requireAccess="Read" />
      </handlers>
    </system.webServer>
  </location>""" % xmlesc(w))
    locs.append("""  <location path="%s">
    <system.webServer>
%s
    </system.webServer>
  </location>""" % (xmlesc(g["entry"]), NOSTORE))
    return """<?xml version="1.0" encoding="utf-8"?>
<!-- Arcade game '%s', generated by arcade.py build. Its own Content-Security-Policy (inline-script hashes, wasm and eval
     only when this game needs them); each .wasm file served by IIS's native static module so it is labelled application/wasm;
     the entry page is never cached. The login gate and request filtering come from ../../web.config. -->
<configuration>
  <system.webServer>
    <httpProtocol>
      <customHeaders>
        <remove name="Content-Security-Policy" />
        <add name="Content-Security-Policy" value="%s" />
      </customHeaders>
    </httpProtocol>
  </system.webServer>
%s
</configuration>
""" % (xmlesc(g["id"]), xmlesc(game_csp(g, r)), "\n".join(locs))


def root_webconfig(exts):
    allow = [e for e in sorted(exts) if e not in NEVER_SERVE]
    mime = "\n".join('      <remove fileExtension="%s" />\n      <mimeMap fileExtension="%s" mimeType="%s" />' % (e, e, MIME[e])
                     for e in allow if e in MIME)
    filt = "\n".join('          <remove fileExtension="%s" />\n          <add fileExtension="%s" allowed="true" />' % (e, e)
                     for e in allow)
    launcher_csp = "; ".join(["default-src 'self'", "script-src 'self'"] + CSP_COMMON)
    nostore = lambda path: """  <location path="%s">
    <system.webServer>
%s
    </system.webServer>
  </location>""" % (path, NOSTORE)
    return """<?xml version="1.0" encoding="utf-8"?>
<!-- Arcade (/customdash/arcade/), generated by arcade.py build. Same principles as the DOOM bundle and dashboard 173:
     every file through the managed StaticFileHandler so the console login applies (<deny users="?"/>); request filtering
     opened for exactly the file types the games use (the SolarWinds app runs allowUnlisted="false"); MIME types for them;
     the launcher's own CSP (each game folder sets its own); launcher page and games.json never cached. -->
<configuration>
  <system.webServer>
    <handlers>
      <remove name="Arcade-StaticViaAspNet" />
      <add name="Arcade-StaticViaAspNet" path="*" verb="GET,HEAD" type="System.Web.StaticFileHandler" resourceType="File" preCondition="integratedMode" />
    </handlers>
    <staticContent>
%s
    </staticContent>
    <security>
      <requestFiltering>
        <fileExtensions>
%s
        </fileExtensions>
      </requestFiltering>
    </security>
    <httpProtocol>
      <customHeaders>
        <remove name="Content-Security-Policy" />
        <add name="Content-Security-Policy" value="%s" />
        <remove name="X-Content-Type-Options" />
        <add name="X-Content-Type-Options" value="nosniff" />
        <remove name="Referrer-Policy" />
        <add name="Referrer-Policy" value="same-origin" />
      </customHeaders>
    </httpProtocol>
  </system.webServer>
  <system.web>
    <authorization>
      <deny users="?" />
    </authorization>
  </system.web>
%s
%s
</configuration>
""" % (mime, filt, xmlesc(launcher_csp), nostore("index.html"), nostore("games.json"))


def dashboard_json(c):
    url = "/customdash/%s/index.html" % c["name"]
    return {"version": 1,
            "dashboards": [{"widgets": [{"unique_key": c["widget_key"], "location": {"x": 0, "y": 0, "cols": 12, "rows": c["rows"]}, "reference": False}],
                            "parent": None, "feature": None, "groupId": None, "groupRank": None, "groupMemberName": None, "groupName": None,
                            "dashboardType": None, "routeId": "", "dashboardRoutes": [], "configuration": None, "legacyUrl": None,
                            "isLegacyDefaultNewAccount": False, "isLegacyDefaultExistingAccount": False,
                            "unique_key": c["dashboard_key"], "name": c["title"], "private": None}],
            "widgets": [{"type": "embedded-content",
                         "configuration": {"header": {"properties": {"title": "", "subtitle": ""}},
                                           "mainContent": {"properties": {"sanitized": True, "mode": 0, "customEmbeddedContent": url}}},
                         "subtitle": "", "description": "", "unique_key": c["widget_key"], "name": c["title"], "private": False}],
            "remove": None}


def cmd_build(a=None):
    c = cfg()
    save_cfg(c)
    if not c["order"]:
        die("no games to build; add one first")
    if not c["default"] or c["default"] not in c["order"]:
        c["default"] = c["order"][0]
        save_cfg(c)
    games, exts = [], {".html", ".js", ".json"}
    for gid in c["order"]:
        g = load_game(gid)
        errs = check_pins(g)
        if errs:
            die("game '%s' differs from what was added: %s. If deliberate: python3 arcade.py repin %s" % (gid, "; ".join(errs[:4]), gid))
        r = scan(os.path.join(GAMES, gid), g["entry"])
        if r["external"]:
            die("game '%s' loads from another host: %s" % (gid, r["external"][0]))
        games.append((g, r))
        exts.update(r["exts"])
    if os.path.isdir(DIST):
        shutil.rmtree(DIST)
    os.makedirs(os.path.join(DIST, "games"))
    for g, r in games:
        dst = os.path.join(DIST, "games", g["id"])
        for rel in g["files"]:
            t = os.path.join(dst, rel)
            os.makedirs(os.path.dirname(t), exist_ok=True)
            shutil.copy2(os.path.join(GAMES, g["id"], rel), t)
        with open(os.path.join(dst, "web.config"), "w") as f:
            f.write(game_webconfig(g, r))
    js = open(os.path.join(LAUNCHER, "launcher.js"), "rb").read()
    js_name = "launcher.%s.js" % hashlib.sha256(js).hexdigest()[:10]
    open(os.path.join(DIST, js_name), "wb").write(js)
    page = open(os.path.join(LAUNCHER, "index.html"), encoding="utf-8").read()
    page = page.replace("{{LAUNCHER_JS}}", js_name).replace("{{TITLE}}", c["title"]).replace("{{TITLE_UPPER}}", c["title"].upper())
    if re.search(r"<script(?![^>]*\bsrc=)[^>]*>", page, re.I):
        die("launcher/index.html must not contain inline scripts (its CSP is script-src 'self')")
    open(os.path.join(DIST, "index.html"), "w", encoding="utf-8").write(page)
    listing = {"title": c["title"], "default": c["default"],
               "games": [{"id": g["id"], "title": g["title"], "entry": g["entry"], "keys": g.get("keys", ""),
                          "license": g.get("license", ""), "source": g.get("source", "")} for g, _ in games]}
    with open(os.path.join(DIST, "games.json"), "w") as f:
        json.dump(listing, f, indent=1)
    with open(os.path.join(DIST, "web.config"), "w") as f:
        f.write(root_webconfig(exts))
    for d, _, files in os.walk(DIST):
        for f in files:
            if f == "web.config":
                try:
                    minidom.parse(os.path.join(d, f))
                except Exception as e:
                    die("generated %s is not well-formed XML: %s" % (os.path.relpath(os.path.join(d, f), DIST), e))
    files = []
    for d, _, fs in os.walk(DIST):
        for f in sorted(fs):
            p = os.path.join(d, f)
            files.append({"path": os.path.relpath(p, DIST).replace(os.sep, "/"), "bytes": os.path.getsize(p), "sha256": sha256(p)})
    manifest = {"tool": "arcade.py", "name": c["name"], "built": time.strftime("%Y-%m-%dT%H:%M:%S"), "default": c["default"],
                "games": [g["id"] for g, _ in games], "files": sorted(files, key=lambda x: x["path"])}
    with open(os.path.join(DIST, "manifest.json"), "w") as f:
        json.dump(manifest, f, indent=1)
    with open(os.path.join(HERE, "dashboard.json"), "w") as f:
        json.dump(dashboard_json(c), f, indent=1)
        f.write("\n")
    total = sum(x["bytes"] for x in files)
    print("OK built dist/ for /customdash/%s/: %d games (%s), %d files, %.1f MB; default %s" %
          (c["name"], len(games), ", ".join(g["id"] for g, _ in games), len(files) + 1, total / 1048576, c["default"]))
    return c, games


def run(cmd, cwd=None, inp=None, timeout=900):
    p = subprocess.run(cmd, cwd=cwd, input=inp, capture_output=True, text=True, timeout=timeout)
    return p.returncode, (p.stdout or "") + (p.stderr or "")


def need_lab():
    for p in (os.path.join(HUD, "sw_lab.py"), os.path.join(HUD, "html2dash", "vm_publish.sh"), os.path.expanduser("~/.local/bin/vm-ps")):
        if not os.path.exists(p):
            die("deploy/verify run on the lab kit host; missing " + p + ". Elsewhere: copy dist/ to C:\\CustomDash\\arcade\\ and import dashboard.json (README).")


def http(url):
    rc, out = run(["curl", "-k", "-s", "-o", "/dev/null", "-w", "%{http_code} %{content_type} %{size_download} %{redirect_url}",
                   "--max-time", "60", url], timeout=90)
    return out.strip()


def server_checks(c, games):
    ok = True
    print("[guest] every served file vs manifest")
    ps = ("$root='C:\\CustomDash\\%s'; Get-ChildItem $root -Recurse -File | ForEach-Object { "
          "$_.FullName.Substring($root.Length+1).Replace('\\','/') + ' ' + (Get-FileHash $_.FullName -Algorithm SHA256).Hash.ToLower() }" % c["name"])
    rc, out = run([os.path.expanduser("~/.local/bin/vm-ps")], inp=ps, timeout=600)
    guest = dict(l.strip().rsplit(" ", 1) for l in out.replace("\r", "").splitlines() if re.search(r" [0-9a-f]{64}$", l.strip()))
    man = json.load(open(os.path.join(DIST, "manifest.json")))
    bad = [x["path"] for x in man["files"] if guest.get(x["path"]) != x["sha256"]]
    if bad:
        ok = False
        print("  !! differ or missing in the VM: " + ", ".join(bad[:8]))
    else:
        print("  ok %d files identical in C:\\CustomDash\\%s" % (len(man["files"]), c["name"]))
    print("[http] anonymous requests")
    checks = [("launcher", "/customdash/%s/index.html" % c["name"], "302")]
    for g, r in games:
        checks.append((g["id"] + " page", "/customdash/%s/games/%s/%s" % (c["name"], g["id"], g["entry"]), "302"))
        for w in r["wasm"]:
            checks.append((g["id"] + " " + w, "/customdash/%s/games/%s/%s" % (c["name"], g["id"], w), "wasm"))
    for label, path, want in checks:
        got = http(BASE + path)
        if want == "302":
            good = got.startswith("302") and "/Orion/Login.aspx" in got
        else:
            size = os.path.getsize(os.path.join(DIST, path.split("/customdash/%s/" % c["name"], 1)[1]))
            good = got.startswith("200 application/wasm %d" % size)
        ok &= good
        print("  %s %-28s %s" % ("ok" if good else "!!", label, got[:110]))
    return ok


def dashboard_id(c):
    rc, out = run(["python3", "sw_lab.py", "list"], cwd=HUD, timeout=120)
    for l in out.splitlines():
        m = re.match(r"^\s*(\d+)\s+(.*?)\s+\[(.*)\]\s*$", l)
        if m and m.group(3) == c["dashboard_key"]:
            return int(m.group(1))
    return None


def browser_checks(c, games, did):
    js = os.path.join(HERE, "verify_arcade.js")
    out_dir = os.path.join(HERE, "verify-shots")
    os.makedirs(out_dir, exist_ok=True)
    env = dict(os.environ, NODE_TLS_REJECT_UNAUTHORIZED="0")
    p = subprocess.run([os.path.expanduser("~/.local/bin/node"), js, str(did), out_dir, ",".join(g["id"] for g, _ in games), c["name"]],
                       capture_output=True, text=True, timeout=900, env=env)
    lines = [l for l in (p.stdout + p.stderr).splitlines() if "NODE_TLS_REJECT" not in l and "trace-warnings" not in l]
    for l in lines:
        print("  " + l)
    return p.returncode == 0


def cmd_deploy(a):
    need_lab()
    c, games = cmd_build()
    print("[publish] vm_publish.sh full dist %s" % c["name"])
    rc, out = run(["bash", "html2dash/vm_publish.sh", "full", DIST, c["name"]], cwd=HUD, timeout=1800)
    print("  " + (out.strip().splitlines() or ["(no output)"])[-1])
    if "published" not in out and "already up to date" not in out:
        die("publish failed")
    wait_console()
    finish(c, games, import_if_missing=True)


def wait_console(limit=300):
    """Publishing rewrites web.config files inside the SolarWinds web application, which can make it restart for a
    minute or so (every console user sees a pause). Wait until the login page answers 200 again before checking."""
    t0 = time.time()
    while time.time() - t0 < limit:
        code = http(BASE + "/Orion/Login.aspx").split(" ")[0]
        if code == "200":
            print("[console] answering again after %ds" % int(time.time() - t0))
            return
        time.sleep(10)
    print("[console] still not answering after %ds; checking anyway" % limit)


def cmd_verify(a):
    need_lab()
    c = cfg()
    games = []
    for gid in c["order"]:
        g = load_game(gid)
        games.append((g, scan(os.path.join(GAMES, gid), g["entry"])))
    if not os.path.isfile(os.path.join(DIST, "manifest.json")):
        die("no dist/ yet; run build or deploy")
    finish(c, games, import_if_missing=False)


def finish(c, games, import_if_missing):
    ok = server_checks(c, games)
    did = dashboard_id(c)
    if did is None and import_if_missing:
        rc, out = run(["python3", "sw_lab.py", "import", os.path.join(HERE, "dashboard.json")], cwd=HUD, timeout=180)
        print("[dashboard] " + (out.strip().splitlines() or [""])[-1])
        did = dashboard_id(c)
    if did is None:
        die("dashboard '%s' not found in the console" % c["title"])
    print("[dashboard] %s = DashboardID %d  %s/apps/platform/dashboard/%d" % (c["title"], did, BASE, did))
    print("[browser] logged-in check of every game")
    ok &= browser_checks(c, games, did)
    print("DONE" if ok else "FAIL (see the !! lines)")
    sys.exit(0 if ok else 1)


def main():
    ap = argparse.ArgumentParser(description="Arcade: offline browser games for the SolarWinds console")
    sp = ap.add_subparsers(dest="cmd", required=True)
    p = sp.add_parser("add")
    p.add_argument("id")
    p.add_argument("source_path")
    p.add_argument("--title", required=True)
    p.add_argument("--entry", default="index.html")
    p.add_argument("--root")
    p.add_argument("--keys")
    p.add_argument("--license")
    p.add_argument("--source")
    p.add_argument("--exclude", action="append")
    p.add_argument("--allow-eval", action="store_true")
    p.add_argument("--allow-inline", action="store_true")
    p.add_argument("--replace", action="store_true")
    for name in ("remove", "default", "repin"):
        sp.add_parser(name).add_argument("id")
    for name in ("list", "build", "deploy", "verify"):
        sp.add_parser(name)
    a = ap.parse_args()
    {"add": cmd_add, "list": cmd_list, "remove": cmd_remove, "default": cmd_default, "repin": cmd_repin,
     "build": cmd_build, "deploy": cmd_deploy, "verify": cmd_verify}[a.cmd](a)


if __name__ == "__main__":
    main()
