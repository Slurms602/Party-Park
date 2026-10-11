# Research: Gang Beasts + Super Battle Golf → Bowling your Friends

Static analysis of the locally installed builds (nothing was executed). Super Battle Golf ships Mono
assemblies, so REA's managed inspector read `Managed/GameAssembly.dll` directly (REA evidence
`ev_3b6e26ac…` artifact, `ev_b8f0745d…` members: 1463 types, 14382 methods, 10540 fields).
Gang Beasts is IL2CPP, so names came from `il2cpp_data/Metadata/global-metadata.dat` (v29: 2217
Assembly-CSharp types) via a small metadata reader; constant values come from its field-default table.

Names and constants below are **observed**. How they behave at runtime is **inferred** from those
names: no tuning assets (`data.unity3d`, Unity scenes) were decoded, so all our numbers are our own.

## Gang Beasts: physics and brawling

| Observation | What we take from it |
|---|---|
| `Femur.BodyHandeler`: Head, Chest, Waist, Stomach, Hips, arm/forearm/hand, thigh/leg/foot **plus `Ball` and `Spring`**; `RunCycleRotateBall`, `RunCyclePoseLeg` | The wobbly body rides on a hidden rolling ball held up by a spring, and the legs are posed procedurally. We use one physics body that a torque spring keeps upright, plus procedural limbs. It wobbles when hit, and it costs little to sync over the network. |
| `ArmActionReadying → ArmActionPunching → ArmActionPunchResetting`, `HeadActionHeadbutting`, `LegActionKicking`, `dropkickFix`, `inputSpamForceModifier` | Punches have three phases: wind-up, strike, recover. Spamming the button is weaker. |
| `StatusHandeler`: health, stamina, `knockoutThreshold`, `min/maxUnconsciousTime`, `healthRegeneration`, `ReviveCheck`, `kInvincibleTime = 2` | Health regenerates. At zero you're knocked out for a random time, and mashing buttons wakes you sooner. You get **2 s of invincibility** after waking. |
| `CollisionHandeler.DamageCheck`, `damageMinimumVelocity`, per-part `damageModifier` | Damage comes from impact speed, not hit-scan. Our bowled bodies and dive tackles hurt in proportion to their speed. |
| `Grab` enum: Break / DrainSlow / DrainMedium / DrainFast / Perminant; `leftGrabJoint`, `rightGrabJoint`; `Lift`, `grabJump` | Grabs attach with a joint and drain stamina, so you can't hold someone forever. Grabbed players can be dragged and thrown. |
| `TargetingHandeler`: `MAX_FORWARD_UPPER_TARGET_DIST = 4`, `BACKWARD = 2`, `LOWER = 2`, `throwPoints` | Light aim assist: attacks turn toward the nearest player within about 4 m in front. |
| `ActorState`: Dead, Unconscious, Stand, Run, Jump, Fall, Climb, Swim, Drive, Idle | Our state machine, minus climb, swim and drive. |
| `DominantRigidbody` / `SubmissiveRigidbody` sync | They needed custom physics-authority tricks. We keep it simple: the host runs all physics. |

## Super Battle Golf: combat, knockouts, game feel

| Observation | What we take from it |
|---|---|
| `Hittable.BecomeSwingProjectile`, `KnockoutType.SwingProjectile / ReflectedSwingProjectile`, `ProjectileMinHitCollisionSpeed` | **Whatever you launch becomes a projectile that knocks out anyone it hits.** This is the core of bowling a friend: a bowled player flattens other players in their path. |
| `KnockoutState`: None, OnGround, InAir, Recovering; `KnockoutRecoveryType`: FromFront/Back/Left/Right; `PlayerKnockedOutMaterial`, `KnockOut*Damping`, `KnockOutGravityFactor` | A knocked-out body swaps to a bouncier, lower-friction physics material and rolls. |
| `PostKnockoutImmunity{Default,Long}Duration`, `MinRecentKnockoutCountForLongImmunityDuration`, `KnockOutImmunity` | Immunity after a knockout stops spawn-camping. Ours: 2 s after waking or coming back out of the ball return. |
| `DiveHorizontalSpeed`, `DiveUpwardsSpeed`, `DiveGetUpDuration`, `DiveHittableSettings` (min/max relative speed → knockback) | **Dive tackle** that knocks people back according to closing speed, followed by a short belly-flop recovery. |
| `SwingChargingSpeed`, `SwingPowerBarUi`, `ReleaseSwingCharge`, `MaxPowerSwingHitSpeed` | Hold to charge, release to hit; you move slower while charging. We use the same input for the haymaker and the bowl. |
| `EliminationResponsibilityDuration`, `responsibleSwingProjectilePlayer` | The last player to launch a ball gets credit for the pins. |
| `InfoFeed`: Knockout / Domination / Revenge / Comeback messages; `KnockoutStreak`; `FirstPlaceCrownVfx`; `ComebackBonus{MinPointsGap, BonusMultiplier}` | Kill feed, a crown on the leader, and a comeback bonus for players who are behind. |
| `ImpactFrameController`, `ScreenshakeSettings{Duration, DistanceIntensityFactor}`, `KnockedOutVfx.SetColoredStarCount` | Hit-stop and screen shake that fade with distance, and stars over knocked-out heads. |
| `ItemType`: DuelingPistol, ElephantGun, Airhorn, SpringBoots, RocketLauncher, Landmine, FreezeBomb, … | Items are arcade-style and over the top. Our first weapon fits the theme: **pick up a bowling pin and use it as a club.** |

## Super Battle Golf: UI, music, cosmetics (second pass)

| Observation | What we take from it |
|---|---|
| `TeeOffCountdown`, `MatchEndCountdown{preOvertimeUrgencyThreshold, urgencyPopSizeFactor, urgencyColor}` | A 3-2-1-BOWL! countdown at the start. In the last 10 s the clock pops and turns red every second. |
| FMOD strings: one theme per course plus `Main Menu Music`; music-bank timelines marked `Hurry version` + `Transition`; announcer `10 Seconds Remaining`, `Overtime` | Music has a menu theme, a match theme, a **hurry version** for the final 30 s (with a HURRY UP! banner) and a victory jingle. |
| `UiSfx.Type`: MainMenuButton, PauseMenuButton, SettingsTab, Slider, StartMatch...; `MainMenuButton{animator, pointerHover}` | Every button bounces and tilts on hover with a tick, and pops on click. |
| `InfoFeedMessage{preIconText, icon1, icon2, postIconText}` | Kill-feed chips: [name] [VERB pill] [name]. |
| `SwingPowerBarUi{overchargeFill, overchargedPopScaleAddition, shakeTween}` | A power bar floats over your bowler while you wind up. It wobbles and shows MAX! at full charge. |
| `ButtonPrompt`, `WorldspaceIconUi{offscreenArrow, distanceLabel}` | Context key prompts (GRAB THEM, WIND UP / BOWL!, GET BEHIND THE FOUL LINE) and a bouncing GRAB! marker over downed players. |
| `ScoreboardEntry{ranking, knockouts, knockoutMedal, wins, hostIcon}` | Ranked scoreboard rows with a crown for the leader. Results show points, strikes, spares and KOs. |
| `TransportType`: Kcp, Steam. `LobbyMode`: Public, Friends, InviteOnly. `BNetworkManager.ConnectToSteamFriend`, `OnSteamGameLobbyJoinRequested`, `LobbyBrowser` | Hosting is painless because of Steam's relay and lobbies. Until we're on Steam, our own relay gives the same "host, share a code, friends join" flow without port forwarding. |
| `MainMenu{background, panAmount}`, `MainMenuScenario` | The menu sits over a live alley where bots brawl and bowl. |
| `PlayerCosmetics` / `Loadout`: Head, Hat, Face, FaceLower, Body, Shoes, Eyes, Mouth, Brows, Cheeks, SkinColor, VictoryDance...; `CustomizationMenuPreview` | Skins are a loadout of slots (hat, eyes, mouth, outfit, gloves, shoes, accent) shown on a turntable preview. The winner dances on the results screen. |

## What Bowling your Friends uses

- **Body:** wobbly upright body kept up by a torque spring, plus procedural jelly limbs (GB). Hits physically knock you around.
- **Fists:** tap for a jab (alternating hands); hold for a charged haymaker (SBG charge). Aim assist toward the nearest target (GB targeting).
- **Dive tackle** (SBG) and **grab / drag / throw** with a hold time limit (GB).
- **Health hits zero → you curl into a ball** (GB unconscious + SBG knockout physics material). Mash buttons to wake sooner; 2 s immunity afterwards.
- **Bowling:** grab a balled player, hold punch to charge, release to bowl. The bowled player becomes a projectile that flattens anyone in the way (SBG swing projectile). Hitting the bowler makes them drop the ball, which is where the chaos comes from.
- **Scoring:** pins knocked down give points, with Strike and Spare bonuses. Pins get re-racked over time. The bowled player comes back out of the ball return with immunity.
- **Bowling pins as clubs**: the first weapon.
- **Game feel:** kill feed, crown on the leader, comeback bonus, screen shake, hit flash, stars.
- **Overhead alley scoreboard** (X, /, –, running totals) and a match timer; most points wins.
- **Look:** a 90s "cosmic bowling" alley: blacklight carpet, glossy wooden lanes, neon, bloom. Bright jelly-bean bowlers with outlines.
