module passmanstate

import fuse
import os
import model

pub fn (mut t PassManStateWiredToFuse) unmount() ! {
	return t.fuse_state.unmount()
}

fn (t &PassManStateWiredToFuse) compute_has_access(path string, subject &FileSystemItem, op FsOperation, executor &Accessor) AccessDecision {
	$if debug {
		println('is_access_permitted requested for subject=${subject.name} operation=${op} by u=${executor.username} exe=${executor.exe_path}')
	}

	// paranoid mode / silly questions
	if !t.passman.verify_access_for_directories_unrelated_to_passman_folders
		&& !subject.is_related_to_passman_folder() {
		return AccessDecision.granted
	}

	if !t.passman.verify_access_for_getattr_on_directory_related_to_passman_folders
		&& subject.details is Dir && op == .get_attribute {
		return AccessDecision.granted
	}

	// dump(executor)

	if origin := subject.get_origin() {
		if origin.access.used {
			acp := origin.access
			// dump(acp)

			return match acp.policy {
				.ask {
					AccessDecision.interaction_required
				}
				.never_allowed {
					AccessDecision.denied
				}
				.executed_by_owner_username {
					grant := executor.username == t.passman.owner_username
					if grant {
						AccessDecision.granted
					} else {
						AccessDecision.denied
					}
				}
				.executed_by_owner_username_and_path_matches {
					grant := acp.exe_path == executor.exe_path
						&& t.passman.owner_username == executor.username
					if grant {
						AccessDecision.granted
					} else {
						AccessDecision.denied
					}
				}
				.user_and_path_matches {
					grant := acp.exe_path == executor.exe_path && acp.username == executor.username
					if grant {
						AccessDecision.granted
					} else {
						AccessDecision.denied
					}
				}
			}
		}
	}

	return match t.passman.access {
		.ask {
			AccessDecision.interaction_required
		}
		.never_allowed {
			AccessDecision.denied
		}
		.executed_by_owner_username {
			grant := executor.username == t.passman.owner_username
			if grant {
				AccessDecision.granted
			} else {
				AccessDecision.denied
			}
		}
		else {
			AccessDecision.denied
		}
	}
}

fn (mut t PassManStateWiredToFuse) assure_access_granted(path string, subject &FileSystemItem, op FsOperation, accessor &Accessor) !model.Unit {
	$if debug {
		println('assure_access_granted starting')
	}

	mut access_reply_provider := t.request_has_access_reply(path, subject, op, accessor)
	access_granted := <-access_reply_provider

	if !access_granted {
		return error('access not granted')
	}

	access_reply_provider.close()
	return model.unit
}

// implementation of IAccessPrompt
pub fn (mut t PassManStateWiredToFuse) request_has_access_reply(path string, subject &FileSystemItem, oper FsOperation, executor &Accessor) chan bool {
	policy_result := t.access_compute.compute_has_access(path, subject, oper, executor)

	t.audit.audit_access(policy_result, .policy, path, subject, oper, executor)

	$if debug {
		println('policy_result is ${policy_result}')
	}

	match policy_result {
		.granted {
			result := chan bool{cap: 1}
			result <- true
			return result
		}
		.denied {
			result := chan bool{cap: 1}
			result <- false
			return result
		}
		.interaction_required {
			$if debug {
				println('invoking request_access_prompt')
			}

			return t.request_access_prompt.request_has_access_reply(path, subject, oper,
				executor)
		}
	}
}

// must match signature of fuse.Fn_getattr = fn (&C.fusewrapper_common_params, &C.fusewrapper_getattr_reply)
pub fn (mut t PassManStateWiredToFuse) getattr_implementation(common &C.fusewrapper_common_params, mut reply fuse.Struct_fusewrapper_getattr_reply) {
	// print_backtrace()

	// dump(t.settings)
	// dump(common)

	fn_name := 'build_fn_getattr'

	$if debug {
		println('${fn_name} starting')
	}

	path := unsafe { cstring_to_vstring(common.path).clone() }

	reply.result = fuse.getattr_no_such_dir // assume failure

	$if debug {
		println('${fn_name} invoked for common=${common} and passmanstate ${t.passman.name}')
	}

	path_info := t.root.get_path_info(path) or {
		$if debug {
			println('${fn_name} ended NOTOK path error=${err}')
		}
		return
	}

	$if debug {
		println('${fn_name} about to build_accessor')
	}

	accessor := t.build_accessor(common) or {
		$if debug {
			println('${fn_name} ended NOTOK accessor error=${err}')
		}
		return
	}

	$if debug {
		println('${fn_name} about to assure_access_granted')
	}

	_ := t.assure_access_granted(path, path_info, FsOperation.get_attribute, accessor) or {
		$if debug {
			println('${fn_name} ended NOTOK access denied')
		}
		return
	}

	$if debug {
		println('${fn_name} returned from assure_access_granted')
	}

	reply.uid = path_info.uid
	reply.gid = path_info.gid
	reply.result = fuse.getattr_success
	reply.item_type = match path_info.details {
		Dir { fuse.File_system_item_type.directory }
		File { fuse.File_system_item_type.file }
	}
	reply.permissions_stat_h_bits = path_info.permissions.to_stat_h_permission_bits()
	reply.file_size_bytes = match path_info.details {
		File {
			path_info.details.content.len
		}
		else {
			0
		}
	}

	$if debug {
		println('${fn_name} ended OK')
	}
}

// must match signature of fuse.Fn_readdir = fn (&C.fusewrapper_common_params, Fn_adder) int
pub fn (mut t PassManStateWiredToFuse) readdir_implementation(common &C.fusewrapper_common_params, adder fuse.Fn_adder) int {
	fn_name := 'build_fn_readdir'

	$if debug {
		println('${fn_name} starting')
	}

	path := unsafe { cstring_to_vstring(common.path).clone() }
	failure_result := fuse.readdir_no_such_dir // assume failure

	$if debug {
		println('${fn_name} invoked for common=${common} and passmanstate ${t.passman.name}')
	}

	path_info, listing := t.root.list_path(path) or {
		$if debug {
			println('${fn_name} ended NOTOK error=${err}')
		}
		return failure_result
	}

	accessor := t.build_accessor(common) or {
		$if debug {
			println('${fn_name} ended NOTOK accessor error=${err}')
		}
		return failure_result
	}

	_ := t.assure_access_granted(path, path_info, FsOperation.list_dir, accessor) or {
		$if debug {
			println('${fn_name} ended NOTOK access denied')
		}
		return failure_result
	}

	adder('.'.str)
	adder('..'.str)

	for chld in listing.children {
		chld_path := os.join_path_single(path, chld.name)
		_ := t.assure_access_granted(chld_path, chld, FsOperation.include_in_listing,
			accessor) or { continue }

		adder(chld.name.str)
	}

	$if debug {
		println('${fn_name} ended OK')
	}

	return fuse.readdir_no_more_items
}

// must match signature of fuse.Fn_open = fn (&C.fusewrapper_common_params, Open_mode) int
pub fn (mut t PassManStateWiredToFuse) open_implementation(common &C.fusewrapper_common_params, mode fuse.Open_mode) int {
	// print_backtrace()

	// dump(t.settings)
	// dump(common)

	fn_name := 'build_fn_open'
	$if debug {
		println('${fn_name} starting')
	}

	path := unsafe { cstring_to_vstring(common.path).clone() }
	failure_result := fuse.open_no_such_file

	$if debug {
		println('${fn_name} invoked common=${common} and passmanstate ${t.passman.name}')
	}

	path_info, _ := t.root.get_file(path) or {
		$if debug {
			println('${fn_name} ended NOTOK error=${err}')
		}
		return failure_result
	}

	accessor := t.build_accessor(common) or {
		$if debug {
			println('${fn_name} ended NOTOK accessor error=${err}')
		}
		return failure_result
	}

	_ := t.assure_access_granted(path, path_info, FsOperation.open_file, accessor) or {
		$if debug {
			println('${fn_name} ended NOTOK access denied')
		}
		return failure_result
	}

	$if debug {
		println('${fn_name} - file ended OK')
	}
	return fuse.open_success
}

// must match signature of fuse.Fn_read = fn (&C.fusewrapper_common_params, i64, u64, Fn_submit_read_result)
pub fn (mut t PassManStateWiredToFuse) read_implementation(common &C.fusewrapper_common_params, raw_offset i64, raw_bytes_to_read u64, submit_result fuse.Fn_submit_read_result) int {
	// print_backtrace()

	// dump(t.settings)
	// dump(common)

	fn_name := 'build_fn_read'
	$if debug {
		println('${fn_name} starting')
	}

	path := unsafe { cstring_to_vstring(common.path).clone() }
	failure_result := fuse.open_no_such_file

	assert raw_offset >= 0
	offset := int(raw_offset)
	assert offset >= 0

	assert raw_bytes_to_read > 0
	bytes_to_read := int(raw_bytes_to_read)
	assert bytes_to_read > 0

	$if debug {
		println('${fn_name} invoked common=${common} and passmanstate ${t.passman.name} offset ${offset} bytes_to_read=${bytes_to_read}')
	}

	// print_backtrace()
	path_info, file_details := t.root.get_file(path) or {
		$if debug {
			println('${fn_name} - NOTOK no such path')
		}
		return failure_result
	}
	// print_backtrace()

	accessor := t.build_accessor(common) or {
		$if debug {
			println('${fn_name} ended NOTOK accessor error=${err}')
		}
		return failure_result
	}

	_ := t.assure_access_granted(path, path_info, FsOperation.read_file, accessor) or {
		$if debug {
			println('${fn_name} ended NOTOK access denied')
		}
		return failure_result
	}

	$if debug {
		println('${fn_name} - file found len=${file_details.content.len}')
	}

	if offset >= file_details.content.len {
		return 0 // no bytes were read
	}

	allowed_to_read := file_details.content.len - offset

	$if debug {
		println('${fn_name} - allowed_to_read=${allowed_to_read}')
	}

	bytes_read := if bytes_to_read > allowed_to_read { allowed_to_read } else { bytes_to_read }

	$if debug {
		println('${fn_name} - bytes_read=${bytes_read}')
	}

	$if debug {
		println('${fn_name} - will submit substr ${offset} -> ${offset} + ${bytes_read}]')
	}
	snippet := file_details.content.substr(offset, offset + bytes_read)

	$if debug {
		println('${fn_name} - as text=${snippet}')
	}

	submit_result(snippet.str, u64(bytes_read))
	return int(bytes_read)
}
