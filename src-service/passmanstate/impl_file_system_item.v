module passmanstate

import fuse

fn (t FileSystemItem) is_related_to_passman_folder() bool {
	unsafe {
		return t.origin != 0
	}
}

pub fn (t FileSystemItem) passman_folder_name_or_empty() string {
	unsafe {
		if t.origin == 0 {
			return ''
		}
		return t.origin.name
	}
}

fn (t FileSystemItem) get_origin() ?&PassManFolder {
	unsafe {
		return if t.origin != 0 { t.origin } else { none }
	}
}

fn (t &FileSystemItem) maybe_get_child_by_name(needed_name string) ?&FileSystemItem {
	match t.details {
		Dir {
			for _, item in t.details.children {
				// println("considering dir's child")

				if item.name == needed_name {
					// println("maybe_get_child_by_name found")
					return item
				}
			}
			// println("maybe_get_child_by_name not found")
			return none
		}
		else {
			// println("is not dir so doesn't have child")
			return none
		}
	}
}

fn (t &FileSystemItem) find_item(path_components []string) ?&FileSystemItem {
	$if debug {
		println('find_item invoked path=${path_components} and self=${t.name}')
	}

	assert path_components.len > 0

	$if debug {
		dump(path_components)
	}

	match path_components.len {
		1 {
			match path_components[0] {
				'' {
					$if debug {
						println("find_item won't recure as 'self' was asked")
					}
					return t
				}
				else {
					if res := t.maybe_get_child_by_name(path_components[0]) {
						$if debug {
							println('find_item found child')
						}
						return res
					} else {
						$if debug {
							println("find_item didn't find child")
						}
						return none
					}
				}
			}
		}
		else {
			needed_name := path_components[0]

			if found := t.maybe_get_child_by_name(needed_name) {
				$if debug {
					println('find_item will recure')
				}
				return found.find_item(path_components[1..])
			} else {
				$if debug {
					println("find_item won't recure")
				}
				return none
			}
		}
	}
}

fn (t &FileSystemItem) get_path_info(path string) ?&FileSystemItem {
	path_components := path.split('/')

	// println('get_path_info START for path=$path')

	assert path_components.len >= 2
	assert path_components[0] == ''

	if found := t.find_item(path_components[1..]) {
		// println("get_path_info END find_item found")

		return found
	} else {
		// println("get_path_info END didn't find item")
		return none
	}
}

fn (t &FileSystemItem) get_file(path string) !(&FileSystemItem, &File) {
	item := t.get_path_info(path) or {
		return error('could not find filesystemitem having path=${path}')
	}

	return match item.details {
		File { item, &item.details }
		else { error('get_file() not a file path=${path}') }
	}
}

fn (t &FileSystemItem) list_path(path string) !(&FileSystemItem, &Dir) {
	path_components := path.split('/')

	// println('list_path START for path=$path')
	// dump(path_components)

	assert path_components.len >= 2
	assert path_components[0] == ''

	if found := t.find_item(path_components[1..]) {
		match found.details {
			Dir {
				// println("list_path END find_item found dir")
				return found, &found.details
			}
			else {
				// println("list_path END find_item is file so 'not found'")
				return error('list_path() not a dir path=${path}')
			}
		}
	} else {
		// println("list_path END didn't find item")
		return error('could not find filesystemitem having path=${path}')
	}
}

pub fn (t &FileSystemItem) wire_root_dir_to_fuse(mut fuse_state fuse.FuseState) &PassManStateWiredToFuse {
	result := &PassManStateWiredToFuse{
		passman: &PassManState{
			name: 'fake'
		}
		root: t
		settings: PassManExportSettings{}
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
