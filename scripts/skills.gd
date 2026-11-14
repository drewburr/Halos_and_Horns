# Every skill in the game, and loadouts (each player picks 2 per team).
# Keys (both teams): Q = skill 1, right click = skill 2. Angels also have F = melee.
# "Hold" skills (Fly) work while their key is held down.
# Numbers here are first guesses, meant to be tuned in playtests.
extends RefCounted

const SKILLS := {
	# ---- angels ----
	"grapple": {"team": "angel", "label": "Grappling Hook", "cooldown": 6.0,
		"desc": "Zip to walls and roofs, or snag a demon: damages it and drags it to you."},
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
	"fire": {"team": "demon", "label": "Hellfire", "cooldown": 2.0, "hatred": 35.0,
		"desc": "Fling a fireball that leaves a patch of fire for 6 seconds. Angels caught in it are slowed and their blessings burn away. Costs Hatred, and the fireball shows where it came from."},
	"possess": {"team": "demon", "label": "Possess", "cooldown": 1.5,
		"desc": "Become a real prop instead of a copy (press its key while aiming at the prop). The one you leave behind slowly dissolves."},
}

const DEFAULTS := {"angel": ["grapple", "cherub"], "demon": ["possess", "fly"]}
const SLOT_KEYS := ["Q", "Right click"]

# Tuning
const GRAPPLE_RANGE := 40.0
const GRAPPLE_SPEED := 20.0       # m/s while zipping toward the hook
const GRAPPLE_DAMAGE := 20
const CHERUB_THROW_SPEED := 11.0 # thrown from the angel's hands: lands and skids ~10-14 m away
const CHERUB_THROW_UP := 3.0
const CHERUB_RADIUS := 6.0       # detection radius
const CHERUB_LIFETIME := 9.0
const CHERUB_KICK_SPEED := 16.0  # how fast a blessing sends it skidding
const CHERUB_KICK_UP := 3.5
const CHERUB_FRICTION := 9.0     # m/s lost per second while sliding on the ground (~14 m per kick)
const LEAP_PUSH := 7.0            # sideways speed in the direction you're holding when you leap
const LEAP_AIR_ACCEL := 40.0      # steering while leaping (normal air steering is much weaker)
const SCRIPTURE_DAMAGE := 40       # a blessing does 25
const SCRIPTURE_SPEED := 24.0
const SCRIPTURE_GRAVITY := 14.0
const KICK_RANGE := 2.8
const KICK_PUSH := 7.0            # how far a kicked demon flies
const KICK_DAMAGE := 5
const STOMP_SPEED := 30.0
const STOMP_RADIUS := 4.0
const STOMP_DAMAGE := 15
const FIRE_RANGE := 15.0
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
		if typeof(id) == TYPE_STRING and SKILLS.has(id) and SKILLS[id]["team"] == team \
				and not SKILLS[id].has("part_of") and not id in out:
			out[i] = id
	return out
