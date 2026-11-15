# Every skill in the game, and loadouts (each player picks 2 per team).
# Keys (both teams): Q = skill 1, right click = skill 2. Angels also have F = melee.
# "Hold" skills (Fly) work while their key is held down.
# Numbers here are first guesses, meant to be tuned in playtests.
extends RefCounted

const SKILLS := {
	# ---- angels ----
	"dash": {"team": "angel", "label": "Flying Dash", "cooldown": 4.0,
		"desc": "Dash any way you like: where you're looking (up into the air too), or the way your movement keys point. You keep the speed afterwards - until you turn. Wide, slow turns cost a little; a quick 180 or a strafe kills it."},
	"cherub": {"team": "angel", "label": "Alarm Cherub", "cooldown": 10.0,
		"desc": "Throw a cherub that stays for 9 seconds. It hovers there tooting its little horn; if a demon comes close it blasts the horn and shows its detection bubble. Hit it with a blessing to send it flying off to check further away."},
	"vacuum": {"team": "angel", "label": "Vacuum Orb", "cooldown": 8.0,
		"desc": "Throw into a pile of props: sucks them in, yanks hidden demons hard, drains their Hatred and locks their skills for 2 seconds."},
	"leap": {"team": "angel", "label": "Holy Leap", "cooldown": 8.0,
		"desc": "A magnificent jump you can steer in the air. Press the key again mid-air to Cloud Stomp: slam down and hurt demons where you land."},
	"scripture": {"team": "angel", "label": "Holy Scripture", "cooldown": 5.0,
		"desc": "Hurl a heavy holy book. Slow and arcing, but it hits a demon far harder than a blessing."},
	"kick": {"team": "angel", "label": "Holy Kick", "cooldown": 4.0,
		"desc": "Boot a demon (or a demon-possessed prop) away from you, so it can't rush you up close."},
	# Not pickable: the second half of Holy Leap.
	"stomp": {"team": "angel", "label": "Cloud Stomp", "cooldown": 0.0, "part_of": "leap"},
	# ---- demons ----
	"fly": {"team": "demon", "label": "Fly", "cooldown": 0.0, "hold": true,
		"desc": "Hold the key to rise, spending Hatred (about 5-6 seconds from full). Let go and you fall. No fall damage."},
	"minion": {"team": "demon", "label": "Minion", "cooldown": 2.0, "hatred": 30.0,
		"desc": "Press to quietly make a decoy of yourself (or the prop you're disguised as) where your crosshair is. Hold the key to steer it: it walks to the ground under your crosshair. It moves like a real player and bumps into things; hits on it look and sound like hits on a demon, but it's flimsy and pops after a hit or two (or 20 seconds). One at a time."},
	"teleport": {"team": "demon", "label": "Teleport", "cooldown": 25.0, "hatred": 60.0,
		"desc": "Blink to where your crosshair points, up to 20 m away (further than that: as far as you can go that way). Very expensive."},
	"fire": {"team": "demon", "label": "Hellfire", "cooldown": 2.0, "hatred": 35.0,
		"desc": "Fling a fireball from your hands; where it lands, fire burns for 6 seconds. Angels caught in it are slowed, stagger about, can barely see straight and their blessings burn away. Costs Hatred, and the fireball shows where it came from."},
	"fear": {"team": "demon", "label": "Fear", "cooldown": 20.0, "hatred": 45.0,
		"desc": "Let out a hellish shriek. Every angel within 10 m who can see you panics for 3 seconds: they run off in a blind scatter, away from you, and can't throw or use skills until it wears off."},
	"possess": {"team": "demon", "label": "Possess", "cooldown": 1.5,
		"desc": "Become a real prop instead of a copy (press its key while aiming at the prop). The one you leave behind slowly dissolves."},
}

const DEFAULTS := {"angel": ["dash", "cherub"], "demon": ["possess", "fly"]}
const SLOT_KEYS := ["Q", "Right click"]

# Tuning
const CHERUB_THROW_SPEED := 11.0 # thrown from the angel's hands: lands and skids ~10-14 m away
const CHERUB_THROW_UP := 3.0
const CHERUB_RADIUS := 6.0       # detection radius
const CHERUB_LIFETIME := 9.0
const CHERUB_KICK_SPEED := 16.0  # how fast a blessing sends it skidding
const CHERUB_KICK_UP := 3.5
const CHERUB_CREEP_SPEED := 0.4 # m/s it drifts toward a demon it has noticed (very slowly: ~3 m in its whole life)
const CHERUB_CREEP_STOP := 1.2  # ...and it stops this close, rather than bumping into them
const CHERUB_FRICTION := 9.0     # m/s lost per second while sliding on the ground (~14 m per kick)
const LEAP_PUSH := 7.0            # sideways speed in the direction you're holding when you leap
const LEAP_AIR_ACCEL := 40.0      # steering while leaping (normal air steering is much weaker)
const SCRIPTURE_DAMAGE := 40       # a blessing does 25
const SCRIPTURE_SPEED := 24.0
const SCRIPTURE_GRAVITY := 14.0
const KICK_RANGE := 2.8
const FEAR_RADIUS := 10.0
const FEAR_TIME := 3.0
const KICK_PUSH := 7.0            # how far a kicked demon flies
const KICK_DAMAGE := 20           # (melee is 34)
const STOMP_SPEED := 30.0
const STOMP_RADIUS := 4.0
const STOMP_DAMAGE := 15
# Hatred for naughtiness (handed out by the host)
const NAUGHTY_FIRE_PER_SEC := 4.0   # per angel standing in your fire
const NAUGHTY_MINION_HIT := 8.0     # an angel wasted a hit on your minion
const NAUGHTY_TAUNT := 4.0          # taunting with an angel within 12 m (at most every 6 s)
const NAUGHTY_TAUNT_RANGE := 12.0
const VANISH_TIME := 6.5          # the Invisibility power-up
const TELEPORT_RANGE := 20.0
const MINION_LIFETIME := 20.0
const MINION_RANGE := 30.0        # how far away you can make one appear
const MINION_HEALTH := 0.4        # share of the copied form's health (a demon body: 2 blessings)
const FIRE_THROW_SPEED := 16.0   # flung from the demon's hands...
const FIRE_THROW_UP := 2.5
const FIRE_GRAVITY := 14.0        # ...in an arc: lands roughly 8-15 m away
const FIRE_LINGER := 2.0          # seconds you keep burning (and staggering) after stepping out
const FIRE_RADIUS := 1.8
const FIRE_LIFETIME := 6.0
const FIRE_SLOW := 0.6            # angels in fire move at 60% speed
const FIRE_BLESSING_BURN := 45.0  # blessing stamina burned per second while standing in fire
const VACUUM_RADIUS := 6.0
const VACUUM_TIME := 2.5
const VACUUM_HATRED_DRAIN := 35.0
const VACUUM_LOCKOUT := 2.0       # seconds a vacuumed demon can't use skills or fly
const LEAP_VELOCITY := 12.0
const MELEE_RANGE := 2.6
const MELEE_DAMAGE := 34          # three hits on a full-health demon
const MELEE_COOLDOWN := 0.6


static func label(id: String) -> String:
	return SKILLS[id]["label"] if SKILLS.has(id) else "-"


static func hatred_cost(id: String) -> float:
	return SKILLS[id].get("hatred", 0.0) if SKILLS.has(id) else 0.0


static func cooldown(id: String) -> float:
	return SKILLS[id]["cooldown"] if SKILLS.has(id) else 0.0


static func for_team(team: String) -> Array:
	var ids := []
	for id in SKILLS:
		if SKILLS[id]["team"] == team and not SKILLS[id].has("part_of"):
			ids.append(id)
	return ids


# Exactly 2 slots, each a real skill of that team or "" (empty), no duplicates.
static func clean_loadout(team: String, wanted) -> Array:
	var out := ["", ""]
	if typeof(wanted) != TYPE_ARRAY:
		return DEFAULTS[team].duplicate()
	for i in mini(2, wanted.size()):
		var id = wanted[i]
		if id == "chicken":
			id = "cherub"   # renamed in 0.4
		if id == "grapple":
			id = "dash"     # the hook became the Flying Dash
		if id == "vanish":
			id = "minion"   # Invisibility became a power-up in 0.5.2
		if typeof(id) == TYPE_STRING and SKILLS.has(id) and SKILLS[id]["team"] == team \
				and not SKILLS[id].has("part_of") and not id in out:
			out[i] = id
	return out
