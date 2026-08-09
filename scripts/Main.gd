extends Node2D
## Errands — the game (Phase 3c: runs on the REAL traced board).
##
## Loads board_map.json (made in BoardEditor.tscn) and plays on it. Native map
## coordinates are scaled down to the window. Highway spaces move like roads
## (the speed comes from their wider spacing). Errand cards are drawn from
## whatever locations you've tagged so far, so you can play a partial trace.
##
## Controls:
##   SPACE ......... roll the dice (your turn) / restart after a win / retry setup
##   Left-click .... after rolling, click a highlighted (yellow) space to move

const BOARD_SIZE := Vector2(6000, 9000)     # native art size (fallback)
const VIEW_SIZE := Vector2(720, 1080)
const MAP_PATH := "res://board_map.json"
const TOKEN_SCALE := 0.13
const WIN_ERRANDS := 3                       # low for testing
const CLICK_RADIUS := 26.0
const ZOOM_MIN := 1.0                        # 1.0 = whole board fits the window
const ZOOM_MAX := 6.0
const PAN_SPEED := 700.0
const STEP_TIME := 0.18                      # seconds per space while animating a move
const TOKEN_ART_ANGLE := PI                  # art faces left, so flip 180° to face travel
const ERRAND_COPIES := 2                     # copies of each single-location errand in the deck

# Which district each location belongs to (used for card colours).
const DISTRICT_OF := {
	"Dance": "mall", "Haircut": "mall", "Hats": "mall", "Jewelry": "mall",
	"Music": "mall", "Pets": "mall", "Shoes": "mall", "Toys": "mall",
	"Bank": "nbhd", "Hardware": "nbhd", "Home": "nbhd", "Park": "nbhd",
	"School": "nbhd", "Worship": "nbhd",
	"Clinic": "dt", "Fair": "dt", "Gas": "dt", "Library": "dt",
	"Museum": "dt", "Offices": "dt", "Pharmacy": "dt", "Police": "dt", "Post Office": "dt",
	"Auto": "ind", "Factory": "ind", "Fast Food": "ind", "Grocery": "ind",
	"Pawn Shop": "ind", "Port": "ind", "Gym": "ind",
	"Beach": "cty", "Camping": "cty", "Farm": "cty", "Forest": "cty",
	"Lake": "cty", "Mountain": "cty",
}

# Duo errand cards: completable at EITHER location, and count as 2.
var DUOS := [
	{ "locations": ["Pharmacy", "Forest"], "flavor": "Buy drugs, or pick your own?" },
	{ "locations": ["Post Office", "Port"], "flavor": "Pick up a package." },
	{ "locations": ["Pawn Shop", "Jewelry"], "flavor": "Buy a gift for your fiancé." },
	{ "locations": ["Gym", "Park"], "flavor": "Get your exercise." },
]

var DISTRICT_COLORS := {
	"mall": Color(0.93, 0.55, 0.12),
	"nbhd": Color(0.80, 0.16, 0.16),
	"dt": Color(0.90, 0.74, 0.10),
	"ind": Color(0.20, 0.36, 0.85),
	"cty": Color(0.16, 0.60, 0.22),
}

var scale_f := 0.12                          # native -> window
var board := {}                              # id -> { pos, kind, name, neighbors }
var home_id := ""
var location_names := []                     # unique errand-location names present

var players := []
var tokens := []
var deck := []
var current := 0
var phase := "SETUP"                         # SETUP | ROLL | MOVE | OVER
var last_roll := 0
var _doubles := false
var destinations := []
var winner := -1
var _note := ""
var _setup_msg := ""

var _board_tex: Texture2D
var _label: Label
var _banner: Label
var _scoreboard: Label
var _camera: Camera2D
var _panning := false
var _animating := false
var _card_layer: CanvasLayer
var _card_row: Control


func _ready() -> void:
	randomize()
	_board_tex = load("res://assets/board.png")
	_setup_camera()
	_build_hud()
	_build_card_bar()
	if not _load_board_map():
		phase = "SETUP"
		_update_hud(); queue_redraw()
		return
	_build_deck()
	if location_names.is_empty():
		phase = "SETUP"
		_setup_msg = "No errand locations tagged yet.\nIn BoardEditor, tag a few locations (Bank, Park…), Save, then press SPACE."
		_update_hud(); queue_redraw()
		return
	_build_players()
	_build_tokens()
	_build_location_labels()
	_update_token_positions()
	phase = "ROLL"
	_update_hud()
	queue_redraw()

# ---------------------------------------------------------------------------
# LOAD MAP
# ---------------------------------------------------------------------------
func _load_board_map() -> bool:
	if not FileAccess.file_exists(MAP_PATH):
		_setup_msg = "No board_map.json yet.\nOpen BoardEditor.tscn, press F6, trace the board, press S to save — then press SPACE here."
		return false
	var f := FileAccess.open(MAP_PATH, FileAccess.READ)
	var data = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(data) != TYPE_DICTIONARY or not data.has("spaces"):
		_setup_msg = "board_map.json could not be read."
		return false

	var native_w := BOARD_SIZE.x
	if data.has("board_size"):
		native_w = float(data["board_size"][0])
	scale_f = VIEW_SIZE.x / native_w

	board.clear()
	home_id = ""
	location_names.clear()
	for id in data["spaces"]:
		var s = data["spaces"][id]
		board[id] = {
			"pos": Vector2(s["x"], s["y"]) * scale_f,
			"kind": s["kind"],
			"name": s["name"],
			"neighbors": [],
		}
		if s["kind"] == "home":
			home_id = id
		elif s["kind"] == "location" and not location_names.has(s["name"]):
			location_names.append(s["name"])
	for e in data["edges"]:
		var a = e[0]
		var b = e[1]
		if board.has(a) and board.has(b):
			board[a]["neighbors"].append(b)
			board[b]["neighbors"].append(a)

	if home_id == "":
		_setup_msg = "No Home tagged.\nIn BoardEditor, select the Home space, press H, Save — then press SPACE."
		return false
	return true


func _build_deck() -> void:
	# A card: { type:"errand", locations:[...], count:int, flavor:String }
	deck.clear()
	for loc in location_names:
		for i in range(ERRAND_COPIES):
			deck.append({ "type": "errand", "locations": [loc], "count": 1, "flavor": "" })
	for duo in DUOS:
		if duo["locations"][0] in location_names and duo["locations"][1] in location_names:
			deck.append({
				"type": "errand",
				"locations": duo["locations"].duplicate(),
				"count": 2,
				"flavor": duo["flavor"],
			})
	deck.shuffle()


func _draw_card() -> Dictionary:
	if deck.is_empty():
		_build_deck()
	return deck.pop_back()


func _build_players() -> void:
	players = [
		{ "name": "Player 1", "tint": Color(1, 1, 1), "space": home_id, "hand": [], "completed": 0 },
		{ "name": "Player 2", "tint": Color(0.45, 0.8, 1.0), "space": home_id, "hand": [], "completed": 0 },
	]
	for p in players:
		for i in range(7):
			p["hand"].append(_draw_card())


func _build_tokens() -> void:
	for i in range(players.size()):
		var spr := Sprite2D.new()
		spr.texture = load("res://assets/player.png")
		spr.scale = Vector2(TOKEN_SCALE, TOKEN_SCALE)
		spr.modulate = players[i]["tint"]
		add_child(spr)
		tokens.append(spr)


func _build_location_labels() -> void:
	for id in board:
		if board[id]["kind"] == "location" or board[id]["kind"] == "home":
			var lb := Label.new()
			lb.text = board[id]["name"]
			lb.add_theme_font_size_override("font_size", 12)
			lb.add_theme_color_override("font_color", Color.WHITE)
			lb.add_theme_color_override("font_outline_color", Color.BLACK)
			lb.add_theme_constant_override("outline_size", 5)
			lb.mouse_filter = Control.MOUSE_FILTER_IGNORE
			lb.position = board[id]["pos"] + Vector2(-16, 8)
			add_child(lb)


func _build_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)

	_label = Label.new()
	_label.add_theme_font_size_override("font_size", 19)
	_label.add_theme_color_override("font_color", Color.WHITE)
	_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_label.add_theme_constant_override("outline_size", 6)
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.position = Vector2(14, 12)
	layer.add_child(_label)

	_banner = Label.new()
	_banner.add_theme_font_size_override("font_size", 30)
	_banner.add_theme_color_override("font_color", Color(1, 0.95, 0.4))
	_banner.add_theme_color_override("font_outline_color", Color.BLACK)
	_banner.add_theme_constant_override("outline_size", 8)
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_banner.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_banner.position = Vector2(40, 0)
	_banner.size = Vector2(VIEW_SIZE.x - 80, VIEW_SIZE.y)
	_banner.visible = false
	layer.add_child(_banner)

	# Always-visible scoreboard (both players) in the top-right.
	_scoreboard = Label.new()
	_scoreboard.add_theme_font_size_override("font_size", 19)
	_scoreboard.add_theme_color_override("font_color", Color.WHITE)
	_scoreboard.add_theme_color_override("font_outline_color", Color.BLACK)
	_scoreboard.add_theme_constant_override("outline_size", 6)
	_scoreboard.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_scoreboard.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_scoreboard.position = Vector2(VIEW_SIZE.x - 264, 12)
	_scoreboard.size = Vector2(250, 80)
	layer.add_child(_scoreboard)


func _setup_camera() -> void:
	_camera = Camera2D.new()
	_camera.zoom = Vector2.ONE          # 1.0 => whole 720x1080 board visible
	_camera.position = VIEW_SIZE * 0.5
	_camera.enabled = true
	add_child(_camera)

# ---------------------------------------------------------------------------
# INPUT
# ---------------------------------------------------------------------------
func _unhandled_input(event: InputEvent) -> void:
	# Camera controls work in every phase.
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			_zoom_by(1.15); return
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			_zoom_by(1.0 / 1.15); return
		elif event.button_index == MOUSE_BUTTON_MIDDLE:
			_panning = event.pressed; return
	elif event is InputEventMouseMotion and _panning:
		_camera.position -= event.relative / _camera.zoom.x
		_clamp_camera(); return

	# Ignore gameplay input while a move is animating.
	if _animating:
		return

	# Gameplay input.
	match phase:
		"SETUP":
			if event.is_action_pressed("ui_accept"):
				get_tree().reload_current_scene()
		"OVER":
			if event.is_action_pressed("ui_accept"):
				_reset_game()
		"ROLL":
			if event.is_action_pressed("ui_accept"):
				_roll()
		"MOVE":
			if event is InputEventMouseButton and event.pressed \
					and event.button_index == MOUSE_BUTTON_LEFT:
				var id := _nearest_destination(get_global_mouse_position())
				if id != "":
					_begin_move(id)


func _process(delta: float) -> void:
	if _camera == null:
		return
	var v := Vector2.ZERO
	if Input.is_key_pressed(KEY_LEFT):  v.x -= 1
	if Input.is_key_pressed(KEY_RIGHT): v.x += 1
	if Input.is_key_pressed(KEY_UP):    v.y -= 1
	if Input.is_key_pressed(KEY_DOWN):  v.y += 1
	if v != Vector2.ZERO:
		_camera.position += v.normalized() * PAN_SPEED * delta / _camera.zoom.x
		_clamp_camera()
	# Keep the active-player indicator glued to the token as it drives.
	if _animating:
		queue_redraw()


func _zoom_by(factor: float) -> void:
	var half: Vector2 = get_viewport_rect().size * 0.5
	var mouse_screen: Vector2 = get_viewport().get_mouse_position()
	var old_zoom: float = _camera.zoom.x
	var new_zoom: float = clampf(old_zoom * factor, ZOOM_MIN, ZOOM_MAX)
	var world_before: Vector2 = _camera.position + (mouse_screen - half) / old_zoom
	var world_after: Vector2 = _camera.position + (mouse_screen - half) / new_zoom
	_camera.zoom = Vector2(new_zoom, new_zoom)
	_camera.position += world_before - world_after
	_clamp_camera()
	queue_redraw()


func _clamp_camera() -> void:
	# Keep the visible area inside the board (no gray void at the edges).
	var half: Vector2 = (VIEW_SIZE * 0.5) / _camera.zoom.x
	_camera.position.x = clampf(_camera.position.x, half.x, VIEW_SIZE.x - half.x)
	_camera.position.y = clampf(_camera.position.y, half.y, VIEW_SIZE.y - half.y)


func _nearest_destination(pos: Vector2) -> String:
	var best := ""
	var best_d := CLICK_RADIUS
	for id in destinations:
		var d: float = board[id]["pos"].distance_to(pos)
		if d <= best_d:
			best_d = d
			best = id
	return best

# ---------------------------------------------------------------------------
# TURN FLOW
# ---------------------------------------------------------------------------
func _roll() -> void:
	_note = ""
	var d1 := randi() % 6 + 1
	var d2 := randi() % 6 + 1
	last_roll = d1 + d2
	_doubles = (d1 == d2)
	destinations = _compute_destinations(players[current]["space"], last_roll).keys()
	if destinations.is_empty():
		_note = "No legal move — turn skipped."
		_end_turn(false)
		return
	phase = "MOVE"
	_update_hud()
	queue_redraw()


func _begin_move(id: String) -> void:
	var path := _find_path(players[current]["space"], id)
	players[current]["space"] = id
	destinations = []
	_animating = true
	_update_hud()
	queue_redraw()

	var tok: Sprite2D = tokens[current]
	if path.size() <= 1:
		tok.position = board[id]["pos"] + Vector2(0, -10)
		_finish_move(id)
		return

	var tw := create_tween()
	for i in range(1, path.size()):
		var frm: Vector2 = board[path[i - 1]]["pos"]
		var to: Vector2 = board[path[i]]["pos"]
		var ang := (to - frm).angle() + TOKEN_ART_ANGLE
		tw.tween_callback(_set_token_rotation.bind(tok, ang))
		tw.tween_property(tok, "position", to + Vector2(0, -10), STEP_TIME)
	tw.tween_callback(_finish_move.bind(id))


func _set_token_rotation(tok: Sprite2D, ang: float) -> void:
	tok.rotation = ang


func _finish_move(id: String) -> void:
	_animating = false
	_update_token_positions()
	_resolve_landing(id)
	if phase == "OVER":
		_update_hud(); queue_redraw()
		return
	_end_turn(_doubles)


# Shortest route from `start` to `dest` that never passes THROUGH another
# location/home (only the destination may be a stop). Used to animate the move.
func _find_path(start: String, dest: String) -> Array:
	var prev := { start: "" }
	var queue := [start]
	while not queue.is_empty():
		var n: String = queue.pop_front()
		if n == dest:
			break
		for nb in board[n]["neighbors"]:
			if prev.has(nb):
				continue
			if _is_stop(nb) and nb != dest:
				continue                 # can't route through a stop
			prev[nb] = n
			queue.append(nb)
	if not prev.has(dest):
		return []
	var path := []
	var cur := dest
	while cur != "":
		path.push_front(cur)
		cur = prev[cur]
	return path


func _resolve_landing(id: String) -> void:
	var p = players[current]
	if board[id]["kind"] == "location":
		var loc: String = board[id]["name"]
		# Complete one hand card whose locations include this spot (Duos match
		# either location and count as 2).
		for i in range(p["hand"].size()):
			var card = p["hand"][i]
			if card["type"] == "errand" and loc in card["locations"]:
				p["hand"].remove_at(i)
				p["completed"] += card["count"]
				p["hand"].append(_draw_card())
				var what: String = " + ".join(card["locations"]) if card["count"] > 1 else loc
				_note = "%s completed: %s  (+%d)" % [p["name"], what, card["count"]]
				break
	if board[id]["kind"] == "home" and p["completed"] >= WIN_ERRANDS:
		phase = "OVER"
		winner = current


func _end_turn(extra_turn: bool) -> void:
	if extra_turn:
		_note = ("Doubles — free turn! " + _note).strip_edges()
	else:
		current = (current + 1) % players.size()
	phase = "ROLL"
	_update_hud()
	queue_redraw()


func _reset_game() -> void:
	_build_deck()
	current = 0
	phase = "ROLL"
	winner = -1
	last_roll = 0
	_doubles = false
	destinations = []
	_note = ""
	for i in range(players.size()):
		players[i]["space"] = home_id
		players[i]["completed"] = 0
		players[i]["hand"] = []
		for j in range(7):
			players[i]["hand"].append(_draw_card())
		tokens[i].rotation = 0.0
	_update_token_positions()
	_update_hud()
	queue_redraw()

# ---------------------------------------------------------------------------
# MOVEMENT GRAPH SEARCH
# ---------------------------------------------------------------------------
func _compute_destinations(start: String, steps: int) -> Dictionary:
	var out := {}
	var visited := {}
	_explore(start, "", steps, out, visited)
	return out


func _explore(node: String, came_from: String, steps_left: int, out: Dictionary, visited: Dictionary) -> void:
	# Memoize on (node, came_from, steps_left) so loops don't cause an
	# exponential blow-up on big, cyclic maps.
	var key: String = node + "|" + came_from + "|" + str(steps_left)
	if visited.has(key):
		return
	visited[key] = true
	for nb in board[node]["neighbors"]:
		if nb == came_from:
			continue
		if _is_stop(nb):
			out[nb] = true
		elif steps_left - 1 <= 0:
			out[nb] = true
		else:
			_explore(nb, node, steps_left - 1, out, visited)


func _is_stop(id: String) -> bool:
	# Locations and Home force a stop. Road and Highway do not.
	return board[id]["kind"] == "location" or board[id]["kind"] == "home"

# ---------------------------------------------------------------------------
# RENDER
# ---------------------------------------------------------------------------
func _draw() -> void:
	draw_texture_rect(_board_tex, Rect2(Vector2.ZERO, VIEW_SIZE), false)

	# Roads.
	var seen := {}
	for a in board:
		for b in board[a]["neighbors"]:
			var key: String = (a + "|" + b) if a < b else (b + "|" + a)
			if seen.has(key):
				continue
			seen[key] = true
			draw_line(board[a]["pos"], board[b]["pos"], Color(0.1, 0.1, 0.1, 0.85), 2.0)

	# Reachable highlights.
	for id in destinations:
		draw_circle(board[id]["pos"], 12.0, Color(1.0, 0.95, 0.2, 0.9))

	# Nodes.
	for id in board:
		var pos: Vector2 = board[id]["pos"]
		match board[id]["kind"]:
			"home":
				draw_circle(pos, 8.0, Color(0.1, 0.7, 0.2))
			"location":
				draw_circle(pos, 7.0, Color(0.2, 0.4, 0.9))
			"highway":
				draw_circle(pos, 6.0, Color(0.95, 0.55, 0.1))
			_:
				draw_circle(pos, 4.0, Color(0.85, 0.85, 0.85))

	# Mark whose turn it is.
	if phase != "SETUP" and phase != "OVER" and not tokens.is_empty():
		_draw_active_indicator(tokens[current].position)

	if phase == "OVER":
		draw_rect(Rect2(Vector2.ZERO, VIEW_SIZE), Color(0, 0, 0, 0.55))


func _draw_active_indicator(pos: Vector2) -> void:
	# Ring around the active token.
	draw_arc(pos, 20.0, 0, TAU, 32, Color(0, 0, 0, 0.7), 5.0)
	draw_arc(pos, 20.0, 0, TAU, 32, Color(1, 1, 1, 0.95), 2.5)
	# Chevron pointing down at it.
	var c := pos + Vector2(0, -30)
	var back := PackedVector2Array([c + Vector2(-12, -12), c + Vector2(12, -12), c + Vector2(0, 6)])
	var tri := PackedVector2Array([c + Vector2(-9, -9), c + Vector2(9, -9), c + Vector2(0, 3)])
	draw_colored_polygon(back, Color(0, 0, 0, 0.8))
	draw_colored_polygon(tri, Color(1, 0.85, 0.1))


func _update_token_positions() -> void:
	if tokens.is_empty():
		return
	var by_space := {}
	for i in range(players.size()):
		var s: String = players[i]["space"]
		if not by_space.has(s):
			by_space[s] = []
		by_space[s].append(i)
	for s in by_space:
		var occ: Array = by_space[s]
		var base: Vector2 = board[s]["pos"]
		for j in range(occ.size()):
			var off := Vector2.ZERO
			if occ.size() > 1:
				off.x = (j - (occ.size() - 1) / 2.0) * 18.0
			tokens[occ[j]].position = base + off + Vector2(0, -10)


func _update_hud() -> void:
	var lines := []
	_update_scoreboard()
	if phase == "SETUP":
		_banner.visible = true
		_banner.text = _setup_msg
		_label.text = "Errands — setup needed"
		_refresh_card_bar()
		return
	if not _note.is_empty():
		lines.append(_note)
	if phase == "OVER":
		_banner.visible = true
		_banner.text = "🎉  %s WINS!  🎉\n\nPress SPACE to play again" % players[winner]["name"]
		lines.append("%s wins!" % players[winner]["name"])
	else:
		_banner.visible = false
		var p = players[current]
		lines.append("%s   —   Errands %d / %d" % [p["name"], p["completed"], WIN_ERRANDS])
		if p["completed"] >= WIN_ERRANDS:
			lines.append("Enough errands — return HOME to win!")
		if phase == "ROLL":
			lines.append("Press SPACE to roll")
		else:
			lines.append("Rolled %d — click a yellow space to move" % last_roll)
		lines.append("(wheel: zoom · middle-drag / arrows: pan)")
	_label.text = "\n".join(lines)
	_refresh_card_bar()


func _update_scoreboard() -> void:
	if _scoreboard == null:
		return
	if players.is_empty():
		_scoreboard.text = ""
		return
	var rows := []
	for i in range(players.size()):
		var mark := "▶ " if (i == current and phase != "OVER") else "    "
		rows.append("%s%s: %d / %d" % [mark, players[i]["name"], players[i]["completed"], WIN_ERRANDS])
	_scoreboard.text = "\n".join(rows)

# ---------------------------------------------------------------------------
# CARD HAND (visual)
# ---------------------------------------------------------------------------
const CARD_W := 84.0
const CARD_H := 116.0
const CARD_GAP := 6.0

func _build_card_bar() -> void:
	_card_layer = CanvasLayer.new()
	add_child(_card_layer)
	_card_row = Control.new()
	_card_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card_layer.add_child(_card_row)


func _refresh_card_bar() -> void:
	if _card_row == null:
		return
	for child in _card_row.get_children():
		child.queue_free()
	if players.is_empty() or phase == "SETUP" or phase == "OVER":
		return
	var hand: Array = players[current]["hand"]
	if hand.is_empty():
		return
	var total := hand.size() * CARD_W + (hand.size() - 1) * CARD_GAP
	var start_x := (VIEW_SIZE.x - total) * 0.5
	var y := VIEW_SIZE.y - CARD_H - 8.0
	for i in range(hand.size()):
		var node := _make_card_node(hand[i])
		node.position = Vector2(start_x + i * (CARD_W + CARD_GAP), y)
		_card_row.add_child(node)


func _make_card_node(card: Dictionary) -> Control:
	var panel := Panel.new()
	panel.size = Vector2(CARD_W, CARD_H)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.97, 0.95, 0.90)
	sb.set_corner_radius_all(6)
	sb.set_border_width_all(2)
	sb.border_color = Color(0.15, 0.15, 0.15)
	panel.add_theme_stylebox_override("panel", sb)

	# District colour strip.
	var header := ColorRect.new()
	header.color = _district_color(card["locations"][0])
	header.position = Vector2(4, 4)
	header.size = Vector2(CARD_W - 8, 18)
	header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(header)

	# Location name(s).
	var name_lbl := Label.new()
	if card["count"] > 1:
		name_lbl.text = card["locations"][0] + "\n+\n" + card["locations"][1]
	else:
		name_lbl.text = card["locations"][0]
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	name_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_lbl.add_theme_font_size_override("font_size", 12)
	name_lbl.add_theme_color_override("font_color", Color(0.1, 0.1, 0.1))
	name_lbl.position = Vector2(4, 24)
	name_lbl.size = Vector2(CARD_W - 8, CARD_H - 28)
	name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(name_lbl)

	# "x2" badge for Duos.
	if card["count"] > 1:
		var badge := Label.new()
		badge.text = "×2"
		badge.add_theme_font_size_override("font_size", 13)
		badge.add_theme_color_override("font_color", Color.WHITE)
		badge.add_theme_color_override("font_outline_color", Color.BLACK)
		badge.add_theme_constant_override("outline_size", 4)
		badge.position = Vector2(CARD_W - 24, 2)
		badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		panel.add_child(badge)

	return panel


func _district_color(loc: String) -> Color:
	var d: String = DISTRICT_OF.get(loc, "")
	return DISTRICT_COLORS.get(d, Color(0.5, 0.5, 0.5))
