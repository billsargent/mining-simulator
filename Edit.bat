@echo off
rem Open the project in the Godot editor. Needs Godot 4.7 on PATH as "godot", or set GODOT.
if defined GODOT (set "GODOT_EXE=%GODOT%") else (set "GODOT_EXE=godot")
start "" "%GODOT_EXE%" --path "%~dp0." -e
