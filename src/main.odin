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
    frequency_counter: [12]i8 = 0
    for input_byte, i in input_bytes {
        if i % 13 == 12 {continue}
        frequency_counter[i % 13] += (i8(input_byte-'0')*2)-1
    }

    gamma: u16 = 0
    epsilon: u16 = 0
    for frequency_count, i in frequency_counter {
        gamma |= u16(frequency_count>0) << u8(11-i)
        epsilon |= u16(frequency_count<0) << u8(11-i)
    }

    answer := gamma * epsilon

    // Clean up
    delete(input_bytes)

    // Print answer
    fmt.println(answer,"found in:", time.duration_milliseconds(time.tick_diff(start_time, time.tick_now())))
}