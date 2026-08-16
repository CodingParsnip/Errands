# Errands — Project Status & Handoff

A homemade board game ("Errands") ported to a playable **Godot 4.7.1** video game.
This file is the source of truth for continuing the project in a fresh session.

## How to run
- **Game:** open the project in Godot 4.7.1, press **F5** (runs `scenes/Main.tscn`).
  Start menu → **Play** (normal) / **Debug Mode** (enables the `G` test-hand key) / **Quit**.
- **Board tracer tool:** open `scenes/BoardEditor.tscn`, press **F6** (Run Current Scene).
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
  win-target picker (3/5/8/10 → `win_target` var), **Opponent picker (Human / CPU)**, Quit, Debug Mode.
- **AI opponent (CPU):** Player 2 can be a CPU (start-menu toggle → `_p2_is_ai`, per-player
  `is_ai` flag). Driven through the same entry points a human uses; a scheduler hooked into
  `_update_hud` (`_ai_tick`/`_ai_act`) acts on a short timer whenever the game waits on a CPU —
  on its own turn AND during `react_prevent`/`react_thanks` on the human's turn. Turn policy:
  play Free Turn → a Lucky 12/20 that lands an errand or wins → disrupt a near-winner with a
  Send/Slow → Lucky 3 → else roll; in MOVE it scores destinations (errands ≫ progress toward the
  nearest needed shop, or toward Home once it has enough). See the **AI OPPONENT** section in Main.gd.
- **HUD/polish:** dark RichTextLabel info panel + scoreboard, per-player colour coding
  (P1 red, P2 cyan) with token halos + turn indicator, inline pip-dice roll readout,
  sliding tokens for send/swap, contextual **mouse action buttons** (Roll Dice, reaction
  choices, Play Again) so the game is fully mouse-playable. Keyboard shortcuts still work.
- **Debug:** in Debug Mode, press **G** to load a test hand of Specials (remove before final).

## OPEN / TODO
- **Standard card art — 33 of 35 locations DONE (2 variants each).** Finished faces render in the
  hand via the `CARD_FACE_PATHS` map (location name → Array of `res://` variant paths). Each errand's
  two deck copies get `face_variant` 0/1 (`_build_deck`), stored on the card dict so the shown art is
  stable across HUD refreshes; `_card_face_for` picks the variant, `_fill_errand_card` draws the full
  image (bg + photo + title + caption, 750×1050 ≈ the 84×116 slot). To add more: drop
  `card-<district>-<loc>N.png` in `assets/cards/standard/<District>/` and add/extend a `CARD_FACE_PATHS`
  line. Preview via **Debug Mode → G**. Source faces live in `Cards/Standard/` named
  `card-<district>-<location>N.png`.
  - **No art yet:** Beach, Fair → still show the color-strip placeholder (graceful fallback).
  - **Golf:** art exists in `Cards/Standard/Country/` but there is NO `Golf` board location (that
    district has `Beach`). Left OUT pending a decision (replace Beach/Fair, or add a new board space).
  - **Still text (no art wired):** Duos (art in `Cards/Duos/`), Specials (`Cards/Specials/`).
- **AI opponents — DONE for 2-player** (see the DONE section). Possible follow-ups: difficulty
  levels, and teaching the CPU the click-based Specials it currently won't play (Road Hazard,
  Shortcut, Dumpster Diving) plus Switcheroo / New Hand / Lucky 2 offense.
- **3+ players** — currently hard-coded 2 players; `_target_player()` returns the single
  opponent. Needs a real target-picker and more token colours. (AI targeting/reactions also
  assume one opponent, so they'd need the same generalization.)
- **Remove the debug `G` key** before a "final" build.
- Sound, nicer menus/animation.

## OPEN DECISIONS
- Being **sent** to a location (To the Beach/Lake/Get Music, Switcheroo) currently does NOT
  auto-complete an errand for the moved player (implemented as purely hindering). User was
  undecided — revisit.

## Notes / source material
- Source board-game assets (masters, GIMP .xcf, per-location JPGs, card PDFs, rules) live in
  `C:/Users/Claudia/Documents/Errands Board Game/`.
- Deck composition (`ERRAND_COPIES`, special `copies`) is tunable/untuned.
- Bridge span is `BRIDGE_REACH` (view px, tunable). Move/slide timings: `STEP_TIME`, `SLIDE_TIME`.
