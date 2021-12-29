call build/pre_build.bat
call odin.exe build ./src -subsystem:window -opt:3 -out:out/asm.S -build-mode:assembly -no-bounds-check -debug