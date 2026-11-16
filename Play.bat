@echo off
rem Launch the game. Needs Godot 4.7 on PATH as "godot", or set GODOT to the Godot executable.
if defined GODOT (set "GODOT_EXE=%GODOT%") else (set "GODOT_EXE=godot")
start "" "%GODOT_EXE%" --path "%~dp0."
