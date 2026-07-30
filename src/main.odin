package main

import "core:os"
import "core:fmt"

main :: proc() {
    buf: [1024]byte

    for {
	    fmt.printf("$ ")
	    n, err := os.read(os.stdin, buf[:])
	    if err != nil do return
	    command := string(buf[:n-1])

	    fmt.printf("%v: command not found\n", command)
    }
}
