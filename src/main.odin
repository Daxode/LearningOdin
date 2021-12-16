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
    win32.ReadFile(input_handle, raw_data(input_bytes), u32(len(input_bytes)), &single_read_length, nil)

    // Loop through every byte
    val_fifo: [4]u32 = 0
    shift_amount: u32 = 1
    answer : u32 = 0
    for i := len(input_bytes)-1; i >= 0; i -= 1 {
        digit := u32(input_bytes[i] - '0')
        
        // When new line means done parsing one num (218 is '\n'-'0' in u8 underflow)
        if (digit == 218) {
            val_fifo = transmute([4]u32)(transmute(u128) val_fifo << 32)
            val_fifo[0] = 0
            shift_amount = 1
            continue
        } 

        val_fifo[0] += digit * shift_amount
        shift_amount *= 10
    }

    fmt.println(answer)

    delete(input_bytes)
    win32.CloseHandle(input_handle)
}