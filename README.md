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
3. **Host game** → add bots with **+ Bot** if you like → **START MATCH**.
   Friends click **Join game** and enter your IP. Over the internet, forward **UDP 7777** or share a LAN VPN
   such as Tailscale or ZeroTier.

To give friends a build: **Project → Export** in Godot. Windows and Linux presets are included; Godot will
offer to download the export templates the first time.

### Controls

| Action | Keyboard + mouse | Gamepad |
|---|---|---|
| Move | WASD / arrows | Left stick |
| Punch: tap = jab, hold = haymaker | Left mouse / J | RT / X |
| Grab: hold to keep hold | Right mouse / K | LT / RB |
| Bowl: hold Grab on a ball, hold Punch to charge, release | | |
| Jump | Space | A |
| Dive tackle | Shift / L | B |
| Menu | Esc | Start |

### Rules

- When your health hits zero you curl into a ball for about 7 s. **Mash buttons** to wake up sooner, or to
  wriggle free while someone is carrying you.
- Pins knocked down = points. **Strike** gives +10 bonus and **Spare** +5. A bowled body that runs someone
  over gives +2. If you're 30+ points behind, your rolls are worth ×1.5.
- Leftover pins stay up for 12 s, so you can go for the spare. Then the pinsetter re-racks the lane.
- Bowled players come back out of the ball return with 2 s of immunity.
- Pick up a pin with Grab and Punch to swing it as a club.

## Development

```
game/
  scripts/net.gd        lobby and ENet connection (autoload)
  scripts/game.gd       match: host simulation, scoring, snapshots, client interpolation, camera
  scripts/beast.gd      the wobbly bowler: movement, fists, grab, bowl, knockout ball
  scripts/arena.gd      alley geometry and shaders, pins, roll detection, re-racks
  scripts/bot.gd        bots (host-side; they send the same input as a human)
  scripts/hud.gd, scoreboard.gd, main.gd, sfx.gd (synthesized sounds), look.gd (materials)
  tests/test_bowling.gd headless test of knockout → grab → bowl → score → re-rack
```

The host runs all physics and sends snapshots at 30 Hz. Clients send input and draw about 100 ms behind,
interpolating between snapshots.

```bash
godot --headless --path game -s tests/test_bowling.gd                       # core-loop test
godot --headless --path game -- --host --bots=5 --autostart --timescale=3 --quit-after=30   # bot match, prints REPORT
godot --path game -- --join=127.0.0.1 --name=Friend                         # second instance as a client
```
