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
    aim: u32
    start_letter: u8
    set_value := true
    for input_byte, i in input_bytes {
        switch {
            case input_byte == '\n':
                num := u32(input_bytes[i-1]-'0')
                switch start_letter {
                    case 'f':
                        pos[0] += num
                        pos[1] += num * aim
                    case 'd':
                        aim += num
                    case 'u':
                        aim -= num
                }
                set_value = true
            case set_value:
                start_letter = input_byte
                set_value = false
        }
    }

    answer := pos[0]*pos[1]

    // Clean up
    delete(input_bytes)

    // Print answer
    fmt.println(answer,"found in:", time.duration_milliseconds(time.tick_diff(start_time, time.tick_now())))
}