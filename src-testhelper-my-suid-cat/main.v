import os

#include <sys/types.h>
#include <pwd.h>

fn C.setuid(uid u32) int

struct C.passwd {
	pw_uid u32
}

fn C.getpwnam(name &char) &C.passwd

fn main() {
	if os.args.len != 3 {
		eprintln('expected exactly two arguments: username-to-suid path-to-file-to-read-from')
		exit(1)
	}

	username_to_switch_to := os.args[1]
	path_to_read := os.args[2]
	mut uid_to_switch_to := u32(0)

	passwd_struct := C.getpwnam(username_to_switch_to.str)

	unsafe {
		if passwd_struct == 0 {
			eprintln('getpwnam failed')
			exit(1)
		}
	}
	uid_to_switch_to = passwd_struct.pw_uid

	if C.setuid(uid_to_switch_to) != 0 {
		eprintln('setuid failed')
		exit(1)
	}

	if content := os.read_file(path_to_read) {
		println(content)
		exit(0)
	} else {
		eprintln('read_file path=${path_to_read} error=${err}')
		exit(1)
	}
}
