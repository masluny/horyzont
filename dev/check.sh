#!/bin/bash
# Parses every GDScript in the project and prints errors.
cd "$(dirname "$0")/.."
godot --headless --path . --import > /dev/null 2>&1
for f in $(find scripts -name "*.gd"); do
	out=$(godot --headless --path . --check-only --script "res://$f" 2>&1 | grep -E "SCRIPT ERROR|Parse Error|ERROR" | grep -v -e "depended" -e "Identifier not found: Game" -e "with error \"Compilation failed\"" | head -3)
	[ -n "$out" ] && echo "== $f" && echo "$out"
done
echo "check done"
