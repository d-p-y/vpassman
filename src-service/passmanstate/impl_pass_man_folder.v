module passmanstate

fn (f &PassManFolder) maybe_get_url() ?string {
	for _, attr in f.uuid_to_attribute {
		if attr.identifier is AttributeIdentifierStandard {
			if attr.identifier.identifier_kind == .url {
				return attr.value
			}
		}
	}
	return none
}

fn (t AttributeIdentifierKind) label_to_string() string {
	return match t {
		.url { 'url' }
		.email { 'email' }
		.password { 'password' }
		.connection_string { 'connection_string' }
		.token { 'token' }
		.username { 'username' }
		.login { 'login' }
		.note { 'note' }
	}
}

fn (f &PassManFolder) build_site_folder(perms PassManExportSettings, include_name bool) &Dir {
	mut result := []&FileSystemItem{}

	for _, attr in f.uuid_to_attribute {
		name := match attr.identifier {
			AttributeIdentifierCustom {
				attr.identifier.attribute_name
			}
			AttributeIdentifierStandard {
				attr.identifier.identifier_kind.label_to_string()
			}
		}

		result << &FileSystemItem{
			name: sanitize_slashes(name)
			uid: perms.uid
			gid: perms.gid
			permissions: perms.file
			details: &File{
				content: attr.value
			}
			origin: f
		}
	}

	if include_name {
		result << &FileSystemItem{
			name: 'name'
			uid: perms.uid
			gid: perms.gid
			permissions: perms.file
			details: &File{
				content: f.name
			}
			origin: f
		}
	}

	return &Dir{
		children: result
	}
}

fn (f &PassManFolder) build_site_folder_with_extra_name_entry(perms PassManExportSettings) &Dir {
	return f.build_site_folder(perms, true)
}

fn (f &PassManFolder) build_site_folder_without_extra_name_entry(perms PassManExportSettings) &Dir {
	return f.build_site_folder(perms, false)
}

pub fn (t PassManFolder) get_field_value_as_string(field FolderField) !string {
	match field {
		.name {
			return t.name
		}
		else {
			return error('get_json_field_value: not implemented yet ${field}')
		}
	}
}

pub fn (mut t PassManFolder) set_field_value_from_string(field FolderField, value string) ! {
	match field {
		.name {
			t.name = value
		}
		else {
			return error('set_field_value_from_string: not implemented yet ${field}')
		}
	}
}
