#!/bin/bash
# Runs the game with a watchdog. Usage: dev/run.sh <seconds> [godot args...] [-- game args]
# Prints shader/script errors from the log.
cd "$(dirname "$0")/.."
LIMIT=$1; shift
mkdir -p dev/out
LOG=dev/out/log.txt
godot --path . "$@" > "$LOG" 2>&1 &
PID=$!
for i in $(seq 1 "$LIMIT"); do sleep 1; kill -0 $PID 2>/dev/null || break; done
kill $PID 2>/dev/null && echo "(killed after ${LIMIT}s)"
grep -E "SHADER ERROR|ERROR|SCRIPT ERROR|Parse Error|E +[0-9]+->|at: \(|WARNING" "$LOG" | grep -v "^   at:" | awk '!seen[$0]++' | head -${MAXERR:-30}
grep -E "^(shot saved|BENCH)" "$LOG"
