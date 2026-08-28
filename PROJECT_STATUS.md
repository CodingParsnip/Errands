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
- Windows machine. Repo: `C:/Users/Claudia/Documents/GitHub/Errands` (GitHub Desktop
  clone of private repo `CodingParsnip/Errands`, branch `main`). User pushes via
  **GitHub Desktop** (no push creds in the agent environment; the agent commits locally).

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
  - **Golf:** art exists in `Cards/Standard/Country/` but there is NO `Golf` board location. Left OUT
    pending a decision (replace an existing location, or add a new board space).
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
- Sound, nicer menus/animation.

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
  - **Batch 5 — rules & celebration:** landing on a space occupied by another player gives the
    LANDING player an extra turn (user-confirmed rule); confetti/celebration on the win screen.

- **Sent-to-location completes errands — DONE.** Being sent to a location (To the Beach/Lake/Get
  Music, and Switcheroo for either swapped player) now auto-completes any matching errand the moved
  player holds (`_complete_errands_at` / `_complete_errands_on_space`). The CPU avoids gifting an
  errand this way, scaled by difficulty (`_ai_send_target`, `SEND_DEST`): Hard never gifts (skips the
  send if every opponent holds it), Medium prefers a non-gifting target, Easy has no awareness.

## OPEN DECISIONS
- (none open)

## Notes / source material
- Source board-game assets (masters, GIMP .xcf, per-location JPGs, card PDFs, rules) live in
  `C:/Users/Claudia/Documents/Errands Board Game/`.
- Deck composition (`ERRAND_COPIES`, special `copies`) is tunable/untuned.
- Bridge span is `BRIDGE_REACH` (view px, tunable). Move/slide timings: `STEP_TIME`, `SLIDE_TIME`.
