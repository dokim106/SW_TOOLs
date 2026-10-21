// verify_arcade.js <dashboardId> <outDir> <id,id,...> [folder=arcade]
// Logged-in check of the Arcade inside the real console: for each game, select it in the launcher, wait, prove it drew
// something, press keys and see the game react, screenshot it. Fails on any request to another host or a game that
// shows nothing. Credentials are read from the lab's files (same as screenshot_dashboard.js) and never printed.
const fs = require("fs"), path = require("path"), { spawn } = require("child_process");
process.env.NODE_TLS_REJECT_UNAUTHORIZED = "0";
const HOME = process.env.HOME, BASE = process.env.ARCADE_CONSOLE || "https://localhost";
const [, , DID, OUT, IDS, FOLDER = "arcade"] = process.argv;
const ids = (IDS || "").split(",").filter(Boolean);
const user = fs.readFileSync(HOME + "/.config/infisical/solarwinds_lab.id", "utf8").trim();
const pass = fs.readFileSync(HOME + "/.config/infisical/solarwinds_lab.secret", "utf8").trim();
const host = new URL(BASE).host;
const jar = new Map();
const sleep = ms => new Promise(r => setTimeout(r, ms));
function keep(res) { const sc = typeof res.headers.getSetCookie === "function" ? res.headers.getSetCookie() : []; for (const c of sc) { const [kv] = c.split(";"); const i = kv.indexOf("="); if (i > 0) jar.set(kv.slice(0, i).trim(), kv.slice(i + 1).trim()); } }
async function step(url, o = {}) { const r = await fetch(url, { ...o, redirect: "manual", headers: { ...(o.headers || {}), Cookie: [...jar].map(([k, v]) => k + "=" + v).join("; ") } }); keep(r); return { r, loc: r.headers.get("location") }; }
async function login() {
  let x = await step(BASE + "/Orion/Login.aspx"); const h = await x.r.text(); const b = new URLSearchParams(); let m;
  const re = /<input[^>]*name="([^"]*)"[^>]*value="([^"]*)"[^>]*>/gi; while ((m = re.exec(h))) { if (/Password$/.test(m[1]) || /PasswordPolicy/.test(m[1])) continue; b.set(m[1], m[2]); }
  const re2 = /<input[^>]*value="([^"]*)"[^>]*name="([^"]*)"[^>]*>/gi; while ((m = re2.exec(h))) b.set(m[2], m[1]);
  b.set("ctl00$BodyContent$Username", user); b.set("ctl00$BodyContent$Password", pass); b.set("__EVENTTARGET", "ctl00$BodyContent$LoginButton");
  x = await step(BASE + "/Orion/Login.aspx", { method: "POST", body: b.toString(), headers: { "Content-Type": "application/x-www-form-urlencoded", Referer: BASE + "/Orion/Login.aspx" } });
  let g = 0; while (x.loc && g++ < 6) x = await step(new URL(x.loc, BASE).toString());
  if (!jar.has(".ASPXAUTH")) throw new Error("login failed (no auth cookie)");
}
function waitCdp(port) { return new Promise(async (res, rej) => { for (let i = 0; i < 80; i++) { try { return res(await (await fetch(`http://127.0.0.1:${port}/json`)).json()); } catch { await sleep(300); } } rej(new Error("cdp timeout")); }); }
(async () => {
  await login();
  const port = 9590, udd = "/tmp/arcade-verify-udd"; spawn("rm", ["-rf", udd]);
  const chrome = spawn("/usr/bin/google-chrome", ["--headless=new", "--no-sandbox", "--disable-gpu", "--disable-dev-shm-usage", "--ignore-certificate-errors", "--autoplay-policy=no-user-gesture-required", "--user-data-dir=" + udd, "--remote-debugging-port=" + port, "--window-size=1876,1046", "about:blank"], { stdio: "ignore" });
  const tabs = await waitCdp(port); const ws = new WebSocket(tabs.find(t => t.type === "page").webSocketDebuggerUrl);
  await new Promise((r, j) => { ws.onopen = r; ws.onerror = j; });
  let id = 0; const pend = new Map(); const foreign = new Set(); const consoleForeign = new Set(); let errors = [];
  ws.onmessage = e => { const m = JSON.parse(e.data);
    if (m.id && pend.has(m.id)) { pend.get(m.id)(m); pend.delete(m.id); return; }
    if (m.method === "Network.requestWillBeSent") { try { const u = new URL(m.params.request.url); if (/^https?:$/.test(u.protocol) && u.host !== host) {
        // judge the Arcade only on requests made by its own documents; the console page's own traffic is reported apart
        const doc = m.params.documentURL || ""; const fromArcade = doc.includes(`/customdash/${FOLDER}/`);
        let where = "?"; try { where = new URL(doc).pathname.slice(0, 60); } catch {}
        (fromArcade ? foreign : consoleForeign).add(u.origin + u.pathname.slice(0, 50) + "  (requested by " + where + ")"); } } catch {} }
    if (m.method === "Runtime.exceptionThrown") { const d = m.params.exceptionDetails; errors.push("exception: " + ((d.exception && d.exception.description) || d.text || "").split("\n")[0].slice(0, 160)); }
    if (m.method === "Log.entryAdded" && m.params.entry.level === "error" && !/ERR_CONNECTION_REFUSED/.test(m.params.entry.text)) errors.push("log: " + m.params.entry.text.slice(0, 160));
    if (m.method === "Runtime.consoleAPICalled" && m.params.type === "error") errors.push("console: " + m.params.args.map(a => a.value || a.description || "").join(" ").slice(0, 160));
  };
  const cdp = (me, pa = {}) => new Promise(r => { const i = ++id; pend.set(i, r); ws.send(JSON.stringify({ id: i, method: me, params: pa })); });
  const ev = async x => { const r = await cdp("Runtime.evaluate", { expression: x, returnByValue: true, awaitPromise: true }); return r.result && r.result.result ? r.result.result.value : null; };
  await cdp("Network.enable"); await cdp("Page.enable"); await cdp("Runtime.enable"); await cdp("Log.enable");
  for (const [name, value] of jar) await cdp("Network.setCookie", { name, value, domain: new URL(BASE).hostname, path: "/" });
  await cdp("Page.navigate", { url: `${BASE}/apps/platform/dashboard/${DID}` });
  const L = `document.querySelector('iframe[src*="/customdash/${FOLDER}/"]')`;
  let ready = false;
  for (let i = 0; i < 40 && !ready; i++) { await sleep(1500); ready = await ev(`(()=>{const f=${L};return !!(f&&f.contentWindow&&f.contentWindow.arcadeSelect&&f.contentDocument.querySelectorAll('#games button').length)})()`); }
  if (!ready) { console.log("!! arcade launcher not found or not ready on dashboard " + DID); process.exit(1); }
  console.log("launcher ready; game buttons: " + await ev(`[...${L}.contentDocument.querySelectorAll('#games button')].map(b=>b.textContent).join(', ')`));
  let ok = true;
  const PROBE = `(()=>{const G=${L}.contentDocument.getElementById('stage').contentDocument;if(!G||!G.body)return null;
     const cv=[...G.querySelectorAll('canvas')].map(c=>c.width*c.height).reduce((a,b)=>Math.max(a,b),0);
     const fr=G.getElementById('drawframes_stats'); const tiles=G.querySelector('.tile-container');
     return JSON.stringify({title:G.title,els:G.getElementsByTagName('*').length,text:(G.body.innerText||'').trim().length,canvas:cv,
       frames:fr?fr.innerText:null,tiles:tiles?tiles.innerHTML.length+':'+tiles.children.length:null,
       sig:(G.body.innerHTML.length)+'/'+(tiles?tiles.innerHTML:'').length});})()`;
  for (const gid of ids) {
    errors = [];
    // judge each game alone: scroll the console page (and anything around the widget) back to the top first
    await ev(`(()=>{let e=${L};while(e){if(e.scrollTop)e.scrollTop=0;e=e.parentElement;}window.scrollTo(0,0);if(document.scrollingElement)document.scrollingElement.scrollTop=0;return true})()`);
    const BAR = `(()=>{const f=${L};const a=f.getBoundingClientRect();const b=f.contentDocument.getElementById('bar').getBoundingClientRect();return JSON.stringify({abs:Math.round(a.top+b.top),launcherScroll:f.contentWindow.scrollY,hidden:getComputedStyle(f.contentDocument.getElementById('bar')).display==='none'})})()`;
    const barBefore = await ev(BAR);
    const sel = await ev(`${L}.contentWindow.arcadeSelect(${JSON.stringify(gid)})`);
    await sleep(9000);
    const cur = await ev(`${L}.contentWindow.arcadeCurrent()`);
    let p = await ev(PROBE); p = p ? JSON.parse(p) : null;
    const drew = !!p && (p.canvas >= 10000 || (p.els >= 30 && p.text >= 20));
    const barAfterLoad = await ev(BAR);
    // keys: click the middle of the game frame, then arrows / Enter, and see the page react
    const rect = await ev(`(()=>{const a=${L}.getBoundingClientRect(),b=${L}.contentDocument.getElementById('stage').getBoundingClientRect();return JSON.stringify({x:a.left+b.left+b.width/2,y:a.top+b.top+b.height/2})})()`);
    let keysReact = "n/a";
    if (rect) {
      const { x, y } = JSON.parse(rect);
      await cdp("Input.dispatchMouseEvent", { type: "mousePressed", x, y, button: "left", clickCount: 1 });
      await cdp("Input.dispatchMouseEvent", { type: "mouseReleased", x, y, button: "left", clickCount: 1 });
      const before = await ev(PROBE);
      for (const k of [["ArrowLeft", 37], ["ArrowUp", 38], ["ArrowRight", 39], ["ArrowDown", 40], ["Enter", 13]]) {
        await cdp("Input.dispatchKeyEvent", { type: "keyDown", key: k[0], code: k[0], windowsVirtualKeyCode: k[1], nativeVirtualKeyCode: k[1] });
        await sleep(120);
        await cdp("Input.dispatchKeyEvent", { type: "keyUp", key: k[0], code: k[0], windowsVirtualKeyCode: k[1], nativeVirtualKeyCode: k[1] });
        await sleep(250);
      }
      await sleep(1200);
      const after = await ev(PROBE);
      const b = before ? JSON.parse(before) : {}, a = after ? JSON.parse(after) : {};
      keysReact = (b.tiles !== null && b.tiles !== undefined) ? (b.sig !== a.sig ? "yes (board changed)" : "NO change seen")
                : (b.frames !== null && b.frames !== undefined) ? (Number(a.frames) > Number(b.frames) ? "game loop running (frames " + b.frames + " -> " + a.frames + ")" : "frames did not advance")
                : (b.sig !== a.sig ? "page changed" : "no visible change (may be fine)");
    }
    const shot = await cdp("Page.captureScreenshot", { format: "png" });
    const file = path.join(OUT, `arcade-${gid}.png`);
    if (shot.result && shot.result.data) fs.writeFileSync(file, Buffer.from(shot.result.data, "base64"));
    // the game bar must still be on screen: neither the console page nor the launcher may have been scrolled by the game
    const barTop = await ev(BAR);
    const bt = barTop ? JSON.parse(barTop) : null;
    const barOk = !!bt && (bt.hidden || (bt.abs >= 0 && bt.abs < 1046 && bt.launcherScroll === 0));
    const good = sel && cur === gid && drew && barOk;
    ok = ok && good;
    console.log(`${good ? "ok" : "!!"} ${gid.padEnd(10)} selected=${cur} drew=${drew} ${p ? `canvas=${p.canvas} els=${p.els} text=${p.text}` : "no document"}${p && p.frames ? " frames=" + p.frames : ""} | keys: ${keysReact} | bar on screen: ${barOk ? "yes" : "NO"} (before ${barBefore} / after load ${barAfterLoad} / after keys ${barTop}) | shot ${file}`);
    for (const e of errors.slice(0, 4)) console.log("     " + e);
  }
  if (foreign.size) { ok = false; console.log("!! the Arcade requested other hosts (must be none): " + [...foreign].slice(0, 8).join(" | ")); }
  else console.log("ok the Arcade made no request outside the console host (" + host + ")");
  if (consoleForeign.size) console.log("   note, not the Arcade: the SolarWinds console page itself contacted " + [...consoleForeign].slice(0, 6).join(" | "));
  ws.close(); chrome.kill("SIGKILL"); process.exit(ok ? 0 : 1);
})().catch(e => { console.log("!! " + e.message); process.exit(1); });
