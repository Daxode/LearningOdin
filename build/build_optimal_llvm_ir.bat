call build/pre_build.bat
call odin.exe build ./src -subsystem:window -opt:3 -out:out/llvm-ir.ll -build-mode:llvm-ir -no-bounds-check