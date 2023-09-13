module fuse

import os
import regex
import model

#pkgconfig fuse3

#include "fusewrapper.h"
#flag -I @VMODROOT
#flag @VMODROOT/fusewrapper.o

struct C.fuse_args {}

struct C.fuse_operations {}

pub enum File_system_item_type {
	file = 1
	directory = 2
}

enum Open_mode {
	read_only = 1
	write_only = 2
	read_write = 3
}

pub struct C.fusewrapper_getattr_reply {
pub mut:
	uid                     u32
	gid                     u32
	permissions_stat_h_bits u32
	result                  int
	item_type               File_system_item_type
	file_size_bytes         int
}

[heap]
pub struct C.fusewrapper_fuse_args {
	allow_other_users bool
	foreground        bool = true // sane default as "foreground=false" daemonizes process by means of fork and exit
	single_thread     bool
	exe_path          &char
	mount_destination &char
}

pub struct C.fusewrapper_common_params {
	path             &char
	requested_by_uid u32
	requested_by_gid u32
	requested_by_pid u32
}

pub type Fn_adder = fn (&char)

pub type Fn_submit_read_result = fn (&char, u64)

pub type Fn_readdir = fn (&C.fusewrapper_common_params, Fn_adder) int

pub type Fn_getattr = fn (&C.fusewrapper_common_params, &C.fusewrapper_getattr_reply)

pub type Fn_open = fn (&C.fusewrapper_common_params, Open_mode) int

pub type Fn_read = fn (&C.fusewrapper_common_params, i64, u64, Fn_submit_read_result) int

pub type Struct_fusewrapper_getattr_reply = C.fusewrapper_getattr_reply

[heap]
struct C.fusewrapper_impl_t {
mut:
	readdir Fn_readdir
	getattr Fn_getattr
	open    Fn_open
	read    Fn_read
}

[heap]
struct C.fusewrapper_impl_holder_t {
mut:
	exit_requested bool
	impl           &C.fusewrapper_impl_t
}

const path_proc_self_mounts = r'/proc/self/mounts'

// unescape_mount_point_path handles special escaped characters such as whitespace and newlines in /proc/self/mounts
fn unescape_mount_point_path(pth string) !string {
	mut re := regex.regex_opt(r'(\\[0-9]{3})') or { return error('regex problem ${err}') }

	mut result := pth

	for {
		start, end := re.find(result)
		if start < 0 {
			break
		}

		v := result[start + 1..end].parse_uint(8, 32) or {
			return error('parsing as uint problem ${err}')
		}
		ch := u8(v).ascii_str()

		result = '${result[0..start]}${ch}${result[end..]}'
	}

	return result
}

pub fn get_mount_points_from_proc_self_mounts(proc_self_mounts_content model.Maybe[string]) ![]string {
	mounts_content := if proc_self_mounts_content.has_value {
		proc_self_mounts_content.value
	} else {
		os.read_file(fuse.path_proc_self_mounts) or {
			return error('could not read mounts from ${fuse.path_proc_self_mounts} error=${err}')
		}
	}

	mut re := regex.regex_opt(r'^([\S]+)\s+([\S]+)') or { panic(err) }

	mount_lines := mounts_content.split('\n')

	mut result := []string{}

	for iline, mount_line in mount_lines {
		start, _ := re.match_string(mount_line)

		if iline == mount_lines.len - 1 {
			assert mount_line == ''
			return result
		}

		if start < 0 {
			return error("didn't match anything in line_no=${iline} content=${mount_line}")
		}

		group2 := re.get_group_list()[1]

		result << unescape_mount_point_path(mount_line[group2.start..group2.end])!
	}
	return []
}

pub fn is_mounted_using_custom_proc_self_mounts(pth string, proc_self_mounts_content model.Maybe[string]) !bool {
	mount_points := get_mount_points_from_proc_self_mounts(proc_self_mounts_content)!
	//$if debug {
	//    println("is_mounted_using_custom_proc_self_mounts path=$pth mounts=$mount_points")
	//}
	return mount_points.contains(pth)
}

pub fn is_mounted(pth string) !bool {
	return is_mounted_using_custom_proc_self_mounts(pth, model.new_maybe_none[string]())
}

fn C.fusewrapper_fuse_args_alloc_and_init(args &C.fusewrapper_fuse_args) &C.fuse_args
fn C.fusewrapper_fuse_alloc_fuse_operations() &C.fuse_operations
fn C.fusewrapper_mount(args &C.fuse_args, ops &C.fuse_operations, impl &C.fusewrapper_impl_holder_t) int
fn C.fusewrapper_umount()

fn C.readdir_no_such_dir() int
fn C.readdir_no_more_items() int
fn C.getattr_no_such_dir() int
fn C.getattr_success() int

fn C.open_no_such_file() int
fn C.open_permission_denied() int
fn C.open_success() int

fn C.read_no_such_file() int

pub const (
	readdir_no_such_dir    = C.readdir_no_such_dir()
	readdir_no_more_items  = C.readdir_no_more_items()
	getattr_no_such_dir    = C.getattr_no_such_dir()
	getattr_success        = C.getattr_success()

	open_no_such_file      = C.open_no_such_file()
	open_permission_denied = C.open_permission_denied()
	open_success           = C.open_success()

	read_no_such_file      = C.read_no_such_file()
)

[heap]
pub struct FuseState {
	// default private and immutable:
	mount_destination string
	user_args         &C.fusewrapper_fuse_args
	fargs             &C.fuse_args
	fops              &C.fuse_operations
pub mut:
	impl_holder &C.fusewrapper_impl_holder_t
}

[trusted]
pub fn new_fuse_state(args &C.fusewrapper_fuse_args) !&FuseState {
	$if debug {
		println('create_state starting, using mount_destination=${unsafe { args.mount_destination.vstring().clone() }}')
	}

	mount_point := unsafe { args.mount_destination.vstring().clone() }

	if mount_point == '/tmp/test_only_default_vpassman_mountpoint' {
		os.mkdir_all('/tmp/test_only_default_vpassman_mountpoint')!
	}

	if !os.exists(mount_point) {
		return error("unable to mount to ${mount_point} as it doesn't exist")
	}

	if !os.is_dir(mount_point) {
		return error('unable to mount to ${mount_point} as it is not a directory')
	}

	fargs := C.fusewrapper_fuse_args_alloc_and_init(args)
	fops := C.fusewrapper_fuse_alloc_fuse_operations()

	$if debug {
		println('create_state ending')
	}

	return &FuseState{
		mount_destination: unsafe { args.mount_destination.vstring().clone() }
		user_args: args
		fargs: fargs
		fops: fops
		impl_holder: &C.fusewrapper_impl_holder_t{
			impl: &C.fusewrapper_impl_t{}
		}
	}
}

[trusted]
pub fn (mut t FuseState) set_readdir(impl Fn_readdir) {
	t.impl_holder.impl.readdir = impl
}

[trusted]
pub fn (mut t FuseState) set_getattr(impl Fn_getattr) {
	t.impl_holder.impl.getattr = impl
}

[trusted]
pub fn (mut t FuseState) set_open(impl Fn_open) {
	t.impl_holder.impl.open = impl
}

[trusted]
pub fn (mut t FuseState) set_read(impl Fn_read) {
	t.impl_holder.impl.read = impl
}

[trusted]
pub fn (t &FuseState) mount() bool {
	$if debug {
		println('mounting ${t.mount_destination}')
	}
	result := C.fusewrapper_mount(t.fargs, t.fops, t.impl_holder)
	$if debug {
		println('mount result ${result} success?=${result == 0}')
	}
	return result == 0
}

[trusted]
pub fn (mut t FuseState) unmount() ! {
	$if debug {
		println('unmounting ${t.mount_destination}')
	}
	t.impl_holder.exit_requested = true

	// trigger 'getattr' callback to actually unblock fuse_loop (=fuse_mount() blocking function)
	if os.is_dir_empty(t.mount_destination) {
		return
	}

	return error('unmounting failed because !empty dir=${t.mount_destination}')
}

// unmount_fuse_by_path tries to unmount
pub fn unmount_fuse_by_path(pth string) !int {
	mut pr := os.new_process('/usr/bin/fusermount') // TODO no hardcoded paths please
	defer {
		pr.close()
	}

	pr.args << '-u'
	pr.args << '-z'
	pr.args << pth

	pr.wait()

	if pr.code != 0 {
		return error('fusermount exitcode=${pr.code}')
	}

	return 0 // TODO wait for 'any'
}
