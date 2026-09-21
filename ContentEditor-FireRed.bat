@echo off
setlocal
cd /d "%~dp0"
set "POKEPORT_RECOMP=%~1"
if not defined POKEPORT_RECOMP set "POKEPORT_RECOMP=%USERPROFILE%\Downloads\gen1recomp-dev\gen1recomp-dev"
if not exist "%POKEPORT_RECOMP%\src\core\GameVersion.lua" (
  echo Pass your Gen1Recomp checkout folder as the first argument.
  pause
  exit /b 1
)
set "POKEPORT_VERSION=firered"
call "%~dp0ContentEditor.bat"
endlocal
