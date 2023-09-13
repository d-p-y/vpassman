module main

import fuse
import passmanstate
import os_extensions
import rand
import time

fn to_disable_fuse_warning_when_implemented_causes_compilation_error() bool {
	a := fuse.Struct_fusewrapper_getattr_reply{}
	return a.uid == 0
}

const (
	millis_for_queueing_request   = time.millisecond * 200
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

fn test_two_simultaneus_reads_queued_and_visible_in_queue_and_deliver_replies_vanishing_from_queue_test() ! {
	println('#-#-# start #-#-# test_two_simultaneus_reads_queued_and_visible_in_queue_and_deliver_replies_vanishing_from_queue_test()')

	passman_state := passmanstate.PassManState{
		verify_access_for_getattr_on_directory_related_to_passman_folders: false
		access: passmanstate.AccessPolicy.ask
		owner_username: this_username
		name: 'complex example'
		uuid_to_folder: {
			rand.uuid_v4(): passmanstate.PassManFolder{
				name: 'somefolder1'
				uuid_to_attribute: {
					rand.uuid_v4(): passmanstate.PassManItemAttribute{
						identifier: passmanstate.AttributeIdentifierStandard{passmanstate.AttributeIdentifierKind.email}
						value: 'a@example.com'
					}
				}
			}
			rand.uuid_v4(): passmanstate.PassManFolder{
				name: 'somefolder2'
				uuid_to_attribute: {
					rand.uuid_v4(): passmanstate.PassManItemAttribute{
						identifier: passmanstate.AttributeIdentifierStandard{passmanstate.AttributeIdentifierKind.email}
						value: 'b@example.com'
					}
				}
			}
		}
	}

	mut history := []string{}
	mut history_copy := &history

	audit := &passmanstate.CustomAccessAudit{fn [mut history_copy] (decision passmanstate.AccessDecision, decision_origin passmanstate.DecisionOrigin, path string, subject &passmanstate.FileSystemItem, op passmanstate.FsOperation, executor &passmanstate.Accessor) {
		history_copy << 'access_decision decision_origin=${decision_origin} decision=${decision} p=${path} o=${op} u=${executor.username} e=${executor.exe_path}'
	}}

	mut accreqman := &passmanstate.AccessRequestManager{
		audit: audit
	}
	mut accreqman_copy := accreqman

	base_multiuser_multithreaded_test_mounting_passman_and_run_body(passman_state, default_multiuser_permissions,
		audit, accreqman, fn [mut history_copy, mut accreqman_copy] () ! {
		history_copy << 'test start'

		history_copy << 'suid-mycat started first /secrets/by-name/somefolder1/email'
		mut pr1 := os_extensions.execute_without_wait(suid_mycat_exe_path, suid_username_first,
			mount_point_path + '/secrets/by-name/somefolder1/email')
		defer {
			pr1.close()
		}

		time.sleep(millis_for_queueing_request)

		history_copy << 'suid-mycat started second /secrets/by-name/somefolder2/email'
		mut pr2 := os_extensions.execute_without_wait(suid_mycat_exe_path, suid_username_second,
			mount_point_path + '/secrets/by-name/somefolder2/email')
		defer {
			pr2.close()
		}
		time.sleep(millis_for_queueing_request)

		if !pr1.is_alive() {
			println(pr1.stderr_slurp())
			assert pr1.is_alive()
		}

		assert pr2.is_alive()

		mut reqs := accreqman_copy.get_pending_requests()

		assert 2 == reqs.len

		mut req1 := reqs.filter(it.request.path == '/secrets/by-name/somefolder1/email')
		assert req1.len == 1
		assert req1[0].request.oper == .get_attribute

		mut req2 := reqs.filter(it.request.path == '/secrets/by-name/somefolder2/email')
		assert req2.len == 1
		assert req2[0].request.oper == .get_attribute

		history_copy << 'accept 1st to progress from .get_attribute to .open_file'

		accreqman_copy.reply_to_request(req1[0].id, true)!
		time.sleep(millis_for_queueing_request)

		assert pr1.is_alive()
		assert pr2.is_alive()

		reqs = accreqman_copy.get_pending_requests()
		assert 2 == reqs.len
		assert 1 == reqs.filter(it.id == req2[0].id).len
		assert 0 == reqs.filter(it.id == req1[0].id).len

		req1 = reqs.filter(it.request.path == '/secrets/by-name/somefolder1/email')
		assert req1[0].request.oper == .open_file

		history_copy << 'accept 1st to progress from .open_file to .read_file'
		accreqman_copy.reply_to_request(req1[0].id, true)!
		time.sleep(millis_for_queueing_request)

		reqs = accreqman_copy.get_pending_requests()
		assert 2 == reqs.len
		assert 1 == reqs.filter(it.id == req2[0].id).len
		req1 = reqs.filter(it.request.path == '/secrets/by-name/somefolder1/email')
		assert req1[0].request.oper == .read_file

		assert pr1.is_alive()
		assert pr2.is_alive()

		history_copy << 'reject 2nd'
		accreqman_copy.reply_to_request(req2[0].id, false)!
		time.sleep(millis_for_queueing_request)

		reqs = accreqman_copy.get_pending_requests()
		assert 1 == reqs.len
		assert 0 == reqs.filter(it.id == req2[0].id).len

		assert pr1.is_alive()

		assert !pr2.is_alive()
		assert pr2.code != 0

		history_copy << 'accept 1st .read_file'
		req1 = reqs.filter(it.request.path == '/secrets/by-name/somefolder1/email')
		accreqman_copy.reply_to_request(req1[0].id, true)!
		time.sleep(millis_for_queueing_request)

		assert !pr1.is_alive()
		assert pr1.code == 0

		reqs = accreqman_copy.get_pending_requests()
		assert 0 == reqs.len

		history_copy << 'test end'
	})!

	expected := [
		'test start',
		'suid-mycat started first /secrets/by-name/somefolder1/email',
		'access_decision decision_origin=policy decision=granted p=/secrets o=get_attribute u=${suid_username_first} e=${suid_mycat_exe_path}',
		'access_decision decision_origin=policy decision=granted p=/secrets/by-name o=get_attribute u=${suid_username_first} e=${suid_mycat_exe_path}',
		'access_decision decision_origin=policy decision=granted p=/secrets/by-name/somefolder1 o=get_attribute u=${suid_username_first} e=${suid_mycat_exe_path}',
		'access_decision decision_origin=policy decision=interaction_required p=/secrets/by-name/somefolder1/email o=get_attribute u=${suid_username_first} e=${suid_mycat_exe_path}',
		'suid-mycat started second /secrets/by-name/somefolder2/email',
		'access_decision decision_origin=policy decision=granted p=/secrets/by-name/somefolder2 o=get_attribute u=${suid_username_second} e=${suid_mycat_exe_path}',
		'access_decision decision_origin=policy decision=interaction_required p=/secrets/by-name/somefolder2/email o=get_attribute u=${suid_username_second} e=${suid_mycat_exe_path}',
		'accept 1st to progress from .get_attribute to .open_file',
		'access_decision decision_origin=interactive decision=granted p=/secrets/by-name/somefolder1/email o=get_attribute u=${suid_username_first} e=${suid_mycat_exe_path}',
		'access_decision decision_origin=policy decision=interaction_required p=/secrets/by-name/somefolder1/email o=open_file u=${suid_username_first} e=${suid_mycat_exe_path}',
		'accept 1st to progress from .open_file to .read_file',
		'access_decision decision_origin=interactive decision=granted p=/secrets/by-name/somefolder1/email o=open_file u=${suid_username_first} e=${suid_mycat_exe_path}',
		'access_decision decision_origin=policy decision=interaction_required p=/secrets/by-name/somefolder1/email o=read_file u=${suid_username_first} e=${suid_mycat_exe_path}',
		'reject 2nd',
		'access_decision decision_origin=interactive decision=denied p=/secrets/by-name/somefolder2/email o=get_attribute u=${suid_username_second} e=${suid_mycat_exe_path}',
		'accept 1st .read_file',
		'access_decision decision_origin=interactive decision=granted p=/secrets/by-name/somefolder1/email o=read_file u=${suid_username_first} e=${suid_mycat_exe_path}',
		'test end',
	]

	assert_pretty_diff_string(expected.str(), history.str())
}
