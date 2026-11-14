# The angels' Alarm Cherub. Normally it just hovers there, tooting its little horn
# now and then. If a demon is inside the detection radius, a bubble swells out to
# the radius and back, over and over, and it blasts the horn and flaps like mad.
# Gone after 9 seconds.
# It has a real collision box: hit it with a blessing and it skids off in that
# direction (handy for checking down a hallway). The host (or the practice game)
# decides the kick and tells everyone, so every screen shows it in the same place.
# Whether a demon is near is decided by the host (or the practice game) and
# set through `alarmed`; the cherub itself never knows where demons are.
extends CharacterBody3D

const Skills = preload("res://scripts/skills.gd")
const PropLib = preload("res://scripts/prop_library.gd")
const Sfx = preload("res://scripts/sfx.gd")

var cherub_id := 0
var alarmed := false
var on_kick: Callable        # set only where kicks are decided (host / practice)
var _life := Skills.CHERUB_LIFETIME
var _phase := 0.0
var _bubble: MeshInstance3D
var _bubble_mat: StandardMaterial3D
var _body: Node3D
var _voice: AudioStreamPlayer3D
var _wings := []
var _alarm_timer := 0.0
var _toot_timer := 1.5

static var _alarm: AudioStreamWAV
static var _toot: AudioStreamWAV


func _ready() -> void:
	if _alarm == null:
		# A tiny brass horn: a soft "doo-doot" when calm, frantic fanfare blasts when alarmed.
		_alarm = Sfx.voice([[784, 784, 0.09, 1.0, 0.02], [988, 988, 0.09, 1.0, 0.02], [1175, 1175, 0.22, 1.0, 0.0]], 0.24, 0.0, 0.03, 0.03)
		_toot = Sfx.voice([[587, 587, 0.1, 0.7, 0.05], [784, 784, 0.16, 0.7, 0.0]], 0.13, 0.0, 0.02, 0.025)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.6, 1.0, 0.6)
	shape.shape = box
	shape.position.y = 0.5
	add_child(shape)
	floor_snap_length = 0.2
	collision_mask = 1 | 2   # stays inside the map's invisible walls
	_body = Node3D.new()      # everything you see; it hovers and bobs above the collision box
	add_child(_body)
	var skin := Color(1.0, 0.82, 0.74)
	var tummy := _sphere(0.2, skin)
	tummy.position.y = 0.45
	tummy.scale = Vector3(1.0, 1.1, 0.95)
	_body.add_child(tummy)
	var head := _sphere(0.15, skin)
	head.position = Vector3(0, 0.78, 0)
	_body.add_child(head)
	var curls := _sphere(0.13, Color(1.0, 0.85, 0.35))   # golden curls on top
	curls.position = Vector3(0, 0.86, 0.03)
	curls.scale = Vector3(1.05, 0.6, 1.0)
	_body.add_child(curls)
	for side in [-1.0, 1.0]:
		var arm := _sphere(0.06, skin)          # little arms holding the horn up
		arm.position = Vector3(0.1 * side, 0.6, -0.14)
		_body.add_child(arm)
		var wing := MeshInstance3D.new()
		var wm := SphereMesh.new()
		wm.radius = 0.2
		wm.height = 0.4
		wing.mesh = wm
		wing.material_override = PropLib.mat(Color(1.0, 1.0, 1.0))
		wing.scale = Vector3(0.25, 0.9, 1.1)
		wing.position = Vector3(0.24 * side, 0.6, 0.12)
		wing.rotation.z = -0.5 * side
		_body.add_child(wing)
		_wings.append(wing)
	var horn := MeshInstance3D.new()             # a little golden horn, raised to its lips
	var hm := CylinderMesh.new()
	hm.top_radius = 0.015
	hm.bottom_radius = 0.07
	hm.height = 0.3
	horn.mesh = hm
	horn.material_override = PropLib.mat(Color(1.0, 0.78, 0.2))
	horn.rotation.x = -PI / 2 - 0.35
	horn.position = Vector3(0, 0.74, -0.27)
	_body.add_child(horn)
	var halo := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.09
	tm.outer_radius = 0.12
	halo.mesh = tm
	var hmat := StandardMaterial3D.new()
	hmat.albedo_color = Color(1.0, 0.92, 0.5)
	hmat.emission_enabled = true
	hmat.emission = Color(1.0, 0.9, 0.4)
	halo.material_override = hmat
	halo.position.y = 1.02
	_body.add_child(halo)

	_bubble = MeshInstance3D.new()
	var bs := SphereMesh.new()
	bs.radius = 1.0
	bs.height = 2.0
	_bubble.mesh = bs
	_bubble_mat = StandardMaterial3D.new()
	_bubble_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_bubble_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_bubble_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_bubble_mat.albedo_color = Color(1.0, 0.9, 0.2, 0.16)
	_bubble.material_override = _bubble_mat
	_bubble.position.y = 0.5
	add_child(_bubble)

	_voice = AudioStreamPlayer3D.new()
	_voice.bus = Sfx.BUS
	_voice.unit_size = 8.0
	_voice.max_distance = 80.0
	_voice.position.y = 0.4
	add_child(_voice)
	_voice.stream = _toot
	_voice.play()


func _sphere(r: float, color: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = r
	sm.height = r * 2.0
	mi.mesh = sm
	mi.material_override = PropLib.mat(color)
	return mi


# A blessing hit us. Only the decider acts on it; everyone else just saw a puff.
func kick(projectile_velocity: Vector3) -> void:
	if on_kick.is_valid():
		on_kick.call(cherub_id, projectile_velocity)


func launch(pos: Vector3, vel: Vector3) -> void:
	global_position = pos
	velocity = vel


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= 18.0 * delta
	else:
		var flat := Vector3(velocity.x, 0, velocity.z)
		flat = flat.move_toward(Vector3.ZERO, Skills.CHERUB_FRICTION * delta)
		velocity.x = flat.x
		velocity.z = flat.z
	var flat_speed := Vector2(velocity.x, velocity.z).length()
	if flat_speed > 0.5:
		rotation.y = lerp_angle(rotation.y, atan2(velocity.x, velocity.z) + PI, 0.3)
	move_and_slide()


func _process(delta: float) -> void:
	_life -= delta
	if _life <= 0.0:
		queue_free()
		return
	# Swell out to the radius and back: 1.6 s per cycle, twice as fast when alarmed.
	_phase += delta * (1.25 if alarmed else 0.625)
	var t := 1.0 - absf(fmod(_phase, 1.0) * 2.0 - 1.0)   # 0 -> 1 -> 0
	var r := maxf(Skills.CHERUB_RADIUS * t, 0.05)
	_bubble.scale = Vector3.ONE * r
	_bubble.visible = alarmed           # no bubble unless a demon is close
	_bubble_mat.albedo_color = Color(1.0, 0.15, 0.1, 0.22)
	# Hover and flap: gentle when calm, frantic when a demon is close.
	var flap_speed := 30.0 if alarmed else 9.0
	var flap := sin(Time.get_ticks_msec() / 1000.0 * flap_speed)
	for i in _wings.size():
		_wings[i].rotation.y = flap * (0.5 if alarmed else 0.3) * (1.0 if i == 0 else -1.0)
	_body.position.y = 0.15 + sin(Time.get_ticks_msec() / 1000.0 * 2.2) * 0.06
	if alarmed:
		_body.position.y += absf(sin(_phase * 12.0)) * 0.12
		_alarm_timer -= delta
		if _alarm_timer <= 0.0:
			_alarm_timer = 0.6
			_voice.stream = _alarm
			_voice.pitch_scale = randf_range(0.97, 1.05)
			_voice.play()
	else:
		_toot_timer -= delta
		if _toot_timer <= 0.0:
			_toot_timer = randf_range(2.0, 3.5)
			_voice.stream = _toot
			_voice.pitch_scale = randf_range(0.95, 1.05)
			_voice.play()
