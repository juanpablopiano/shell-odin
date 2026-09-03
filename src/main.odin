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

		repl_switch: switch {
		case command == "exit":
			break repl
		case strings.has_prefix(command, "echo "):
			fmt.printfln("%s", command[5:])
		case strings.has_prefix(command, "type "):
			text := strings.trim(command[5:], " ")
			if text == "echo" || text == "type" || text == "exit" {
				fmt.printfln("%v is a shell builtin", text)
			} else {
				path := os.get_env("PATH", context.temp_allocator)
				dirs, ok := os.split_path_list(path, context.temp_allocator)
				if err != nil do return

				for dir in dirs {
					full_path := strings.concatenate({dir, "/", text})
					if !os.exists(full_path) do continue
					info, err := os.stat(full_path, context.temp_allocator);
					if err != os.ERROR_NONE do continue
					x_permission := .Execute_User in info.mode

					if x_permission {
						fmt.printfln("%v is %v", text, full_path)
						break repl_switch
					}
				}
				fmt.printfln("%v: not found", text)
			}
		case:
			fmt.printfln("%v: command not found", command)
		}
	}
}
