module main

// disabled as v tests end up as binary in /tmp/v with unpredictable name
import os
import regex

#include <unistd.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <pwd.h>

// self contained program with minimal dependencies

fn C.getppid() u32
fn C.readlink(path &char, output_buffer &char, output_buffer_size usize) int

struct C.passwd {
	pw_name &char
}

fn C.getpwuid(uid u32) &C.passwd

const (
	max_supported_path_length = 1024
)

fn get_uid_of_pid(pid u32) !u32 {
	mut raw_stat := C.stat{}

	raw_stat_res := C.lstat('/proc/${pid}/'.str, &raw_stat)

	if raw_stat_res != 0 {
		return error('lstat error ${raw_stat_res}')
	}

	return raw_stat.st_uid
}

struct CmdLineParams {
	pid_to_check u32
	be_verbose   bool
}

fn extract_pid_to_check_from_commandline_param_no(param_no u32) !u32 {
	mut re := regex.regex_opt(r'^([0-9]{1,6})$')!
	pid_as_str := os.args[param_no]
	start, _ := re.match_string(pid_as_str)

	if start < 0 {
		return error("didn't match pid in first commandline argument")
	}

	grp := re.get_group_list()[0]

	return u32(pid_as_str[grp.start..grp.end].parse_uint(10, 32)!)
}

fn extract_pid_to_check_from_commandline() !CmdLineParams {
	match os.args.len {
		3 {
			if os.args[1] != '-verbose' {
				return error("when two parameters are given, first one must be '-verbose'")
			}

			return CmdLineParams{
				pid_to_check: extract_pid_to_check_from_commandline_param_no(2)!
				be_verbose: true
			}
		}
		2 {
			return CmdLineParams{
				pid_to_check: extract_pid_to_check_from_commandline_param_no(1)!
				be_verbose: false
			}
		}
		else {
			return error("expected either '-verbose pid' or 'pid' as command line arguments (where pid is numbers only)")
		}
	}
}

fn get_exe_path_of_pid(cmdline CmdLineParams, pid u32) !string {
	raw_actual_exe_path := [max_supported_path_length]u8{}

	exe_link_path := '/proc/${pid}/exe'.str
	readlink_result := C.readlink(exe_link_path, &char(&raw_actual_exe_path[0]), raw_actual_exe_path.len)

	if readlink_result < 0 {
		return error('readlink error=${readlink_result}')
	}

	actual_exe_path_private := unsafe { (&char(&raw_actual_exe_path[0])).vstring_with_len(readlink_result) }
	actual_exe_path := '${actual_exe_path_private}' // vstring_with_len doesn't copy memory!

	if cmdline.be_verbose {
		println('parent exec path=${actual_exe_path}')
	}

	return actual_exe_path
}

fn get_full_path_from_ppid() !string {
	mut cmdline := extract_pid_to_check_from_commandline()!

	if cmdline.be_verbose {
		eprintln('pid_to_check=${cmdline.pid_to_check}')
	}

	pid_to_check_exe_path := get_exe_path_of_pid(cmdline, cmdline.pid_to_check) or {
		return error('unable to get_exe_path_of_pid for requested pid error=${err}')
	}

	return pid_to_check_exe_path
}

fn main() {
	if path_to_report := get_full_path_from_ppid() {
		println('${path_to_report}')
		exit(0)
	} else {
		eprintln(err)
		exit(1)
	}
}
