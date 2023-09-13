module main

import fuse
import passmanstate
import os
import time
import math
import regex
import os_extensions

const (
	milis_to_assure_unmount_processing   = 1 * time.millisecond
	milis_to_assure_mount_processing     = 1 * time.millisecond
	retries_to_assure_mount_processing   = 1000
	retries_to_assure_unmount_processing = 1000

	mount_point_path                     = os.real_path(if os.getenv('VPASSMAN_MOUNTPOINT') == '' {
		'/tmp/test_only_default_vpassman_mountpoint'
	} else {
		os.getenv('VPASSMAN_MOUNTPOINT')
	})

	ls_exe_path                          = os_extensions.which('ls')!
	stat_exe_path                        = os_extensions.which('stat')!
	cat_exe_path                         = os_extensions.which('cat')!

	suid_mycat_exe_path                  = $env('VPASSMAN_TESTHELPER_SUID_MYCAT_EXE_PATH')
	suid_username_first                  = $env('VPASSMAN_TESTHELPER_FIRST_USERNAME')
	suid_username_second                 = $env('VPASSMAN_TESTHELPER_SECOND_USERNAME')

	existing_text_file_path              = $env('VPASSMAN_EXISTING_READABLE_FILE')

	this_username                        = os.getenv('LOGNAME')
	this_exe_path                        = os.executable()
)

fn unmount_if_needed() ! {
	for _ in 0 .. retries_to_assure_unmount_processing {
		if fuse.is_mounted(mount_point_path)! {
			fuse.unmount_fuse_by_path(mount_point_path) or {
				println('unmounting failed error=${err}')
			}
		}

		if !fuse.is_mounted(mount_point_path)! {
			break
		}

		time.sleep(milis_to_assure_unmount_processing) // so that umounting actually happens
	}

	assert !fuse.is_mounted(mount_point_path)!
}

fn fuse_mounting_thread(fuse_state &fuse.FuseState, exited chan bool) {
	$if debug {
		println('mounting')
	}

	result := fuse_state.mount()
	$if debug {
		println('mount exited ${result}')
	}

	exited <- result
}

fn fuse_in_foreground_test_body(mut t passmanstate.PassManStateWiredToFuse, foreground_continuation fn () !) ! {
	thread_chan := chan bool{}
	proc := go fuse_mounting_thread(t.fuse_state, thread_chan)

	mut irrelevant := false

	for _ in 0 .. retries_to_assure_mount_processing {
		does_mount_failed_reply := thread_chan.try_pop(mut irrelevant)

		assert does_mount_failed_reply == .not_ready

		if fuse.is_mounted(mount_point_path)! {
			break
		}

		time.sleep(milis_to_assure_mount_processing) // so that blocking mount is actually called
	}
	does_mount_failed_reply := thread_chan.try_pop(mut irrelevant)
	assert does_mount_failed_reply == .not_ready

	assert fuse.is_mounted(mount_point_path)!

	foreground_continuation()!

	t.unmount()!

	mut got_mount_result_reply := ChanState.not_ready

	for _ in 0 .. retries_to_assure_unmount_processing {
		got_mount_result_reply = thread_chan.try_pop(mut irrelevant)
		if got_mount_result_reply == .success {
			break
		}

		time.sleep(milis_to_assure_unmount_processing) // so that umounting actually happens
	}
	assert got_mount_result_reply == .success
	assert !fuse.is_mounted(mount_point_path)!

	proc.wait()
	unmount_if_needed()!
}

struct RootDirExpectations {
	uid         u32
	gid         u32
	permissions os_extensions.UnixFilePermissions
}

struct ExpectedFsEntry {
	name        string
	uid         u32
	gid         u32
	permissions os_extensions.UnixFilePermissions
	details     ExpectedFsEntryDetails
}

struct ExpectedFsFileEntry {
	content string
}

struct ExpectedFsDirEntry {
	children []ExpectedFsEntry
}

type ExpectedFsEntryDetails = ExpectedFsDirEntry | ExpectedFsFileEntry

fn (e ExpectedFsEntry) to_file_system_item() &passmanstate.FileSystemItem {
	match e.details {
		ExpectedFsFileEntry {
			return &passmanstate.FileSystemItem{
				name: e.name
				uid: e.uid
				gid: e.gid
				permissions: e.permissions
				details: &passmanstate.File{
					content: e.details.content
				}
			}
		}
		ExpectedFsDirEntry {
			return &passmanstate.FileSystemItem{
				name: e.name
				uid: e.uid
				gid: e.gid
				permissions: e.permissions
				details: &passmanstate.Dir{
					children: e.details.children.map(it.to_file_system_item())
				}
			}
		}
	}
}

fn external_ls_on_dir(dir string) ![]string {
	res := os_extensions.execute_wait_and_capture_should_succeed(ls_exe_path, '-1', '--hide-control-chars',
		'--escape', dir)!

	mut result := res.stdout#[..-1]
	result = result.replace(r'\ ', ' ')

	return if result == '' { []string{} } else { result.split('\n') }
}

fn external_stats_from_path(item_path string) !os_extensions.FileStat {
	res := os_extensions.execute_wait_and_capture_should_succeed(stat_exe_path, '--format=%A %u %g %s',
		item_path)!

	mut re := regex.regex_opt( // dr-x------ 3333 5555 0
	 r'^([\-dbcpls])([rwxs\-]{9})\s+(\d+)\s+(\d+)\s+(\d+)') or { panic(err) }

	start, _ := re.match_string(res.stdout)

	if start < 0 {
		return error("didn't match anything in stat path=${item_path} output=${res.stdout}")
	}

	grps := re.get_group_list()

	stats := os_extensions.FileStat{
		uid: u32(res.stdout[grps[2].start..grps[2].end].parse_uint(10, 32)!)
		gid: u32(res.stdout[grps[3].start..grps[3].end].parse_uint(10, 32)!)
		perms: os_extensions.new_permissions_from_octets(res.stdout[grps[1].start..grps[1].end])!
		item_type: os_extensions.file_type_from_letter(res.stdout[grps[0].start..grps[0].end])!
		size_bytes: res.stdout[grps[4].start..grps[4].end].parse_uint(10, 32)!
	}

	return stats
}

fn external_read_file(item_path string) !string {
	res := os_extensions.execute_wait_and_capture_should_succeed(cat_exe_path, item_path)!

	return res.stdout
}

fn assert_expected_fs_entry_matches_reality(dir string, raw_expects []ExpectedFsEntry) ! {
	$if debug {
		println('assert_expected_fs_entry_matches_reality path=${dir} has ${raw_expects.len} items?')
	}
	mut root_contents := external_ls_on_dir(dir)!

	root_contents.sort()

	mut expects := raw_expects.clone()
	expects.sort(a.name < b.name)

	if root_contents.len != expects.len {
		assert expects.map(it.name) == root_contents
	}

	for i, e in expects {
		actual := root_contents[i]
		$if debug {
			println('assert_expected_fs_entry_matches_reality processing expected file=${e.name}')
		}

		assert e.name == actual
		item_path := os.join_path_single(dir, e.name)

		stats := external_stats_from_path(item_path)!

		assert stats.uid == e.uid
		assert stats.gid == e.gid
		assert e.permissions.to_ls_dash_l_permissions_string() == stats.perms.to_ls_dash_l_permissions_string()

		// TODO check if expected file type matches d == d and - == -

		match e.details {
			ExpectedFsFileEntry {
				assert stats.item_type == .regular_file
				assert stats.size_bytes == u64(e.details.content.len)
				assert external_read_file(item_path)! == e.details.content
			}
			ExpectedFsDirEntry {
				assert stats.item_type == .directory
				assert_expected_fs_entry_matches_reality(os.join_path_single(dir, e.name),
					e.details.children)!
			}
		}
	}
}

fn build_wiredtofusepassmanstate_from_expectations(root_expect RootDirExpectations, expects []ExpectedFsEntry) !&passmanstate.PassManStateWiredToFuse {
	args := &C.fusewrapper_fuse_args{
		foreground: true
		single_thread: true
		exe_path: os.args[0].str
		mount_destination: mount_point_path.str
	}

	mut root_dir_contents := []&passmanstate.FileSystemItem{}

	for e in expects {
		root_dir_contents << e.to_file_system_item()
	}

	root_dir := &passmanstate.FileSystemItem{
		name: ''
		uid: root_expect.uid
		gid: root_expect.gid
		permissions: root_expect.permissions
		details: &passmanstate.DirOrFile(passmanstate.Dir{
			children: root_dir_contents
		})
	}

	mut fuse_state := fuse.new_fuse_state(args)!
	return root_dir.wire_root_dir_to_fuse(mut fuse_state)
}

fn base_build_fs_and_assert_expectations(mut t passmanstate.PassManStateWiredToFuse, root_expect RootDirExpectations, expects []ExpectedFsEntry) ! {
	fuse_in_foreground_test_body(mut t, fn [root_expect, expects] () ! {
		// root
		dir_stats := os_extensions.new_stats_from_path(mount_point_path)!

		assert dir_stats.uid == root_expect.uid
		assert dir_stats.gid == root_expect.gid

		assert root_expect.permissions.to_ls_dash_l_permissions_string() == dir_stats.perms.to_ls_dash_l_permissions_string()

		// contents
		assert_expected_fs_entry_matches_reality(mount_point_path, expects)!
	})!
}

fn base_test_mounting_in_foreground_actually_exposes_requested_file(root_expect RootDirExpectations, raw_expects ...ExpectedFsEntry) ! {
	unmount_if_needed()!

	mut expects := []ExpectedFsEntry{}

	for x in raw_expects {
		expects << x
	}

	expects.sort(a.name < b.name)

	mut wiredtofusepassmanstate := build_wiredtofusepassmanstate_from_expectations(root_expect,
		expects)!

	base_build_fs_and_assert_expectations(mut wiredtofusepassmanstate, root_expect, expects)!
}

fn build_wiredtofusepassmanstate_from_passmanstate_without_access_checker(settings passmanstate.PassManExportSettings, passman_state &passmanstate.PassManState) !&passmanstate.PassManStateWiredToFuse {
	args := C.fusewrapper_fuse_args{
		foreground: true
		single_thread: true
		exe_path: os.args[0].str
		mount_destination: mount_point_path.str
	}

	mut fuse_state := fuse.new_fuse_state(args)!
	return passman_state.wire_to_fuse_without_access_checking(mut fuse_state, settings)
}

fn build_wiredtofusepassmanstate_from_passmanstate_with_access_checker(multiuser bool, multithreaded bool, settings passmanstate.PassManExportSettings, passman_state &passmanstate.PassManState, access_prompt passmanstate.IAccessPrompt, access_audit passmanstate.IAccessAudit) !&passmanstate.PassManStateWiredToFuse {
	args := C.fusewrapper_fuse_args{
		allow_other_users: multiuser
		foreground: true
		single_thread: !multithreaded
		exe_path: os.args[0].str
		mount_destination: mount_point_path.str
	}

	mut fuse_state := fuse.new_fuse_state(args)!

	return passman_state.wire_to_fuse_without_custom_compute(mut fuse_state, settings,
		access_prompt, access_audit)
}

fn base_test_mounting_passman_in_foreground_actually_exposes_requested_file(passman_state &passmanstate.PassManState, settings passmanstate.PassManExportSettings, root_expect RootDirExpectations, raw_expects ...ExpectedFsEntry) ! {
	unmount_if_needed()!

	mut expects := []ExpectedFsEntry{}

	for x in raw_expects {
		expects << x
	}

	expects.sort(a.name < b.name)

	mut wiredtofusepassmanstate := build_wiredtofusepassmanstate_from_passmanstate_without_access_checker(settings,
		passman_state)!

	base_build_fs_and_assert_expectations(mut wiredtofusepassmanstate, root_expect, expects)!
}

fn base_multiuser_multithreaded_test_mounting_passman_and_run_body(passman_state &passmanstate.PassManState, settings passmanstate.PassManExportSettings, capture passmanstate.IAccessAudit, access_checker passmanstate.IAccessPrompt, assert_body fn () !) ! {
	unmount_if_needed()!

	mut wiredtofusepassmanstate := build_wiredtofusepassmanstate_from_passmanstate_with_access_checker(true,
		true, settings, passman_state, access_checker, capture)!

	fuse_in_foreground_test_body(mut wiredtofusepassmanstate, assert_body)!
}

fn base_multiuser_test_mounting_passman_and_run_body(passman_state &passmanstate.PassManState, settings passmanstate.PassManExportSettings, capture passmanstate.IAccessAudit, access_checker passmanstate.IAccessPrompt, assert_body fn () !) ! {
	unmount_if_needed()!

	mut wiredtofusepassmanstate := build_wiredtofusepassmanstate_from_passmanstate_with_access_checker(true,
		false, settings, passman_state, access_checker, capture)!

	fuse_in_foreground_test_body(mut wiredtofusepassmanstate, assert_body)!
}

fn base_singleuser_test_mounting_passman_and_run_body(passman_state &passmanstate.PassManState, settings &passmanstate.PassManExportSettings, capture passmanstate.IAccessAudit, access_checker passmanstate.IAccessPrompt, assert_body fn () !) ! {
	unmount_if_needed()!

	mut wiredtofusepassmanstate := build_wiredtofusepassmanstate_from_passmanstate_with_access_checker(false,
		false, settings, passman_state, access_checker, capture)!

	fuse_in_foreground_test_body(mut wiredtofusepassmanstate, assert_body)!
}

fn assert_pretty_diff_string(expected string, actual string) {
	if expected == actual {
		return
	}

	expected_runes := expected.runes()
	actual_runes := actual.runes()

	min_len := math.min(expected_runes.len, actual_runes.len)

	for i in 0 .. min_len {
		if expected_runes[i] != actual_runes[i] {
			msg := 'diff found at index=${i}\n\texpected=${expected_runes[0..i + 1].string()}\n\tactual=${actual_runes[0..
				i + 1].string()}'
			assert expected == actual, msg
		}
	}

	assert expected == actual
}
