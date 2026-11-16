# Cherub Sense: a little cherub dangling above an angel's head for as long as the
# power-up lasts. It sways and flaps lazily, and when a demon comes close (the
# owner's game knows; teammates just see it calm) it flaps like mad, pedals its
# legs and puffs its cheeks into the horn. Purely for show: the alarm sound and
# the red bubble are handled by main.gd as before.
#
# Only angels see these, the same as the power-ups themselves.
extends Node3D

const CherubModel = preload("res://scripts/cherub_model.gd")

const SIZE := 0.55              # smaller than the Alarm Cherub skill
const ABOVE_HEAD := 0.45        # how far above the top of the head it hangs

var alarmed := false            # set every frame by whoever owns it
var life := -1.0                # counts down when set (teammates' cherubs); -1 = owner keeps it

var _body: Node3D
var _wings := []
var _legs := []
var _cheeks := []
var _halo: Node3D
var _phase := randf() * TAU


func _ready() -> void:
	_body = Node3D.new()
	add_child(_body)
	var model: Dictionary = CherubModel.make()
	_body.add_child(model["root"])
	model["root"].scale = Vector3.ONE * SIZE
	model["root"].position.y = -0.1 * SIZE
	_wings = model["wings"]
	_legs = model["legs"]
	_cheeks = model["cheeks"]
	_halo = model["halo"]
	for mi in find_children("*", "MeshInstance3D", true, false):
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _process(delta: float) -> void:
	if life >= 0.0:
		life -= delta
		if life <= 0.0:
			queue_free()
			return
	var now := Time.get_ticks_msec() / 1000.0 + _phase
	# Dangling sway, and a slow turn to look around.
	_body.rotation.z = sin(now * 1.7) * (0.25 if alarmed else 0.12)
	_body.rotation.x = sin(now * 1.3 + 1.0) * (0.2 if alarmed else 0.08)
	_body.rotation.y = sin(now * 0.4) * 0.6
	_body.position.y = sin(now * 2.2) * 0.05 + (absf(sin(now * 9.0)) * 0.08 if alarmed else 0.0)
	var flap := sin(now * (30.0 if alarmed else 9.0))
	for i in _wings.size():
		var side := -1.0 if i == 0 else 1.0
		_wings[i].rotation.z = (0.1 + flap * (0.5 if alarmed else 0.3)) * side
		_wings[i].rotation.y = flap * 0.15 * side
	for i in _legs.size():
		_legs[i].rotation.x = sin(now * (14.0 if alarmed else 2.6) + i * PI) * (0.45 if alarmed else 0.18)
	var puff := 1.0 + (0.3 * absf(sin(now * 6.0)) if alarmed else 0.0)
	for cheek in _cheeks:
		cheek.scale = Vector3.ONE * puff
	_halo.position.y = 1.07 + sin(now * 3.1) * 0.012
