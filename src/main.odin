package main

import "core:slice"
import "base:runtime"
import "core:fmt"
import "core:os"
import "core:strings"

QuoteState :: enum {
	None,
	Single,
	Double,
}
@(rodata)
BUILTINS := [?]string{"exit", "echo", "type", "pwd", "cd"}

main :: proc() {

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

		switch command {
		case "exit":
			break repl
		case "echo":
			text := strings.join(input[1:], " ")
			fmt.println(text)
		case "pwd":
			wd, _ := os.get_working_directory(context.allocator)
			fmt.println(wd)
		case "cd":
			directory := len(input) > 1 ? input[1] : "~"
			if directory == "" do continue
			if directory[0] == '~' {
				home_dir, _ := os.user_home_dir(context.allocator)
				directory = strings.concatenate({home_dir, directory[1:]})
			}
			if err := os.chdir(directory); err != nil {
				fmt.printfln("cd: %v: No such file or directory", directory)
			}
		case "type":
			if len(input) <= 1 do continue
			command := input[1]

			if slice.contains(BUILTINS[:], command) {
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
			// full_path, ok := find_executable(input[0])
			// if !ok {
			// 	fmt.printfln("%v: command not found", input[0])
			// 	continue
			// }
			desc := os.Process_Desc{
        command = input,
        stdin   = os.stdin,
        stdout  = os.stdout,
        stderr  = os.stderr,
  		}
  		process, err := os.process_start(desc)
    	if err != nil {
   			fmt.printfln("%v: command not found", input[0])
        continue
     	}
     	state, _ := os.process_wait(process)
		}
	}
}

is_delimiter :: proc(r: rune) -> bool {
	return r == ' ' || r == '\t' || r == '\n'
}

is_escapable_in_double :: proc(r: rune) -> bool {
	return r == '\"' || r == '\\' || r == '`' || r == '$' || r == '\n'
}

find_executable :: proc(text: string, allocator := context.allocator) -> (full_path := "", ok := false) {
	path := os.get_env("PATH", allocator)
	if path == "" do return
	dirs, err := os.split_path_list(path, allocator)
	if err != nil do return

	for dir in dirs {
		candidate := strings.concatenate({dir, "/", text})
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
	escaped: bool

	for r in line {
		if state == .None && !escaped && is_delimiter(r) {
			if has_token {
        append(&result, strings.clone(strings.to_string(accumulator), allocator))
        strings.builder_reset(&accumulator)
        has_token = false
			}
			continue
		}

		has_token = true

		if escaped {
			if state == .Double && !is_escapable_in_double(r) {
				strings.write_rune(&accumulator, '\\')
			}
			strings.write_rune(&accumulator, r)
			escaped = false
			continue
		}

		switch r {
		case '\\':
			if state == .Single do break
			escaped = true
			continue
		case '\'':
			if state == .Double do break
			state = state == .None ? .Single : .None
			continue
		case '\"':
			if state == .Single do break
			state = state == .None ? .Double : .None
			continue
		}
		strings.write_rune(&accumulator, r)
	}

	if has_token {
    append(&result, strings.clone(strings.to_string(accumulator), allocator))
  }

	return result[:]
}
