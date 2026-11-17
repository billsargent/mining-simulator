@echo off
rem Build the game for Windows, Linux and macOS into build\.
rem Needs Godot 4.7 on PATH as "godot" (or GODOT set) and its export templates installed
rem (Editor > Manage Export Templates). The GitHub "Build" workflow makes the same builds.
if defined GODOT (set "GODOT_EXE=%GODOT%") else (set "GODOT_EXE=godot")
cd /d "%~dp0."
if not exist build\windows mkdir build\windows
if not exist build\linux mkdir build\linux
if not exist build\macos mkdir build\macos
"%GODOT_EXE%" --headless --path . --import
"%GODOT_EXE%" --headless --path . --export-release "Windows" build/windows/Paystreak.exe
"%GODOT_EXE%" --headless --path . --export-release "Linux" build/linux/Paystreak.x86_64
"%GODOT_EXE%" --headless --path . --export-release "macOS" build/macos/Paystreak.zip
echo Builds are in the build folder.
pause
