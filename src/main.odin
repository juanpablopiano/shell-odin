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

		switch {
		case command == "exit":
			break repl
		case strings.has_prefix(command, "echo "):
			fmt.printfln("%s", command[5:])
		case strings.has_prefix(command, "type "):
			text := strings.trim(command[5:], " ")
			if text == "echo" || text == "type" || text == "exit" {
				fmt.printfln("%v is a shell builtin", text)
			} else {
				fmt.printfln("%v: not found", text)
			}
		}
	}
}
