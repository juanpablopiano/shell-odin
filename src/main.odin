package main

import "core:os"
import "core:fmt"

main :: proc() {
    // TODO: Uncomment the code below to pass the first stage
    buf: [1024]byte
    fmt.printf("$ ")
    n, err := os.read(os.stdin, buf[:])
    if err != nil do return
    command := string(buf[:n-1])

    fmt.printf("%v: command %v not found", command, command)
}
