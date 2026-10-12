# Party Park

A Mario Party-style online party game in Godot 4.7 (GDScript): race around a board, play a sports minigame every
round. The app is still called "Bowling your Friends" (`config/name` in `game/project.godot`); renaming it moves
everyone's save folder, so it needs a save migration first.

## Repos

| Repo | What | Where it lives here |
|---|---|---|
| `Slurms602/Party-Park` (this) | core, party board, builds, relay server | `/` |
| `Slurms602/Bowling-your-Friends` | bowling minigame (Cosmic + Sunset Lanes) | `game/minigames/bowling` (submodule) |
| `Slurms602/Party-Park-Sumo` | Sumo Ring minigame | `game/minigames/sumo` (submodule) |
| `Slurms602/Bowling-your-Friends-Site` | website (GitHub Pages) and the release downloads | separate |

Clone with `git clone --recursive`, or run `git submodule update --init` after a plain clone. A minigame can't run on
its own: it needs this repo around it.

## Layout

- `game/scripts/`: the core. `game.gd` the match (host sim, snapshots, scores, HUD, camera), `beast.gd` the bowler,
  `bot.gd`, `net.gd` + `relay_peer.gd` networking, `powerups.gd` items, `ui.gd`/`hud.gd`/`main.gd` UI,
  `progress.gd` XP and achievements, `arena.gd` **the minigame base class**, `party.gd` + `board.gd` the board.
- `game/minigames/<id>/`: one folder per minigame, each its own repo.
- `game/assets/`: shared fonts, music, Kenney props, `cosmetics.glb`. `server/`: the relay (Render). `tools/`: Blender and music generators.

## Adding a minigame

1. Make `game/minigames/<id>/` with a `minigame.gd` holding `const MAPS := {<map_id> = {name, map, rules, seconds, arena = preload("x.gd")}}`
   (see `minigames/sumo/minigame.gd`). `Arena.maps()` finds it at startup: the lobby, the party board and the
   menu pick it up with no core edits.
2. The arena script `extends Arena` and builds its world in `setup()`. Override only the hooks your game needs. They're
   all listed with their defaults in `game/scripts/arena.gd`: spawns, items, `server_update` (your rules), snapshots,
   prompts, throws, camera and bot behaviour. A game that isn't a brawl can take over the punch and grab buttons
   (`buttons`), the bots (`bot_think`) and set `damage = 0` (no knockouts). `sumo_ring.gd` does all three (grappling
   and shoving); `bowling_arena.gd` is the full brawl. Say "player", not "bowler", in anything a non-bowling game shows.
3. Rules run on the host in `server_update`, through `game`: `game.scores[pid].total += n` then `game.push_scores()`,
   `game.feed(...)` for the kill feed, `game.end_match()` to finish early. Effects that everyone sees go through your
   own `@rpc` methods sent with `game.send(_my_rpc, [args])` (the arena node is named `Arena` on every peer).
4. Scripts in a minigame are compiled by headless tests where autoload names don't exist: reach `Net`, `Sfx`,
   `Music` with `get_node("/root/Net")` into an untyped variable, and don't name the `Game` or `Hud` classes.
5. Put tests in `<id>/tests/` (exports skip them). Create the repo and add it:
   `git submodule add https://github.com/Slurms602/<repo> game/minigames/<id>`.

## Working in a submodule

Commit and push inside the minigame folder first (it's its own repo, on `main`), then commit the new pointer here:
`git add game/minigames/<id> && git commit`. Parallel agents: one minigame each, staying inside its folder.
A core change (anything outside `game/minigames/`) is its own commit in this repo, kept small, because every
minigame depends on it.

If you change anything on the wire (snapshot layout, RPC arguments, a new RPC), bump `PROTOCOL` in
`game/scripts/relay_peer.gd`, so old builds can't join new ones.

## Tests

`$GODOT` is the Godot 4.7.2 binary. Run from the repo root:

```bash
$GODOT --headless --path game -s tests/test_party.gd
$GODOT --headless --path game -s tests/test_progress.gd
$GODOT --headless --path game -s minigames/bowling/tests/test_bowling.gd     # real time, ~30 s
$GODOT --headless --path game -s minigames/bowling/tests/test_powerups.gd
$GODOT --headless --path game -s minigames/bowling/tests/test_touch_grab.gd
$GODOT --headless --path game -s minigames/bowling/tests/strike_rate.gd      # ~1 min
$GODOT --headless --path game -- --host --bots=3 --party=2 --timescale=3 --quit-after=80   # a whole party with bots
$GODOT --headless --path game -- --host --bots=5 --autostart --map=sumo --timescale=3 --quit-after=30   # one minigame, prints REPORT
```

After moving or adding scripts, run `$GODOT --headless --path game --import` once so `class_name`s are registered,
and commit the `.uid` files Godot makes.

## Releases

Bump `config/version` in `game/project.godot` and `version/name` + `version/code` (+1) in `game/export_presets.cfg`.
Export Windows, Linux and Android (`--export-release`). Zip with Python's `zipfile` (there is no `zip` command here),
with the `How to play.txt` and `Licenses.txt`, then upload the assets to the `v0.1.0` release of the Site repo:
the site links to `releases/latest/download/...`. The Android keystore stays outside every repo; its location and
password are in the maintainer's local notes.

## Never commit

`friend.png`, `me.PNG`, `sbgui.PNG` (private screenshots), the reference game installs (`Gang Beasts/`,
`Super Battle Golf/`), `builds/`, or any keystore.

## Style

GDScript, tabs, static types. Everything is built in code (the only scene is `main.tscn`). `##` docs on classes and
non-obvious functions; comments say why.
