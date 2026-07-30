package main

import "base:runtime"
import "core:fmt"
import "core:os"
import "core:strings"

main :: proc() {
	buf: [1024]byte

	repl: for {
		fmt.printf("$ ")
		n, err := os.read(os.stdin, buf[:])
		if err != nil do return
		command := strings.trim_right(string(buf[:n]), "\r\n")

		switch (command) {
		case "exit":
			break repl
		}

		fmt.printf("%v: command not found\n", command)
	}
}
