#!/bin/bash
# Double-click to play (opens Terminal). Logs go to ~/Library/Logs/horyzont.log
cd "$(dirname "$0")"
exec /Applications/Godot.app/Contents/MacOS/Godot --path . "$@"
