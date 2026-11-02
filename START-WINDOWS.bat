@echo off
cd /d "%~dp0"
py -3 --version >nul 2>&1
if not errorlevel 1 (
  py -3 start_game.py
  pause
  exit /b
)
python --version >nul 2>&1
if not errorlevel 1 (
  python start_game.py
  pause
  exit /b
)
echo This launcher requires Python 3, available from https://www.python.org/downloads/
echo Alternatively, play through the project's GitHub Pages site once it is enabled.
pause
