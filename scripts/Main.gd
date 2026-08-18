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
var win_target := 8                          # errands needed to win (chosen on the start menu)
const CLICK_RADIUS := 26.0
const BRIDGE_REACH := 95.0                    # max span (view px) the bridge can bridge
const ZOOM_MIN := 0.5                        # zoom out far enough to see the whole board (even rotated)
const ZOOM_MAX := 6.0
const FIT_ZOOM := 1.0                        # zoom where the upright board fills the window
const CAM_KEEP_ON_SCREEN := 60.0             # min board px kept on screen (pan the rest off onto the felt)
const CAM_TIME := 0.35                        # seconds for a view button to glide the camera
const CAM_FOCUS_ZOOM := 3.0                    # zoom when focusing a player / Home
const DISTRICT_HIGHWAY_REACH := 170.0          # how far past a corner district to pull in the highway ring
const DISTRICT_PAD := 60.0                      # extra margin so the view sits slightly past the highway
const DISTRICT_CORNER_SCALE := 0.9             # ×fit zoom-out for the corner districts
const DT_PAD := 240.0                            # Downtown: frame its area wide to show the board's centre
# Hand tray: peeks at the bottom and slides up when the cursor nears the bottom edge.
const TRAY_HIDE_OFFSET := 92.0                  # how far the tray drops when hidden (view px)
const TRAY_REVEAL_FRAC := 0.22                  # cursor within this fraction of the bottom reveals it
const PAN_SPEED := 700.0
const STEP_TIME := 0.18                      # seconds per space while animating a move
const SLIDE_TIME := 0.8                       # seconds to slide a sent/swapped token
const TOKEN_ART_ANGLE := PI                  # art faces left, so flip 180° to face travel
const ERRAND_COPIES := 2                     # copies of each single-location errand in the deck
const AI_DELAY := 0.55                        # seconds the CPU "thinks" before each action
# Specials the CPU will Prevent (things that hurt it) and use to disrupt an opponent.
const AI_PREVENT_SET := ["to_beach", "to_lake", "get_music", "slow_traffic", "switcheroo", "road_hazard"]
const AI_DISRUPT_SET := ["to_beach", "to_lake", "get_music", "slow_traffic"]
# CPU difficulty (chosen on the start menu; stored per AI player as "difficulty").
const AI_EASY := 0
const AI_MEDIUM := 1
const AI_HARD := 2

# Multiplayer seat setup (start menu). Up to 6 seats; each seat has a mode and a
# colour. Seat mode: 0 Off · 1 Human · 2 CPU Easy · 3 CPU Normal · 4 CPU Hard.
const MAX_SEATS := 6
const SEAT_MODE_LABELS := ["Off", "Human", "CPU · Easy", "CPU · Normal", "CPU · Hard"]
# A small palette players pick from (kept visually distinct on the board).
const PLAYER_PALETTE := [
	{ "name": "Red", "color": Color(0.95, 0.27, 0.24) },
	{ "name": "Cyan", "color": Color(0.18, 0.82, 1.0) },
	{ "name": "Green", "color": Color(0.36, 0.82, 0.38) },
	{ "name": "Yellow", "color": Color(0.98, 0.84, 0.22) },
	{ "name": "Orange", "color": Color(0.99, 0.56, 0.16) },
	{ "name": "Magenta", "color": Color(0.93, 0.38, 0.85) },
	{ "name": "Blue", "color": Color(0.40, 0.53, 0.98) },
	{ "name": "White", "color": Color(0.92, 0.93, 0.97) },
]
var _seat_mode := [1, 3, 0, 0, 0, 0]             # default: P1 Human, P2 CPU Normal, rest Off
var _seat_color := [0, 1, 2, 3, 4, 5]            # palette index per seat
var _seat_mode_btns := []
var _seat_color_btns := []
var _color_popup: Control                        # the pop-out colour palette (menu)

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

# Duo errand cards: completable at EITHER location, and count as 2. Each has a
# finished card face (both locations + caption, 750×1050 like the standard faces).
var DUOS := [
	{ "locations": ["Pharmacy", "Forest"], "flavor": "Buy drugs, or pick your own?", "face": "res://assets/cards/duos/duos-drugs.png" },
	{ "locations": ["Post Office", "Port"], "flavor": "Pick up a package.", "face": "res://assets/cards/duos/duos-package.png" },
	{ "locations": ["Pawn Shop", "Jewelry"], "flavor": "Buy a gift for your fiancé.", "face": "res://assets/cards/duos/duos-gift.png" },
	{ "locations": ["Gym", "Park"], "flavor": "Get your exercise.", "face": "res://assets/cards/duos/duos-exercise.png" },
]

# Real card-face art for standard (single-location) errands, keyed by location.
# Each face is a finished design (district background + photo + title + caption),
# so when one exists we draw the image instead of the color-strip placeholder.
# Values are the available art variants; the deck's copies are spread across them.
const CARD_FACE_PATHS := {
	"Auto":         ["res://assets/cards/standard/Industry/card-industry-auto1.png", "res://assets/cards/standard/Industry/card-industry-auto2.png"],
	"Bank":         ["res://assets/cards/standard/Neighborhood/card-neighborhood-bank1.png", "res://assets/cards/standard/Neighborhood/card-neighborhood-bank2.png"],
	"Beach":        ["res://assets/cards/standard/Country/card-country-beach1.png", "res://assets/cards/standard/Country/card-country-beach2.png"],
	"Camping":      ["res://assets/cards/standard/Country/card-country-camping1.png", "res://assets/cards/standard/Country/card-country-camping2.png"],
	"Clinic":       ["res://assets/cards/standard/Downtown/card-downtown-clinic1.png", "res://assets/cards/standard/Downtown/card-downtown-clinic2.png"],
	"Dance":        ["res://assets/cards/standard/Mall/card-mall-dance1.png", "res://assets/cards/standard/Mall/card-mall-dance2.png"],
	"Factory":      ["res://assets/cards/standard/Industry/card-industry-factory1.png", "res://assets/cards/standard/Industry/card-industry-factory2.png"],
	"Fair":         ["res://assets/cards/standard/Downtown/card-downtown-fair1.png", "res://assets/cards/standard/Downtown/card-downtown-fair2.png"],
	"Farm":         ["res://assets/cards/standard/Country/card-country-farm1.png", "res://assets/cards/standard/Country/card-country-farm2.png"],
	"Fast Food":    ["res://assets/cards/standard/Industry/card-industry-fastfood1.png", "res://assets/cards/standard/Industry/card-industry-fastfood2.png"],
	"Forest":       ["res://assets/cards/standard/Country/card-country-forest1.png", "res://assets/cards/standard/Country/card-country-forest2.png"],
	"Gas":          ["res://assets/cards/standard/Downtown/card-downtown-gas1.png", "res://assets/cards/standard/Downtown/card-downtown-gas2.png"],
	"Grocery":      ["res://assets/cards/standard/Industry/card-industry-grocery1.png", "res://assets/cards/standard/Industry/card-industry-grocery2.png"],
	"Gym":          ["res://assets/cards/standard/Industry/card-industry-gym1.png", "res://assets/cards/standard/Industry/card-industry-gym2.png"],
	"Haircut":      ["res://assets/cards/standard/Mall/card-mall-haircut1.png", "res://assets/cards/standard/Mall/card-mall-haircut2.png"],
	"Hardware":     ["res://assets/cards/standard/Neighborhood/card-neighborhood-hardware1.png", "res://assets/cards/standard/Neighborhood/card-neighborhood-hardware2.png"],
	"Hats":         ["res://assets/cards/standard/Mall/card-mall-hats1.png", "res://assets/cards/standard/Mall/card-mall-hats2.png"],
	"Jewelry":      ["res://assets/cards/standard/Mall/card-mall-jewelry1.png", "res://assets/cards/standard/Mall/card-mall-jewelry2.png"],
	"Lake":         ["res://assets/cards/standard/Country/card-country-lake1.png", "res://assets/cards/standard/Country/card-country-lake2.png"],
	"Library":      ["res://assets/cards/standard/Downtown/card-downtown-library1.png", "res://assets/cards/standard/Downtown/card-downtown-library2.png"],
	"Mountain":     ["res://assets/cards/standard/Country/card-country-mountain1.png", "res://assets/cards/standard/Country/card-country-mountain2.png"],
	"Museum":       ["res://assets/cards/standard/Downtown/card-downtown-museum1.png", "res://assets/cards/standard/Downtown/card-downtown-museum2.png"],
	"Music":        ["res://assets/cards/standard/Mall/card-mall-music1.png", "res://assets/cards/standard/Mall/card-mall-music2.png"],
	"Offices":      ["res://assets/cards/standard/Downtown/card-downtown-offices1.png", "res://assets/cards/standard/Downtown/card-downtown-offices2.png"],
	"Park":         ["res://assets/cards/standard/Neighborhood/card-neighborhood-park1.png", "res://assets/cards/standard/Neighborhood/card-neighborhood-park2.png"],
	"Pawn Shop":    ["res://assets/cards/standard/Industry/card-industry-pawn1.png", "res://assets/cards/standard/Industry/card-industry-pawn2.png"],
	"Pets":         ["res://assets/cards/standard/Mall/card-mall-pets1.png", "res://assets/cards/standard/Mall/card-mall-pets2.png"],
	"Pharmacy":     ["res://assets/cards/standard/Downtown/card-downtown-pharmacy1.png", "res://assets/cards/standard/Downtown/card-downtown-pharmacy2.png"],
	"Police":       ["res://assets/cards/standard/Downtown/card-downtown-police1.png", "res://assets/cards/standard/Downtown/card-downtown-police2.png"],
	"Port":         ["res://assets/cards/standard/Industry/card-industry-port1.png", "res://assets/cards/standard/Industry/card-industry-port2.png"],
	"Post Office":  ["res://assets/cards/standard/Downtown/card-downtown-post1.png", "res://assets/cards/standard/Downtown/card-downtown-post2.png"],
	"School":       ["res://assets/cards/standard/Neighborhood/card-neighborhood-school1.png", "res://assets/cards/standard/Neighborhood/card-neighborhood-school2.png"],
	"Shoes":        ["res://assets/cards/standard/Mall/card-mall-shoes1.png", "res://assets/cards/standard/Mall/card-mall-shoes2.png"],
	"Toys":         ["res://assets/cards/standard/Mall/card-mall-toys1.png", "res://assets/cards/standard/Mall/card-mall-toys2.png"],
	"Worship":      ["res://assets/cards/standard/Neighborhood/card-neighborhood-worship1.png", "res://assets/cards/standard/Neighborhood/card-neighborhood-worship2.png"],
}

# Finished Special card faces, keyed by Special id (750×1050, like the other faces).
const SPECIAL_FACE_PATHS := {
	"lucky12":         "res://assets/cards/specials/cards-special-lucky12.png",
	"lucky20":         "res://assets/cards/specials/cards-special-lucky20.png",
	"lucky3":          "res://assets/cards/specials/cards-special-lucky3.png",
	"lucky2":          "res://assets/cards/specials/cards-special-lucky2.png",
	"free_turn":       "res://assets/cards/specials/cards-special-freeturn.png",
	"new_hand":        "res://assets/cards/specials/cards-special-hand.png",
	"to_beach":        "res://assets/cards/specials/cards-special-beach.png",
	"to_lake":         "res://assets/cards/specials/cards-special-lake.png",
	"get_music":       "res://assets/cards/specials/cards-special-music.png",
	"slow_traffic":    "res://assets/cards/specials/cards-special-traffic.png",
	"switcheroo":      "res://assets/cards/specials/cards-special-switcheroo.png",
	"road_hazard":     "res://assets/cards/specials/cards-special-block.png",
	"prevent":         "res://assets/cards/specials/cards-special-prevent.png",
	"thanks":          "res://assets/cards/specials/cards-special-thanks.png",
	"dumpster_diving": "res://assets/cards/specials/cards-special-dumpster.png",
	"shortcut":        "res://assets/cards/specials/cards-special-bridge.png",
}

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
var phase := "MENU"                          # MENU | SETUP | ROLL | MOVE | OVER
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
# Multiplayer Special targeting + reaction polling.
const TARGETED_SPECIALS := ["to_beach", "to_lake", "get_music", "slow_traffic", "switcheroo"]
var _sp_index := -1                            # hand index of the Special being played
var _sp_target := -1                           # chosen victim for a targeted Special (or -1)
var _react_queue := []                          # opponents still to be offered a Prevent
var _thanks_queue := []                         # opponents still to be offered Thanks
var _thanks_loc := ""                           # location that triggered the Thanks poll

var _board_tex: Texture2D
var _blockade_tex: Texture2D
var _token_gray_tex: Texture2D                  # desaturated car, tinted per player
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
var _view_layer: CanvasLayer                    # view-control buttons (focus player / district…)
var _view_root: Control
var _follow_btn: Button
var _follow_active := false                      # camera auto-centers on the current player
var _cam_tween: Tween                            # active view-button camera glide
var _rot_tween: Tween                            # active board-rotation glide
var _cam_rot_target := 0.0                       # target camera rotation (radians)
var _table_layer: CanvasLayer                     # green "card table" behind the board
var _hud_layer: CanvasLayer                       # info panel + banner (top-left / centre)
var _score_layer: CanvasLayer                     # scoreboard (top-right, own layer so it hugs the edge)
var _btn_layer: CanvasLayer                       # the ☰ menu button
var _menu_dim: ColorRect                           # start-menu tint (kept full-window)
var _pause_dim: ColorRect                          # pause-menu tint (kept full-window)
var _animating := false
var _card_face_cache := {}                       # location name -> loaded Texture2D (or null)
var _card_layer: CanvasLayer
var _card_row: Control
var _discard_layer: CanvasLayer
var _discard_root: Control
var _action_layer: CanvasLayer                  # contextual action buttons (Roll, reactions, etc.)
var _action_root: Control
var _dd_held := {}                            # the Dumpster Diving card held aside while picking
var _menu_layer: CanvasLayer                   # start menu overlay
var _debug_mode := false                       # true = debug shortcuts (e.g. G) enabled
var _pause_layer: CanvasLayer                   # in-game pause overlay
var _menu_button: Button                        # in-game "Menu" button
var _move_tween: Tween                          # active movement/slide tween (killed on restart)
var _paused := false                            # in-game pause menu is open
var _ai_scheduled := false                      # a CPU action is queued on a timer
var _ai_turn_plays := 0                          # Specials the CPU has played this turn (loop guard)


func _ready() -> void:
	randomize()
	_board_tex = load("res://assets/board.png")
	_blockade_tex = load("res://assets/blockade.png")
	_bridge_tex = load("res://assets/bridge.png")
	_build_table_background()                  # green table, behind everything
	_bridge_sprite = Sprite2D.new()
	_bridge_sprite.texture = _bridge_tex
	_bridge_sprite.visible = false
	add_child(_bridge_sprite)                  # drawn above the board, below tokens
	_build_die_textures()
	_setup_camera()
	_build_hud()
	_build_card_bar()
	_build_menu()
	_build_pause_ui()
	_build_view_controls()
	get_viewport().size_changed.connect(_apply_safe_offset)
	_apply_safe_offset()
	phase = "MENU"
	queue_redraw()


# Called from the start menu (Play = normal, Debug Mode = debug shortcuts on).
func _start_game(debug: bool) -> void:
	var active := 0
	for m in _seat_mode:
		if m != 0:
			active += 1
	if active < 2:
		return                                     # need at least two players to start
	_debug_mode = debug
	_menu_layer.visible = false
	_menu_button.visible = true
	_view_layer.visible = true
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
	_layout_scoreboard()
	_populate_view_controls()
	_update_token_positions()
	phase = "ROLL"
	_update_hud()
	queue_redraw()


# Grow the top-right scoreboard panel to fit however many players are in the game,
# and slide the ☰ Menu button below it so they don't overlap.
func _layout_scoreboard() -> void:
	var rows := players.size() + 1                 # header + one row per player
	var line := 26.0                                # generous per-row height so nothing clips
	var h := rows * line + 18.0
	if _scoreboard != null:
		_scoreboard.add_theme_font_size_override("normal_font_size", 17)
		_scoreboard.add_theme_font_size_override("bold_font_size", 17)
		_scoreboard.position = Vector2(VIEW_SIZE.x - 242, 14)
		_scoreboard.size = Vector2(222, h - 12)
	if _score_bg != null:
		_score_bg.size = Vector2(244, h)
	if _menu_button != null:
		_menu_button.position = Vector2(VIEW_SIZE.x - 114, 8 + h + 6)


func _on_quit() -> void:
	get_tree().quit()


func _build_menu() -> void:
	_menu_layer = CanvasLayer.new()
	_menu_layer.layer = 4
	add_child(_menu_layer)

	var bg := ColorRect.new()
	bg.color = Color(0.03, 0.04, 0.07, 0.82)
	bg.position = Vector2.ZERO
	bg.size = VIEW_SIZE
	bg.mouse_filter = Control.MOUSE_FILTER_STOP     # swallow clicks (blocks board pan/zoom)
	_menu_layer.add_child(bg)
	_menu_dim = bg

	var title := Label.new()
	title.text = "ERRANDS"
	title.add_theme_font_size_override("font_size", 56)
	title.add_theme_color_override("font_color", Color(1, 0.95, 0.5))
	title.add_theme_color_override("font_outline_color", Color.BLACK)
	title.add_theme_constant_override("outline_size", 8)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.position = Vector2(0, 34)
	title.size = Vector2(VIEW_SIZE.x, 72)
	_menu_layer.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "drive around town · do your errands · get home"
	subtitle.add_theme_font_size_override("font_size", 19)
	subtitle.add_theme_color_override("font_color", Color(0.85, 0.88, 0.95))
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.position = Vector2(0, 106)
	subtitle.size = Vector2(VIEW_SIZE.x, 28)
	_menu_layer.add_child(subtitle)

	# Win-target picker.
	_menu_layer.add_child(_menu_heading("Errands to win", 150))
	var opts := [3, 5, 8, 10]
	var bw := 62.0
	var gap := 14.0
	var total := opts.size() * bw + (opts.size() - 1) * gap
	var sx := (VIEW_SIZE.x - total) * 0.5
	var group := ButtonGroup.new()
	for i in range(opts.size()):
		var v: int = opts[i]
		var b := Button.new()
		b.text = str(v)
		b.toggle_mode = true
		b.button_group = group
		b.button_pressed = (v == win_target)
		b.add_theme_font_size_override("font_size", 22)
		b.custom_minimum_size = Vector2(bw, 46)
		b.size = Vector2(bw, 46)
		b.position = Vector2(sx + i * (bw + gap), 182)
		b.pressed.connect(_set_win_target.bind(v))
		_menu_layer.add_child(b)

	# Seat setup: one row per seat — a colour swatch and a mode button.
	_menu_layer.add_child(_menu_heading("Players", 246))
	_seat_mode_btns.clear()
	_seat_color_btns.clear()
	var row_w := 300.0
	var swatch_w := 46.0
	var rgap := 8.0
	var rx := (VIEW_SIZE.x - row_w) * 0.5
	for i in range(MAX_SEATS):
		var ry := 284.0 + i * 44.0
		var sw := Button.new()
		sw.custom_minimum_size = Vector2(swatch_w, 38)
		sw.size = Vector2(swatch_w, 38)
		sw.position = Vector2(rx, ry)
		sw.pressed.connect(_open_color_popup.bind(i))
		_menu_layer.add_child(sw)
		_seat_color_btns.append(sw)
		var mb := Button.new()
		mb.add_theme_font_size_override("font_size", 20)
		mb.custom_minimum_size = Vector2(row_w - swatch_w - rgap, 38)
		mb.size = Vector2(row_w - swatch_w - rgap, 38)
		mb.position = Vector2(rx + swatch_w + rgap, ry)
		mb.pressed.connect(_cycle_seat_mode.bind(i))
		_menu_layer.add_child(mb)
		_seat_mode_btns.append(mb)
		_refresh_seat_row(i)

	_menu_layer.add_child(_make_menu_button("Play", 566, _start_game.bind(false)))
	_menu_layer.add_child(_make_menu_button("Debug Mode", 634, _start_game.bind(true)))
	_menu_layer.add_child(_make_menu_button("Quit", 702, _on_quit))


func _menu_heading(text: String, y: float) -> Label:
	var lb := Label.new()
	lb.text = text
	lb.add_theme_font_size_override("font_size", 22)
	lb.add_theme_color_override("font_color", Color(0.9, 0.92, 0.98))
	lb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lb.position = Vector2(0, y)
	lb.size = Vector2(VIEW_SIZE.x, 28)
	return lb


func _set_win_target(v: int) -> void:
	win_target = v


func _cycle_seat_mode(i: int) -> void:
	_seat_mode[i] = (_seat_mode[i] + 1) % SEAT_MODE_LABELS.size()
	if _seat_mode[i] != 0:
		_ensure_unique_color(i)                      # newly-active seat gets a free colour
	_refresh_seat_row(i)


func _ensure_unique_color(i: int) -> void:
	var used := {}
	for j in range(MAX_SEATS):
		if j != i and _seat_mode[j] != 0:
			used[_seat_color[j]] = true
	if used.has(_seat_color[i]):
		for idx in range(PLAYER_PALETTE.size()):
			if not used.has(idx):
				_seat_color[i] = idx
				break


# Pop out the full colour palette for a seat so the player can see every option.
func _open_color_popup(seat: int) -> void:
	if seat < 0 or seat >= MAX_SEATS or _seat_mode[seat] == 0:
		return
	_close_color_popup()
	_color_popup = Control.new()
	_color_popup.size = VIEW_SIZE
	_menu_layer.add_child(_color_popup)

	var shade := Button.new()                        # click outside the panel to close
	shade.flat = true
	shade.size = VIEW_SIZE
	var shsb := StyleBoxFlat.new()
	shsb.bg_color = Color(0, 0, 0, 0.55)
	for st in ["normal", "hover", "pressed", "focus"]:
		shade.add_theme_stylebox_override(st, shsb)
	shade.pressed.connect(_close_color_popup)
	_color_popup.add_child(shade)

	var cols := 4
	var cw := 74.0
	var ch := 58.0
	var cg := 12.0
	var pw := cols * cw + (cols - 1) * cg + 32.0
	var ph := 64.0 + 2 * ch + cg + 16.0
	var panel := Panel.new()
	panel.position = ((VIEW_SIZE - Vector2(pw, ph)) * 0.5).round()
	panel.size = Vector2(pw, ph)
	var psb := StyleBoxFlat.new()
	psb.bg_color = Color(0.10, 0.12, 0.16, 0.98)
	psb.set_corner_radius_all(10)
	psb.set_border_width_all(2)
	psb.border_color = Color(1, 1, 1, 0.25)
	panel.add_theme_stylebox_override("panel", psb)
	_color_popup.add_child(panel)

	var title := Label.new()
	title.text = "Seat %d colour" % (seat + 1)
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", Color(0.95, 0.97, 1.0))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.position = Vector2(0, 14)
	title.size = Vector2(pw, 30)
	panel.add_child(title)

	var gw := cols * cw + (cols - 1) * cg
	var gx := (pw - gw) * 0.5
	var gy := 54.0
	for idx in range(PLAYER_PALETTE.size()):
		var taken := false
		for j in range(MAX_SEATS):
			if j != seat and _seat_mode[j] != 0 and _seat_color[j] == idx:
				taken = true
				break
		var cb := Button.new()
		var col := idx % cols
		@warning_ignore("integer_division")
		var row := idx / cols
		cb.position = Vector2(gx + col * (cw + cg), gy + row * (ch + cg))
		cb.custom_minimum_size = Vector2(cw, ch)
		cb.size = Vector2(cw, ch)
		var cbsb := StyleBoxFlat.new()
		cbsb.bg_color = PLAYER_PALETTE[idx]["color"]
		cbsb.set_corner_radius_all(6)
		cbsb.set_border_width_all(4 if idx == _seat_color[seat] else 2)
		cbsb.border_color = Color(1, 1, 0.4) if idx == _seat_color[seat] else Color(0, 0, 0, 0.45)
		for st in ["normal", "hover", "pressed", "focus"]:
			cb.add_theme_stylebox_override(st, cbsb)
		if taken:
			cb.disabled = true
			cb.modulate = Color(1, 1, 1, 0.3)
		else:
			cb.pressed.connect(_pick_seat_color.bind(seat, idx))
		panel.add_child(cb)


func _pick_seat_color(seat: int, idx: int) -> void:
	_seat_color[seat] = idx
	_refresh_seat_row(seat)
	_close_color_popup()


func _close_color_popup() -> void:
	if _color_popup != null and is_instance_valid(_color_popup):
		_color_popup.queue_free()
	_color_popup = null


func _refresh_seat_row(i: int) -> void:
	var mb: Button = _seat_mode_btns[i]
	mb.text = "Seat %d:  %s" % [i + 1, SEAT_MODE_LABELS[_seat_mode[i]]]
	var off: bool = _seat_mode[i] == 0
	mb.add_theme_color_override("font_color", Color(0.6, 0.63, 0.7) if off else Color(0.95, 0.97, 1.0))
	var sw: Button = _seat_color_btns[i]
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.2, 0.2, 0.24) if off else PLAYER_PALETTE[_seat_color[i]]["color"]
	sb.set_corner_radius_all(6)
	sb.set_border_width_all(2)
	sb.border_color = Color(1, 1, 1, 0.35)
	sw.add_theme_stylebox_override("normal", sb)
	sw.add_theme_stylebox_override("hover", sb)
	sw.add_theme_stylebox_override("pressed", sb)


func _make_menu_button(text: String, y: float, on_press: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", 28)
	b.custom_minimum_size = Vector2(320, 60)
	b.size = Vector2(320, 60)
	b.position = Vector2((VIEW_SIZE.x - 320) * 0.5, y)
	b.pressed.connect(on_press)
	return b


func _build_pause_ui() -> void:
	# The in-game "Menu" button (top-right, below the scoreboard).
	var btn_layer := CanvasLayer.new()
	btn_layer.layer = 3
	add_child(btn_layer)
	_btn_layer = btn_layer
	_menu_button = Button.new()
	_menu_button.text = "☰ Menu"
	_menu_button.add_theme_font_size_override("font_size", 18)
	_menu_button.size = Vector2(104, 36)
	_menu_button.position = Vector2(VIEW_SIZE.x - 114, 122)
	_menu_button.visible = false
	_menu_button.pressed.connect(_open_pause)
	btn_layer.add_child(_menu_button)

	# The pause overlay (works while the tree is paused).
	_pause_layer = CanvasLayer.new()
	_pause_layer.layer = 5
	_pause_layer.visible = false
	add_child(_pause_layer)

	var bg := ColorRect.new()
	bg.color = Color(0.03, 0.04, 0.07, 0.85)
	bg.position = Vector2.ZERO
	bg.size = VIEW_SIZE
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	_pause_layer.add_child(bg)
	_pause_dim = bg

	var title := Label.new()
	title.text = "Paused"
	title.add_theme_font_size_override("font_size", 48)
	title.add_theme_color_override("font_color", Color(1, 0.95, 0.5))
	title.add_theme_color_override("font_outline_color", Color.BLACK)
	title.add_theme_constant_override("outline_size", 6)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.position = Vector2(0, 300)
	title.size = Vector2(VIEW_SIZE.x, 60)
	_pause_layer.add_child(title)

	_pause_layer.add_child(_make_menu_button("Resume", 430, _on_resume))
	_pause_layer.add_child(_make_menu_button("Restart", 506, _on_restart))
	_pause_layer.add_child(_make_menu_button("Back to Main Menu", 582, _on_back_to_menu))


func _open_pause() -> void:
	if phase == "MENU" or _paused:
		return
	_paused = true
	_pause_layer.visible = true
	if _move_tween != null and _move_tween.is_valid():
		_move_tween.pause()            # freeze any in-flight token move


func _on_resume() -> void:
	_paused = false
	_pause_layer.visible = false
	if _move_tween != null and _move_tween.is_valid():
		_move_tween.play()
	_ai_tick()                              # a CPU action may have been waiting on the pause


func _on_restart() -> void:
	_paused = false
	_pause_layer.visible = false
	_reset_game()


func _on_back_to_menu() -> void:
	get_tree().reload_current_scene()

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
			# Spread the copies across the available art variants (0, 1, …).
			deck.append({ "type": "errand", "locations": [loc], "count": 1, "flavor": "", "face_variant": i })
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
	# Build the active players from the seat setup. "tint" is each player's identity
	# colour (token + halo + HUD); the seat mode gives Human vs CPU-difficulty.
	players = []
	for seat in range(MAX_SEATS):
		var mode: int = _seat_mode[seat]
		if mode == 0:
			continue
		var is_ai: bool = mode >= 2
		var diff: int = (mode - 2) if is_ai else AI_MEDIUM
		var n := players.size() + 1
		var nm := ("CPU %d" % n) if is_ai else ("Player %d" % n)
		players.append({
			"name": nm, "tint": PLAYER_PALETTE[_seat_color[seat]]["color"],
			"color_idx": _seat_color[seat], "space": home_id, "hand": [],
			"completed": 0, "skip_turns": 0, "slow_turns": 0, "is_ai": is_ai, "difficulty": diff,
		})
	for p in players:
		for i in range(7):
			p["hand"].append(_draw_card())


func _build_tokens() -> void:
	# The car art is red; desaturate it once so it can be tinted to any player colour.
	if _token_gray_tex == null:
		_token_gray_tex = _grayscale_texture(load("res://assets/player.png"))
	for i in range(players.size()):
		var spr := Sprite2D.new()
		spr.texture = _token_gray_tex
		spr.scale = Vector2(TOKEN_SCALE, TOKEN_SCALE)
		spr.modulate = players[i]["tint"]
		add_child(spr)
		tokens.append(spr)


# A desaturated (and brightened) copy of `tex` so `modulate` recolours it cleanly.
func _grayscale_texture(tex: Texture2D) -> Texture2D:
	var img := tex.get_image()
	img.convert(Image.FORMAT_RGBA8)
	for y in range(img.get_height()):
		for x in range(img.get_width()):
			var c := img.get_pixel(x, y)
			if c.a <= 0.0:
				continue
			var l := 0.30 * c.r + 0.59 * c.g + 0.11 * c.b
			l = clampf(0.30 + l * 0.78, 0.0, 1.0)     # lift so tints stay vivid
			img.set_pixel(x, y, Color(l, l, l, c.a))
	return ImageTexture.create_from_image(img)


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
	_hud_layer = layer

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

	# Top-right scoreboard panel (all players, always visible). On its own layer so
	# it can hug the window's right edge independently of the top-left info panel.
	var score_layer := CanvasLayer.new()
	score_layer.layer = 1
	add_child(score_layer)
	_score_layer = score_layer
	_score_bg = _make_hud_panel(Vector2(VIEW_SIZE.x - 254, 8), Vector2(244, 108))
	score_layer.add_child(_score_bg)
	_scoreboard = RichTextLabel.new()
	_scoreboard.bbcode_enabled = true
	_scoreboard.scroll_active = false
	_scoreboard.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_scoreboard.add_theme_font_size_override("normal_font_size", 20)
	_scoreboard.add_theme_font_size_override("bold_font_size", 20)
	_scoreboard.add_theme_color_override("default_color", Color(0.93, 0.95, 0.99))
	_scoreboard.position = Vector2(VIEW_SIZE.x - 242, 16)
	_scoreboard.size = Vector2(222, 92)
	score_layer.add_child(_scoreboard)


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
	_camera.ignore_rotation = false     # apply the camera's rotation (so Rotate L/R works)
	_camera.enabled = true
	add_child(_camera)


# A green "card table" that fills the screen behind the board, so panning/rotating
# past the board edges shows felt rather than a grey void.
func _build_table_background() -> void:
	_table_layer = CanvasLayer.new()
	_table_layer.layer = -10                    # behind the board and everything else
	add_child(_table_layer)
	var felt := ColorRect.new()
	felt.color = Color(0.09, 0.34, 0.16)        # dark green felt
	felt.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)   # always fill the viewport
	felt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_table_layer.add_child(felt)


# The actual viewport size (varies with window shape under stretch "expand").
func _vp() -> Vector2:
	return get_viewport_rect().size


# Anchor each in-game HUD group to its own window edge (rather than floating the
# whole HUD in a central 720×1080 "safe area"): the top-left panel hugs the top-left
# corner, the scoreboard / ☰ Menu / view toolbar hug the top-right, the hand and
# action buttons sit along the bottom, and overlays/menus stay centred. The board is
# camera-centred and green felt fills whatever is left.
func _apply_safe_offset() -> void:
	var vp := _vp()
	var dx := roundf(vp.x - VIEW_SIZE.x)          # safe-area right edge → window right edge
	var dy := roundf(vp.y - VIEW_SIZE.y)          # safe-area bottom edge → window bottom edge
	var cx := roundf(dx * 0.5)
	var cy := roundf(dy * 0.5)
	_place_layer(_hud_layer, Vector2.ZERO)          # info panel — top-left
	_place_layer(_score_layer, Vector2(dx, 0.0))    # scoreboard — top-right
	_place_layer(_btn_layer, Vector2(dx, 0.0))      # ☰ Menu — top-right
	_place_layer(_view_layer, Vector2(dx, 0.0))     # view toolbar — top-right
	_place_layer(_card_layer, Vector2(cx, dy))      # hand — bottom-centre
	_place_layer(_action_layer, Vector2(cx, dy))    # action buttons — bottom-centre
	_place_layer(_discard_layer, Vector2(cx, cy))   # discard picker — centre
	_place_layer(_menu_layer, Vector2(cx, cy))      # start menu — centre
	_place_layer(_pause_layer, Vector2(cx, cy))     # pause menu — centre
	# The big centred announcement banner rides the top-left HUD layer; nudge it back
	# to the middle of the window.
	if _banner != null and is_instance_valid(_banner):
		_banner.position = Vector2(40.0 + cx, cy)
	# The menu/pause tints live on centred layers but must cover (and block input on)
	# the WHOLE window — position them to counter the offset and fill the viewport.
	for dim in [_menu_dim, _pause_dim]:
		if dim != null and is_instance_valid(dim):
			dim.position = Vector2(-cx, -cy)
			dim.size = vp


# Set a CanvasLayer's screen offset, guarding against not-yet-built layers.
func _place_layer(lyr: CanvasLayer, off: Vector2) -> void:
	if lyr != null and is_instance_valid(lyr):
		lyr.offset = off

# ---------------------------------------------------------------------------
# INPUT
# ---------------------------------------------------------------------------
func _unhandled_input(event: InputEvent) -> void:
	# Esc toggles the in-game pause menu (never on the start menu).
	if phase != "MENU" and event is InputEventKey and event.pressed and not event.echo \
			and event.keycode == KEY_ESCAPE:
		if _paused:
			_on_resume()
		else:
			_open_pause()
		return
	if _paused or phase == "MENU":
		return                              # frozen while a menu (pause or start) is open

	# Camera controls work in every phase.
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			_zoom_by(1.15); return
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			_zoom_by(1.0 / 1.15); return
		elif event.button_index == MOUSE_BUTTON_MIDDLE:
			_panning = event.pressed; return
	elif event is InputEventMouseMotion and _panning and not _follow_active:
		_kill_cam_tween()
		_camera.position -= (event.relative / _camera.zoom.x).rotated(_camera.rotation)
		_clamp_camera(); return

	# Ignore gameplay input while a move is animating.
	if _animating:
		return

	# New Hand is waiting for a Discard/Swap choice.
	if _pending == "newhand_choice":
		if event is InputEventKey and event.pressed and not event.echo:
			if event.keycode == KEY_D:
				_newhand_discard()
			elif event.keycode == KEY_S:
				_newhand_choose_swap()
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

	# DEBUG MODE: press G on your turn to load a hand full of Specials for testing.
	if _debug_mode and event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_G:
		_debug_special_hand()
		return

	# Any other pending prompt (e.g. choosing a target) blocks roll/move input.
	if _pending != "":
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
	if _camera == null or _paused or phase == "MENU":
		return
	if _follow_active:
		_follow_step(delta)             # camera glued to the current player
	else:
		var v := Vector2.ZERO
		if Input.is_key_pressed(KEY_LEFT):  v.x -= 1
		if Input.is_key_pressed(KEY_RIGHT): v.x += 1
		if Input.is_key_pressed(KEY_UP):    v.y -= 1
		if Input.is_key_pressed(KEY_DOWN):  v.y += 1
		if v != Vector2.ZERO:
			_kill_cam_tween()
			_camera.position += (v.normalized().rotated(_camera.rotation)) * PAN_SPEED * delta / _camera.zoom.x
			_clamp_camera()
	_update_card_tray(delta)
	# Keep the active-player indicator glued to the token as it drives.
	if _animating:
		queue_redraw()


# Slide the hand tray up when the cursor nears the bottom edge; otherwise let it
# rest low, peeking, so it doesn't cover the board.
func _update_card_tray(delta: float) -> void:
	if _card_row == null:
		return
	var vp := get_viewport_rect().size
	var frac := get_viewport().get_mouse_position().y / maxf(vp.y, 1.0)
	var want := frac > (1.0 - TRAY_REVEAL_FRAC)
	if _pending == "lucky2_discard":
		want = true                          # must be able to click a card to discard
	var target := 0.0 if want else TRAY_HIDE_OFFSET
	_card_row.position.y = lerpf(_card_row.position.y, target, clampf(delta * 12.0, 0.0, 1.0))


func _zoom_by(factor: float) -> void:
	_kill_cam_tween()
	# Keep the world point under the cursor fixed (works under any rotation).
	var before := get_global_mouse_position()
	var new_zoom := clampf(_camera.zoom.x * factor, ZOOM_MIN, ZOOM_MAX)
	_camera.zoom = Vector2(new_zoom, new_zoom)
	var after := get_global_mouse_position()
	_camera.position += before - after
	_clamp_camera()
	queue_redraw()


func _clamp_camera() -> void:
	# Let the board be panned almost entirely off-screen (felt fills the rest), while
	# always keeping a sliver on screen so it's never fully lost. Zoom/window-aware.
	var half := (_vp() * 0.5) / _camera.zoom.x
	var keep := CAM_KEEP_ON_SCREEN
	_camera.position.x = clampf(_camera.position.x, keep - half.x, VIEW_SIZE.x - keep + half.x)
	_camera.position.y = clampf(_camera.position.y, keep - half.y, VIEW_SIZE.y - keep + half.y)

# ---------------------------------------------------------------------------
# VIEW CONTROLS (camera focus buttons)
# ---------------------------------------------------------------------------
func _build_view_controls() -> void:
	_view_layer = CanvasLayer.new()
	_view_layer.layer = 3
	_view_layer.visible = false
	add_child(_view_layer)
	_view_root = Control.new()
	_view_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_view_layer.add_child(_view_root)


# (Re)build the view toolbar in three labelled sections: camera controls (rotate /
# fit / follow), board views (Home + districts), and one focus button per player.
func _populate_view_controls() -> void:
	if _view_root == null:
		return
	for c in _view_root.get_children():
		c.queue_free()
	var bh := 28.0
	# Size every button to one uniform width, wide enough to show the longest label
	# (incl. "Follow: Off" and player names) in full — no clipping, no ragged edges.
	var labels := ["Rotate L", "Rotate R", "Fit Board", "Follow: Off", "Home",
		"Mall", "Downtown", "Industry", "Country", "Neighborhood"]
	for i in range(players.size()):
		labels.append(("CPU %d" % (i + 1)) if players[i]["is_ai"] else ("Player %d" % (i + 1)))
	var bw := _view_button_width(labels)
	var x := VIEW_SIZE.x - bw - 8.0
	var y := (_menu_button.position.y + 44.0) if _menu_button != null else 164.0   # below the ☰ button

	# Section 1 — camera controls (Rotate L/R, Fit Board, Follow toggle).
	y = _view_section_header(x, bw, y, "Camera")
	y = _add_view_buttons(x, bw, bh, y, [
		["Rotate L", _rotate_view.bind(-1), Color(0.82, 0.88, 1.0)],
		["Rotate R", _rotate_view.bind(1), Color(0.82, 0.88, 1.0)],
		["Fit Board", _fit_board, Color(0.92, 0.94, 0.99)],
	])
	_follow_btn = Button.new()
	_follow_btn.text = "Follow: Off"
	_follow_btn.toggle_mode = true
	_follow_btn.add_theme_font_size_override("font_size", 14)
	_follow_btn.custom_minimum_size = Vector2(bw, bh)
	_follow_btn.size = Vector2(bw, bh)
	_follow_btn.position = Vector2(x, y)
	_follow_btn.toggled.connect(_toggle_follow)
	_view_root.add_child(_follow_btn)
	y += bh

	# Section 2 — board views (Home + the five districts).
	var views := [["Home", _focus_home, Color(0.55, 0.95, 0.6)]]
	for d in [["Mall", "mall"], ["Downtown", "dt"], ["Industry", "ind"], ["Country", "cty"], ["Neighborhood", "nbhd"]]:
		views.append([d[0], _focus_district.bind(d[1]), DISTRICT_COLORS[d[1]].lightened(0.25)])
	y = _view_section_header(x, bw, y, "Views")
	y = _add_view_buttons(x, bw, bh, y, views)

	# Section 3 — one focus button per active player, coloured to match.
	var seats := []
	for i in range(players.size()):
		var label := ("CPU %d" % (i + 1)) if players[i]["is_ai"] else ("Player %d" % (i + 1))
		seats.append([label, _focus_player.bind(i), Color(players[i]["tint"]).lightened(0.15)])
	y = _view_section_header(x, bw, y, "Players")
	_add_view_buttons(x, bw, bh, y, seats)


# Uniform view-button width: the widest label rendered at font size 14, plus padding
# for the button's inner margins, so no label is ever clipped or shortened.
func _view_button_width(labels: Array) -> float:
	var probe := Button.new()
	var font := probe.get_theme_font("font")
	if font == null:
		font = ThemeDB.fallback_font
	var w := 60.0
	for t in labels:
		w = maxf(w, font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x)
	probe.free()
	return ceilf(w) + 22.0


# Add a stack of view-toolbar buttons top-to-bottom; returns the y below the last one.
# Each entry is [text, Callable, font Color].
func _add_view_buttons(x: float, bw: float, bh: float, y: float, entries: Array) -> float:
	for e in entries:
		var b := Button.new()
		b.text = e[0]
		b.add_theme_font_size_override("font_size", 14)
		b.custom_minimum_size = Vector2(bw, bh)
		b.size = Vector2(bw, bh)
		b.position = Vector2(x, y)
		b.add_theme_color_override("font_color", e[2])
		b.pressed.connect(e[1])
		_view_root.add_child(b)
		y += bh + 2.0                                # tight, even spacing
	return y


# A small section heading with a divider line above it (skipped for the first one);
# returns the y where the section's buttons should start.
func _view_section_header(x: float, bw: float, y: float, text: String) -> float:
	if _view_root.get_child_count() > 0:
		y += 8.0                                     # breathing room between sections
		var line := ColorRect.new()
		line.color = Color(1, 1, 1, 0.20)
		line.position = Vector2(x, y)
		line.size = Vector2(bw, 2.0)
		line.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_view_root.add_child(line)
		y += 6.0
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 12)
	lbl.add_theme_color_override("font_color", Color(0.75, 0.80, 0.90))
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lbl.position = Vector2(x + 2.0, y)
	lbl.size = Vector2(bw, 16.0)
	_view_root.add_child(lbl)
	return y + 18.0


func _kill_cam_tween() -> void:
	if _cam_tween != null and _cam_tween.is_valid():
		_cam_tween.kill()


# Glide the camera so `center` sits in the middle of the screen at `zoom`.
func _camera_focus(center: Vector2, zoom: float) -> void:
	if _camera == null:
		return
	zoom = clampf(zoom, ZOOM_MIN, ZOOM_MAX)
	var c := center                              # focus targets are board points already
	_kill_cam_tween()
	_cam_tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_cam_tween.tween_property(_camera, "position", c, CAM_TIME)
	_cam_tween.tween_property(_camera, "zoom", Vector2(zoom, zoom), CAM_TIME)


func _follow_off() -> void:
	if not _follow_active:
		return
	_follow_active = false
	if _follow_btn != null:
		_follow_btn.set_pressed_no_signal(false)
		_follow_btn.text = "Follow: Off"


func _toggle_follow(pressed: bool) -> void:
	_follow_active = pressed
	_follow_btn.text = "Follow: On" if pressed else "Follow: Off"
	if pressed:
		_kill_cam_tween()


# Called each frame while Follow is on: ease the camera toward the current token.
func _follow_step(delta: float) -> void:
	if tokens.is_empty() or current >= tokens.size():
		return
	var target: Vector2 = tokens[current].position   # tokens are on the board, so no clamp needed
	_camera.position = _camera.position.lerp(target, clampf(delta * 6.0, 0.0, 1.0))


func _fit_board() -> void:
	_follow_off()
	_camera_focus(VIEW_SIZE * 0.5, FIT_ZOOM)


# Smoothly rotate the whole board view a quarter-turn (dir -1 = left, +1 = right).
func _rotate_view(dir: int) -> void:
	_cam_rot_target += dir * (PI / 2.0)
	if _rot_tween != null and _rot_tween.is_valid():
		_rot_tween.kill()
	_rot_tween = create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_rot_tween.tween_property(_camera, "rotation", _cam_rot_target, 0.4)


func _focus_home() -> void:
	if not board.has(home_id):
		return
	_follow_off()
	_camera_focus(board[home_id]["pos"], CAM_FOCUS_ZOOM)


func _focus_player(i: int) -> void:
	if i < 0 or i >= tokens.size():
		return
	_follow_off()
	_camera_focus(tokens[i].position, CAM_FOCUS_ZOOM)


func _focus_district(code: String) -> void:
	# Frame the district's location spaces, then extend the box to take in the
	# nearby highway ring so the view reaches slightly past the highway (and, for
	# the central Downtown, shows a wide slice of the board's middle).
	var mn := Vector2(INF, INF)
	var mx := Vector2(-INF, -INF)
	var pts := []
	for id in board:
		if board[id]["kind"] != "location":
			continue
		if DISTRICT_OF.get(board[id]["name"], "") != code:
			continue
		var p: Vector2 = board[id]["pos"]
		pts.append(p)
		mn = mn.min(p)
		mx = mx.max(p)
	if pts.is_empty():
		return
	_follow_off()
	# Downtown is ringed by the highway on all sides, so pulling in the ring would
	# just show the whole board. Instead frame its own area wide → a central slice.
	if code == "dt":
		var span_c := (mx - mn) + Vector2(DT_PAD, DT_PAD)
		var zoom_c := minf(_vp().x / maxf(span_c.x, 1.0), _vp().y / maxf(span_c.y, 1.0))
		_camera_focus((mn + mx) * 0.5, zoom_c)
		return
	# Corner districts: extend the box to include the nearby highway ring, then a
	# little more, so the view sits slightly past the highway.
	var center := (mn + mx) * 0.5
	var radius := 0.0
	for p in pts:
		radius = maxf(radius, center.distance_to(p))
	var reach := radius + DISTRICT_HIGHWAY_REACH
	for id in board:
		if board[id]["kind"] != "highway":
			continue
		var hp: Vector2 = board[id]["pos"]
		if center.distance_to(hp) <= reach:
			mn = mn.min(hp)
			mx = mx.max(hp)
	var span := (mx - mn) + Vector2(DISTRICT_PAD, DISTRICT_PAD)
	var fit := minf(_vp().x / maxf(span.x, 1.0), _vp().y / maxf(span.y, 1.0))
	_camera_focus((mn + mx) * 0.5, fit * DISTRICT_CORNER_SCALE)


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
	_move_tween = tw
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
	var o: int = int(_reaction.get("reactor", _target_player()))
	var loc: String = _thanks_loc
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
	if not _thanks_queue.is_empty():
		_thanks_queue.pop_front()             # this player answered — offer the next one
	_next_thanks_reactor()


# Offer Thanks to each queued opponent; when none remain, resume the turn-end.
func _next_thanks_reactor() -> void:
	while not _thanks_queue.is_empty():
		var pi: int = _thanks_queue[0]
		if _has_card(players[pi], "thanks") and _find_errand(players[pi], _thanks_loc) != -1:
			_reaction = { "reactor": pi }
			_pending = "react_thanks"
			_note = "%s landed on %s.  %s: play Thanks?" % [players[current]["name"], _thanks_loc, players[pi]["name"]]
			_update_hud()
			return
		_thanks_queue.pop_front()
	_pending = ""
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
		# Complete ALL hand cards whose locations include this spot (Duos match
		# either location and count as 2). Scan the original hand once, then draw
		# a replacement per completed card so replacements aren't re-checked.
		var kept := []
		var gained := 0
		var n := 0
		for card in p["hand"]:
			if card["type"] == "errand" and loc in card["locations"]:
				gained += card["count"]
				n += 1
			else:
				kept.append(card)
		if n > 0:
			p["hand"] = kept
			for j in range(n):
				p["hand"].append(_draw_card())
			p["completed"] += gained
			var word := "errand" if n == 1 else "errands"
			_note = "%s completed %d %s at %s  (+%d)" % [p["name"], n, word, loc, gained]
		# Thanks reaction: any opponent holding Thanks + a matching errand may cash it in.
		_thanks_loc = loc
		_thanks_queue = []
		for k in range(1, players.size()):
			var pi := (current + k) % players.size()
			if _has_card(players[pi], "thanks") and _find_errand(players[pi], loc) != -1:
				_thanks_queue.append(pi)
		if not _thanks_queue.is_empty():
			_next_thanks_reactor()
	if board[id]["kind"] == "home" and p["completed"] >= win_target:
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
	_ai_turn_plays = 0                  # reset the CPU's per-turn Special count
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


# Play a Special: pick a target (if it needs one), then poll opponents for Prevent.
func _attempt_special(index: int) -> void:
	var p = players[current]
	var card = p["hand"][index]
	_sp_index = index
	_sp_target = -1
	if card["id"] in TARGETED_SPECIALS and _active_opponents().size() >= 2:
		if p["is_ai"]:
			_sp_target = _ai_pick_target(card["id"])
			_begin_prevent_poll()
		else:
			_pending = "choose_target"
			_note = "%s — choose a player to target." % card["title"]
			_update_hud()
	else:
		if card["id"] in TARGETED_SPECIALS:
			_sp_target = _target_player()           # only one opponent
		_begin_prevent_poll()


func _active_opponents() -> Array:
	var out := []
	for i in range(players.size()):
		if i != current:
			out.append(i)
	return out


func _target_or_next() -> int:
	return _sp_target if _sp_target >= 0 else _target_player()


# The human clicked an opponent to target; continue to the Prevent poll.
func _choose_target_pick(pi: int) -> void:
	if _pending != "choose_target":
		return
	_sp_target = pi
	_pending = ""
	_begin_prevent_poll()


# The human cancelled before committing the Special (nothing spent yet).
func _cancel_target() -> void:
	if _pending != "choose_target":
		return
	_pending = ""
	_sp_index = -1
	_sp_target = -1
	_note = ""
	_update_hud()


# Offer Prevent to each other player (turn order) until one prevents or all decline.
func _begin_prevent_poll() -> void:
	var card = players[current]["hand"][_sp_index]
	_react_queue = []
	if card["id"] != "prevent":
		for k in range(1, players.size()):
			var pi := (current + k) % players.size()
			if _has_card(players[pi], "prevent"):
				_react_queue.append(pi)
	_next_prevent_reactor()


func _next_prevent_reactor() -> void:
	if _react_queue.is_empty():
		_resolve_special(_sp_index)                 # nobody prevented — resolve
		return
	var reactor: int = _react_queue[0]
	_reaction = { "reactor": reactor }
	_pending = "react_prevent"
	var card = players[current]["hand"][_sp_index]
	_note = "%s played %s.  %s: Prevent it?" % [players[current]["name"], card["title"], players[reactor]["name"]]
	_update_hud()


func _do_prevent(prevent_it: bool) -> void:
	var reactor: int = int(_reaction.get("reactor", _target_player()))
	_pending = ""
	if not prevent_it:
		if not _react_queue.is_empty():
			_react_queue.pop_front()                # this player passed — ask the next
		_reaction = {}
		_next_prevent_reactor()
		return
	var p = players[current]
	var card = p["hand"][_sp_index]
	var was_instant: bool = card["instant"]
	var title: String = card["title"]
	_discard_from_hand(p, _sp_index)                # the Special is spent, with no effect
	_draw_to_hand(p)
	var pidx := _find_card(players[reactor], "prevent")
	if pidx != -1:
		_discard_from_hand(players[reactor], pidx)
		_draw_to_hand(players[reactor])
	_note = "%s Prevented %s's %s!" % [players[reactor]["name"], p["name"], title]
	_react_queue = []
	_reaction = {}
	_sp_index = -1
	_sp_target = -1
	if was_instant:
		_update_hud()                               # instant: no turn lost
	else:
		_end_turn(false)                            # a turn-costing Special was spent
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
			var t := _target_or_next()
			players[t]["slow_turns"] = 2
			_note = "%s hit %s with Slow Traffic (1 space/turn for 2 turns)." % [p["name"], players[t]["name"]]
			_end_turn(false)               # costs the turn
		"switcheroo":
			_discard_from_hand(p, index)
			_draw_to_hand(p)
			var t2 := _target_or_next()
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
	var v := 0
	if CARD_FACE_PATHS.has(loc):
		v = randi() % CARD_FACE_PATHS[loc].size()
	return { "type": "errand", "locations": [loc], "count": 1, "flavor": "", "face_variant": v }


func _play_send(index: int, loc: String) -> void:
	var p = players[current]
	_discard_from_hand(p, index)
	_draw_to_hand(p)
	var t := _target_or_next()
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
	_move_tween = tw
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


func _newhand_discard() -> void:
	var p = players[current]
	for card in p["hand"]:
		discard.append(card)
	p["hand"] = []
	for i in range(7):
		p["hand"].append(_draw_card())
	_note = "New Hand — discarded and drew a fresh 7."
	_pending = ""
	_end_turn(false)                # New Hand costs the turn


# "Swap hands" chosen: with 3+ players let the human pick whose hand to take.
func _newhand_choose_swap() -> void:
	if _pending != "newhand_choice":
		return
	var opps := _active_opponents()
	if opps.size() >= 2 and not players[current]["is_ai"]:
		_pending = "newhand_target"
		_note = "New Hand — choose whose hand to swap with."
		_update_hud()
	else:
		_newhand_swap_with(opps[0] if not opps.is_empty() else (current + 1) % players.size())


func _newhand_swap_with(pi: int) -> void:
	var p = players[current]
	var tmp = players[pi]["hand"]
	players[pi]["hand"] = p["hand"]
	p["hand"] = tmp
	_note = "New Hand — swapped hands with %s." % players[pi]["name"]
	_pending = ""
	_end_turn(false)                # New Hand costs the turn


# Back out of the swap target choice to the discard/swap prompt (card already spent).
func _newhand_back() -> void:
	if _pending != "newhand_target":
		return
	_pending = "newhand_choice"
	_note = "New Hand — discard & draw 7, or swap hands?"
	_update_hud()


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
	# Test aid: deal a spread of the finished standard card art (both Gym variants
	# side by side, plus a few other districts) and two Specials.
	if players.is_empty() or phase != "ROLL" or _pending != "":
		return
	var me = players[current]
	me["hand"] = []
	me["hand"].append({ "type": "errand", "locations": ["Gym"], "count": 1, "flavor": "", "face_variant": 0 })
	me["hand"].append(_errand_card("Museum"))
	me["hand"].append({ "type": "errand", "locations": ["Pharmacy", "Forest"], "count": 2, "flavor": "" })
	me["hand"].append({ "type": "errand", "locations": ["Pawn Shop", "Jewelry"], "count": 2, "flavor": "" })
	me["hand"].append({ "type": "errand", "locations": ["Gym", "Park"], "count": 2, "flavor": "" })
	me["hand"].append(_special_card("shortcut"))
	me["hand"].append(_special_card("dumpster_diving"))
	if discard.size() < 6:
		for i in range(8):
			discard.append(_draw_card())
	_note = "(debug) Test hand: standard + 3 Duo cards + 2 Specials."
	_update_hud()


func _reset_game() -> void:
	if _move_tween != null and _move_tween.is_valid():
		_move_tween.kill()             # stop any in-flight move so it can't fire stale
	if _rot_tween != null and _rot_tween.is_valid():
		_rot_tween.kill()
	_camera.rotation = 0.0             # back to an upright board
	_cam_rot_target = 0.0
	_animating = false
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
	_sp_index = -1
	_sp_target = -1
	_react_queue = []
	_thanks_queue = []
	_thanks_loc = ""
	_dd_held = {}
	_dice_count = 2
	_doubles_gives_free = true
	_free_turn_pending = false
	_slowed = false
	_ai_scheduled = false
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
# AI OPPONENT
# ---------------------------------------------------------------------------
# The CPU is driven by the same entry points a human uses (_roll, _begin_move,
# _attempt_special, _do_prevent/_do_thanks). After any state change _update_hud()
# calls _ai_tick(); if the game is waiting on a CPU player, we queue _ai_act on a
# short timer so the move is watchable, then dispatch on the current wait-state.

# Who is the game currently waiting on? -1 = nobody / a human-only UI state.
func _ai_actor() -> int:
	if phase != "ROLL" and phase != "MOVE":
		return -1
	match _pending:
		"react_prevent", "react_thanks":
			return int(_reaction.get("reactor", -1))    # the specific reacting player
		"", "lucky2_discard", "newhand_choice", "place_roadblock", \
		"remove_roadblock", "pick_discard", "place_bridge":
			return current                   # the CPU resolves its own Special prompts
		_:
			return -1                        # choose_target is human-only


# Difficulty of the player currently acting.
func _ai_diff() -> int:
	return int(players[current].get("difficulty", AI_MEDIUM))


func _ai_tick() -> void:
	if _ai_scheduled or _paused or _animating or players.is_empty():
		return
	if phase == "MENU" or phase == "SETUP" or phase == "OVER":
		return
	var who := _ai_actor()
	if who < 0 or who >= players.size() or not players[who].get("is_ai", false):
		return
	_ai_scheduled = true
	get_tree().create_timer(AI_DELAY).timeout.connect(_ai_act)


func _ai_act() -> void:
	_ai_scheduled = false
	# Re-check: state may have moved on (or paused) since this was queued.
	if _paused or _animating or players.is_empty():
		return
	if phase == "MENU" or phase == "SETUP" or phase == "OVER":
		return
	var who := _ai_actor()
	if who < 0 or who >= players.size() or not players[who].get("is_ai", false):
		return
	match _pending:
		"react_prevent":
			_ai_react_prevent(); return
		"react_thanks":
			# A free errand — Medium/Hard always take it; Easy sometimes fumbles it.
			var rr := int(_reaction.get("reactor", current))
			var rdiff := int(players[rr].get("difficulty", AI_MEDIUM))
			_do_thanks(rdiff != AI_EASY or randf() < 0.6); return
		"lucky2_discard":
			_on_card_clicked(_ai_worst_card_index()); return
		"newhand_choice":
			if _ai_newhand_swap():
				_newhand_swap_with(_ai_leader_opponent())   # steal the leader's hand
			else:
				_newhand_discard()
			return
		"place_roadblock":
			_ai_place_roadblock(); return
		"remove_roadblock":
			_ai_remove_roadblock(); return
		"pick_discard":
			_ai_pick_discard(); return
		"place_bridge":
			_ai_place_bridge(); return
	if phase == "MOVE":
		_ai_do_move(); return
	if phase == "ROLL":
		_ai_do_roll()


# The CPU's decision on its own turn before moving: play a Special, else roll.
func _ai_do_roll() -> void:
	if _ai_turn_plays < 10:                        # safety cap against a Special loop
		var pick := _ai_choose_special(_ai_diff())
		if pick != -1:
			_ai_turn_plays += 1
			_attempt_special(pick)
			return
	_roll()


# Which Special (hand index) the CPU should play now, or -1 to just roll.
func _ai_choose_special(diff: int) -> int:
	var p = players[current]
	# Free Turn is pure upside (doesn't cost the turn) — every level plays it.
	var fi := _find_card(p, "free_turn")
	if fi != -1:
		return fi
	if diff == AI_EASY:
		if not _slowed and randf() < 0.5:
			var l3e := _find_card(p, "lucky3")
			if l3e != -1:
				return l3e
		return -1                                  # Easy otherwise just rolls

	# --- Medium & Hard ---
	# A Lucky 12/20 that lands an errand or wins outright.
	var lm := _ai_best_lucky_move()
	if lm != -1:
		return lm
	var opp := _ai_leader_opponent()               # the biggest threat, not just "next"
	# Disrupt: both tiers hit an about-to-win opponent; Hard also hits when it's behind.
	var disrupt: bool = players[opp]["completed"] >= win_target - 1
	if diff == AI_HARD and players[opp]["completed"] > p["completed"]:
		disrupt = true
	if disrupt:
		for id in AI_DISRUPT_SET:
			var di := _find_card(p, id)
			if di != -1:
				return di
	# Hard-only strategic Specials (each gated on a valid, useful target existing).
	if diff == AI_HARD:
		var sw := _find_card(p, "switcheroo")
		if sw != -1 and _ai_switcheroo_good():
			return sw
		var rh := _find_card(p, "road_hazard")
		if rh != -1 and _ai_block_candidate() != "":
			return rh
		var sc := _find_card(p, "shortcut")
		if sc != -1 and not _ai_bridge_candidate().is_empty():
			return sc
		var pv := _find_card(p, "prevent")
		if pv != -1 and _ai_removeable_block() != "":
			return pv
	# Card churn (Medium & Hard).
	var dd := _find_card(p, "dumpster_diving")
	if dd != -1 and _ai_best_discard_index(p) != -1:
		return dd
	if _ai_hand_wants_churn(p):
		var l2 := _find_card(p, "lucky2")
		if l2 != -1:
			return l2
		if diff == AI_HARD and _ai_hand_is_bad(p):
			var nh := _find_card(p, "new_hand")
			if nh != -1:
				return nh
	# Lucky 3 to fatten the roll when we're far from anything useful.
	if not _slowed and _ai_far_from_targets(p):
		var l3 := _find_card(p, "lucky3")
		if l3 != -1:
			return l3
	return -1


# --- Multi-opponent target selection ----------------------------------------

# Which opponent a targeting Special should hit: the leader for attacks, the
# most advantageous space for Switcheroo.
func _ai_pick_target(special_id: String) -> int:
	if special_id == "switcheroo":
		return _ai_best_switch_target()
	return _ai_leader_opponent()


# The most threatening opponent: most errands done, tie broken by closeness to Home.
func _ai_leader_opponent() -> int:
	var best := -1
	var best_key := -1e9
	for i in range(players.size()):
		if i == current:
			continue
		var key := float(players[i]["completed"]) * 100.0 - float(_bfs_hops(players[i]["space"], { home_id: true }))
		if key > best_key:
			best_key = key
			best = i
	return best if best != -1 else _target_player()


# The opponent whose space would put us closest to our own goal (for Switcheroo).
func _ai_best_switch_target() -> int:
	var goals := _ai_goal_spaces(current)
	var best := -1
	var best_d := 1 << 30
	for i in range(players.size()):
		if i == current:
			continue
		var d := _bfs_hops(players[i]["space"], goals)
		if d < best_d:
			best_d = d
			best = i
	return best if best != -1 else _target_player()


# --- Hard-tier target evaluation --------------------------------------------

# Switcheroo is worth it when the best target's space is clearly closer to our goal.
func _ai_switcheroo_good() -> bool:
	var opp := _ai_best_switch_target()
	if opp == current:
		return false
	var opp_space: String = players[opp]["space"]
	if players[current]["space"] == opp_space:
		return false
	var goals := _ai_goal_spaces(current)
	return _bfs_hops(opp_space, goals) + 2 <= _bfs_hops(players[current]["space"], goals)


# A placeable space that sits on the leader's shortest path to their goal, or "".
func _ai_block_candidate() -> String:
	var opp := _ai_leader_opponent()
	var goals := _ai_goal_spaces(opp)
	var here: String = players[opp]["space"]
	var d0 := _bfs_hops(here, goals)
	if d0 <= 0 or d0 >= 9999:
		return ""
	for nb in board[here]["neighbors"]:
		if _can_place_roadblock(nb) and _bfs_hops(nb, goals) < d0:
			return nb
	return ""


# [anchor, far_end] for a bridge that shortens our path to goal, or [].
func _ai_bridge_candidate() -> Array:
	var me: String = players[current]["space"]
	var goals := _ai_goal_spaces(current)
	var d0 := _bfs_hops(me, goals)
	if d0 <= 1:
		return []
	var best_end := ""
	var best := d0
	for b in _bridge_reachable(me):
		var db := _bfs_hops(b, goals)
		if db < 9999 and 1 + db < best:
			best = 1 + db
			best_end = b
	return [me, best_end] if best_end != "" else []


# A roadblock whose removal would shorten our path to goal, or "".
func _ai_removeable_block() -> String:
	if roadblocks.is_empty():
		return ""
	var me: String = players[current]["space"]
	var goals := _ai_goal_spaces(current)
	var d0 := _bfs_hops(me, goals)
	for id in roadblocks.keys():
		roadblocks.erase(id)
		var d := _bfs_hops(me, goals)
		roadblocks[id] = true
		if d < d0:
			return id
	return ""


# Best card to grab from the discard pile, or -1 if nothing is worth it.
func _ai_best_discard_index(_p) -> int:
	var best := -1
	var best_val := 0
	for i in range(discard.size()):
		var v := _ai_discard_value(discard[i])
		if v > best_val:
			best_val = v
			best = i
	return best if best_val >= 14 else -1


func _ai_discard_value(c: Dictionary) -> int:
	if c["type"] == "errand":
		var v := 0
		for loc in c["locations"]:
			if location_spaces.has(loc):
				var h := _bfs_hops(players[current]["space"], { location_spaces[loc]: true })
				v = max(v, 22 - min(h, 20))
		return v * max(1, int(c["count"]))
	match String(c.get("id", "")):
		"prevent", "free_turn", "lucky20", "thanks":
			return 30
		"lucky12", "lucky2", "dumpster_diving", "switcheroo":
			return 22
		_:
			return 14


# --- CPU handlers for the click-based Special prompts ------------------------

func _ai_place_roadblock() -> void:
	var id := _ai_block_candidate()
	if id == "" or not _can_place_roadblock(id):
		_pending = ""
		_end_turn(false)                           # nothing valid — don't get stuck
		return
	_try_place_roadblock(board[id]["pos"])         # places, clears pending, ends turn


func _ai_remove_roadblock() -> void:
	var id := _ai_removeable_block()
	if id == "" and not roadblocks.is_empty():
		id = roadblocks.keys()[0]
	if id == "":
		_pending = ""
		_update_hud()
		return
	_try_remove_roadblock(board[id]["pos"])        # instant — turn continues


func _ai_pick_discard() -> void:
	var idx := _ai_best_discard_index(players[current])
	if idx < 0:
		idx = discard.size() - 1
	if idx < 0:
		_pending = ""
		_update_hud()
		return
	_pick_discard(idx)                             # instant — turn continues


func _ai_place_bridge() -> void:
	var pair := _ai_bridge_candidate()
	if pair.is_empty():
		_pending = ""
		_bridge_anchor = ""
		bridge_candidates = []
		_end_turn(false)
		return
	_set_bridge(pair[0], pair[1])
	_bridge_anchor = ""
	bridge_candidates = []
	_pending = ""
	_note = "%s moved the bridge." % players[current]["name"]
	_end_turn(false)
	queue_redraw()


# New Hand: swap hands if the opponent's is bigger (Hard only), else discard & draw.
func _ai_newhand_swap() -> bool:
	if _ai_diff() != AI_HARD:
		return false
	var opp := _target_player()
	return players[opp]["hand"].size() > players[current]["hand"].size()


# --- hand heuristics ---------------------------------------------------------

func _ai_hand_wants_churn(p) -> bool:
	var errs := 0
	for card in p["hand"]:
		if card["type"] == "errand":
			errs += 1
	return errs <= 2


func _ai_hand_is_bad(p) -> bool:
	for card in p["hand"]:
		if card["type"] == "errand":
			return false
	return true


func _ai_far_from_targets(_p) -> bool:
	return _bfs_hops(players[current]["space"], _ai_goal_spaces(current)) >= 6


# Spaces player `pi` is aiming for: Home if they have enough errands, else their
# errand locations (falling back to Home).
func _ai_goal_spaces(pi: int) -> Dictionary:
	var p = players[pi]
	if p["completed"] >= win_target:
		return { home_id: true }
	var out := {}
	for card in p["hand"]:
		if card["type"] == "errand":
			for loc in card["locations"]:
				if location_spaces.has(loc):
					out[location_spaces[loc]] = true
	if out.is_empty():
		out[home_id] = true
	return out


# Best Lucky 12/20 card to play now, or -1 if none is clearly worth it.
func _ai_best_lucky_move() -> int:
	if _slowed:
		return -1                            # can't dodge Slow Traffic with a move card
	var p = players[current]
	var best_idx := -1
	var best_score := -INF
	for id in ["lucky20", "lucky12"]:
		var ci := _find_card(p, id)
		if ci == -1:
			continue
		var dist := 20 if id == "lucky20" else 12
		for d in _compute_destinations(p["space"], dist).keys():
			var worth: bool = _ai_errands_at(d) >= 1 \
					or (board[d]["kind"] == "home" and p["completed"] >= win_target)
			if not worth:
				continue
			var sc := _ai_score_destination(d)
			if sc > best_score:
				best_score = sc
				best_idx = ci
	return best_idx


# In MOVE: pick the highest-scoring legal destination (Easy often moves at random).
func _ai_do_move() -> void:
	if destinations.is_empty():
		return
	if _ai_diff() == AI_EASY and randf() < 0.7:
		_begin_move(destinations[randi() % destinations.size()])
		return
	var best: String = destinations[0]
	var best_score := -INF
	for d in destinations:
		var sc := _ai_score_destination(d)
		if sc > best_score:
			best_score = sc
			best = d
	_begin_move(best)


# How good is it to land on `dest` right now? Errand completions dominate; then
# position (toward Home once we have enough errands, else toward a needed shop).
func _ai_score_destination(dest: String) -> float:
	var p = players[current]
	var s := float(_ai_errands_at(dest)) * 120.0
	if board[dest]["kind"] == "home" and p["completed"] >= win_target:
		s += 100000.0
	if p["completed"] >= win_target:
		s -= float(_bfs_hops(dest, { home_id: true })) * 2.0
	else:
		var targets := _ai_target_spaces()
		if not targets.is_empty():
			s -= float(_bfs_hops(dest, targets)) * 2.0
	return s + randf() * 0.1                  # tiny jitter to vary tie-breaks


# Errand value (Duos count 2) the current player would complete by landing on dest.
func _ai_errands_at(dest: String) -> int:
	if board[dest]["kind"] != "location":
		return 0
	var loc: String = board[dest]["name"]
	var n := 0
	for card in players[current]["hand"]:
		if card["type"] == "errand" and loc in card["locations"]:
			n += card["count"]
	return n


# Board spaces of the locations named on the current player's errand cards.
func _ai_target_spaces() -> Dictionary:
	var out := {}
	for card in players[current]["hand"]:
		if card["type"] == "errand":
			for loc in card["locations"]:
				if location_spaces.has(loc):
					out[location_spaces[loc]] = true
	return out


# Hop-count from `start` to the nearest space in `goals` (roadblocks impassable).
func _bfs_hops(start: String, goals: Dictionary) -> int:
	if goals.has(start):
		return 0
	var dist := { start: 0 }
	var q := [start]
	while not q.is_empty():
		var n: String = q.pop_front()
		var nd: int = dist[n] + 1
		for nb in board[n]["neighbors"]:
			if dist.has(nb) or roadblocks.has(nb):
				continue
			if goals.has(nb):
				return nd
			dist[nb] = nd
			q.append(nb)
	return 9999                               # unreachable


# CPU reaction: Prevent Specials that hurt it (Easy under-reacts). Only prevents
# things aimed at it (or global harmful ones) — not a Send targeting someone else.
func _ai_react_prevent() -> void:
	var incoming = players[current]["hand"][_sp_index]  # `current` is the player who played it
	var reactor := int(_reaction.get("reactor", _target_player()))
	var diff := int(players[reactor].get("difficulty", AI_MEDIUM))
	var harmful: bool = incoming["id"] in AI_PREVENT_SET
	# If it's a targeted attack aimed at someone else, this reactor isn't threatened.
	if incoming["id"] in TARGETED_SPECIALS and _sp_target >= 0 and _sp_target != reactor:
		harmful = false
	var do_it := false
	if harmful:
		do_it = randf() < 0.35 if diff == AI_EASY else true
	_do_prevent(do_it)


# When shedding an extra card (Lucky 2 / New Hand), drop the errand for the
# farthest-away shop; failing that, the last card.
func _ai_worst_card_index() -> int:
	var p = players[current]
	var worst := -1
	var worst_hops := -1
	for i in range(p["hand"].size()):
		var c = p["hand"][i]
		if c["type"] == "errand" and c["count"] == 1 and location_spaces.has(c["locations"][0]):
			var h := _bfs_hops(p["space"], { location_spaces[c["locations"][0]]: true })
			if h > worst_hops:
				worst_hops = h
				worst = i
	return worst if worst != -1 else p["hand"].size() - 1

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
	_refresh_action_bar()
	_label.clear()
	if phase == "MENU":
		_refresh_card_bar()
		_refresh_discard_picker()
		return
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
	var controls := "[color=#7f8ba0][font_size=15]wheel: zoom · drag / arrows: pan[/font_size][/color]"
	if _debug_mode:
		controls += "\n[color=#ff7676][font_size=18]DEBUG  (G = test hand)[/font_size][/color]"
	_label.append_text(controls)
	_refresh_card_bar()
	_refresh_discard_picker()
	_ai_tick()                              # let the CPU act if the game is waiting on it


# The action prompt for the current situation (BBCode).
func _current_prompt(p) -> String:
	match _pending:
		"lucky2_discard":
			return "[b]Lucky 2[/b] — click a card to discard"
		"newhand_choice":
			return "[b]New Hand[/b] — press [b]D[/b] = discard & draw 7,  [b]S[/b] = swap hands"
		"newhand_target":
			return "[b]New Hand[/b] — choose whose hand to swap with (buttons below)"
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
		"choose_target":
			return "[b]Choose a player to target[/b] (buttons below)"
		"react_prevent":
			var o := int(_reaction.get("reactor", _target_player()))
			return "[color=%s]%s[/color]: press [b]Y[/b] to Prevent, [b]N[/b] to allow" % [_hud_color(o), players[o]["name"]]
		"react_thanks":
			var o2 := int(_reaction.get("reactor", _target_player()))
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
	if p["completed"] >= win_target:
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
	var rows := ["[color=#aeb6c2]ERRANDS — first to %d[/color]" % win_target]
	for i in range(players.size()):
		var active := (i == current and phase != "OVER")
		var body := "%s[color=%s]%s[/color]   [b]%d[/b]/%d" % [_swatch(i), _hud_color(i), players[i]["name"], players[i]["completed"], win_target]
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
const HOVER_SCALE := 3.1                      # how much a card grows while hovered
const HOVER_LIFT := 130.0                      # rise clears the card row so neighbours stay visible
const HOVER_TIME := 0.11                       # seconds for the pop in/out
const HOVER_MARGIN := 8.0                       # keep a hovered card this far inside the screen edges

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

	# Contextual action buttons (Roll Dice, reaction choices, Play Again…).
	_action_layer = CanvasLayer.new()
	_action_layer.layer = 2
	add_child(_action_layer)
	_action_root = Control.new()
	_action_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_action_layer.add_child(_action_root)


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


func _refresh_action_bar() -> void:
	if _action_root == null:
		return
	for c in _action_root.get_children():
		c.queue_free()
	if players.is_empty() or phase == "MENU" or phase == "SETUP":
		return
	if _pending == "choose_target":
		_build_target_buttons(_choose_target_pick, _cancel_target)
		return
	if _pending == "newhand_target":
		_build_target_buttons(_newhand_swap_with, _newhand_back, "Back")   # whose hand to take
		return
	# [text, callable] for the buttons that fit the current situation.
	var btns := []
	if _pending == "newhand_choice":
		btns = [["Discard & draw 7", _newhand_discard], ["Swap hands", _newhand_choose_swap]]
	elif _pending == "react_prevent":
		btns = [["Prevent", _do_prevent.bind(true)], ["Allow", _do_prevent.bind(false)]]
	elif _pending == "react_thanks":
		btns = [["Play Thanks", _do_thanks.bind(true)], ["Skip", _do_thanks.bind(false)]]
	elif _pending != "":
		return                              # click-based prompts (roadblock, bridge, discards)
	elif phase == "OVER":
		btns = [["Play Again", _reset_game]]
	elif phase == "ROLL":
		btns = [["Roll Dice", _roll]]
	else:
		return                              # MOVE: click a highlighted space

	var bw := 240.0
	var bh := 52.0
	var gap := 18.0
	var total := btns.size() * bw + (btns.size() - 1) * gap
	var x := (VIEW_SIZE.x - total) * 0.5
	var y := 838.0
	for bd in btns:
		var b := Button.new()
		b.text = bd[0]
		b.add_theme_font_size_override("font_size", 22)
		b.custom_minimum_size = Vector2(bw, bh)
		b.size = Vector2(bw, bh)
		b.position = Vector2(x, y)
		b.pressed.connect(bd[1])
		_action_root.add_child(b)
		x += bw + gap


# Colour-coded buttons (one per opponent) for choosing a player; `pick_cb` takes the
# chosen player index, `cancel_cb` backs out. Reused for target Specials and New Hand.
func _build_target_buttons(pick_cb: Callable, cancel_cb: Callable, cancel_text := "Cancel") -> void:
	var opps := _active_opponents()
	var bw := 112.0
	var bh := 50.0
	var gap := 6.0
	var count := opps.size() + 1                    # opponents + Cancel/Back
	var total := count * bw + (count - 1) * gap
	var x := (VIEW_SIZE.x - total) * 0.5
	var y := 838.0
	for pi in opps:
		var b := Button.new()
		b.text = players[pi]["name"]
		b.add_theme_font_size_override("font_size", 16)
		b.add_theme_color_override("font_color", Color(players[pi]["tint"]).lightened(0.2))
		b.custom_minimum_size = Vector2(bw, bh)
		b.size = Vector2(bw, bh)
		b.position = Vector2(x, y)
		b.pressed.connect(pick_cb.bind(pi))
		_action_root.add_child(b)
		x += bw + gap
	var cancel := Button.new()
	cancel.text = cancel_text
	cancel.add_theme_font_size_override("font_size", 16)
	cancel.custom_minimum_size = Vector2(bw, bh)
	cancel.size = Vector2(bw, bh)
	cancel.position = Vector2(x, y)
	cancel.pressed.connect(cancel_cb)
	_action_root.add_child(cancel)


func _refresh_discard_picker() -> void:
	if _discard_root == null:
		return
	for child in _discard_root.get_children():
		child.queue_free()
	if _pending != "pick_discard":
		return

	# The picker rides a centre-anchored layer; stretch the dim to cover the whole
	# window by countering that centre offset.
	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 0.72)
	bg.position = Vector2(-roundf((_vp().x - VIEW_SIZE.x) * 0.5), -roundf((_vp().y - VIEW_SIZE.y) * 0.5))
	bg.size = _vp()
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
	# `hit` is a fixed-size, fixed-position hover/click target. The visual `panel`
	# is a child that scales and lifts on hover. Keeping the hitbox stationary stops
	# the hover state from flickering as the card animates away from the cursor.
	var hit := Control.new()
	hit.custom_minimum_size = Vector2(CARD_W, CARD_H)
	hit.size = Vector2(CARD_W, CARD_H)

	var panel := Panel.new()
	panel.size = Vector2(CARD_W, CARD_H)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Scale/lift from the bottom-centre so the card grows upward on hover.
	panel.pivot_offset = Vector2(CARD_W * 0.5, CARD_H)
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
	hit.add_child(panel)
	hit.set_meta("visual", panel)

	if clickable:
		hit.mouse_filter = Control.MOUSE_FILTER_STOP
		if on_gui.is_valid():
			hit.gui_input.connect(on_gui)
		else:
			hit.gui_input.connect(_on_card_gui_input.bind(index))
	else:
		hit.mouse_filter = Control.MOUSE_FILTER_PASS   # still receives hover; clicks pass through
	# Hover: pop the card up and enlarge it so the small face is readable.
	hit.mouse_entered.connect(_on_card_hover.bind(hit, true))
	hit.mouse_exited.connect(_on_card_hover.bind(hit, false))
	return hit


# Animate a hovered card up + larger (or back to rest). The `hit` target stays put;
# only its child `visual` moves, so the cursor never leaves the hitbox (no flicker).
func _on_card_hover(hit: Control, entering: bool) -> void:
	if not is_instance_valid(hit):
		return
	var visual = hit.get_meta("visual", null)
	if visual == null or not is_instance_valid(visual):
		return
	if hit.has_meta("hover_tw"):
		var old = hit.get_meta("hover_tw")
		if old is Tween and old.is_valid():
			old.kill()
	var tw := create_tween().set_parallel(true).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	hit.set_meta("hover_tw", tw)
	if entering:
		hit.move_to_front()                              # draw the whole card above its neighbours
		# Slide an edge card toward centre so the enlarged card isn't clipped off-screen.
		var half_w := CARD_W * HOVER_SCALE * 0.5
		var center_x := hit.position.x + CARD_W * 0.5
		var target_center := clampf(center_x, HOVER_MARGIN + half_w, VIEW_SIZE.x - HOVER_MARGIN - half_w)
		var target := Vector2(target_center - center_x, -HOVER_LIFT)   # local offset from the hitbox
		tw.tween_property(visual, "scale", Vector2(HOVER_SCALE, HOVER_SCALE), HOVER_TIME)
		tw.tween_property(visual, "position", target, HOVER_TIME)
	else:
		tw.tween_property(visual, "scale", Vector2.ONE, HOVER_TIME)
		tw.tween_property(visual, "position", Vector2.ZERO, HOVER_TIME)


# The card-face texture for a single-location errand that has finished art, else null.
# `face_variant` on the card (set when it was built) picks which art variant to show,
# so it stays stable across HUD refreshes instead of changing every redraw.
func _card_face_for(card: Dictionary) -> Texture2D:
	if card["type"] != "errand":
		return null
	var path := ""
	if card["count"] >= 2 and card["locations"].size() >= 2:
		path = _duo_face_path(card["locations"])   # Duos: one finished face for the pair
	elif card["count"] == 1:
		var loc: String = card["locations"][0]
		if not CARD_FACE_PATHS.has(loc):
			return null
		var variants: Array = CARD_FACE_PATHS[loc]
		if variants.is_empty():
			return null
		path = variants[int(card.get("face_variant", 0)) % variants.size()]
	if path == "":
		return null
	if not _card_face_cache.has(path):
		_card_face_cache[path] = load(path) if ResourceLoader.exists(path) else null
	return _card_face_cache[path]


# The finished face texture for a Special card (by id), or null.
func _special_face_for(card: Dictionary) -> Texture2D:
	if card["type"] != "special":
		return null
	var id := String(card.get("id", ""))
	if not SPECIAL_FACE_PATHS.has(id):
		return null
	var path: String = SPECIAL_FACE_PATHS[id]
	if not _card_face_cache.has(path):
		_card_face_cache[path] = load(path) if ResourceLoader.exists(path) else null
	return _card_face_cache[path]


# The finished face for a Duo whose pair matches `locs` (either order), or "".
func _duo_face_path(locs: Array) -> String:
	for duo in DUOS:
		if String(duo.get("face", "")) == "":
			continue
		var d: Array = duo["locations"]
		if (d[0] == locs[0] and d[1] == locs[1]) or (d[0] == locs[1] and d[1] == locs[0]):
			return duo["face"]
	return ""


# Draw the rounded outline ON TOP of a card's art (added last so it masks the
# image's square corners), and give the panel a black background behind any letterbox.
func _add_card_frame(panel: Panel) -> void:
	var border_w := 3
	var border_col := Color(0.15, 0.15, 0.15)
	var sb := panel.get_theme_stylebox("panel")
	if sb is StyleBoxFlat:
		var f := sb as StyleBoxFlat
		border_w = max(f.border_width_left, 3)
		border_col = f.border_color
		f.bg_color = Color.BLACK
		f.set_border_width_all(0)
	var frame := Panel.new()
	frame.position = Vector2.ZERO
	frame.size = Vector2(CARD_W, CARD_H)
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var fsb := StyleBoxFlat.new()
	fsb.bg_color = Color(0, 0, 0, 0)               # border only, no fill
	fsb.draw_center = false
	fsb.set_corner_radius_all(6)
	fsb.set_border_width_all(border_w)
	fsb.border_color = border_col
	frame.add_theme_stylebox_override("panel", fsb)
	panel.add_child(frame)


func _fill_errand_card(panel: Panel, card: Dictionary) -> void:
	# If this location has finished art, show the whole card face and skip the
	# placeholder text (the art already carries the title, colour and caption).
	var face := _card_face_for(card)
	if face != null:
		var trect := TextureRect.new()
		trect.texture = face
		trect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		trect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		trect.position = Vector2(3, 3)
		trect.size = Vector2(CARD_W - 6, CARD_H - 6)
		trect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		panel.add_child(trect)
		_add_card_frame(panel)
		return

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
	# Finished art if available (drawn like the errand faces); else the text layout.
	var face := _special_face_for(card)
	if face != null:
		var trect := TextureRect.new()
		trect.texture = face
		trect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		trect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		trect.position = Vector2(3, 3)
		trect.size = Vector2(CARD_W - 6, CARD_H - 6)
		trect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		panel.add_child(trect)
		_add_card_frame(panel)
		return

	# Header/title area is tall enough for two lines so long titles (e.g. "Dumpster
	# Diving") wrap inside the card instead of overflowing its edges.
	var header := ColorRect.new()
	header.color = SPECIAL_HEADER
	header.position = Vector2(4, 4)
	header.size = Vector2(CARD_W - 8, 28)
	header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(header)

	var title := Label.new()
	title.text = card["title"]
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.add_theme_font_size_override("font_size", 10)
	title.add_theme_color_override("font_color", Color.WHITE)
	title.position = Vector2(4, 4)
	title.size = Vector2(CARD_W - 8, 28)
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(title)

	var body := Label.new()
	body.text = card["short"]
	body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_theme_font_size_override("font_size", 11)
	body.add_theme_color_override("font_color", Color(0.1, 0.1, 0.1))
	body.position = Vector2(4, 34)
	body.size = Vector2(CARD_W - 8, CARD_H - 50)
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(body)

	if card["instant"]:
		var tag := Label.new()
		tag.text = "INSTANT"
		tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		tag.add_theme_font_size_override("font_size", 9)
		tag.add_theme_color_override("font_color", SPECIAL_HEADER)
		tag.position = Vector2(4, CARD_H - 16)
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
