# What the Alarm Cherub looks like: a chubby little baby angel with golden curls,
# feathered wings, a cloth nappy with a blue sash, a glowing halo and a long
# golden trumpet held up to its lips. Built out of simple shapes in code, like
# everything else in the game, so there are no model files to ship.
# Feet at about y = 0.1, top of the halo at about y = 1.1, facing -Z.
# make() hands back the parts that move so cherub.gd can animate them.
extends RefCounted

const SKIN := Color(1.0, 0.8, 0.7)
const BLUSH := Color(1.0, 0.7, 0.66)
const HAIR := Color(1.0, 0.8, 0.28)
const CLOTH := Color(0.97, 0.97, 1.0)
const SASH := Color(0.45, 0.68, 0.95)
const FEATHER := Color(1.0, 1.0, 1.0)
const FEATHER_SHADE := Color(0.86, 0.9, 0.98)
const GOLD := Color(1.0, 0.76, 0.22)
const EYE := Color(0.16, 0.11, 0.1)

const MOUTH := Vector3(0, 0.745, -0.165)   # where the trumpet meets the lips
const HORN_TILT := 0.3                     # how far the trumpet points above level


# Returns {root, wings: [left, right], legs: [left, right], cheeks: [left, right], halo, horn}.
# Wings and legs are hinges (turn them, don't move them); cheeks can be scaled to puff.
static func make() -> Dictionary:
	var root := Node3D.new()
	var skin := _mat(SKIN, 0.65)
	skin.rim_enabled = true        # a soft glow round the edges, so it reads as chubby not plastic
	skin.rim = 0.12
	skin.rim_tint = 0.8
	var cloth := _mat(CLOTH, 0.9)
	var gold := _mat(GOLD, 0.28)
	gold.metallic = 0.85

	# Body: round tummy, pot belly, little bottom in a cloth nappy.
	_ball(root, 0.19, skin, Vector3(0, 0.47, 0), Vector3(1.0, 1.12, 0.95))
	_ball(root, 0.15, skin, Vector3(0, 0.43, -0.065), Vector3(1.0, 1.0, 0.9))
	_ball(root, 0.012, _mat(SKIN.darkened(0.25), 0.7), Vector3(0, 0.41, -0.2))   # belly button
	_ball(root, 0.19, cloth, Vector3(0, 0.345, 0.005), Vector3(1.06, 0.62, 1.04))
	_ball(root, 0.05, cloth, Vector3(0.0, 0.37, -0.19), Vector3(1.2, 0.8, 0.6))   # the knot at the front
	# A blue sash from the right shoulder down to the left hip.
	var sash := MeshInstance3D.new()
	var ring := TorusMesh.new()
	ring.inner_radius = 0.178
	ring.outer_radius = 0.212
	ring.rings = 32
	ring.ring_segments = 12
	sash.mesh = ring
	sash.material_override = _mat(SASH, 0.85)
	sash.position = Vector3(0, 0.5, -0.012)
	sash.rotation.z = 0.75
	sash.scale = Vector3(1.0, 1.8, 1.0)
	root.add_child(sash)

	# Head: big for its body, like a baby's.
	var head := Vector3(0, 0.8, -0.015)
	_ball(root, 0.17, skin, head, Vector3(1.0, 0.97, 0.98))
	_ball(root, 0.06, skin, Vector3(0, 0.655, 0), Vector3(1.0, 0.8, 1.0))   # neck
	_ball(root, 0.02, skin, Vector3(0, 0.79, -0.18))                        # button nose
	var dark := _mat(EYE, 0.25)
	var white := _mat(Color(1, 1, 1), 0.3)
	var blush := _mat(BLUSH, 0.8)
	var hair := _mat(HAIR, 0.55)
	var cheeks := []
	for side in [-1.0, 1.0]:
		_ball(root, 0.024, dark, Vector3(0.062 * side, 0.83, -0.152), Vector3(0.9, 1.15, 0.6))    # eye
		_ball(root, 0.007, white, Vector3(0.056 * side, 0.84, -0.165))                              # its sparkle
		var brow := _ball(root, 0.02, hair, Vector3(0.066 * side, 0.875, -0.148), Vector3(1.3, 0.3, 0.4))
		brow.rotation.z = 0.25 * side
		# Cheeks stick out a little and puff right up when it blows.
		var cheek := _ball(root, 0.062, skin, Vector3(0.088 * side, 0.762, -0.105))
		_ball(cheek, 0.05, blush, Vector3(0.006 * side, 0.002, -0.016), Vector3(0.95, 0.8, 0.95))
		cheeks.append(cheek)
		_ball(root, 0.035, skin, Vector3(0.165 * side, 0.8, 0.0), Vector3(0.5, 1.0, 0.8))          # ear

	# Golden curls: rings of little balls round the head, leaving the face clear.
	for row in [[0.60, 9, 0.058, 0.0], [1.05, 10, 0.056, 0.3], [1.45, 10, 0.05, 0.1]]:
		var polar: float = row[0]            # 0 = crown of the head, PI/2 = level with the ears
		var count: int = row[1]
		for i in count:
			var around: float = TAU * (i + row[3]) / count
			var dir: Vector3 = Vector3(sin(polar) * sin(around), cos(polar), sin(polar) * cos(around))
			if dir.z < -0.55 and polar > 0.9:
				continue                         # that would be over its eyes
			if dir.z < -0.1 and polar > 1.3:
				continue                         # and that over its cheeks
			_ball(root, row[2], hair, head + dir * 0.155)
	_ball(root, 0.062, hair, head + Vector3(0, 0.15, 0.0))
	_ball(root, 0.04, hair, head + Vector3(0.02, 0.2, -0.03))     # one curl sticking up

	# The trumpet: mouthpiece at the lips, a long thin tube, a flared bell.
	var horn := Node3D.new()
	horn.position = MOUTH
	horn.rotation.x = -PI / 2.0 + HORN_TILT      # local +Y now points forward and a little up
	root.add_child(horn)
	_tube(horn, 0.02, 0.012, 0.03, gold, 0.015)
	_tube(horn, 0.011, 0.014, 0.25, gold, 0.155)
	_tube(horn, 0.014, 0.036, 0.07, gold, 0.315)
	_tube(horn, 0.036, 0.085, 0.05, gold, 0.375)
	var rim := MeshInstance3D.new()
	var rim_mesh := TorusMesh.new()
	rim_mesh.inner_radius = 0.079
	rim_mesh.outer_radius = 0.093
	rim_mesh.rings = 24
	rim_mesh.ring_segments = 8
	rim.mesh = rim_mesh
	rim.material_override = gold
	rim.position.y = 0.4
	horn.add_child(rim)
	var bell_dark := _mat(GOLD.darkened(0.3), 0.6)       # dark down inside the bell
	bell_dark.cull_mode = BaseMaterial3D.CULL_FRONT
	_tube(horn, 0.03, 0.078, 0.045, bell_dark, 0.3795)
	var forward := Vector3(0, sin(HORN_TILT), -cos(HORN_TILT))

	# Arms reach up to hold the trumpet, one hand in front of the other.
	for side in [-1.0, 1.0]:
		var shoulder := Vector3(0.15 * side, 0.6, -0.03)
		var hand := MOUTH + forward * (0.085 if side < 0.0 else 0.17) + Vector3(0.022 * side, -0.03, 0)
		var elbow := Vector3(0.2 * side, 0.6, -0.15)      # elbows out, like a proper little herald
		_ball(root, 0.052, skin, shoulder)
		_limb(root, shoulder, elbow, 0.048, skin)
		_limb(root, elbow, hand, 0.04, skin)
		_ball(root, 0.04, skin, hand)

	# Legs dangle from the hips, knees bent, and kick about as it hovers.
	var legs := []
	for side in [-1.0, 1.0]:
		var hip := Node3D.new()
		hip.position = Vector3(0.095 * side, 0.33, -0.01)
		root.add_child(hip)
		var knee := Vector3(0.02 * side, -0.1, -0.09)
		var ankle := Vector3(0.02 * side, -0.19, -0.01)
		_limb(hip, Vector3.ZERO, knee, 0.066, skin)
		_limb(hip, knee, ankle, 0.054, skin)
		_ball(hip, 0.05, skin, ankle + Vector3(0, -0.02, -0.035), Vector3(0.85, 0.65, 1.35))    # foot
		legs.append(hip)

	# Wings: a hinge on each shoulder blade with two rows of feathers fanned off it.
	var feather := _mat(FEATHER, 0.8)
	var feather_shade := _mat(FEATHER_SHADE, 0.8)
	var wings := []
	for side in [-1.0, 1.0]:
		var hinge := Node3D.new()
		hinge.position = Vector3(0.08 * side, 0.6, 0.15)
		root.add_child(hinge)
		var fan := Node3D.new()
		fan.rotation.y = -0.35 * side        # swept back a little
		hinge.add_child(fan)
		var tip := Vector3(0.3 * side, 0.23, 0)          # the end of the wing's "arm"
		# Long flight feathers: pointing down near the body, out and up at the tip.
		for i in 8:
			var t := i / 7.0
			_feather(fan, tip * t, lerpf(-1.75, 0.35, t * t * 0.4 + t * 0.6), lerpf(0.18, 0.36, t),
				0.085, 0.004 * i, feather_shade if i % 2 == 0 else feather, side)
		# A shorter fluffy row over the top of them.
		for i in 6:
			var t := i / 5.0
			_feather(fan, tip * t * 0.92, lerpf(-1.6, 0.25, t), lerpf(0.1, 0.17, t),
				0.075, -0.014 - 0.002 * i, feather, side)
		# The wing's leading edge.
		for i in 7:
			var t := i / 6.0
			_ball(fan, lerpf(0.05, 0.026, t), feather, tip * t + Vector3(0, 0.005, -0.016), Vector3(1.25, 1.0, 0.7))
		wings.append(hinge)

	# Halo: glows, floats just above the curls, tipped at a jaunty angle.
	var halo := MeshInstance3D.new()
	var halo_mesh := TorusMesh.new()
	halo_mesh.inner_radius = 0.1
	halo_mesh.outer_radius = 0.128
	halo_mesh.rings = 32
	halo_mesh.ring_segments = 10
	halo.mesh = halo_mesh
	var glow := StandardMaterial3D.new()
	glow.albedo_color = Color(1.0, 0.92, 0.5)
	glow.emission_enabled = true
	glow.emission = Color(1.0, 0.88, 0.4)
	glow.emission_energy_multiplier = 1.6
	halo.material_override = glow
	halo.position = Vector3(0, 1.07, -0.01)
	halo.rotation = Vector3(0.14, 0, 0.1)
	root.add_child(halo)

	return {"root": root, "wings": wings, "legs": legs, "cheeks": cheeks, "halo": halo, "horn": horn}


static func _mat(color: Color, roughness: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = roughness
	return m


static func _ball(parent: Node3D, r: float, material: Material, pos: Vector3, stretch := Vector3.ONE) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = r
	sm.height = r * 2.0
	sm.radial_segments = 24 if r >= 0.1 else 14     # the little ones don't need many faces
	sm.rings = 12 if r >= 0.1 else 7
	mi.mesh = sm
	mi.material_override = material
	mi.position = pos
	mi.scale = stretch
	parent.add_child(mi)
	return mi


# A cone or cylinder standing along the parent's +Y, centred at height y.
static func _tube(parent: Node3D, bottom_r: float, top_r: float, length: float, material: Material, y: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.bottom_radius = bottom_r
	cm.top_radius = top_r
	cm.height = length
	cm.radial_segments = 20
	cm.rings = 1
	mi.mesh = cm
	mi.material_override = material
	mi.position.y = y
	parent.add_child(mi)
	return mi


# A rounded sausage from one point to another: arms, legs, the edge of a wing.
static func _limb(parent: Node3D, from: Vector3, to: Vector3, r: float, material: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CapsuleMesh.new()
	cm.radius = r
	cm.height = from.distance_to(to) + r * 2.0
	cm.radial_segments = 14
	cm.rings = 5
	mi.mesh = cm
	mi.material_override = material
	mi.position = (from + to) / 2.0
	var along := (to - from).normalized()
	if absf(along.dot(Vector3.UP)) < 0.999:
		mi.quaternion = Quaternion(Vector3.UP, along)
	parent.add_child(mi)
	return mi


# One feather: a long flat leaf lying in the wing's plane, starting at `base` and
# pointing `angle` radians up from straight out sideways. `depth` layers them.
static func _feather(parent: Node3D, base: Vector3, angle: float, length: float, width: float, depth: float, material: Material, side: float) -> void:
	var dir := Vector3(cos(angle) * side, sin(angle), 0)
	var f := _ball(parent, 0.5, material, base + dir * length * 0.45 + Vector3(0, 0, depth), Vector3(length, width, 0.022))
	f.rotation.z = angle * side
