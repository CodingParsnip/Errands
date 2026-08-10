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

# Special cards implemented so far (Phase 2B-i). More added in later steps.
var SPECIAL_DEFS := [
	{ "id": "lucky12", "title": "Lucky 12", "short": "Move 12\ninstead of\nrolling", "instant": false, "copies": 2 },
	{ "id": "lucky20", "title": "Lucky 20", "short": "Move 20\ninstead of\nrolling", "instant": false, "copies": 1 },
	{ "id": "lucky3", "title": "Lucky 3", "short": "Roll 3 dice\n(no doubles\nbonus)", "instant": true, "copies": 2 },
	{ "id": "lucky2", "title": "Lucky 2", "short": "Draw 2,\ndiscard 1", "instant": true, "copies": 2 },
	{ "id": "free_turn", "title": "Free Turn", "short": "Extra turn\nafter this\none", "instant": true, "copies": 2 },
	{ "id": "new_hand", "title": "New Hand", "short": "Discard OR\nswap your\nhand", "instant": false, "copies": 2 },
]
var SPECIAL_HEADER := Color(0.36, 0.20, 0.90)

var scale_f := 0.12                          # native -> window
var board := {}                              # id -> { pos, kind, name, neighbors }
var home_id := ""
var location_names := []                     # unique errand-location names present

var players := []
var tokens := []
var deck := []
var discard := []
var current := 0
var phase := "SETUP"                         # SETUP | ROLL | MOVE | OVER
var last_roll := 0
var _doubles := false
var destinations := []
var winner := -1
var _note := ""
var _setup_msg := ""
var _dice_count := 2                          # 2 normally; Lucky 3 makes it 3 for one roll
var _doubles_gives_free := true               # Lucky 3 turns this off for its roll
var _free_turn_pending := false               # Free Turn: current player goes again
var _pending := ""                            # "", "lucky2_discard", "newhand_choice"

var _board_tex: Texture2D
var _label: Label
var _banner: Label
var _scoreboard: Label
var _dice_row: Control
var _last_dice := []                          # individual die values from the last roll
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
	for sd in SPECIAL_DEFS:
		for i in range(sd["copies"]):
			deck.append({
				"type": "special", "id": sd["id"], "title": sd["title"],
				"short": sd["short"], "instant": sd["instant"],
				"locations": [], "count": 0, "flavor": "",
			})
	deck.shuffle()


func _draw_card() -> Dictionary:
	if deck.is_empty():
		if not discard.is_empty():
			deck = discard.duplicate()
			discard.clear()
			deck.shuffle()
		else:
			_build_deck()
	return deck.pop_back()


func _discard_from_hand(p, index: int) -> void:
	discard.append(p["hand"][index])
	p["hand"].remove_at(index)


func _draw_to_hand(p) -> void:
	p["hand"].append(_draw_card())


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

	# Dice / movement readout (top-centre, shown while choosing a move).
	_dice_row = Control.new()
	_dice_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_dice_row)


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

	# New Hand is waiting for a Discard/Swap choice.
	if _pending == "newhand_choice":
		if event is InputEventKey and event.pressed and not event.echo:
			if event.keycode == KEY_D:
				_newhand_resolve(false)
			elif event.keycode == KEY_S:
				_newhand_resolve(true)
		return

	# Lucky 2 waits for a card click (handled on the card itself); block the rest.
	if _pending == "lucky2_discard":
		return

	# DEBUG: press G on your turn to load a hand full of Specials for testing.
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_G:
		_debug_special_hand()
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
	var total := 0
	var vals := []
	for i in range(_dice_count):
		var v := randi() % 6 + 1
		vals.append(v)
		total += v
	_doubles = _doubles_gives_free and _dice_count == 2 and vals[0] == vals[1]
	_last_dice = vals.duplicate()
	# Reset per-turn dice modifiers (Lucky 3 only lasts one roll).
	_dice_count = 2
	_doubles_gives_free = true
	_start_move(total)


# Begin choosing a destination for a movement total (from dice OR a Lucky card).
func _start_move(total: int) -> void:
	last_roll = total
	destinations = _compute_destinations(players[current]["space"], total).keys()
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
	var again := extra_turn or _free_turn_pending
	if _free_turn_pending:
		_note = ("Free turn! " + _note).strip_edges()
		_free_turn_pending = false
	elif extra_turn:
		_note = ("Doubles — free turn! " + _note).strip_edges()
	if not again:
		current = (current + 1) % players.size()
	phase = "ROLL"
	_update_hud()
	queue_redraw()

# ---------------------------------------------------------------------------
# SPECIAL CARDS
# ---------------------------------------------------------------------------
func _on_card_clicked(index: int) -> void:
	if _animating or players.is_empty():
		return
	var p = players[current]
	if index < 0 or index >= p["hand"].size():
		return
	# Lucky 2 is waiting for the player to pick a card to discard.
	if _pending == "lucky2_discard":
		_discard_from_hand(p, index)
		_pending = ""
		_note = "Discarded down to 7."
		_update_hud()
		return
	if _pending != "" or phase != "ROLL":
		return
	if p["hand"][index]["type"] != "special":
		return
	_play_special(index)


func _play_special(index: int) -> void:
	var p = players[current]
	match p["hand"][index]["id"]:
		"lucky12":
			_play_lucky_move(index, 12)
		"lucky20":
			_play_lucky_move(index, 20)
		"lucky3":
			_discard_from_hand(p, index)
			_draw_to_hand(p)
			_dice_count = 3
			_doubles_gives_free = false
			_note = "Lucky 3 — press SPACE to roll THREE dice (no doubles bonus)."
			_update_hud()
		"lucky2":
			_discard_from_hand(p, index)   # remove Lucky 2 (hand -> 6)
			_draw_to_hand(p)               # draw 2 (hand -> 8)
			_draw_to_hand(p)
			_pending = "lucky2_discard"    # player clicks one to discard back to 7
			_note = "Lucky 2 — drew 2 cards; click one to discard."
			_update_hud()
		"new_hand":
			_discard_from_hand(p, index)   # remove New Hand (hand -> 6)
			_draw_to_hand(p)               # replacement (hand -> 7)
			_pending = "newhand_choice"
			_note = "New Hand — press D to discard & draw 7, or S to swap hands."
			_update_hud()
		"free_turn":
			_discard_from_hand(p, index)
			_draw_to_hand(p)
			_free_turn_pending = true
			_note = "Free Turn banked — you'll go again after this turn."
			_update_hud()


func _play_lucky_move(index: int, dist: int) -> void:
	var p = players[current]
	_discard_from_hand(p, index)
	_draw_to_hand(p)                 # replacement, keep hand at 7
	_doubles = false
	_last_dice = []                  # not a dice roll; readout shows "Move N"
	_note = "%s played Lucky %d!" % [p["name"], dist]
	_start_move(dist)               # choose a destination; consumes the turn


func _newhand_resolve(swap: bool) -> void:
	var p = players[current]
	if swap:
		var opp := (current + 1) % players.size()
		var tmp = players[opp]["hand"]
		players[opp]["hand"] = p["hand"]
		p["hand"] = tmp
		_note = "New Hand — swapped hands with %s." % players[opp]["name"]
	else:
		for card in p["hand"]:
			discard.append(card)
		p["hand"] = []
		for i in range(7):
			p["hand"].append(_draw_card())
		_note = "New Hand — discarded and drew a fresh 7."
	_pending = ""
	_end_turn(false)                # New Hand costs the turn


func _debug_special_hand() -> void:
	# Test aid: fill the current player's hand with the four Specials + errands.
	if players.is_empty() or phase != "ROLL" or _pending != "":
		return
	var p = players[current]
	p["hand"] = []
	for sd in SPECIAL_DEFS:
		p["hand"].append({
			"type": "special", "id": sd["id"], "title": sd["title"],
			"short": sd["short"], "instant": sd["instant"],
			"locations": [], "count": 0, "flavor": "",
		})
	while p["hand"].size() < 7:
		p["hand"].append(_draw_card())
	_note = "(debug) Test hand of Specials loaded."
	_update_hud()


func _reset_game() -> void:
	discard.clear()
	_build_deck()
	current = 0
	phase = "ROLL"
	winner = -1
	last_roll = 0
	_doubles = false
	destinations = []
	_note = ""
	_pending = ""
	_dice_count = 2
	_doubles_gives_free = true
	_free_turn_pending = false
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
		if _pending == "lucky2_discard":
			lines.append("LUCKY 2 — click a card to discard")
		elif _pending == "newhand_choice":
			lines.append("NEW HAND — press D to discard & draw 7, or S to swap hands")
		elif phase == "ROLL":
			if _dice_count == 3:
				lines.append("Press SPACE to roll THREE dice (Lucky 3)")
			elif _has_playable_special(p):
				lines.append("Press SPACE to roll  ·  or click a purple Special card")
			else:
				lines.append("Press SPACE to roll")
		else:
			lines.append("Click a yellow space to move")
		lines.append("(wheel: zoom · middle-drag / arrows: pan)")
	_label.text = "\n".join(lines)
	_refresh_card_bar()
	_show_move_readout()


func _has_playable_special(p) -> bool:
	for card in p["hand"]:
		if card["type"] == "special":
			return true
	return false


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
	var specials_playable := (phase == "ROLL" and _pending == "")
	for i in range(hand.size()):
		var card = hand[i]
		var clickable := false
		if _pending == "lucky2_discard":
			clickable = true                       # any card can be discarded
		elif specials_playable and card["type"] == "special":
			clickable = true
		var node := _make_card_node(card, clickable, i)
		node.position = Vector2(start_x + i * (CARD_W + CARD_GAP), y)
		_card_row.add_child(node)


func _make_card_node(card: Dictionary, clickable: bool, index: int) -> Control:
	var panel := Panel.new()
	panel.size = Vector2(CARD_W, CARD_H)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.97, 0.95, 0.90)
	sb.set_corner_radius_all(6)
	if clickable:
		sb.set_border_width_all(3)
		sb.border_color = Color(1.0, 0.85, 0.15)   # playable highlight
	else:
		sb.set_border_width_all(2)
		sb.border_color = Color(0.15, 0.15, 0.15)
	panel.add_theme_stylebox_override("panel", sb)

	if card["type"] == "special":
		_fill_special_card(panel, card)
	else:
		_fill_errand_card(panel, card)

	if clickable:
		panel.mouse_filter = Control.MOUSE_FILTER_STOP
		panel.gui_input.connect(_on_card_gui_input.bind(index))
	else:
		panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return panel


func _fill_errand_card(panel: Panel, card: Dictionary) -> void:
	var header := ColorRect.new()
	header.color = _district_color(card["locations"][0])
	header.position = Vector2(4, 4)
	header.size = Vector2(CARD_W - 8, 18)
	header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(header)

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


func _fill_special_card(panel: Panel, card: Dictionary) -> void:
	var header := ColorRect.new()
	header.color = SPECIAL_HEADER
	header.position = Vector2(4, 4)
	header.size = Vector2(CARD_W - 8, 20)
	header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(header)

	var title := Label.new()
	title.text = card["title"]
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 11)
	title.add_theme_color_override("font_color", Color.WHITE)
	title.position = Vector2(4, 4)
	title.size = Vector2(CARD_W - 8, 20)
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(title)

	var body := Label.new()
	body.text = card["short"]
	body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_theme_font_size_override("font_size", 11)
	body.add_theme_color_override("font_color", Color(0.1, 0.1, 0.1))
	body.position = Vector2(4, 26)
	body.size = Vector2(CARD_W - 8, CARD_H - 44)
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(body)

	if card["instant"]:
		var tag := Label.new()
		tag.text = "INSTANT"
		tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		tag.add_theme_font_size_override("font_size", 9)
		tag.add_theme_color_override("font_color", SPECIAL_HEADER)
		tag.position = Vector2(4, CARD_H - 18)
		tag.size = Vector2(CARD_W - 8, 14)
		tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
		panel.add_child(tag)


func _on_card_gui_input(event: InputEvent, index: int) -> void:
	if event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT:
		_on_card_clicked(index)


func _district_color(loc: String) -> Color:
	var d: String = DISTRICT_OF.get(loc, "")
	return DISTRICT_COLORS.get(d, Color(0.5, 0.5, 0.5))

# ---------------------------------------------------------------------------
# DICE / MOVE READOUT
# ---------------------------------------------------------------------------
func _show_move_readout() -> void:
	if _dice_row == null:
		return
	for c in _dice_row.get_children():
		c.queue_free()
	if phase != "MOVE":
		return
	var die := 54.0
	var gap := 10.0
	var eq_w := 36.0
	var sum_w := 60.0
	var y := 150.0

	# Lucky 12/20 aren't dice — show a "Move N" chip instead.
	if _last_dice.is_empty():
		var chip := _make_readout_label("Move %d" % last_roll, 40)
		chip.size = Vector2(260, die)
		chip.position = Vector2((VIEW_SIZE.x - 260) * 0.5, y)
		chip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		chip.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_dice_row.add_child(chip)
		return

	var n := _last_dice.size()
	var content_w := n * die + (n - 1) * gap + gap + eq_w + gap + sum_w
	var x := (VIEW_SIZE.x - content_w) * 0.5
	for v in _last_dice:
		var d := _make_die(int(v), die)
		d.position = Vector2(x, y)
		_dice_row.add_child(d)
		x += die + gap
	x += gap
	var eq := _make_readout_label("=", 38)
	eq.position = Vector2(x, y); eq.size = Vector2(eq_w, die)
	eq.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	eq.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_dice_row.add_child(eq)
	x += eq_w + gap
	var sm := _make_readout_label(str(last_roll), 44)
	sm.position = Vector2(x, y); sm.size = Vector2(sum_w, die)
	sm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sm.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_dice_row.add_child(sm)


func _make_die(value: int, size: float) -> Control:
	var p := Panel.new()
	p.size = Vector2(size, size)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.98, 0.98, 0.98)
	sb.set_corner_radius_all(8)
	sb.set_border_width_all(2)
	sb.border_color = Color(0.1, 0.1, 0.1)
	p.add_theme_stylebox_override("panel", sb)
	var l := Label.new()
	l.text = str(value)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", 32)
	l.add_theme_color_override("font_color", Color(0.1, 0.1, 0.1))
	l.position = Vector2.ZERO
	l.size = Vector2(size, size)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(l)
	return p


func _make_readout_label(text: String, font_size: int) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", Color.WHITE)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 6)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l
