#+feature dynamic-literals
package main

import "base:runtime"
import "core:fmt"
import "core:os"
import "core:strings"

main :: proc() {
	Builtins := map[string]struct{}{
	  "exit" = {},
	  "echo" = {},
	  "type" = {},
	  "pwd"  = {},
	  "cd"  = {},
	}
	defer delete(Builtins)

	buf: [1024]byte

	repl: for {
		defer free_all(context.temp_allocator)
		fmt.printf("$ ")
		n, err := os.read(os.stdin, buf[:])
		if err != nil do return
		input := strings.fields(strings.trim_right(string(buf[:n]), "\r\n"), context.temp_allocator)

		switch {
		case input[0] == "exit":
			break repl
		case input[0] == "echo":
			fmt.printfln("%s", strings.join(input[1:], " ", context.temp_allocator))
		case input[0] == "pwd":
			wd, _ := os.get_working_directory(context.temp_allocator)
			fmt.println(wd)
		case input[0] == "cd":
			directory := input[1]
			if directory == "~" do directory, _ = os.user_home_dir(context.temp_allocator)
			if err := os.chdir(directory); err != nil {
				fmt.printfln("cd: %v: No such file or directory", directory)
			}
		case input[0] == "type":
			if len(input) <= 1 do continue
			command := input[1]

			if command in Builtins {
				fmt.printfln("%v is a shell builtin", command)
				continue
			}

			full_path, ok := find_executable(command)
			if !ok {
				fmt.printfln("%v: not found", command)
				continue
			}
			fmt.printfln("%v is %v", command, full_path)
		case:
			if len(input) == 0 do continue

			full_path, ok := find_executable(input[0])
			if !ok {
				fmt.printfln("%v: command not found", input[0])
				continue
			}
			desc := os.Process_Desc{
        command = input,
        stdin   = os.stdin,
        stdout  = os.stdout,
        stderr  = os.stderr,
  		}
  		process := os.process_start(desc) or_else panic("Couldn't init")
     	state, _ := os.process_wait(process)
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

		if info.type != .Regular do continue
		if info.mode & os.Permissions_Execute_All != {} do return candidate, true
	}
	return
}
