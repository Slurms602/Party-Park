# Party Park

A chaotic online party game: a Mario Party-style board where everyone rolls at once, with a sports minigame after
every round. The first minigame is the one this started as, **Bowling your Friends**: beat your friends until they
curl up into a ball, then bowl them down the lane for points. (The app itself is still called Bowling your Friends.)

The combat and physics mix **Gang Beasts** (wobbly bodies, grabbing, mash-to-wake knockouts) with
**Super Battle Golf** (charged swings, dive tackles, launched bodies that flatten whoever they hit, comeback
bonus). See [docs/RESEARCH.md](docs/RESEARCH.md) for what was pulled from each game and why.

Each minigame is its own repository, mounted under `game/minigames/` as a git submodule, so clone with
`git clone --recursive https://github.com/Slurms602/Party-Park` (or run `git submodule update --init` afterwards).

## Play

1. Install [Godot 4.7](https://godotengine.org/download) (standard build, no .NET needed).
2. Open `game/project.godot` and press **Play** (F5).
3. **HOST GAME** gives you a 4-letter **room code**. Add bots with **+ BOT** if you like, pick **Party** or
   **Quick match**, then start.
4. Friends click **JOIN GAME** and type the code. Nobody needs to port forward. Friends on the same Wi-Fi don't even
   need the code: your game shows up in their list.

If the online server can't be reached, HOST GAME switches to hosting by IP by itself. It asks your router to open
UDP 7777 (UPnP) and shows your internet IP in the lobby, and friends type that IP into the same JOIN box.

### Builds for friends

`builds/Bowling your Friends (Windows).zip` is a single `.exe` plus a one-page *How to play*. To rebuild it, use
Godot **Project → Export → Windows**, or
`godot --headless --path game --export-release "Windows" "../builds/windows/Bowling your Friends.exe"`.
The game is unsigned, so Windows shows "Windows protected your PC" the first time: **More info → Run anyway**.

### One-time setup: the online server

Room codes go through a tiny relay server (`server/relay.js`). Everyone connects *out* to it, which is why no router
setup is needed. (Super Battle Golf gets the same thing from Steam's relay, but that only works once a game is on
Steam.) You deploy it once:

1. Go to [render.com](https://render.com) and sign up with your GitHub account (free).
2. **New → Blueprint** → pick this repository → **Apply**. `render.yaml` sets everything up.
3. When it says *Live*, check the URL. If it's `https://bowling-your-friends-relay.onrender.com`, you're done.
   If Render picked a different name, put it in the game under **Settings → Online server** as `wss://<that-host>`,
   or set `DEFAULT_RELAY` in `game/scripts/net.gd` so everyone's build uses it.

The free plan sleeps after 15 idle minutes. The game wakes it when it opens, but the first game of the day can take
up to a minute to connect. For an always-awake server, use Render's paid Starter plan or run `server/Dockerfile` on
any host.

To give friends a build: **Project → Export** in Godot. Windows and Linux presets are included; Godot will
offer to download the export templates the first time.

### Controls

| Action | Keyboard + mouse | Gamepad |
|---|---|---|
| Move | WASD / arrows | Left stick |
| Punch: tap = jab (3 in a row = combo finisher), hold = haymaker | Left mouse / J | RT / X |
| Grab: hold to grab whatever you touch | Right mouse / K | LT / RB |
| Bowl: hold Grab on a ball, hold Punch to charge, release | | |
| Jump | Space | A |
| Dive tackle | Shift / L | B |
| Menu | Esc | Start |

### Fighting

- **Jab, jab, COMBO!** Three quick jabs on the same person: the third one launches them and knocks them flat.
- **Haymaker:** hold punch to wind up (you move slower), release to swing. At full charge the fist pulses and
  dings, and the swing is a **SMASH**: two SMASHes ball anyone. A quick jab interrupts a wind-up.
- **Dive tackle** knocks people down. Bodies sent flying crash through whoever they land on.
- Health bars show over everyone's heads. Below a quarter health you're visibly woozy.
- Carrying a ball? Jabs only stagger you. A real hit (haymaker, finisher, tackle, flying body) makes you drop it.

### Rules

- When your health hits zero you curl into a ball for about 7 s (at least 3). **Mash buttons** to wake up
  sooner, or to wriggle free while someone is carrying you.
- **Bowl from behind the foul line.** Release past it and it's a **FOUL**: the pins still fall, but you score
  nothing, so the line is where the fight happens.
- Pins knocked down = points. **Strike** gives +10 bonus and **Spare** +5. A bowled body that runs someone
  over gives +2. If you're 30+ points behind, your rolls are worth ×1.5.
- Leftover pins stay up for 12 s, so you can go for the spare. Then the pinsetter re-racks the lane.
- Bowled players come back out of the ball return with 2 s of immunity.
- Pick up a pin with Grab and Punch to swing it as a club.

### Party mode

A Mario Party-style board game on **Party Park**, an amusement park island. Everyone **rolls at the same time**
(dice 1–10) and hops along a path that winds past the rides. At two **forks** you pick a way: the plaza shortcut or
the long way past the sumo dojo, the main path or the lakeside walk.

- Spaces: blue +3 coins, red −3, green "?" lucky, yellow items, purple seagulls (they steal coins or an item), the
  **ticket booth** (passing pays 3 coins in, landing wins the lot) and orange **landmark events**: ride the **roller
  coaster** across the park, spin the **prize wheel**, bowl over everyone near the **bowling alley**, or take on
  whoever's closest in a **sumo duel**.
- Items (carry two, use before rolling): **Double Dice**, **Swap Ticket** (trade places), **Coin Magnet** (5 coins from
  the richest), **Golden Ticket** (warp to the star).
- Reach the **star** with 20 coins and you buy it, then it moves. After every round a random **sports minigame** pays
  coins by finishing place (10, 7, 5, 3, 2, 1...).
- After 5, 8 or 12 rounds come the **bonus stars** (most minigame coins, most coins at once, most event spaces), then
  most stars wins (coins break ties). A whole party counts as one match for XP and trophies.

Minigames so far: **Cosmic Bowling** and **Sunset Bowling** (75-second versions of the main game) and **Sumo Ring**
(no punches: grab belts, shove and charge everyone off a floating ring; everyone still in scores when someone goes
over, the pusher scores again, last one standing +3).
**Quick match** plays a single game on the map you pick, as before.

### Maps

The host picks the map in the lobby.

- **Cosmic Lanes**: the blacklight alley. Four lanes, tight pins, strikes come easy.
- **Sunset Lanes**: a rooftop alley at golden hour. Three longer, wider lanes with bigger, more spread-out
  pins, and less aim assist. You get about half as many strikes (28% vs 53% in `strike_rate.gd`),
  so aim matters.

### Power-ups

Spinning **?** boxes pop up on the back floor, where you bowl from, so that's where the fight is worth having.
Run through one to grab a random power-up. A **?** marker at the bottom of the screen points to boxes behind you.
Everyone sees what you're holding over your head. You hold one at a time, and players who are well behind
get the scoring ones twice as often.

| Power-up | What it does |
|---|---|
| Big Gloves | 10 s of punches that hit 1.5× harder |
| Turbo Shoes | 10 s of running 40% faster, even while carrying |
| Sticky Grip | Whoever you carry next can't wake up in your arms (up to 8 s) |
| Golden Ball | Your next bowl scores double |
| Bumpers | Rails rise out of the gutters for your next bowl |
| Giant Pin | 3 swings, each one a full SMASH |
| Bowling Ball | A real ball to throw at people: tap Punch to throw, hold to throw harder. Up to 55 damage |

### Graphics

**Settings → Graphics** has three levels: **High** (the PC default), **Classic** (the original look) and **Fast**
(the phone default). Fast renders the 3D at 70% resolution with FXAA (menus stay sharp), uses one shadow cascade,
only lets bowlers and pins cast shadows, keeps outlines on bodies only, and on Sunset Lanes drops the second
directional light, the glow and the cloud layer. In `tests/render_bench.gd` it cuts GPU time by about 60% on both
maps. On first launch a PC watches the menu for a few seconds and drops to Classic under 35 fps, Fast under 25.

**Show FPS and ping** (Settings) puts both under the match clock: low fps means the device, high ping the connection.

High adds:
- volumetric haze that catches the light: sweeping disco beams and spotlit pin decks in Cosmic Lanes, sun haze
  on Sunset Lanes;
- bounce light (SSIL), softer shadows, lacquered lanes and glossy vinyl bowlers;
- a filmic finishing pass (contrast, split toning, vignette, lens fringing, grain) and soft depth of field;
- light flashes, shockwave rings and spark streaks on big hits, and a golden explosion on strikes;
- painted cartoon faces with expressions (angry wind-up, squeezed-shut eyes when hit, happy arcs, X eyes when
  knocked out), blinking and glancing around;
- modelled cosmetics made in Blender (`tools/blender/cosmetics.py`): every hat, the mitts, boxing and cartoon gloves,
  and laced bowling shoes;
- furnished maps with Kenney's CC0 props: an arcade corner, lounge, ball racks and a snack bar in Cosmic Lanes; a
  rooftop bar, parasols, loungers and a real city skyline in Sunset Lanes.

Classic keeps the original 3D look (the menus are the same at every level).

On phones the camera sits closer, PUNCH relabels itself (BOWL!, THROW, BONK), GRAB pulses when a knocked-out
player is in reach, and aim is a little more forgiving (punch targeting, grab reach, bowl assist). On first launch the game watches the menu for a few
seconds and switches itself to Classic if it runs under 35 fps.

### Levels, trophies and unlocks

Every match you finish earns XP (25 for finishing, your points, 5 per knockout, 50 for a win), even if you lose.
The end screen shows your XP filling the level bar and anything you unlocked. **TROPHIES** on the main menu
lists your level, the next level reward and all 15 achievements.

- **Level rewards:** Flame shoes (2), Cowboy hat (3), Laser eyes (4), Tiger outfit (5), Chef hat (6),
  Lava gloves (7), Bunny ears (8), Lava outfit (10), Wizard hat (12).
- **Achievements** (Turkey, Hat Trick, Midas Touch, Buzzer Beater, Fastball, Foul Play...) unlock the rest:
  Golden Pin hat, Crown, Dunce cap, Sparkle eyes, Fangs, Kiss, Gold suit, Rainbow outfit, Diamond gloves,
  Gold accent, Ice and Candy shoes.
- Everything from before stays free. In CUSTOMIZE you can try on a locked item to see it and what earns it.
- Progress is saved on each player's own device, so everyone levels up on their own.

### Make it yours

**Customize** from the menu or the lobby to pick a look: hat, eyes, mouth, outfit, gloves, shoes and accent color,
or start from a preset like *Disco Dan* or *Lane Shark*. Your name and look are saved on your machine. Your player
color stays the main body color, so you're always easy to spot in a pile.

## Development

```
game/
  scripts/              the core, shared by every minigame:
    arena.gd            the minigame base class: every hook a minigame can override, with its default
    game.gd             match: host simulation, scores, snapshots, client interpolation, camera
    beast.gd            the wobbly bowler: physics, fists, grab, throw, knockout ball
    bowler_model.gd     the bowler's look: bean body + outfit/face shader, hats, gloves, shoes
    net.gd              lobby, hosting/joining by room code, LAN discovery, direct IP, party state (autoload)
    relay_peer.gd       MultiplayerPeer that tunnels through the relay over a WebSocket
    party.gd, board.gd  party rules and map (moves, forks, items, events, the star, payouts) and the park itself
    powerups.gd         item boxes, the power-up table, thrown bowling balls
    progress.gd         XP, levels, achievements and which cosmetics they unlock
    bot.gd              bots (host-side; they send the same input as a human)
    skins.gd            cosmetic catalog: add a cosmetic here + a builder in bowler_model
    dressing.gd         loads the Kenney props
    hud.gd, scoreboard.gd, main.gd, ui.gd, menu_art.gd, look.gd, prefs.gd, sfx.gd, music.gd
  minigames/            one folder per minigame, each its own repo (submodule)
    bowling/            Bowling your Friends: Cosmic Lanes, Sunset Lanes, their props, bowling tests
    sumo/               Sumo Ring
  assets/               music, fonts (SIL OFL), cosmetics.glb (tools/blender/cosmetics.py), Kenney props (CC0)
  tests/                core tests: party rules, progression, render benchmark
```

Adding a minigame is adding a folder with a `minigame.gd` and an `Arena` subclass; nothing in the core changes.
[CLAUDE.md](CLAUDE.md) has the details and the workflow for working on several minigames at once.

The host runs all physics (on its own thread) and sends snapshots at 30 Hz. Clients send input and draw just far
enough behind to ride out their connection's jitter (55–150 ms, adaptive), interpolating between snapshots.

```bash
godot --headless --path game -s minigames/bowling/tests/test_bowling.gd   # core-loop test
godot --headless --path game -s minigames/bowling/tests/strike_rate.gd    # map difficulty check (~1 min)
godot --headless --path game -s minigames/bowling/tests/test_powerups.gd  # power-ups
godot --headless --path game -s tests/test_progress.gd                      # progression
godot --headless --path game -s tests/test_party.gd                         # party rules
godot --headless --path game -- --host --bots=3 --party=2 --timescale=3 --quit-after=80   # a whole party with bots
godot --headless --path game -- --host --bots=5 --autostart --timescale=3 --quit-after=30   # bot match, prints REPORT (--map=sunset)
godot --path game -- --join=127.0.0.1 --name=Friend                         # second instance as a client
python3 tools/make_music.py                                                 # re-render the music (numpy + oggenc)
blender -b -P tools/blender/cosmetics.py -- "$PWD/game/assets/models/cosmetics.glb"  # rebuild the 3D cosmetics
cd server && npm install && node relay.js                                   # run the relay locally (port 8080)
godot --path game -- --relay=ws://127.0.0.1:8080 --host-online              # host through the local relay
```
