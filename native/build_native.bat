@echo off
rem Builds NikkeGunMode.dll with the Visual Studio 2019 compiler already on this PC.
setlocal
set "HERE=%~dp0"
call "C:\Program Files (x86)\Microsoft Visual Studio\2019\Community\VC\Auxiliary\Build\vcvars64.bat" >nul
if not exist "%HERE%build" mkdir "%HERE%build"
cl /nologo /LD /O2 /MT /EHa /W3 /std:c++17 "%HERE%ngm_native.cpp" /Fe"%HERE%build\NikkeGunMode.dll" /Fo"%HERE%build\\" /link /NOLOGO
exit /b %ERRORLEVEL%
