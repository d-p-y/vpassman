module main

import fuse
import rand
import passmanstate
import os
import time
import os_extensions
import readline

pub fn new_state_empty() passmanstate.PassManState {
	return passmanstate.PassManState{
		name: 'empty'
		owner_username: os.getenv('LOGNAME')
	}
}

pub fn new_state_complex_example() passmanstate.PassManState {
	return passmanstate.PassManState{
		access: .ask
		verify_access_for_getattr_on_directory_related_to_passman_folders: false
		owner_username: os.getenv('LOGNAME')
		name: 'complex example'
		uuid_to_folder: {
			// empty folder
			rand.uuid_v4(): passmanstate.PassManFolder{
				name: 'empty folder'
			}
			// one standard attribute folder
			rand.uuid_v4(): passmanstate.PassManFolder{
				access: passmanstate.AccessCustomPolicy{
					used: true
					policy: .executed_by_owner_username_and_path_matches
					username: 'dominik'
					exe_path: '/usr/bin/cat'
				}
				name: 'folder with one standard attr (dominik cat-able)'
				uuid_to_attribute: {
					rand.uuid_v4(): passmanstate.PassManItemAttribute{
						identifier: passmanstate.AttributeIdentifierStandard{passmanstate.AttributeIdentifierKind.url}
						value: 'http://example.com'
					}
				}
			}
			// one custom attribute folder
			rand.uuid_v4(): passmanstate.PassManFolder{
				name: 'folder with one custom attr'
				uuid_to_attribute: {
					rand.uuid_v4(): passmanstate.PassManItemAttribute{
						identifier: passmanstate.AttributeIdentifierCustom{'mobile phone number'}
						value: '+48 000 00 00'
					}
				}
			}
			// duplicated names
			rand.uuid_v4(): passmanstate.PassManFolder{
				name: 'duplicated name'
			}
			rand.uuid_v4(): passmanstate.PassManFolder{
				name: 'duplicated name'
			}
		}
	}
}

fn update_fs_state(mut fuse_state fuse.FuseState, mut audit passmanstate.IAccessAudit, mut access_prompt passmanstate.AccessRequestManager) ! {
	delay_sec := 3

	println('sleep for ${delay_sec}s so that you can see that FS is not initialized')
	time.sleep(delay_sec * 1000 * time.millisecond)

	println('populating FS with empty impl')
	pass_man_state_initial := new_state_empty()

	settings := passmanstate.PassManExportSettings{
		uid: 1000
		gid: 136
		dir: os_extensions.new_permissions_from_octets('r-x------')!
		file: os_extensions.new_permissions_from_octets('r-x------')!
	}

	pass_man_state_initial.wire_to_fuse_without_custom_compute(mut fuse_state, settings,
		access_prompt, audit)

	println('sleep for ${delay_sec}s so that you can see that FS is empty')
	time.sleep(delay_sec * 1000 * time.millisecond)

	println('populating FS with example content - start')
	pass_man_state_complex := new_state_complex_example()
	// dump(pass_man_state_complex)

	pass_man_state_complex.wire_to_fuse_without_custom_compute(mut fuse_state, settings,
		access_prompt, audit)

	println('populating FS with new content - ended')

	for {
		println('staying alive...')
		time.sleep(time.second * 5)
	}
}

[heap]
struct PromptItem {
	path      string
	subject   &passmanstate.FileSystemItem
	operation passmanstate.FsOperation
	executor  &passmanstate.Accessor
	reply     chan bool
}

[heap]
struct UserPrompter {
	bus chan &PromptItem = chan &PromptItem{cap: 100}
mut:
	manager &passmanstate.AccessRequestManager
}

fn (mut u UserPrompter) prompting_loop(mut fuse_state fuse.FuseState) {
	mut rdr := readline.Readline{}

	mut requests := []passmanstate.AccessRequestWithId{}
	mut should_fetch_requests := true
	mut ref_to_should_fetch_requests := &should_fetch_requests

	subscription := u.manager.subscribe(fn [mut ref_to_should_fetch_requests] () {
		unsafe {
			*ref_to_should_fetch_requests = true
		}
		println('changes in request list, press enter to refresh')
	})

	defer {
		u.manager.unsubscribe(subscription)
	}

	for {
		if should_fetch_requests {
			should_fetch_requests = false

			requests = u.manager.get_pending_requests()

			println('have ${requests.len} in queue')

			for i, req in requests {
				println('${i + 1} id=${req.id} oper=${req.request.oper} path=${req.request.path} folder?=${req.request.maybe_get_folder_name()}')
			}

			$if debug {
				dump(requests)
			}
		}

		if raw_cmd := rdr.read_line('command [quit,list,ok,reject]:') {
			$if debug {
				println('got request [${raw_cmd}]')
			}

			cmd := raw_cmd.trim_right('\r\n')

			match cmd {
				'quit' {
					// TODO enable 'auto reject requests' and reject all current pending requests
					u.manager.reject_all_pending_and_future()

					fuse_state.unmount() or {
						println('unmounting failed')
						return
					}
					println('unmounted')
					return
				}
				'list' {
					should_fetch_requests = true
				}
				else {
					cmd_items := cmd.split_any(' \t')

					if cmd_items.len < 1 {
						println('expected: verb whitespace one-or-more-arguments-separated-with-whitespace')
						continue
					}

					match cmd_items[0] {
						'ok' {
							if requests.len <= 0 {
								println('no pending requests')
								continue
							}

							if cmd_items.len <= 1 {
								println("expected one or more arguments to 'ok' command. Each argument is number of request from 'list' command")
								continue
							}

							for i_as_str in cmd_items[1..] {
								i := i_as_str.parse_uint(10, 32) or {
									println('could not parse argument as nonnegative integer ${i_as_str}')
									break
								}

								if i - 1 < 0 || i - 1 >= requests.len {
									println('request id must be between 1 and ${requests.len}')
									break
								}

								u.manager.reply_to_request(requests[i - 1].id, true) or {
									println('accepting request failed ${err}')
									continue
								}

								println('accepted request')
							}
							should_fetch_requests = true
						}
						'reject' {
							if requests.len <= 0 {
								println('no pending requests')
								continue
							}

							if cmd_items.len <= 1 {
								println("expected one or more arguments to 'reject' command. Each argument is number of request from 'list' command")
								continue
							}

							for i_as_str in cmd_items[1..] {
								i := i_as_str.parse_uint(10, 32) or {
									println('could not parse argument as nonnegative integer ${i_as_str}')
									break
								}

								if i - 1 < 0 || i - 1 >= requests.len {
									println('request id must be between 1 and ${requests.len}')
									break
								}

								u.manager.reply_to_request(requests[i - 1].id, false) or {
									println('rejecting request failed ${err}')
									continue
								}

								println('rejected request')
							}
							should_fetch_requests = true
						}
						else {
							println('unknown command ${cmd_items[0]}')
							continue
						}
					}
				}
			}
		}
	}
}

[heap]
struct SyslogAudit {
}

// implements IAccessAudit
fn (t &SyslogAudit) audit_access(decision passmanstate.AccessDecision, decision_origin passmanstate.DecisionOrigin, path string, subject &passmanstate.FileSystemItem, op passmanstate.FsOperation, executor &passmanstate.Accessor) {
	os_extensions.syslog_info('access subject=${subject.passman_folder_name_or_empty()} executor_username=${executor.username} executor_exe_path=${executor.exe_path} path=${path} operation=${op} decision=${decision} decision_origin=${decision_origin}')
}

fn main() {
	os_extensions.syslog_init('vpassman')
	os_extensions.syslog_info('starting')

	//$ journalctl --since -1min

	os_extensions.syslog_debug('creating state')

	args := C.fusewrapper_fuse_args{
		foreground: true
		single_thread: true
		exe_path: os.args[0].str
		mount_destination: os.getenv('VPASSMAN_MOUNTPOINT').str
	}

	mut fuse_state := fuse.new_fuse_state(args)!
	// dump(fuse_state)

	println('mounting')

	mut audit := &SyslogAudit{}
	mut req_man := &passmanstate.AccessRequestManager{
		audit: audit
	}
	mut prompter := &UserPrompter{
		manager: req_man
	}
	go prompter.prompting_loop(mut fuse_state)

	thr := spawn update_fs_state(mut fuse_state, mut audit, mut req_man)

	thr.wait()!

	fuse_state.mount()
	os_extensions.syslog_info('ending')
}
