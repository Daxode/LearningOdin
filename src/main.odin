package advent_of_code_d15

import "core:fmt"
import "core:os"
import win32 "core:sys/windows"
import "core:time"

main::proc()
{
    // Get start time
    start_time := time.tick_now()
    
    // All three segments could be replaced with `input_bytes, _ := os.read_entire_file("input.txt")`
    
    // Get file handle | Can be replaced with `input_handle, _ = os.open("input.txt")`
    input_handle := win32.CreateFileW(
        win32.utf8_to_wstring("input.txt"), win32.FILE_GENERIC_READ, 
        win32.FILE_SHARE_READ, nil, win32.OPEN_EXISTING,
        win32.FILE_ATTRIBUTE_NORMAL|win32.FILE_FLAG_BACKUP_SEMANTICS, nil)
    
    // Get file Length and make array to fit | Can be replaced with `input_file_length, _ = os.file_size(input_handle)`
    input_file_length : win32.LARGE_INTEGER
    win32.GetFileSizeEx(input_handle, &input_file_length)
    input_bytes := make([]u8, input_file_length)
    
    // Read file into input_bytes | Can be replaced with `input_file_length, _ = os.read_full(input_handle, input_bytes)`
    single_read_length: win32.DWORD
    win32.ReadFile(input_handle, raw_data(input_bytes), u32(len(input_bytes)), &single_read_length, nil)

    // Loop through every byte
    val_fifo: [4]u32 = 0
    shift_amount: u32 = 1
    answer : u32 = 0
    for i := len(input_bytes)-1; i >= 0; i -= 1 {
        digit := u32(input_bytes[i] - '0')
        
        // When new line means done parsing one num (218 is '\n'-'0' in u8 underflow)
        eol := u32(digit == 218)
        answer += eol*u32(val_fifo[0] < val_fifo[3]) // add answer when end of line
        val_fifo = (transmute([4]u32)(transmute(u128) val_fifo << 32))*eol+(1-eol)*val_fifo // shift buffer when eol
        val_fifo[0] += (1-eol) * digit*shift_amount // Add when not eol
        shift_amount = (eol + (1-eol)*shift_amount*10) // Set 1 when eol, otherwise mul shift_amount by 10
    }

    // Clean up
    delete(input_bytes)
    win32.CloseHandle(input_handle)

    // Print answer
    fmt.println(answer,"found in:", time.duration_milliseconds(time.tick_diff(start_time, time.tick_now())))
}