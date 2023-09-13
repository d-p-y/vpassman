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
	default_singleuser_permissions = passmanstate.PassManExportSettings{
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
	default_multiuser_permissions = passmanstate.PassManExportSettings{
		uid: 3333
		gid: 5555
		dir: os_extensions.UnixFilePermissions{
			user_r: true
			user_x: true
		}
		file: os_extensions.UnixFilePermissions{
			user_r: true
		}
		maybe_get_full_path_of_pid_tool_exe: $env('VPASSMAN_TESTHELPER_FULLPATHOFPID_EXE_PATH')
	}
)

fn testsuite_begin() ! {
	unmount_if_needed()!
}

fn testsuite_end() ! {
	unmount_if_needed()!
}

fn test_access_is_checked_without_gettattr_on_dir_when_stipulated_by_policy_on_readfile() ! {
	println('#-#-# start #-#-# test_access_is_checked_without_gettattr_on_dir_when_stipulated_by_policy_on_readfile()')

	passman_state := passmanstate.PassManState{
		access: .ask
		verify_access_for_getattr_on_directory_related_to_passman_folders: false
		name: 'complex example'
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

	base_singleuser_test_mounting_passman_and_run_body(passman_state, default_singleuser_permissions,
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
		'asked p=/secrets/by-name/somefolder/email o=get_attribute u=${this_username} e=${cat_exe_path}',
		'asked p=/secrets/by-name/somefolder/email o=open_file u=${this_username} e=${cat_exe_path}',
		'asked p=/secrets/by-name/somefolder/email o=read_file u=${this_username} e=${cat_exe_path}',
		'test end',
	]

	assert_pretty_diff_string(expected.str(), history.str())

	assert history == expected
}

fn test_access_is_checked_without_gettattr_on_dir_when_stipulated_by_policy_on_listdir() ! {
	println('#-#-# start #-#-# test_access_is_checked_without_gettattr_on_dir_when_stipulated_by_policy_on_listdir()')

	passman_state := passmanstate.PassManState{
		access: .ask
		verify_access_for_getattr_on_directory_related_to_passman_folders: false
		name: 'complex example'
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

	base_singleuser_test_mounting_passman_and_run_body(passman_state, default_singleuser_permissions,
		passmanstate.EmptyAccessAudit{}, passmanstate.CustomAccessPrompt{fn [mut history_copy] (path string, subject &passmanstate.FileSystemItem, op passmanstate.FsOperation, executor &passmanstate.Accessor) chan bool {
		res := chan bool{cap: 1}
		res <- true

		history_copy << 'asked p=${path} o=${op} u=${executor.username} e=${executor.exe_path}'

		return res
	}}, fn [mut history_copy] () ! {
		history_copy << 'test start'

		history_copy << 'list /secrets/by-name/somefolder'
		external_ls_on_dir(mount_point_path + '/secrets/by-name/somefolder')!

		history_copy << 'test end'
	})!

	expected := [
		'test start',
		'list /secrets/by-name/somefolder',
		'asked p=/secrets/by-name/somefolder o=list_dir u=${this_username} e=${ls_exe_path}',
		'asked p=/secrets/by-name/somefolder/email o=include_in_listing u=${this_username} e=${ls_exe_path}',
		'test end',
	]

	assert_pretty_diff_string(expected.str(), history.str())

	assert history == expected
}

fn test_in_singleuser_mode_fuse_itself_rejects_other_users() ! {
	println('#-#-# start #-#-# test_in_singleuser_mode_fuse_itself_rejects_other_users()')

	passman_state := passmanstate.PassManState{
		access: .ask
		verify_access_for_getattr_on_directory_related_to_passman_folders: false
		name: 'complex example'
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

	base_singleuser_test_mounting_passman_and_run_body(passman_state, default_singleuser_permissions,
		passmanstate.EmptyAccessAudit{}, passmanstate.CustomAccessPrompt{fn [mut history_copy] (path string, subject &passmanstate.FileSystemItem, op passmanstate.FsOperation, executor &passmanstate.Accessor) chan bool {
		res := chan bool{cap: 1}
		res <- true

		history_copy << 'asked p=${path} o=${op} u=${executor.username} e=${executor.exe_path}'

		return res
	}}, fn [mut history_copy] () ! {
		history_copy << 'test start'

		history_copy << 'suidmycat first /secrets/by-name/somefolder/email'
		os_extensions.execute_wait_and_capture_should_fail(suid_mycat_exe_path, suid_username_first,
			mount_point_path + '/secrets/by-name/somefolder/email')!

		history_copy << 'test end'
	})!

	expected := [
		'test start',
		'suidmycat first /secrets/by-name/somefolder/email',
		'test end',
	]

	assert_pretty_diff_string(expected.str(), history.str())

	assert history == expected
}

fn test_cat_and_mycat_may_rely_on_exit_code() {
	println('#-#-# start #-#-# test_cat_and_mycat_may_rely_on_exit_code()')

	for i in 0 .. 5 {
		os_extensions.execute_wait_and_capture_should_succeed(cat_exe_path, existing_text_file_path)!

		os_extensions.execute_wait_and_capture_should_succeed(suid_mycat_exe_path, suid_username_first,
			existing_text_file_path)!

		os_extensions.execute_wait_and_capture_should_fail(cat_exe_path, '/this_doesnt_exist_for_sure_or_perhaps_it_does')!

		os_extensions.execute_wait_and_capture_should_fail(suid_mycat_exe_path, suid_username_first,
			'/this_doesnt_exist_for_sure_or_perhaps_it_does')!

		full_path_tool_result := os_extensions.execute_wait_and_capture_should_succeed(default_multiuser_permissions.maybe_get_full_path_of_pid_tool_exe,
			'1')!
		assert full_path_tool_result.stdout.len > 0
		assert full_path_tool_result.stdout[0..1] == '/'
	}
}

fn test_access_default_policy_executed_by_owner_username() ! {
	println('#-#-# start #-#-# test_access_default_policy_executed_by_owner_username()')

	passman_state := passmanstate.PassManState{
		verify_access_for_getattr_on_directory_related_to_passman_folders: false
		access: passmanstate.AccessPolicy.executed_by_owner_username
		owner_username: suid_username_first
		name: 'complex example'
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

	base_multiuser_test_mounting_passman_and_run_body(passman_state, default_multiuser_permissions,
		passmanstate.CustomAccessAudit{fn [mut history_copy] (decision passmanstate.AccessDecision, decision_origin passmanstate.DecisionOrigin, path string, subject &passmanstate.FileSystemItem, op passmanstate.FsOperation, executor &passmanstate.Accessor) {
		history_copy << 'access_decision decision=${decision} p=${path} o=${op} u=${executor.username} e=${executor.exe_path}'
	}}, passmanstate.CustomAccessPrompt{fn [mut history_copy] (path string, subject &passmanstate.FileSystemItem, op passmanstate.FsOperation, executor &passmanstate.Accessor) chan bool {
		res := chan bool{cap: 1}
		res <- true

		history_copy << 'asked p=${path} o=${op} u=${executor.username} e=${executor.exe_path}'

		return res
	}}, fn [mut history_copy] () ! {
		history_copy << 'test start'

		history_copy << 'suidmycat first /secrets/by-name/somefolder/email'
		os_extensions.execute_wait_and_capture_should_succeed(suid_mycat_exe_path, suid_username_first,
			mount_point_path + '/secrets/by-name/somefolder/email')!

		history_copy << 'suidmycat second /secrets/by-name/somefolder/email'
		os_extensions.execute_wait_and_capture_should_fail(suid_mycat_exe_path, suid_username_second,
			mount_point_path + '/secrets/by-name/somefolder/email')!

		history_copy << 'test end'
	})!

	expected := [
		'test start',
		'suidmycat first /secrets/by-name/somefolder/email',
		// following four were auto accepted by verify_access_for_getattr_on_directory_related_to_passman_folders
		'access_decision decision=granted p=/secrets o=get_attribute u=${suid_username_first} e=${suid_mycat_exe_path}',
		'access_decision decision=granted p=/secrets/by-name o=get_attribute u=${suid_username_first} e=${suid_mycat_exe_path}',
		'access_decision decision=granted p=/secrets/by-name/somefolder o=get_attribute u=${suid_username_first} e=${suid_mycat_exe_path}',
		'access_decision decision=granted p=/secrets/by-name/somefolder/email o=get_attribute u=${suid_username_first} e=${suid_mycat_exe_path}',
		// following two accepted by custom policy
		'access_decision decision=granted p=/secrets/by-name/somefolder/email o=open_file u=${suid_username_first} e=${suid_mycat_exe_path}',
		'access_decision decision=granted p=/secrets/by-name/somefolder/email o=read_file u=${suid_username_first} e=${suid_mycat_exe_path}',
		'suidmycat second /secrets/by-name/somefolder/email',
		// rejected by default policy
		'access_decision decision=denied p=/secrets/by-name/somefolder/email o=open_file u=${suid_username_second} e=${suid_mycat_exe_path}',
		'test end',
	]

	assert_pretty_diff_string(expected.str(), history.str())
}

fn test_access_custom_policy_executed_by_owner_username() ! {
	println('#-#-# start #-#-# test_access_custom_policy_executed_by_owner_username()')

	passman_state := passmanstate.PassManState{
		verify_access_for_getattr_on_directory_related_to_passman_folders: false
		access: passmanstate.AccessPolicy.never_allowed
		owner_username: suid_username_first
		name: 'complex example'
		uuid_to_folder: {
			// empty folder
			rand.uuid_v4(): passmanstate.PassManFolder{
				access: passmanstate.AccessCustomPolicy{
					used: true
					policy: .executed_by_owner_username
				}
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

	base_multiuser_test_mounting_passman_and_run_body(passman_state, default_multiuser_permissions,
		passmanstate.CustomAccessAudit{fn [mut history_copy] (decision passmanstate.AccessDecision, decision_origin passmanstate.DecisionOrigin, path string, subject &passmanstate.FileSystemItem, op passmanstate.FsOperation, executor &passmanstate.Accessor) {
		history_copy << 'access_decision decision=${decision} p=${path} o=${op} u=${executor.username} e=${executor.exe_path}'
	}}, passmanstate.CustomAccessPrompt{fn [mut history_copy] (path string, subject &passmanstate.FileSystemItem, op passmanstate.FsOperation, executor &passmanstate.Accessor) chan bool {
		res := chan bool{cap: 1}
		res <- true

		history_copy << 'asked p=${path} o=${op} u=${executor.username} e=${executor.exe_path}'

		return res
	}}, fn [mut history_copy] () ! {
		history_copy << 'test start'

		history_copy << 'suidmycat first /secrets/by-name/somefolder/email'
		os_extensions.execute_wait_and_capture_should_succeed(suid_mycat_exe_path, suid_username_first,
			mount_point_path + '/secrets/by-name/somefolder/email')!

		history_copy << 'suidmycat second /secrets/by-name/somefolder/email'
		os_extensions.execute_wait_and_capture_should_fail(suid_mycat_exe_path, suid_username_second,
			mount_point_path + '/secrets/by-name/somefolder/email')!

		history_copy << 'test end'
	})!

	expected := [
		'test start',
		'suidmycat first /secrets/by-name/somefolder/email',
		// following four were auto accepted by verify_access_for_getattr_on_directory_related_to_passman_folders
		'access_decision decision=granted p=/secrets o=get_attribute u=${suid_username_first} e=${suid_mycat_exe_path}',
		'access_decision decision=granted p=/secrets/by-name o=get_attribute u=${suid_username_first} e=${suid_mycat_exe_path}',
		'access_decision decision=granted p=/secrets/by-name/somefolder o=get_attribute u=${suid_username_first} e=${suid_mycat_exe_path}',
		'access_decision decision=granted p=/secrets/by-name/somefolder/email o=get_attribute u=${suid_username_first} e=${suid_mycat_exe_path}',
		// following two accepted by custom policy
		'access_decision decision=granted p=/secrets/by-name/somefolder/email o=open_file u=${suid_username_first} e=${suid_mycat_exe_path}',
		'access_decision decision=granted p=/secrets/by-name/somefolder/email o=read_file u=${suid_username_first} e=${suid_mycat_exe_path}',
		'suidmycat second /secrets/by-name/somefolder/email',
		// rejected by default policy
		'access_decision decision=denied p=/secrets/by-name/somefolder/email o=open_file u=${suid_username_second} e=${suid_mycat_exe_path}',
		'test end',
	]

	assert_pretty_diff_string(expected.str(), history.str())
}

fn test_access_custom_policy_executed_by_owner_username_and_path_matches() ! {
	println('#-#-# start #-#-# test_access_custom_policy_executed_by_owner_username_and_path_matches()')

	passman_state := passmanstate.PassManState{
		verify_access_for_getattr_on_directory_related_to_passman_folders: false
		access: passmanstate.AccessPolicy.never_allowed
		owner_username: suid_username_first
		name: 'complex example'
		uuid_to_folder: {
			// empty folder
			rand.uuid_v4(): passmanstate.PassManFolder{
				access: passmanstate.AccessCustomPolicy{
					used: true
					policy: .executed_by_owner_username_and_path_matches
					exe_path: suid_mycat_exe_path
				}
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

	base_multiuser_test_mounting_passman_and_run_body(passman_state, default_multiuser_permissions,
		passmanstate.CustomAccessAudit{fn [mut history_copy] (decision passmanstate.AccessDecision, decision_origin passmanstate.DecisionOrigin, path string, subject &passmanstate.FileSystemItem, op passmanstate.FsOperation, executor &passmanstate.Accessor) {
		history_copy << 'access_decision decision=${decision} p=${path} o=${op} u=${executor.username} e=${executor.exe_path}'
	}}, passmanstate.CustomAccessPrompt{fn [mut history_copy] (path string, subject &passmanstate.FileSystemItem, op passmanstate.FsOperation, executor &passmanstate.Accessor) chan bool {
		res := chan bool{cap: 1}
		res <- true

		history_copy << 'asked p=${path} o=${op} u=${executor.username} e=${executor.exe_path}'

		return res
	}}, fn [mut history_copy] () ! {
		history_copy << 'test start'

		history_copy << 'suidmycat first /secrets/by-name/somefolder/email'
		os_extensions.execute_wait_and_capture_should_succeed(suid_mycat_exe_path, suid_username_first,
			mount_point_path + '/secrets/by-name/somefolder/email')!

		history_copy << 'suidmycat second /secrets/by-name/somefolder/email'
		os_extensions.execute_wait_and_capture_should_fail(suid_mycat_exe_path, suid_username_second,
			mount_point_path + '/secrets/by-name/somefolder/email')!

		history_copy << 'test end'
	})!

	expected := [
		'test start',
		'suidmycat first /secrets/by-name/somefolder/email',
		// following four were auto accepted by verify_access_for_getattr_on_directory_related_to_passman_folders
		'access_decision decision=granted p=/secrets o=get_attribute u=${suid_username_first} e=${suid_mycat_exe_path}',
		'access_decision decision=granted p=/secrets/by-name o=get_attribute u=${suid_username_first} e=${suid_mycat_exe_path}',
		'access_decision decision=granted p=/secrets/by-name/somefolder o=get_attribute u=${suid_username_first} e=${suid_mycat_exe_path}',
		'access_decision decision=granted p=/secrets/by-name/somefolder/email o=get_attribute u=${suid_username_first} e=${suid_mycat_exe_path}',
		// following two accepted by custom policy
		'access_decision decision=granted p=/secrets/by-name/somefolder/email o=open_file u=${suid_username_first} e=${suid_mycat_exe_path}',
		'access_decision decision=granted p=/secrets/by-name/somefolder/email o=read_file u=${suid_username_first} e=${suid_mycat_exe_path}',
		'suidmycat second /secrets/by-name/somefolder/email',
		// rejected by default policy
		'access_decision decision=denied p=/secrets/by-name/somefolder/email o=open_file u=${suid_username_second} e=${suid_mycat_exe_path}',
		'test end',
	]

	assert_pretty_diff_string(expected.str(), history.str())
}

fn test_access_custom_policy_user_and_path_matches() ! {
	println('#-#-# start #-#-# test_access_custom_policy_user_and_path_matches()')

	passman_state := passmanstate.PassManState{
		verify_access_for_getattr_on_directory_related_to_passman_folders: false
		access: passmanstate.AccessPolicy.never_allowed
		owner_username: this_username
		name: 'complex example'
		uuid_to_folder: {
			// empty folder
			rand.uuid_v4(): passmanstate.PassManFolder{
				access: passmanstate.AccessCustomPolicy{
					used: true
					policy: .user_and_path_matches
					exe_path: suid_mycat_exe_path
					username: suid_username_first
				}
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

	base_multiuser_test_mounting_passman_and_run_body(passman_state, default_multiuser_permissions,
		passmanstate.CustomAccessAudit{fn [mut history_copy] (decision passmanstate.AccessDecision, decision_origin passmanstate.DecisionOrigin, path string, subject &passmanstate.FileSystemItem, op passmanstate.FsOperation, executor &passmanstate.Accessor) {
		history_copy << 'access_decision decision=${decision} p=${path} o=${op} u=${executor.username} e=${executor.exe_path}'
	}}, passmanstate.CustomAccessPrompt{fn [mut history_copy] (path string, subject &passmanstate.FileSystemItem, op passmanstate.FsOperation, executor &passmanstate.Accessor) chan bool {
		res := chan bool{cap: 1}
		res <- true

		history_copy << 'asked p=${path} o=${op} u=${executor.username} e=${executor.exe_path}'

		return res
	}}, fn [mut history_copy] () ! {
		history_copy << 'test start'

		history_copy << 'suid-mycat first /secrets/by-name/somefolder/email'
		os_extensions.execute_wait_and_capture_should_succeed(suid_mycat_exe_path, suid_username_first,
			mount_point_path + '/secrets/by-name/somefolder/email')!

		history_copy << 'suid-mycat this /secrets/by-name/somefolder/email'
		os_extensions.execute_wait_and_capture_should_fail(suid_mycat_exe_path, this_username,
			mount_point_path + '/secrets/by-name/somefolder/email')!

		history_copy << 'test end'
	})!

	expected := [
		'test start',
		'suid-mycat first /secrets/by-name/somefolder/email',
		// following four were auto accepted by verify_access_for_getattr_on_directory_related_to_passman_folders
		'access_decision decision=granted p=/secrets o=get_attribute u=${suid_username_first} e=${suid_mycat_exe_path}',
		'access_decision decision=granted p=/secrets/by-name o=get_attribute u=${suid_username_first} e=${suid_mycat_exe_path}',
		'access_decision decision=granted p=/secrets/by-name/somefolder o=get_attribute u=${suid_username_first} e=${suid_mycat_exe_path}',
		'access_decision decision=granted p=/secrets/by-name/somefolder/email o=get_attribute u=${suid_username_first} e=${suid_mycat_exe_path}',
		// following two accepted by custom policy
		'access_decision decision=granted p=/secrets/by-name/somefolder/email o=open_file u=${suid_username_first} e=${suid_mycat_exe_path}',
		'access_decision decision=granted p=/secrets/by-name/somefolder/email o=read_file u=${suid_username_first} e=${suid_mycat_exe_path}',
		'suid-mycat this /secrets/by-name/somefolder/email',
		'access_decision decision=denied p=/secrets/by-name/somefolder/email o=open_file u=${this_username} e=${suid_mycat_exe_path}',
		'test end',
	]

	assert_pretty_diff_string(expected.str(), history.str())
}
