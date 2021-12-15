package advent_of_code_d15

import "core:fmt"
import "core:os"

main::proc()
{
    input_handle, _ := os.open("input.txt")
    input_file_length, _ := os.file_size(input_handle)
    input_bytes := make([]u8, input_file_length)
    os.read_full(input_handle, input_bytes)

    width := 0
    for input_byte, i in input_bytes {
        if input_byte == '\n' { 
            width = i+1
            break
        }
    }

    for input_byte in &input_bytes {
        input_byte -= '0'
    }
    
    fmt.println(input_bytes, width)

    delete(input_bytes)
    os.close(input_handle)
}