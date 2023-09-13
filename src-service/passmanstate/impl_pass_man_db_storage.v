module passmanstate

import model
import db.sqlite
import os
import time
import rand

const (
	db_schema_v1 = [
		'create table change_origin(
			id integer not null constraint change_origin_pk primary key autoincrement,
			computer_name text not null,
			user_name text not null);',
		'create table change(
			id integer,			
			utc_when integer not null,
			origin_id integer not null,
			type_insert_update_delete integer not null,
			subject_type_folder_stdattr_custattr_attachment integer not null,
			subject_subtype_for_ins_upd text null,
			subject_uuid text not null,
			parent_folder_uuid_for_ins_attr text null,
			subject_value_for_ins_upd text null,
			constraint change_pk unique (utc_when, origin_id));',
		'create table vpassman_v1(irrelevant integer);',
	]
)

pub fn (mut t PassManDbStorage) close() ! {
	t.db.close()!
}

fn get_or_create_change_origin(db sqlite.DB, origin ChangeOrigin) !ChangeOrigin {
	assert origin.computer_name.len > 0
	assert origin.user_name.len > 0

	origins := sql db {
		select from ChangeOrigin where computer_name == origin.computer_name
		&& user_name == origin.user_name
	}!

	$if debug {
		dump(origins)
	}

	match origins.len {
		0 {
			sql db {
				insert origin into ChangeOrigin
			}!
			if db.get_affected_rows_count() != 1 {
				return error('insert into ChangeOrigin failed')
			}

			id := db.last_id() as int
			result := ChangeOrigin{
				...origin
				id: id
			}

			$if debug {
				dump(result)
			}
			return result
		}
		1 {
			return origins[0]
		}
		else {
			return error('expected zero or one origin but have ${origins.len}')
		}
	}
}

pub fn create_new_passmandbstorage(db_name string) !PassManDbStorage {
	default_vfs := sqlite.get_default_vfs() or { return error('could not get default vfs') }
	default_vfs_name := unsafe { cstring_to_vstring(default_vfs.zName).clone() }

	mut conn := sqlite.connect_full(db_name, [sqlite.OpenModeFlag.create, sqlite.OpenModeFlag.readwrite],
		default_vfs_name)!

	for query in passmanstate.db_schema_v1 {
		_ := conn.exec(query)!
	}

	result := sql conn {
		select from Change order by utc_when desc limit 2
	}!

	$if debug {
		dump(result)
	}

	last_unix_time_milli := match result.len {
		0 { u64(0) }
		else { result[0].utc_when }
	}

	return PassManDbStorage{
		db: conn
		last_unix_time_milli: last_unix_time_milli
	}
}

pub fn (mut t PassManDbStorage) get_or_create_change_origin(origin ChangeOrigin) !ChangeOrigin {
	return get_or_create_change_origin(t.db, origin)
}

fn (mut t PassManDbStorage) get_or_create_current_origin() !ChangeOrigin {
	origin := ChangeOrigin{
		computer_name: os.hostname()!
		user_name: os.loginname() or { os.getenv('LOGNAME') }
	}

	return get_or_create_change_origin(t.db, origin)
}

fn (mut t PassManDbStorage) insert_change(chng Change) !Change {
	$if debug {
		println('starting insert_change')
	}
	$if debug {
		dump(chng)
	}

	mut failed := false
	mut e := ''

	sql t.db {
		insert chng into Change
	} or {
		failed = true
		e = err.msg()
	}

	if failed {
		return error('insert into Change failed error=${e}')
	}

	if t.db.get_affected_rows_count() != 1 {
		return error('insert into Change failed affected_rows is not 1')
	}

	if chng.subject_value_for_ins_upd.len == 0 {
		// inserted null instead of empty string
		t.db.exec('update change set subject_value_for_ins_upd = null where utc_when = ${chng.utc_when} and origin_id=${chng.origin_id};')! // NOTE: no sql injection, both are numbers
		assert 1 == t.db.get_affected_rows_count()
	}

	return chng
}

fn (mut t PassManDbStorage) get_unique_growing_utc_now_milli() u64 {
	mut result := u64(time.utc().unix_time_milli())

	if result <= t.last_unix_time_milli {
		result = t.last_unix_time_milli + 1
		t.last_unix_time_milli = result
		return result
	}

	t.last_unix_time_milli = result
	return result
}

pub fn (mut t PassManDbStorage) create_folder(folder_name string) !Change {
	assert folder_name.len > 0

	chng := Change{
		utc_when: t.get_unique_growing_utc_now_milli()
		origin_id: t.get_or_create_current_origin()!.id // TODO calculate once and keep in this
		type_insert_update_delete: u8(InsertUpdateDelete.insert)
		subject_type_folder_stdattr_custattr_attachment: u8(SubjectType.folder)
		// subject_subtype_for_ins_upd:""
		subject_uuid: rand.uuid_v4()
		// parent_folder_uuid_for_ins_attr:""
		subject_value_for_ins_upd: folder_name
	}

	t.insert_change(chng)!
	return chng
}

fn (mut t PassManDbStorage) is_known_folder_ident(folder_ident string) !bool {
	all := sql t.db {
		select from Change
	}!
	// TODO process inserts and deletes in right order to drop removed items

	$if debug {
		dump(all)
	}

	ty := u8(InsertUpdateDelete.insert)
	st := u8(SubjectType.folder)

	result := sql t.db {
		select from Change where type_insert_update_delete == ty
		&& subject_type_folder_stdattr_custattr_attachment == st && subject_uuid == folder_ident
	}!

	match result.len {
		1 { return true }
		0 { return false }
		else { return error('expected zero or 1 records but got ${result.len}') }
	}
}

fn (mut t PassManDbStorage) is_known_custom_attribute_ident(custom_attr_ident string) !bool {
	// TODO process inserts and deletes in right order to drop removed items
	all := sql t.db {
		select from Change
	}!

	$if debug {
		dump(all)
	}

	ty := u8(InsertUpdateDelete.insert)
	st := u8(SubjectType.custom_attribute)

	result := sql t.db {
		select from Change where type_insert_update_delete == ty
		&& subject_type_folder_stdattr_custattr_attachment == st
		&& subject_uuid == custom_attr_ident
	}!

	match result.len {
		1 { return true }
		0 { return false }
		else { return error('expected zero or 1 records but got ${result.len}') }
	}
}

fn (mut t PassManDbStorage) is_known_standard_attribute_ident(standard_attr_ident string) !bool {
	// TODO process inserts and deletes in right order to drop removed items
	all := sql t.db {
		select from Change
	}!

	$if debug {
		dump(all)
	}

	ty := u8(InsertUpdateDelete.insert)
	st := u8(SubjectType.standard_attribute)

	result := sql t.db {
		select from Change where type_insert_update_delete == ty
		&& subject_type_folder_stdattr_custattr_attachment == st
		&& subject_uuid == standard_attr_ident
	}!

	match result.len {
		1 { return true }
		0 { return false }
		else { return error('expected zero or 1 records but got ${result.len}') }
	}
}

pub fn (mut t PassManDbStorage) create_custom_attribute(folder_ident string, name string, value string) !Change {
	assert folder_ident.len > 0
	assert t.is_known_folder_ident(folder_ident)!

	chng := Change{
		utc_when: t.get_unique_growing_utc_now_milli()
		origin_id: t.get_or_create_current_origin()!.id // TODO calculate once and keep in this
		type_insert_update_delete: u8(InsertUpdateDelete.insert)
		subject_type_folder_stdattr_custattr_attachment: u8(SubjectType.custom_attribute)
		subject_subtype_for_ins_upd: name
		subject_uuid: rand.uuid_v4()
		parent_folder_uuid_for_ins_attr: folder_ident
		subject_value_for_ins_upd: value
	}

	t.insert_change(chng)!
	return chng
}

pub fn (mut t PassManDbStorage) create_standard_attribute(folder_ident string, attr_type AttributeIdentifierKind, value string) !Change {
	assert folder_ident.len > 0
	assert t.is_known_folder_ident(folder_ident)!

	chng := Change{
		utc_when: t.get_unique_growing_utc_now_milli()
		origin_id: t.get_or_create_current_origin()!.id // TODO calculate once and keep in this
		type_insert_update_delete: u8(InsertUpdateDelete.insert)
		subject_type_folder_stdattr_custattr_attachment: u8(SubjectType.standard_attribute)
		subject_subtype_for_ins_upd: '${u8(attr_type)}'
		subject_uuid: rand.uuid_v4()
		parent_folder_uuid_for_ins_attr: folder_ident
		subject_value_for_ins_upd: value
	}

	t.insert_change(chng)!
	return chng
}

pub fn (mut t PassManDbStorage) update_folder_property(folder_ident string, field FolderField, src PassManState) !Change {
	assert folder_ident.len > 0
	assert t.is_known_folder_ident(folder_ident)!
	assert folder_ident in src.uuid_to_folder

	chng := Change{
		utc_when: t.get_unique_growing_utc_now_milli()
		origin_id: t.get_or_create_current_origin()!.id // TODO calculate once and keep in this
		type_insert_update_delete: u8(InsertUpdateDelete.update)
		subject_type_folder_stdattr_custattr_attachment: u8(SubjectType.folder)
		subject_subtype_for_ins_upd: '${u8(field)}'
		subject_uuid: folder_ident
		// parent_folder_uuid_for_ins_attr:
		subject_value_for_ins_upd: src.uuid_to_folder[folder_ident].get_field_value_as_string(field)!
	}

	t.insert_change(chng)!

	return chng
}

pub fn (mut t PassManDbStorage) delete_folder(folder_ident string) !Change {
	assert folder_ident.len > 0
	assert t.is_known_folder_ident(folder_ident)!

	chng := Change{
		utc_when: t.get_unique_growing_utc_now_milli()
		origin_id: t.get_or_create_current_origin()!.id // TODO calculate once and keep in this
		type_insert_update_delete: u8(InsertUpdateDelete.delete)
		subject_type_folder_stdattr_custattr_attachment: u8(SubjectType.folder)
		// subject_subtype_for_ins_upd:
		subject_uuid: folder_ident
		// parent_folder_uuid_for_ins_attr:
		// subject_value_for_ins_upd:
	}

	t.insert_change(chng)!

	return chng
}

pub fn (mut t PassManDbStorage) update_custom_attribute(custom_attr_ident string, field CustomAttrField, mut src PassManState) !Change {
	assert custom_attr_ident.len > 0
	assert t.is_known_custom_attribute_ident(custom_attr_ident)!

	chng := Change{
		utc_when: t.get_unique_growing_utc_now_milli()
		origin_id: t.get_or_create_current_origin()!.id // TODO calculate once and keep in this
		type_insert_update_delete: u8(InsertUpdateDelete.update)
		subject_type_folder_stdattr_custattr_attachment: u8(SubjectType.custom_attribute)
		subject_subtype_for_ins_upd: '${u8(field)}'
		subject_uuid: custom_attr_ident
		// parent_folder_uuid_for_ins_attr:
		subject_value_for_ins_upd: src.process_attribute_by_uuid[string](custom_attr_ident,
			fn [field] (mut fldr PassManFolder, mut attr PassManItemAttribute) !string {
			return attr.get_field_value_as_string(field)
		})!
	}

	t.insert_change(chng)!

	return chng
}

pub fn (mut t PassManDbStorage) update_standard_attribute(standard_attr_ident string, mut src PassManState) !Change {
	assert standard_attr_ident.len > 0
	assert t.is_known_standard_attribute_ident(standard_attr_ident)!

	chng := Change{
		utc_when: t.get_unique_growing_utc_now_milli()
		origin_id: t.get_or_create_current_origin()!.id // TODO calculate once and keep in this
		type_insert_update_delete: u8(InsertUpdateDelete.update)
		subject_type_folder_stdattr_custattr_attachment: u8(SubjectType.standard_attribute)
		// subject_subtype_for_ins_upd:
		subject_uuid: standard_attr_ident
		// parent_folder_uuid_for_ins_attr:
		subject_value_for_ins_upd: src.process_attribute_by_uuid[string](standard_attr_ident,
			fn (mut fldr PassManFolder, mut attr PassManItemAttribute) !string {
			return attr.get_field_value_as_string(.value)
		})!
	}

	t.insert_change(chng)!

	return chng
}

pub fn (mut t PassManDbStorage) delete_custom_attribute(custom_attr_ident string) !Change {
	assert custom_attr_ident.len > 0
	assert t.is_known_custom_attribute_ident(custom_attr_ident)!

	chng := Change{
		utc_when: t.get_unique_growing_utc_now_milli()
		origin_id: t.get_or_create_current_origin()!.id // TODO calculate once and keep in this
		type_insert_update_delete: u8(InsertUpdateDelete.delete)
		subject_type_folder_stdattr_custattr_attachment: u8(SubjectType.custom_attribute)
		// subject_subtype_for_ins_upd:
		subject_uuid: custom_attr_ident
		// parent_folder_uuid_for_ins_attr:
		// subject_value_for_ins_upd:
	}

	t.insert_change(chng)!

	return chng
}

pub fn (mut t PassManDbStorage) delete_standard_attribute(standard_attr_ident string) !Change {
	assert standard_attr_ident.len > 0
	assert t.is_known_standard_attribute_ident(standard_attr_ident)!

	chng := Change{
		utc_when: t.get_unique_growing_utc_now_milli()
		origin_id: t.get_or_create_current_origin()!.id // TODO calculate once and keep in this
		type_insert_update_delete: u8(InsertUpdateDelete.delete)
		subject_type_folder_stdattr_custattr_attachment: u8(SubjectType.standard_attribute)
		// subject_subtype_for_ins_upd:
		subject_uuid: standard_attr_ident
		// parent_folder_uuid_for_ins_attr:
		// subject_value_for_ins_upd:
	}

	t.insert_change(chng)!

	return chng
}

pub fn (t PassManDbStorage) calculate_state() !PassManState {
	mut result := PassManState{}

	mut all := sql t.db {
		select from Change
	}!

	all.sort_with_compare(fn (a &Change, b &Change) int {
		if a.utc_when < b.utc_when {
			return -1
		}

		if a.utc_when > b.utc_when {
			return 1
		}

		if a.origin_id < b.origin_id {
			return -1
		}

		if a.origin_id > b.origin_id {
			return 1
		}

		panic('same rows comparison?')
	})

	$if debug {
		dump(all)
	}

	for chng in all {
		subject_type := unsafe { SubjectType(chng.subject_type_folder_stdattr_custattr_attachment) }
		ins_upd_del := unsafe { InsertUpdateDelete(chng.type_insert_update_delete) }

		match subject_type {
			.folder {
				match ins_upd_del {
					.insert {
						assert chng.subject_uuid !in result.uuid_to_folder

						result.uuid_to_folder[chng.subject_uuid] = PassManFolder{
							name: chng.subject_value_for_ins_upd
						}
					}
					.update {
						assert chng.subject_uuid in result.uuid_to_folder
						assert chng.subject_subtype_for_ins_upd.len > 0

						field_id_raw := chng.subject_subtype_for_ins_upd.parse_uint(10,
							8)!
						field_id := unsafe { FolderField(field_id_raw) }
						str_val := chng.subject_value_for_ins_upd

						result.process_folder_by_uuid(chng.subject_uuid, fn [field_id, str_val] (mut fldr PassManFolder) ! {
							fldr.set_field_value_from_string(field_id, str_val)!
						})!
					}
					.delete {
						assert chng.subject_uuid in result.uuid_to_folder

						result.uuid_to_folder.delete(chng.subject_uuid)
					}
				}
			}
			.custom_attribute {
				match ins_upd_del {
					.insert {
						assert chng.parent_folder_uuid_for_ins_attr in result.uuid_to_folder
						assert chng.subject_uuid !in result.uuid_to_folder[chng.parent_folder_uuid_for_ins_attr].uuid_to_attribute

						result.uuid_to_folder[chng.parent_folder_uuid_for_ins_attr].uuid_to_attribute[chng.subject_uuid] = PassManItemAttribute{
							identifier: AttributeIdentifierCustom{
								attribute_name: chng.subject_subtype_for_ins_upd
							}
							value: chng.subject_value_for_ins_upd
						}
					}
					.update {
						assert chng.subject_uuid.len > 0
						assert chng.subject_subtype_for_ins_upd.len > 0
						str_val := chng.subject_value_for_ins_upd

						field_id_raw := chng.subject_subtype_for_ins_upd.parse_uint(10,
							8)!
						field_id := unsafe { CustomAttrField(field_id_raw) }

						result.process_attribute_by_uuid[model.Unit](chng.subject_uuid,
							fn [field_id, str_val] (mut fldr PassManFolder, mut attr PassManItemAttribute) !model.Unit {
							assert attr.identifier is AttributeIdentifierCustom

							attr.set_field_value_from_string(field_id, str_val)!
							return model.unit
						})!
					}
					.delete {
						assert chng.subject_uuid.len > 0
						subject_id := chng.subject_uuid

						result.process_attribute_by_uuid[model.Unit](chng.subject_uuid,
							fn [subject_id] (mut fldr PassManFolder, mut attr PassManItemAttribute) !model.Unit {
							assert attr.identifier is AttributeIdentifierCustom

							fldr.uuid_to_attribute.delete(subject_id)
							return model.unit
						})!
					}
				}
			}
			.standard_attribute {
				match ins_upd_del {
					.insert {
						assert chng.parent_folder_uuid_for_ins_attr in result.uuid_to_folder
						assert chng.subject_uuid !in result.uuid_to_folder[chng.parent_folder_uuid_for_ins_attr].uuid_to_attribute

						ident_kind_raw := chng.subject_subtype_for_ins_upd.parse_uint(10,
							8)!
						ident_kind := unsafe { AttributeIdentifierKind(ident_kind_raw) }

						result.uuid_to_folder[chng.parent_folder_uuid_for_ins_attr].uuid_to_attribute[chng.subject_uuid] = PassManItemAttribute{
							identifier: AttributeIdentifierStandard{
								identifier_kind: ident_kind
							}
							value: chng.subject_value_for_ins_upd
						}
					}
					.update {
						assert chng.subject_uuid.len > 0
						str_val := chng.subject_value_for_ins_upd

						result.process_attribute_by_uuid[model.Unit](chng.subject_uuid,
							fn [str_val] (mut _ PassManFolder, mut attr PassManItemAttribute) !model.Unit {
							assert attr.identifier is AttributeIdentifierStandard

							attr.set_field_value_from_string(.value, str_val)!
							return model.unit
						})!
					}
					.delete {
						assert chng.subject_uuid.len > 0
						subject_id := chng.subject_uuid

						result.process_attribute_by_uuid[model.Unit](chng.subject_uuid,
							fn [subject_id] (mut fldr PassManFolder, mut attr PassManItemAttribute) !model.Unit {
							assert attr.identifier is AttributeIdentifierStandard
							fldr.uuid_to_attribute.delete(subject_id)
							return model.unit
						})!
					}
				}
			}
			// TODO .attachment
			else {
				panic('unsupported subject_type_folder_stdattr_custattr_attachment')
			}
		}
	}

	return result
}
