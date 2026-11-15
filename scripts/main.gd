# Halos & Horns: menu, the test map, the HUD, practice mode, and the screens
# around online play (online rules themselves live in net_game.gd).
#   Practice: single player. Angel side hunts 3 test demons; demon side is a sandbox.
#   Online: one player hosts, friends join by address. Mobification rules.
extends Node3D

const PropLib = preload("res://scripts/prop_library.gd")
const Player = preload("res://scripts/player.gd")
const BotDemon = preload("res://scripts/bot_demon.gd")
const Sfx = preload("res://scripts/sfx.gd")
const Blessings = preload("res://scripts/blessings.gd")
const Taunts = preload("res://scripts/taunts.gd")
const NetGame = preload("res://scripts/net_game.gd")
const Effects = preload("res://scripts/effects.gd")
const Autobot = preload("res://scripts/autobot.gd")
const Skills = preload("res://scripts/skills.gd")
const Cherub = preload("res://scripts/cherub.gd")
const Fire = preload("res://scripts/fire.gd")
const Minion = preload("res://scripts/minion.gd")
const PowerUps = preload("res://scripts/powerups.gd")
const Keybinds = preload("res://scripts/keybinds.gd")
const Shrine = preload("res://scripts/shrine.gd")
const SHRINE_POS := Vector3(-20, 0, 4)   # the one shrine on this map
const Vortex = preload("res://scripts/vortex.gd")
const Projectile = preload("res://scripts/projectile.gd")
const Updater = preload("res://scripts/updater.gd")

const GAME_CODENAME := "Power-ups"
const HIDE_TIME := 30.0
const HUNT_TIME := 180.0
const HEAT_SHADER := """
shader_type canvas_item;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float strength = 0.0;
void fragment() {
	float t = TIME;
	vec2 uv = SCREEN_UV;
	// Big slow swirls plus fast shimmer, like looking through a bonfire.
	uv.x += strength * (0.025 * sin(uv.y * 9.0 + t * 3.1) + 0.008 * sin(uv.y * 47.0 + t * 17.0));
	uv.y += strength * (0.02 * sin(uv.x * 7.0 - t * 2.3) + 0.008 * cos(uv.x * 39.0 + t * 13.0));
	// Edges pulled in and out, like the view is breathing.
	uv = mix(uv, vec2(0.5) + (uv - vec2(0.5)) * (1.0 + 0.06 * sin(t * 4.0)), strength);
	vec3 c = textureLod(screen_tex, uv, strength * 1.5).rgb;
	// Hot orange cast and a red glow creeping in from the edges.
	float edge = smoothstep(0.35, 0.75, distance(SCREEN_UV, vec2(0.5)));
	c = mix(c, c * vec3(1.35, 0.8, 0.45) + vec3(0.12, 0.03, 0.0), strength * 0.7);
	c = mix(c, vec3(0.9, 0.25, 0.02), edge * strength * 0.55);
	COLOR = vec4(c, 1.0);
}
"""
const HIDE_CHOICES := [15.0, 30.0, 45.0, 60.0, 90.0]
const IDLE_CHOICES := [0.0, 120.0, 300.0, 600.0]   # kick players who haven't moved or looked around for this long (0 = never)
const HUNT_CHOICES := [120.0, 180.0, 300.0, 600.0, 900.0, 1800.0]
const BOT_COUNT := 3
const PROP_COUNT := 45
const MAP_HALF := 28.0
const ANGEL_SPAWN := Vector3(0, 0.1, -24)
const DEMON_SPAWN := Vector3(0, 0.1, 0)
const SETTINGS_PATH := "user://settings.cfg"

enum State { LOBBY, HIDING, HUNTING, ENDED }

var mode := "menu"           # menu, practice, online
var state: State = State.LOBBY
var time_left := 0.0
var role := "angel"          # practice starts on the side that has a full round to play
var bots_left := 0           # demons left (test demons in practice, players online)
var my_health := 1.0         # online demons: fraction of health left (same fraction in every form)
var loadout := Skills.DEFAULTS.duplicate(true)   # your chosen skills (saved)
var props: Array = []        # this round's map props, by index (same on every computer)
var cherubs := {}           # cherub id -> Cherub node (visuals, everyone)
var _auth_cherubs := {}     # cherub id -> {pos, until, alarmed} (decider only)
var _cherub_counter := 0
var fires := {}              # fire id -> Fire node (everyone; angels check if they're standing in one)
var _fire_counter := 0
var powerups                 # power-up drops and pickups (powerups.gd)
var _auth_fires := {}        # decider: fire id -> {owner, pos, lit_at, until} (who earns Hatred from it)
var _naughty_tick := 0.0
var _cherub_check := 0.0
var _possessions := {}       # who possesses which prop: user key -> prop index (decider only)
var _loadout_buttons: Array = []   # [team, slot, OptionButton]
var skill_label: Label
var bonus_label: Label
var powerup_label: Label
var _sense_bubble: MeshInstance3D
var _sense_sound_time := 0.0
var _bonus_time := 0.0
var shrine: Node3D
var shrine_panel: PanelContainer
var _shrine_buttons := []       # the two OptionButtons for the current side
var _shrine_pick := ["", ""]
var _shrine_elapsed := 0.0      # seconds since this swap started
var _shrine_done := false       # picked and confirmed; waiting out the rest of the 3 s
var _shrine_status: Label
var _was_at_shrine := false   # just walked up to the shrine: show how to use it
var chat_box: VBoxContainer     # recent chat lines, bottom left
var chat_edit: LineEdit
var chat_team_only := false
var _chat_lines := []           # [Label, seconds left on screen]
var lobby_times: VBoxContainer   # host's round-length pickers
var _kick_pick: OptionButton     # host: who to kick
var _time_pick := {}            # picker label -> chosen index
var heat_rect: ColorRect         # Hellfire screen distortion
var hold_bar: ColorRect          # "returning to demon form" progress, under the crosshair
var hold_fill: ColorRect
var player: Player
var net: Node = null
# The version is the GitHub release tag, stamped into the build by release-builds.yml.
# Run from source, or built by hand, it's "dev".
var game_version: String = ProjectSettings.get_setting("application/config/version", "dev")
var game_build := 0          # the same version as one number (0.4.1 -> 401); only equal builds can play together
var updater: Updater          # checks GitHub for a newer version (see updater.gd)
var update_button: Button
var update_note: Label
var autobot: Node = null
var round_root: Node3D
var rng := RandomNumberGenerator.new()
var structures: Array = []   # each: [Vector2 center, float keep-clear radius]
var used_spots: Array = []
var lobby_names: Array = []
var scoreboard_rows: Array = []   # Tab roster, from the host

var status_label: Label
var hint_label: Label
var controls_label: Label
var center_label: Label
var blind_rect: ColorRect
var hurt_rect: ColorRect
var crosshair: Label
var _toast_time := 0.0
var _hitmarker_time := 0.0
var _hurt_time := 0.0
var _sounds := {}             # name -> AudioStreamPlayer
var bar_fills := {}           # HUD stamina bars: name -> [fill ColorRect, Label]
var taunt_label: Label
var hud_layer: CanvasLayer
var _taunt_label_time := 0.0
var tuning_panel: PanelContainer
var _tuning_rows := {}        # tuning key -> [HSlider, Label, title]
var _tuning_defaults := {}

var menu_panel: PanelContainer
var name_edit: LineEdit
var address_edit: LineEdit
var port_edit: LineEdit
var menu_status: Label
var pause_panel: PanelContainer
var lobby_panel: PanelContainer
var lobby_players: Label
var lobby_info: Label
var lobby_start: Button
var _public_ip := ""
var _settings := ConfigFile.new()
var ping_label: Label
var scoreboard_panel: PanelContainer
var _scoreboard_columns := {}     # "angel"/"demon" -> GridContainer
var _scoreboard_titles := {}
var _scoreboard_footer: Label
var _ping_timer := 0.0

# F1 tuning panel: [key, label, min, max, step]
const TUNING_SLIDERS := [
	["ground_accel", "Acceleration", 5.0, 120.0, 1.0],
	["ground_decel", "Stopping (lower = more slide)", 5.0, 120.0, 1.0],
	["air_accel", "Air control", 0.0, 40.0, 1.0],
	["gravity_scale", "Gravity", 0.5, 3.0, 0.05],
	["fall_multiplier", "Extra fall speed", 1.0, 3.0, 0.05],
	["jump_velocity", "Jump strength", 3.0, 9.0, 0.1],
	["head_bob", "Head bob (0 = off)", 0.0, 2.0, 0.05],
	["dash_speed", "Dash: speed", 8.0, 35.0, 0.5],
	["dash_time", "Dash: length (seconds)", 0.1, 0.6, 0.01],
	["dash_carry", "Dash: momentum kept after", 0.0, 1.0, 0.05],
	["dash_ground_drag", "Dash: momentum fade on ground", 0.0, 40.0, 0.5],
	["dash_air_drag", "Dash: momentum fade in air", 0.0, 40.0, 0.5],
	["dash_turn_loss", "Dash: momentum lost in a slow 180", 0.0, 1.0, 0.05],
	["dash_sharp_turn", "Dash: turn speed that kills it (deg/s)", 60.0, 1080.0, 10.0],
]


func _ready() -> void:
	var numbers := Updater.version_numbers(game_version)
	while numbers.size() < 3:   # "dev" has no numbers and "0.4" has two: the rest count as 0
		numbers.append(0)
	game_build = numbers[0] * 10000 + numbers[1] * 100 + numbers[2]
	rng.randomize()
	_setup_input()
	_build_environment()
	_build_map()
	_build_hud()
	_build_sounds()
	player = Player.new()
	player.role = role
	add_child(player)
	player.threw.connect(func(kind): _play("throw_" + kind))
	player.form_changed.connect(func(): _play("possess"))
	player.hit_confirmed.connect(_on_hit_confirmed)
	player.taunted.connect(_on_taunted)
	player.powerup_taken.connect(func(kind):
		_play("powerup")
		_toast(PowerUps.LABELS.get(kind, kind) + "!", 1.5))
	player.hatred_bonus.connect(func(amount, reason):
		bonus_label.text = "+%d Hatred: %s" % [int(round(amount)), reason]
		_bonus_time = 2.5)
	player.launched.connect(_on_player_launched)
	player.hit_taken.connect(_on_player_hit_taken)
	player.skill_used.connect(_on_player_skill)
	player.pick_minion_form = random_map_prop_type
	powerups = PowerUps.new()
	powerups.main = self
	add_child(powerups)
	player.melee_used.connect(_on_player_melee)
	player.released_possessed.connect(_on_player_released)
	_build_tuning_panel()
	_build_menu()
	_build_pause_menu()
	_build_controls()
	_build_lobby()
	_build_shrine_panel()
	_build_chat()
	_load_settings()
	_show_menu("")
	_handle_command_line()
	updater = Updater.new()
	add_child(updater)
	updater.changed.connect(_refresh_update_row)
	updater.check(game_version)


# ---------- input ----------

func _add_key(action: String, key: Key) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	var ev := InputEventKey.new()
	ev.physical_keycode = key
	InputMap.action_add_event(action, ev)


func _setup_input() -> void:
	Keybinds.setup({})   # defaults now; saved choices are applied when settings load


func _unhandled_input(event: InputEvent) -> void:
	if mode == "menu":
		if event is InputEventKey and event.pressed and event.physical_keycode == KEY_ESCAPE and controls_panel.visible:
			_close_controls()
		return
	if chat_edit.visible:
		if event is InputEventKey and event.pressed and event.physical_keycode == KEY_ESCAPE:
			_close_chat()
			get_viewport().set_input_as_handled()
		return
	if mode == "online" and not _any_panel_open() and (event.is_action_pressed("chat_all") or event.is_action_pressed("chat_team")):
		_open_chat(event.is_action_pressed("chat_team"))
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("shrine") and not _any_panel_open():
		_try_open_shrine()
		return
	if event is InputEventKey and event.pressed and event.physical_keycode == KEY_ESCAPE and shrine_panel.visible:
		_close_shrine()
		return
	if event is InputEventKey and event.pressed and event.physical_keycode == KEY_ESCAPE and controls_panel.visible:
		_close_controls()
		return
	if event is InputEventKey and event.pressed and event.physical_keycode == KEY_ESCAPE:
		pause_panel.visible = not pause_panel.visible
		_refresh_mouse()
	elif event.is_action_pressed("toggle_tuning"):
		tuning_panel.visible = not tuning_panel.visible
		_refresh_mouse()
	elif mode == "practice":
		if event.is_action_pressed("restart"):
			start_round()
		elif event.is_action_pressed("switch_role"):
			role = "demon" if role == "angel" else "angel"
			start_round()
		elif event.is_action_pressed("skip_hiding") and state == State.HIDING:
			time_left = 0.0


# The mouse is free whenever a menu or panel is open; otherwise it steers.
func _any_panel_open() -> bool:
	return menu_panel.visible or pause_panel.visible or tuning_panel.visible or lobby_panel.visible \
			or shrine_panel.visible or chat_edit.visible or (controls_panel != null and controls_panel.visible)


func _refresh_mouse() -> void:
	var ui_open := _any_panel_open()
	player.input_enabled = not ui_open
	if DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if ui_open else Input.MOUSE_MODE_CAPTURED


# ---------- the shrine (swap skills mid-round) ----------
# Stand at the shrine and press G. Picking takes as long as you like, but the
# whole swap takes at least 3 seconds from pressing G: pick fast and you wait out
# the rest, take longer and it applies as soon as you confirm. You can't move
# while you're at it, demons have to leave their prop first, and the shrine
# flares up so everyone knows someone is there.

func _build_shrine_panel() -> void:
	var parts := _panel(420)
	shrine_panel = parts[0]
	var box: VBoxContainer = parts[1]
	var title := Label.new()
	title.text = "Shrine: swap your skills"
	title.add_theme_font_size_override("font_size", 26)
	box.add_child(title)
	var row := HBoxContainer.new()
	box.add_child(row)
	for slot in 2:
		var ob := OptionButton.new()
		ob.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		ob.item_selected.connect(func(i): _on_shrine_pick(slot, ob.get_item_metadata(i)))
		row.add_child(ob)
		_shrine_buttons.append(ob)
	_shrine_status = Label.new()
	box.add_child(_shrine_status)
	_button(box, "Done", _confirm_shrine)
	_button(box, "Cancel (Esc)", _close_shrine)
	shrine_panel.visible = false


func near_shrine(pos: Vector3) -> bool:
	return Vector2(pos.x - SHRINE_POS.x, pos.z - SHRINE_POS.z).length() <= Shrine.RADIUS and absf(pos.y - SHRINE_POS.y) < 2.0


func _try_open_shrine() -> void:
	if not (state == State.HIDING or state == State.HUNTING) or player.frozen:
		return
	if not near_shrine(player.global_position):
		_toast("The shrine is the only place to swap skills.", 1.5)
		return
	if player.possessed_type != "":
		_toast("Leave your prop first (hold left click).", 1.5)
		return
	_shrine_pick = player.loadout[role].duplicate()
	var keys: Array = [Keybinds.key_name("skill_1"), Keybinds.key_name("rmb")]
	for slot in 2:
		var ob: OptionButton = _shrine_buttons[slot]
		ob.clear()
		ob.add_item("%s: none" % keys[slot])
		ob.set_item_metadata(0, "")
		for id in Skills.for_team(role):
			ob.add_item("%s: %s" % [keys[slot], Skills.label(id)])
			ob.set_item_metadata(ob.item_count - 1, id)
			ob.set_item_tooltip(ob.item_count - 1, Skills.SKILLS[id]["desc"])
			if id == _shrine_pick[slot]:
				ob.select(ob.item_count - 1)
	_shrine_elapsed = 0.0
	_shrine_done = false
	shrine_panel.visible = true
	player.velocity = Vector3.ZERO
	_refresh_mouse()
	if mode == "practice":
		shrine.flare()
	elif net:
		net.shrine_open()


func _on_shrine_pick(slot: int, id: String) -> void:
	if id != "" and id in _shrine_pick:
		_shrine_pick[_shrine_pick.find(id)] = ""
	_shrine_pick[slot] = id
	for s2 in 2:   # keep both buttons showing the real picks
		var ob: OptionButton = _shrine_buttons[s2]
		for i in ob.item_count:
			if ob.get_item_metadata(i) == _shrine_pick[s2]:
				ob.select(i)


func _confirm_shrine() -> void:
	_shrine_done = true


func _close_shrine() -> void:
	_shrine_done = false
	shrine_panel.visible = false
	_refresh_mouse()


func _update_shrine(delta: float) -> void:
	if not shrine_panel.visible:
		return
	_shrine_elapsed += delta
	if not (state == State.HIDING or state == State.HUNTING) or player.frozen or player.possessed_type != "":
		_close_shrine()
		return
	var left := Shrine.SWAP_TIME - _shrine_elapsed
	if _shrine_done and left <= 0.0:
		loadout[role] = Skills.clean_loadout(role, _shrine_pick)
		player.loadout = loadout.duplicate(true)
		for id in loadout[role]:   # fresh skills start on cooldown (no swap-dancing)
			if id != "":
				player.skill_cd[id] = Skills.cooldown(id)
		_sync_loadout_buttons()
		_save_settings()
		if net:
			net.shrine_swap(loadout[role])
		_close_shrine()
		_toast("Skills swapped!", 1.2)
		return
	if _shrine_done:
		_shrine_status.text = "Swapping... %.1f s" % left
	elif left > 0.0:
		_shrine_status.text = "Pick your skills (the swap takes %.1f s more)" % left
	else:
		_shrine_status.text = "Pick your skills, then Done"


# ---------- chat ----------
# Enter: everyone. Backspace: your team only. Enter sends, Esc cancels.

func _build_chat() -> void:
	chat_box = VBoxContainer.new()
	chat_box.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	chat_box.grow_vertical = Control.GROW_DIRECTION_BEGIN
	chat_box.position += Vector2(16, -190)
	chat_box.custom_minimum_size.x = 520
	chat_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud_layer.add_child(chat_box)
	chat_edit = LineEdit.new()
	chat_edit.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	chat_edit.grow_vertical = Control.GROW_DIRECTION_BEGIN
	chat_edit.position += Vector2(16, -150)
	chat_edit.custom_minimum_size.x = 520
	chat_edit.max_length = 120
	chat_edit.visible = false
	chat_edit.text_submitted.connect(_send_chat)
	hud_layer.add_child(chat_edit)


func _open_chat(team_only: bool) -> void:
	chat_team_only = team_only
	chat_edit.placeholder_text = ("Team chat (%ss only)" % role) if team_only else "Chat to everyone"
	chat_edit.text = ""
	chat_edit.visible = true
	_refresh_mouse()
	chat_edit.call_deferred("grab_focus")
	for entry in _chat_lines:
		entry[1] = maxf(entry[1], 8.0)   # show recent lines while typing


func _close_chat() -> void:
	chat_edit.release_focus()
	chat_edit.visible = false
	_refresh_mouse()


func _send_chat(text: String) -> void:
	text = text.strip_edges()
	_close_chat()
	if text == "":
		return
	# Host only: "/kick Name" removes someone mid-round.
	if text.begins_with("/kick ") and net and net.is_host:
		net.kick_by_name(text.trim_prefix("/kick ").strip_edges(), "The host kicked you.")
		return
	if net:
		net.send_chat(text, chat_team_only)


# Big news for everyone (who redeemed whom): shown in gold in the chat area.
func announce(text: String) -> void:
	var lbl := _make_label(19)
	lbl.text = "*** %s ***" % text
	lbl.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
	chat_box.add_child(lbl)
	print("[news] " + text)
	_chat_lines.append([lbl, 8.0])
	while _chat_lines.size() > 8:
		_chat_lines[0][0].queue_free()
		_chat_lines.pop_front()


# Called by the network for every chat line we're allowed to see.
func show_chat(sender: String, sender_role: String, text: String, team_only: bool) -> void:
	var lbl := _make_label(17)
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl.custom_minimum_size.x = 520
	lbl.text = "%s%s: %s" % ["[TEAM] " if team_only else "", sender, text]
	var color := Color(1, 1, 1)
	if sender_role == "angel":
		color = Color(1.0, 0.92, 0.6)
	elif sender_role == "demon":
		color = Color(1.0, 0.55, 0.5)
	lbl.add_theme_color_override("font_color", color)
	chat_box.add_child(lbl)
	print("[chat] " + lbl.text)
	_chat_lines.append([lbl, 12.0])
	while _chat_lines.size() > 8:
		_chat_lines[0][0].queue_free()
		_chat_lines.pop_front()


func _update_chat(delta: float) -> void:
	for entry in _chat_lines:
		if not chat_edit.visible:
			entry[1] -= delta
		entry[0].modulate.a = clampf(entry[1], 0.0, 1.0)


# ---------- world ----------

func _build_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.45, 0.4, 0.75)       # heavenly lavender up top
	sky_mat.sky_horizon_color = Color(0.95, 0.6, 0.45)   # hellish glow at the horizon
	sky_mat.ground_horizon_color = Color(0.95, 0.6, 0.45)
	sky.sky_material = sky_mat
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)

	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(deg_to_rad(-50), deg_to_rad(30), 0)
	sun.shadow_enabled = true
	add_child(sun)


func _add_block(center: Vector3, size: Vector3, color: Color, rot := Vector3.ZERO, keep_clear := true) -> void:
	var body := StaticBody3D.new()
	var shape_node := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape_node.shape = box
	body.add_child(shape_node)
	var mi := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mi.mesh = mesh
	mi.material_override = PropLib.mat(color)
	body.add_child(mi)
	body.position = center
	body.rotation = rot
	add_child(body)
	if keep_clear:
		structures.append([Vector2(center.x, center.z), maxf(size.x, size.z) / 2.0 + 1.0])


func _build_map() -> void:
	# Ground and boundary walls
	_add_block(Vector3(0, -0.5, 0), Vector3(MAP_HALF * 2 + 2, 1, MAP_HALF * 2 + 2), Color(0.35, 0.55, 0.3), Vector3.ZERO, false)
	var wall_color := Color(0.5, 0.48, 0.52)
	var span := MAP_HALF * 2 + 2
	_add_block(Vector3(0, 2, MAP_HALF + 1), Vector3(span, 4, 1), wall_color, Vector3.ZERO, false)
	_add_block(Vector3(0, 2, -MAP_HALF - 1), Vector3(span, 4, 1), wall_color, Vector3.ZERO, false)
	_add_block(Vector3(MAP_HALF + 1, 2, 0), Vector3(1, 4, span), wall_color, Vector3.ZERO, false)
	_add_block(Vector3(-MAP_HALF - 1, 2, 0), Vector3(1, 4, span), wall_color, Vector3.ZERO, false)
	# Invisible walls above the visible ones, and a ceiling, so flying demons
	# (and dashing angels) can't leave the map.
	_add_invisible(Vector3(0, 17, MAP_HALF + 1), Vector3(span, 26, 1))
	_add_invisible(Vector3(0, 17, -MAP_HALF - 1), Vector3(span, 26, 1))
	_add_invisible(Vector3(MAP_HALF + 1, 17, 0), Vector3(1, 26, span))
	_add_invisible(Vector3(-MAP_HALF - 1, 17, 0), Vector3(1, 26, span))
	_add_invisible(Vector3(0, CEILING + 0.5, 0), Vector3(span, 1, span))
	# Buildings and cover
	_add_block(Vector3(8, 2, 8), Vector3(6, 4, 6), Color(0.7, 0.6, 0.5))
	_add_block(Vector3(-10, 2, -6), Vector3(7, 4, 5), Color(0.6, 0.55, 0.65))
	_add_block(Vector3(14, 4, -12), Vector3(3, 8, 3), Color(0.55, 0.5, 0.6))
	_add_block(Vector3(-16, 0.5, -16), Vector3(6, 1, 6), Color(0.65, 0.6, 0.5))
	_add_block(Vector3(18, 1.5, 14), Vector3(4, 3, 10), Color(0.6, 0.5, 0.45))
	# The shrine: the only place to swap skills mid-round
	shrine = Shrine.new()
	add_child(shrine)
	shrine.position = SHRINE_POS
	structures.append([Vector2(SHRINE_POS.x, SHRINE_POS.z), 3.0])
	# A raised platform with a ramp up to it
	_add_block(Vector3(-6, 1, 12), Vector3(8, 2, 4), Color(0.6, 0.6, 0.55))
	_add_block(Vector3(-6, 0.8, 7.3), Vector3(2.5, 0.4, 5.9), Color(0.5, 0.45, 0.4), Vector3(-0.35, 0, 0))   # top edge flush with the platform


const DASH_TRAIL := 4.5          # length of the sparkle trail others see behind a dash
const WORLD_LAYER := 1         # everything real you can see and hit
const BOUNDS_LAYER := 2        # invisible map walls and ceiling
const CEILING := 24.0


func _add_invisible(center: Vector3, size: Vector3) -> void:
	var body := StaticBody3D.new()
	var shape_node := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape_node.shape = box
	body.add_child(shape_node)
	body.position = center
	# Its own layer: it stops bodies (players, cherubs) but aim rays and
	# throws go right through.
	body.collision_layer = BOUNDS_LAYER
	body.collision_mask = 0
	add_child(body)


func _random_spot() -> Vector3:
	for _attempt in 60:
		var p := Vector2(rng.randf_range(-MAP_HALF + 1.5, MAP_HALF - 1.5), rng.randf_range(-MAP_HALF + 1.5, MAP_HALF - 1.5))
		var ok := p.distance_to(Vector2(ANGEL_SPAWN.x, ANGEL_SPAWN.z)) > 5.0 \
				and p.distance_to(Vector2(DEMON_SPAWN.x, DEMON_SPAWN.z)) > 3.0
		for s in structures:
			if ok and p.distance_to(s[0]) < s[1]:
				ok = false
		for u in used_spots:
			if ok and p.distance_to(u) < 1.8:
				ok = false
		if ok:
			used_spots.append(p)
			return Vector3(p.x, 0, p.y)
	return Vector3.ZERO


func _spawn_prop(type_name: String, pos: Vector3) -> void:
	var body := StaticBody3D.new()
	body.add_to_group("prop")
	body.set_meta("prop_type", type_name)
	body.add_child(PropLib.make_visual(type_name))
	var shape_node := CollisionShape3D.new()
	shape_node.shape = PropLib.make_shape(type_name)
	shape_node.position.y = PropLib.height(type_name) / 2.0
	body.add_child(shape_node)
	body.position = pos
	body.rotation.y = rng.randf_range(0, TAU)
	body.set_meta("prop_index", props.size())
	props.append(body)
	round_root.add_child(body)


# Fresh props for a round. The same seed gives the same layout on every computer,
# which is how everyone in an online match sees an identical map.
func _reset_round_props(seed_value: int) -> void:
	if round_root:
		round_root.free()
	round_root = Node3D.new()
	add_child(round_root)
	used_spots.clear()
	props.clear()
	cherubs.clear()
	powerups.reset()
	_auth_cherubs.clear()
	_auth_fires.clear()
	fires.clear()
	_possessions.clear()
	rng.seed = seed_value
	var types := PropLib.type_names()
	for i in PROP_COUNT:
		_spawn_prop(types[rng.randi() % types.size()], _random_spot())


# Spread players out around a spawn point so they don't stack.
func spawn_point(for_role: String, index: int) -> Vector3:
	var base := ANGEL_SPAWN if for_role == "angel" else DEMON_SPAWN
	var offsets := [Vector3.ZERO, Vector3(1.5, 0, 0), Vector3(-1.5, 0, 0), Vector3(0, 0, 1.5),
			Vector3(0, 0, -1.5), Vector3(1.5, 0, 1.5), Vector3(-1.5, 0, 1.5), Vector3(1.5, 0, -1.5)]
	return base + offsets[index % offsets.size()]


func _spawn_bot(type_name: String, pos: Vector3) -> void:
	var bot := BotDemon.new()
	bot.setup(type_name)
	bot.position = pos
	bot.rotation.y = rng.randf_range(0, TAU)
	bot.caught.connect(_on_bot_caught)
	round_root.add_child(bot)


# ---------- menus ----------

func _panel(min_width: float) -> Array:
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	hud_layer.add_child(panel)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 18)
	panel.add_child(margin)
	var box := VBoxContainer.new()
	box.custom_minimum_size.x = min_width
	box.add_theme_constant_override("separation", 10)
	margin.add_child(box)
	return [panel, box]


func _button(parent: Control, text: String, action: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size.y = 40
	b.pressed.connect(action)
	parent.add_child(b)
	return b


func _field(parent: Control, label_text: String, placeholder: String) -> LineEdit:
	var lbl := Label.new()
	lbl.text = label_text
	parent.add_child(lbl)
	var e := LineEdit.new()
	e.placeholder_text = placeholder
	parent.add_child(e)
	return e


func _build_menu() -> void:
	var parts := _panel(420)
	menu_panel = parts[0]
	var box: VBoxContainer = parts[1]
	var title := Label.new()
	title.text = "HALOS & HORNS"
	title.add_theme_font_size_override("font_size", 40)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	var version := Label.new()
	version.text = "version %s (%s)" % [game_version, GAME_CODENAME]
	version.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(version)
	# Hidden unless a newer version is out (see _refresh_update_row).
	update_button = _button(box, "", func(): updater.install())
	update_button.visible = false
	update_note = Label.new()
	update_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	update_note.add_theme_color_override("font_color", Color(1.0, 0.7, 0.5))
	update_note.visible = false
	box.add_child(update_note)
	name_edit = _field(box, "Your name", "Name")
	_build_loadout(box)
	_button(box, "Practice (single player)", start_practice)
	box.add_child(HSeparator.new())
	port_edit = _field(box, "Port", str(NetGame.DEFAULT_PORT))
	_button(box, "Host a game", _on_host_pressed)
	address_edit = _field(box, "Host's address (to join)", "e.g. 203.0.113.5")
	_button(box, "Join a game", _on_join_pressed)
	box.add_child(HSeparator.new())
	_button(box, "Controls", _open_controls)
	_button(box, "Quit", func(): get_tree().quit())
	menu_status = Label.new()
	menu_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	menu_status.add_theme_color_override("font_color", Color(1.0, 0.7, 0.5))
	box.add_child(menu_status)


func _refresh_update_row() -> void:
	update_button.text = updater.button_text
	update_button.visible = updater.state != "idle"
	update_button.disabled = updater.state in ["downloading", "restarting"]
	update_note.text = updater.note
	update_note.visible = updater.note != ""


func _build_pause_menu() -> void:
	var parts := _panel(300)
	pause_panel = parts[0]
	var box: VBoxContainer = parts[1]
	var title := Label.new()
	title.text = "Paused (the game keeps running)"
	box.add_child(title)
	_button(box, "Resume", func():
		pause_panel.visible = false
		_refresh_mouse())
	_button(box, "Controls", _open_controls)
	_button(box, "Leave to main menu", func(): _show_menu(""))
	pause_panel.visible = false


# ---- Controls: rebind any action to any key or mouse button ----
var controls_panel: PanelContainer
var _bind_buttons := {}        # action -> its Button
var _rebinding := ""           # action waiting for a key press
var _controls_note: Label


func _build_controls() -> void:
	var parts := _panel(560)
	controls_panel = parts[0]
	var solid := StyleBoxFlat.new()
	solid.bg_color = Color(0.12, 0.12, 0.15, 0.97)
	solid.set_corner_radius_all(6)
	controls_panel.add_theme_stylebox_override("panel", solid)
	var box: VBoxContainer = parts[1]
	var title := Label.new()
	title.text = "Controls"
	title.add_theme_font_size_override("font_size", 28)
	box.add_child(title)
	var hint := Label.new()
	hint.text = "Click a key, then press the key or mouse button you want. Esc cancels."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(hint)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(540, 420)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)
	var rows := VBoxContainer.new()
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(rows)
	for a in Keybinds.ACTIONS:
		var row := HBoxContainer.new()
		var lbl := Label.new()
		lbl.text = a[1]
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		row.add_child(lbl)
		var b := Button.new()
		b.custom_minimum_size = Vector2(150, 34)
		var action: String = a[0]
		b.pressed.connect(func(): _start_rebind(action))
		row.add_child(b)
		rows.add_child(row)
		_bind_buttons[action] = b
	_controls_note = Label.new()
	_controls_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_controls_note.add_theme_color_override("font_color", Color(1.0, 0.8, 0.5))
	box.add_child(_controls_note)
	var bottom := HBoxContainer.new()
	box.add_child(bottom)
	var reset := Button.new()
	reset.text = "Reset all to defaults"
	reset.custom_minimum_size.y = 40
	reset.pressed.connect(func():
		Keybinds.setup({})
		_controls_note.text = "Back to the default keys."
		_refresh_controls()
		_save_settings())
	bottom.add_child(reset)
	var done := Button.new()
	done.text = "Done"
	done.custom_minimum_size = Vector2(120, 40)
	done.pressed.connect(_close_controls)
	bottom.add_child(done)
	controls_panel.visible = false


var _controls_hid: Control     # the menu we hid while Controls is open


func _open_controls() -> void:
	_controls_hid = menu_panel if menu_panel.visible else (pause_panel if pause_panel.visible else null)
	if _controls_hid:
		_controls_hid.visible = false
	_rebinding = ""
	_controls_note.text = ""
	_refresh_controls()
	controls_panel.visible = true
	_refresh_mouse()


func _close_controls() -> void:
	_rebinding = ""
	controls_panel.visible = false
	if _controls_hid:
		_controls_hid.visible = true
		_controls_hid = null
	_save_settings()
	_refresh_mouse()


func _refresh_controls() -> void:
	for action in _bind_buttons:
		_bind_buttons[action].text = "..." if action == _rebinding else Keybinds.key_name(action)


func _start_rebind(action: String) -> void:
	_rebinding = action
	_controls_note.text = ""
	_refresh_controls()


# While waiting for a key: the next key or mouse button becomes the binding.
func _input(event: InputEvent) -> void:
	if _rebinding == "" or not controls_panel.visible:
		return
	if not (event is InputEventKey or event is InputEventMouseButton) or not event.pressed:
		return
	get_viewport().set_input_as_handled()
	if event is InputEventKey and event.physical_keycode == KEY_ESCAPE:
		_rebinding = ""
		_refresh_controls()
		return
	var code := Keybinds.code_of(event)
	if code == "":
		return
	# Whatever else used that key gives it up (except the practice-only skip, which
	# shares Enter with chat on purpose).
	var moved_from := []
	for a in Keybinds.ACTIONS:
		if a[0] != _rebinding and Keybinds.current(a[0]) == code and not (a[0] in ["skip_hiding", "chat_all"] and _rebinding in ["skip_hiding", "chat_all"]):
			Keybinds.bind(a[0], "")
			moved_from.append(a[1])
	Keybinds.bind(_rebinding, code)
	_controls_note.text = ("%s was also on that key; it's now unbound." % ", ".join(moved_from)) if not moved_from.is_empty() else ""
	_rebinding = ""
	_refresh_controls()
	_save_settings()


func _build_lobby() -> void:
	var parts := _panel(460)
	lobby_panel = parts[0]
	var box: VBoxContainer = parts[1]
	var title := Label.new()
	title.text = "Lobby"
	title.add_theme_font_size_override("font_size", 30)
	box.add_child(title)
	lobby_players = Label.new()
	box.add_child(lobby_players)
	lobby_info = Label.new()
	lobby_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(lobby_info)
	_build_loadout(box)
	# Host only: how long the hiding and hunting phases last.
	lobby_times = VBoxContainer.new()
	box.add_child(lobby_times)
	_time_choice(lobby_times, "Hiding time", HIDE_CHOICES, 1)
	_time_choice(lobby_times, "Hunting time", HUNT_CHOICES, 2)
	_time_choice(lobby_times, "Kick idle players", IDLE_CHOICES, 0, func(i): if net: net.idle_limit = IDLE_CHOICES[i])
	var kick_row := HBoxContainer.new()
	lobby_times.add_child(kick_row)
	_kick_pick = OptionButton.new()
	_kick_pick.custom_minimum_size.x = 200
	kick_row.add_child(_kick_pick)
	var kick_btn := Button.new()
	kick_btn.text = "Kick"
	kick_btn.pressed.connect(func():
		if net and _kick_pick.selected >= 0:
			net.kick_by_name(_kick_pick.get_item_text(_kick_pick.selected), "The host kicked you."))
	kick_row.add_child(kick_btn)
	lobby_start = _button(box, "Start round", func():
		if net:
			net.hide_time = HIDE_CHOICES[_time_pick["Hiding time"]]
			net.hunt_time = HUNT_CHOICES[_time_pick["Hunting time"]]
			net.start_round())
	_button(box, "Leave", func(): _show_menu(""))
	lobby_panel.visible = false


func _time_choice(parent: Control, label_text: String, choices: Array, default_index: int, on_pick := Callable()) -> void:
	var row := HBoxContainer.new()
	var lbl := Label.new()
	lbl.text = label_text
	lbl.custom_minimum_size.x = 140
	row.add_child(lbl)
	var ob := OptionButton.new()
	for secs in choices:
		ob.add_item("Off" if secs == 0 else "%d:%02d" % [int(secs) / 60, int(secs) % 60])
	ob.select(default_index)
	_time_pick[label_text] = default_index
	ob.item_selected.connect(func(i):
		_time_pick[label_text] = i
		if on_pick.is_valid():
			on_pick.call(i))
	row.add_child(ob)
	parent.add_child(row)


# Pick 2 skills per side. Shown on the main menu and in the lobby (between rounds).
func _build_loadout(parent: Control) -> void:
	var title := Label.new()
	title.text = "Your skills (2 per side)"
	parent.add_child(title)
	for team in ["angel", "demon"]:
		var row := HBoxContainer.new()
		var lbl := Label.new()
		lbl.text = "Angel:" if team == "angel" else "Demon:"
		lbl.custom_minimum_size.x = 64
		row.add_child(lbl)
		var keys: Array = ["Skill 1", "Skill 2"]   # (the keys are on the Controls screen)
		for slot in 2:
			var ob := OptionButton.new()
			ob.add_item("%s: none" % keys[slot])
			ob.set_item_metadata(0, "")
			for id in Skills.for_team(team):
				ob.add_item("%s: %s" % [keys[slot], Skills.label(id)])
				ob.set_item_metadata(ob.item_count - 1, id)
				ob.set_item_tooltip(ob.item_count - 1, Skills.SKILLS[id]["desc"])
			ob.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			ob.item_selected.connect(func(i): _on_loadout_pick(team, slot, ob.get_item_metadata(i)))
			row.add_child(ob)
			_loadout_buttons.append([team, slot, ob])
		parent.add_child(row)
	_sync_loadout_buttons()


func _on_loadout_pick(team: String, slot: int, id: String) -> void:
	var picked: Array = loadout[team].duplicate()
	if id != "" and id in picked:
		picked[picked.find(id)] = ""   # picking it in the other slot moves it
	picked[slot] = id
	loadout[team] = Skills.clean_loadout(team, picked)
	_apply_loadout()
	_save_settings()


func _apply_loadout() -> void:
	player.loadout = loadout.duplicate(true)
	_sync_loadout_buttons()
	if net:
		net.send_loadout(loadout)


func _sync_loadout_buttons() -> void:
	for entry in _loadout_buttons:
		var ob: OptionButton = entry[2]
		var id: String = loadout[entry[0]][entry[1]]
		for i in ob.item_count:
			if ob.get_item_metadata(i) == id:
				ob.select(i)


func _load_settings() -> void:
	_settings.load(SETTINGS_PATH)
	name_edit.text = _settings.get_value("player", "name", "")
	address_edit.text = _settings.get_value("net", "address", "")
	port_edit.text = str(_settings.get_value("net", "port", NetGame.DEFAULT_PORT))
	for team in ["angel", "demon"]:
		loadout[team] = Skills.clean_loadout(team, _settings.get_value("skills", team, Skills.DEFAULTS[team]))
	# Picks saved before Fly became a skill (v0.3.1) wouldn't include it: reset once.
	if _settings.get_value("skills", "version", 1) < 2:
		loadout["demon"] = Skills.DEFAULTS["demon"].duplicate()
	_apply_loadout()
	var saved_keys := {}
	if _settings.has_section("keys"):
		for action in _settings.get_section_keys("keys"):
			saved_keys[action] = str(_settings.get_value("keys", action))
	Keybinds.setup(saved_keys)


func _save_settings() -> void:
	_settings.set_value("player", "name", name_edit.text)
	_settings.set_value("net", "address", address_edit.text)
	_settings.set_value("net", "port", int(port_edit.text) if port_edit.text.is_valid_int() else NetGame.DEFAULT_PORT)
	_settings.set_value("skills", "angel", loadout["angel"])
	_settings.set_value("skills", "demon", loadout["demon"])
	_settings.set_value("skills", "version", 2)
	for a in Keybinds.ACTIONS:
		_settings.set_value("keys", a[0], Keybinds.current(a[0]))
	_settings.save(SETTINGS_PATH)


func _show_menu(message: String) -> void:
	if net:
		net.leave()
		net.name = "NetOld"
		net.queue_free()
		net = null
	mode = "menu"
	state = State.LOBBY
	player.net_mode = ""
	player.frozen = true
	player.set_role("demon")
	player.velocity = Vector3.ZERO
	player.global_position = Vector3(0, 0.1, 22)   # a nice view of the map behind the menu
	player.rotation.y = 0.0
	player.visual_root.visible = false             # don't stand in front of the menu
	if round_root:
		round_root.free()
		round_root = null
	menu_status.text = message
	menu_panel.visible = true
	pause_panel.visible = false
	lobby_panel.visible = false
	tuning_panel.visible = false
	blind_rect.visible = false
	center_label.text = ""
	_refresh_mouse()


func _hide_menus() -> void:
	menu_panel.visible = false
	pause_panel.visible = false
	lobby_panel.visible = false
	_refresh_mouse()


func _port() -> int:
	return int(port_edit.text) if port_edit.text.is_valid_int() else NetGame.DEFAULT_PORT


func _make_net() -> void:
	net = NetGame.new()
	net.name = "Net"     # must be the same path on every computer
	net.main = self
	add_child(net)


func _on_host_pressed() -> void:
	if not NetGame.name_ok(name_edit.text):
		menu_status.text = NetGame.NOPE
		return
	_save_settings()
	_make_net()
	var err: Error = net.host(_port(), name_edit.text)
	if err != OK:
		_show_menu("Couldn't host on port %d (error %d). Is another copy already hosting?" % [_port(), err])
		return
	mode = "online"
	player.net_mode = "server"
	net.send_loadout(loadout)
	_hide_menus()
	_fetch_public_ip()
	online_lobby(lobby_names, "lobby")


func _on_join_pressed() -> void:
	var address := address_edit.text.strip_edges()
	if address == "":
		menu_status.text = "Type the host's address first."
		return
	if not NetGame.name_ok(name_edit.text):
		menu_status.text = NetGame.NOPE
		return
	_save_settings()
	_make_net()
	var err: Error = net.join(address, _port(), name_edit.text)
	if err != OK:
		_show_menu("Couldn't start connecting (error %d)." % err)
		return
	mode = "online"
	player.net_mode = "client"
	player.on_claim = func(seq, eid, point): if net: net.claim_hit(seq, eid, point)
	_hide_menus()
	lobby_players.text = "Connecting to %s..." % address
	lobby_info.text = ""
	lobby_start.visible = false
	lobby_panel.visible = true
	_refresh_mouse()


# The host's internet address, to share with friends (asks a free lookup service).
func _fetch_public_ip() -> void:
	var req := HTTPRequest.new()
	add_child(req)
	req.request_completed.connect(func(result, code, _headers, body):
		if result == HTTPRequest.RESULT_SUCCESS and code == 200:
			_public_ip = body.get_string_from_utf8().strip_edges()
			if net and lobby_panel.visible:
				online_lobby(lobby_names, "lobby")
		req.queue_free())
	req.request("https://api.ipify.org")


# Real network addresses only, labeled with the adapter name ("Ethernet", "Wi-Fi").
# Virtual adapters from VirtualBox, VMware, Hyper-V, WSL and so on are left out:
# friends can't reach those, and they're confusing.
func _local_ips() -> Array:
	var ips := []
	var virtual_words := ["virtualbox", "vmware", "vethernet", "hyper-v", "wsl", "loopback",
			"bluetooth", "docker", "tap", "tun", "zerotier", "tailscale"]
	for iface in IP.get_local_interfaces():
		var label: String = str(iface.get("friendly", iface.get("name", "")))
		var lower := label.to_lower()
		var skip := false
		for w in virtual_words:
			if w in lower:
				skip = true
		for ip in iface.get("addresses", []):
			if skip or ip.count(".") != 3 or ip.begins_with("127.") or ip.begins_with("169.254.") \
					or ip.begins_with("192.168.56."):   # VirtualBox's usual fake network
				continue
			ips.append("%s (%s)" % [ip, label] if label != "" else ip)
	return ips


# ---------- practice rounds ----------

func start_practice() -> void:
	_hide_menus()
	mode = "practice"
	player.net_mode = ""
	start_round()


func start_round() -> void:
	_reset_round_props(randi())
	var types := PropLib.type_names()
	bots_left = 0
	if role == "angel":
		for i in BOT_COUNT:
			_spawn_bot(types[rng.randi() % types.size()], _random_spot())
			bots_left += 1

	player.set_role(role)
	player.velocity = Vector3.ZERO
	player.global_position = ANGEL_SPAWN if role == "angel" else DEMON_SPAWN
	player.rotation.y = PI if role == "angel" else 0.0   # angel faces into the map
	player.frozen = role == "angel"
	state = State.HIDING
	time_left = HIDE_TIME
	blind_rect.visible = role == "angel"
	controls_label.text = _controls_text()
	if role == "angel":
		_toast("The demons are hiding...\n(%s to skip the wait while testing)" % Keybinds.key_name("skip_hiding"), HIDE_TIME)
	else:
		_toast("Demon sandbox: practice possessing props.\nTry Host / Join for real hunting.", 5.0)


func _controls_text() -> String:
	var k := Keybinds.key_name
	var move := "%s%s%s%s" % [k.call("move_forward"), k.call("move_left"), k.call("move_back"), k.call("move_right")]
	var common := "%s move   %s run   %s sneak   %s jump   %s / %s taunt   %s first/third person" % [
		move, k.call("run"), k.call("sneak"), k.call("jump"), k.call("taunt_random"), k.call("taunt_signature"), k.call("toggle_view")]
	var skills := "%s / %s skills" % [k.call("skill_1"), k.call("rmb")]
	var side := "%s throw   %s   %s melee   %s look around   %s swap skills (at the shrine)" % [
		k.call("shoot"), skills, k.call("melee"), k.call("free_look"), k.call("shrine")] if role == "angel" \
		else "%s a prop: transform   Hold %s: demon form   %s (hold Fly to rise)   %s + mouse: turn your prop   %s swap skills (at the shrine)" % [
		k.call("shoot"), k.call("shoot"), skills, k.call("run"), k.call("shrine")]
	if mode == "practice":
		return common + "\n" + side + "   %s switch side   %s restart   %s movement tuning   Esc menu" % [k.call("switch_role"), k.call("restart"), k.call("toggle_tuning")]
	return common + "\n" + side + "   %s roster   %s / %s chat   Esc menu" % [k.call("scoreboard"), k.call("chat_all"), k.call("chat_team")]


func _start_hunting() -> void:
	state = State.HUNTING
	time_left = HUNT_TIME
	player.frozen = false
	blind_rect.visible = false
	if role == "angel":
		_toast("Find the %d demons hiding as props!" % bots_left, 3.0)
	else:
		_toast("The hunt is on!", 2.0)


func _end_round(message: String) -> void:
	state = State.ENDED
	_toast(message + "\nR to play again   Tab to switch sides", 9999.0)


func _on_bot_caught(bot) -> void:
	_play("caught")
	if is_instance_valid(bot):
		powerups.demon_caught(bot.global_position)
	bots_left -= 1
	if bots_left <= 0 and state == State.HUNTING:
		_end_round("All demons caught! Angels win!")
	else:
		_toast("Demon caught! %d left" % bots_left, 2.0)


func _process(delta: float) -> void:
	if mode == "practice" and state != State.ENDED:
		time_left -= delta
		if time_left <= 0.0:
			if state == State.HIDING:
				_start_hunting()
			else:
				_end_round("Time's up! The demons win." if role == "angel" else "Time's up! You survived!")
	elif mode == "online":
		time_left = maxf(time_left - delta, 0.0)   # the host decides when phases change
	if is_authority():
		_check_cherubs(delta)
		_check_naughty(delta)
		if state == State.HUNTING:
			powerups.decider_tick(delta)
			_check_sense(delta)
	_check_burning()
	_update_shrine(delta)
	_update_chat(delta)
	_update_hud(delta)


# ---------- online (called by net_game.gd) ----------

func in_online_round() -> bool:
	return mode == "online" and (state == State.HIDING or state == State.HUNTING)


func _phase_to_state(phase: String) -> State:
	match phase:
		"hiding":
			return State.HIDING
		"hunting":
			return State.HUNTING
		"ended":
			return State.ENDED
	return State.LOBBY


func online_lobby(names: Array, host_phase: String) -> void:
	lobby_names = names
	if _kick_pick and net and net.is_host:
		_kick_pick.clear()
		for n in names.slice(1):   # everyone but the host (always first)
			_kick_pick.add_item(n)
	if state != State.LOBBY:
		return   # mid-round: the list updates, the panel stays hidden
	lobby_players.text = "Players (%d):\n  %s" % [names.size(), "\n  ".join(_lobby_lines(names))]
	var is_host: bool = net != null and net.is_host
	lobby_start.visible = is_host
	lobby_times.visible = is_host
	if is_host:
		lobby_start.disabled = names.size() < 2
		lobby_start.text = "Start round" if names.size() >= 2 else "Start round (need at least 2 players)"
		var lines := ["Friends join with your address and port %d:" % _port()]
		if _public_ip != "":
			lines.append("  Over the internet: %s  (needs the port forwarded on your router)" % _public_ip)
		var lan := _local_ips()
		if not lan.is_empty():
			lines.append("  Same house / same Wi-Fi: %s" % ", ".join(lan))
		lobby_info.text = "\n".join(lines)
	elif host_phase == "lobby":
		lobby_info.text = "Waiting for the host to start the round..."
	else:
		lobby_info.text = "A round is in progress. You'll join it as an angel in a moment..."
	lobby_panel.visible = true
	_refresh_mouse()


# Lobby list with pings when the host has sent them.
func _lobby_lines(names: Array) -> Array:
	var lines := []
	for n in names:
		var line: String = n
		for row in scoreboard_rows:
			if row[0] == n:
				if row[6]:
					line += "   (host)"
				elif row[2] >= 0:
					line += "   %d ms" % row[2]
				if row[5]:
					line += "   <- you"
		lines.append(line)
	return lines


func online_scoreboard(rows: Array) -> void:
	scoreboard_rows = rows
	if lobby_panel.visible and state == State.LOBBY:
		lobby_players.text = "Players (%d):\n  %s" % [lobby_names.size(), "\n  ".join(_lobby_lines(lobby_names))]
	if scoreboard_panel.visible:
		_fill_scoreboard()


func online_round_start(seed_value: int, new_role: String, pos: Vector3, phase: String, seconds: float) -> void:
	_reset_round_props(seed_value)
	role = new_role
	my_health = 1.0
	player.set_role(new_role)
	player.velocity = Vector3.ZERO
	player.global_position = pos
	player.rotation.y = PI if new_role == "angel" else 0.0
	state = _phase_to_state(phase)
	time_left = seconds
	player.frozen = new_role == "angel" and state == State.HIDING
	blind_rect.visible = player.frozen
	controls_label.text = _controls_text()
	lobby_panel.visible = false
	pause_panel.visible = false
	_refresh_mouse()
	if new_role == "angel":
		_toast("You're an ANGEL.\nThe demons are hiding..." if state == State.HIDING else "You're an ANGEL. Find the demons!", 4.0)
	else:
		_toast("You're a DEMON! Hide!\nClick a prop to possess it.", 4.0)


func online_phase(phase: String, seconds: float) -> void:
	state = _phase_to_state(phase)
	time_left = seconds
	if state == State.HUNTING:
		player.frozen = false
		blind_rect.visible = false
		_toast("The hunt is on!" if role == "demon" else "Go find them!", 2.5)


func online_count(n: int) -> void:
	bots_left = n


func online_you_hit(health_fraction: float) -> void:
	my_health = health_fraction
	_hurt_time = 0.25


# The angels yanked us (vacuum orb, kick).
func online_affected(target: Vector3, hatred_drain: float, lockout: float, label: String) -> void:
	player.pull_to(target, 1.0)
	player.hatred = maxf(player.hatred - hatred_drain, 0.0)
	player.skill_lock = maxf(player.skill_lock, lockout)
	_hurt_time = 0.2
	if state != State.ENDED:
		_toast(label, 1.2)


func online_you_were_caught(pos: Vector3, by_name := "") -> void:
	role = "angel"
	player.set_role("angel")
	player.velocity = Vector3.ZERO
	player.global_position = pos
	player.rotation.y = PI
	player.frozen = false
	controls_label.text = _controls_text()
	var who := ("%s got you!\n" % by_name) if by_name != "" else ""
	_toast("%sYou were caught and REDEEMED!\nNow you're an angel. Hunt your old friends!" % who, 4.0)


func online_caught_fx(pos: Vector3) -> void:
	_play("caught")
	Effects.puff(self, pos + Vector3.UP * 0.5, Color(0.8, 0.1, 0.1, 0.9), 1.6)
	if role == "angel" and bots_left > 0:
		_toast("A demon was redeemed! %d left" % bots_left, 2.0)


func online_round_end(message: String) -> void:
	state = State.ENDED
	player.frozen = true
	if is_instance_valid(player.minion):
		player.minion.queue_free()
	_toast(message + "\nBack to the lobby in a few seconds...", 9999.0)


func online_back_to_lobby() -> void:
	state = State.LOBBY
	center_label.text = ""
	blind_rect.visible = false
	if round_root:
		round_root.free()
		round_root = null
	player.frozen = true
	online_lobby(lobby_names, "lobby")


func online_correct(pos: Vector3) -> void:
	player.global_position = pos
	player.velocity = Vector3.ZERO
	player.clear_dash()


func online_disconnected(message: String) -> void:
	_show_menu(message)


func _on_player_launched(origin: Vector3, velocity: Vector3, kind: String, gravity: float, seq: int) -> void:
	if net:
		net.on_local_launched(origin, velocity, kind, gravity, seq)


func _on_player_hit_taken(damage: int, by: Node) -> void:
	if net and net.is_host:
		net.damage_player(1, damage, net.peer_of(by))


# ---------- skills: deciding what happens ----------
# In practice the game itself decides what a skill does; online, the host does
# (net_game.gd checks every request first). The same code runs either way, and
# broadcast_fx() shows the results on every screen.

func is_authority() -> bool:
	return mode == "practice" or (net != null and net.is_host)


func _on_player_skill(id: String, origin: Vector3, dir: Vector3, point: Vector3, index: int) -> void:
	if id == "minion":
		_spawn_my_minion(point, index)
	if mode == "practice":
		authority_skill(player, 0, id, origin, dir, point, index)
	elif net:
		if id == "vacuum" and not net.is_host:
			_spawn_orb(origin, dir, true)   # our own copy, just to see; the host's is real
		if id == "scripture" and not net.is_host:
			_spawn_scripture(origin, dir, true)
		net.on_local_skill(id, origin, dir, point, index)


# A random kind of prop that's standing somewhere on the map right now.
func random_map_prop_type() -> String:
	var kinds := []
	for prop in props:
		if is_instance_valid(prop) and prop.visible and prop.has_meta("prop_type") and not prop.get_meta("prop_type") in kinds:
			kinds.append(prop.get_meta("prop_type"))
	return kinds.pick_random() if not kinds.is_empty() else "crate"


func map_has_prop_type(type_name: String) -> bool:
	for prop in props:
		if is_instance_valid(prop) and prop.has_meta("prop_type") and prop.get_meta("prop_type") == type_name:
			return true
	return false


# Our own decoy: we run it (we steer it); the host shows it to everyone else.
func _spawn_my_minion(at: Vector3, form_index: int) -> void:
	if is_instance_valid(player.minion):
		player.minion.queue_free()
	var m := Minion.new()
	var types: Array = PropLib.type_names()
	m.form = types[form_index] if form_index >= 0 and form_index < types.size() else ""
	m.fall_gravity = player.gravity * player.tuning["gravity_scale"]
	m.jump_velocity = player.tuning["jump_velocity"]
	round_root.add_child(m)
	m.global_position = ground_below(at + Vector3.UP * 1.0)
	m.rotation.y = player.shown_yaw()
	player.minion = m
	if mode == "practice":
		# Practice: hits come straight here; it has the health of the form it copies.
		var hp := [PropLib.max_hp(m.form) * Skills.MINION_HEALTH]
		m.on_hit = func(_by, damage):
			hp[0] -= damage
			award_hatred(0, Skills.NAUGHTY_MINION_HIT, "your minion fooled an angel")
			if hp[0] <= 0 and is_instance_valid(m):
				m.pop()
			return true
	elif net and net.is_host:
		m.on_hit = func(by, damage): return net.minion_hit(1, by, damage)


func _on_player_melee(origin: Vector3, dir: Vector3) -> void:
	if mode == "practice":
		authority_melee(player, 0, origin, dir)
	elif net:
		net.on_local_melee(origin, dir)


func _on_player_released() -> void:
	if mode == "practice":
		authority_release(0, player.global_position, player.shown_yaw())
	elif net:
		net.on_local_release()


func _ray(from: Vector3, to: Vector3, exclude: Array) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(from, to, WORLD_LAYER)
	var rids := []
	for n in exclude:
		if is_instance_valid(n) and n is CollisionObject3D:
			rids.append(n.get_rid())
	q.exclude = rids
	return get_world_3d().direct_space_state.intersect_ray(q)


func ground_below(point: Vector3) -> Vector3:
	var hit := _ray(point + Vector3.UP * 0.5, point + Vector3.DOWN * 40.0, [])
	return hit["position"] if not hit.is_empty() else Vector3(point.x, 0.0, point.z)


# Every demon the decider can affect: practice test demons, or (host) players.
func demon_targets() -> Array:
	if mode == "practice":
		var out := []
		if round_root:
			for c in round_root.get_children():
				if c is BotDemon:
					out.append(c)
		return out
	return net.demon_nodes() if net else []


# `user` is whoever used the skill (our player, or another player's stand-in on the
# host); `user_key` is 0 in practice, otherwise their network id (1 = host).
func authority_skill(user: Node3D, user_key: int, id: String, origin: Vector3, dir: Vector3,
		point: Vector3, index: int) -> void:
	match id:
		"minion":
			if net and net.is_host:
				net.minion_spawned(user_key, point, index)
		"vanish":
			if net and net.is_host:
				net.set_vanished(user_key, Skills.VANISH_TIME)
		"teleport":
			var from: Vector3 = user.global_position
			if Vector2(point.x - from.x, point.z - from.z).length() > Skills.TELEPORT_RANGE + 3.0:
				return
			# (Too far: the point is set high up, so you land on top of whatever is there.)
			var dest := ground_below(point + Vector3.UP * 0.5)
			if absf(dest.x) > MAP_HALF - 1.0 or absf(dest.z) > MAP_HALF - 1.0 or point.y > CEILING:
				return
			broadcast_fx("teleport", [from, dest])
			if mode == "practice":
				player.teleport_to(dest)
			elif net:
				net.teleport_player(user_key, dest)
			print("[decider] teleport")
		"cherub":
			# Thrown from the angel's hands; where it ends up is up to physics.
			_cherub_counter += 1
			var flat := Vector3(dir.x, 0.0, dir.z).normalized()
			var pos: Vector3 = user.global_position + Vector3.UP * 1.1 + flat * 1.2   # clear of the thrower
			var vel: Vector3 = dir * Skills.CHERUB_THROW_SPEED + Vector3.UP * Skills.CHERUB_THROW_UP
			_auth_cherubs[_cherub_counter] = {"pos": pos, "until": Time.get_ticks_msec() / 1000.0 + Skills.CHERUB_LIFETIME,
					"alarmed": false, "rested": false}
			broadcast_fx("cherub", [_cherub_counter, pos, vel])
			print("[decider] cherub dropped")
		"fire":
			# Flung from the demon's hands; it lights wherever it comes down.
			_fire_counter += 1
			var flat := Vector3(dir.x, 0.0, dir.z).normalized()
			var from: Vector3 = user.global_position + Vector3.UP * 1.3 + flat * 0.6
			var vel: Vector3 = dir * Skills.FIRE_THROW_SPEED + Vector3.UP * Skills.FIRE_THROW_UP
			var flight := _fly_until_hit(from, vel, Skills.FIRE_GRAVITY, [user])
			var spot := ground_below(flight[0] - vel.normalized() * 0.3)
			broadcast_fx("fire", [_fire_counter, from, vel, spot, flight[1]])
			_auth_fires[_fire_counter] = {"owner": user_key, "pos": spot, "lit_at": _now() + flight[1],
				"until": _now() + flight[1] + Skills.FIRE_LIFETIME}
			print("[decider] hellfire lit")
		"scripture":
			var book := _spawn_scripture(origin, dir, false)
			book.shooter = user
			broadcast_fx("scripture", [origin, dir], user_key)
		"kick":
			var c = _close_demon(user, dir, Skills.KICK_RANGE)
			if c == null:
				return
			if c.take_hit(Skills.KICK_DAMAGE, user):
				user.confirm_hit()
				var away := Vector3(dir.x, 0.0, dir.z).normalized()
				var land := ground_below(c.global_position + away * Skills.KICK_PUSH + Vector3.UP * 1.0)
				_affect_demon(c, land, 0.0, 0.0, "KICKED!")
				broadcast_fx("kick", [c.global_position + Vector3.UP * 0.6])
				print("[decider] holy kick sent a demon flying")
		"stomp":
			var hurt := 0
			for d in demon_targets():
				var off: Vector3 = d.global_position - origin
				if Vector2(off.x, off.z).length() <= Skills.STOMP_RADIUS and absf(off.y) < 2.5 \
						and d.has_method("take_hit") and d.take_hit(Skills.STOMP_DAMAGE, user):
					hurt += 1
			if hurt > 0 and user.has_method("confirm_hit"):
				user.confirm_hit()
			broadcast_fx("stomp", [origin])
			print("[decider] cloud stomp hit %d demon(s)" % hurt)
		"vacuum":
			var orb := _spawn_orb(origin, dir, false)
			orb.shooter = user
			orb.on_impact = _vacuum_at
			broadcast_fx("orb", [origin, dir], user_key)
		"dash":
			# The dash itself happens on the dasher's own screen; everyone gets the trail.
			var start := user.global_position + Vector3.UP * 0.5
			broadcast_fx("sparkle", [start, start + dir.normalized() * DASH_TRAIL])
			if net and user_key > 1:
				net.grant_dash(user_key)   # they may move fast for a moment
			print("[decider] flying dash")
		"possess":
			_authority_possess(user, user_key, index)


func authority_melee(user: Node3D, _user_key: int, origin: Vector3, dir: Vector3) -> void:
	var d = _close_demon(user, dir, Skills.MELEE_RANGE)
	if d and d.take_hit(Skills.MELEE_DAMAGE, user):
		user.confirm_hit()
		print("[decider] melee hit a demon")


# Up-close attacks (melee, kick) don't need pixel-perfect aim: the nearest demon
# within reach, roughly in front of you (within 45 degrees) and not behind a wall.
func _close_demon(user: Node3D, dir: Vector3, reach: float):
	var flat_dir := Vector2(dir.x, dir.z).normalized()
	var me := user.global_position + Vector3.UP * 0.9
	var best = null
	var best_d := INF
	for d in demon_targets():
		if d == user or not d.has_method("take_hit"):
			continue
		var off: Vector3 = d.global_position + Vector3.UP * 0.5 - me
		var flat := Vector2(off.x, off.z)
		var dist := flat.length()
		if dist > reach + 0.6 or absf(off.y) > 2.0 or dist >= best_d:
			continue
		if dist > 0.5 and rad_to_deg(absf(flat_dir.angle_to(flat))) > 45.0:
			continue
		var wall := _ray(me, d.global_position + Vector3.UP * 0.5, [user, d])
		if not wall.is_empty():
			continue
		best = d
		best_d = dist
	return best


# Follow a thrown thing's arc until it hits something: [where, after how many seconds].
func _fly_until_hit(from: Vector3, vel: Vector3, g: float, skip: Array) -> Array:
	var t := 0.0
	var prev := from
	while t < 4.0:
		t += 0.02
		var p := from + vel * t + Vector3.DOWN * 0.5 * g * t * t
		var hit := _ray(prev, p, skip)
		if not hit.is_empty():
			return [hit["position"], t]
		prev = p
	return [prev, t]


func _spawn_scripture(origin: Vector3, dir: Vector3, visual_only: bool) -> Projectile:
	var book := Projectile.new()
	book.book = true
	book.damage = Skills.SCRIPTURE_DAMAGE
	book.gravity = Skills.SCRIPTURE_GRAVITY
	book.visual_only = visual_only
	_fx_parent().add_child(book)
	book.global_position = origin + dir * 0.6
	book.velocity = dir * Skills.SCRIPTURE_SPEED + Vector3.UP * 3.0
	return book


func _spawn_orb(origin: Vector3, dir: Vector3, visual_only: bool) -> Projectile:
	var orb := Projectile.new()
	orb.color = Color(0.65, 0.35, 1.0)
	orb.size = 0.22
	orb.gravity = 9.0
	orb.damage = 0
	orb.visual_only = visual_only
	_fx_parent().add_child(orb)
	orb.global_position = origin + dir * 0.6
	orb.velocity = dir * 22.0 + Vector3.UP * 2.0
	return orb


func _vacuum_at(center: Vector3) -> void:
	var caught := false
	for d in demon_targets():
		if d.global_position.distance_to(center) <= Skills.VACUUM_RADIUS:
			caught = true
			var offset := Vector3(randf_range(-0.6, 0.6), 0.0, randf_range(-0.6, 0.6))
			_affect_demon(d, center + offset, Skills.VACUUM_HATRED_DRAIN, Skills.VACUUM_LOCKOUT, "VACUUMED!")
	broadcast_fx("vortex", [center, caught])
	print("[decider] vacuum orb %s" % ("CAUGHT a demon" if caught else "found nothing"))


# Yank a demon somewhere, drain Hatred, lock their skills.
func _affect_demon(node: Node3D, target: Vector3, hatred_drain: float, lockout: float, label: String) -> void:
	if node is BotDemon:
		var tw := node.create_tween()
		tw.tween_property(node, "global_position", Vector3(target.x, node.global_position.y, target.z), 0.3)
	elif net:
		net.affect_node(node, target, hatred_drain, lockout, label)


func _authority_possess(user: Node3D, user_key: int, index: int) -> void:
	if index < 0 or index >= props.size():
		return
	var prop = props[index]
	if not is_instance_valid(prop) or not prop.is_in_group("prop"):
		return   # already possessed by someone, or dissolving
	if user.global_position.distance_to(prop.global_position) > 12.0:
		return
	var from: Vector3 = user.global_position
	authority_release(user_key, from, user.rotation.y)
	_possessions[user_key] = index
	broadcast_fx("prop_taken", [index])
	broadcast_fx("sparkle", [from, prop.global_position])
	var type_name: String = prop.get_meta("prop_type")
	if user_key <= 1:
		player.become_possessed(type_name, prop.global_position, prop.rotation.y, index)
	else:
		net.tell_possessed(user_key, type_name, prop.global_position, prop.rotation.y, index)
	print("[decider] a demon possessed a %s" % type_name)


# Someone left a possessed prop (or was caught in it): the original stays where
# they left it and slowly dissolves.
func authority_release(user_key: int, pos: Vector3, yaw: float) -> void:
	if not _possessions.has(user_key):
		return
	var index: int = _possessions[user_key]
	_possessions.erase(user_key)
	broadcast_fx("prop_shell", [index, pos, yaw])


# Decider only: a blessing hit a cherub. Send it skidding the way the shot was going.
func kick_cherub(cid: int, shot_velocity: Vector3) -> void:
	if not _auth_cherubs.has(cid) or not cherubs.has(cid) or not is_instance_valid(cherubs[cid]):
		return
	var flat := Vector3(shot_velocity.x, 0, shot_velocity.z)
	if flat.length() < 0.1:
		return
	var vel := flat.normalized() * Skills.CHERUB_KICK_SPEED + Vector3.UP * Skills.CHERUB_KICK_UP
	var pos: Vector3 = cherubs[cid].global_position + Vector3.UP * 0.05
	_auth_cherubs[cid]["rested"] = false
	broadcast_fx("cherub_kick", [cid, pos, vel])
	print("[decider] cherub kicked")


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


# ---- Hatred for naughtiness ----
# Demons earn a little Hatred for being naughty: angels roasting in their fire,
# their minion fooling an angel, taunting right under an angel's nose.
# The decider (host / practice game) hands it out.
# ---- Power-ups (the drops are in powerups.gd) ----

# Everyone the decider can see: [key, body, team]. (Practice: you, and the test demons.)
func team_entries() -> Array:
	if mode == "practice":
		var out := [[0, player, role]]
		var i := 1
		for b in get_tree().get_nodes_in_group("demon"):
			out.append([-i, b, "demon"])
			i += 1
		return out
	return net.team_entries() if net else []


# Decider: someone picked up a power-up.
func give_powerup(user_key: int, kind: String, where: Vector3) -> void:
	if user_key < 0:
		return   # a practice test demon walked over it
	if kind == "fire_burst":
		broadcast_fx("fire_burst", [where])
		var burned := 0
		for e in team_entries():
			if e[2] == "angel" and e[1].global_position.distance_to(where) <= PowerUps.FIRE_BURST_RADIUS:
				burned += 1
				if mode == "practice":
					e[1].burning = maxf(e[1].burning, Skills.FIRE_LINGER * 2.0)
				elif net:
					net.burn_player(e[0], Skills.FIRE_LINGER * 2.0)
		if burned > 0:
			award_hatred(user_key, Skills.NAUGHTY_FIRE_PER_SEC * burned, "your fire burst caught an angel")
		return
	if mode == "practice":
		player.apply_powerup(kind)
	elif net:
		net.give_powerup(user_key, kind)


# Cherub Sense: a red bubble pulses around you and the horn blares while a demon is close.
func _update_sense_bubble(delta: float) -> void:
	if _sense_bubble == null:
		_sense_bubble = MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 1.0
		sm.height = 2.0
		_sense_bubble.mesh = sm
		var mat := StandardMaterial3D.new()
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		mat.albedo_color = Color(1.0, 0.15, 0.1, 0.12)
		_sense_bubble.material_override = mat
		player.add_child(_sense_bubble)
	_sense_bubble.visible = player.sense_alarm
	if player.sense_alarm:
		var tt := Time.get_ticks_msec() / 1000.0
		_sense_bubble.scale = Vector3.ONE * Skills.CHERUB_RADIUS * (0.6 + 0.4 * absf(sin(tt * 3.0)))
		_sense_bubble.position.y = 0.9
		_sense_sound_time -= delta
		if _sense_sound_time <= 0.0:
			_sense_sound_time = 0.8
			_play("sense")


# Cherub Sense: an angel with it acts like a walking alarm cherub.
var _sense_tick := 0.0


func _check_sense(delta: float) -> void:
	_sense_tick -= delta
	if _sense_tick > 0.0:
		return
	_sense_tick = 0.25
	if mode == "practice":
		if role == "angel" and player.powerup_left("sense") > 0.0:
			var near := false
			for d in demon_targets():
				if d.global_position.distance_to(player.global_position) <= Skills.CHERUB_RADIUS:
					near = true
			player.sense_alarm = near
	elif net:
		net.check_sense()


func award_hatred(user_key: int, amount: float, reason: String) -> void:
	if mode == "practice" and user_key == 0:
		player.add_hatred(amount, reason)
	elif net and net.is_host:
		net.grant_hatred(user_key, amount, reason)


func angel_nodes() -> Array:
	if mode == "practice":
		return [player] if role == "angel" else []
	return net.angel_nodes() if net else []


func _check_naughty(delta: float) -> void:
	_naughty_tick -= delta
	if _naughty_tick > 0.0 or state != State.HUNTING:
		return
	_naughty_tick = 0.5
	var t := _now()
	for id in _auth_fires.keys():
		var f: Dictionary = _auth_fires[id]
		if t > f["until"]:
			_auth_fires.erase(id)
			continue
		if t < f["lit_at"]:
			continue
		for a in angel_nodes():
			var off: Vector3 = a.global_position - f["pos"]
			if Vector2(off.x, off.z).length() <= Skills.FIRE_RADIUS and off.y > -0.5 and off.y < 1.5:
				award_hatred(f["owner"], Skills.NAUGHTY_FIRE_PER_SEC * 0.5, "an angel is roasting in your fire")


# Our own angel standing in demon fire? (Slowed, blessings burn away.)
func _check_burning() -> void:
	if role != "angel" or state != State.HUNTING:
		return   # angels are safe from fire until the hunt starts
	var me := player.global_position
	for id in fires.keys():
		var f = fires[id]
		if not is_instance_valid(f):
			fires.erase(id)
			continue
		var off: Vector3 = me - f.global_position
		if f.is_lit() and Vector2(off.x, off.z).length() <= Skills.FIRE_RADIUS and off.y > -0.5 and off.y < 1.5:
			player.burning = maxf(player.burning, Skills.FIRE_LINGER)


func _check_cherubs(delta: float) -> void:
	_cherub_check -= delta
	if _cherub_check > 0.0 or _auth_cherubs.is_empty():
		return
	_cherub_check = 0.25
	var now := Time.get_ticks_msec() / 1000.0
	var targets := demon_targets()
	for cid in _auth_cherubs.keys():
		var c: Dictionary = _auth_cherubs[cid]
		if now > c["until"]:
			_auth_cherubs.erase(cid)
			continue
		var node = cherubs.get(cid)
		if node != null and is_instance_valid(node):
			c["pos"] = node.global_position   # it may have been knocked somewhere
			# Once it comes to rest, tell everyone where it ended up (tiny drift fix).
			if node.is_on_floor() and node.velocity.length() < 0.2 and not c.get("rested", true):
				c["rested"] = true
				broadcast_fx("cherub_kick", [cid, node.global_position, Vector3.ZERO])
		var near := false
		var closest := Vector3.ZERO      # from the cherub to the nearest demon it can sense
		var closest_dist := INF
		for d in targets:
			var dist: float = d.global_position.distance_to(c["pos"])
			if dist <= Skills.CHERUB_RADIUS:
				near = true
				if dist < closest_dist:
					closest_dist = dist
					closest = d.global_position - c["pos"]
		if near != c["alarmed"]:
			c["alarmed"] = near
			broadcast_fx("cherub_alarm", [cid, near])
			if near:
				print("[decider] cherub alarm: demon nearby")
		# An alarmed cherub creeps toward that demon. Only tell everyone when its
		# heading really changes, not four times a second.
		var creep := Vector3.ZERO
		closest.y = 0.0
		if near and closest.length() > Skills.CHERUB_CREEP_STOP:
			creep = closest.normalized() * Skills.CHERUB_CREEP_SPEED
		var old: Vector3 = c.get("creep", Vector3.ZERO)
		if creep.is_zero_approx() != old.is_zero_approx() or (not creep.is_zero_approx() and creep.angle_to(old) > 0.2):
			c["creep"] = creep
			if creep.is_zero_approx():
				c["rested"] = false      # when it has stopped, tell everyone exactly where
			broadcast_fx("cherub_creep", [cid, creep])


# ---------- effects everyone sees ----------

# Show an effect here and on everyone else's screen. `except_key` is the player
# who caused it: they already drew their own orb, so they don't get a copy.
func broadcast_fx(kind: String, args: Array, except_key := -1) -> void:
	var we_caused_it := except_key == 0 or except_key == 1   # practice player or the host
	# Orbs and books: the decider's own real projectile is already flying here.
	var real_one_here := kind == "orb" or kind == "scripture"
	if not real_one_here:
		fx(kind, args)
	if net and net.is_host:
		net.send_fx(kind, args, except_key)


func _fx_parent() -> Node:
	return round_root if round_root else self


func fx_parent() -> Node:
	return _fx_parent()


func puff_at(pos: Vector3, color: Color, size: float) -> void:
	Effects.puff(_fx_parent(), pos, color, size)


func fx(kind: String, args: Array) -> void:
	match kind:
		"teleport":
			Effects.puff(_fx_parent(), args[0] + Vector3.UP * 0.8, Color(0.15, 0.02, 0.05, 0.85), 1.8)
			Effects.puff(_fx_parent(), args[1] + Vector3.UP * 0.5, Color(0.15, 0.02, 0.05, 0.6), 0.9)
		"powerup":
			powerups.show_item(args[0], args[1], args[2])
		"powerup_gone":
			powerups.hide_item(args[0], args[1])
		"fire_burst":
			for i in 10:
				var a := TAU * i / 10.0
				Effects.puff(_fx_parent(), args[0] + Vector3(cos(a), 0.3, sin(a)) * PowerUps.FIRE_BURST_RADIUS * 0.6, Color(1.0, 0.45, 0.05, 0.85), 2.2)
			Effects.puff(_fx_parent(), args[0] + Vector3.UP * 0.5, Color(1.0, 0.3, 0.0, 0.9), 3.5)
		"cherub":
			var c := Cherub.new()
			c.cherub_id = args[0]
			_fx_parent().add_child(c)
			c.launch(args[1], args[2] if args.size() > 2 else Vector3.ZERO)
			cherubs[args[0]] = c
			if mode != "online" or (net and net.is_host):
				c.on_kick = kick_cherub
		"cherub_kick":
			if cherubs.has(args[0]) and is_instance_valid(cherubs[args[0]]):
				cherubs[args[0]].launch(args[1], args[2])
		"cherub_creep":
			if cherubs.has(args[0]) and is_instance_valid(cherubs[args[0]]):
				cherubs[args[0]].creep = args[1]
		"cherub_alarm":
			if cherubs.has(args[0]) and is_instance_valid(cherubs[args[0]]):
				cherubs[args[0]].alarmed = args[1]
		"shrine":
			shrine.flare()
		"orb":
			_spawn_orb(args[0], args[1], true)
		"scripture":
			_spawn_scripture(args[0], args[1], true)
		"fire":
			var f := Fire.new()
			f.from = args[1]
			f.vel = args[2]
			f.to = args[3]
			f.flight_time = args[4]
			_fx_parent().add_child(f)
			fires[args[0]] = f
		"kick":
			Effects.puff(_fx_parent(), args[0], Color(1.0, 0.95, 0.6, 0.8), 1.2)
		"minion_pop":
			Effects.puff(_fx_parent(), args[0] + Vector3.UP * 0.6, Color(0.35, 0.05, 0.08, 0.8), 1.6)
		"stomp":
			Effects.puff(_fx_parent(), args[0] + Vector3.UP * 0.2, Color(1.0, 1.0, 1.0, 0.75), Skills.STOMP_RADIUS * 1.5)
			Effects.puff(_fx_parent(), args[0] + Vector3.UP * 0.6, Color(1.0, 0.95, 0.7, 0.6), 2.0)
		"vortex":
			var v := Vortex.new()
			v.caught = args[1]
			_fx_parent().add_child(v)
			v.global_position = args[0]
			_pull_props(args[0])
		"sparkle":
			Effects.sparkle_trail(_fx_parent(), args[0], args[1])
		"prop_taken":
			_set_prop_taken(args[0])
		"prop_shell":
			_make_shell(args[0], args[1], args[2])


# Host: how the props differ from the fresh layout right now (taken by demons, or
# moved by vacuums), so someone joining mid-round sees the same thing as everyone.
func prop_state() -> Array:
	var gone := []
	var moved := []
	for i in props.size():
		var prop = props[i]
		if not is_instance_valid(prop) or not prop.is_in_group("prop"):
			gone.append(i)
		elif prop.has_meta("moved_to"):
			moved.append([i, prop.get_meta("moved_to")])
	return [gone, moved]


func apply_prop_state(gone: Array, moved: Array) -> void:
	for i in gone:
		_set_prop_taken(int(i))
	for m in moved:
		var i := int(m[0])
		if i >= 0 and i < props.size() and is_instance_valid(props[i]):
			props[i].global_position = m[1]


func _set_prop_taken(index: int) -> void:
	if index < 0 or index >= props.size() or not is_instance_valid(props[index]):
		return
	var prop: Node3D = props[index]
	prop.visible = false
	prop.remove_from_group("prop")
	for c in prop.get_children():
		if c is CollisionShape3D:
			c.disabled = true


# The abandoned original: back where the demon left it, solid (shots just hit it,
# no damage), can't be transformed into or possessed again, fading away.
func _make_shell(index: int, pos: Vector3, yaw: float) -> void:
	if index < 0 or index >= props.size() or not is_instance_valid(props[index]):
		return
	var prop: Node3D = props[index]
	prop.global_position = pos
	prop.rotation.y = yaw
	prop.visible = true
	for c in prop.get_children():
		if c is CollisionShape3D:
			c.disabled = false
	# Whoever just left it is standing inside it: let them walk straight out
	# instead of being stuck until it fades. (Everyone else still bumps into it.)
	if player and prop is PhysicsBody3D and player.global_position.distance_to(pos) < 3.0:
		player.add_collision_exception_with(prop)
	Effects.dissolve(prop, 6.0)


# The vortex drags nearby props toward its middle. Every computer runs the same
# math on the same starting positions, so every screen ends up identical.
func _pull_props(center: Vector3) -> void:
	for prop in props:
		if not is_instance_valid(prop) or not prop.is_in_group("prop"):
			continue
		var flat := Vector3(prop.global_position.x - center.x, 0.0, prop.global_position.z - center.z)
		var d := flat.length()
		if d >= Skills.VACUUM_RADIUS or d < 0.01:
			continue
		var target := Vector3(center.x, prop.global_position.y, center.z) + flat / d * maxf(1.2, d * 0.45)
		var tw: Tween = prop.create_tween()
		tw.tween_property(prop, "global_position", target, 1.2).set_ease(Tween.EASE_IN)
		prop.set_meta("moved_to", target)   # (for anyone joining later)


# ---------- command line (automated testing) ----------
# e.g.  godot -- --host --name=Ted --autostart=3 --hide=5
#       godot -- --join=127.0.0.1 --name=Bot --autobot

func _handle_command_line() -> void:
	var args := {}
	for a in OS.get_cmdline_user_args():
		var kv: PackedStringArray = a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "true"
	if args.is_empty():
		return
	if args.has("name"):
		name_edit.text = args["name"]
	if args.has("port"):
		port_edit.text = args["port"]
	if args.has("autobot"):
		autobot = Autobot.new()
		autobot.main = self
		autobot.options = args
		add_child(autobot)
	if args.has("practice"):
		start_practice()
	elif args.has("host"):
		_on_host_pressed()
		if net and args.has("hide"):
			net.hide_time = float(args["hide"])
		if net and args.has("hunt"):
			net.hunt_time = float(args["hunt"])
		if net and args.has("idle"):
			net.idle_limit = float(args["idle"])
		if net and args.has("roles"):   # e.g. --roles=Theo:demon,Wife:angel
			for pair in args["roles"].split(","):
				var kv: PackedStringArray = pair.split(":")
				net.forced_roles[kv[0]] = kv[1]
	elif args.has("join"):
		address_edit.text = args["join"]
		_on_join_pressed()


# ---------- HUD ----------

func _make_label(size: int) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_constant_override("outline_size", 6)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _build_hud() -> void:
	var hud := CanvasLayer.new()
	hud_layer = hud
	add_child(hud)

	# Burning in Hellfire: the whole view wobbles and swims with heat (HUD stays readable).
	heat_rect = ColorRect.new()
	heat_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	heat_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var heat := ShaderMaterial.new()
	heat.shader = Shader.new()
	heat.shader.code = HEAT_SHADER
	heat_rect.material = heat
	heat_rect.visible = false
	hud.add_child(heat_rect)

	blind_rect = ColorRect.new()
	blind_rect.color = Color(0.06, 0.03, 0.1)
	blind_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	blind_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(blind_rect)

	hurt_rect = ColorRect.new()
	hurt_rect.color = Color(0.9, 0.05, 0.05, 0.0)
	hurt_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	hurt_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(hurt_rect)

	status_label = _make_label(30)
	status_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	status_label.position.y = 12
	hud.add_child(status_label)

	center_label = _make_label(36)
	center_label.set_anchors_preset(Control.PRESET_CENTER)
	center_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	center_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	center_label.grow_vertical = Control.GROW_DIRECTION_BOTH
	center_label.position.y -= 120
	hud.add_child(center_label)

	crosshair = _make_label(28)
	crosshair.text = "+"
	crosshair.set_anchors_preset(Control.PRESET_CENTER)
	crosshair.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	crosshair.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	crosshair.grow_horizontal = Control.GROW_DIRECTION_BOTH
	crosshair.grow_vertical = Control.GROW_DIRECTION_BOTH
	hud.add_child(crosshair)

	hint_label = _make_label(24)
	hint_label.set_anchors_preset(Control.PRESET_CENTER)
	hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	hint_label.position.y += 40
	hud.add_child(hint_label)

	controls_label = _make_label(18)
	controls_label.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	controls_label.grow_vertical = Control.GROW_DIRECTION_BEGIN
	controls_label.position += Vector2(16, -16)
	hud.add_child(controls_label)

	# Stamina bars, bottom center
	var bars := VBoxContainer.new()
	bars.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	bars.grow_horizontal = Control.GROW_DIRECTION_BOTH
	bars.grow_vertical = Control.GROW_DIRECTION_BEGIN
	bars.position.y -= 70
	bars.add_theme_constant_override("separation", 6)
	bars.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(bars)
	_make_bar(bars, "health", Color(0.85, 0.2, 0.25))
	_make_bar(bars, "sprint", Color(0.4, 0.85, 0.45))
	_make_bar(bars, "power", Color(1.0, 0.85, 0.3))

	# Hold-to-return progress bar, just under the crosshair
	hold_bar = ColorRect.new()
	hold_bar.color = Color(0, 0, 0, 0.5)
	hold_bar.size = Vector2(80, 6)
	hold_bar.set_anchors_preset(Control.PRESET_CENTER)
	hold_bar.position += Vector2(-40, 24)
	hold_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hold_bar.visible = false
	hud.add_child(hold_bar)
	hold_fill = ColorRect.new()
	hold_fill.color = Color(0.9, 0.2, 0.15)
	hold_fill.size = Vector2(0, 6)
	hold_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hold_bar.add_child(hold_fill)

	# Skills, bottom right
	skill_label = _make_label(18)
	skill_label.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	skill_label.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	skill_label.grow_vertical = Control.GROW_DIRECTION_BEGIN
	skill_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	skill_label.position += Vector2(-16, -76)   # above the two controls lines
	hud.add_child(skill_label)

	# Ping, top right
	ping_label = _make_label(20)
	ping_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	ping_label.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	ping_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	ping_label.position += Vector2(-16, 14)
	hud.add_child(ping_label)

	_build_scoreboard(hud)

	# Active power-ups, with seconds left
	powerup_label = _make_label(18)
	powerup_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	powerup_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	powerup_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	powerup_label.position.y -= 215
	powerup_label.add_theme_color_override("font_color", Color(1.0, 0.92, 0.55))
	hud.add_child(powerup_label)
	# "+4 Hatred: taunting right under an angel's nose"
	bonus_label = _make_label(18)
	bonus_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	bonus_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bonus_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	bonus_label.position.y -= 185
	bonus_label.add_theme_color_override("font_color", Color(1.0, 0.45, 0.35))
	hud.add_child(bonus_label)
	taunt_label = _make_label(22)
	taunt_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	taunt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	taunt_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	taunt_label.position.y -= 150
	hud.add_child(taunt_label)


const BAR_WIDTH := 260.0


# Hold Tab: both teams, ping and chosen skills.
func _build_scoreboard(hud: CanvasLayer) -> void:
	scoreboard_panel = PanelContainer.new()
	scoreboard_panel.set_anchors_preset(Control.PRESET_CENTER)
	scoreboard_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	scoreboard_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	scoreboard_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	scoreboard_panel.visible = false
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.07, 0.05, 0.11, 0.9)   # dark enough to read over any scene
	bg.set_corner_radius_all(10)
	scoreboard_panel.add_theme_stylebox_override("panel", bg)
	hud.add_child(scoreboard_panel)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 20)
	scoreboard_panel.add_child(margin)
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 12)
	margin.add_child(outer)
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 48)
	outer.add_child(cols)
	_scoreboard_footer = Label.new()
	_scoreboard_footer.add_theme_color_override("font_color", Color(0.75, 0.75, 0.8))
	outer.add_child(_scoreboard_footer)
	for team in ["demon", "angel"]:   # demons on the left, angels on the right
		var box := VBoxContainer.new()
		box.custom_minimum_size.x = 380
		cols.add_child(box)
		var title := Label.new()
		title.add_theme_font_size_override("font_size", 26)
		title.add_theme_color_override("font_color", Color(1.0, 0.88, 0.5) if team == "angel" else Color(1.0, 0.45, 0.4))
		box.add_child(title)
		_scoreboard_titles[team] = title
		var grid := GridContainer.new()
		grid.columns = 3
		grid.add_theme_constant_override("h_separation", 24)
		box.add_child(grid)
		_scoreboard_columns[team] = grid


func _fill_scoreboard() -> void:
	var rows := scoreboard_rows
	if mode == "practice":
		rows = [[name_edit.text if name_edit.text != "" else "You", role, 0, [], false, true, false]]
	for team in ["angel", "demon"]:
		var grid: GridContainer = _scoreboard_columns[team]
		for c in grid.get_children():
			c.queue_free()
		var count := 0
		for header in ["Name", "Ping", "Skills"]:
			var h := Label.new()
			h.text = header
			h.add_theme_color_override("font_color", Color(0.75, 0.75, 0.8))
			grid.add_child(h)
		for row in rows:
			if row[1] != team:
				continue
			count += 1
			var n := Label.new()
			n.text = row[0] + ("  (you)" if row[5] else "") + ("  (host)" if row[6] else "") \
					+ ("  redeemed" if row[4] else "")
			if row[5]:
				n.add_theme_color_override("font_color", Color(0.6, 1.0, 0.7))
			grid.add_child(n)
			var p := Label.new()
			p.text = "-" if row[6] or mode == "practice" else ("%d ms" % row[2] if row[2] >= 0 else "?")
			p.add_theme_color_override("font_color", _ping_color(row[2]))
			grid.add_child(p)
			var sk := Label.new()
			sk.text = ", ".join(row[3]) if not row[3].is_empty() else "none yet"
			grid.add_child(sk)
		_scoreboard_titles[team].text = ("ANGELS" if team == "angel" else "DEMONS") + " (%d)" % count
	var waiting := 0
	for row in rows:
		if row[1] == "":
			waiting += 1
	_scoreboard_footer.text = "%d waiting in the lobby for the next round" % waiting if waiting > 0 else ""
	_scoreboard_footer.visible = waiting > 0


func _skill_line(key: String, id: String) -> String:
	if id == "":
		return "[%s] -" % key
	if Skills.SKILLS[id].get("hold", false):
		return "[Hold %s] %s%s" % [key, Skills.label(id), "   (flying)" if player.flying else ""]
	var cd: float = player.skill_cd.get(id, 0.0)
	return "[%s] %s   %s" % [key, Skills.label(id), "ready" if cd <= 0.0 else "%ds" % ceili(cd)]


func _skill_text() -> String:
	var lo: Array = player.loadout[role]
	if role == "angel":
		var melee := "ready" if player.melee_cd <= 0.0 else "..."
		return "%s\n%s\n[%s] Melee   %s" % [_skill_line(Keybinds.key_name("skill_1"), lo[0]), _skill_line(Keybinds.key_name("rmb"), lo[1]), Keybinds.key_name("melee"), melee]
	var text := "%s\n%s" % [_skill_line(Keybinds.key_name("skill_1"), lo[0]), _skill_line(Keybinds.key_name("rmb"), lo[1])]
	if player.skill_lock > 0.0:
		text += "\nSKILLS LOCKED  %.1fs" % player.skill_lock
	return text


func _ping_color(ms: int) -> Color:
	if ms < 0:
		return Color(0.8, 0.8, 0.8)
	if ms < 90:
		return Color(0.55, 1.0, 0.55)
	if ms < 170:
		return Color(1.0, 0.9, 0.4)
	return Color(1.0, 0.5, 0.4)


func _make_bar(parent: Control, bar_name: String, color: Color) -> void:
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var lbl := _make_label(16)
	lbl.custom_minimum_size.x = 70
	row.add_child(lbl)
	var back := ColorRect.new()
	back.color = Color(0, 0, 0, 0.45)
	back.custom_minimum_size = Vector2(BAR_WIDTH, 14)
	back.size_flags_vertical = Control.SIZE_SHRINK_CENTER   # don't stretch to the label's height
	back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(back)
	var value := _make_label(16)      # optional number to the right of the bar
	value.custom_minimum_size.x = 80
	row.add_child(value)
	var fill := ColorRect.new()
	fill.color = color
	fill.size = Vector2(BAR_WIDTH, 14)
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	back.add_child(fill)
	parent.add_child(row)
	bar_fills[bar_name] = [fill, lbl, value]


func _set_bar(bar_name: String, text: String, fraction: float, color := Color.TRANSPARENT, value := "") -> void:
	bar_fills[bar_name][2].text = value
	var fill: ColorRect = bar_fills[bar_name][0]
	fill.size.x = BAR_WIDTH * clampf(fraction, 0.0, 1.0)
	if color != Color.TRANSPARENT:
		fill.color = color
	bar_fills[bar_name][1].text = text


func _build_tuning_panel() -> void:
	tuning_panel = PanelContainer.new()
	tuning_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	tuning_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	tuning_panel.position += Vector2(-16, 60)
	tuning_panel.visible = false
	hud_layer.add_child(tuning_panel)
	var box := VBoxContainer.new()
	box.custom_minimum_size.x = 340
	tuning_panel.add_child(box)
	var title := Label.new()
	title.text = "Movement tuning (F1 to close)\nApplies to both teams, only on your computer"
	box.add_child(title)
	for row in TUNING_SLIDERS:
		var key: String = row[0]
		var lbl := Label.new()
		box.add_child(lbl)
		var slider := HSlider.new()
		slider.min_value = row[2]
		slider.max_value = row[3]
		slider.step = row[4]
		slider.value = player.tuning[key]
		slider.value_changed.connect(func(v): _on_tuning_changed(key, v))
		box.add_child(slider)
		_tuning_rows[key] = [slider, lbl, row[1]]
		_on_tuning_changed(key, slider.value)
	var reset := Button.new()
	reset.text = "Reset to defaults"
	reset.pressed.connect(_reset_tuning)
	box.add_child(reset)


func _on_tuning_changed(key: String, value: float) -> void:
	if not _tuning_defaults.has(key):
		_tuning_defaults[key] = player.tuning[key]
	player.tuning[key] = value
	var row: Array = _tuning_rows[key]
	row[1].text = "%s: %s" % [row[2], str(snappedf(value, 0.01))]


func _reset_tuning() -> void:
	for key in _tuning_defaults:
		_tuning_rows[key][0].value = _tuning_defaults[key]


func _build_sounds() -> void:
	Sfx.setup_bus()
	var streams := {
		"hit": Sfx.hit_sound(),
		"caught": Sfx.caught_sound(),
		"possess": Sfx.possess_sound(),
		# Cherub Sense alarm: the cherub's little horn fanfare.
		"sense": Sfx.voice([[784, 784, 0.09, 1.0, 0.02], [988, 988, 0.09, 1.0, 0.02], [1175, 1175, 0.22, 1.0, 0.0]], 0.24, 0.0, 0.03, 0.03),
		"powerup": Sfx.voice([[660, 990, 0.12, 0.8, 0.0], [990, 1320, 0.18, 0.7, 0.0]], 0.2, 0.0, 0.02, 0.02),
	}
	for kind in Blessings.names():
		streams["throw_" + kind] = Sfx.throw_sound(kind)
	for sound_name in streams:
		var asp := AudioStreamPlayer.new()
		asp.max_polyphony = 4   # overlapping plays layer instead of cutting off
		asp.stream = streams[sound_name]
		asp.bus = Sfx.BUS
		if sound_name.begins_with("throw_"):
			asp.volume_db = -4.0   # throws happen constantly: keep them in the background
		add_child(asp)
		_sounds[sound_name] = asp


func _play(sound_name: String) -> void:
	var asp: AudioStreamPlayer = _sounds[sound_name]
	# A little random pitch each time so repeated sounds don't feel robotic.
	asp.pitch_scale = randf_range(0.94, 1.06)
	asp.play()


# Our throw hit a demon: ding, and flash a red X on the crosshair.
func _on_hit_confirmed() -> void:
	_play("hit")
	_hitmarker_time = 0.3
	if mode == "practice":
		powerups.angels_made_progress()


func _on_taunted(taunt_name: String) -> void:
	taunt_label.text = "\"%s\"" % Taunts.label(taunt_name)
	_taunt_label_time = 1.5
	if net:
		net.on_local_taunt(taunt_name)


func _toast(text: String, seconds: float) -> void:
	center_label.text = text
	_toast_time = seconds


func _update_hud(delta: float) -> void:
	# Standing at the shrine: say how to use it.
	var at_shrine := (state == State.HIDING or state == State.HUNTING) and near_shrine(player.global_position) \
			and not player.frozen
	if at_shrine and not _was_at_shrine and not shrine_panel.visible:
		_toast("Press %s to swap your skills" % Keybinds.key_name("shrine") + (" (leave your prop first)" if player.possessed_type != "" else ""), 2.5)
	_was_at_shrine = at_shrine
	var want_board := mode != "menu" and Input.is_action_pressed("scoreboard") \
			and not pause_panel.visible and not menu_panel.visible
	if want_board and not scoreboard_panel.visible:
		_fill_scoreboard()
	scoreboard_panel.visible = want_board
	center_label.modulate.a = 0.0 if want_board else 1.0   # don't overlap the roster
	_ping_timer -= delta
	if _ping_timer <= 0.0:
		_ping_timer = 0.5
		if mode == "online" and net:
			if net.is_host:
				ping_label.text = "You're hosting"
				ping_label.remove_theme_color_override("font_color")
			else:
				var ms: int = net.my_ping()
				ping_label.text = "Ping: %s" % ("%d ms" % ms if ms >= 0 else "...")
				ping_label.add_theme_color_override("font_color", _ping_color(ms))
		else:
			ping_label.text = ""
	_toast_time -= delta
	if _toast_time <= 0.0:
		center_label.text = ""
	var in_game := mode != "menu" and state != State.LOBBY
	status_label.visible = in_game
	crosshair.visible = in_game
	controls_label.visible = in_game
	bar_fills["sprint"][0].get_parent().get_parent().get_parent().visible = in_game
	var t := maxi(int(ceil(time_left)), 0)
	var clock := "%d:%02d" % [t / 60, t % 60]
	var phase := "Hiding" if state == State.HIDING else ("Hunting" if state == State.HUNTING else "Round over")
	var side := "ANGEL" if role == "angel" else "DEMON"
	var text := "%s   |   %s  %s" % [side, phase, clock if state != State.ENDED else ""]
	if role == "angel":
		text += "   |   Demons left: %d   |   %s" % [bots_left, Blessings.label(player.blessing)]
	status_label.text = text

	_hurt_time -= delta
	hurt_rect.color.a = clampf(_hurt_time, 0.0, 0.25) * 1.4
	heat_rect.visible = player.burning > 0.0
	if heat_rect.visible:
		(heat_rect.material as ShaderMaterial).set_shader_parameter("strength", clampf(player.burning / Skills.FIRE_LINGER, 0.25, 1.0))
	if player.burning > 0.0:   # standing in demon fire: orange glow at the edges of sight
		hurt_rect.color = Color(1.0, 0.45, 0.05, maxf(hurt_rect.color.a, 0.18 + sin(Time.get_ticks_msec() * 0.02) * 0.05))
	else:
		hurt_rect.color = Color(0.9, 0.05, 0.05, hurt_rect.color.a)

	_hitmarker_time -= delta
	if _hitmarker_time > 0.0:
		crosshair.text = "X"
		crosshair.add_theme_color_override("font_color", Color(1.0, 0.2, 0.15))
		crosshair.add_theme_font_size_override("font_size", 40)
	else:
		crosshair.text = "+"
		crosshair.remove_theme_color_override("font_color")
		crosshair.add_theme_font_size_override("font_size", 28)

	_taunt_label_time -= delta
	if _taunt_label_time <= 0.0:
		taunt_label.text = ""
	_bonus_time -= delta
	bonus_label.modulate.a = clampf(_bonus_time, 0.0, 1.0)
	# Power-ups we have going, and Cherub Sense's alarm around us.
	var active := []
	for k in player.powerups:
		active.append("%s %ds" % [PowerUps.LABELS.get(k, k), int(ceil(player.powerups[k]))])
	powerup_label.text = "   ".join(active)
	_update_sense_bubble(delta)
	skill_label.visible = in_game
	skill_label.text = _skill_text()

	# Health: the bar shows how much is left, the number shows real hit points for
	# the current form (a hay bale has more to lose than a stack of books).
	var health_row: Control = bar_fills["health"][0].get_parent().get_parent()
	health_row.visible = mode == "online" and role == "demon"
	if health_row.visible:
		var max_hp := PropLib.max_hp(player.possessed_type)
		_set_bar("health", "Health", my_health, Color.TRANSPARENT,
				"%d / %d" % [int(ceil(my_health * max_hp)), max_hp])

	var sprint_color := Color(0.85, 0.35, 0.3) if player._sprint_exhausted else Color(0.4, 0.85, 0.45)
	_set_bar("sprint", "Sprint", player.sprint_stamina / player.SPRINT_MAX, sprint_color)
	if role == "angel":
		var low := player.throw_stamina < player.THROW_COST
		_set_bar("power", "Blessing", player.throw_stamina / player.THROW_STAMINA_MAX,
				Color(0.6, 0.5, 0.25) if low else Color(1.0, 0.85, 0.3))
	else:
		_set_bar("power", "Hatred", player.hatred / player.HATRED_MAX, Color(0.8, 0.12, 0.12))

	hold_bar.visible = player.hold_fraction > 0.0
	hold_fill.size.x = 80.0 * player.hold_fraction
	if player.hold_fraction > 0.0:
		hint_label.text = ""
	elif role == "demon" and player.look_target_type != "" and in_game:
		hint_label.text = "Click: possess %s" % PropLib.label(player.look_target_type)
	else:
		hint_label.text = ""
