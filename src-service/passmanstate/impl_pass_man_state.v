module passmanstate

import fuse
import os_extensions

fn (t &PassManState) build_by_name_dirs(perms PassManExportSettings) &Dir {
	mut result := []&FileSystemItem{}

	mut duplicates := map[string]int{}

	mut uids_as_keys := t.uuid_to_folder.keys().clone()
	uids_as_keys.sort()

	for uuid_as_key in uids_as_keys {
		folder := t.uuid_to_folder[uuid_as_key]
		dups_val := duplicates[folder.name]

		duplicates[folder.name] = duplicates[folder.name] + 1

		result << &FileSystemItem{
			name: if dups_val <= 0 { folder.name } else { '${folder.name} (${dups_val + 1})' }
			uid: perms.uid
			gid: perms.gid
			permissions: perms.dir
			details: &DirOrFile(folder.build_site_folder_without_extra_name_entry(perms))
			origin: &folder
		}
	}

	return &Dir{
		children: result
	}
}

fn (t &PassManState) build_by_url_dirs(perms PassManExportSettings) &Dir {
	mut result := []&FileSystemItem{}

	mut duplicates := map[string]int{}

	mut uids_as_keys := t.uuid_to_folder.keys().clone()
	uids_as_keys.sort()

	for uid_as_key in uids_as_keys {
		folder := t.uuid_to_folder[uid_as_key]

		if url := folder.maybe_get_url() {
			dups_val := duplicates[url]

			duplicates[url] = duplicates[url] + 1

			result << &FileSystemItem{
				name: sanitize_slashes(if dups_val <= 0 { url } else { '${url} (${dups_val + 1})' })
				uid: perms.uid
				gid: perms.gid
				permissions: perms.dir
				details: &DirOrFile(folder.build_site_folder_with_extra_name_entry(perms))
				origin: &folder
			}
		}
	}

	return &Dir{
		children: result
	}
}

fn (t &PassManStateWiredToFuse) build_accessor(common &C.fusewrapper_common_params) !&Accessor {
	$if debug {
		println('build_accessor from common ${common}')
	}

	// dump(t.settings)
	// dump(common)

	mut exe_path := ''

	match t.settings.maybe_get_full_path_of_pid_tool_exe {
		'' {
			$if debug {
				println('using readlink to identify full path of pid=${common.requested_by_pid}')
			}

			exe_path = os_extensions.get_exe_path_of_pid(common.requested_by_pid)!
		}
		else {
			tool_exe := t.settings.maybe_get_full_path_of_pid_tool_exe

			$if debug {
				println('using tool to identify full path of pid=${common.requested_by_pid} tool=${tool_exe}')
			}

			outcome := os_extensions.execute_wait_and_capture(tool_exe, '${common.requested_by_pid}')

			if outcome.exit_code != 0 {
				return error('tool returned error exit_code=${outcome.exit_code} exe=${t.settings.maybe_get_full_path_of_pid_tool_exe}')
			}
			exe_path = outcome.stdout#[..-1] // trailing newline to have no issues with buffering
		}
	}

	return &Accessor{
		username: os_extensions.get_username_by_uid(common.requested_by_uid)!
		exe_path: exe_path
	}
}

fn (t &PassManState) to_file_system(perms PassManExportSettings) &FileSystemItem {
	by_name := &FileSystemItem{
		name: 'by-name'
		uid: perms.uid
		gid: perms.gid
		permissions: perms.dir
		details: t.build_by_name_dirs(perms)
	}

	by_url := &FileSystemItem{
		name: 'by-url'
		uid: perms.uid
		gid: perms.gid
		permissions: perms.dir
		details: &DirOrFile(t.build_by_url_dirs(perms))
	}

	secrets_dir := &FileSystemItem{
		name: 'secrets'
		uid: perms.uid
		gid: perms.gid
		permissions: perms.dir
		details: &DirOrFile(Dir{
			children: [by_name, by_url]
		})
	}

	root := &FileSystemItem{
		name: ''
		uid: perms.uid
		gid: perms.gid
		permissions: perms.dir
		details: &DirOrFile(Dir{
			children: [secrets_dir]
		})
	}

	return root
}

pub fn (t &PassManState) wire_to_fuse_full(mut fuse_state fuse.FuseState, settings PassManExportSettings, access_prompt IAccessPrompt, access_audit IAccessAudit, access_compute IAccessCompute) &PassManStateWiredToFuse {
	result := &PassManStateWiredToFuse{
		passman: t
		root: t.to_file_system(settings)
		settings: settings
		fuse_state: fuse_state
		audit: access_audit
		request_access_prompt: access_prompt
		access_compute: access_compute
	}

	fuse_state.set_getattr(result.getattr_implementation)
	fuse_state.set_readdir(result.readdir_implementation)
	fuse_state.set_open(result.open_implementation)
	fuse_state.set_read(result.read_implementation)

	return result
}

pub fn (t &PassManState) wire_to_fuse_without_custom_compute(mut fuse_state fuse.FuseState, settings PassManExportSettings, access_prompt IAccessPrompt, access_audit IAccessAudit) &PassManStateWiredToFuse {
	mut result := &PassManStateWiredToFuse{
		passman: t
		root: t.to_file_system(settings)
		settings: settings
		fuse_state: fuse_state
		audit: access_audit
		request_access_prompt: access_prompt
		access_compute: AlwaysDeniedAccessCompute{} // to be replaced in next line
	}
	result.access_compute = result // replace with default policy

	fuse_state.set_getattr(result.getattr_implementation)
	fuse_state.set_readdir(result.readdir_implementation)
	fuse_state.set_open(result.open_implementation)
	fuse_state.set_read(result.read_implementation)

	return result
}

pub fn (t &PassManState) wire_to_fuse_without_prompt_and_audit(mut fuse_state fuse.FuseState, settings PassManExportSettings, access_prompt IAccessPrompt) &PassManStateWiredToFuse {
	mut result := &PassManStateWiredToFuse{
		passman: t
		root: t.to_file_system(settings)
		settings: settings
		fuse_state: fuse_state
		audit: EmptyAccessAudit{}
		request_access_prompt: access_prompt
		access_compute: AlwaysDeniedAccessCompute{} // to be replaced in next line
	}
	result.access_compute = result // replace with default policy

	fuse_state.set_getattr(result.getattr_implementation)
	fuse_state.set_readdir(result.readdir_implementation)
	fuse_state.set_open(result.open_implementation)
	fuse_state.set_read(result.read_implementation)

	return result
}

pub fn (t &PassManState) wire_to_fuse_without_access_checking(mut fuse_state fuse.FuseState, settings PassManExportSettings) &PassManStateWiredToFuse {
	result := &PassManStateWiredToFuse{
		passman: t
		root: t.to_file_system(settings)
		settings: settings
		fuse_state: fuse_state
		audit: EmptyAccessAudit{}
		request_access_prompt: DenyingAccessPrompt{}
		access_compute: IAccessCompute(AlwaysGrantedAccessCompute{})
	}

	fuse_state.set_getattr(result.getattr_implementation)
	fuse_state.set_readdir(result.readdir_implementation)
	fuse_state.set_open(result.open_implementation)
	fuse_state.set_read(result.read_implementation)

	return result
}

pub fn (mut t PassManState) process_folder_by_uuid(folder_uuid string, continuation fn (mut PassManFolder) !) ! {
	for fldr_id, mut fldr in t.uuid_to_folder {
		if fldr_id == folder_uuid {
			continuation(mut fldr)!
			return
		}
	}
	return error('could not find folder with ident=${folder_uuid}')
}

pub fn (mut t PassManState) process_attribute_by_uuid[T](attribute_ident string, continutation fn (mut PassManFolder, mut PassManItemAttribute) !T) !T {
	for _, mut fldr in t.uuid_to_folder {
		for attr_id, mut attr in fldr.uuid_to_attribute {
			if attribute_ident == attr_id {
				return continutation(mut fldr, mut attr)
			}
		}
	}

	return error('could not find attribute with ident=${attribute_ident}')
}

// 2022-11 map has ordered keys so can leverage this fact for easier comparison
pub fn (t PassManState) cannonicalize() PassManState {
	mut result := PassManState{
		...t
		uuid_to_folder: map[string]PassManFolder{}
	}

	mut folder_uuids := t.uuid_to_folder.keys()
	folder_uuids.sort(a < b)

	for folder_uuid in folder_uuids {
		fldr_proto := t.uuid_to_folder[folder_uuid]
		mut attrs_ids := fldr_proto.uuid_to_attribute.keys()
		attrs_ids.sort(a < b)

		mut fldr := PassManFolder{
			...fldr_proto
			uuid_to_attribute: map[string]PassManItemAttribute{}
		}

		for attr_id in attrs_ids {
			fldr.uuid_to_attribute[attr_id] = fldr_proto.uuid_to_attribute[attr_id]
		}

		result.uuid_to_folder[folder_uuid] = fldr
	}

	return result
}
