@echo off
setlocal

powershell -ExecutionPolicy Bypass -File "%~dp0configure-esp-remote.ps1"

if errorlevel 1 (
  echo.
  echo Echec de la configuration ou du flash.
  exit /b 1
)

echo.
echo Configuration et flash termines.
exit /b 0