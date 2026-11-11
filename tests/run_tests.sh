#!/usr/bin/env bash
# Runs every tests/test_*.gd headless. Fails if any test reports FAIL,
# hits a script error, or exits non-zero.
#
# Usage (from the project folder):  tests/run_tests.sh
# Needs `godot` on the PATH and the project imported once (godot --headless --import).
set -uo pipefail

cd "$(dirname "$0")/.."
status=0
for test in tests/test_*.gd; do
	echo "=== $test"
	log="$(mktemp)"
	timeout 240 godot --headless -s "res://$test" >"$log" 2>&1
	code=$?
	grep -E "^(PASS|FAIL)|SCRIPT ERROR|FAILURES" "$log"
	if [ $code -ne 0 ] || grep -qE "^FAIL |SCRIPT ERROR" "$log"; then
		echo "!!! $test failed (exit $code). Full log:"
		cat "$log"
		status=1
	fi
	rm -f "$log"
done
exit $status
