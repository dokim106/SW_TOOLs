# games/

One folder per game, named by its id (`doom`, `2048`, ...). Each holds the game's files exactly as downloaded, plus
`game.json`: title, keys hint, licence, source, and the sha256 of every file. `build` refuses a game whose files no longer
match `game.json` (run `arcade.py repin <id>` after a deliberate change). Add games with `arcade.py add`, never by copying
folders in by hand. Everything here ends up under `C:\CustomDash\arcade\games\<id>\` on the server.
