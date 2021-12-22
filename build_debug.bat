cd shaders
call compile.bat
cd ..
call odin.exe build ./src -subsystem:console -out:out/debug.exe -opt:0 -debug