# The one shrine on each map: the only place to swap skills mid-round.
# A low stone dais with a floating crystal, half heavenly and half hellish.
# When anyone uses it, a pillar of light shoots up and it chimes, so everyone
# on the map knows someone is standing there (and where to go pester them).
extends Node3D

const PropLib = preload("res://scripts/prop_library.gd")
const Sfx = preload("res://scripts/sfx.gd")

const RADIUS := 2.5           # how close you have to stand to use it
const SWAP_TIME := 3.0        # a swap takes this long in total

var _crystal: Node3D
var _pillar: MeshInstance3D
var _pillar_mat: StandardMaterial3D
var _voice: AudioStreamPlayer3D
var _glow := 0.0

static var _chime: AudioStreamWAV


func _ready() -> void:
	if _chime == null:
		_chime = Sfx.voice([[1047, 1047, 0.25, 0.8, 0.0], [1319, 1319, 0.25, 0.7, 0.0], [1568, 1568, 0.6, 0.6, 0.0]], 0.18, 0.0, 0.01, 0.01)
	var dais := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = 1.6
	cyl.height = 0.25
	shape.shape = cyl
	shape.position.y = 0.125
	dais.add_child(shape)
	var dm := MeshInstance3D.new()
	var dmesh := CylinderMesh.new()
	dmesh.top_radius = 1.6
	dmesh.bottom_radius = 1.75
	dmesh.height = 0.25
	dm.mesh = dmesh
	dm.material_override = PropLib.mat(Color(0.75, 0.72, 0.68))
	dm.position.y = 0.125
	dais.add_child(dm)
	add_child(dais)

	_crystal = Node3D.new()
	_crystal.position.y = 1.6
	add_child(_crystal)
	for half in [[Color(1.0, 0.95, 0.7), 1.0], [Color(0.9, 0.15, 0.1), -1.0]]:
		var mi := MeshInstance3D.new()
		var cone := CylinderMesh.new()
		cone.top_radius = 0.0
		cone.bottom_radius = 0.3
		cone.height = 0.55
		cone.radial_segments = 6
		mi.mesh = cone
		var m := StandardMaterial3D.new()
		m.albedo_color = half[0]
		m.emission_enabled = true
		m.emission = half[0]
		m.emission_energy_multiplier = 1.2
		mi.material_override = m
		mi.position.y = 0.275 * half[1]
		if half[1] < 0.0:
			mi.rotation.x = PI
		_crystal.add_child(mi)

	_pillar = MeshInstance3D.new()
	var pm := CylinderMesh.new()
	pm.top_radius = 0.9
	pm.bottom_radius = 0.9
	pm.height = 20.0
	_pillar.mesh = pm
	_pillar_mat = StandardMaterial3D.new()
	_pillar_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_pillar_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_pillar_mat.albedo_color = Color(1.0, 0.95, 0.75, 0.0)
	_pillar.material_override = _pillar_mat
	_pillar.position.y = 10.0
	_pillar.visible = false
	add_child(_pillar)

	# A label over it so people can find it and know what it's for.
	var sign := Label3D.new()
	sign.text = "SHRINE\nG: swap skills"
	sign.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sign.font_size = 48
	sign.outline_size = 10
	sign.pixel_size = 0.01
	sign.modulate = Color(1.0, 0.93, 0.7)
	sign.position.y = 2.7
	add_child(sign)

	_voice = AudioStreamPlayer3D.new()
	_voice.bus = Sfx.BUS
	_voice.unit_size = 12.0
	_voice.max_distance = 120.0
	_voice.position.y = 1.5
	add_child(_voice)


# Someone started swapping here: light it up for everyone to see and hear.
func flare() -> void:
	_glow = SWAP_TIME + 0.5
	_voice.stream = _chime
	_voice.play()


func _process(delta: float) -> void:
	_crystal.rotation.y += delta * (4.0 if _glow > 0.0 else 0.8)
	_crystal.position.y = 1.6 + sin(Time.get_ticks_msec() / 600.0) * 0.1
	_glow = maxf(_glow - delta, 0.0)
	_pillar.visible = _glow > 0.0
	_pillar_mat.albedo_color.a = minf(_glow, 1.0) * 0.35
