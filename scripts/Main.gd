extends Node2D
## Errands — Phase 1: core turn loop on a visible TEST TRACK.
##
## This is not the real maze yet — it's a small hand-made track (a loop with one
## fork and 4 locations) drawn onto the board so we can prove out every turn
## mechanic before tracing the full board in Phase 3.
##
## Controls:
##   SPACE ............ roll the dice (on your turn)
##   Left-click ....... after rolling, click a highlighted (yellow) space to move
##
## Rules modelled here:
##   - Move up to the rolled total along roads; you choose the route at forks.
##   - Landing on a location forces a stop (remaining steps are lost).
##   - Land on a location matching a card in your hand -> errand done, draw a new card.
##   - Complete WIN_ERRANDS errands, then return Home to win.
##   - Rolling doubles = a free turn.

# ---------------------------------------------------------------------------
# CONFIG
# ---------------------------------------------------------------------------
const BOARD_SIZE := Vector2(6000, 9000)   # native art size
const VIEW_SIZE := Vector2(720, 1080)     # window size (board scaled to fit)
const TOKEN_SCALE := 0.13
const WIN_ERRANDS := 3                     # low for testing; real game is ~8-10
const CLICK_RADIUS := 30.0                 # how close a click must be to a space

# ---------------------------------------------------------------------------
# STATE
# ---------------------------------------------------------------------------
var board := {}            # id -> { pos:Vector2, neighbors:Array, kind:String, name:String }
var players := []          # array of { name, tint, space, hand:Array, completed:int }
var tokens := []           # Sprite2D per player
var deck := []             # array of location-name strings

var current := 0           # whose turn
var phase := "ROLL"        # "ROLL" | "MOVE" | "OVER"
var last_roll := 0
var _doubles := false
var destinations := []     # valid destination space ids after a roll
var winner := -1
var _note := ""            # transient status line (e.g. "Doubles!")

var _board_tex: Texture2D
var _label: Label
var _banner: Label

# ---------------------------------------------------------------------------
# SETUP
# ---------------------------------------------------------------------------
func _ready() -> void:
	randomize()
	_board_tex = load("res://assets/board.png")
	_build_board_data()
	_build_deck()
	_build_players()
	_build_tokens()
	_build_location_labels()
	_build_hud()
	_update_token_positions()
	_update_hud()
	queue_redraw()


func _build_board_data() -> void:
	# The loop, clockwise from Home. Coordinates are in the 720x1080 view space.
	_add_space("home", 431, 164, "home", "Home")
	_add_space("a1", 545, 205)
	_add_space("a2", 610, 300)
	_add_space("bank", 630, 410, "location", "Bank")
	_add_space("a3", 615, 520)
	_add_space("a4", 560, 615)          # <- the fork
	_add_space("gas", 440, 660, "location", "Gas")
	_add_space("a5", 315, 620)
	_add_space("a6", 250, 520)
	_add_space("school", 235, 410, "location", "School")
	_add_space("a7", 255, 300)
	_add_space("a8", 325, 205)
	# spur off the fork
	_add_space("b1", 640, 690)
	_add_space("park", 700, 770, "location", "Park")

	_connect("home", "a1"); _connect("a1", "a2"); _connect("a2", "bank")
	_connect("bank", "a3"); _connect("a3", "a4"); _connect("a4", "gas")
	_connect("gas", "a5"); _connect("a5", "a6"); _connect("a6", "school")
	_connect("school", "a7"); _connect("a7", "a8"); _connect("a8", "home")
	_connect("a4", "b1"); _connect("b1", "park")


func _add_space(id: String, x: float, y: float, kind := "road", loc_name := "") -> void:
	board[id] = { "pos": Vector2(x, y), "neighbors": [], "kind": kind, "name": loc_name }


func _connect(a: String, b: String) -> void:
	board[a]["neighbors"].append(b)
	board[b]["neighbors"].append(a)


func _build_deck() -> void:
	var names := ["Bank", "Gas", "School", "Park"]
	deck.clear()
	for i in range(10):
		for n in names:
			deck.append(n)
	deck.shuffle()


func _draw_card() -> String:
	if deck.is_empty():
		_build_deck()
	return deck.pop_back()


func _build_players() -> void:
	players = [
		{ "name": "Player 1", "tint": Color(1, 1, 1), "space": "home", "hand": [], "completed": 0 },
		{ "name": "Player 2", "tint": Color(0.45, 0.8, 1.0), "space": "home", "hand": [], "completed": 0 },
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
			lb.add_theme_font_size_override("font_size", 13)
			lb.add_theme_color_override("font_color", Color.WHITE)
			lb.add_theme_color_override("font_outline_color", Color.BLACK)
			lb.add_theme_constant_override("outline_size", 5)
			lb.mouse_filter = Control.MOUSE_FILTER_IGNORE
			lb.position = board[id]["pos"] + Vector2(-18, 12)
			add_child(lb)


func _build_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	_label = Label.new()
	_label.add_theme_font_size_override("font_size", 20)
	_label.add_theme_color_override("font_color", Color.WHITE)
	_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_label.add_theme_constant_override("outline_size", 6)
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.position = Vector2(14, 12)
	layer.add_child(_label)

	# Big centered win banner (hidden until someone wins).
	_banner = Label.new()
	_banner.add_theme_font_size_override("font_size", 42)
	_banner.add_theme_color_override("font_color", Color(1, 0.95, 0.4))
	_banner.add_theme_color_override("font_outline_color", Color.BLACK)
	_banner.add_theme_constant_override("outline_size", 10)
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_banner.position = Vector2.ZERO
	_banner.size = VIEW_SIZE
	_banner.visible = false
	layer.add_child(_banner)

# ---------------------------------------------------------------------------
# INPUT
# ---------------------------------------------------------------------------
func _unhandled_input(event: InputEvent) -> void:
	if phase == "OVER":
		if event.is_action_pressed("ui_accept"):
			_reset_game()
		return
	if phase == "ROLL" and event.is_action_pressed("ui_accept"):
		_roll()
	elif phase == "MOVE" and event is InputEventMouseButton \
			and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var id := _space_at(get_global_mouse_position())
		if id != "" and id in destinations:
			_move_to(id)


func _space_at(pos: Vector2) -> String:
	var best := ""
	var best_d := INF
	for id in board:
		var d: float = board[id]["pos"].distance_to(pos)
		if d < best_d:
			best_d = d
			best = id
	return best if best_d <= CLICK_RADIUS else ""

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


func _move_to(id: String) -> void:
	players[current]["space"] = id
	destinations = []
	_update_token_positions()
	_resolve_landing(id)
	if phase == "OVER":
		_update_hud()
		queue_redraw()
		return
	_end_turn(_doubles)


func _resolve_landing(id: String) -> void:
	var p = players[current]
	if board[id]["kind"] == "location":
		var loc: String = board[id]["name"]
		var idx: int = p["hand"].find(loc)
		if idx != -1:
			p["hand"].remove_at(idx)
			p["completed"] += 1
			p["hand"].append(_draw_card())
			_note = "%s ran the %s errand!" % [p["name"], loc]
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

# ---------------------------------------------------------------------------
# MOVEMENT GRAPH SEARCH
# ---------------------------------------------------------------------------
# Returns a set (dict of id->true) of legal stopping spaces reachable from
# `start` using exactly the rolled `steps`, stopping early on any location/home
# and never immediately reversing the space just left.
func _compute_destinations(start: String, steps: int) -> Dictionary:
	var out := {}
	_explore(start, "", steps, out)
	return out


func _explore(node: String, came_from: String, steps_left: int, out: Dictionary) -> void:
	for nb in board[node]["neighbors"]:
		if nb == came_from:
			continue
		if _is_stop(nb):
			out[nb] = true          # forced stop on a location/home
		elif steps_left - 1 <= 0:
			out[nb] = true          # used up the roll here
		else:
			_explore(nb, node, steps_left - 1, out)


func _is_stop(id: String) -> bool:
	return board[id]["kind"] == "location" or board[id]["kind"] == "home"

# ---------------------------------------------------------------------------
# RENDERING
# ---------------------------------------------------------------------------
func _draw() -> void:
	# Board first, then the track overlay on top of it.
	draw_texture_rect(_board_tex, Rect2(Vector2.ZERO, VIEW_SIZE), false)

	# Edges.
	var seen := {}
	for id in board:
		for nb in board[id]["neighbors"]:
			var pair := [id, nb]
			pair.sort()
			var key: String = pair[0] + "|" + pair[1]
			if seen.has(key):
				continue
			seen[key] = true
			draw_line(board[id]["pos"], board[nb]["pos"], Color(0.1, 0.1, 0.1, 0.85), 3.0)

	# Highlight rings for reachable destinations.
	for id in destinations:
		draw_circle(board[id]["pos"], 17.0, Color(1.0, 0.95, 0.2, 0.9))

	# Nodes.
	for id in board:
		var pos: Vector2 = board[id]["pos"]
		match board[id]["kind"]:
			"home":
				draw_circle(pos, 13.0, Color(0.1, 0.7, 0.2))
			"location":
				draw_circle(pos, 11.0, Color(0.2, 0.4, 0.9))
			_:
				draw_circle(pos, 7.0, Color(0.8, 0.8, 0.8))

	# Dim the board behind the win banner.
	if phase == "OVER":
		draw_rect(Rect2(Vector2.ZERO, VIEW_SIZE), Color(0, 0, 0, 0.55))


func _update_token_positions() -> void:
	# Spread multiple tokens that share a space so both stay visible.
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
				off.x = (j - (occ.size() - 1) / 2.0) * 20.0
			tokens[occ[j]].position = base + off + Vector2(0, -12)


func _update_hud() -> void:
	var lines := []
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
		lines.append("Hand: " + ", ".join(p["hand"]))
		if p["completed"] >= WIN_ERRANDS:
			lines.append("Enough errands — return HOME to win!")
		if phase == "ROLL":
			lines.append("Press SPACE to roll")
		else:
			lines.append("Rolled %d — click a yellow space to move" % last_roll)
	_label.text = "\n".join(lines)


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
		players[i]["space"] = "home"
		players[i]["completed"] = 0
		players[i]["hand"] = []
		for j in range(7):
			players[i]["hand"].append(_draw_card())
	_update_token_positions()
	_update_hud()
	queue_redraw()
