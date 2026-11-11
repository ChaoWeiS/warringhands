#!/usr/bin/env bash
# Runs every tests/test_*.gd headless. Fails if any test reports FAIL,
# hits a script error, or exits non-zero.
#
# Usage (from the project folder):  tests/run_tests.sh
# Needs `godot` on the PATH and the project imported once (godot --headless --import).
set -uo pipefail

cd "$(dirname "$0")/.."
status=0

# The multiplayer relay server, for tests/test_online.gd (skipped without Node).
relay_pid=""
if command -v node >/dev/null 2>&1; then
	if [ ! -d server/node_modules ]; then
		(cd server && npm ci --no-fund --no-audit >/dev/null 2>&1)
	fi
	echo "=== server (npm test)"
	server_log="$(cd server && npm test --silent 2>&1)"
	echo "$server_log" | grep -E "^(PASS|FAIL)|FAILURES"
	if echo "$server_log" | grep -qE "^FAIL" || ! echo "$server_log" | grep -q "FAILURES: 0"; then
		echo "!!! server tests failed"
		status=1
	fi
	(cd server && PORT=18766 exec node index.js >/dev/null 2>&1) &
	relay_pid=$!
	export WH_SERVER="ws://127.0.0.1:18766"
	sleep 1
fi
trap '[ -n "$relay_pid" ] && kill "$relay_pid" 2>/dev/null' EXIT
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
