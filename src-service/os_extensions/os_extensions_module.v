module os_extensions

import regex
import os

#include "os_extensions.h"
#flag -I @VMODROOT
#flag @VMODROOT/os_extensions.o

pub struct UnixFilePermissions {
pub mut:
	user_r bool
	user_w bool
	user_x bool
	suid   bool

	group_r bool
	group_w bool
	group_x bool
	sgid    bool

	other_r bool
	other_w bool
	other_x bool
}

pub enum FileItemType {
	regular_file = 1
	directory
	block
	character
	pipe
	link
	socket
}

fn C.st_mode_to_item_type(st_mode u64) FileItemType

pub struct FileStat {
pub mut:
	uid        u32
	gid        u32
	perms      UnixFilePermissions
	size_bytes u64
	item_type  FileItemType
}

fn C.get_user_rwx_octet(raw_stat_res &C.stat) int
fn C.get_group_rwx_octet(raw_stat_res &C.stat) int
fn C.get_other_rwx_octet(raw_stat_res &C.stat) int
fn C.is_suid(raw_stat_res &C.stat) bool
fn C.is_sgid(raw_stat_res &C.stat) bool

const (
	max_supported_path_length = 1024
)

fn file_type_from_letter(letter string) !FileItemType {
	if letter.len != 1 {
		return error('must be exactly one letter but got ${letter.len}')
	}

	return match letter {
		'-' { FileItemType.regular_file }
		'd' { FileItemType.directory }
		'b' { FileItemType.block }
		'c' { FileItemType.character }
		'p' { FileItemType.pipe }
		'l' { FileItemType.link }
		's' { FileItemType.socket }
		else { error('unsupported type letter=${letter}') }
	}
}

pub fn (t UnixFilePermissions) is_executable_for_anyone() bool {
	return t.user_x || t.group_x || t.other_x
}

pub fn (t UnixFilePermissions) to_stat_h_permission_bits() u32 {
	return (if t.user_r {
		u32(0o400)
	} else {
		0
	}) | (if t.user_w {
		u32(0o200)
	} else {
		0
	}) | (if t.user_x {
		u32(0o100)
	} else {
		0
	}) | (if t.suid {
		u32(0o4000)
	} else {
		0
	}) | (if t.group_r {
		u32(0o040)
	} else {
		0
	}) | (if t.group_w {
		u32(0o020)
	} else {
		0
	}) | (if t.group_x {
		u32(0o010)
	} else {
		0
	}) | (if t.sgid {
		u32(0o2000)
	} else {
		0
	}) | (if t.other_r {
		u32(0o004)
	} else {
		0
	}) | (if t.other_w {
		u32(0o002)
	} else {
		0
	}) | (if t.other_x {
		u32(0o001)
	} else {
		0
	})
}

pub fn (t UnixFilePermissions) to_ls_dash_l_permissions_string() string {
	return (if t.user_r {
		'r'
	} else {
		'-'
	}) + (if t.user_w {
		'w'
	} else {
		'-'
	}) + (if t.suid {
		's'
	} else {
		(if t.user_x {
			'x'
		} else {
			'-'
		})
	}) + (if t.group_r {
		'r'
	} else {
		'-'
	}) + (if t.group_w {
		'w'
	} else {
		'-'
	}) + (if t.sgid {
		's'
	} else {
		(if t.group_x {
			'x'
		} else {
			'-'
		})
	}) + (if t.other_r {
		'r'
	} else {
		'-'
	}) + (if t.other_w {
		'w'
	} else {
		'-'
	}) + (if t.other_x {
		'x'
	} else {
		'-'
	})
}

// new_permissions_from_octets builds permissions from ABCDEFGHI string where
// A,D,G must be r or -
// B,D,H must be w or -
// C,E must be x or s or -
// I must be x or -
pub fn new_permissions_from_octets(perms string) !UnixFilePermissions {
	if perms.len != 'rwxrwxrwx'.len {
		return error('expected rwxrwxrwx like string')
	}

	mut re := regex.regex_opt(r'^([r\-])([w\-])([xs\-])([r\-])([w\-])([xs\-])([r\-])([w\-])([x\-])') or {
		panic(err)
	}

	start, _ := re.match_string(perms)

	if start < 0 {
		return error("didn't match anything in perms=${perms}")
	}

	grps := re.get_group_list()

	return UnixFilePermissions{
		user_r: perms[grps[0].start..grps[0].end] == 'r'
		user_w: perms[grps[1].start..grps[1].end] == 'w'
		user_x: perms[grps[2].start..grps[2].end] == 'x'
		suid: perms[grps[2].start..grps[2].end] == 's'
		group_r: perms[grps[3].start..grps[3].end] == 'r'
		group_w: perms[grps[4].start..grps[4].end] == 'w'
		group_x: perms[grps[5].start..grps[5].end] == 'x'
		sgid: perms[grps[5].start..grps[5].end] == 's'
		other_r: perms[grps[6].start..grps[6].end] == 'r'
		other_w: perms[grps[7].start..grps[7].end] == 'w'
		other_x: perms[grps[8].start..grps[8].end] == 'x'
	}
}

pub fn new_stats_from_path(pth string) !FileStat {
	mut raw_stat := C.stat{}

	raw_stat_res := C.lstat(pth.str, &raw_stat)

	if raw_stat_res != 0 {
		return error('lstat error ${raw_stat_res}')
	}

	u_perm := C.get_user_rwx_octet(&raw_stat)
	g_perm := C.get_group_rwx_octet(&raw_stat)
	o_perm := C.get_other_rwx_octet(&raw_stat)

	return FileStat{
		uid: raw_stat.st_uid
		gid: raw_stat.st_gid
		perms: UnixFilePermissions{
			user_r: u_perm & 0b100 != 0
			user_w: u_perm & 0b010 != 0
			user_x: u_perm & 0b001 != 0
			suid: C.is_suid(&raw_stat)
			group_r: g_perm & 0b100 != 0
			group_w: g_perm & 0b010 != 0
			group_x: g_perm & 0b001 != 0
			sgid: C.is_sgid(&raw_stat)
			other_r: o_perm & 0b100 != 0
			other_w: o_perm & 0b010 != 0
			other_x: o_perm & 0b001 != 0
		}
		size_bytes: raw_stat.st_size
		item_type: C.st_mode_to_item_type(raw_stat.st_mode)
	}
}

fn C.readlink(path &char, output_buffer &char, output_buffer_size usize) int

fn C.maybe_get_username_by_uid(uid u32) &char

pub fn get_username_by_uid(uid u32) !string {
	pw_name := C.maybe_get_username_by_uid(uid)

	unsafe {
		if pw_name == nil {
			return error('maybe_get_username_by_uid error=${C.errno}')
		}

		result := pw_name.vstring().clone()
		C.free(pw_name)
		return result
	}
}

pub fn get_exe_path_of_pid(pid u32) !string {
	raw_exe_path := [os_extensions.max_supported_path_length]char{}

	exe_link_path := '/proc/${pid}/exe'.str
	readlink_result := C.readlink(exe_link_path, &raw_exe_path[0], raw_exe_path.len)

	if readlink_result < 0 {
		return error('readlink error=${readlink_result}')
	}

	exe_path_private := unsafe { (&raw_exe_path[0]).vstring_with_len(readlink_result) }
	return exe_path_private.clone() // vstring_with_len doesn't copy memory!
}

fn C.openlog(ident &char, option int, facility int)
fn C.syslog(priority int, format &char, args ...&char)
fn C.syslog_get_facility_user() int
fn C.syslog_get_level_warning() int

fn C.get_syslog_level_emerg() int
fn C.get_syslog_level_alert() int
fn C.get_syslog_level_crit() int
fn C.get_syslog_level_err() int
fn C.get_syslog_level_warning() int
fn C.get_syslog_level_notice() int
fn C.get_syslog_level_info() int
fn C.get_syslog_level_debug() int

pub fn syslog_init(program_name string) {
	C.openlog(program_name.str, 0, 0)
}

const (
	syslog_level_emerg   = C.get_syslog_level_emerg()
	syslog_level_alert   = C.get_syslog_level_alert()
	syslog_level_crit    = C.get_syslog_level_crit()
	syslog_level_err     = C.get_syslog_level_err()
	syslog_level_warning = C.get_syslog_level_warning()
	syslog_level_notice  = C.get_syslog_level_notice()
	syslog_level_info    = C.get_syslog_level_info()
	syslog_level_debug   = C.get_syslog_level_debug()
)

pub enum SyslogLevel {
	emerg
	alert
	crit
	err
	warning
	notice
	info
	debug
}

fn (l SyslogLevel) to_syslog_level() int {
	return match l {
		.emerg { os_extensions.syslog_level_emerg }
		.alert { os_extensions.syslog_level_alert }
		.crit { os_extensions.syslog_level_crit }
		.err { os_extensions.syslog_level_err }
		.warning { os_extensions.syslog_level_warning }
		.notice { os_extensions.syslog_level_notice }
		.info { os_extensions.syslog_level_info }
		.debug { os_extensions.syslog_level_debug }
	}
}

pub fn syslog(level SyslogLevel, msg string) {
	prio := C.syslog_get_facility_user() | level.to_syslog_level()

	C.syslog(prio, '%s'.str, msg.str)
}

pub fn syslog_emerg(msg string) {
	syslog(SyslogLevel.emerg, msg)
}

pub fn syslog_alert(msg string) {
	syslog(SyslogLevel.alert, msg)
}

pub fn syslog_crit(msg string) {
	syslog(SyslogLevel.crit, msg)
}

pub fn syslog_err(msg string) {
	syslog(SyslogLevel.err, msg)
}

pub fn syslog_warning(msg string) {
	syslog(SyslogLevel.warning, msg)
}

pub fn syslog_notice(msg string) {
	syslog(SyslogLevel.notice, msg)
}

pub fn syslog_info(msg string) {
	syslog(SyslogLevel.info, msg)
}

pub fn syslog_debug(msg string) {
	syslog(SyslogLevel.debug, msg)
}

// which finds fullpath to program_name using PATH environment
pub fn which(program_name string) !string {
	paths := os.getenv('PATH').split(':')

	for path in paths {
		result := os.join_path_single(path, program_name)
		if !os.is_file(result) {
			continue
		}

		stat := new_stats_from_path(result)!

		if stat.perms.is_executable_for_anyone() {
			return result
		}

		return result
	}

	return error('not found path to ${program_name} within ${paths.len} path locations')
}

pub struct ExecuteProcessResult {
pub:
	exit_code int // in linux: 0-255
	stdout    string
	stderr    string
}

pub fn execute_without_wait(pth string, args ...string) &os.Process {
	mut pr := os.new_process(pth)

	$if debug {
		println('executing ${pth}')
	}

	pr.set_redirect_stdio()

	for arg in args {
		pr.args << arg

		$if debug {
			println('arg ${arg}')
		}
	}
	pr.run()
	return pr
}

pub fn execute_without_wait_and_redirect_stdio(pth string, args ...string) &os.Process {
	mut pr := os.new_process(pth)

	$if debug {
		println('executing ${pth}')
	}

	for arg in args {
		pr.args << arg

		$if debug {
			println('arg ${arg}')
		}
	}
	pr.run()
	return pr
}

pub fn execute_wait_and_capture(pth string, args ...string) ExecuteProcessResult {
	mut pr := os.new_process(pth)
	defer {
		pr.close()
	}

	$if debug {
		println('executing ${pth}')
	}

	for arg in args {
		pr.args << arg

		$if debug {
			println('arg ${arg}')
		}
	}

	pr.set_redirect_stdio()

	$if debug {
		println('wait starting')
	}

	pr.wait()

	result := ExecuteProcessResult{
		exit_code: pr.code
		stdout: pr.stdout_slurp()
		stderr: pr.stderr_slurp()
	}

	$if debug {
		println('wait ended result=${result}')
	}

	return result
}

pub fn execute_wait_and_capture_should_succeed(pth string, args ...string) !ExecuteProcessResult {
	res := execute_wait_and_capture(pth, ...args)

	if res.exit_code != 0 {
		return error('expected success but command failed ${res}')
	}

	return res
}

pub fn execute_wait_and_capture_should_fail(pth string, args ...string) !ExecuteProcessResult {
	res := execute_wait_and_capture(pth, ...args)

	if res.exit_code == 0 {
		return error('expected failure but command succeeded ${res}')
	}

	return res
}
