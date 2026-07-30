package main

import "base:runtime"
import "core:fmt"
import "core:os"
import "core:strings"

main :: proc() {
	buf: [1024]byte

	for {
		fmt.printf("$ ")
		n, err := os.read(os.stdin, buf[:])
		if err != nil do return
		command := strings.trim_right(string(buf[:n]), "\r\n")

		if command == "exit" {
			break
		} else if strings.has_prefix(command, "echo ") {
			text := strings.trim(command[5:], " ")
			fmt.printfln(text)
		} else if strings.has_prefix(command, "type ") {
			text := strings.trim(command[5:], " ")
			if text == "echo" || text == "type" || text == "exit" {
				fmt.printfln("%v is a shell builtin", text)
			} else {
				fmt.printfln("%v: not found", text)
			}
		} else {
			fmt.printfln("%v: command not found", command)
		}
	}
}
