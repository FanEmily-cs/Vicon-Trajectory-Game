@echo off
setlocal
set "MATLAB_EXE=%ProgramFiles%\MATLAB\R2025b\bin\matlab.exe"
if exist "%MATLAB_EXE%" goto launch
set "MATLAB_EXE="
for /f "delims=" %%M in ('where matlab.exe 2^>nul') do if not defined MATLAB_EXE set "MATLAB_EXE=%%M"
if defined MATLAB_EXE goto launch
echo MATLAB was not found. Install MATLAB or edit MATLAB_EXE in this BAT.
pause
exit /b 1
:launch
start "Vicon_Trajectory_UM" /min "%MATLAB_EXE%" -nosplash -sd "%~dp0." -batch "f=Vicon_Trajectory_UM; waitfor(f);"
exit /b 0
