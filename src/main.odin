package main

import "core:sys/posix"
import "core:slice"
import "base:runtime"
import "core:fmt"
import "core:os"
import "core:strings"

Redirect :: struct {
	path: string,
	append: bool,
}

QuoteState :: enum {
	None,
	Single,
	Double,
}

@(rodata)
BUILTINS := [?]string{"exit", "echo", "type", "pwd", "cd"}
PROMPT :: "$ "

main :: proc() {
	repl: for {
		context.allocator = context.temp_allocator
		defer free_all(context.temp_allocator)
		fmt.printf(PROMPT)
		line, ok := read_line(context.allocator)
		if !ok do break repl
		input := tokenize(line)
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

enable_raw_mode :: proc() -> (original: posix.termios, ok: bool) {
	if posix.tcgetattr(posix.STDIN_FILENO, &original) != .OK {
		return
	}

	termios := original
	termios.c_lflag -= { .ECHO, .ICANON, .ISIG }

	termios.c_cc[.VMIN] = 1
	termios.c_cc[.VTIME] = 0

	if posix.tcsetattr(posix.STDIN_FILENO, .TCSANOW, &termios) != .OK {
		fmt.eprintln("There was an error with tcsetattr.")
		return
	}

	return original, true
}

set_termios :: proc(t: posix.termios) {
	t := t
	posix.tcsetattr(posix.STDIN_FILENO, .TCSANOW, &t)
}

read_line :: proc(allocator := context.allocator) -> (line: string, ok: bool) {
	original, raw_ok := enable_raw_mode()
	defer if raw_ok do set_termios(original)

	accumulator := strings.builder_make(allocator)
	defer strings.builder_destroy(&accumulator)

	buf: [1]byte
	last_was_tab: bool

	for {
		n, err := os.read(os.stdin, buf[:])
		if err != nil || n == 0 do return

		was_tab := last_was_tab
		last_was_tab = buf[0] == '\t'

		switch buf[0] {
			case '\r', '\n':
				os.write(os.stdout, []byte{'\r', '\n'})
				return strings.clone(strings.to_string(accumulator), allocator), true
			case 0x03: // ctrl-C
				os.write(os.stdout, transmute([]byte)string("^C\r\n"))
				return "", true
			case 0x04: // ctrl-D
				if strings.builder_len(accumulator) > 0 do break
				os.write(os.stdout, []byte{'\r', '\n'})
				return
			case 0x7f, 0x08: // backspace and del
				_, w := strings.pop_rune(&accumulator)
				if w > 0 {
					os.write(os.stdout, []byte{'\b', ' ', '\b'})
				}
			case '\t':
				prefix := strings.to_string(accumulator)
				matches := find_completions(strings.to_string(accumulator), context.temp_allocator)

				switch len(matches) {
				case 0:
					os.write(os.stdout, []byte{0x07})
				case 1:
					suffix := matches[0][len(prefix):]
					strings.write_string(&accumulator, suffix)
					strings.write_byte(&accumulator, ' ')
					os.write(os.stdout, transmute([]byte)suffix)
					os.write(os.stdout, []byte{' '})
				case:
					if !was_tab {
						os.write(os.stdout, []byte{0x07})
					} else {
						list := strings.join(matches, "  ", context.temp_allocator)
						fmt.printf("\r\n%s\r\n%s%s", list, PROMPT, prefix)
					}
				}
			case:
				strings.write_byte(&accumulator, buf[0])
				os.write(os.stdout, buf[:n])
		}
	}
}

find_completions :: proc(prefix: string, allocator := context.allocator) -> []string {
	if prefix == "" do return nil

	names := make([dynamic]string, allocator)
	for builtin in BUILTINS {
		if strings.has_prefix(builtin, prefix) do append(&names, builtin)
	}
	append_executable_completions(&names, prefix, allocator)

	slice.sort(names[:])
	return slice.unique(names[:])
}

is_delimiter :: proc(r: rune) -> bool {
	return r == ' ' || r == '\t' || r == '\n'
}

is_escapable_in_double :: proc(r: rune) -> bool {
	return r == '\"' || r == '\\' || r == '`' || r == '$' || r == '\n'
}

open_target :: proc(redir: Redirect) -> (^os.File, bool) {
	if redir.path == "" do return nil, false

	flags := os.File_Flags{.Write, .Create}
	flags |= redir.append ? {.Append} : {.Trunc}

	file, open_err := os.open(redir.path, flags, os.Permissions_Default_File)
	if open_err != nil {
		fmt.fprintfln(os.stderr, "%v: cannot create file", redir.path)
		return nil, false
	}
	return file, true
}

parse_redirect :: proc(tokens: []string) -> (args: []string, stdout_path, stderr_path: Redirect) {
	args_end := len(tokens)
	is_stdout, is_stderr, is_append: bool
	for i := 0; i < len(tokens); i += 1 {
		t := tokens[i]
		switch t {
		case ">", "1>":   is_stdout = true
		case ">>", "1>>": is_stdout = true; is_append = true
		case "2>": 				is_stderr = true
		case "2>>": 			is_stderr = true; is_append = true
		case: 						continue
		}

		if i < args_end do args_end = i
		if i + 1 >= len(tokens) do break

		if  is_stdout {
			stdout_path = {
				tokens[i + 1],
				is_append,
			}
		} else {
			stderr_path = {
				tokens[i + 1],
				is_append,
			}
		}
		i += 1
	}
	args = tokens[:args_end]
	return
}

find_executable :: proc(text: string, allocator := context.allocator) -> (full_path := "", ok := false) {
	dirs := path_dirs(allocator) or_return
	for dir in dirs {
		candidate := strings.concatenate({dir, "/", text})
		info := os.stat(candidate, allocator) or_continue

		if is_executable(info) do return candidate, true
	}
	return
}

append_executable_completions :: proc(names: ^[dynamic]string, prefix: string, allocator := context.allocator) {
	dirs, ok := path_dirs(allocator)
	if !ok do return

	for dir in dirs {
		entries := os.read_all_directory_by_path(dir, allocator) or_continue
		for entry in entries {
			if strings.has_prefix(entry.name, prefix) && is_executable(entry) do append(names, entry.name)
		}
	}
}

path_dirs :: proc(allocator := context.allocator) -> (dirs: []string, ok: bool) {
	path := os.get_env("PATH", allocator)
	if path == "" do return
	err: os.Error
	dirs, err = os.split_path_list(path, allocator)
	return dirs, err == nil
}

is_executable :: proc(info: os.File_Info) -> bool {
	return info.type == .Regular && info.mode & os.Permissions_Execute_All != {}
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
