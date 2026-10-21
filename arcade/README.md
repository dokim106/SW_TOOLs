# Arcade: swap games inside the SolarWinds console

The Arcade is one dashboard with a small game bar at the top. Click a game's name and it plays below. Adding a new game is
one command. It is separate from the DOOM bundle: its own folder on the server, its own dashboard, its own copy of DOOM.

| | |
|---|---|
| Dashboard | **Arcade**, number **179**: `https://XXX.xxx.xxx.xxx/apps/platform/dashboard/xxx` (My Dashboards, then Arcade) |
| Files on the server | `C:\CustomDash\arcade\` in the lab VM, served at `/customdash/arcade/` |
| Canonical copy | XXXXXhostname `~/solarwinds-hud/bundles/arcade/` (run the commands below there) |
| Games today | DOOM (default) and 2048 |
| Online? | Never. Each game's files are on the server; the Arcade makes no request to any other host (checked on every deploy) |

## Play and swap

1. Open the Arcade dashboard.
2. Click a game in the bar (DOOM, 2048, ...). The previous game is unloaded completely; the new one starts.
3. Click inside the game once so it has the keyboard. The bar shows that game's keys.

The Arcade remembers the last game you played, per browser. **open in tab** opens the current game on its own page.

**Pin a widget to one game.** In edit mode, click the widget's pencil, and in "Show the contents of a specific URL" put:

```
/customdash/arcade/index.html?game=2048&bar=0
```

`game=` picks the game, `bar=0` hides the game bar so the widget looks like that game alone. Save. You can have several
widgets, each pinned to a different game. (The pencil works on this lab because of the dashboard patch in the DOOM
package's `sw-patch/`; without it, change the URL in the dashboard JSON instead.)

## Add a game

A game qualifies when it is **prebuilt** (ready-to-serve files, no build step), **fully offline** (loads nothing from another
host), **single-threaded** (no SharedArrayBuffer; the console cannot provide it), and **free to redistribute** (code and data).
Get its files onto XXXXXhostname as a folder, a `.zip` or a `.tar.gz`, then:

```bash
cd ~/solarwinds-hud/bundles/arcade
```

```bash
python3 arcade.py add hextris ~/Downloads/hextris-gh-pages.zip --title "Hextris" --keys "Left and right rotate; space pauses" --license "GPL-3.0" --source "https://github.com/Hextris/hextris"
```

You should see a short scan (file count, size, file types) and `OK added hextris`. The tool finds the game's `index.html`
inside the archive by itself (`--root sub/folder` or `--entry play.html` if it can't), copies the files unmodified into
`games/hextris/`, drops build clutter (`.md`, `.scss`, source maps, scripts), and records every file's fingerprint. Then
publish it:

```bash
python3 arcade.py deploy
```

You should see, in order: `OK built dist/`, `published arcade (... every sha256 verified in the VM)`, every file identical in
the VM, the login checks (`302 ... /Orion/Login.aspx` for pages, `200 application/wasm` for WebAssembly files), the dashboard
line, then one `ok` line per game (it drew something, keys reached it, the bar stayed on screen) and
`ok the Arcade made no request outside the console host`, and finally `DONE`. Reload the Arcade and the new button is there.

A deploy can make the console pause for a moment while the web server re-reads its settings; `deploy` waits for it.

### What `add` refuses, and why

| refused because | meaning | what you can do |
|---|---|---|
| loads something from another host | a `<script>`, stylesheet, font or image comes from the internet | not fixable by a flag: the Arcade is offline by design. Find a build that bundles its files |
| uses eval/new Function | the browser would block it under the Arcade's security policy | `--allow-eval`, which relaxes the policy for that one game only |
| inline event handlers | `onclick="..."` style code, also blocked by the policy | `--allow-inline`, for that one game only |
| IIS never serves this path / file name | a folder named `bin` or `App_Data`, or `+ % #` in a file name | rename it in a copy of the game, then add the copy |

Nothing changes when `add` refuses. If a game mentions SharedArrayBuffer, `add` only warns; the browser check on deploy
decides whether it really runs.

## Other commands

| command | what it does |
|---|---|
| `python3 arcade.py list` | every game, its size, and the default; flags a game whose files changed since it was added |
| `python3 arcade.py default 2048` | the game the Arcade opens with |
| `python3 arcade.py remove 2048` | takes a game out (then `deploy`) |
| `python3 arcade.py repin doom` | after you deliberately edited a game's files |
| `python3 arcade.py build` | builds `dist/` and `dashboard.json` only; works on any machine with Python 3 |
| `python3 arcade.py verify` | re-runs the server and browser checks without publishing |

## On another SolarWinds server (no XXXXXhostname)

1. Do the one-time `/customdash` server prep from the DOOM package (`docs/INSTRUCTIONS-step-by-step.md`, Part B, Step 2).
2. On any machine with Python 3: `python3 arcade.py build`.
3. Copy everything inside `dist/` to `C:\CustomDash\arcade\` on the Orion web server.
4. Import `dashboard.json` (SWQL Studio, Invoke Verb, `Orion.Dashboards.Instances` Import, or `Invoke-SwisVerb` in PowerShell).
5. Check: opening `https://<console>/customdash/arcade/index.html` while signed out redirects to the login page; signed in, the bar and the default game appear.

## Where everything goes

| item | what it is |
|---|---|
| `arcade.py` | the tool (add, list, remove, default, repin, build, deploy, verify) |
| `arcade.json` | the Arcade's settings: game order, default game, dashboard and widget keys, widget height (`rows`, 7) |
| `games/<id>/` | one folder per game: its unmodified files plus `game.json` (fingerprints, keys, licence, source). See `games/README.md` |
| `launcher/` | the Arcade page and its script (the game bar). See `launcher/README.md` |
| `verify_arcade.js` | the logged-in browser check `deploy` runs |
| `dist/` | built output: exactly what goes into `C:\CustomDash\arcade\` (made by `build`, never edit by hand) |
| `dashboard.json` | the Modern Dashboard import for the Arcade |
| `evidence/` | screenshots from the lab checks |

## Good to know

- **After a deploy, one hard refresh** (Cmd+Shift+R or Ctrl+Shift+R) may be needed the first time; the pages are served
  uncached, but an older browser cache can hold the previous launcher once.
- **The Arcade's DOOM** carries one small extra script, `no-lurch.js`, so DOOM's engine log and start-up focus no longer
  scroll the console page and push the game bar out of view. The standalone DOOM dashboard (178) is unchanged.
- **2048 is taller than the widget** at 7 rows; it scrolls inside its own frame. Raise `rows` in `arcade.json` and
  re-import if you prefer (delete the dashboard first, then `deploy`).
- **The SolarWinds console page itself** contacts `googletagmanager.com` when a dashboard opens. That is the console, not
  the Arcade; the deploy check reports it separately.
