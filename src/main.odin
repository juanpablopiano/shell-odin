package main

import "base:runtime"
import "core:fmt"
import "core:os"
import "core:strings"
import "core:c/libc"

main :: proc() {
	buf: [1024]byte

	repl: for {
		defer free_all(context.temp_allocator)
		fmt.printf("$ ")
		n, err := os.read(os.stdin, buf[:])
		if err != nil do return
		input := strings.trim_right(string(buf[:n]), "\r\n")

		switch {
		case input == "exit":
			break repl
		case strings.has_prefix(input, "echo "):
			fmt.printfln("%s", input[5:])
		case strings.has_prefix(input, "type "):
			command := strings.trim(input[5:], " ")
			if command == "echo" || command == "type" || command == "exit" {
				fmt.printfln("%v is a shell builtin", command)
			} else {
				full_path, ok := find_executable(command)
				if !ok {
					fmt.printfln("%v: not found", command)
				} else {
					fmt.printfln("%v is %v", command, full_path)
				}
			}
		case:
			parts := strings.fields(input, context.temp_allocator)
			if len(parts) == 0 do continue

			full_path, ok := find_executable(parts[0])
			if !ok {
				fmt.printfln("%v: command not found", parts[0])
			} else {
				system_error := libc.system(strings.clone_to_cstring(input, context.temp_allocator))
				if system_error != 0 {
					fmt.printf("exited with status: %d\n", i16(system_error))
				}
			// } else {
			// 	parts[0] = full_path
			// 	desc := os.Process_Desc{
	  //       command = parts,
	  //       stdin   = os.stdin,
	  //       stdout  = os.stdout,
	  //       stderr  = os.stderr,
   //  		}
   //   		process := os.process_start(desc) or_else panic("no se pudo iniciar")
   //     	state, _ := os.process_wait(process)
			}
		}
	}
}

find_executable :: proc(text: string) -> (full_path := "", ok := false) {
	path := os.get_env("PATH", context.temp_allocator)
	if path == "" do return
	dirs, err := os.split_path_list(path, context.temp_allocator)
	if err != nil do return

	for dir in dirs {
		candidate := strings.concatenate({dir, "/", text}, context.temp_allocator)
		info := os.stat(candidate, context.temp_allocator) or_continue

		if info.mode & os.Permissions_Execute_All != {} do return candidate, true
	}
	return
}
