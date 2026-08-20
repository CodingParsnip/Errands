#!/bin/sh
# Run the Errands headless test suite.
#   exit 0  -> every assertion passed
#   exit 1  -> a test failed, or a script/parse error, or the suite didn't finish
#   exit 2  -> couldn't find the Godot binary
#
# Godot binary: defaults to the known local install; override with GODOT_BIN.
# Usage: bash tests/run.sh
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GODOT="${GODOT_BIN:-C:/Users/Claudia/Downloads/Godot_v4.7.1-stable_win64.exe/Godot_v4.7.1-stable_win64_console.exe}"

if [ ! -f "$GODOT" ]; then
	echo "run.sh: Godot binary not found at:" >&2
	echo "        $GODOT" >&2
	echo "        Set GODOT_BIN to your Godot 4.7.1 console executable." >&2
	exit 2
fi

# --quit-after is only a hang safety net; the suite quits itself when done.
OUT="$("$GODOT" --headless --path "$ROOT" --quit-after 3000 res://tests/Tests.tscn 2>&1)"

# Show the suite's own output (skip the engine boot noise before it).
echo "$OUT" | sed -n '/Errands test suite/,$p'

# A compile/parse error means Main (or a test) failed to load — always a failure.
if echo "$OUT" | grep -qiE "parse error|script error|failed to (load|instantiate)"; then
	echo "run.sh: script/parse error detected." >&2
	echo "$OUT" | grep -iE "parse error|script error|error" | head -20 >&2
	exit 1
fi

# Require a clean summary with a positive pass count and zero failures. This also
# catches a crash that ends the run before the summary is printed.
if echo "$OUT" | grep -qE "RESULT: [1-9][0-9]* passed, 0 failed"; then
	exit 0
fi

echo "run.sh: test suite did not pass cleanly." >&2
exit 1
