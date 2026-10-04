@echo off
setlocal enabledelayedexpansion
title MyLangLean PC Server (uvicorn :8000)

rem ============================================================
rem  MyLangLean PC service one-click launcher
rem
rem  Usage (this script file, double-click = no argument):
rem    (none)        Start if idle; if running ask:
rem                  R = force restart, Q = open admin (default)
rem    start         Same as no-arg (non-interactive: start/open admin)
rem    restart       Force-stop the running server, then start it again
rem    stop          Force-stop only
rem
rem  Stop strategy (safe, never "taskkill /IM python.exe"):
rem    1) Find LISTENING PID(s) on port 8000, verify the process command line
rem       contains uvicorn/app.main (or image name is python), then
rem       Stop-Process by exact PID only.
rem    2) If its parent is a cmd.exe launched from a .bat (this launcher),
rem       stop that parent console PID as well so no pause window is left.
rem ============================================================

set "ACTION=%~1"
if "%ACTION%"=="" set "ACTION=menu"

set "ROOT=%~dp0"
set "PY=%ROOT%.tools\venvs\mll\Scripts\python.exe"
set "ADB=%ROOT%.tools\android-sdk\platform-tools\adb.exe"
set "URL=http://127.0.0.1:8000"

if /I "%ACTION%"=="stop"   goto :doStop
if /I "%ACTION%"=="restart" goto :doRestart
goto :doStart

rem ------------------------------------------------------------
rem :portBusy -> errorlevel 0 when something listens on 8000
:portBusy
netstat -ano | findstr ":8000 " | findstr LISTENING >nul 2>&1
exit /b %errorlevel%

rem ------------------------------------------------------------
:doStop
echo [STOP] Stopping MyLangLean server on port 8000 ...

rem Precise recycle, never "taskkill /IM python.exe":
rem   1) Find LISTENING PID(s) on port 8000, verify command line.
rem   2) Snapshot the whole parent chain FIRST (the venv wrapper exits
rem      immediately once its child dies, so kill-as-you-walk misses it),
rem      then terminate in REVERSE order - launcher cmd first (this stops
rem      it from re-reading this file and relaunching), then pythons:
rem        - cmd.exe launched from a .bat  -> the launcher console
rem        - python with uvicorn/app.main  -> wrapper and real server
rem        - anything else (explorer/pwsh) -> stop walking
rem   All inner quoting is single-quoted; the outer pair belongs to cmd.
powershell -NoProfile -ExecutionPolicy Bypass -Command "$ErrorActionPreference='SilentlyContinue'; $k=@(); $lpids=@(Get-NetTCPConnection -LocalPort 8000 -State Listen | Select-Object -Expand OwningProcess -Unique); foreach($id in $lpids){ $cur=Get-CimInstance Win32_Process -Filter ('ProcessId=' + $id); if(-not $cur){continue}; $cl=[string]$cur.CommandLine; if(-not (($cl -match 'uvicorn') -or ($cl -match 'app\.main') -or ($cur.Name -match 'python'))){continue}; $chain=@(); $n=$cur; for($i=0; $n -and ($i -lt 6); $i++){ $chain += $n; $pp=[int]$n.ParentProcessId; if($pp -eq [int]$n.ProcessId){break}; $n=Get-CimInstance Win32_Process -Filter ('ProcessId=' + $pp) }; $targets=@(); foreach($n in $chain){ $c=[string]$n.CommandLine; if(($n.Name -match 'python') -and ($c -match 'uvicorn|app\.main')){ $targets += ('python ' + $n.ProcessId) } elseif(($n.Name -eq 'cmd.exe') -and ($c -match '\.bat')){ $targets += ('console ' + $n.ProcessId); break } else { break } }; [array]::Reverse($targets); foreach($t in $targets){ $tp=([string]$t).Split(' ')[1]; Stop-Process -Id ([int]$tp) -Force -ErrorAction SilentlyContinue; $k += $t } }; if($k.Count -gt 0){ Write-Output ('[STOP] Stopped: ' + ($k -join ', ')) } else { Write-Output '[STOP] No uvicorn listener found on port 8000' }"

rem 3) Wait until the port is released (max ~10s).
set "WAITS=0"
:waitRelease
call :portBusy
if errorlevel 1 goto :stopped
set /a WAITS+=1
if %WAITS% GEQ 10 goto :stopTimeout
ping 127.0.0.1 -n 2 >nul
goto :waitRelease

:stopTimeout
echo [WARN] Port 8000 is still busy after 10s. Check the process manually.
exit /b 1

:stopped
echo [STOP] Port 8000 released.
exit /b 0

rem ------------------------------------------------------------
:doRestart
call :doStop
echo.
echo [RESTART] Starting server again...
echo.
goto :launch

rem ------------------------------------------------------------
:doStart
call :portBusy
if errorlevel 1 goto :launch

echo [INFO] Port 8000 is already listening.
if /I "%ACTION%"=="start" (
  start "" "%URL%/admin"
  exit /b 0
)
if /I "%ACTION%"=="menu" (
  rem Non-interactive sessions take the default Q immediately.
  choice /C RQ /N /T 8 /D Q /M "Press R to force restart, Q to just open the admin console (auto Q in 8s): "
  if errorlevel 2 (
    start "" "%URL%/admin"
    exit /b 0
  )
  if errorlevel 1 goto :doRestart
)
start "" "%URL%/admin"
exit /b 0

rem ------------------------------------------------------------
:launch
rem Interpreter: prefer the bundled venv (no extra installs).
if not exist "%PY%" (
  echo [WARN] Bundled venv not found: %PY%
  echo [WARN] Falling back to system python ^(pip install -r server\requirements.txt first^).
  set "PY=python"
)

rem Set up adb reverse automatically when an authorized device is online.
if exist "%ADB%" (
  "%ADB%" devices | findstr /R /C:"device$" >nul 2>&1
  if not errorlevel 1 (
    "%ADB%" reverse tcp:8000 tcp:8000 >nul 2>&1
    echo [OK] adb reverse tcp:8000 established ^(device reaches server via 127.0.0.1:8000^)
  ) else (
    echo [INFO] No authorized device detected, skipping adb reverse.
  )
)

echo.
rem Open Windows Firewall for Wi-Fi clients + show this PC's LAN IP.
powershell -NoProfile -ExecutionPolicy Bypass -Command "$names=@('MyLangLean Server TCP 8000','MyLangLean Discovery UDP 43800'); $ports=@(8000,43800); $protos=@('TCP','UDP'); for($i=0;$i -lt 2;$i++){ if(-not (Get-NetFirewallRule -DisplayName $names[$i] -ErrorAction SilentlyContinue)){ try { New-NetFirewallRule -DisplayName $names[$i] -Direction Inbound -Action Allow -Protocol $protos[$i] -LocalPort $ports[$i] -ErrorAction Stop | Out-Null; Write-Output ('[OK] Firewall opened for Wi-Fi clients: ' + $names[$i]) } catch { Write-Output '[WARN] Need administrator rights to open the firewall.'; Write-Output '[WARN] Right-click this launcher and choose Run as administrator once,'; Write-Output '[WARN] or click Allow when Windows asks about Python network access.' } } }; $ip=Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue | Where-Object { $_.IPAddress -notlike '127.*' -and $_.IPAddress -notlike '169.254.*' } | Select-Object -First 1 -ExpandProperty IPAddress; if($ip){ Write-Output ('[INFO] This PC LAN address: ' + $ip); Write-Output ('[INFO] Phone Wi-Fi server URL: http://' + $ip + ':8000') }"

echo ============================================================
echo   MyLangLean PC server is starting...
echo   Health check : %URL%/health
echo   API docs     : %URL%/docs
echo   Admin console: %URL%/admin   (header X-Admin-Token: dev-admin-token)
echo   Restart/stop : run this script with "restart" or "stop"
echo   Press Ctrl+C to stop.
echo ============================================================
echo.

rem Open the admin console after ~3s (detached, does not block uvicorn).
start "mll-open-admin" /min cmd /c "ping 127.0.0.1 -n 4 >nul && start """" %URL%/admin"

cd /d "%ROOT%server"
"%PY%" -m uvicorn app.main:app --host 0.0.0.0 --port 8000

echo.
echo [EXIT] Server stopped.
pause
