# Halos & Horns

A free, non-commercial prop-hunt game: demons possess everyday objects to hide, angels hunt them down.
Passion project, inspired by Witch It.

## Status: version 0.4.3, Redemption

One small test map, placeholder shapes for everything.

- **Practice:** single player. The angel side hunts 3 test demons (they hop and taunt so you can find them); the demon side is a sandbox for possessing props.
- **Online:** one player hosts, friends join by address. Mobification rules: caught demons are redeemed and switch to the angels. About one angel per three players.
- **Skills:** pick 2 per side on the main menu or in the lobby. Angels: Flying Dash (dash where you look or the way your keys point, up into the air too; you keep the momentum until you turn: wide turns cost a little, a quick 180 or a strafe kills it), Alarm Cherub (thrown), Vacuum Orb, Holy Leap (steer it in the air; press its key again mid-air to Cloud Stomp), Holy Scripture (a heavy book, big holy damage), Holy Kick (boot a demon away). Demons: Possess, Fly, Hellfire (costs Hatred; angels in the fire are slowed and their blessings burn away).
- **Demons** can **transform** into a copy of any prop (click), or with skills **become** the real one (Possess) and **fly** (hold the key: you rise while Hatred lasts, gravity brings you down; no fall damage).
- The Alarm Cherub just hovers there tooting its little horn until a demon comes close; then it blasts the horn and shows its detection bubble. Shoot it with a blessing to send it flying down a hallway.
- **The shrine:** one per map, the only place to swap skills mid-round. Press G there; a swap takes 3 seconds in total, you can't move while at it, demons have to leave their prop first, and the shrine flares up so everyone knows someone is there. Fresh skills start on cooldown.
- **Chat:** Enter talks to everyone, Backspace to your team only. Everyone is told who redeemed whom, and who the last demon standing is.
- Every prop form has its own health and speed: small = fragile but quick, big = tanky but slow. Your health bar shows how much is left; the number shows real hit points for your current form.

## Playing (Windows)

Download `HalosAndHorns.exe` from the [Releases page](https://github.com/theobigdog/halos_and_horns/releases) and run it. Nothing to install.
Windows may warn "Windows protected your PC" because the game isn't signed; click **More info**, then **Run anyway**.

## Playing (Linux)

Download `HalosAndHorns.x86_64` from the [Releases page](https://github.com/theobigdog/halos_and_horns/releases). Nothing to install, but Linux needs to be told the file is a program before it will run it:

```
chmod +x HalosAndHorns.x86_64
./HalosAndHorns.x86_64
```

(Or in your file manager: right-click the file → Properties → Permissions → allow executing, then double-click it.)

Windows and Linux players can play together.

## Updating

When a newer version is out, the main menu shows an **Update to version ...** button. Click it and the game downloads the new version, replaces itself and restarts. If that can't work (for example the game sits in a folder it isn't allowed to change), the button opens the download page instead.

Making a release (developers): publish a GitHub release tagged like `v0.4.1`. The tag is the version: the build stamps it into the game, so there is no version number to change in the source. Run from source, the game calls itself version "dev".

## Hosting and joining

**Hosting:** click **Host a game**. The lobby shows the addresses friends should use. Pick the hiding and hunting times (and, if you like, a time after which idle players get kicked; you can also kick someone by hand), then click **Start round** once at least 2 players are in.
- Friends on the same Wi-Fi use the "same house" address. That needs no setup.
- Friends over the internet use your internet address, which needs **UDP port 7777 forwarded** on your router to your PC. Windows will also ask to allow the game through the firewall: allow it. On Linux, if you run a firewall, allow UDP port 7777 yourself.

**Joining:** type the host's address, click **Join a game**. Everyone needs exactly the same version as the host; anything else is turned away with a message saying which version to get.

## Playing from the source (developers)

1. Download **Godot 4.3** (standard, *not* .NET): https://godotengine.org/download/archive/4.3-stable/
2. Open Godot, click **Import**, pick `project.godot`, press **F5**.
3. To build the game yourself: Editor → Manage Export Templates → Download, then Project → Export → Windows or Linux. Either one can be built from either operating system.

Both builds are also made automatically: publishing a release on GitHub runs [the release builds workflow](.github/workflows/release-builds.yml), which attaches `HalosAndHorns.exe` and `HalosAndHorns.x86_64` to that release a few minutes later.

## Controls

| Key | Angel | Demon |
| --- | --- | --- |
| WASD / Space | Move / jump | Move / jump |
| Shift | Run (uses sprint stamina) | Run (uses sprint stamina) |
| Ctrl | Sneak | Sneak |
| 1 | Random taunt | Random taunt |
| 2 | Signature taunt | Signature taunt |
| Left click | Throw a blessing (hold to keep throwing; uses blessing stamina) | Transform into a copy of the outlined prop |
| Hold left click | | Back to demon form |
| Q | Skill 1 | Skill 1 |
| Right click | Skill 2 | Skill 2 |
| F | Melee | |
| (hold the key) | | Fly, if it's one of your skills: rise while held, fall when let go |
| T | First/third person | First/third person |
| B | Change blessing type (testing) | |
| G | Swap skills (at the shrine) | Swap skills (at the shrine, in demon form) |
| Enter / Backspace | Chat to everyone / team chat (online; the host can type /kick Name) | Chat to everyone / team chat (online) |
| F1 | Movement tuning panel | Movement tuning panel |
| Esc | Menu | Menu |
| Tab (hold) | Roster: both teams, ping, skills | Roster: both teams, ping, skills |
| F2 / R / Enter | Practice only: switch side / restart / skip the hiding wait | |

## How online play stays fair

The host is the referee. It decides every hit (other players' throws are only visuals on their own screens), checks every movement for speed hacks and out-of-bounds tricks and snaps cheaters back, mirrors blessing stamina and Hatred (flying longer than your Hatred allows, or floating without flying, drops you to the ground), checks every skill against your loadout and cooldowns, and limits taunt spam. Because everyone sees other players a split second in the past, a throw that hits on the thrower's screen still counts: the host checks it was a real throw, that the hit lies on its flight path with no wall in between, and that the demon really was there a moment ago. Only angels receive names, and only their fellow angels', so no game ever knows who a disguised demon is (not even another demon's).

## Automated tests

- `godot --headless -s res://tests/test_gameplay.gd`: practice mode, movement, stamina, taunts.
- `godot --headless -s res://tests/test_skills.gd`: flying, possess vs transform, per-form health and speed, every angel tool.
- `GODOT=godot tests/test_multiplayer.sh`: plays a whole 5-player online match with bots, including a cheater, and checks the results and that no names leak.
- `GODOT=godot tests/test_updater.sh`: exports two builds and checks the older one updates itself to the newer one and restarts (Linux only).

## License

Free forever, never for profit. Code: PolyForm Noncommercial 1.0.0. Art and sound: CC BY-NC-SA 4.0. See [LICENSE.md](LICENSE.md).
