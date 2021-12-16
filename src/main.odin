package advent_of_code_d15

import "core:fmt"
import "core:os"
import "core:time"

main::proc()
{
    // Get start time
    start_time := time.tick_now()

    // Read file into ram
    input_bytes, _ := os.read_entire_file("input.txt")

    // Loop through every byte
    pos: [2]u32 = {0, 0}
    num: u32
    for i := len(input_bytes)-1; i >= 0; i -= 1 {
        switch input_bytes[i] {
            case '0'..'9':
                num = u32(input_bytes[i]-'0')
            case '\n':
                switch input_bytes[i+1] {
                    case 'f':
                        pos[0] += num
                    case 'd':
                        pos[1] += num
                    case 'u':
                        pos[1] -= num
                }
        }
    }

    switch input_bytes[0] {
        case 'f':
            pos[0] += num
        case 'd':
            pos[1] += num
        case 'u':
            pos[1] -= num
    }

    answer := pos[0]*pos[1]

    // Clean up
    delete(input_bytes)

    // Print answer
    fmt.println(answer,"found in:", time.duration_milliseconds(time.tick_diff(start_time, time.tick_now())))
}