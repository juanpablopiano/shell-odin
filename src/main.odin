#+feature dynamic-literals
package main

import "base:runtime"
import "core:fmt"
import "core:os"
import "core:strings"

QuoteState :: enum {
	None,
	Single,
	Double,
}

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
		context.allocator = context.temp_allocator
		defer free_all(context.temp_allocator)
		fmt.printf("$ ")
		n, err := os.read(os.stdin, buf[:])
		if err != nil do return
		input := tokenize(string(buf[:n]))
		if len(input) == 0 do continue

		command := input[0]

		switch {
		case command == "exit":
			break repl
		case command == "echo":
			text := strings.join(input[1:], " ")
			fmt.println(text)
		case command == "pwd":
			wd, _ := os.get_working_directory(context.allocator)
			fmt.println(wd)
		case command == "cd":
			directory := len(input) > 1 ?  input[1] : ""
			if directory == "~" || directory == "" {
				directory, _ = os.user_home_dir(context.allocator)
			} else if directory[0] == '~' {
				home_dir, _ := os.user_home_dir(context.allocator)
				dir, _ := strings.replace(directory, "~", "", 1)
				directory = strings.concatenate({home_dir, dir})
			}
			if err := os.chdir(directory); err != nil {
				fmt.printfln("cd: %v: No such file or directory", directory)
			}
		case command == "type":
			if len(input) <= 1 do continue
			command := input[1]

			if command in Builtins {
				fmt.printfln("%v is a shell builtin", command)
				continue
			}

			full_path, ok := find_executable(command, context.allocator)
			if !ok {
				fmt.printfln("%v: not found", command)
				continue
			}
			fmt.printfln("%v is %v", command, full_path)
		case:
			full_path, ok := find_executable(input[0], context.allocator)
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

find_executable :: proc(text: string, allocator := context.allocator) -> (full_path := "", ok := false) {
	path := os.get_env("PATH", allocator)
	if path == "" do return
	dirs, err := os.split_path_list(path, allocator)
	if err != nil do return

	for dir in dirs {
		candidate := strings.concatenate({dir, "/", text}, allocator)
		info := os.stat(candidate, allocator) or_continue

		if info.type != .Regular do continue
		if info.mode & os.Permissions_Execute_All != {} do return candidate, true
	}
	return
}

tokenize :: proc(line: string, allocator := context.allocator) -> []string {
	result := make([dynamic]string, allocator)
	accumulator := strings.builder_make(allocator)
	defer strings.builder_destroy(&accumulator)

	state := QuoteState.None
	has_token: bool
	for r in line {
		switch r {
		case '\'':
			if state == .Double do break
			state = state == .None ? .Single : .None
			has_token = true
			continue
		case '\"':
			if state == .Single do break
			state = state == .None ? .Double : .None
			has_token = true
			continue
		case '\t', ' ', '\n':
			if state == .None {
				if has_token {
					append(&result, strings.clone(strings.to_string(accumulator), allocator))
					strings.builder_reset(&accumulator)
				}
				has_token = false
				continue
			}
		}
		strings.write_rune(&accumulator, r)
		has_token = true
	}
	if has_token {
    append(&result, strings.clone(strings.to_string(accumulator), allocator))
  }

	return result[:]
}
