# Errands test suite

Headless tests that instance the real game (`scenes/Main.tscn`) and drive its
logic through the same functions a game uses, then assert on the results. No
extra framework — just Godot running one scene.

## Run the tests

```bash
bash tests/run.sh
```

Exit code `0` = all passed, `1` = something failed (a test, a parse/script
error, or the suite crashed before finishing), `2` = Godot binary not found.

The Godot binary defaults to the known local install
(`Godot_v4.7.1-stable_win64_console.exe`). Override it with an env var:

```bash
GODOT_BIN="/path/to/godot_console.exe" bash tests/run.sh
```

## Run before every commit (git hook)

A pre-commit hook lives in `hooks/pre-commit`. It's tracked in the repo, so
enable it once per clone with:

```bash
git config core.hooksPath hooks
```

After that, every `git commit` runs the suite first and aborts the commit if it
fails. Bypass in an emergency with `git commit --no-verify`.

## What's covered

- Board graph loads; Home and key locations (Beach/Fair/Lake/Music/Park) present.
- Deck builds with both errand and Special cards; errands carry a `face_variant`.
- **Card art:** every appearing errand location has finished art (no placeholder),
  and every referenced face file (standard variants, Duos, Specials) exists.
- Landing on a location completes matching errands and consumes the card.
- Being **sent** to a location (send Specials / Switcheroo) auto-completes the
  moved player's matching errand; no false completion without the card.
- **AI gift guard** by difficulty: Hard avoids/skips gifting, Medium prefers a
  safe target, Easy targets the leader regardless.
- View toolbar builds Camera/Views/Players buttons at one uniform width.
- In-game HUD anchors to the window edges (`_apply_safe_offset`).

## Adding a test

Add a `test_*` method to `tests/TestRunner.gd`, then list its name in the
`tests` array in `_ready()`. Use `_new_main([seat_modes])` to get a fresh started
game, `_check(cond, msg)` / `_eq(got, expected, msg)` to assert, and `m.free()`
at the end.
