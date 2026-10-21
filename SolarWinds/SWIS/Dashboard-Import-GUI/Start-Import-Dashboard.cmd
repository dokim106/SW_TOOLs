@echo off
rem Opens the dashboard import window (Windows PowerShell 5.1).
powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -File "%~dp0Import-Dashboard-GUI.ps1"
