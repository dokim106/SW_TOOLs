# launcher/

The Arcade page itself. `index.html` is the template (game bar plus the frame the game plays in); `launcher.js` reads
`games.json`, draws a button per game, and loads the chosen game. `build` copies the script under a name that includes
its fingerprint (`launcher.<hash>.js`), so a changed launcher is never served from an old cache. It is our own code (no
inline scripts, no outside hosts). URL options: `?game=<id>` picks the game, `&bar=0` hides the bar.
