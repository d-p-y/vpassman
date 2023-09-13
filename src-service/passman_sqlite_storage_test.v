module main

import os
import passmanstate

const (
	uuid_v4len = 36 // https://en.wikipedia.org/wiki/Universally_unique_identifier
)

fn test_sqlite_storage_get_or_reuse_origin_works() ! {
	println('#-#-# start #-#-# test_sqlite_storage_get_or_reuse_origin_works()')

	mut storage := passmanstate.create_new_passmandbstorage(':memory:')!
	defer {
		storage.close() or { panic(err) }
	}

	origin := passmanstate.ChangeOrigin{
		computer_name: os.hostname()!
		user_name: os.loginname() or { os.getenv('LOGNAME') }
	}

	origin1 := storage.get_or_create_change_origin(origin)!
	$if debug {
		dump(origin1)
	}

	origin2 := storage.get_or_create_change_origin(origin)!
	$if debug {
		dump(origin2)
	}

	assert origin1.id == origin2.id
	assert 1 == storage.db.q_int('select count(*) from change_origin')!
}

fn test_sqlite_storage_change_aggregation_yields_expected_passmanstate() ! {
	println('#-#-# start #-#-# test_sqlite_storage_change_aggregation_yields_expected_passmanstate()')
	mut expected_changes_count := 0

	mut storage := passmanstate.create_new_passmandbstorage(':memory:')!
	defer {
		storage.close() or { panic(err) }
	}

	fldr1_insert := storage.create_folder('fname')!
	expected_changes_count++
	assert uuid_v4len == fldr1_insert.subject_uuid.len

	attr11_insert := storage.create_custom_attribute(fldr1_insert.subject_uuid, 'caname',
		'a@b.com')!
	expected_changes_count++
	assert uuid_v4len == attr11_insert.subject_uuid.len

	attr12_insert := storage.create_custom_attribute(fldr1_insert.subject_uuid, r'¥.€/$ąęП ЖДäüöß',
		r'¥€$ąęПЖДäüöß')!
	expected_changes_count++
	assert uuid_v4len == attr12_insert.subject_uuid.len

	fldr2_insert := storage.create_folder('fname2')!
	expected_changes_count++
	assert uuid_v4len == fldr2_insert.subject_uuid.len

	mut expected_state := passmanstate.PassManState{
		name: ''
		uuid_to_folder: {
			fldr1_insert.subject_uuid: passmanstate.PassManFolder{
				name: 'fname'
				uuid_to_attribute: {
					attr11_insert.subject_uuid: passmanstate.PassManItemAttribute{
						identifier: passmanstate.AttributeIdentifierCustom{'caname'}
						value: 'a@b.com'
					}
					attr12_insert.subject_uuid: passmanstate.PassManItemAttribute{
						identifier: passmanstate.AttributeIdentifierCustom{r'¥.€/$ąęП ЖДäüöß'}
						value: r'¥€$ąęПЖДäüöß'
					}
				}
			}
			fldr2_insert.subject_uuid: passmanstate.PassManFolder{
				name: 'fname2'
			}
		}
	}
	assert expected_changes_count == storage.db.q_int('select count(*) from change')!
	assert expected_state.cannonicalize() == storage.calculate_state()!.cannonicalize()

	expected_state = passmanstate.PassManState{
		name: ''
		uuid_to_folder: {
			fldr1_insert.subject_uuid: passmanstate.PassManFolder{
				name: 'new folder name'
				uuid_to_attribute: {
					attr11_insert.subject_uuid: passmanstate.PassManItemAttribute{
						identifier: passmanstate.AttributeIdentifierCustom{'caname'}
						value: 'a@b.com'
					}
					attr12_insert.subject_uuid: passmanstate.PassManItemAttribute{
						identifier: passmanstate.AttributeIdentifierCustom{r'¥.€/$ąęП ЖДäüöß'}
						value: r'¥€$ąęПЖДäüöß'
					}
				}
			}
			fldr2_insert.subject_uuid: passmanstate.PassManFolder{
				name: 'fname2'
			}
		}
	}
	storage.update_folder_property(fldr1_insert.subject_uuid, .name, expected_state)!
	expected_changes_count++
	assert expected_changes_count == storage.db.q_int('select count(*) from change')!
	assert expected_state.cannonicalize() == storage.calculate_state()!.cannonicalize()

	expected_state = passmanstate.PassManState{
		name: ''
		uuid_to_folder: {
			fldr1_insert.subject_uuid: passmanstate.PassManFolder{
				name: 'new folder name'
				uuid_to_attribute: {
					attr11_insert.subject_uuid: passmanstate.PassManItemAttribute{
						identifier: passmanstate.AttributeIdentifierCustom{'other name'}
						value: 'a@b.com'
					}
					attr12_insert.subject_uuid: passmanstate.PassManItemAttribute{
						identifier: passmanstate.AttributeIdentifierCustom{r'¥.€/$ąęП ЖДäüöß'}
						value: r'¥€$ąęПЖДäüöß'
					}
				}
			}
			fldr2_insert.subject_uuid: passmanstate.PassManFolder{
				name: 'fname2'
			}
		}
	}
	storage.update_custom_attribute(attr11_insert.subject_uuid, .name, mut expected_state)!
	expected_changes_count++
	assert expected_changes_count == storage.db.q_int('select count(*) from change')!
	assert expected_state.cannonicalize() == storage.calculate_state()!.cannonicalize()

	expected_state = passmanstate.PassManState{
		name: ''
		uuid_to_folder: {
			fldr1_insert.subject_uuid: passmanstate.PassManFolder{
				name: 'new folder name'
				uuid_to_attribute: {
					attr11_insert.subject_uuid: passmanstate.PassManItemAttribute{
						identifier: passmanstate.AttributeIdentifierCustom{'other name'}
						value: 'other@value.com'
					}
					attr12_insert.subject_uuid: passmanstate.PassManItemAttribute{
						identifier: passmanstate.AttributeIdentifierCustom{r'¥.€/$ąęП ЖДäüöß'}
						value: r'¥€$ąęПЖДäüöß'
					}
				}
			}
			fldr2_insert.subject_uuid: passmanstate.PassManFolder{
				name: 'fname2'
			}
		}
	}
	storage.update_custom_attribute(attr11_insert.subject_uuid, .value, mut expected_state)!
	expected_changes_count++
	assert expected_changes_count == storage.db.q_int('select count(*) from change')!
	assert expected_state.cannonicalize() == storage.calculate_state()!.cannonicalize()

	attr21_insert := storage.create_standard_attribute(fldr2_insert.subject_uuid, .token,
		'12345')!
	expected_changes_count++
	assert uuid_v4len == attr12_insert.subject_uuid.len
	expected_state = passmanstate.PassManState{
		name: ''
		uuid_to_folder: {
			fldr1_insert.subject_uuid: passmanstate.PassManFolder{
				name: 'new folder name'
				uuid_to_attribute: {
					attr11_insert.subject_uuid: passmanstate.PassManItemAttribute{
						identifier: passmanstate.AttributeIdentifierCustom{'other name'}
						value: 'other@value.com'
					}
					attr12_insert.subject_uuid: passmanstate.PassManItemAttribute{
						identifier: passmanstate.AttributeIdentifierCustom{r'¥.€/$ąęП ЖДäüöß'}
						value: r'¥€$ąęПЖДäüöß'
					}
				}
			}
			fldr2_insert.subject_uuid: passmanstate.PassManFolder{
				name: 'fname2'
				uuid_to_attribute: {
					attr21_insert.subject_uuid: passmanstate.PassManItemAttribute{
						identifier: passmanstate.AttributeIdentifierStandard{
							identifier_kind: .token
						}
						value: '12345'
					}
				}
			}
		}
	}
	assert expected_changes_count == storage.db.q_int('select count(*) from change')!
	assert expected_state.cannonicalize() == storage.calculate_state()!.cannonicalize()

	expected_state = passmanstate.PassManState{
		name: ''
		uuid_to_folder: {
			fldr1_insert.subject_uuid: passmanstate.PassManFolder{
				name: 'new folder name'
				uuid_to_attribute: {
					attr11_insert.subject_uuid: passmanstate.PassManItemAttribute{
						identifier: passmanstate.AttributeIdentifierCustom{'other name'}
						value: 'other@value.com'
					}
					attr12_insert.subject_uuid: passmanstate.PassManItemAttribute{
						identifier: passmanstate.AttributeIdentifierCustom{r'¥.€/$ąęП ЖДäüöß'}
						value: r'¥€$ąęПЖДäüöß'
					}
				}
			}
			fldr2_insert.subject_uuid: passmanstate.PassManFolder{
				name: 'fname2'
				uuid_to_attribute: {
					attr21_insert.subject_uuid: passmanstate.PassManItemAttribute{
						identifier: passmanstate.AttributeIdentifierStandard{
							identifier_kind: .token
						}
						value: '54321'
					}
				}
			}
		}
	}
	storage.update_standard_attribute(attr21_insert.subject_uuid, mut expected_state)!
	expected_changes_count++
	assert expected_changes_count == storage.db.q_int('select count(*) from change')!
	assert expected_state.cannonicalize() == storage.calculate_state()!.cannonicalize()

	expected_state = passmanstate.PassManState{
		name: ''
		uuid_to_folder: {
			fldr1_insert.subject_uuid: passmanstate.PassManFolder{
				name: 'new folder name'
				uuid_to_attribute: {
					attr11_insert.subject_uuid: passmanstate.PassManItemAttribute{
						identifier: passmanstate.AttributeIdentifierCustom{'other name'}
						value: 'other@value.com'
					}
					attr12_insert.subject_uuid: passmanstate.PassManItemAttribute{
						identifier: passmanstate.AttributeIdentifierCustom{r'¥.€/$ąęП ЖДäüöß'}
						value: r'¥€$ąęПЖДäüöß'
					}
				}
			}
			fldr2_insert.subject_uuid: passmanstate.PassManFolder{
				name: 'fname2'
			}
		}
	}
	storage.delete_standard_attribute(attr21_insert.subject_uuid)!
	expected_changes_count++
	assert expected_changes_count == storage.db.q_int('select count(*) from change')!
	assert expected_state.cannonicalize() == storage.calculate_state()!.cannonicalize()

	expected_state = passmanstate.PassManState{
		name: ''
		uuid_to_folder: {
			fldr1_insert.subject_uuid: passmanstate.PassManFolder{
				name: 'new folder name'
				uuid_to_attribute: {
					attr12_insert.subject_uuid: passmanstate.PassManItemAttribute{
						identifier: passmanstate.AttributeIdentifierCustom{r'¥.€/$ąęП ЖДäüöß'}
						value: r'¥€$ąęПЖДäüöß'
					}
				}
			}
			fldr2_insert.subject_uuid: passmanstate.PassManFolder{
				name: 'fname2'
			}
		}
	}
	storage.delete_custom_attribute(attr11_insert.subject_uuid)!
	expected_changes_count++
	assert expected_changes_count == storage.db.q_int('select count(*) from change')!
	assert expected_state.cannonicalize() == storage.calculate_state()!.cannonicalize()

	expected_state = passmanstate.PassManState{
		name: ''
		uuid_to_folder: {
			fldr2_insert.subject_uuid: passmanstate.PassManFolder{
				name: 'fname2'
			}
		}
	}
	storage.delete_folder(fldr1_insert.subject_uuid)!
	expected_changes_count++
	assert expected_changes_count == storage.db.q_int('select count(*) from change')!
	assert expected_state.cannonicalize() == storage.calculate_state()!.cannonicalize()
}
