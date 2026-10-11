# Bowling your Friends

A chaotic online party brawler. Beat your friends until they curl up into a ball, then bowl them down the
lane for points. There are no turns: four lanes, a running clock, and whoever has the most points when time
runs out wins. Anyone can wreck a bowl in progress by punching the bowler or diving in front of the ball.

The combat and physics mix **Gang Beasts** (wobbly bodies, grabbing, mash-to-wake knockouts) with
**Super Battle Golf** (charged swings, dive tackles, launched bodies that flatten whoever they hit, comeback
bonus). The look is a 90s cosmic bowling alley. See [docs/RESEARCH.md](docs/RESEARCH.md) for what was pulled
from each game and why.

## Play

1. Install [Godot 4.7](https://godotengine.org/download) (standard build, no .NET needed).
2. Open `game/project.godot` and press **Play** (F5).
3. **HOST GAME** gives you a 4-letter **room code**. Add bots with **+ BOT** if you like, then **START MATCH**.
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

### Maps

The host picks the map in the lobby.

- **Cosmic Lanes**: the blacklight alley. Four lanes, tight pins, strikes come easy.
- **Sunset Lanes**: a rooftop alley at golden hour. Three longer, wider lanes with bigger, more spread-out
  pins, and less aim assist. You get about half as many strikes (28% vs 53% in `tests/strike_rate.gd`),
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

### Make it yours

**Customize** from the menu or the lobby to pick a look: hat, eyes, mouth, outfit, gloves, shoes and accent color,
or start from a preset like *Disco Dan* or *Lane Shark*. Your name and look are saved on your machine. Your player
color stays the main body color, so you're always easy to spot in a pile.

## Development

```
game/
  scripts/net.gd        lobby, hosting/joining by room code, LAN discovery, direct IP (autoload)
  scripts/relay_peer.gd MultiplayerPeer that tunnels through the relay over a WebSocket
  scripts/game.gd       match: host simulation, scoring, snapshots, client interpolation, camera
  scripts/beast.gd      the wobbly bowler: physics, fists, grab, bowl, knockout ball
  scripts/bowler_model.gd  the bowler's look: bean body + outfit shader, face with expressions, hats, gloves, shoes
  scripts/skins.gd      cosmetic catalog (slots, options, presets): add a cosmetic here + a builder in bowler_model
  scripts/ui.gd         UI kit (theme, bouncy buttons, panels); prefs.gd saved profile; music.gd music player
  scripts/arena.gd      alley geometry and shaders, pins, roll detection, re-racks (Cosmic Lanes)
  scripts/sunset_arena.gd  Sunset Lanes: extends Arena with its own sizes and look
  scripts/powerups.gd   item boxes, the power-up table, thrown bowling balls
  scripts/bot.gd        bots (host-side; they send the same input as a human)
  scripts/hud.gd, scoreboard.gd, main.gd, sfx.gd (synthesized sounds), look.gd (materials, fonts)
  assets/music          menu, match, hurry and victory tracks, rendered by tools/make_music.py
  assets/fonts          Lilita One + Fredoka (SIL Open Font License)
  tests/test_bowling.gd headless test of knockout → grab → bowl → score → re-rack
  tests/strike_rate.gd  bowls randomized human-ish throws on every map and compares strike rates
  tests/test_powerups.gd  item boxes and every power-up
```

The host runs all physics and sends snapshots at 30 Hz. Clients send input and draw about 100 ms behind,
interpolating between snapshots.

```bash
godot --headless --path game -s tests/test_bowling.gd                       # core-loop test
godot --headless --path game -s tests/strike_rate.gd                        # map difficulty check (~1 min)
godot --headless --path game -s tests/test_powerups.gd                      # power-ups
godot --headless --path game -- --host --bots=5 --autostart --timescale=3 --quit-after=30   # bot match, prints REPORT (--map=sunset)
godot --path game -- --join=127.0.0.1 --name=Friend                         # second instance as a client
python3 tools/make_music.py                                                 # re-render the music (numpy + oggenc)
cd server && npm install && node relay.js                                   # run the relay locally (port 8080)
godot --path game -- --relay=ws://127.0.0.1:8080 --host-online              # host through the local relay
```
