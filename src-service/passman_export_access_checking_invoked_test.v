module main

import fuse
import passmanstate
import os_extensions
import rand

fn to_disable_fuse_warning_when_implemented_causes_compilation_error() bool {
	a := fuse.Struct_fusewrapper_getattr_reply{}
	return a.uid == 0
}

const (
	default_permissions = passmanstate.PassManExportSettings{
		uid: 3333
		gid: 5555
		dir: os_extensions.UnixFilePermissions{
			user_r: true
			user_x: true
		}
		file: os_extensions.UnixFilePermissions{
			user_r: true
		}
	}
)

fn testsuite_begin() ! {
	unmount_if_needed()!
}

fn testsuite_end() ! {
	unmount_if_needed()!
}

fn test_access_is_checked_on_internal_listing() ! {
	println('#-#-# start #-#-# test_access_is_checked_on_internal_listing()')

	passman_state := passmanstate.PassManState{
		name: 'complex example'
		access: .ask
		uuid_to_folder: {
			// empty folder
			rand.uuid_v4(): passmanstate.PassManFolder{
				name: 'somefolder'
				uuid_to_attribute: {
					rand.uuid_v4(): passmanstate.PassManItemAttribute{
						identifier: passmanstate.AttributeIdentifierStandard{passmanstate.AttributeIdentifierKind.email}
						value: 'a@example.com'
					}
				}
			}
		}
	}

	mut history := []string{}
	mut history_copy := &history

	base_singleuser_test_mounting_passman_and_run_body(passman_state, default_permissions,
		passmanstate.EmptyAccessAudit{}, passmanstate.CustomAccessPrompt{fn [mut history_copy] (path string, subject &passmanstate.FileSystemItem, op passmanstate.FsOperation, executor &passmanstate.Accessor) chan bool {
		res := chan bool{cap: 1}
		res <- true

		history_copy << 'asked p=${path} o=${op} u=${executor.username} e=${executor.exe_path}'

		return res
	}}, fn [mut history_copy] () ! {
		history_copy << 'test start'

		history_copy << 'list /'
		external_ls_on_dir(mount_point_path)! // dir-unrelated-to-passmanfolder

		history_copy << 'list /secrets'
		external_ls_on_dir(mount_point_path + '/secrets')! // dir-unrelated-to-passmanfolder

		// dir-containing-passmanfolders start here
		history_copy << 'list /secrets/by-name'
		external_ls_on_dir(mount_point_path + '/secrets/by-name')!

		history_copy << 'list /secrets/by-name/somefolder'
		external_ls_on_dir(mount_point_path + '/secrets/by-name/somefolder')!

		history_copy << 'test end'
	})!

	expected := [
		'test start',
		'list /',
		'list /secrets',
		'list /secrets/by-name',
		'asked p=/secrets/by-name/somefolder o=include_in_listing u=${this_username} e=${ls_exe_path}',
		'list /secrets/by-name/somefolder',
		'asked p=/secrets/by-name/somefolder o=get_attribute u=${this_username} e=${ls_exe_path}',
		'asked p=/secrets/by-name/somefolder o=list_dir u=${this_username} e=${ls_exe_path}',
		'asked p=/secrets/by-name/somefolder/email o=include_in_listing u=${this_username} e=${ls_exe_path}',
		'test end',
	]

	assert_pretty_diff_string(expected.str(), history.str())

	assert history == expected
}

fn test_access_is_checked_on_external_listing_program() ! {
	println('#-#-# start #-#-# test_access_is_checked_on_external_listing_program()')

	passman_state := passmanstate.PassManState{
		name: 'complex example'
		access: .ask
		uuid_to_folder: {
			// empty folder
			rand.uuid_v4(): passmanstate.PassManFolder{
				name: 'somefolder'
				uuid_to_attribute: {
					rand.uuid_v4(): passmanstate.PassManItemAttribute{
						identifier: passmanstate.AttributeIdentifierStandard{passmanstate.AttributeIdentifierKind.email}
						value: 'a@example.com'
					}
				}
			}
		}
	}

	mut history := []string{}
	mut history_copy := &history

	base_singleuser_test_mounting_passman_and_run_body(passman_state, default_permissions,
		passmanstate.EmptyAccessAudit{}, passmanstate.CustomAccessPrompt{fn [mut history_copy] (path string, subject &passmanstate.FileSystemItem, op passmanstate.FsOperation, executor &passmanstate.Accessor) chan bool {
		res := chan bool{cap: 1}
		res <- true

		history_copy << 'asked p=${path} o=${op} u=${executor.username} e=${executor.exe_path}'

		return res
	}}, fn [mut history_copy] () ! {
		history_copy << 'test start'
		history_copy << 'ls /secrets/by-name/somefolder'
		os_extensions.execute_wait_and_capture_should_succeed(ls_exe_path, mount_point_path +
			'/secrets/by-name/somefolder')!

		history_copy << 'test end'
	})!

	expected := [
		'test start',
		'ls /secrets/by-name/somefolder',
		'asked p=/secrets/by-name/somefolder o=get_attribute u=${this_username} e=${ls_exe_path}',
		'asked p=/secrets/by-name/somefolder o=list_dir u=${this_username} e=${ls_exe_path}',
		'asked p=/secrets/by-name/somefolder/email o=include_in_listing u=${this_username} e=${ls_exe_path}',
		'test end',
	]

	assert_pretty_diff_string(expected.str(), history.str())

	assert history == expected
}

fn test_access_is_checked_on_internal_reading() ! {
	println('#-#-# start #-#-# test_access_is_checked_on_internal_reading()')

	passman_state := passmanstate.PassManState{
		name: 'complex example'
		access: .ask
		uuid_to_folder: {
			// empty folder
			rand.uuid_v4(): passmanstate.PassManFolder{
				name: 'somefolder'
				uuid_to_attribute: {
					rand.uuid_v4(): passmanstate.PassManItemAttribute{
						identifier: passmanstate.AttributeIdentifierStandard{passmanstate.AttributeIdentifierKind.email}
						value: 'a@example.com'
					}
				}
			}
		}
	}

	mut history := []string{}
	mut history_copy := &history

	base_singleuser_test_mounting_passman_and_run_body(passman_state, default_permissions,
		passmanstate.EmptyAccessAudit{}, passmanstate.CustomAccessPrompt{fn [mut history_copy] (path string, subject &passmanstate.FileSystemItem, op passmanstate.FsOperation, executor &passmanstate.Accessor) chan bool {
		res := chan bool{cap: 1}
		res <- true

		history_copy << 'asked p=${path} o=${op} u=${executor.username} e=${executor.exe_path}'

		return res
	}}, fn [mut history_copy] () ! {
		history_copy << 'test start'

		history_copy << 'read_file /secrets/by-name/somefolder/email'

		os_extensions.execute_wait_and_capture_should_succeed(cat_exe_path, mount_point_path +
			'/secrets/by-name/somefolder/email')!

		history_copy << 'test end'
	})!

	expected := [
		'test start',
		'read_file /secrets/by-name/somefolder/email',
		'asked p=/secrets/by-name/somefolder o=get_attribute u=${this_username} e=${cat_exe_path}',
		'asked p=/secrets/by-name/somefolder/email o=get_attribute u=${this_username} e=${cat_exe_path}',
		'asked p=/secrets/by-name/somefolder/email o=open_file u=${this_username} e=${cat_exe_path}',
		'asked p=/secrets/by-name/somefolder/email o=read_file u=${this_username} e=${cat_exe_path}',
		'test end',
	]

	assert_pretty_diff_string(expected.str(), history.str())

	assert history == expected
}

fn test_access_is_checked_on_external_reading() ! {
	println('#-#-# start #-#-# test_access_is_checked_on_external_reading()')

	passman_state := passmanstate.PassManState{
		name: 'complex example'
		access: .ask
		uuid_to_folder: {
			// empty folder
			rand.uuid_v4(): passmanstate.PassManFolder{
				name: 'somefolder'
				uuid_to_attribute: {
					rand.uuid_v4(): passmanstate.PassManItemAttribute{
						identifier: passmanstate.AttributeIdentifierStandard{passmanstate.AttributeIdentifierKind.email}
						value: 'a@example.com'
					}
				}
			}
		}
	}

	mut history := []string{}
	mut history_copy := &history

	base_singleuser_test_mounting_passman_and_run_body(passman_state, default_permissions,
		passmanstate.EmptyAccessAudit{}, passmanstate.CustomAccessPrompt{fn [mut history_copy] (path string, subject &passmanstate.FileSystemItem, op passmanstate.FsOperation, executor &passmanstate.Accessor) chan bool {
		res := chan bool{cap: 1}
		res <- true

		history_copy << 'asked p=${path} o=${op} u=${executor.username} e=${executor.exe_path}'

		return res
	}}, fn [mut history_copy] () ! {
		history_copy << 'test start'

		history_copy << 'cat /secrets/by-name/somefolder/email'

		os_extensions.execute_wait_and_capture_should_succeed(cat_exe_path, mount_point_path +
			'/secrets/by-name/somefolder/email')!

		history_copy << 'test end'
	})!

	expected := [
		'test start',
		'cat /secrets/by-name/somefolder/email',
		'asked p=/secrets/by-name/somefolder o=get_attribute u=${this_username} e=${cat_exe_path}',
		'asked p=/secrets/by-name/somefolder/email o=get_attribute u=${this_username} e=${cat_exe_path}',
		'asked p=/secrets/by-name/somefolder/email o=open_file u=${this_username} e=${cat_exe_path}',
		'asked p=/secrets/by-name/somefolder/email o=read_file u=${this_username} e=${cat_exe_path}',
		'test end',
	]

	assert_pretty_diff_string(expected.str(), history.str())

	assert history == expected
}
