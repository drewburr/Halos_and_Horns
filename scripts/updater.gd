# New-version notice. At startup it asks GitHub whether a newer release exists,
# and if so the main menu shows a button that opens the download page in the
# player's browser. That's all: it never downloads, replaces or runs anything.
# (It used to install updates itself; that was taken out in 0.5.3 until updates
# can be properly signed.)
#
# Only exported Windows and Linux builds check. Run from the Godot editor (or
# from source) this does nothing.
extends Node

signal changed   # state, button_text or note changed: the menu redraws its update row

const REPO := "theobigdog/Halos_and_Horns"
const API_URL := "https://api.github.com/repos/" + REPO + "/releases/latest"
const PAGE_URL := "https://github.com/" + REPO + "/releases/latest"
const AGENT := "User-Agent: HalosAndHorns-version-check"

var state := "idle"     # idle, available
var button_text := ""   # what the menu's update button says
var note := ""          # a line under it
var latest := ""        # the newer version's number, e.g. "0.4.1"

var _testing := false   # a test pointed us at a stand-in for GitHub


# "v0.4.1" or "0.4.1 (Hellfire)" -> [0, 4, 1]
static func version_numbers(version: String) -> Array:
	var found := RegEx.create_from_string("\\d+(\\.\\d+)*").search(version)
	var numbers := []
	if found:
		for part in found.get_string().split("."):
			numbers.append(int(part))
	return numbers


static func is_newer(candidate: String, current: String) -> bool:
	var a := version_numbers(candidate)
	var b := version_numbers(current)
	for i in max(a.size(), b.size()):
		var x: int = a[i] if i < a.size() else 0
		var y: int = b[i] if i < b.size() else 0
		if x != y:
			return x > y
	return false


# Called once at startup with the running game's version.
func check(current_version: String) -> void:
	if not OS.has_feature("template") or not OS.get_name() in ["Windows", "Linux"]:
		return
	if version_numbers(current_version).is_empty():
		return   # a "dev" build made by hand: there's no telling what's newer than it
	_remove_leftovers()
	var api := API_URL
	# Automated testing (debug builds only):  game -- --update-api=http://127.0.0.1:8000/latest.json
	if OS.is_debug_build():
		for a in OS.get_cmdline_user_args():
			if a.begins_with("--update-api="):
				api = a.trim_prefix("--update-api=")
				_testing = true
	var req := HTTPRequest.new()
	req.timeout = 15
	add_child(req)
	req.request_completed.connect(func(result, code, _headers, body):
		req.queue_free()
		if result == HTTPRequest.RESULT_SUCCESS and code == 200:
			_read_release(body.get_string_from_utf8(), current_version))
	req.request(api, ["Accept: application/vnd.github+json", AGENT])


# Versions 0.4-0.5.2 updated themselves and could leave a "<game>.old" file behind.
func _remove_leftovers() -> void:
	var old := OS.get_executable_path() + ".old"
	if FileAccess.file_exists(old):
		DirAccess.remove_absolute(old)


func _read_release(json: String, current_version: String) -> void:
	var release = JSON.parse_string(json)
	if not release is Dictionary or not is_newer(str(release.get("tag_name", "")), current_version):
		return
	latest = ".".join(version_numbers(str(release["tag_name"])).map(func(n): return str(n)))
	state = "available"
	button_text = "Version %s is out: open the download page" % latest
	note = ""
	changed.emit()
	print("[updater] version %s is available" % latest)
	if _testing and "--update-click" in OS.get_cmdline_user_args():
		install()


# The menu's button: open the releases page in the browser. Always the fixed
# GitHub address, never anything the release info says.
func install() -> void:
	if state != "available":
		return
	print("[updater] opening the download page")
	if not _testing:
		OS.shell_open(PAGE_URL)
	note = "Download it there, then replace this game file with the new one."
	changed.emit()
