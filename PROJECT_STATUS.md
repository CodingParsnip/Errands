# Errands — Project Status & Handoff

A homemade board game ("Errands") ported to a playable **Godot 4.7.1** video game.
This file is the source of truth for continuing the project in a fresh session.

## How to run
- **Game:** open the project in Godot 4.7.1, press **F5** (runs `scenes/Main.tscn`).
  Start menu → **Play** (normal) / **Debug Mode** (enables the `G` test-hand key) / **Quit**.
- **Board tracer tool:** open `scenes/BoardEditor.tscn`, press **F6** (Run Current Scene).
- **Tests:** `bash tests/run.sh` (headless; exit 0 = all pass). A pre-commit hook in
  `hooks/pre-commit` runs them and blocks a failing commit — enable per clone with
  `git config core.hooksPath hooks`. See `tests/README.md`.
- Repo: private `CodingParsnip/Errands`, branch `main`. Windows dev so far; on the
  original machine there were TWO clones (agent session clone + the user's GitHub
  Desktop clone at `C:/Users/Claudia/Documents/GitHub/Errands`) — the agent pushed
  directly via Git Credential Manager and the other clone synced with
  `git fetch && git reset --hard origin/main`. On a single-clone machine none of
  that dance is needed.

## Continuing on a new machine (setup checklist)
1. **Clone** `CodingParsnip/Errands` (private — sign into GitHub via GitHub Desktop
   or `gh auth login` first).
2. **Godot 4.7.1 (standard build, not .NET).** Get the Windows zip from
   godotengine.org — it includes `Godot_v4.7.1-stable_win64_console.exe`, which the
   test runner needs. If it isn't at the path hardcoded in `tests/run.sh`, either
   edit that default or set `GODOT_BIN` to the console exe's full path.
3. **Enable the commit gate** (per clone, once): `git config core.hooksPath hooks`.
   The pre-commit hook runs the full headless suite (~1–2 min) and blocks failing
   commits. Bypass in an emergency with `git commit --no-verify`.
4. **Tests need a POSIX shell** — Git Bash on Windows: `bash tests/run.sh`.
   Line endings: `.gitattributes` already pins `*.sh` + the hook to LF; keep any
   new shell files LF.
5. Open the project in Godot once so it imports assets (or run
   `<console exe> --headless --path . --import`). `.import` churn that is
   line-endings-only can be discarded; don't blanket-`git checkout -- assets`
   (that once reverted a real asset change).
6. **Source master assets ARE in the repo** (since 2026-09-13) under
   `source-assets/` — card sources (Publisher .pub templates, per-location photos,
   PDFs, exported faces), the flattened board .xcf, rules docs (~855 MB, mirrors
   the original machine's `C:/Users/Claudia/Documents/Errands Board Game/`).
   A `.gdignore` inside keeps Godot from importing any of it. **EXCEPTION:** the
   12 layered board .xcf masters exceed GitHub's 100 MB per-file limit and are NOT
   in git — they remain only on the original machine (Board/: Draft1-FinalBase,
   Draft2-RoadDetail, FinalLayers, FinalLayers-Expanded, FinalPrint,
   rescale-FinalLayers, Drafts/, plus several "copy*" duplicates of these).
   Transfer via USB/cloud drive only if layered board editing is needed;
   `source-assets/Board/Errands-Board-FinalFlattened.xcf` (62.7 MB) IS included.
7. **For a fresh Claude session there:** this file is the complete handoff — the
   agent's local memory does not transfer between computers. Point it here first.
   Known quirks it should inherit: headless Godot cannot deliver GUI input events
   (mouse/drag behaviour can only be verified in real play), test assertion counts
   wobble a few between runs (random hands — only pass/fail matters), and GDScript
   type inference fails on Variant element access (annotate explicitly).

## Repo layout
- `scripts/Main.gd` — the whole game (one script, clearly sectioned).
- `scripts/BoardEditor.gd` + `scenes/BoardEditor.tscn` — the board-tracing tool.
- `board_map.json` — the traced board: `spaces{id:{x,y,kind,name}}` in native 6000x9000
  coords + `edges[[a,b]]`. `kind` = road | highway | location | home.
- `assets/` — board.png (6000x9000), player/bridge/blockade PNGs, card PDFs, rules.docx.

## Architecture
- **Board = a graph of spaces** (dots) connected by edges. Native coords scaled to the
  720x1080 window (`scale_f`). Game logic is separated from visuals (so AI can drop in).
- **Movement:** `_compute_destinations`/`_explore` (memoized) find legal stops N steps out;
  forced stop on locations/home; roadblocks impassable; the bridge is a movable edge.
  `_find_path` animates the chosen route; tokens rotate to face travel.
- **Cards** are dicts `{type:"errand"|"special", locations, count, id, title, short, instant}`.
  Deck built in `_build_deck` (ERRAND_COPIES per location + 4 Duos + SPECIAL_DEFS). Discard
  pile with reshuffle. Landing completes ALL matching errand cards (Duos count as 2).

## DONE
- **Board fully traced** (5 districts, 35 locations, Home, 36-space highway ring, 1 connected
  component). Tracer supports pan/zoom, road chaining, location/highway/Home tagging, sticky
  bulk-tag (K), JSON save/load.
- **All deck content:** errand cards, 4 Duos, and **all 16 Special cards** — Lucky 2/3/12/20,
  Free Turn, New Hand (D/S choice), To the Beach/Lake/Get Music (send + skip turn),
  Slow Traffic, Switcheroo, Road Hazard (+ Prevent removes block), Prevent (cancel a Special),
  Thanks, Dumpster Diving, Shortcut (movable bridge). Reactions use Y/N prompts.
- **Shell & UX:** start menu, in-game pause menu (☰ button / Esc → Resume/Restart/Main Menu),
  win-target picker (3/5/8/10 → `win_target` var), Quit, Debug Mode.
- **Multiplayer — 2 to 6 players.** Start-menu seat setup: 6 rows, each cycles Off / Human /
  CPU·Easy / CPU·Normal / CPU·Hard (`_seat_mode`), each with a colour picked from a pop-out palette
  (`_seat_color`, `PLAYER_PALETTE`; no two active seats share a colour). Need ≥2 active seats to
  start. `_build_players` builds the active players; the car token is a desaturated copy of
  `player.png` tinted per seat colour (`_grayscale_texture`). Scoreboard + view toolbar + ☰ button
  reflow for the player count (`_layout_scoreboard`, `_populate_view_controls`).
  - **Targeting (3+):** Send / Slow / Switcheroo let a human pick the victim via colour-coded
    buttons (`choose_target` → `_choose_target_pick` / `_cancel_target`); a CPU auto-picks
    (`_ai_pick_target`: leader for attacks, best-swap spot for Switcheroo). `_sp_index`/`_sp_target`.
  - **Reactions (3+):** Prevent and Thanks poll every other player in turn order
    (`_react_queue` / `_thanks_queue`; `_reaction.reactor`). A CPU only Prevents attacks aimed at
    itself. New-Hand "swap" also lets a human pick whose hand to take (`newhand_target`);
    a CPU steals the leader's hand.
- **Camera / table view:** view-toolbar buttons (Rotate L/R, Fit Board, Home, per-district,
  per-player, Follow). A green felt "table" (`_build_table_background`, CanvasLayer −10, full-rect)
  sits behind the board; the camera can pan the board almost fully off-screen (`_clamp_camera`,
  zoom/window-aware, keeps `CAM_KEEP_ON_SCREEN` px on screen) with felt filling the rest, and
  **Rotate L/R** smoothly quarter-turns the whole board via `_camera.rotation` (`_rotate_view`;
  needs `_camera.ignore_rotation = false`; pan/drag/zoom are rotation-aware). Zoom-out to `ZOOM_MIN`
  0.5; Fit uses `FIT_ZOOM` 1.0.
- **Fills any window shape:** stretch `mode=canvas_items` + `aspect=expand` (project.godot). The felt
  fills the whole viewport; the board is camera-centred and the HUD is centred as a 720×1080 "safe
  area" via each UI layer's `offset` (`_apply_safe_offset`, on `size_changed`) so board + UI stay
  aligned with green margins around. The start/pause tints are kept full-window (positioned to counter
  the offset) and camera input is frozen while a menu is open (`phase=="MENU"` / `_paused` guards).
- **AI opponent (CPU) with Easy/Medium/Hard:** any seat can be a CPU at a chosen difficulty
  (set per seat in the multiplayer setup above; stored per-player as `is_ai` / `difficulty`).
  Driven through the same entry points a human uses; a scheduler hooked into `_update_hud`
  (`_ai_tick`/`_ai_act`) acts on a short timer whenever the game waits on a CPU — on its own turn,
  during `react_prevent`/`react_thanks`, AND resolving its own click-Special prompts
  (`place_roadblock`/`remove_roadblock`/`pick_discard`/`place_bridge`, via `_ai_place_*` handlers).
  `_ai_choose_special(diff)` gates Special use by tier: **Easy** = mostly random moves, almost no
  Specials, under-reacts; **Medium** = best moves + clearly-good Specials + card churn; **Hard** =
  full toolkit (Road Hazard blocks the opponent's path, Shortcut shortens its own, Switcheroo steals
  a better spot, New Hand when dead, proactive Prevent to clear a block, aggressive disruption).
  Each click-Special is only played when a valid target provably exists (no soft-locks; there's also
  a per-turn `_ai_turn_plays` loop cap). See the **AI OPPONENT** section in Main.gd.
- **HUD/polish:** dark RichTextLabel info panel + scoreboard, per-player colour coding
  (P1 red, P2 cyan) with token halos + turn indicator, inline pip-dice roll readout,
  sliding tokens for send/swap, contextual **mouse action buttons** (Roll Dice, reaction
  choices, Play Again) so the game is fully mouse-playable. Keyboard shortcuts still work.
- **Debug:** in Debug Mode, press **G** to load a test hand of Specials (remove before final).

## OPEN / TODO
- **Standard card art — ALL 35 of 35 locations DONE (2 variants each).** Finished faces render in the
  hand via the `CARD_FACE_PATHS` map (location name → Array of `res://` variant paths). Each errand's
  two deck copies get `face_variant` 0/1 (`_build_deck`), stored on the card dict so the shown art is
  stable across HUD refreshes; `_card_face_for` picks the variant, `_fill_errand_card` draws the full
  image (bg + photo + title + caption, 750×1050 ≈ the 84×116 slot). The color-strip placeholder path
  is no longer reachable for any standard card. To add/replace: drop `card-<district>-<loc>N.png` in
  `assets/cards/standard/<District>/` and add/extend a `CARD_FACE_PATHS` line. Preview via
  **Debug Mode → G**. Repo faces use `card-<district>-<location>N.png` (singular); the source masters
  in `Cards/Standard/<District>/` use `cards-<district>-<location>N.png` (plural).
  - **Golf:** art exists in `Cards/Standard/Country/` but there is NO `Golf` board location.
    DECIDED 2026-09-20: no Golf board space — the art and `ERRAND_VALUE` entry stay dormant.
- **Duo card art — DONE (all 4).** Each Duo has a finished face showing both locations + the caption
  (750×1050), in `assets/cards/duos/duos-{drugs,package,gift,exercise}.png`. The `face` path lives on
  each `DUOS` entry; `_card_face_for` resolves it via `_duo_face_path` (matches the pair either order)
  and renders it as a single face like a standard card, plus a small `×2` badge. Source finished faces
  came from `SemiFinal Assets/Duo Cards/` (the `Cards/Duos/` folder only had raw per-location photos).
- **Special card art — DONE (all 16).** Finished faces in `assets/cards/specials/cards-special-*.png`,
  keyed by Special id in `SPECIAL_FACE_PATHS`; `_special_face_for` loads it and `_fill_special_card`
  draws it like the other faces (falls back to the text layout if art is missing). Source:
  `Cards/Specials/Exported/`.
- **AI opponents — DONE, all Specials, Easy/Normal/Hard, 2–6 players** (see the DONE section).
  Possible follow-ups: balance tuning (tier thresholds/weights in the AI OPPONENT section),
  deeper lookahead for Hard.
- **Multiplayer — DONE (2–6 players).**
- **Remove the debug `G` key** before a "final" build.
- **Sound effects — Tier 1 DONE (2026-09-21).** A SOUND EFFECTS section at the bottom of
  Main.gd synthesizes ten tiny clips at startup (16-bit WAV, no asset files): dice_tick /
  dice_land, step (per space moved, via `_set_token_rotation`), draw / discard, complete
  (chime in `_complete_errands_at`), turn (human's turn cue in `_advance_turn`), special
  (whoosh in `_resolve_special`), shuffle (discard reshuffle in `_draw_card`), win (fanfare
  with the first confetti). Played through an 8-voice `AudioStreamPlayer` pool via
  `_sfx(name)` (percussive names get ±6% random pitch; `SFX_VARIED`). **Dropping
  `assets/sfx/<name>.ogg|wav` into the repo overrides the synth for that name** — the
  upgrade path to real recorded audio, zero code changes. Pause menu has a Sound On/Off
  toggle (`_sfx_on`, `_sound_btn`).
- **Sound effects — Tier 2 DONE (2026-10-09).** Each Special now resolves with a flavor
  clip instead of the generic whoosh: `SPECIAL_SFX` maps all 16 ids onto 11 new synth
  clips by family (sp_lucky/sp_send/sp_traffic/sp_swap/sp_block/sp_prevent/sp_thanks/
  sp_newhand/sp_dumpster/sp_bridge; "special" remains the fallback). An **extra-turn
  jingle** (`extra_turn`) fires in `_advance_turn` whenever the same player keeps the
  turn (covers doubles, Free Turn and the occupied-space rule in one hook), and a
  **reaction alert** (`alert`) plays when a Prevent/Thanks window opens for a HUMAN
  reactor (CPUs stay silent). All new names are in `SFX_NAMES`, so the
  `assets/sfx/<name>.ogg|wav` drop-in override works for each. `Main._exit_tree` now
  stops the voice pool (a voice freed mid-playback leaked audio objects in headless
  runs). Tests: `test_sfx_tier2` (+ `_sfx_recent`, the observable clip history).
  User listening pass (2026-10-09) reshaped most clips: sp_lucky is a plingy bell
  arpeggio, sp_send got a longer/richer drive-off, sp_traffic is a distinct
  HONK-HOOONK, sp_swap glides wider/longer, sp_block is deeper (sub-thumps),
  sp_prevent is a real detuned buzzer **and now also fires on a REACTION Prevent**
  (`_do_prevent(true)` — the common path — previously played nothing), sp_thanks is
  a longer ta-da-daa, sp_dumpster opens with a hollow bin-lid thud. sp_newhand,
  sp_bridge, extra_turn and alert confirmed good (the "ding-dong" heard after
  Shortcut is the separate "turn" doorbell cue, not part of sp_bridge).
  Second listening pass (same day): sp_send honks lengthened; sp_traffic pitched
  up to 311/392 Hz and tinnier; sp_block longer (8 hits) with a sharp crack per
  hit; sp_prevent is now ONE continuous held buzz; sp_dumpster double-thuds
  (the lid bounces) before the rummage. Third pass (2026-10-10): sp_traffic honks
  lengthened again (0.22/0.5 s); sp_block ends on one BIG settle hit (crack +
  body + 50 Hz boom); sp_prevent is a continuous tinny buzz, settled at
  330/340 Hz with a faint 660/680 Hz top layer after a flatter/lower request.
- **Sound effects — Tier 3 DONE (2026-10-10, awaiting listening pass).**
  - **UI clicks:** every `BaseButton` that ever enters the tree is wired to a soft
    "click" tick automatically (`get_tree().node_added` → `_on_node_added_click`),
    so new buttons anywhere pick it up with zero wiring.
  - **Drag pick-up/drop:** dedicated "pickup" (up-wisp) and "drop" (soft thock)
    clips in `_hand_drag_data` / `_finish_hand_drop` / `_cancel_hand_drag`
    (pickup used to reuse the "draw" wisp).
  - **Ambience:** `_build_music` synthesizes a gentle looping pad (C–Am–F–G, two
    detuned soft voices per note, ~9.6 s, `LOOP_FORWARD`) on its own
    `AudioStreamPlayer` at `MUSIC_DB` −14 under the SFX; **Music: On/Off** button in
    the pause menu (`_on_toggle_music`, independent of the SFX toggle). Drop
    `assets/sfx/music.ogg|wav` in to replace the synth pad with real music.
  - **Volume slider:** pause-menu HSlider (0–1) → `_set_sfx_volume`/`_apply_volumes`
    drives the SFX pool and the music together (music keeps its −14 dB offset;
    0 = −80 dB mute). Test: `test_sfx_tier3`.
  Remaining sound work: swap synth clips for real recorded audio via the
  `assets/sfx/<name>.ogg|wav` drop-ins whenever desired.
- **Windows export preset (2026-10-12).** `export_presets.cfg` (tracked — the stock
  gitignore line hiding it was removed; it holds no secrets) defines "Windows
  Desktop": single self-contained `build/Errands.exe` (embedded PCK, x86_64),
  car icon + product metadata stamped via rcedit, `tests/*` + `hooks/*` excluded;
  `build/` is gitignored. Machine setup behind it (per machine, done on this one):
  4.7.1 export templates installed at `%APPDATA%\Godot\export_templates\4.7.1.stable\`
  (only the windows_*_x86_64 files + version.txt extracted from the official tpz),
  and `rcedit-x64.exe` sits next to the editor exe, wired as `export/windows/rcedit`
  in `editor_settings-4.7.tres`. Export from CLI:
  `<console exe> --headless --path . --export-release "Windows Desktop" build/Errands.exe`
  Verified: exports clean, icon/metadata stamped, exported exe runs.
- **Linux / Steam Deck export preset (2026-10-12).** `export_presets.cfg` preset
  "Linux (Steam Deck)": self-contained `build/Errands-linux.x86_64` (embedded PCK,
  x86_64). Linux templates installed next to the Windows ones (plus Android's, for
  later) in `%APPDATA%\Godot\export_templates\4.7.1.stable\`. Smoke-tested: the
  exported ELF boots headless under WSL2 Ubuntu. On the Deck: copy it over,
  `chmod +x`, then Desktop Mode → Steam → "Add a Non-Steam Game". Playable today
  via right-trackpad mouse + touchscreen taps (the game is fully mouse-playable);
  verify the HUD at 1280×800 in real use.
- **CONTROLLER SUPPORT — REQUIRED for the final version (decided 2026-10-12).**
  The game must be fully playable with a gamepad as well as mouse/keyboard, as an
  accessibility goal — PC/Steam players choose either, and the Deck gets native
  button controls instead of trackpad-only.
  - **Phase A — virtual cursor: DONE (2026-10-13, awaiting real-controller test).**
    GAMEPAD section in Main.gd: the controller steers a virtual cursor through the
    same input pipeline as the mouse (`get_viewport().warp_mouse` + synthesized
    events via `push_input(ev, true)` — local coords, NOT window coords, or headless
    and scaled windows mis-map). Left stick moves (deadzone-rescaled, eases near
    centre), D-pad = fine nudges, A = click (hold + move = card drag), B/Start = Esc,
    X = Enter, LB/RB = zoom, right stick = camera pan. A gold ring (CanvasLayer 10)
    marks the cursor; it appears on first pad input and yields to a real mouse move.
    Works on every screen (menus, pause, prompts) — the pad tick runs before
    `_process`'s phase guards, and pausing never pauses the tree. NOTE: synthesized
    clicks hit screen-space UI; board-space clicks work because the real pointer is
    warped along (`get_global_mouse_position` paths). Test: `test_pad_cursor`
    (a test button must sit on a HUD CanvasLayer — base-canvas Controls are
    camera-warped — and aim in SCREEN coords; the HUD layer renders at 0.85×).
  - **Phase A.5 — first controller-playtest fixes (2026-10-13):**
    1. **Pad drag works**: synthesized motions now carry `button_mask` while A is
       held (plus `relative`) — the GUI's drag detection reads the mask, so
       hold-A + stick drags cards like a mouse (`_pad_click_held` in `_pad_warp`).
    2. **Menu snap navigation**: on the start menu and pause menu the stick and
       D-pad SNAP the cursor between buttons (+ the volume slider — left/right
       on it adjusts the volume) instead of free-roaming: `_pad_menu_context`,
       `_pad_snap_targets`/`_pad_snap_step` (direction-scored via
       `get_global_transform_with_canvas` centres), `PAD_SNAP_COOLDOWN` repeat.
       In-game the D-pad still does fine pixel nudges.
    3. **Controller glyphs**: while a pad is active, action-bar buttons carry
       their controller badge (`_add_pad_glyph`, meta "pad_glyph"): X = Roll
       Dice / End Turn / Play Again (Enter), Y = Prevent / Play Thanks / Play
       (the "yes" key), B = Allow / Skip / Cancel. New pad keys: Y button sends
       KEY_Y; B sends KEY_N inside yes/no prompts and Esc elsewhere. Badges
       appear/disappear via `_refresh_action_bar` on pad activate/deactivate.
    4. **Crisp location labels**: board name labels are supersampled
       (`LOC_LABEL_SS` 3× font + outline, displayed at 1/3 scale) because fonts
       don't re-rasterize under Camera2D zoom — they were fuzzy at table zoom.
    Tests: `test_pad_cursor` (+drag mask), `test_pad_menu_snap`,
    `test_pad_glyphs`, `test_location_label_crispness`.
  - **Phase A.6 — pad drag & confirm fixes (2026-10-13):** field report said A
    couldn't drag and B couldn't cancel a selection. Diagnosed headless with an
    end-to-end drag test:
    1. **Godot's drag pipeline ignores synthesized input twice over** — the drag
       detector never requests drag data for pushed events, AND forwarded
       can_drop/drop callbacks receive GARBAGE local positions for them. So pad
       drags are self-driven: `_pad_force_drag` (Control.force_drag with the same
       payload/preview once A is held across 12 px), `_pad_warp` keeps
       `_drag_slot` tracking the cursor, both can_drop handlers skip their
       pos-math while `_pad_click_held` (mouse drags unaffected), and
       `_pad_click(false)` completes the drop itself if the engine didn't —
       with `_pad_click_held` cleared only AFTER the release flows, or the
       release-time can_drop stomps the tracked slot.
    2. **confirm_play now takes keys** (it never had any): Y/Enter plays,
       N backs out — so pad Y/X confirm and B cancels, matching the glyphs.
    3. **Mapping diagnostics:** on first pad input the game log names the
       controller (and flags an unrecognized mapping); in Debug Mode every
       joypad press logs its button index.
    Tests: `test_pad_drag` (full synthetic drag→reorder), `test_pad_confirm_keys`.
    **User-verified 2026-10-13:** A-drag and B-cancel work on a real controller.
  - **Steam Input note (2026-10-13):** with Steam running, its default Desktop
    Configuration turns the RIGHT TRIGGER into a real OS left-click (Errands reads
    no trigger axes). That's why "drag worked on the trigger" before A did: Steam's
    click is a real mouse event, which Godot's drag detection honours, unlike our
    synthesized ones. The pad's own indices are fine (no scrambling). Implications:
    without Steam the trigger does nothing; once Errands ships AS a Steam game,
    Steam applies the game's own controller config instead of the desktop one, so
    the trigger-click disappears unless that config keeps it. If RT should be an
    official alternate click, implement it in-game (JOY_AXIS_TRIGGER_RIGHT) and
    ship a Steam Input config that passes RT through as a trigger, or players
    under Steam get a double click.
  - **Phase B1 — in-game snapping: DONE (2026-10-13, awaiting real-controller
    test).** The D-pad now snaps on EVERY screen, not just menus:
    `_pad_snap_targets()` returns SCREEN points — in play, every live control on
    the action/card/pile/view/menu-button/picker/debug layers (buttons, hand
    cards via `hand_idx`, clickable cards + the discard pile via the
    `pad_target` meta set in `_make_card_node` / at pile creation) plus the board
    spaces the current step accepts (`_pad_board_target_ids`, mirroring the
    click handlers: MOVE destinations; open unoccupied road/highway spaces for
    roadblock placement — strand check skipped, it costs a path search per
    space; existing roadblocks for remove/move; all spaces then
    `bridge_candidates` for the bridge). Board points off screen, or under a
    control or the tray bar, are excluded. Stepping right past the last visible
    card of an oversized hand scrolls it (`_pad_hand_edge_scroll`). The stick
    stays free but settles onto a target within `PAD_MAGNET_RADIUS` 30 px when
    released (`_pad_magnet`; not while A is held). The pixel nudge survives only
    as a fallback when nothing is snappable. Test: `test_pad_ingame_snap`
    (hand step, edge scroll, destination snap + screen→board round trip,
    roadblock targets).
  - **Phase B2 — playtest fixes (2026-10-13):**
    1. **B is a real "back"** (`_pad_back`), never the pause menu: resumes from
       pause, closes the colour picker / debug panel / discard browser, cancels a
       card confirmation, target pick, New-Hand target, redraw or locate pick,
       answers "no" to a HUMAN reactor's Prevent/Thanks (never decides for a
       CPU), and otherwise does nothing. **Start** alone opens the pause menu.
       B badges now also sit on Cancel/Back/Close buttons (`_pad_refresh_glyphs`
       also rebuilds the open discard browser).
    2. **Overlays own the cursor** (`_pad_modal_root`): pause, start menu, the
       start-menu colour picker, the discard browser, the Dumpster picker and the
       debug panel each restrict snapping to their own controls (the stick snaps
       there too); in plain play every layer is live. Browser cards are snap
       targets (step through to enlarge/read); the colour picker's full-screen
       click-outside shade is excluded (`pad_skip` meta).
    3. **On-screen 🛠 Debug button** (`_debug_btn`, Debug Mode only) at the foot of
       the toolbar's left column toggles the panel — G still works. While the
       panel is open it and the toggle are the only targets; B closes it.
    Tests: `test_pad_back`, `test_pad_modal_snap`, `test_debug_button`.
  - **Phase B3 — playtest fixes (2026-10-13):**
    1. **Dropdowns (debug panel OptionButtons):** an open PopupMenu swallows
       controller presses BEFORE Main._input, yet ignores them — Godot 4.7's
       default ui_accept/ui_cancel do not include pad A/B (verified headless). It
       does obey keys, so while one is open (`_pad_open_popup`, via the viewport's
       embedded subwindows) `_pad_tick` polls the pad (`_pad_popup_tick`, edge
       detection; the press that opened it is not an edge) and translates:
       D-pad/stick up/down → Up/Down keys, A → Enter (pick), B → `hide()` (a
       pushed Escape does NOT reach the list). `_pad_button` stands aside.
    2. **Y = Redraw** on your turn (`_begin_redraw` self-guards); Y badge on the
       button. Y is still "yes" inside prompts.
    3. **Board steps own the D-pad:** while moving, placing/moving/removing a
       roadblock or placing the bridge, `_pad_snap_targets` returns ONLY that
       step's on-screen board spaces (buttons/cards come back only if none are
       on screen — the stick can still reach the toolbar to pan/fit).
    4. **Bridge undo:** after picking the first end, B (pad) or right-click
       (mouse) clears it to re-pick (`_bridge_undo_anchor`; human turns only);
       the prompt names the right one for the active input.
    5. **Debug dice boxes** (SpinBox) are snap targets; left/right on any slider
       or number box in an overlay adjusts it (`_pad_range_at_cursor`,
       generalizing the old volume-slider special case).
    Tests: `test_pad_debug_controls`, `test_pad_redraw_y`, and additions to
    `test_pad_back` (bridge undo both ways) and `test_pad_ingame_snap`
    (board-only targets).
  - **Phase B — still TODO:** button remapping, an official RT decision (see the
    Steam Input note), and a Steam Input config if a Steam release happens.
- **Deck fullscreen fix (2026-10-13).** `window/size/mode.linuxbsd=3` in
  project.godot: on Linux/gamescope the game now opens true-fullscreen — the
  "maximized" mode left the window at 720×1080 and the Deck squashed it.
  Windows keeps maximized-windowed. Re-test on the Deck.
- **Game icon (2026-10-12).** `assets/errands-icon.png` (256²) + multi-size
  `errands-icon.ico`, rendered from the player-car art; wired as `config/icon`
  (window/taskbar) and `config/windows_native_icon` (future exported .exe) in
  project.godot. The user's desktop has "Godot 4.7.1" and "Errands" shortcuts;
  Errands launches the game directly (`--path`) and carries the car icon.
- **Oversized-hand scrolling (2026-10-09).** A hand wider than the tray no longer runs
  off screen: `_hand_metrics` adds `_hand_scroll`/`max_scroll` (row pinned to the left
  limit and slid by the scroll), ◀ ▶ paddles at the row ends (`_add_hand_paddle`, only
  on the sides with more cards), cards scrolled past either end HIDE (`_card_in_view`,
  so they never slide under the action buttons), and the wheel is routed centrally in
  `_unhandled_input`: over an overflowing hand it pages the row INSTEAD of zooming the
  board (`_mouse_over_hand`, same pattern as the game-log carve-out). To clear the
  paddles' right lane, the **discard pile moved out of the bar** — it sits on the
  right edge under the view-button stack and **scales itself to the free gap**
  between the stack and the tray (`_position_discard_pile`: fit 0.7–1.5×, hugging
  the bar's top if the gap is still too tight; recomputed on every window resize
  via `_apply_safe_offset` and on `_populate_view_controls`). Scrolling is SMOOTH
  (2026-10-10): `_hand_scroll_by` glides cards via `_scroll_hand_row`/`_slide_card_to`
  (a card stays visible through the trip if in view at either end; a deferred
  `_relayout_hand_row(false)` strict-culls once settled) instead of rebuilding the
  row. Drag reorder keeps working — the one drop-slot formula reads the scrolled
  `start_x`. Built for debug gifts today, reusable for a custom big-hand game mode
  later. Test: `test_hand_scroll` (+ the reshaped `test_discard_pile_widget`).
- **Debug panel: category gifts (2026-10-09).** New row — **All Specials / All Duos /
  All Errands** gives the target player one of every card in that category
  (`_dbg_give_all`; All Errands arrives batched by district, alphabetical within each;
  also a handy stress test for the hand scrolling). Test: `test_dbg_give_all`.
- **Resizable game log (2026-10-09).** A ◢ grip in the log box's bottom-right corner
  drag-resizes its HEIGHT (64–560); the width stays locked to the info panel above so
  the left column keeps one clean edge (`_on_log_grip_input`/`_set_log_box_size`).
  Test: `test_log_resize`.
- **Lucky 20 card art updated (2026-09-21)** — the face now reads "…Lose a turn."
  matching the rule shipped in round 4 (user edited the master; copied into
  `assets/cards/specials/` + the `source-assets/` mirror).

- **Playtest backlog (2026-08 session, user + 2 CPUs).** Batch 1 — DONE (horizontal board with
  Neighborhood bottom-right, re-oriented district plates in board.png, upright location labels,
  uniform district-button zoom, window opens maximized). Remaining, in planned order:
  - **Batch 2 — information flow: DONE** (scrollable colour-coded game log incl. dice values;
    drawing an errand for your current spot completes instantly, chained through
    `_complete_errands_at`; CPU hands hidden + reactor's hand shown during Prevent/Thanks;
    camera glides to each player at turn start; plus HUD scaling for large screens —
    `UI_SCALE` 1.3 via content_scale_factor, menus counter-scaled, left boxes at
    `UI_SCALE_LEFT` 0.85, log font 18).
  - **Batch 3 — dice & prompts: DONE** (centre-screen dice tumble → land with total → linger →
    clear before move selection, `DICE_BIG`/`DICE_LAND_HOLD`; Prevent/Thanks prompts show the
    relevant card faces at 2×; Dumpster picker laid out in real window coords — title pinned top,
    per-row-centred grid, adaptive scale, 2.7× clamped in-place hover; game log box halved, wheel
    over it never zooms the board. Plus a **debug panel** — Debug Mode, `G` toggles: give any card,
    teleport, force dice, score ±1, fill discard, end turn, win now; remove before a final build).
  - **Batch 4 — hand management: DONE** (drag-to-reorder with pick-up + parting-gap preview,
    hover suppressed mid-drag; instants playable + reordering from the End Turn review —
    `_resume_end_gate` re-raises the gate, Lucky 3 excluded; free discard-&-redraw
    `REDRAW_LIMIT`=1/turn; discard pile widget pinned bottom-right corner at 1.6× with a
    read-only full-screen browser; "Where is this place?" toolbar button with bouncing
    outlined arrows, Duos frame both spots; top-right controls split into two columns —
    left: Menu + Players, right: Camera + Views).
  - **Batch 5 — rules & celebration: DONE** (dice-landing on an occupied space grants the LANDING
    player an extra turn — rides Free Turn, Home excluded, sends/Switcheroo don't trigger; win
    screen rains 460 palette confetti pieces with a per-letter waving title).
  - **Post-batch polish: DONE** — "CPU is thinking..." animated indicator replaces buttons whenever
    the game waits on a CPU (also stops humans clicking a CPU's reaction buttons), and the
    **bottom tray bar** redesign: full-width strip (`BOTTOM_BAR_H` 200) housing the hand at
    `HAND_SCALE` 1.5× (no slide-up tray; 1.9× window-clamped in-place hover), compact action
    buttons at its left end, discard pile + count chip at its right; all camera fits/focuses
    reserve the bar via `_zoom_to_fit`/`_bar_center_shift`.
  - **ALL 16 playtest items are now implemented.**
  - **Playtest round 3 (2026-08-29): DONE** — hand-input regression fixed (hand on canvas layer 2
    above the bar strip; cards STOP-filter; one cursor-position drop-slot formula so the drag gap
    never oscillates; hand row clamps clear of buttons/pile via `_hand_metrics`); roadblock/bridge
    placements zoom to the spot (CPU turns held ~1.6s via `_end_turn_after_beat`/`_turn_ending`/
    `_epoch`); turn chevron counter-rotates to stay above tokens on screen; finished CPUs race Home
    (errand weight ~1 when done, Lucky moves only for the winning hop, churn skipped); CPU
    thinking label in the bar.
  - **Playtest round 4 (2026-09-20): DONE, all 9 items** —
    1. **Confirm before playing**: hand clicks fire on mouse RELEASE (a drag never counts
       as a click any more) and clicking a Special raises a Play/Cancel window
       (`_pending == "confirm_play"`, `_confirm_index`, big context face; clicking another
       playable Special switches the pick; works from the End Turn review too).
    2. **Lucky 20 costs the next turn** (`skip_turns += 1` in `_play_lucky_move`; AI only
       spends it on a 2-pt payoff or the winning hop; discard-pile value demoted).
       ⚠ USER TODO: edit the Lucky 20 card art to say it loses the player their next turn.
    3. **Reaction attribution**: Prevent/Thanks prompts say who is playing what on whom
       (`_incoming_special_desc`, `_next_prevent_reactor` note).
    4. **Slow Traffic** down to 1 copy; 6. **Prevent** up to 3 copies.
    5. **2-pt faces fixed**: `_card_face_for` now discriminates Duo-vs-standard by
       `locations.size()`, not `count` (Beach/Lake had fallen through to the text fallback).
    7. **Road Hazard**: 4 copies, `MAX_ROADBLOCKS` 4 on the board; the card places a NEW
       block or MOVES an existing one (`hazard_choice` buttons / `hazard_pick_block` click
       flow; at the cap it's move-only; CPU lifts its least-useful block via
       `_ai_least_useful_block` / `_ai_hazard_would_help`).
    8. **Dumpster reveal**: the log names who took what, and a CPU's pick is shown as a
       card face beside "thinking" for ~3s (`_dd_reveal`).
    9. **Usability gating**: `_special_usable` — Prevent needs a block out, Dumpster needs
       a non-empty pile, Thanks is reaction-only; unusable Specials don't highlight, click,
       or count for the "play a Special" hint, in ROLL and at the End Turn gate alike.
  - **Card point values (`ERRAND_VALUE`):** all standard errands 1 pt EXCEPT Beach/Lake/Golf = 2
    (art carries its own ×2 marker; the generated "N pts" chip only appears on the art-less
    fallback layout). Duos = 1 pt — either location redeems them; flexibility is the bonus, not
    points. Values flow through everything via the card's `count`. Golf stays out of the deck
    until it gets a board space.

- **Sent-to-location completes errands — DONE.** Being sent to a location (To the Beach/Lake/Get
  Music, and Switcheroo for either swapped player) now auto-completes any matching errand the moved
  player holds (`_complete_errands_at` / `_complete_errands_on_space`). The CPU avoids gifting an
  errand this way, scaled by difficulty (`_ai_send_target`, `SEND_DEST`): Hard never gifts (skips the
  send if every opponent holds it), Medium prefers a non-gifting target, Easy has no awareness.

## OPEN DECISIONS
- (none open)

## RESOLVED (2026-09-20 playtest check-in)
- **Hand drag-reorder** verified in real play — feels good. Done.
- **Win-target-3 balance** with 2-pt Beach/Lake: user is not worried; no change.
- **Golf:** NOT getting a board space — its art + `ERRAND_VALUE` entry stay dormant.
- **Debug panel stays** for now (still remove before a true final build).

## Notes / source material
- Source board-game assets (masters, per-location JPGs, card PDFs, rules) are in the repo at
  `source-assets/` (Godot ignores it via `.gdignore`); the original lives at
  `C:/Users/Claudia/Documents/Errands Board Game/` on the first machine. The 12 layered
  board .xcf masters (>100 MB each) exist ONLY there — see the new-machine checklist.
- Deck composition (`ERRAND_COPIES`, special `copies`) is tunable/untuned.
- Bridge span is `BRIDGE_REACH` (view px, tunable). Move/slide timings: `STEP_TIME`, `SLIDE_TIME`.
