@echo off
for /F "delims=" %%p in ('vswhere -latest -find **\vcvarsall.bat') do set vcvarsall="%%p"

call %vcvarsall% %1 %2
set
