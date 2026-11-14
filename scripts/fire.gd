# A demon's Hellfire: a fireball flies from the demon to where it aimed, then a
# patch of fire burns there for a few seconds. Angels standing in it are slowed
# and their blessing stamina burns away (main.gd checks `is_lit()` and `radius`).
# Every computer shows the same fire; positions come from the host.
extends Node3D

const Skills = preload("res://scripts/skills.gd")
const Sfx = preload("res://scripts/sfx.gd")
const Effects = preload("res://scripts/effects.gd")


var from := Vector3.ZERO
var vel := Vector3.ZERO           # thrown from `from` with this velocity...
var to := Vector3.ZERO            # ...and lights here after `flight_time` seconds
var flight_time := 0.3
var _travel := 0.0
var _travel_time := 0.3
var _life := Skills.FIRE_LIFETIME
var _ball: MeshInstance3D
var _flames: CPUParticles3D
var _light: OmniLight3D
var _voice: AudioStreamPlayer3D
var _lit := false

static var _whoosh: AudioStreamWAV
static var _crackle: AudioStreamWAV


func _ready() -> void:
	if _whoosh == null:
		_whoosh = Sfx.voice([[180, 90, 0.35, 0.8, 0.0]], 0.2, 0.6, 0.5)
		_crackle = Sfx.voice([[120, 110, 0.5, 0.5, 0.0]], 0.12, 0.9, 0.7)
	_travel_time = maxf(flight_time, 0.05)
	global_position = from

	_ball = MeshInstance3D.new()
	var s := SphereMesh.new()
	s.radius = 0.22
	s.height = 0.44
	_ball.mesh = s
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(1.0, 0.45, 0.1)
	m.emission_enabled = true
	m.emission = Color(1.0, 0.4, 0.05)
	m.emission_energy_multiplier = 3.0
	_ball.material_override = m
	add_child(_ball)

	_light = OmniLight3D.new()
	_light.light_color = Color(1.0, 0.5, 0.2)
	_light.omni_range = 5.0
	_light.light_energy = 1.5
	add_child(_light)

	_voice = AudioStreamPlayer3D.new()
	_voice.bus = Sfx.BUS
	_voice.unit_size = 7.0
	_voice.max_distance = 70.0
	add_child(_voice)
	_voice.stream = _whoosh
	_voice.play()


func is_lit() -> bool:
	return _lit


func _light_up() -> void:
	_lit = true
	global_position = to
	_ball.visible = false
	_flames = CPUParticles3D.new()
	_flames.amount = 60
	_flames.lifetime = 0.8
	_flames.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	_flames.emission_sphere_radius = Skills.FIRE_RADIUS * 0.8
	_flames.direction = Vector3.UP
	_flames.spread = 15.0
	_flames.gravity = Vector3(0, 2.5, 0)
	_flames.initial_velocity_min = 0.5
	_flames.initial_velocity_max = 1.5
	_flames.scale_amount_min = 0.6
	_flames.scale_amount_max = 1.2
	var grad := Gradient.new()
	grad.set_color(0, Color(1.0, 0.85, 0.3, 0.9))
	grad.set_color(1, Color(0.8, 0.1, 0.0, 0.0))
	_flames.color_ramp = grad
	var q := QuadMesh.new()
	q.size = Vector2(0.35, 0.5)
	var fm := StandardMaterial3D.new()
	fm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	fm.vertex_color_use_as_albedo = true
	q.material = fm
	_flames.mesh = q
	_flames.position.y = 0.2
	add_child(_flames)
	# Scorched ground under the flames, so the patch's edge is easy to see.
	var scorch := MeshInstance3D.new()
	var c := CylinderMesh.new()
	c.top_radius = Skills.FIRE_RADIUS
	c.bottom_radius = Skills.FIRE_RADIUS
	c.height = 0.02
	scorch.mesh = c
	var sm := StandardMaterial3D.new()
	sm.albedo_color = Color(0.25, 0.05, 0.0, 0.6)
	sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sm.emission_enabled = true
	sm.emission = Color(0.6, 0.12, 0.0)
	scorch.material_override = sm
	scorch.position.y = 0.02
	add_child(scorch)
	_light.position.y = 0.8
	Effects.puff(get_parent(), to + Vector3.UP * 0.3, Color(1.0, 0.5, 0.1, 0.8), 1.4)


func _process(delta: float) -> void:
	if not _lit:
		_travel += delta
		var t := minf(_travel / _travel_time, 1.0)
		var ft := t * _travel_time
		global_position = from + vel * ft + Vector3.DOWN * 0.5 * Skills.FIRE_GRAVITY * ft * ft
		if t >= 1.0:
			_light_up()
		return
	_life -= delta
	_light.light_energy = 1.3 + sin(Time.get_ticks_msec() * 0.03) * 0.3 + randf() * 0.2
	if not _voice.playing:
		_voice.stream = _crackle
		_voice.pitch_scale = randf_range(0.8, 1.2)
		_voice.play()
	if _life < 1.0:
		_flames.emitting = false     # die down for the last second
		_light.light_energy *= _life
	if _life <= 0.0:
		queue_free()
