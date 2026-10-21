/* Arcade launcher: reads games.json, shows a button per game, plays the chosen game in the #stage frame.
   ?game=<id> picks the game (wins over the last one played), &bar=0 hides the bar (a widget pinned to one game).
   No inline script, no external host: its CSP is script-src 'self'. */
(function () {
  'use strict';
  var qs = new URLSearchParams(location.search);
  var list = document.getElementById('games');
  var stage = document.getElementById('stage');
  var keys = document.getElementById('keys');
  var newtab = document.getElementById('newtab');
  var KEY = 'arcade.lastGame';
  var games = [];
  var current = null;
  if (qs.get('bar') === '0') document.body.classList.add('nobar');

  function remember(id) { try { localStorage.setItem(KEY, id); } catch (e) { /* storage blocked: fine */ } }
  function recall() { try { return localStorage.getItem(KEY); } catch (e) { return null; } }
  function pathFor(g) { return 'games/' + encodeURIComponent(g.id) + '/' + g.entry.split('/').map(encodeURIComponent).join('/'); }

  function select(id) {
    var g = null;
    for (var i = 0; i < games.length; i++) if (games[i].id === id) g = games[i];
    if (!g) g = games[0];
    if (!g) return false;
    current = g.id;
    stage.src = pathFor(g);              /* replacing the frame unloads the previous game completely */
    newtab.href = pathFor(g);
    keys.textContent = g.keys || '';
    keys.title = g.title + (g.license ? '  |  ' + g.license : '');
    for (var j = 0; j < list.children.length; j++) {
      list.children[j].classList.toggle('on', list.children[j].getAttribute('data-id') === g.id);
    }
    document.title = g.title + ' · Arcade';
    remember(g.id);
    try { var u = new URL(location.href); u.searchParams.set('game', g.id); history.replaceState(null, '', u.toString()); } catch (e) {}
    return true;
  }
  window.arcadeSelect = select;          /* also used by verify_arcade.js */
  window.arcadeCurrent = function () { return current; };

  /* hand the keyboard to the game without scrolling the console page (focus() normally scrolls every ancestor) */
  stage.addEventListener('load', function () { try { stage.focus({ preventScroll: true }); } catch (e) {} });

  fetch('games.json', { credentials: 'same-origin', cache: 'no-store' })
    .then(function (r) { if (!r.ok) throw new Error('HTTP ' + r.status); return r.json(); })
    .then(function (cfg) {
      games = cfg.games || [];
      if (!games.length) { keys.textContent = 'No games installed yet (arcade.py add).'; return; }
      games.forEach(function (g) {
        var b = document.createElement('button');
        b.type = 'button';
        b.textContent = g.title;
        b.setAttribute('data-id', g.id);
        b.addEventListener('click', function () { select(g.id); b.blur(); });
        list.appendChild(b);
      });
      var want = qs.get('game') || recall() || cfg['default'];
      if (!games.some(function (g) { return g.id === want; })) want = cfg['default'] || games[0].id;
      select(want);
    })
    .catch(function (e) { keys.textContent = 'Could not load the game list (' + e.message + '). Reload the console page if you were signed out.'; });
})();
