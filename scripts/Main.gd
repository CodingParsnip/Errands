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
const BRIDGE_REACH := 95.0                    # max span (view px) the bridge can bridge
const ZOOM_MIN := 1.0                        # 1.0 = whole board fits the window
const ZOOM_MAX := 6.0
const PAN_SPEED := 700.0
const STEP_TIME := 0.18                      # seconds per space while animating a move
const SLIDE_TIME := 0.8                       # seconds to slide a sent/swapped token
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
	{ "id": "to_beach", "title": "To the Beach", "short": "Send a player\nto the Beach\n(lose a turn)", "instant": false, "copies": 1 },
	{ "id": "to_lake", "title": "To the Lake", "short": "Send a player\nto the Lake\n(lose a turn)", "instant": false, "copies": 1 },
	{ "id": "get_music", "title": "Get Music", "short": "Send a player\nto Music\n(lose a turn)", "instant": false, "copies": 1 },
	{ "id": "slow_traffic", "title": "Slow Traffic", "short": "Target moves 1\nspace, next\n2 turns", "instant": false, "copies": 2 },
	{ "id": "switcheroo", "title": "Switcheroo", "short": "Swap places\nwith another\nplayer", "instant": false, "copies": 2 },
	{ "id": "road_hazard", "title": "Road Hazard", "short": "Place a\nroad-block", "instant": false, "copies": 2 },
	{ "id": "prevent", "title": "Prevent", "short": "Cancel a\nSpecial OR\nremove block", "instant": true, "copies": 2 },
	{ "id": "thanks", "title": "Thanks", "short": "Finish an errand\nan opponent\nlands on", "instant": true, "copies": 2 },
	{ "id": "dumpster_diving", "title": "Dumpster Diving", "short": "Take any card\nfrom the\ndiscard pile", "instant": true, "copies": 2 },
	{ "id": "shortcut", "title": "Shortcut", "short": "Move the\nbridge", "instant": false, "copies": 2 },
]
var SPECIAL_HEADER := Color(0.36, 0.20, 0.90)

var scale_f := 0.12                          # native -> window
var board := {}                              # id -> { pos, kind, name, neighbors }
var home_id := ""
var location_names := []                     # unique errand-location names present
var location_spaces := {}                    # location name -> a space id (for "send" cards)

var players := []
var tokens := []
var deck := []
var discard := []
var roadblocks := {}                          # set of blocked space ids (id -> true)
var bridge_ends := []                          # [a, b] space ids the bridge currently spans (or empty)
var _bridge_anchor := ""                        # first end chosen while placing the bridge
var bridge_candidates := []                     # valid second-end space ids while placing
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
var _pending := ""                            # "", "lucky2_discard", "newhand_choice", reactions…
var _slowed := false                          # current player is under Slow Traffic this turn
var _reaction := {}                           # context for a pending reaction window

var _board_tex: Texture2D
var _blockade_tex: Texture2D
var _bridge_tex: Texture2D
var _bridge_sprite: Sprite2D
var _label: RichTextLabel
var _info_bg: Panel
var _banner: Label
var _scoreboard: RichTextLabel
var _score_bg: Panel
var _last_dice := []                          # individual die values from the last roll
var _die_tex := {}                            # value(1-6) -> generated pip-die texture
var PIP_LAYOUT := {                           # pip grid positions (col,row in 0..2) per face
	1: [Vector2i(1, 1)],
	2: [Vector2i(0, 0), Vector2i(2, 2)],
	3: [Vector2i(0, 0), Vector2i(1, 1), Vector2i(2, 2)],
	4: [Vector2i(0, 0), Vector2i(2, 0), Vector2i(0, 2), Vector2i(2, 2)],
	5: [Vector2i(0, 0), Vector2i(2, 0), Vector2i(1, 1), Vector2i(0, 2), Vector2i(2, 2)],
	6: [Vector2i(0, 0), Vector2i(2, 0), Vector2i(0, 1), Vector2i(2, 1), Vector2i(0, 2), Vector2i(2, 2)],
}
var _camera: Camera2D
var _panning := false
var _animating := false
var _card_layer: CanvasLayer
var _card_row: Control
var _discard_layer: CanvasLayer
var _discard_root: Control
var _dd_held := {}                            # the Dumpster Diving card held aside while picking


func _ready() -> void:
	randomize()
	_board_tex = load("res://assets/board.png")
	_blockade_tex = load("res://assets/blockade.png")
	_bridge_tex = load("res://assets/bridge.png")
	_bridge_sprite = Sprite2D.new()
	_bridge_sprite.texture = _bridge_tex
	_bridge_sprite.visible = false
	add_child(_bridge_sprite)                  # drawn above the board, below tokens
	_build_die_textures()
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
	location_spaces.clear()
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
		elif s["kind"] == "location":
			if not location_names.has(s["name"]):
				location_names.append(s["name"])
			if not location_spaces.has(s["name"]):
				location_spaces[s["name"]] = id
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
	# "tint" is each player's identity colour (token halo + HUD). Player 1's car
	# art is red, so P1 = red; P2 = cyan for a clear contrast.
	players = [
		{ "name": "Player 1", "tint": Color(0.95, 0.25, 0.20), "space": home_id, "hand": [], "completed": 0, "skip_turns": 0, "slow_turns": 0 },
		{ "name": "Player 2", "tint": Color(0.15, 0.85, 1.0), "space": home_id, "hand": [], "completed": 0, "skip_turns": 0, "slow_turns": 0 },
	]
	for p in players:
		for i in range(7):
			p["hand"].append(_draw_card())


func _build_tokens() -> void:
	# The car art is red. Leave P1 natural (bright red); cool-tint P2 so the two
	# cars also differ, then the coloured halo (drawn in _draw) makes it obvious.
	var mods := [Color.WHITE, Color(0.40, 0.90, 1.0)]
	for i in range(players.size()):
		var spr := Sprite2D.new()
		spr.texture = load("res://assets/player.png")
		spr.scale = Vector2(TOKEN_SCALE, TOKEN_SCALE)
		spr.modulate = mods[i] if i < mods.size() else Color.WHITE
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

	# Top-left info panel (turn / action log / prompt).
	_info_bg = _make_hud_panel(Vector2(10, 8), Vector2(436, 188))
	layer.add_child(_info_bg)
	_label = RichTextLabel.new()
	_label.bbcode_enabled = true
	_label.scroll_active = false
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.add_theme_font_size_override("normal_font_size", 20)
	_label.add_theme_font_size_override("bold_font_size", 20)
	_label.add_theme_color_override("default_color", Color(0.93, 0.95, 0.99))
	_label.position = Vector2(22, 16)
	_label.size = Vector2(414, 172)
	layer.add_child(_label)

	_banner = Label.new()
	_banner.add_theme_font_size_override("font_size", 34)
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

	# Top-right scoreboard panel (both players, always visible).
	_score_bg = _make_hud_panel(Vector2(VIEW_SIZE.x - 254, 8), Vector2(244, 108))
	layer.add_child(_score_bg)
	_scoreboard = RichTextLabel.new()
	_scoreboard.bbcode_enabled = true
	_scoreboard.scroll_active = false
	_scoreboard.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_scoreboard.add_theme_font_size_override("normal_font_size", 20)
	_scoreboard.add_theme_font_size_override("bold_font_size", 20)
	_scoreboard.add_theme_color_override("default_color", Color(0.93, 0.95, 0.99))
	_scoreboard.position = Vector2(VIEW_SIZE.x - 242, 16)
	_scoreboard.size = Vector2(222, 92)
	layer.add_child(_scoreboard)


func _make_hud_panel(pos: Vector2, size: Vector2) -> Panel:
	var p := Panel.new()
	p.position = pos
	p.size = size
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.06, 0.09, 0.74)
	sb.set_corner_radius_all(10)
	sb.set_border_width_all(2)
	sb.border_color = Color(1, 1, 1, 0.22)
	p.add_theme_stylebox_override("panel", sb)
	return p


func _hud_color(i: int) -> String:
	return "#" + players[i]["tint"].to_html(false)


func _swatch(i: int) -> String:
	return "[color=%s]■[/color] " % _hud_color(i)


func _colorize(text: String) -> String:
	for i in range(players.size()):
		text = text.replace(players[i]["name"], "[color=%s]%s[/color]" % [_hud_color(i), players[i]["name"]])
	return text


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

	# Lucky 2 / Dumpster Diving wait for a card click (handled on the card node).
	if _pending == "lucky2_discard" or _pending == "pick_discard":
		return

	# Prevent reaction window (opponent chooses).
	if _pending == "react_prevent":
		if event is InputEventKey and event.pressed and not event.echo:
			if event.keycode == KEY_Y:
				_do_prevent(true)
			elif event.keycode == KEY_N:
				_do_prevent(false)
		return

	# Thanks reaction window (opponent chooses).
	if _pending == "react_thanks":
		if event is InputEventKey and event.pressed and not event.echo:
			if event.keycode == KEY_Y:
				_do_thanks(true)
			elif event.keycode == KEY_N:
				_do_thanks(false)
		return

	# Road Hazard: click an open road space to place a block.
	if _pending == "place_roadblock":
		if event is InputEventMouseButton and event.pressed \
				and event.button_index == MOUSE_BUTTON_LEFT:
			_try_place_roadblock(get_global_mouse_position())
		return

	# Prevent: click a roadblock to remove it.
	if _pending == "remove_roadblock":
		if event is InputEventMouseButton and event.pressed \
				and event.button_index == MOUSE_BUTTON_LEFT:
			_try_remove_roadblock(get_global_mouse_position())
		return

	# Shortcut: click the two ends of the bridge.
	if _pending == "place_bridge":
		if event is InputEventMouseButton and event.pressed \
				and event.button_index == MOUSE_BUTTON_LEFT:
			_on_bridge_click(get_global_mouse_position())
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
	if _slowed:
		_doubles = false
		_last_dice = []
		_note = "%s is stuck in Slow Traffic — move only 1 space." % players[current]["name"]
		_start_move(1)
		return
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
	if _pending == "react_thanks":
		_update_hud(); queue_redraw()       # wait for the reaction; end-turn is deferred
		return
	_end_turn(_doubles)


func _do_thanks(play: bool) -> void:
	var o: int = _reaction["who"]
	var loc: String = _reaction["loc"]
	_pending = ""
	_reaction = {}
	if play:
		var tidx := _find_card(players[o], "thanks")
		if tidx != -1:
			_discard_from_hand(players[o], tidx)
			_draw_to_hand(players[o])
		var eidx := _find_errand(players[o], loc)
		if eidx != -1:
			var ecard = players[o]["hand"][eidx]
			players[o]["hand"].remove_at(eidx)
			players[o]["completed"] += ecard["count"]
			_draw_to_hand(players[o])
			_note = "%s played Thanks — finished %s (+%d)!" % [players[o]["name"], loc, ecard["count"]]
	_end_turn(_doubles)                       # resume the interrupted turn-end


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
			if roadblocks.has(nb):
				continue                 # can't pass a roadblock
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
		# Thanks reaction: an opponent who holds Thanks + a matching errand may cash it in.
		var o := _target_player()
		if _has_card(players[o], "thanks") and _find_errand(players[o], loc) != -1:
			_reaction = { "who": o, "loc": loc }
			_pending = "react_thanks"
			_note = "%s landed on %s.  %s: Y = play Thanks (finish your %s errand), N = skip." \
					% [p["name"], loc, players[o]["name"], loc]
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
		# "Lose a turn" skips (from To the Beach/Lake/Get Music).
		while players[current]["skip_turns"] > 0:
			players[current]["skip_turns"] -= 1
			_note = (_note + "  •  %s loses a turn!" % players[current]["name"]).strip_edges()
			current = (current + 1) % players.size()
	# Slow Traffic: this player's turn is capped to 1 space; count it down now.
	_slowed = false
	if players[current]["slow_turns"] > 0:
		players[current]["slow_turns"] -= 1
		_slowed = true
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
	_attempt_special(index)


# Before a Special resolves, give the opponent a chance to Prevent it.
func _attempt_special(index: int) -> void:
	var p = players[current]
	var card = p["hand"][index]
	var o := _target_player()
	if card["id"] != "prevent" and _has_card(players[o], "prevent"):
		_reaction = { "special_index": index, "title": card["title"], "instant": card["instant"] }
		_pending = "react_prevent"
		_note = "%s played %s.  %s: Y = Prevent it, N = allow." % [p["name"], card["title"], players[o]["name"]]
		_update_hud()
		return
	_resolve_special(index)


func _do_prevent(prevent_it: bool) -> void:
	var idx: int = _reaction["special_index"]
	var was_instant: bool = _reaction["instant"]
	var title: String = _reaction["title"]
	_pending = ""
	_reaction = {}
	if not prevent_it:
		_resolve_special(idx)               # opponent allowed it — resolve normally
		return
	var p = players[current]
	var o := _target_player()
	_discard_from_hand(p, idx)              # the Special is spent, with no effect
	_draw_to_hand(p)
	var pidx := _find_card(players[o], "prevent")
	if pidx != -1:
		_discard_from_hand(players[o], pidx)
		_draw_to_hand(players[o])
	_note = "%s Prevented %s's %s!" % [players[o]["name"], p["name"], title]
	if was_instant:
		_update_hud()                       # instant: no turn lost
	else:
		_end_turn(false)                    # a turn-costing Special was spent
	queue_redraw()


func _resolve_special(index: int) -> void:
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
		"to_beach":
			_play_send(index, "Beach")
		"to_lake":
			_play_send(index, "Lake")
		"get_music":
			_play_send(index, "Music")
		"slow_traffic":
			_discard_from_hand(p, index)
			_draw_to_hand(p)
			var t := _target_player()
			players[t]["slow_turns"] = 2
			_note = "%s hit %s with Slow Traffic (1 space/turn for 2 turns)." % [p["name"], players[t]["name"]]
			_end_turn(false)               # costs the turn
		"switcheroo":
			_discard_from_hand(p, index)
			_draw_to_hand(p)
			var t2 := _target_player()
			var tmp = players[current]["space"]
			players[current]["space"] = players[t2]["space"]
			players[t2]["space"] = tmp
			_note = "%s swapped places with %s!" % [p["name"], players[t2]["name"]]
			_update_hud()
			_slide_tokens([current, t2])   # both slide, then end the turn
		"road_hazard":
			_discard_from_hand(p, index)
			_draw_to_hand(p)
			_pending = "place_roadblock"
			_note = "Road Hazard — click an open road space to place a roadblock."
			_update_hud()
		"prevent":
			if roadblocks.is_empty():
				_note = "Prevent: no roadblock to remove right now."
				_update_hud()
			else:
				_discard_from_hand(p, index)
				_draw_to_hand(p)
				_pending = "remove_roadblock"
				_note = "Prevent — click a roadblock to remove it."
				_update_hud()
		"free_turn":
			_discard_from_hand(p, index)
			_draw_to_hand(p)
			_free_turn_pending = true
			_note = "Free Turn banked — you'll go again after this turn."
			_update_hud()
		"dumpster_diving":
			if discard.is_empty():
				_note = "Dumpster Diving — the discard pile is empty."
				_update_hud()
			else:
				# Hold the card aside (not into discard yet) and open the picker.
				_dd_held = p["hand"][index]
				p["hand"].remove_at(index)
				_pending = "pick_discard"
				_note = "Dumpster Diving — click a card from the discard pile to take it."
				_update_hud()
		"shortcut":
			_discard_from_hand(p, index)
			_draw_to_hand(p)
			_bridge_anchor = ""
			bridge_candidates = []
			_pending = "place_bridge"
			_note = "Shortcut — click one end of the bridge (a space)."
			_update_hud()
			queue_redraw()


func _pick_discard(discard_index: int) -> void:
	if _pending != "pick_discard":
		return
	if discard_index < 0 or discard_index >= discard.size():
		return
	var picked = discard[discard_index]
	discard.remove_at(discard_index)
	players[current]["hand"].append(picked)     # hand 6 -> 7
	if not _dd_held.is_empty():
		discard.append(_dd_held)                # the Dumpster Diving card now discards
		_dd_held = {}
	_pending = ""
	_note = "Took %s from the discard pile." % _card_label(picked)
	_update_hud()
	queue_redraw()


func _on_discard_gui_input(event: InputEvent, discard_index: int) -> void:
	if event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT:
		_pick_discard(discard_index)


func _card_label(card: Dictionary) -> String:
	if card["type"] == "special":
		return card["title"]
	return " + ".join(card["locations"])


func _play_lucky_move(index: int, dist: int) -> void:
	var p = players[current]
	_discard_from_hand(p, index)
	_draw_to_hand(p)                 # replacement, keep hand at 7
	_doubles = false
	_last_dice = []                  # not a dice roll; readout shows "Move N"
	_note = "%s played Lucky %d!" % [p["name"], dist]
	_start_move(dist)               # choose a destination; consumes the turn


func _target_player() -> int:
	# 2-player: the opponent. (For 3+ players, replace with a target picker.)
	return (current + 1) % players.size()


func _has_card(player, id: String) -> bool:
	return _find_card(player, id) != -1


func _find_card(player, id: String) -> int:
	for i in range(player["hand"].size()):
		var c = player["hand"][i]
		if c["type"] == "special" and c["id"] == id:
			return i
	return -1


func _find_errand(player, loc: String) -> int:
	for i in range(player["hand"].size()):
		var c = player["hand"][i]
		if c["type"] == "errand" and loc in c["locations"]:
			return i
	return -1


func _errand_card(loc: String) -> Dictionary:
	return { "type": "errand", "locations": [loc], "count": 1, "flavor": "" }


func _play_send(index: int, loc: String) -> void:
	var p = players[current]
	_discard_from_hand(p, index)
	_draw_to_hand(p)
	var t := _target_player()
	players[t]["skip_turns"] += 1
	_note = "%s sent %s to %s — they lose a turn." % [p["name"], players[t]["name"], loc]
	if location_spaces.has(loc):
		players[t]["space"] = location_spaces[loc]
		_update_hud()
		_slide_tokens([t])             # slide over, then end the turn
	else:
		_end_turn(false)               # costs the turn


# Slide the given player tokens to their (already-updated) spaces, then end turn.
func _slide_tokens(indices: Array) -> void:
	if tokens.is_empty():
		_end_turn(false)
		return
	_animating = true
	var tw := create_tween().set_parallel(true)
	for i in indices:
		var start_pos: Vector2 = tokens[i].position
		var target: Vector2 = board[players[i]["space"]]["pos"] + Vector2(0, -10)
		if (target - start_pos).length() > 1.0:
			tokens[i].rotation = (target - start_pos).angle() + TOKEN_ART_ANGLE
		tw.tween_property(tokens[i], "position", target, SLIDE_TIME)
	tw.chain().tween_callback(_finish_slide)


func _finish_slide() -> void:
	_animating = false
	_update_token_positions()
	_end_turn(false)

# ---------------------------------------------------------------------------
# ROADBLOCKS
# ---------------------------------------------------------------------------
func _try_place_roadblock(world: Vector2) -> void:
	var id := _nearest_space_any(world)
	if id == "":
		return
	if not _can_place_roadblock(id):
		_note = "Can't place there — pick an open road that won't strand anyone."
		_update_hud()
		return
	roadblocks[id] = true
	_pending = ""
	_note = "%s placed a roadblock." % players[current]["name"]
	_end_turn(false)                   # Road Hazard costs the turn
	queue_redraw()


func _try_remove_roadblock(world: Vector2) -> void:
	var id := _nearest_roadblock(world)
	if id == "":
		return
	roadblocks.erase(id)
	_pending = ""
	_note = "Roadblock removed."
	_update_hud()
	queue_redraw()                     # Prevent is instant — no turn spent


func _can_place_roadblock(id: String) -> bool:
	if board[id]["kind"] != "road" and board[id]["kind"] != "highway":
		return false
	if roadblocks.has(id):
		return false
	for p in players:
		if p["space"] == id:
			return false
	# Placing must not cut any player off from Home.
	var blocked := roadblocks.duplicate()
	blocked[id] = true
	for p in players:
		if not _reaches(p["space"], home_id, blocked):
			return false
	return true


func _reaches(start: String, goal: String, blocked: Dictionary) -> bool:
	if start == goal:
		return true
	var seen := { start: true }
	var q := [start]
	while not q.is_empty():
		var n: String = q.pop_front()
		for nb in board[n]["neighbors"]:
			if blocked.has(nb) or seen.has(nb):
				continue
			if nb == goal:
				return true
			seen[nb] = true
			q.append(nb)
	return false


func _nearest_space_any(world: Vector2) -> String:
	var best := ""
	var best_d := CLICK_RADIUS
	for id in board:
		var d: float = board[id]["pos"].distance_to(world)
		if d <= best_d:
			best_d = d
			best = id
	return best


func _nearest_roadblock(world: Vector2) -> String:
	var best := ""
	var best_d := CLICK_RADIUS
	for id in roadblocks:
		var d: float = board[id]["pos"].distance_to(world)
		if d <= best_d:
			best_d = d
			best = id
	return best

# ---------------------------------------------------------------------------
# BRIDGE (Shortcut)
# ---------------------------------------------------------------------------
func _on_bridge_click(world: Vector2) -> void:
	var id := _nearest_space_any(world)
	if id == "":
		return
	# Second click on a valid far end -> place the bridge there.
	if _bridge_anchor != "" and id in bridge_candidates:
		_set_bridge(_bridge_anchor, id)
		_bridge_anchor = ""
		bridge_candidates = []
		_pending = ""
		_note = "%s moved the bridge." % players[current]["name"]
		_end_turn(false)                   # Shortcut costs the turn
		return
	# Otherwise (re)choose the first end and show what's in reach.
	_bridge_anchor = id
	bridge_candidates = _bridge_reachable(id)
	if bridge_candidates.is_empty():
		_note = "Nothing in reach from there — pick a different first end."
	else:
		_note = "Shortcut — now click the other end (highlighted cyan)."
	_update_hud()
	queue_redraw()


func _bridge_reachable(id: String) -> Array:
	# Spaces within the bridge's span that aren't already directly connected.
	var out := []
	var from: Vector2 = board[id]["pos"]
	for other in board:
		if other == id:
			continue
		if other in board[id]["neighbors"]:
			continue
		if from.distance_to(board[other]["pos"]) <= BRIDGE_REACH:
			out.append(other)
	return out


func _set_bridge(a: String, b: String) -> void:
	# Remove the old bridge edge (bridge edges only ever connect non-adjacent
	# spaces, so this can't delete a real road).
	if bridge_ends.size() == 2:
		var oa: String = bridge_ends[0]
		var ob: String = bridge_ends[1]
		board[oa]["neighbors"].erase(ob)
		board[ob]["neighbors"].erase(oa)
	bridge_ends = []
	if a != "" and b != "" and a != b:
		board[a]["neighbors"].append(b)
		board[b]["neighbors"].append(a)
		bridge_ends = [a, b]
	_update_bridge_sprite()


func _update_bridge_sprite() -> void:
	if _bridge_sprite == null:
		return
	if bridge_ends.size() != 2:
		_bridge_sprite.visible = false
		return
	var pa: Vector2 = board[bridge_ends[0]]["pos"]
	var pb: Vector2 = board[bridge_ends[1]]["pos"]
	var dist := pa.distance_to(pb)
	_bridge_sprite.visible = true
	_bridge_sprite.position = (pa + pb) * 0.5
	_bridge_sprite.rotation = (pb - pa).angle()
	var tex_w: float = max(1.0, float(_bridge_tex.get_width()))
	_bridge_sprite.scale = Vector2(dist / tex_w, 0.13)


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


func _special_card(id: String) -> Dictionary:
	for sd in SPECIAL_DEFS:
		if sd["id"] == id:
			return {
				"type": "special", "id": sd["id"], "title": sd["title"],
				"short": sd["short"], "instant": sd["instant"],
				"locations": [], "count": 0, "flavor": "",
			}
	return {}


func _debug_special_hand() -> void:
	# Test aid: load the current player's hand with the movement/self Specials.
	if players.is_empty() or phase != "ROLL" or _pending != "":
		return
	var me = players[current]
	me["hand"] = []
	for id in ["shortcut", "shortcut", "switcheroo", "to_beach", "dumpster_diving"]:
		me["hand"].append(_special_card(id))
	while me["hand"].size() < 7:
		me["hand"].append(_draw_card())
	if discard.size() < 6:
		for i in range(8):
			discard.append(_draw_card())
	_note = "(debug) Test hand: Shortcut ×2, Switcheroo, To the Beach, Dumpster Diving."
	_update_hud()


func _reset_game() -> void:
	discard.clear()
	roadblocks.clear()
	_set_bridge("", "")                # remove any placed bridge edge + hide sprite
	_bridge_anchor = ""
	bridge_candidates = []
	_build_deck()
	current = 0
	phase = "ROLL"
	winner = -1
	last_roll = 0
	_doubles = false
	destinations = []
	_note = ""
	_pending = ""
	_reaction = {}
	_dd_held = {}
	_dice_count = 2
	_doubles_gives_free = true
	_free_turn_pending = false
	_slowed = false
	for i in range(players.size()):
		players[i]["space"] = home_id
		players[i]["completed"] = 0
		players[i]["skip_turns"] = 0
		players[i]["slow_turns"] = 0
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
		if roadblocks.has(nb):
			continue                     # a roadblock is impassable
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

	# Roadblocks.
	for id in roadblocks:
		var bp: Vector2 = board[id]["pos"]
		draw_circle(bp, 9.0, Color(0.85, 0.1, 0.1, 0.85))
		if _blockade_tex != null:
			draw_texture_rect(_blockade_tex, Rect2(bp - Vector2(14, 7), Vector2(28, 14)), false)

	# Bridge placement (Shortcut): anchor + in-reach candidates.
	if _pending == "place_bridge":
		for id in bridge_candidates:
			draw_circle(board[id]["pos"], 9.0, Color(0.2, 0.9, 1.0, 0.75))
		if _bridge_anchor != "" and board.has(_bridge_anchor):
			draw_circle(board[_bridge_anchor]["pos"], 11.0, Color(1.0, 0.95, 0.2, 0.95))

	# Per-player colour halo under each token, so the two are easy to tell apart.
	for i in range(tokens.size()):
		var tp: Vector2 = tokens[i].position
		var col: Color = players[i]["tint"]
		draw_circle(tp, 18.0, Color(col.r, col.g, col.b, 0.55))
		draw_arc(tp, 18.0, 0, TAU, 28, col, 2.5)

	# Mark whose turn it is.
	if phase != "SETUP" and phase != "OVER" and not tokens.is_empty():
		_draw_active_indicator(tokens[current].position)

	if phase == "OVER":
		draw_rect(Rect2(Vector2.ZERO, VIEW_SIZE), Color(0, 0, 0, 0.55))


func _draw_active_indicator(pos: Vector2) -> void:
	var tint: Color = players[current]["tint"]
	# Ring around the active token, in the current player's colour.
	draw_arc(pos, 20.0, 0, TAU, 32, Color(0, 0, 0, 0.8), 6.0)
	draw_arc(pos, 20.0, 0, TAU, 32, tint, 3.0)
	# Chevron pointing down at it, in the current player's colour.
	var c := pos + Vector2(0, -30)
	var back := PackedVector2Array([c + Vector2(-13, -13), c + Vector2(13, -13), c + Vector2(0, 7)])
	var tri := PackedVector2Array([c + Vector2(-10, -10), c + Vector2(10, -10), c + Vector2(0, 4)])
	draw_colored_polygon(back, Color(0, 0, 0, 0.85))
	draw_colored_polygon(tri, tint)


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
	_update_scoreboard()
	_label.clear()
	if phase == "SETUP":
		_banner.visible = true
		_banner.text = _setup_msg
		_label.append_text("[b]Errands[/b] — setup needed (see centre of screen)")
		_refresh_card_bar()
		_refresh_discard_picker()
		return
	if phase == "OVER":
		_banner.visible = true
		_banner.text = "🎉  %s WINS!  🎉\n\nPress SPACE to play again" % players[winner]["name"]
		_label.append_text("[font_size=25]%s[color=%s]%s[/color] WINS! 🎉[/font_size]" % [_swatch(winner), _hud_color(winner), players[winner]["name"]])
		_refresh_card_bar()
		_refresh_discard_picker()
		return

	_banner.visible = false
	var p = players[current]
	_label.append_text("[font_size=25]%s[color=%s]%s[/color]'s turn[/font_size]\n" % [_swatch(current), _hud_color(current), players[current]["name"]])
	if phase == "MOVE":
		_append_roll_readout()
	if not _note.is_empty():
		_label.append_text(_colorize(_note) + "\n")
	_label.append_text(_current_prompt(p) + "\n")
	_label.append_text("[color=#7f8ba0][font_size=15]wheel: zoom · drag / arrows: pan[/font_size][/color]")
	_refresh_card_bar()
	_refresh_discard_picker()


# The action prompt for the current situation (BBCode).
func _current_prompt(p) -> String:
	match _pending:
		"lucky2_discard":
			return "[b]Lucky 2[/b] — click a card to discard"
		"newhand_choice":
			return "[b]New Hand[/b] — press [b]D[/b] = discard & draw 7,  [b]S[/b] = swap hands"
		"place_roadblock":
			return "[b]Road Hazard[/b] — click an open road to place a block"
		"remove_roadblock":
			return "[b]Prevent[/b] — click a roadblock to remove it"
		"pick_discard":
			return "[b]Dumpster Diving[/b] — click a card in the discard pile"
		"place_bridge":
			if _bridge_anchor == "":
				return "[b]Shortcut[/b] — click one end of the bridge (a space)"
			return "[b]Shortcut[/b] — click the other end (highlighted cyan)"
		"react_prevent":
			var o := _target_player()
			return "[color=%s]%s[/color]: press [b]Y[/b] to Prevent, [b]N[/b] to allow" % [_hud_color(o), players[o]["name"]]
		"react_thanks":
			var o2 := _target_player()
			return "[color=%s]%s[/color]: press [b]Y[/b] for Thanks, [b]N[/b] to skip" % [_hud_color(o2), players[o2]["name"]]
	if phase == "MOVE":
		return "Click a highlighted (yellow) space to move"
	if _slowed:
		return "[b]Slow Traffic[/b] — press [b]SPACE[/b] to crawl 1 space"
	if _dice_count == 3:
		return "[b]Lucky 3[/b] — press [b]SPACE[/b] to roll THREE dice"
	var msg := "Press [b]SPACE[/b] to roll"
	if _has_playable_special(p):
		msg += "  ·  or click a purple [b]Special[/b]"
	if p["completed"] >= WIN_ERRANDS:
		msg += "\n[color=#9fe0ff]Enough errands — head HOME to win![/color]"
	return msg


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
	var rows := ["[color=#aeb6c2]ERRANDS — first to %d[/color]" % WIN_ERRANDS]
	for i in range(players.size()):
		var active := (i == current and phase != "OVER")
		var body := "%s[color=%s]%s[/color]   [b]%d[/b]/%d" % [_swatch(i), _hud_color(i), players[i]["name"], players[i]["completed"], WIN_ERRANDS]
		if active:
			rows.append("[bgcolor=#ffffff26]▶ " + body + "[/bgcolor]")
		else:
			rows.append("   " + body)
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

	# Overlay for the Dumpster Diving discard-pile picker.
	_discard_layer = CanvasLayer.new()
	_discard_layer.layer = 2
	add_child(_discard_layer)
	_discard_root = Control.new()
	_discard_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_discard_layer.add_child(_discard_root)


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
			# While slowed, the move-Specials are disabled (can't dodge Slow Traffic).
			var move_card: bool = card["id"] == "lucky12" or card["id"] == "lucky20"
			clickable = not (_slowed and move_card)
		var node := _make_card_node(card, clickable, i)
		node.position = Vector2(start_x + i * (CARD_W + CARD_GAP), y)
		_card_row.add_child(node)


func _refresh_discard_picker() -> void:
	if _discard_root == null:
		return
	for child in _discard_root.get_children():
		child.queue_free()
	if _pending != "pick_discard":
		return

	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 0.72)
	bg.position = Vector2.ZERO
	bg.size = VIEW_SIZE
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_discard_root.add_child(bg)

	var start: int = max(0, discard.size() - 24)   # show the most recent 24
	var count := discard.size() - start

	var title := Label.new()
	title.text = "Dumpster Diving — click a card to take it"
	if start > 0:
		title.text += "   (most recent 24)"
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", Color(1, 0.95, 0.5))
	title.add_theme_color_override("font_outline_color", Color.BLACK)
	title.add_theme_constant_override("outline_size", 5)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title.position = Vector2(0, 40)
	title.size = Vector2(VIEW_SIZE.x, 30)
	_discard_root.add_child(title)

	var cols := 6
	var gap := 8.0
	var used_cols: int = min(count, cols)
	var grid_w := used_cols * (CARD_W + gap) - gap
	var gx := (VIEW_SIZE.x - grid_w) * 0.5
	var gy := 84.0
	for k in range(count):
		var real_index := start + k
		var node := _make_card_node(discard[real_index], true, real_index, _on_discard_gui_input.bind(real_index))
		var col := k % cols
		var row := int(k / float(cols))
		node.position = Vector2(gx + col * (CARD_W + gap), gy + row * (CARD_H + gap))
		_discard_root.add_child(node)


func _make_card_node(card: Dictionary, clickable: bool, index: int, on_gui := Callable()) -> Control:
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
		if on_gui.is_valid():
			panel.gui_input.connect(on_gui)
		else:
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
# ROLL READOUT (a line inside the info panel)
# ---------------------------------------------------------------------------
# Appends the roll readout (inline pip dice) into the info RichTextLabel.
func _append_roll_readout() -> void:
	if _last_dice.is_empty():
		_label.append_text("[font_size=22]Moving [b]%d[/b] spaces[/font_size]\n" % last_roll)
		return
	_label.append_text("[font_size=22]Rolled  [/font_size]")
	for v in _last_dice:
		if _die_tex.has(int(v)):
			_label.add_image(_die_tex[int(v)], 30, 30)
		_label.append_text(" ")
	_label.append_text("[font_size=22][b] =  %d[/b][/font_size]\n" % last_roll)


func _build_die_textures() -> void:
	for v in range(1, 7):
		_die_tex[v] = _make_die_texture(v)


func _make_die_texture(value: int) -> Texture2D:
	var s := 40
	var img := Image.create_empty(s, s, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.98, 0.98, 0.98))
	var dark := Color(0.12, 0.12, 0.12)
	for i in range(s):                        # 2px dark border
		img.set_pixel(i, 0, dark); img.set_pixel(i, 1, dark)
		img.set_pixel(i, s - 1, dark); img.set_pixel(i, s - 2, dark)
		img.set_pixel(0, i, dark); img.set_pixel(1, i, dark)
		img.set_pixel(s - 1, i, dark); img.set_pixel(s - 2, i, dark)
	for pc in PIP_LAYOUT[value]:              # pips
		_fill_circle(img, 10 + pc.x * 10, 10 + pc.y * 10, 4, dark)
	return ImageTexture.create_from_image(img)


func _fill_circle(img: Image, cx: int, cy: int, r: int, col: Color) -> void:
	for dy in range(-r, r + 1):
		for dx in range(-r, r + 1):
			if dx * dx + dy * dy <= r * r:
				var px := cx + dx
				var py := cy + dy
				if px >= 0 and px < img.get_width() and py >= 0 and py < img.get_height():
					img.set_pixel(px, py, col)
