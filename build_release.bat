cd shaders
call compile.bat
cd ..
call odin.exe build ./src -subsystem:window -out:out/release.exe -opt:3 -no-bounds-check -resource:resources.rc