extends Node2D
## Errands — Board Tracer (Phase 3, steps 3a + 3b).
##
## Traces your maze into a movement graph the game can navigate, working on the
## FULL 6000x9000 board with pan + zoom. Saves to res://board_map.json.
##
## TWO MODES (shown top-left; switch with keys 1 / 2):
##   [1] ROAD mode — lay the road network
##       Left-click empty ...... drop a road space, chained to the last one
##       Left-click a dot ...... connect the chain into it (junctions / loops)
##       Right-click ........... break the chain (start a separate road)
##   [2] TAG mode — label dots as locations
##       Pick a name in the palette (right side), then left-click a dot to label it
##
## ALWAYS AVAILABLE:
##   Middle-drag / arrows ... pan      Mouse wheel ... zoom toward cursor
##   Del / Backspace ........ delete the selected dot
##   H ...................... mark the selected dot as Home
##   P ...................... show / hide the location palette
##   S ...................... SAVE the map to board_map.json
##
## Run this scene directly with F6 (Run Current Scene).

const BOARD_SIZE := Vector2(6000, 9000)
const MAP_PATH := "res://board_map.json"
const ZOOM_MIN := 0.09
const ZOOM_MAX := 2.0
const PAN_SPEED := 900.0
const PANEL_X := 528.0

const LOCATION_NAMES := [
	"Auto", "Bank", "Beach", "Camping", "Clinic", "Dance", "Factory", "Fair",
	"Farm", "Fast Food", "Forest", "Gas", "Grocery", "Gym", "Haircut", "Hardware",
	"Hats", "Jewelry", "Lake", "Library", "Mountain", "Museum", "Music", "Offices",
	"Park", "Pawn Shop", "Pets", "Pharmacy", "Police", "Port", "Post Office",
	"School", "Shoes", "Toys", "Worship",
]

var spaces := {}                # id -> { pos:Vector2, kind:String, name:String }
var adj := {}                   # id -> Array[String]
var _id_counter := 0
var _last := ""                 # end of the current chain
var _selected := ""

var _mode := "road"             # "road" | "tag"
var _armed_name := ""           # location name armed from the palette

var _board_tex: Texture2D
var _camera: Camera2D
var _panning := false
var _font: Font

var _label: Label
var _palette: ItemList
var _palette_bg: ColorRect
var _palette_names := []         # index -> name ("Home", "__road__", or a location)
var _status := ""


func _ready() -> void:
	_board_tex = load("res://assets/board.png")
	_font = ThemeDB.fallback_font
	_setup_camera()
	_build_hud()
	_load_map()
	_refresh_palette()
	_update_hud()
	queue_redraw()


func _setup_camera() -> void:
	_camera = Camera2D.new()
	var fit_zoom: float = get_viewport_rect().size.y / BOARD_SIZE.y
	_camera.zoom = Vector2(fit_zoom, fit_zoom)
	_camera.position = BOARD_SIZE * 0.5
	_camera.enabled = true
	add_child(_camera)


func _build_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)

	_label = Label.new()
	_label.add_theme_font_size_override("font_size", 16)
	_label.add_theme_color_override("font_color", Color.WHITE)
	_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_label.add_theme_constant_override("outline_size", 5)
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.position = Vector2(12, 10)
	layer.add_child(_label)

	_palette_bg = ColorRect.new()
	_palette_bg.color = Color(0, 0, 0, 0.55)
	_palette_bg.position = Vector2(PANEL_X - 6, 150)
	_palette_bg.size = Vector2(198, 912)
	_palette_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_palette_bg)

	_palette = ItemList.new()
	_palette.position = Vector2(PANEL_X, 156)
	_palette.size = Vector2(186, 900)
	_palette.add_theme_font_size_override("font_size", 14)
	_palette.item_selected.connect(_on_palette_selected)
	layer.add_child(_palette)

	_palette_names.clear()
	_palette.clear()
	_add_palette_item("Home")
	_add_palette_item("__road__")
	_add_palette_item("__highway__")
	for n in LOCATION_NAMES:
		_add_palette_item(n)


func _add_palette_item(name_key: String) -> void:
	_palette_names.append(name_key)
	_palette.add_item(_palette_label(name_key))

# ---------------------------------------------------------------------------
# INPUT
# ---------------------------------------------------------------------------
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		match event.button_index:
			MOUSE_BUTTON_LEFT:
				if event.pressed:
					if _mode == "tag":
						_tag_at(get_global_mouse_position())
					else:
						_road_click(get_global_mouse_position())
			MOUSE_BUTTON_RIGHT:
				if event.pressed and _mode == "road":
					_last = ""
					_update_hud()
					queue_redraw()
			MOUSE_BUTTON_MIDDLE:
				_panning = event.pressed
			MOUSE_BUTTON_WHEEL_UP:
				if event.pressed:
					_zoom_by(1.15)
			MOUSE_BUTTON_WHEEL_DOWN:
				if event.pressed:
					_zoom_by(1.0 / 1.15)
	elif event is InputEventMouseMotion and _panning:
		_camera.position -= event.relative / _camera.zoom.x
	elif event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_1:
				_mode = "road"; _update_hud()
			KEY_2:
				_mode = "tag"; _update_hud()
			KEY_P:
				_palette.visible = not _palette.visible
				_palette_bg.visible = _palette.visible
			KEY_S:
				_save_map()
			KEY_DELETE, KEY_BACKSPACE:
				_delete_selected()
			KEY_H:
				_set_home(_selected)


func _process(delta: float) -> void:
	var v := Vector2.ZERO
	if Input.is_key_pressed(KEY_LEFT):  v.x -= 1
	if Input.is_key_pressed(KEY_RIGHT): v.x += 1
	if Input.is_key_pressed(KEY_UP):    v.y -= 1
	if Input.is_key_pressed(KEY_DOWN):  v.y += 1
	if v != Vector2.ZERO:
		_camera.position += v.normalized() * PAN_SPEED * delta / _camera.zoom.x


func _zoom_by(factor: float) -> void:
	# world = position + (screen - viewport/2) / zoom  (Camera2D centered anchor)
	var half: Vector2 = get_viewport_rect().size * 0.5
	var mouse_screen: Vector2 = get_viewport().get_mouse_position()
	var old_zoom: float = _camera.zoom.x
	var new_zoom: float = clampf(old_zoom * factor, ZOOM_MIN, ZOOM_MAX)
	var world_before: Vector2 = _camera.position + (mouse_screen - half) / old_zoom
	var world_after: Vector2 = _camera.position + (mouse_screen - half) / new_zoom
	_camera.zoom = Vector2(new_zoom, new_zoom)
	_camera.position += world_before - world_after
	_update_hud()
	queue_redraw()

# ---------------------------------------------------------------------------
# ROAD MODE
# ---------------------------------------------------------------------------
func _road_click(world: Vector2) -> void:
	var target := _nearest_space(world)
	if target == "":
		target = _new_id()
		spaces[target] = { "pos": world, "kind": "road", "name": "" }
		adj[target] = []
	if _last != "" and _last != target:
		_add_edge(_last, target)
	_last = target
	_selected = target
	_update_hud()
	queue_redraw()


func _nearest_space(world: Vector2) -> String:
	var reach: float = 18.0 / _camera.zoom.x
	var best := ""
	var best_d := INF
	for id in spaces:
		var d: float = spaces[id]["pos"].distance_to(world)
		if d < best_d:
			best_d = d
			best = id
	return best if best_d <= reach else ""


func _new_id() -> String:
	_id_counter += 1
	return "s" + str(_id_counter)


func _add_edge(a: String, b: String) -> void:
	if not adj.has(a): adj[a] = []
	if not adj.has(b): adj[b] = []
	if b not in adj[a]: adj[a].append(b)
	if a not in adj[b]: adj[b].append(a)


func _delete_selected() -> void:
	if _selected == "":
		return
	for b in adj.get(_selected, []):
		adj[b].erase(_selected)
	adj.erase(_selected)
	spaces.erase(_selected)
	if _last == _selected:
		_last = ""
	_selected = ""
	_refresh_palette()
	_update_hud()
	queue_redraw()

# ---------------------------------------------------------------------------
# TAG MODE
# ---------------------------------------------------------------------------
func _tag_at(world: Vector2) -> void:
	var target := _nearest_space(world)
	if target == "" or _armed_name == "":
		return
	if _armed_name == "__road__":
		spaces[target]["kind"] = "road"
		spaces[target]["name"] = ""
	elif _armed_name == "__highway__":
		spaces[target]["kind"] = "highway"
		spaces[target]["name"] = ""
	elif _armed_name == "Home":
		_set_home(target)
		return
	else:
		spaces[target]["kind"] = "location"
		spaces[target]["name"] = _armed_name
	_selected = target
	_refresh_palette()
	_update_hud()
	queue_redraw()


func _set_home(target: String) -> void:
	if target == "":
		return
	for id in spaces:                       # only one Home allowed
		if spaces[id]["kind"] == "home":
			spaces[id]["kind"] = "road"
			spaces[id]["name"] = ""
	spaces[target]["kind"] = "home"
	spaces[target]["name"] = "Home"
	_selected = target
	_refresh_palette()
	_update_hud()
	queue_redraw()


func _on_palette_selected(index: int) -> void:
	_armed_name = _palette_names[index]
	_mode = "tag"
	_update_hud()


func _palette_label(name_key: String) -> String:
	if name_key == "__road__":
		return "— set to road —"
	if name_key == "__highway__":
		return "— set to Highway —"
	var text := name_key
	if _is_placed(name_key):
		text = "* " + text
	return text


func _is_placed(name_key: String) -> bool:
	for id in spaces:
		if spaces[id]["name"] == name_key and spaces[id]["kind"] != "road":
			return true
	return false


func _refresh_palette() -> void:
	for i in range(_palette_names.size()):
		_palette.set_item_text(i, _palette_label(_palette_names[i]))

# ---------------------------------------------------------------------------
# SAVE / LOAD
# ---------------------------------------------------------------------------
func _save_map() -> void:
	var out := { "version": 1, "board_size": [int(BOARD_SIZE.x), int(BOARD_SIZE.y)],
			"spaces": {}, "edges": [] }
	for id in spaces:
		out["spaces"][id] = {
			"x": int(round(spaces[id]["pos"].x)),
			"y": int(round(spaces[id]["pos"].y)),
			"kind": spaces[id]["kind"],
			"name": spaces[id]["name"],
		}
	var seen := {}
	for a in adj:
		for b in adj[a]:
			var key: String = (a + "|" + b) if a < b else (b + "|" + a)
			if seen.has(key):
				continue
			seen[key] = true
			out["edges"].append([a, b])
	var f := FileAccess.open(MAP_PATH, FileAccess.WRITE)
	if f == null:
		_status = "SAVE FAILED (could not open file)"
		_update_hud()
		return
	f.store_string(JSON.stringify(out, "  "))
	f.close()
	_status = "Saved %d spaces / %d roads" % [spaces.size(), out["edges"].size()]
	_update_hud()


func _load_map() -> void:
	if not FileAccess.file_exists(MAP_PATH):
		_status = "New map (no board_map.json yet)"
		return
	var f := FileAccess.open(MAP_PATH, FileAccess.READ)
	var data = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(data) != TYPE_DICTIONARY:
		_status = "Could not read board_map.json"
		return
	spaces.clear()
	adj.clear()
	for id in data["spaces"]:
		var s = data["spaces"][id]
		spaces[id] = { "pos": Vector2(s["x"], s["y"]), "kind": s["kind"], "name": s["name"] }
		adj[id] = []
	for e in data["edges"]:
		_add_edge(e[0], e[1])
	_id_counter = 0
	for id in spaces:
		_id_counter = max(_id_counter, int(id.substr(1)))
	_status = "Loaded %d spaces" % spaces.size()

# ---------------------------------------------------------------------------
# RENDER
# ---------------------------------------------------------------------------
func _sw(px: float) -> float:
	return px / _camera.zoom.x


func _draw() -> void:
	draw_texture_rect(_board_tex, Rect2(Vector2.ZERO, BOARD_SIZE), false)

	var seen := {}
	for a in adj:
		for b in adj[a]:
			var key: String = (a + "|" + b) if a < b else (b + "|" + a)
			if seen.has(key):
				continue
			seen[key] = true
			draw_line(spaces[a]["pos"], spaces[b]["pos"], Color(0.1, 0.1, 0.1, 0.9), _sw(2.5))

	for id in spaces:
		var pos: Vector2 = spaces[id]["pos"]
		var r := _sw(8.0)
		var col := Color(0.85, 0.85, 0.85)
		match spaces[id]["kind"]:
			"home":
				r = _sw(11.0); col = Color(0.1, 0.7, 0.2)
			"location":
				r = _sw(10.0); col = Color(0.2, 0.4, 0.9)
			"highway":
				r = _sw(9.0); col = Color(0.95, 0.55, 0.1)
		draw_circle(pos, r, col)
		if spaces[id]["kind"] != "road":
			_draw_label(spaces[id]["name"], pos + Vector2(_sw(12.0), _sw(4.0)))

	if _selected != "" and spaces.has(_selected):
		draw_arc(spaces[_selected]["pos"], _sw(13.0), 0, TAU, 28, Color.WHITE, _sw(2.5))
	if _mode == "road" and _last != "" and spaces.has(_last):
		draw_arc(spaces[_last]["pos"], _sw(17.0), 0, TAU, 28, Color(1, 0.9, 0.2), _sw(2.0))


func _draw_label(text: String, pos: Vector2) -> void:
	var fs := int(max(9.0, _sw(15.0)))
	draw_string_outline(_font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, int(_sw(3.0)), Color.BLACK)
	draw_string(_font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.WHITE)


func _update_hud() -> void:
	var edges := 0
	for a in adj:
		edges += adj[a].size()
	edges = edges / 2
	var mode_txt := ""
	if _mode == "road":
		mode_txt = "[1] ROAD — draw the road network"
	else:
		var armed := "(pick a name in the palette)"
		if _armed_name == "__road__":
			armed = "road (erase)"
		elif _armed_name == "__highway__":
			armed = "Highway"
		elif _armed_name != "":
			armed = _armed_name
		mode_txt = "[2] TAG — armed: " + armed
	var lines := [
		"ERRANDS — Board Tracer (3b)     MODE: %s" % mode_txt,
		"Spaces: %d   Roads: %d   Zoom: %d%%" % [spaces.size(), edges, round(_camera.zoom.x * 100)],
		"1/2: switch mode   ·   wheel: zoom   ·   middle-drag/arrows: pan   ·   P: palette",
		"Del: delete selected   ·   H: mark Home   ·   S: SAVE",
	]
	if not _status.is_empty():
		lines.append("→ " + _status)
	_label.text = "\n".join(lines)
