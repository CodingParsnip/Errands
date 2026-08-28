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
		"test_horizontal_board_start",
		"test_location_labels_upright",
		"test_district_zoom_uniform",
		"test_ui_scale",
		"test_game_log",
		"test_draw_on_spot_award",
		"test_cpu_hand_hidden",
		"test_turn_start_pan",
		"test_dice_overlay",
		"test_reaction_context_cards",
		"test_discard_picker_layout",
		"test_debug_panel",
		"test_hand_reorder",
		"test_redraw_action",
		"test_gate_instants",
		"test_discard_pile_widget",
		"test_where_pick",
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
	_check(absf(m._hud_layer.scale.x - m.UI_SCALE_LEFT) < 0.001, "left boxes run slightly smaller")
	_eq(m._score_layer.offset, Vector2(dx, 0.0), "scoreboard hugs the right edge")
	_eq(m._view_layer.offset, Vector2(dx, 0.0), "view toolbar hugs the right edge")
	m.free()


func test_horizontal_board_start() -> void:
	var m = _new_main()
	if m == null: return
	_check(is_equal_approx(m._camera.rotation, m.BASE_VIEW_ROT), "game starts with the board horizontal")
	_check(is_equal_approx(m._cam_rot_target, m.BASE_VIEW_ROT), "rotation target matches the base view")
	_check(m._camera.zoom.x > 0.0, "start zoom is sane")
	# The fit zoom must account for the sideways board: the 1080-long axis lies
	# across the screen width.
	var expect := minf(m._vp().x / m.VIEW_SIZE.y, m._vp().y / m.VIEW_SIZE.x)
	_check(absf(m._camera.zoom.x - clampf(expect, m.ZOOM_MIN, m.ZOOM_MAX)) < 0.01,
		"start zoom fits the rotated board to the window")
	# Restart returns to the same default view even after rotating away from it.
	m._rotate_view(1)
	m._reset_game()
	_check(is_equal_approx(m._camera.rotation, m.BASE_VIEW_ROT), "reset restores the horizontal view")
	m.free()


func test_ui_scale() -> void:
	var m = _new_main()
	if m == null: return
	_check(absf(m._ui_scale_for(Vector2(1920, 1032)) - m.UI_SCALE) < 0.001,
		"a roomy window gets the full HUD magnification")
	_check(absf(m._ui_scale_for(Vector2(720, 1080)) - 1.0) < 0.001,
		"the bare 720x1080 window stays 1:1")
	var mid: float = m._ui_scale_for(Vector2(1100, 1080))
	_check(mid > 1.0 and mid < m.UI_SCALE, "a narrow window eases the scale down")
	m.free()


func test_game_log() -> void:
	var m = _new_main()
	if m == null: return
	var n0: int = m._log_lines.size()
	m._note = "Test event alpha."
	m._update_hud()
	m._update_hud()                                 # repeated HUD refreshes must not duplicate
	_eq(m._log_lines.size(), n0 + 1, "a new note logs exactly once")
	m._note = "Test event beta."
	m._update_hud()
	_eq(m._log_lines.size(), n0 + 2, "the next note appends to the log")
	m._reset_game()
	_eq(m._log_lines.size(), 0, "restart clears the log")
	m.free()


func test_draw_on_spot_award() -> void:
	var m = _new_main()
	if m == null: return
	m.players[0]["space"] = m.location_spaces["Park"]
	m.players[0]["hand"] = []
	m.deck.append(m._errand_card("Bank"))           # replacement draw (kept in hand)
	m.deck.append(m._errand_card("Park"))           # drawn first — matches the spot
	var before: int = m.players[0]["completed"]
	m._draw_to_hand(m.players[0])
	_eq(m.players[0]["completed"], before + 1, "drawing an errand for the current spot completes it")
	_eq(m._find_errand(m.players[0], "Park"), -1, "the matching card does not stay in hand")
	_eq(m.players[0]["hand"].size(), 1, "a replacement was drawn")
	m.free()


func test_cpu_hand_hidden() -> void:
	var m = _new_main()                             # P1 Human, P2 CPU
	if m == null: return
	m.current = 1                                   # CPU's turn
	m._refresh_card_bar()
	_eq(_live_children(m._card_row), 0, "CPU hand renders no cards")
	m.current = 0
	m._refresh_card_bar()
	_check(_live_children(m._card_row) > 0, "human hand renders cards")
	m.free()


# Children not already queue_free'd (rebuilds use deferred frees).
func _live_children(node: Node) -> int:
	var n := 0
	for c in node.get_children():
		if not c.is_queued_for_deletion():
			n += 1
	return n


func test_turn_start_pan() -> void:
	var m = _new_main()
	if m == null: return
	m.players[1]["space"] = m.location_spaces["Beach"]
	m._update_token_positions()
	m.current = 0
	m._kill_cam_tween()
	m._advance_turn(false)                          # pass play to P2
	_eq(m.current, 1, "turn advanced to the next player")
	_check(m._cam_tween != null and m._cam_tween.is_valid(), "camera glide to the new player started")
	m.free()


func test_dice_overlay() -> void:
	var m = _new_main()
	if m == null: return
	m.current = 0
	m._roll()
	_check(m._rolling, "roll starts the animation")
	_eq(_live_children(m._dice_root), 2, "two big dice tumble in the centre overlay")
	m._dice_anim_land()
	_eq(_live_children(m._dice_root), 3, "landing shows the final dice plus the total")
	_eq(m.phase, "ROLL", "the move waits out the linger")
	m._dice_anim_done()
	_eq(_live_children(m._dice_root), 0, "the dice clear away for move selection")
	_eq(m.phase, "MOVE", "the move begins after the dice clear")
	m.free()


func test_reaction_context_cards() -> void:
	var m = _new_main()
	if m == null: return
	# Prevent window: the incoming Special's face shows above the buttons.
	m.current = 0
	m.players[0]["hand"] = [m._special_card("slow_traffic")]
	m._sp_index = 0
	m._reaction = { "reactor": 1 }
	m._pending = "react_prevent"
	m._refresh_action_bar()
	_eq(_live_children(m._action_root), 3, "Prevent prompt shows 1 context card + 2 buttons")
	# Thanks window: the reactor's Thanks + matching errand faces show.
	m._thanks_loc = "Park"
	m.players[1]["hand"] = [m._special_card("thanks"), m._errand_card("Park")]
	m._pending = "react_thanks"
	m._refresh_action_bar()
	_eq(_live_children(m._action_root), 4, "Thanks prompt shows 2 context cards + 2 buttons")
	m._pending = ""
	m.free()


func test_discard_picker_layout() -> void:
	var m = _new_main()
	if m == null: return
	m.discard = []
	for i in range(8):
		m.discard.append(m._errand_card("Bank"))
	m._pending = "pick_discard"
	m._refresh_discard_picker()
	_eq(_live_children(m._discard_root), 10, "picker shows dim + title + 8 cards")
	var scaled := 0
	var gentle := 0
	for c in m._discard_root.get_children():
		if c.is_queued_for_deletion():
			continue
		if c.scale.x > 1.4:
			scaled += 1
		if bool(c.get_meta("hover_center", false)) and float(c.get_meta("hover_scale", 99.0)) < 3.0 \
				and c.has_meta("hover_bounds"):
			gentle += 1
	_eq(scaled, 8, "every card in the picker is enlarged")
	_eq(gentle, 8, "picker cards use the gentle in-place hover, not the hand pop")
	m._pending = ""
	m.free()


func test_hand_reorder() -> void:
	var m = _new_main()
	if m == null: return
	m.current = 0
	m.players[0]["hand"] = [m._errand_card("Bank"), m._errand_card("Park"), m._special_card("free_turn")]
	var data := { "kind": "errands_hand", "from": 0, "pi": 0 }
	# Pick up Bank (index 0): the gap starts at its own slot.
	m._drag_from = 0
	m._drag_slot = 0
	# Drag to the end of the row (strip x past the last card) and drop there.
	m._strip_can_drop(Vector2(9999, 0), data)
	_eq(m._drag_slot, 2, "the gap follows the cursor to the end slot")
	m._strip_drop(Vector2(9999, 0), data)
	_eq(m._card_label(m.players[0]["hand"][2]), "Bank", "dropped card lands in the gap")
	_eq(m._card_label(m.players[0]["hand"][0]), "Park", "the others shifted up")
	_eq(m._drag_from, -1, "drag state cleared after the drop")
	# A drop carrying a stale player index is ignored.
	m._drag_from = 0
	m._drag_slot = 1
	m._finish_hand_drop({ "kind": "errands_hand", "from": 0, "pi": 1 })
	_eq(m._card_label(m.players[0]["hand"][2]), "Bank", "a drop with a stale player index is ignored")
	m.free()


func test_redraw_action() -> void:
	var m = _new_main()
	if m == null: return
	m.current = 0
	_eq(m._redraws_left, m.REDRAW_LIMIT, "the free redraw is available")
	m.players[0]["hand"] = [m._errand_card("Bank")]
	m._begin_redraw()
	_eq(m._pending, "redraw_pick", "redraw prompt opens")
	var dsz: int = m.discard.size()
	m._do_redraw(0)
	_eq(m.discard.size(), dsz + 1, "the swapped card went to the discard")
	_eq(m.players[0]["hand"].size(), 1, "a replacement was drawn")
	_eq(m._redraws_left, 0, "the free redraw is spent")
	m._begin_redraw()
	_eq(m._pending, "", "no second redraw this turn")
	m.free()


func test_gate_instants() -> void:
	var m = _new_main()
	if m == null: return
	m.current = 0
	m.players[0]["hand"] = [m._special_card("free_turn"), m._errand_card("Bank")]
	m.players[1]["hand"] = []                       # nobody can Prevent
	m._end_turn(false)
	_eq(m._pending, "end_turn", "the review gate is up")
	_check(m._gate_playable(m.players[0]["hand"][0]), "Free Turn is playable from the review")
	_check(not m._gate_playable(m._special_card("lucky3")), "Lucky 3 is excluded at the review")
	m._on_card_clicked(0)                           # fire Free Turn from the gate
	_check(m._free_turn_pending, "Free Turn banked from the review")
	_eq(m._pending, "end_turn", "the gate came back after the instant resolved")
	m._confirm_end_turn()
	_eq(m.current, 0, "the banked Free Turn keeps the same player")
	m.free()


func test_discard_pile_widget() -> void:
	var m = _new_main()
	if m == null: return
	m.discard = [m._errand_card("Bank")]
	m._update_hud()
	_check(m._discard_pile.visible, "the pile widget shows during play")
	_check(m._discard_pile.scale.x > 1.5, "the pile widget is enlarged")
	_check(m._discard_pile.get_parent() == m._pile_layer, "the pile rides its corner-pinned layer")
	_check(_live_children(m._discard_pile) >= 2, "pile shows the top card plus the count tag")
	m._open_discard_view()
	_eq(m._pending, "view_discard", "clicking the pile opens the browser")
	_eq(_live_children(m._discard_root), 4, "browser shows dim, title, Close and the card")
	m._close_discard_view()
	_eq(m._pending, "", "Close returns to play")
	m.free()


func test_where_pick() -> void:
	var m = _new_main()
	if m == null: return
	m.current = 0
	m.players[0]["hand"] = [m._errand_card("Bank")]
	m._begin_where_pick()
	_eq(m._pending, "where_pick", "the lookup prompt opens")
	m._kill_cam_tween()
	m._where_show(0)
	_eq(m._pending, "", "the lookup resolves")
	_check(m._cam_tween != null and m._cam_tween.is_valid(), "camera glides to the errand's location")
	_eq(m._where_arrows.size(), 1, "a bouncing arrow marks the spot")
	_check(is_instance_valid(m._where_arrows[0]), "the arrow is live on the board")
	m.free()


func test_debug_panel() -> void:
	var m = _new_main()
	if m == null: return
	m._debug_mode = true
	m._dbg_toggle_panel()
	_check(m._debug_layer.visible, "G toggles the debug panel open")
	_check(m._dbg_card.item_count >= 50, "catalogue lists every special, errand and duo")
	_eq(m._dbg_target.item_count, m.players.size(), "target list matches the players")
	# Give: first catalogue entry (a Special) lands in the target's hand.
	m._dbg_target.select(0)
	m.players[0]["hand"] = []
	m._dbg_card.select(0)
	m._dbg_give_card()
	_eq(m.players[0]["hand"].size(), 1, "Give adds the chosen card")
	_eq(m.players[0]["hand"][0]["type"], "special", "the first catalogue entry is a Special")
	# Teleport: send the target to the first listed location.
	m._dbg_loc.select(0)
	m._dbg_teleport()
	var want: String = m._dbg_loc.get_item_text(0)
	_eq(m.board[m.players[0]["space"]]["name"], want, "teleport moves the target there")
	# Forced dice apply to the next roll only.
	m.current = 0
	m._dbg_d1.value = 6
	m._dbg_d2.value = 6
	m._dbg_force_roll()
	m._roll()
	_eq(m._roll_final, [6, 6], "forced dice land exactly as set")
	_check(m._dbg_force.is_empty(), "the forced roll is consumed")
	m._dbg_toggle_panel()
	_check(not m._debug_layer.visible, "toggling again closes the panel")
	m.free()


func test_district_zoom_uniform() -> void:
	var m = _new_main()
	if m == null: return
	var uz: float = m._district_uniform_zoom()
	_check(uz > 0.0 and uz != INF, "uniform district zoom is sane")
	for code in ["mall", "dt", "ind", "cty", "nbhd"]:
		var f: Dictionary = m._district_frame(code)
		_check(not f.is_empty(), "district frame exists: %s" % code)
		if not f.is_empty():
			# The shared zoom must never cut a district off (it is the tightest fit
			# of the largest district, so each individual fit is >= it).
			_check(f["zoom"] >= uz - 0.0001, "uniform zoom fits district: %s" % code)
	m.free()


func test_location_labels_upright() -> void:
	var m = _new_main()
	if m == null: return
	_check(m._loc_labels.size() > 30, "a label exists for every location + Home")
	m._sync_location_labels()
	for e in m._loc_labels:
		if not is_equal_approx(e["lb"].rotation, m._camera.rotation):
			_check(false, "label '%s' not counter-rotated upright" % e["lb"].text)
			m.free()
			return
	_check(true, "every location label is counter-rotated to stay upright")
	m.free()
