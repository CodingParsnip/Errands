# Headless test suite for Errands. Instances the real game (scenes/Main.tscn) and
# drives its logic through the same entry points a game uses, asserting on the
# results. Run via tests/run.sh (which the pre-commit hook calls), or directly:
#   godot --headless --path . res://tests/Tests.tscn
# Exits 0 when every assertion passes, 1 otherwise (so it can gate a commit).
extends Node

var _pass := 0
var _fail := 0
var _fails: Array[String] = []


func _ready() -> void:
	var tests := [
		"test_board_loads",
		"test_deck_builds",
		"test_card_art_coverage",
		"test_card_art_resources",
		"test_landing_completes",
		"test_send_completes",
		"test_no_false_completion",
		"test_switch_space_completes",
		"test_ai_gift_guard",
		"test_end_turn_gate",
		"test_dice_roll_anim",
		"test_view_toolbar_uniform_width",
		"test_hud_edge_anchoring",
	]
	print("=== Errands test suite (%d tests) ===" % tests.size())
	for t in tests:
		var before := _fail
		call(t)
		print("  [%s] %s" % ["ok" if _fail == before else "FAIL", t])
	print("=== RESULT: %d passed, %d failed ===" % [_pass, _fail])
	for f in _fails:
		print("  - ", f)
	get_tree().quit(0 if _fail == 0 else 1)


# --- assertion helpers ------------------------------------------------------

func _check(cond: bool, msg: String) -> void:
	if cond:
		_pass += 1
	else:
		_fail += 1
		_fails.append(msg)

func _eq(got, expected, msg: String) -> void:
	_check(got == expected, "%s (got %s, expected %s)" % [msg, got, expected])


# Instance a fresh game and start it. `seats` overrides the seat setup (default
# is the built-in 2-player layout). Returns the Main node, or null on failure.
func _new_main(seats := []) -> Node:
	var scene = load("res://scenes/Main.tscn")
	if scene == null:
		_check(false, "could not load scenes/Main.tscn (parse error?)")
		return null
	var m = scene.instantiate()
	if m == null:
		_check(false, "could not instantiate scenes/Main.tscn")
		return null
	add_child(m)                                   # runs Main._ready (builds MENU)
	if not seats.is_empty():
		m._seat_mode = seats.duplicate()
	m._start_game(false)
	if m.players.size() < 2:
		_check(false, "game did not start (board/locations failed to load)")
	return m


# --- tests ------------------------------------------------------------------

func test_board_loads() -> void:
	var m = _new_main()
	if m == null: return
	_check(m.board.size() > 0, "board graph loaded")
	_check(m.home_id != "", "home space identified")
	for loc in ["Beach", "Fair", "Lake", "Music", "Park"]:
		_check(m.location_spaces.has(loc), "location present on board: %s" % loc)
	m.free()


func test_deck_builds() -> void:
	var m = _new_main()
	if m == null: return
	_check(m.deck.size() > 0, "deck built non-empty")
	var has_special := false
	var has_errand := false
	for c in m.deck:
		if c["type"] == "special":
			has_special = true
		elif c["type"] == "errand":
			has_errand = true
			# Single-location errands carry a stable art variant; Duos (count 2) use
			# their own "face" field instead, so they legitimately have no face_variant.
			if c["count"] == 1:
				_check(c.has("face_variant"), "standard errand card carries a face_variant")
	_check(has_special, "deck contains Special cards")
	_check(has_errand, "deck contains errand cards")
	m.free()


# Every errand location that can appear must have finished art (never the placeholder).
func test_card_art_coverage() -> void:
	var m = _new_main()
	if m == null: return
	for loc in m.location_names:
		_check(m.CARD_FACE_PATHS.has(loc), "location has card art (no placeholder): %s" % loc)
	m.free()


# Every referenced art file (standard variants, Duos, Specials) actually exists.
func test_card_art_resources() -> void:
	var m = _new_main()
	if m == null: return
	for loc in m.CARD_FACE_PATHS.keys():
		for path in m.CARD_FACE_PATHS[loc]:
			_check(ResourceLoader.exists(path), "missing standard face: %s" % path)
	for duo in m.DUOS:
		_check(ResourceLoader.exists(duo["face"]), "missing duo face: %s" % duo["face"])
	for id in m.SPECIAL_FACE_PATHS.keys():
		_check(ResourceLoader.exists(m.SPECIAL_FACE_PATHS[id]), "missing special face: %s" % m.SPECIAL_FACE_PATHS[id])
	m.free()


func test_landing_completes() -> void:
	var m = _new_main()
	if m == null: return
	m.current = 0
	m.players[1]["hand"] = []                       # isolate from Thanks reactions
	m.players[0]["hand"] = [m._errand_card("Beach")]
	var before: int = m.players[0]["completed"]
	m._resolve_landing(m.location_spaces["Beach"])
	_eq(m.players[0]["completed"], before + 1, "landing on Beach completes the Beach errand")
	_eq(m._find_errand(m.players[0], "Beach"), -1, "the completed Beach card is consumed")
	m.free()


func test_send_completes() -> void:
	var m = _new_main([1, 3, 0, 0, 0, 0])           # 2 players
	if m == null: return
	m.current = 0
	m.players[1]["hand"] = [m._errand_card("Beach")]
	var before: int = m.players[1]["completed"]
	m.players[0]["hand"] = [{ "type": "special", "id": "to_beach", "title": "To the Beach", "short": "", "instant": false }]
	m._play_send(0, "Beach")
	_eq(m.players[1]["completed"], before + 1, "being sent to Beach completes the target's Beach errand")
	_eq(m._find_errand(m.players[1], "Beach"), -1, "the sent player's Beach card is consumed")
	if m._move_tween != null and m._move_tween.is_valid():
		m._move_tween.kill()                        # stop the slide before freeing
	m.free()


func test_no_false_completion() -> void:
	var m = _new_main()
	if m == null: return
	m.players[0]["hand"] = [m._errand_card("Lake")]
	var before: int = m.players[0]["completed"]
	var r = m._complete_errands_at(0, "Beach")
	_eq(m.players[0]["completed"], before, "no completion without the matching card")
	_eq(r[0], 0, "helper reports zero completed")
	m.free()


func test_switch_space_completes() -> void:
	var m = _new_main()
	if m == null: return
	m.players[0]["hand"] = [m._errand_card("Lake")]
	m.players[0]["space"] = m.location_spaces["Lake"]
	var before: int = m.players[0]["completed"]
	var r = m._complete_errands_on_space(0)
	_eq(m.players[0]["completed"], before + 1, "landing (via swap) on Lake completes the Lake errand")
	_eq(r[0], 1, "helper reports one completed")
	m.free()


func test_ai_gift_guard() -> void:
	var m = _new_main([3, 3, 3, 0, 0, 0])           # 3 CPUs → two opponents to choose between
	if m == null: return
	m.current = 0
	m.players[1]["hand"] = [m._errand_card("Beach")]; m.players[1]["completed"] = 5   # leader, would be gifted
	m.players[2]["hand"] = [m._errand_card("Lake")];  m.players[2]["completed"] = 0   # safe target
	_eq(m._ai_send_target("Beach", m.AI_HARD), 2, "Hard avoids gifting the Beach holder")
	_eq(m._ai_send_target("Beach", m.AI_MEDIUM), 2, "Medium prefers the non-gifting target")
	_eq(m._ai_send_target("Beach", m.AI_EASY), 1, "Easy targets the leader regardless")
	m.players[2]["hand"] = [m._errand_card("Beach")]                                   # now everyone would benefit
	_eq(m._ai_send_target("Beach", m.AI_HARD), -1, "Hard skips the send when every target would benefit")
	_eq(m._ai_send_target("Beach", m.AI_MEDIUM), 1, "Medium still fires at the leader when all benefit")
	m.free()


func test_end_turn_gate() -> void:
	var m = _new_main()                             # P1 Human, P2 CPU
	if m == null: return
	# A human's finished turn waits for the End Turn click; play doesn't pass yet.
	m.current = 0
	m._end_turn(false)
	_eq(m._pending, "end_turn", "human turn end raises the End Turn gate")
	_eq(m.current, 0, "play has not passed while the gate is up")
	m._confirm_end_turn()
	_eq(m._pending, "", "confirming clears the gate")
	_eq(m.current, 1, "confirming passes play to the next player")
	_eq(m.phase, "ROLL", "next turn starts in ROLL")
	# A CPU's turn end advances on its own (no gate).
	m._end_turn(false)                              # current is now the CPU
	_eq(m._pending, "", "CPU turn end needs no confirmation")
	_eq(m.current, 0, "CPU turn passed straight back to the human")
	# A free/extra turn keeps the same player, so it skips the gate.
	m._free_turn_pending = true
	m._end_turn(false)
	_eq(m._pending, "", "free turn skips the gate")
	_eq(m.current, 0, "free turn keeps the same player")
	m.free()


func test_dice_roll_anim() -> void:
	var m = _new_main()
	if m == null: return
	m.current = 0
	m._roll()
	_check(m._rolling, "rolling starts the dice animation")
	_eq(m.phase, "ROLL", "the move waits until the animation lands")
	_eq(m._roll_final.size(), 2, "two dice are queued behind the animation")
	m._roll()                                       # a second roll mid-animation is ignored
	_eq(m._roll_final.size(), 2, "re-rolling mid-animation is a no-op")
	m._dice_anim_done()                             # land it immediately (headless)
	_check(not m._rolling, "the animation flag clears when the roll lands")
	_eq(m.phase, "MOVE", "landing starts the MOVE phase")
	_eq(m.last_roll, m._roll_final[0] + m._roll_final[1], "movement total matches the final dice")
	m.free()


func test_view_toolbar_uniform_width() -> void:
	var m = _new_main([1, 3, 3, 0, 0, 0])           # 3 players → 3 player buttons
	if m == null: return
	var widths := {}
	var buttons := 0
	for c in m._view_root.get_children():
		if c is Button:
			widths[c.size.x] = true
			buttons += 1
	_check(buttons >= 4 + 6 + 3, "toolbar has Camera(4)+Views(6)+Players(3) buttons (got %d)" % buttons)
	_eq(widths.size(), 1, "all view buttons share a single uniform width")
	m.free()


func test_hud_edge_anchoring() -> void:
	var m = _new_main()
	if m == null: return
	m._apply_safe_offset()
	var dx := roundf(m._vp().x - m.VIEW_SIZE.x)
	_eq(m._hud_layer.offset, Vector2.ZERO, "info panel layer hugs the top-left")
	_eq(m._score_layer.offset, Vector2(dx, 0.0), "scoreboard hugs the right edge")
	_eq(m._view_layer.offset, Vector2(dx, 0.0), "view toolbar hugs the right edge")
	m.free()
