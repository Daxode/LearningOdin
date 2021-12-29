call build/pre_build.bat
call odin.exe build ./src -subsystem:console -out:out/debug.exe -opt:0 -debug -define:DAX_DEBUG_CMD=true