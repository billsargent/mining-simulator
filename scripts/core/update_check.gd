extends Node
## Asks GitHub once, at start, whether a newer release is out. Normal play only (main skips it when
## any command-line flag is given) and only when Settings.check_updates is on. Sends nothing but a
## plain GET with a generic User-Agent; any failure (offline, rate limit, bad reply) stays silent.

const URL := "https://api.github.com/repos/billsargent/mining-simulator/releases?per_page=1"
const RELEASES_PAGE := "https://github.com/billsargent/mining-simulator/releases"

signal found(tag: String, url: String)

var _http: HTTPRequest


## The running game's version, from project.godot (stamped from the tag by the Build workflow).
static func current() -> String:
	return str(ProjectSettings.get_setting("application/config/version", "0"))


## Parses "v1.2.3" / "1.2" / "v0.10-beta" into a list of ints (non-digit tails ignored).
static func _parts(v: String) -> Array:
	var s := v.strip_edges().trim_prefix("v").trim_prefix("V")
	var dash := s.find("-")
	if dash >= 0:
		s = s.substr(0, dash)
	var out := []
	for p in s.split("."):
		out.append(int(p) if p.is_valid_int() else 0)
	return out


## True when version `a` is newer than `b` ("v0.10" is newer than "0.9").
static func is_newer(a: String, b: String) -> bool:
	var pa := _parts(a)
	var pb := _parts(b)
	for i in maxi(pa.size(), pb.size()):
		var x: int = pa[i] if i < pa.size() else 0
		var y: int = pb[i] if i < pb.size() else 0
		if x != y:
			return x > y
	return false


func start() -> void:
	_http = HTTPRequest.new()
	_http.timeout = 10.0
	add_child(_http)
	_http.request_completed.connect(_done)
	if _http.request(URL, ["User-Agent: Paystreak-game", "Accept: application/vnd.github+json"]) != OK:
		_http.queue_free()


func _done(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	_http.queue_free()
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		return
	var data = JSON.parse_string(body.get_string_from_utf8())
	if not (data is Array) or data.is_empty() or not (data[0] is Dictionary):
		return
	var tag := str(data[0].get("tag_name", ""))
	var page := str(data[0].get("html_url", RELEASES_PAGE))
	if not page.begins_with("https://github.com/"):
		page = RELEASES_PAGE
	if tag != "" and is_newer(tag, current()):
		found.emit(tag, page)
