package advent_of_code_d15

import "core:fmt"
import "core:os"
import win32 "core:sys/windows"

main::proc()
{
    // Get file handle
    input_handle := win32.CreateFileW(
        win32.utf8_to_wstring("input.txt"), win32.FILE_GENERIC_READ, 
        win32.FILE_SHARE_READ, nil, win32.OPEN_EXISTING,
        win32.FILE_ATTRIBUTE_NORMAL|win32.FILE_FLAG_BACKUP_SEMANTICS, nil)
    
    // Get file Length and make array to fit
    input_file_length : win32.LARGE_INTEGER
    win32.GetFileSizeEx(input_handle, &input_file_length)
    input_bytes := make([]u8, input_file_length)
    
    // Read file into input_bytes
    single_read_length: win32.DWORD
    win32.ReadFile(input_handle, raw_data(input_bytes), win32.DWORD(len(input_bytes)), &single_read_length, nil)

    for i in 0..<len(input_bytes) {
        input_bytes[i] -= '0'
    }
    
    fmt.println(input_bytes)

    delete(input_bytes)
    win32.CloseHandle(input_handle)
}