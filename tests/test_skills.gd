# Automated test of flying, possess vs transform, and the angel tools, in practice mode.
#   godot --headless -s res://tests/test_skills.gd
extends SceneTree

const Skills = preload("res://scripts/skills.gd")
const PropLib = preload("res://scripts/prop_library.gd")

var main: Node
var failures := 0


func _initialize() -> void:
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	_run.call_deferred()


func check(cond: bool, what: String) -> void:
	print(("PASS  " if cond else "FAIL  ") + what)
	if not cond:
		failures += 1


func frames(n: int) -> void:
	for i in n:
		await physics_frame


# Stand a few meters from target with a clear crosshair line to it.
func aim_at(player, target: Node3D, aim_height: float, dist := 3.5) -> bool:
	var aim_point := target.global_position + Vector3.UP * aim_height
	for i in 16:
		var angle := TAU * i / 16.0
		var spot := target.global_position + Vector3(cos(angle), 0, sin(angle)) * dist
		player.global_position = spot + Vector3.UP * 0.1
		player.velocity = Vector3.ZERO
		player.look_at(Vector3(aim_point.x, player.global_position.y, aim_point.z))
		await frames(2)
		for pass_num in 4:
			var eye: Vector3 = player.camera.global_position
			var flat := Vector2(aim_point.x - eye.x, aim_point.z - eye.z).length()
			player.pivot.rotation.x = clampf(atan2(aim_point.y - eye.y, flat), -1.4, 1.2)
			await frames(1)
		var hit: Dictionary = player._aim_ray(20.0)
		if not hit.is_empty() and hit["collider"] == target:
			return true
	return false


# Stand still in the open, facing -z, ready to dash.
# With up_high, floating well above the props and roofs (the test switches gravity off).
func dash_setup(player, up_high := false) -> void:
	player.test_input = {}
	player.global_position = Vector3(8, 14.0 if up_high else 0.1, 18)
	player.rotation = Vector3.ZERO
	player.pivot.rotation.x = 0.0
	player.velocity = Vector3.ZERO
	player.clear_dash()
	player.skill_cd.clear()
	await frames(5)


func visible_props() -> Array:
	var out := []
	for p in main.props:
		if is_instance_valid(p) and p.is_in_group("prop"):
			out.append(p)
	return out


func _run() -> void:
	await frames(5)
	main.role = "demon"
	main.start_practice()
	await frames(5)
	var player = main.player
	player.rotation = Vector3.ZERO

	# ---- Flying (a demon skill: hold its key to rise, let go to fall) ----
	player.loadout["demon"] = ["possess", "fly"]
	player.global_position = Vector3(0, 0.1, 20)
	player.hatred = player.HATRED_MAX
	await frames(5)
	player.test_input = {"fly": true}
	await frames(60)
	check(player.flying and player.global_position.y > 3.0, "holding the Fly key rises (y %.1f)" % player.global_position.y)
	player.test_input = {"fly": true, "dir": Vector2(1, 0)}
	var x_before: float = player.global_position.x
	await frames(30)
	check(player.global_position.x > x_before + 1.5, "WASD steers while flying")
	player.test_input = {}
	var y_top: float = player.global_position.y
	await frames(150)   # coasts upward first (it was rising fast), like the top of a jump
	check(player.global_position.y < y_top - 0.3, "letting go: gravity takes you down (%.1f -> %.1f, flying %s)" % [y_top, player.global_position.y, player.flying])
	await frames(90)
	check(player.is_on_floor(), "...all the way to the ground (no fall damage either)")

	player.hatred = player.HATRED_MAX
	var seconds := 0.0
	player.test_input = {"fly": true}
	while seconds < 1.0 or (player.flying and seconds < 15.0):
		await frames(6)
		seconds += 0.1
	check(seconds > 5.0 and seconds < 8.5, "a full Hatred bar gives 5-8 s of flight (%.1f s)" % seconds)
	await frames(30)
	check(not player.flying, "out of Hatred: no more lift")
	player.test_input = {}
	await frames(240)

	player.hatred = player.HATRED_MAX
	player.hatred_regen_multiplier = 6.0   # the future fast-Hatred power-up
	player.test_input = {"fly": true}
	await frames(660)
	check(player.flying, "with fast Hatred regen you can fly endlessly (11 s and counting)")
	player.hatred_regen_multiplier = 1.0
	player.test_input = {}
	await frames(300)

	player.hatred = player.HATRED_MAX
	player.skill_lock = 2.0
	player.test_input = {"fly": true}
	await frames(20)
	check(not player.flying, "can't fly during a vacuum lockout")
	player.skill_lock = 0.0
	player.test_input = {}
	await frames(30)

	player.loadout["demon"] = ["possess", ""]
	player.test_input = {"fly": true}
	await frames(20)
	check(not player.flying, "no Fly skill picked: no flying")
	player.loadout["demon"] = ["possess", "fly"]
	player.test_input = {}

	player.force_possess("hay")
	await frames(2)
	player.hatred = player.HATRED_MAX
	player.test_input = {"fly": true}
	await frames(40)
	check(player.flying and player.global_position.y > 1.5, "props can fly (a flying hay bale)")
	player.test_input = {}
	await frames(120)

	# ---- Per-form health and speed ----
	check(PropLib.max_hp("books") < PropLib.max_hp("") and PropLib.max_hp("") < PropLib.max_hp("hay"),
			"small props have less health than a demon, big ones more")
	var form_speeds := {}
	for form in ["books", "", "hay"]:
		if form == "":
			player.unpossess()
		else:
			player.force_possess(form)
		player.global_position = Vector3(-20, 0.1, 20)
		player.velocity = Vector3.ZERO
		player.rotation = Vector3.ZERO
		await frames(5)
		player.test_input = {"dir": Vector2(1, 0)}
		await frames(30)
		form_speeds[form] = Vector2(player.velocity.x, player.velocity.z).length()
		player.test_input = {}
	check(form_speeds["books"] > form_speeds[""] and form_speeds[""] > form_speeds["hay"],
			"books run faster than a demon, hay bales slower (%.1f / %.1f / %.1f)" % [form_speeds["books"], form_speeds[""], form_speeds["hay"]])
	player.unpossess()
	await frames(5)

	# ---- Transform vs possess ----
	var props_before := visible_props().size()
	var first: Node3D = null
	for p in visible_props():
		if await aim_at(player, p, 0.2):
			first = p
			break
	check(first != null, "lined up on a prop")
	player.try_transform()
	await frames(2)
	check(player.possessed_type == first.get_meta("prop_type") and player.possessed_index == -1,
			"left click transforms into a copy")
	check(visible_props().size() == props_before and first.visible, "the original stays put when transforming")
	player.unpossess()
	await frames(5)

	player.loadout["demon"] = ["possess", ""]
	check(await aim_at(player, first, 0.2), "lined up again")
	await frames(2)
	check(player.use_skill(0), "Q possesses the prop under the crosshair")
	await frames(2)
	check(player.possessed_index == first.get_meta("prop_index"), "we ARE that prop now")
	check(not first.visible and not first.is_in_group("prop"), "the original is gone (we took its place)")
	check(player.global_position.distance_to(first.global_position) < 0.05, "we moved exactly to where it stood")
	check(visible_props().size() == props_before - 1, "possessing doesn't add a duplicate prop")

	var second: Node3D = null
	var others := visible_props()
	others.sort_custom(func(a, b): return a.global_position.distance_to(first.global_position) < b.global_position.distance_to(first.global_position))
	for p in others:
		if await aim_at(player, p, 0.2, 3.0):
			second = p
			break
	check(second != null, "found a second prop to hop into")
	if second:
		player.skill_cd.clear()
		player.global_position = first.global_position
		await aim_at(player, second, 0.2, 3.0)
		await frames(2)
		var left_at: Vector3 = player.global_position
		player.use_skill(0)
		await frames(2)
		check(player.possessed_index == second.get_meta("prop_index"), "hopped into the second prop")
		check(first.visible and not first.is_in_group("prop"), "the first prop was left behind")
		check(first.global_position.distance_to(left_at) < 0.05, "...exactly where we left it")
		await frames(120)
		var mi: MeshInstance3D = first.get_child(0).get_child(0)
		check(mi.material_override.albedo_color.a < 0.9, "...and it's slowly dissolving")
		await frames(300)
		check(not is_instance_valid(first), "...until it's gone")
	player.unpossess()
	await frames(5)
	check(second == null or (is_instance_valid(second) and second.visible), "leaving a possessed prop leaves it behind too")
	var walk_from: Vector3 = player.global_position
	player.test_input = {"dir": Vector2(0, -1)}
	await frames(30)
	player.test_input = {}
	var walked := Vector2(player.global_position.x - walk_from.x, player.global_position.z - walk_from.z).length()
	check(walked > 1.0, "you can walk away right away, not stuck inside the prop you left (%.1f m)" % walked)

	# ---- Angel tools vs the test demons ----
	main.role = "angel"
	main.start_round()
	main.time_left = 0.0
	await frames(5)
	player.loadout["angel"] = ["cherub", "vacuum"]
	var bot = get_nodes_in_group("demon")[0]

	# Cherub: near a demon it alarms, far away it doesn't.
	main.authority_skill(player, 0, "cherub", player.global_position, Vector3.FORWARD, bot.global_position + Vector3(2, 0, 0), -1)
	main.authority_skill(player, 0, "cherub", player.global_position, Vector3.FORWARD, Vector3(0, 0, -26), -1)
	await frames(30)
	var near_c = main.cherubs.get(1)
	var far_c = main.cherubs.get(2)
	check(near_c != null and near_c.alarmed, "a cherub near a hidden demon squawks")
	check(far_c != null and not far_c.alarmed, "a cherub with no demon nearby stays calm")
	check(near_c != null and near_c._bubble.visible, "...and shows its detection bubble")
	check(far_c != null and not far_c._bubble.visible, "...a calm cherub shows no bubble, it's just a cherub")

	# Knock the calm cherub down the "hallway" with a blessing.
	if far_c != null:
		var c_start: Vector3 = far_c.global_position
		var shot = preload("res://scripts/projectile.gd").new()
		shot.velocity = Vector3(30, 0, 0)
		shot.shooter = player
		main.add_child(shot)
		shot.global_position = c_start + Vector3(-3, 0.4, 0)
		await frames(150)
		var moved: float = far_c.global_position.x - c_start.x
		check(moved > 6.0, "a blessing sends the cherub skidding (%.1f m)" % moved)
		check(absf(far_c.velocity.x) < 0.3, "...and it slides to a stop")
		check(main._auth_cherubs.has(2) and main._auth_cherubs[2]["pos"].distance_to(far_c.global_position) < 0.5,
				"...and it keeps watching from where it landed")

	# Vacuum: pulls nearby props in and yanks the demon.
	var center: Vector3 = bot.global_position + Vector3(3, 0, 0)
	var near_props := []
	for p in visible_props():
		var d := Vector2(p.global_position.x - center.x, p.global_position.z - center.z).length()
		if d < Skills.VACUUM_RADIUS and d > 1.5:
			near_props.append([p, d])
	var bot_dist_before: float = bot.global_position.distance_to(center)
	main._vacuum_at(center)
	await frames(90)
	check(bot.global_position.distance_to(center) < bot_dist_before - 1.0, "the vacuum yanks the demon toward its center")
	var pulled := true
	for pd in near_props:
		var d2 := Vector2(pd[0].global_position.x - center.x, pd[0].global_position.z - center.z).length()
		if d2 > pd[1] - 0.3:
			pulled = false
	check(pulled, "the vacuum drags nearby props in too (%d props)" % near_props.size())

	# Melee: three hits catch a full-health test demon.
	var bot2 = get_nodes_in_group("demon")[1]
	check(await aim_at(player, bot2, 0.3, 1.8), "standing next to a demon")
	var health_before: int = bot2.health
	player.melee_cd = 0.0
	player.melee()
	await frames(2)
	check(bot2.health == health_before - Skills.MELEE_DAMAGE, "F melee hits a demon (%d -> %d)" % [health_before, bot2.health])

	# Flying Dash: a burst in any direction that leaves momentum behind.
	player.loadout["angel"] = ["dash", "leap"]
	# Up in the air with gravity off, so no prop or wall gets in the way.
	var saved: Dictionary = player.tuning.duplicate()
	player.tuning["gravity_scale"] = 0.0
	player.tuning["dash_air_drag"] = 9.0
	await dash_setup(player, true)
	check(player.use_skill(0), "Flying Dash")
	check(not player.use_skill(0), "...which then has a cooldown")
	await frames(20)
	var burst: float = 18.0 - player.global_position.z
	check(burst > 3.5 and absf(player.global_position.x - 8.0) < 0.3, "dashed straight ahead (%.1f m)" % burst)
	var gave: float = player.dash_momentum()
	check(gave > 10.0, "...and kept momentum afterwards (%.1f m/s)" % gave)
	var z_then: float = player.global_position.z
	await frames(20)
	check(player.global_position.z < z_then - 1.5, "the momentum carries you on with no keys held")
	check(player.dash_momentum() > 5.0, "...for a while")
	check(player.dash_momentum() < gave, "...fading as you slide (%.1f m/s)" % player.dash_momentum())
	await frames(150)
	check(player.dash_momentum() == 0.0, "...until it's gone")

	# Turning costs momentum. (No fading here, so only the turning counts.)
	player.tuning["dash_air_drag"] = 0.0
	await dash_setup(player, true)
	player.use_skill(0)
	await frames(20)
	gave = player.dash_momentum()
	player.rotate_y(PI)
	await frames(2)
	check(player.dash_momentum() == 0.0, "a quick 180 kills all the momentum")

	await dash_setup(player, true)
	player.use_skill(0)
	await frames(20)
	for i in 120:
		player.rotate_y(PI / 120.0)
		await frames(1)
	var kept: float = player.dash_momentum() / gave
	check(kept > 0.5 and kept < 0.8, "a wide, slow 180 keeps most of it (%d%%)" % roundi(kept * 100.0))
	var facing: Vector3 = -player.global_transform.basis.z
	check(player.velocity.normalized().dot(facing) > 0.95, "...and it follows you round the turn")

	await dash_setup(player, true)
	player.use_skill(0)
	await frames(20)
	for i in 30:
		player.rotate_y(PI / 30.0)
		await frames(1)
	var kept_fast: float = player.dash_momentum() / gave
	check(kept_fast < kept - 0.3, "the same turn made faster loses more (%d%%)" % roundi(kept_fast * 100.0))

	await dash_setup(player, true)
	player.use_skill(0)
	await frames(20)
	player.test_input = {"dir": Vector2(1, 0)}
	await frames(2)
	kept = player.dash_momentum() / gave
	check(kept > 0.4 and kept < 0.6, "strafing sideways costs half (%d%%)" % roundi(kept * 100.0))
	player.test_input = {"dir": Vector2(-1, 0)}
	await frames(2)
	check(player.dash_momentum() == 0.0, "...and strafing back the other way kills the rest")
	player.test_input = {}
	player.tuning = saved
	# On a roof (no props up there to bump into), with a short burst so we stay on it.
	player.tuning["dash_time"] = 0.1
	await dash_setup(player)
	player.global_position = Vector3(8, 4.1, 10.5)
	await frames(5)
	player.use_skill(0)
	await frames(8)
	gave = player.dash_momentum()
	await frames(10)
	player.tuning["dash_time"] = saved["dash_time"]
	check(gave > 8.0 and player.is_on_floor() and player.dash_momentum() < gave - 1.0, "on the ground the momentum fades faster (%.1f -> %.1f m/s)" % [gave, player.dash_momentum()])

	# Any direction: backwards with the back key held, or up into the air.
	await dash_setup(player)
	player.test_input = {"dir": Vector2(0, 1)}
	await frames(1)
	player.use_skill(0)
	await frames(15)
	player.test_input = {}
	check(player.global_position.z > 18.0 + 3.0, "holding back dashes backwards (%.1f m)" % (player.global_position.z - 18.0))
	await dash_setup(player)
	player.pivot.rotation.x = 1.0
	await frames(2)
	player.use_skill(0)
	var top := 0.0
	for i in 90:
		await frames(1)
		top = maxf(top, player.global_position.y)
	check(top > 5.0, "looking up dashes into the air (%.1f m up)" % top)
	player.pivot.rotation.x = 0.0
	# The invisible map walls still stop you.
	await dash_setup(player)
	player.global_position = Vector3(22, 0.1, 18)
	player.rotation.y = -PI / 2.0
	await frames(2)
	player.use_skill(0)
	player.test_input = {"dir": Vector2(0, -1)}
	await frames(90)
	player.test_input = {}
	check(player.global_position.x < 28.6, "the invisible map wall still stops a dash (x %.1f)" % player.global_position.x)
	check(player.dash_momentum() == 0.0, "...and running into it ends the momentum")
	check(Skills.clean_loadout("angel", ["grapple", "leap"]) == ["dash", "leap"], "a saved Grappling Hook pick becomes the Flying Dash")

	# Holy Leap
	player.global_position = Vector3(-20, 0.1, -20)
	player.velocity = Vector3.ZERO
	await frames(20)
	player.skill_cd.clear()
	var y0: float = player.global_position.y
	check(player.use_skill(1), "Holy Leap")
	var peak := y0
	for i in 90:
		await frames(1)
		peak = maxf(peak, player.global_position.y)
	check(peak - y0 > 3.5, "a magnificent jump (%.1f m)" % (peak - y0))
	for i in 120:
		if player.is_on_floor():
			break
		await frames(1)
	check(not player.use_skill(1), "skills have cooldowns")

	# Steering a leap: holding a direction carries you that way.
	player.skill_cd.clear()
	player.rotation = Vector3.ZERO
	await frames(5)
	var x0: float = player.global_position.x
	player.test_input = {"dir": Vector2(1, 0)}
	await frames(2)
	player.use_skill(1)
	await frames(50)
	check(player.global_position.x - x0 > 4.0, "a leap goes where you steer it (%.1f m sideways)" % (player.global_position.x - x0))
	player.test_input = {}
	await frames(60)

	# Cloud Stomp: press the leap key again mid-air, slam down, hurt demons nearby.
	var victim = null
	for b in get_nodes_in_group("demon"):
		if b.health > 0:
			victim = b
	check(victim != null, "a test demon to stomp on")
	if victim:
		player.global_position = victim.global_position + Vector3(2.0, 0.1, 0)
		player.velocity = Vector3.ZERO
		await frames(10)
		player.skill_cd.clear()
		var hp_before: int = victim.health
		check(player.use_skill(1), "leap again")
		await frames(12)
		check(player.use_skill(1), "...press it again mid-air: Cloud Stomp")
		var t_stomp := 0
		while not player.is_on_floor() and t_stomp < 60:
			await frames(1)
			t_stomp += 1
		await frames(3)
		check(t_stomp < 20, "...slams straight down (%d frames)" % t_stomp)
		check(victim.health == hp_before - Skills.STOMP_DAMAGE, "...and hurts the demon it lands next to")
		check(not player.use_skill(1), "...one stomp per leap (the cooldown is still running)")

	# Hellfire (decided by the practice game here): an angel in it is slowed and burns blessings.
	player.global_position = Vector3(-20, 0.1, -20)
	player.velocity = Vector3.ZERO
	player.throw_stamina = player.THROW_STAMINA_MAX
	await frames(10)
	var feet: Vector3 = player.global_position
	main.authority_skill(player, 0, "fire", feet + Vector3(0, 1.5, 6), Vector3(0, -0.24, -0.97), feet, -1)
	await frames(45)
	check(player.burning > 0.0, "standing in Hellfire sets an angel burning")
	check(player.throw_stamina < player.THROW_STAMINA_MAX - 15.0, "...which burns away blessing stamina")
	player.global_position = feet + Vector3(5, 0, 0)
	await frames(30)
	check(player.burning <= 0.0, "...and stepping out stops it")

	# Demons pay Hatred for Hellfire.
	player.set_role("demon")
	player.loadout["demon"] = ["fire", "fly"]
	player.hatred = 20.0
	check(not player.use_skill(0), "not enough Hatred: no Hellfire")
	player.hatred = 100.0
	var fires_before: int = main.fires.size()
	check(player.use_skill(0), "Hellfire with a full bar")
	check(player.hatred < 70.0, "...costs Hatred (%.0f left)" % player.hatred)
	await frames(5)
	check(main.fires.size() > fires_before, "...and lights a fire")

	print("\n%s: %d failure(s)" % ["ALL PASSED" if failures == 0 else "FAILED", failures])
	quit(1 if failures else 0)
