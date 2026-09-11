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

		out := os.stdout
		errout := os.stderr

		args, out_path, err_path := parse_redirect(input)

		if file, fileExists := open_target(out_path); fileExists do out = file
		if file, fileExists := open_target(err_path); fileExists do errout = file

		defer if out != os.stdout do os.close(out)
		defer if errout != os.stderr do os.close(errout)

		if len(args) == 0 do continue
		command := args[0]

		switch command {
		case "exit":
			break repl
		case "echo":
			text := strings.join(args[1:], " ")
			fmt.fprintln(out, text)
		case "pwd":
			wd, _ := os.get_working_directory(context.allocator)
			fmt.fprintln(out, wd)
		case "cd":
			directory := len(args) > 1 ? args[1] : "~"
			if directory == "" do continue
			if directory[0] == '~' {
				home_dir, _ := os.user_home_dir(context.allocator)
				directory = strings.concatenate({home_dir, directory[1:]})
			}
			if err := os.chdir(directory); err != nil {
				fmt.fprintfln(errout, "cd: %v: No such file or directory", directory)
			}
		case "type":
			if len(args) <= 1 do continue
			name := args[1]

			if slice.contains(BUILTINS[:], name) {
				fmt.fprintfln(out, "%v is a shell builtin", name)
				continue
			}

			full_path, ok := find_executable(name)
			if !ok {
				fmt.fprintfln(errout, "%v: not found", name)
				continue
			}
			fmt.fprintfln(out, "%v is %v", name, full_path)
		case:
			desc := os.Process_Desc{
        command = args,
        stdin   = os.stdin,
        stdout  = out,
        stderr  = errout,
  		}
  		process, err := os.process_start(desc)
    	if err != nil {
   			fmt.fprintfln(errout, "%v: command not found", args[0])
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

open_target :: proc(path: string) -> (^os.File, bool) {
	if path != "" {
		file, open_err := os.create(path)
		if open_err == nil {
			return file, true
		}
		fmt.eprintfln("%v: cannot create file", path)
	}
	return nil, false
}

parse_redirect :: proc(tokens: []string) -> (args: []string, stdout_path: string, stderr_path: string) {
	args_end := len(tokens)
	for i := 0; i < len(tokens); i += 1 {
		is_stdout := tokens[i] == ">" || tokens[i] == "1>"
		is_stderr := tokens[i] == "2>"
		if !is_stdout && !is_stderr do continue

		if i < args_end do args_end = i
		if i + 1 >= len(tokens) do break

		if  is_stdout {
			stdout_path = tokens[i + 1]
		} else {
			stderr_path = tokens[i + 1]
		}
		i += 1
	}
	args = tokens[:args_end]
	return
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
