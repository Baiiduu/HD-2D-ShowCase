#!/bin/sh
# Renders the five reference screenshots into ./screenshots
cd "$(dirname "$0")"
"/d/Project/godot/Godot_v4.7.2/Godot_v4.7.2-stable_win64_console.exe" --path . -- --screenshots "$@"
