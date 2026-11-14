# Built-in updater. Asks GitHub whether a newer release exists and, when the
# player clicks the menu button, downloads it, swaps it in for the running game
# file and restarts.
#
# How the swap works: a running program can't be overwritten, but it can be
# renamed. So the game renames itself to "<name>.old", moves the download into
# its place, starts it and quits. The new copy deletes the ".old" file.
#
# Only exported Windows and Linux builds update themselves. Run from the Godot
# editor (or from source) this does nothing.
extends Node

signal changed   # state, button_text or note changed: the menu redraws its update row

const REPO := "theobigdog/Halos_and_Horns"
const API_URL := "https://api.github.com/repos/" + REPO + "/releases/latest"
const DOWNLOAD_PREFIX := "https://github.com/" + REPO + "/releases/download/"
const PAGE_URL := "https://github.com/" + REPO + "/releases/latest"
# The file each platform downloads (the names release-builds.yml attaches).
const ASSETS := {"Windows": "HalosAndHorns.exe", "Linux": "HalosAndHorns.x86_64"}
const AGENT := "User-Agent: HalosAndHorns-updater"

var state := "idle"     # idle, available, downloading, failed, restarting
var button_text := ""   # what the menu's update button says
var note := ""          # a line under it (why something failed)
var latest := ""        # the newer version's number, e.g. "0.4.1"

var _exe := ""          # the running game file
var _url := ""
var _size := 0
var _sha256 := ""
var _download: HTTPRequest
var _percent := -1
var _testing := false   # a test pointed us at a stand-in for GitHub
var _auto := false      # a test asked us to install without a click


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


func _show(new_state: String, new_button: String, new_note := "") -> void:
	state = new_state
	button_text = new_button
	note = new_note
	changed.emit()


# Called once at startup with the running game's version.
func check(current_version: String) -> void:
	if not OS.has_feature("template") or not ASSETS.has(OS.get_name()):
		return
	if version_numbers(current_version).is_empty():
		return   # a "dev" build made by hand: there's no telling what's newer than it
	_exe = OS.get_executable_path()
	_remove_leftovers()
	var api := API_URL
	# Automated testing (debug builds only):
	#   game -- --update-api=http://127.0.0.1:8000/latest.json --update-auto
	if OS.is_debug_build():
		for a in OS.get_cmdline_user_args():
			if a.begins_with("--update-api="):
				api = a.trim_prefix("--update-api=")
				_testing = true
			elif a == "--update-auto":
				_auto = true
	var req := HTTPRequest.new()
	req.timeout = 15
	add_child(req)
	req.request_completed.connect(func(result, code, _headers, body):
		req.queue_free()
		if result == HTTPRequest.RESULT_SUCCESS and code == 200:
			_read_release(body.get_string_from_utf8(), current_version))
	req.request(api, ["Accept: application/vnd.github+json", AGENT])


# The last update's ".old" file. Right after an update the old game may still be
# closing (Windows won't delete it until then), so try again a little later.
func _remove_leftovers() -> void:
	var old := _exe + ".old"
	if FileAccess.file_exists(old) and DirAccess.remove_absolute(old) != OK:
		get_tree().create_timer(5.0).timeout.connect(func(): DirAccess.remove_absolute(old))


func _read_release(json: String, current_version: String) -> void:
	var release = JSON.parse_string(json)
	if not release is Dictionary or not is_newer(str(release.get("tag_name", "")), current_version):
		return
	# A release exists a few minutes before its builds are attached; until our
	# file is there, there's nothing to update to.
	for asset in release.get("assets", []):
		if asset is Dictionary and asset.get("name", "") == ASSETS[OS.get_name()]:
			_url = str(asset.get("browser_download_url", ""))
			_size = int(asset.get("size", 0))
			_sha256 = str(asset.get("digest", "")).trim_prefix("sha256:")
	if not _url.begins_with(DOWNLOAD_PREFIX) and not _testing:
		return
	latest = ".".join(version_numbers(release["tag_name"]).map(func(n): return str(n)))
	_show("available", "Update to version %s" % latest)
	print("[updater] version %s is available" % latest)
	if _auto:
		install()


# The menu's update button.
func install() -> void:
	if state == "failed":
		OS.shell_open(PAGE_URL)
		return
	if state != "available":
		return
	var incoming := _exe + ".new"
	var probe := FileAccess.open(incoming, FileAccess.WRITE)
	if probe == null:
		_fail("The game can't write to its own folder.")
		return
	probe.close()
	_download = HTTPRequest.new()
	_download.download_file = incoming
	_download.use_threads = true
	add_child(_download)
	_download.request_completed.connect(_on_downloaded)
	if _download.request(_url, [AGENT]) != OK:
		_fail("The download couldn't start.")
		return
	_percent = -1
	_show("downloading", "Downloading the update...")


func _process(_delta: float) -> void:
	if state != "downloading" or _size <= 0:
		return
	var percent := int(100.0 * _download.get_downloaded_bytes() / _size)
	if percent != _percent:
		_percent = percent
		_show("downloading", "Downloading the update... %d%%" % clampi(percent, 0, 100))


func _fail(reason: String) -> void:
	if _download:
		_download.queue_free()
		_download = null
	DirAccess.remove_absolute(_exe + ".new")
	print("[updater] failed: " + reason)
	_show("failed", "Open the download page", reason + " You can get version %s from the download page instead." % latest)


func _on_downloaded(result: int, code: int, _headers: PackedStringArray, _body: PackedByteArray) -> void:
	_download.queue_free()
	_download = null
	var incoming := _exe + ".new"
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		_fail("The download didn't finish.")
		return
	# Make sure the file is exactly the one GitHub lists before running it.
	var file := FileAccess.open(incoming, FileAccess.READ)
	var size := file.get_length() if file else -1
	if file:
		file.close()
	if size != _size or (_sha256 != "" and FileAccess.get_sha256(incoming) != _sha256):
		_fail("The downloaded file was damaged.")
		return
	var old := _exe + ".old"
	DirAccess.remove_absolute(old)
	if DirAccess.rename_absolute(_exe, old) != OK:
		_fail("The game file couldn't be replaced.")
		return
	if DirAccess.rename_absolute(incoming, _exe) != OK:
		DirAccess.rename_absolute(old, _exe)
		_fail("The game file couldn't be replaced.")
		return
	if OS.get_name() == "Linux":
		FileAccess.set_unix_permissions(_exe, 493)   # rwxr-xr-x: mark it as a program
	print("[updater] installed version %s, restarting" % latest)
	if OS.create_process(_exe, _restart_args()) == -1:
		_show("restarting", "Updated", "Version %s is installed. Close the game and start it again." % latest)
		return
	_show("restarting", "Restarting...")
	get_tree().quit()


# Start the new version the way this one was started. Godot doesn't hand back
# the options it used itself, so the one that matters (no window) is put back.
func _restart_args() -> PackedStringArray:
	var args := OS.get_cmdline_args()
	if DisplayServer.get_name() == "headless" and not args.has("--headless"):
		args.append("--headless")
	var user_args := OS.get_cmdline_user_args()
	if not user_args.is_empty() and not args.has("--"):
		args.append("--")
		args.append_array(user_args)
	return args
