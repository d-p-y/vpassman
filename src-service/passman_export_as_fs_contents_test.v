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
	default_root_expect = RootDirExpectations{
		uid: 3333
		gid: 5555
		permissions: os_extensions.UnixFilePermissions{
			user_r: true
			user_x: true
		}
	}
)

fn testsuite_begin() ! {
	unmount_if_needed()!
}

fn testsuite_end() ! {
	unmount_if_needed()!
}

fn test_empty_passman_state_exports_expected_content() ! {
	println('#-#-# start #-#-# test_empty_passman_state_exports_expected_content()')

	pass_man_state := passmanstate.PassManState{
		name: 'empty'
	}
	perms := passmanstate.PassManExportSettings{
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

	expects := ExpectedFsEntry{
		name: 'secrets'
		uid: 3333
		gid: 5555
		permissions: os_extensions.new_permissions_from_octets('r-x------')!
		details: ExpectedFsDirEntry{
			children: [
				ExpectedFsEntry{
					name: 'by-name'
					uid: 3333
					gid: 5555
					permissions: os_extensions.new_permissions_from_octets('r-x------')!
					details: ExpectedFsDirEntry{
						children: []
					}
				},
				ExpectedFsEntry{
					name: 'by-url'
					uid: 3333
					gid: 5555
					permissions: os_extensions.new_permissions_from_octets('r-x------')!
					details: ExpectedFsDirEntry{
						children: []
					}
				},
			]
		}
	}

	base_test_mounting_passman_in_foreground_actually_exposes_requested_file(pass_man_state,
		perms, default_root_expect, expects)!
}

fn test_passman_state_empty_folders_are_exported() ! {
	println('#-#-# start #-#-# test_passman_state_empty_folders_are_exported()')

	pass_man_state := passmanstate.PassManState{
		name: 'complex example'
		uuid_to_folder: {
			// empty folder
			rand.uuid_v4(): passmanstate.PassManFolder{
				name: 'some empty folder'
			}
		}
	}

	perms := passmanstate.PassManExportSettings{
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

	expects := ExpectedFsEntry{
		name: 'secrets'
		uid: 3333
		gid: 5555
		permissions: os_extensions.new_permissions_from_octets('r-x------')!
		details: ExpectedFsDirEntry{
			children: [
				ExpectedFsEntry{
					name: 'by-name'
					uid: 3333
					gid: 5555
					permissions: os_extensions.new_permissions_from_octets('r-x------')!
					details: ExpectedFsDirEntry{
						children: [
							ExpectedFsEntry{
								name: 'some empty folder'
								uid: 3333
								gid: 5555
								permissions: os_extensions.new_permissions_from_octets('r-x------')!
								details: ExpectedFsDirEntry{
									children: []
								}
							},
						]
					}
				},
				ExpectedFsEntry{
					name: 'by-url'
					uid: 3333
					gid: 5555
					permissions: os_extensions.new_permissions_from_octets('r-x------')!
					details: ExpectedFsDirEntry{
						children: []
					}
				},
			]
		}
	}

	base_test_mounting_passman_in_foreground_actually_exposes_requested_file(pass_man_state,
		perms, default_root_expect, expects)!
}

fn test_passman_state_standard_and_custom_attributes_are_exported() ! {
	println('#-#-# start #-#-# test_passman_state_standard_and_custom_attributes_are_exported()')

	pass_man_state := passmanstate.PassManState{
		name: 'complex example'
		uuid_to_folder: {
			rand.uuid_v4(): passmanstate.PassManFolder{
				name: 'folder with attributes'
				uuid_to_attribute: {
					rand.uuid_v4(): passmanstate.PassManItemAttribute{
						identifier: passmanstate.AttributeIdentifierStandard{passmanstate.AttributeIdentifierKind.email}
						value: 'user@example.com'
					}
					rand.uuid_v4(): passmanstate.PassManItemAttribute{
						identifier: passmanstate.AttributeIdentifierCustom{'mobile phone number'}
						value: '+48 000 00 00'
					}
				}
			}
		}
	}

	perms := passmanstate.PassManExportSettings{
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

	expects := ExpectedFsEntry{
		name: 'secrets'
		uid: 3333
		gid: 5555
		permissions: os_extensions.new_permissions_from_octets('r-x------')!
		details: ExpectedFsDirEntry{
			children: [
				ExpectedFsEntry{
					name: 'by-name'
					uid: 3333
					gid: 5555
					permissions: os_extensions.new_permissions_from_octets('r-x------')!
					details: ExpectedFsDirEntry{
						children: [
							ExpectedFsEntry{
								name: 'folder with attributes'
								uid: 3333
								gid: 5555
								permissions: os_extensions.new_permissions_from_octets('r-x------')!
								details: ExpectedFsDirEntry{
									children: [
										ExpectedFsEntry{
											name: 'email'
											uid: 3333
											gid: 5555
											permissions: os_extensions.new_permissions_from_octets('r--------')!
											details: ExpectedFsFileEntry{
												content: 'user@example.com'
											}
										},
										ExpectedFsEntry{
											name: 'mobile phone number'
											uid: 3333
											gid: 5555
											permissions: os_extensions.new_permissions_from_octets('r--------')!
											details: ExpectedFsFileEntry{
												content: '+48 000 00 00'
											}
										},
									]
								}
							},
						]
					}
				},
				ExpectedFsEntry{
					name: 'by-url'
					uid: 3333
					gid: 5555
					permissions: os_extensions.new_permissions_from_octets('r-x------')!
					details: ExpectedFsDirEntry{
						children: []
					}
				},
			]
		}
	}

	base_test_mounting_passman_in_foreground_actually_exposes_requested_file(pass_man_state,
		perms, default_root_expect, expects)!
}

fn test_passman_state_urls_as_fs_entry_names_are_sanitized_during_export() ! {
	println('#-#-# start #-#-# test_passman_state_urls_as_fs_entry_names_are_sanitized_during_export()')

	pass_man_state := passmanstate.PassManState{
		name: 'complex example'
		uuid_to_folder: {
			rand.uuid_v4(): passmanstate.PassManFolder{
				name: 'folder with attributes'
				uuid_to_attribute: {
					rand.uuid_v4(): passmanstate.PassManItemAttribute{
						identifier: passmanstate.AttributeIdentifierCustom{'mobile phone number'}
						value: '+48 000 00 00'
					}
					rand.uuid_v4(): passmanstate.PassManItemAttribute{
						identifier: passmanstate.AttributeIdentifierStandard{passmanstate.AttributeIdentifierKind.url}
						value: 'http://example.com/foo'
					}
				}
			}
		}
	}

	perms := passmanstate.PassManExportSettings{
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

	expects := ExpectedFsEntry{
		name: 'secrets'
		uid: 3333
		gid: 5555
		permissions: os_extensions.new_permissions_from_octets('r-x------')!
		details: ExpectedFsDirEntry{
			children: [
				ExpectedFsEntry{
					name: 'by-name'
					uid: 3333
					gid: 5555
					permissions: os_extensions.new_permissions_from_octets('r-x------')!
					details: ExpectedFsDirEntry{
						children: [
							ExpectedFsEntry{
								name: 'folder with attributes'
								uid: 3333
								gid: 5555
								permissions: os_extensions.new_permissions_from_octets('r-x------')!
								details: ExpectedFsDirEntry{
									children: [
										ExpectedFsEntry{
											name: 'mobile phone number'
											uid: 3333
											gid: 5555
											permissions: os_extensions.new_permissions_from_octets('r--------')!
											details: ExpectedFsFileEntry{
												content: '+48 000 00 00'
											}
										},
										ExpectedFsEntry{
											name: 'url'
											uid: 3333
											gid: 5555
											permissions: os_extensions.new_permissions_from_octets('r--------')!
											details: ExpectedFsFileEntry{
												content: 'http://example.com/foo'
											}
										},
									]
								}
							},
						]
					}
				},
				ExpectedFsEntry{
					name: 'by-url'
					uid: 3333
					gid: 5555
					permissions: os_extensions.new_permissions_from_octets('r-x------')!
					details: ExpectedFsDirEntry{
						children: [
							ExpectedFsEntry{
								name: 'http:⁄⁄example.com⁄foo'
								uid: 3333
								gid: 5555
								permissions: os_extensions.new_permissions_from_octets('r-x------')!
								details: ExpectedFsDirEntry{
									children: [
										ExpectedFsEntry{
											name: 'mobile phone number'
											uid: 3333
											gid: 5555
											permissions: os_extensions.new_permissions_from_octets('r--------')!
											details: ExpectedFsFileEntry{
												content: '+48 000 00 00'
											}
										},
										ExpectedFsEntry{
											name: 'name'
											uid: 3333
											gid: 5555
											permissions: os_extensions.new_permissions_from_octets('r--------')!
											details: ExpectedFsFileEntry{
												content: 'folder with attributes'
											}
										},
										ExpectedFsEntry{
											name: 'url'
											uid: 3333
											gid: 5555
											permissions: os_extensions.new_permissions_from_octets('r--------')!
											details: ExpectedFsFileEntry{
												content: 'http://example.com/foo'
											}
										},
									]
								}
							},
						]
					}
				},
			]
		}
	}

	base_test_mounting_passman_in_foreground_actually_exposes_requested_file(pass_man_state,
		perms, default_root_expect, expects)!
}

fn test_passman_state_with_duplicated_names_exports_expected_content() ! {
	println('#-#-# start #-#-# test_passman_state_with_duplicated_names_exports_expected_content()')

	// order in duplicates: by uuid

	pass_man_state := passmanstate.PassManState{
		name: 'complex example'
		uuid_to_folder: {
			// one standard attribute folder
			'bbb': passmanstate.PassManFolder{
				name: 'duplicated name'
				uuid_to_attribute: {
					rand.uuid_v4(): passmanstate.PassManItemAttribute{
						identifier: passmanstate.AttributeIdentifierStandard{passmanstate.AttributeIdentifierKind.email}
						value: 'a@example.com'
					}
				}
			}
			// one custom attribute folder
			'aaa': passmanstate.PassManFolder{
				name: 'duplicated name'
				uuid_to_attribute: {
					rand.uuid_v4(): passmanstate.PassManItemAttribute{
						identifier: passmanstate.AttributeIdentifierCustom{'mobile phone number'}
						value: '+48 000 00 00'
					}
				}
			}
		}
	}

	perms := passmanstate.PassManExportSettings{
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

	expects := ExpectedFsEntry{
		name: 'secrets'
		uid: 3333
		gid: 5555
		permissions: os_extensions.new_permissions_from_octets('r-x------')!
		details: ExpectedFsDirEntry{
			children: [
				ExpectedFsEntry{
					name: 'by-name'
					uid: 3333
					gid: 5555
					permissions: os_extensions.new_permissions_from_octets('r-x------')!
					details: ExpectedFsDirEntry{
						children: [
							ExpectedFsEntry{
								name: 'duplicated name'
								uid: 3333
								gid: 5555
								permissions: os_extensions.new_permissions_from_octets('r-x------')!
								details: ExpectedFsDirEntry{
									children: [
										ExpectedFsEntry{
											name: 'mobile phone number'
											uid: 3333
											gid: 5555
											permissions: os_extensions.new_permissions_from_octets('r--------')!
											details: ExpectedFsFileEntry{
												content: '+48 000 00 00'
											}
										},
									]
								}
							},
							ExpectedFsEntry{
								name: 'duplicated name (2)'
								uid: 3333
								gid: 5555
								permissions: os_extensions.new_permissions_from_octets('r-x------')!
								details: ExpectedFsDirEntry{
									children: [
										ExpectedFsEntry{
											name: 'email'
											uid: 3333
											gid: 5555
											permissions: os_extensions.new_permissions_from_octets('r--------')!
											details: ExpectedFsFileEntry{
												content: 'a@example.com'
											}
										},
									]
								}
							},
						]
					}
				},
				ExpectedFsEntry{
					name: 'by-url'
					uid: 3333
					gid: 5555
					permissions: os_extensions.new_permissions_from_octets('r-x------')!
					details: ExpectedFsDirEntry{
						children: []
					}
				},
			]
		}
	}

	base_test_mounting_passman_in_foreground_actually_exposes_requested_file(pass_man_state,
		perms, default_root_expect, expects)!
}

fn test_passman_state_with_duplicated_urls_exports_expected_content() ! {
	println('#-#-# start #-#-# test_passman_state_with_duplicated_urls_exports_expected_content()')

	// order in duplicates: by uuid

	pass_man_state := passmanstate.PassManState{
		name: 'complex example'
		uuid_to_folder: {
			// one standard attribute folder
			'bbb': passmanstate.PassManFolder{
				name: 'something'
				uuid_to_attribute: {
					rand.uuid_v4(): passmanstate.PassManItemAttribute{
						identifier: passmanstate.AttributeIdentifierStandard{passmanstate.AttributeIdentifierKind.url}
						value: 'http://a.b.c'
					}
				}
			}
			// one custom attribute folder
			'aaa': passmanstate.PassManFolder{
				name: 'zzzz'
				uuid_to_attribute: {
					rand.uuid_v4(): passmanstate.PassManItemAttribute{
						identifier: passmanstate.AttributeIdentifierStandard{passmanstate.AttributeIdentifierKind.url}
						value: 'http://a.b.c'
					}
				}
			}
		}
	}

	perms := passmanstate.PassManExportSettings{
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

	expects := ExpectedFsEntry{
		name: 'secrets'
		uid: 3333
		gid: 5555
		permissions: os_extensions.new_permissions_from_octets('r-x------')!
		details: ExpectedFsDirEntry{
			children: [
				ExpectedFsEntry{
					name: 'by-name'
					uid: 3333
					gid: 5555
					permissions: os_extensions.new_permissions_from_octets('r-x------')!
					details: ExpectedFsDirEntry{
						children: [
							ExpectedFsEntry{
								name: 'something'
								uid: 3333
								gid: 5555
								permissions: os_extensions.new_permissions_from_octets('r-x------')!
								details: ExpectedFsDirEntry{
									children: [
										ExpectedFsEntry{
											name: 'url'
											uid: 3333
											gid: 5555
											permissions: os_extensions.new_permissions_from_octets('r--------')!
											details: ExpectedFsFileEntry{
												content: 'http://a.b.c'
											}
										},
									]
								}
							},
							ExpectedFsEntry{
								name: 'zzzz'
								uid: 3333
								gid: 5555
								permissions: os_extensions.new_permissions_from_octets('r-x------')!
								details: ExpectedFsDirEntry{
									children: [
										ExpectedFsEntry{
											name: 'url'
											uid: 3333
											gid: 5555
											permissions: os_extensions.new_permissions_from_octets('r--------')!
											details: ExpectedFsFileEntry{
												content: 'http://a.b.c'
											}
										},
									]
								}
							},
						]
					}
				},
				ExpectedFsEntry{
					name: 'by-url'
					uid: 3333
					gid: 5555
					permissions: os_extensions.new_permissions_from_octets('r-x------')!
					details: ExpectedFsDirEntry{
						children: [
							ExpectedFsEntry{
								name: 'http:⁄⁄a.b.c'
								uid: 3333
								gid: 5555
								permissions: os_extensions.new_permissions_from_octets('r-x------')!
								details: ExpectedFsDirEntry{
									children: [
										ExpectedFsEntry{
											name: 'name'
											uid: 3333
											gid: 5555
											permissions: os_extensions.new_permissions_from_octets('r--------')!
											details: ExpectedFsFileEntry{
												content: 'zzzz'
											}
										},
										ExpectedFsEntry{
											name: 'url'
											uid: 3333
											gid: 5555
											permissions: os_extensions.new_permissions_from_octets('r--------')!
											details: ExpectedFsFileEntry{
												content: 'http://a.b.c'
											}
										},
									]
								}
							},
							ExpectedFsEntry{
								name: 'http:⁄⁄a.b.c (2)'
								uid: 3333
								gid: 5555
								permissions: os_extensions.new_permissions_from_octets('r-x------')!
								details: ExpectedFsDirEntry{
									children: [
										ExpectedFsEntry{
											name: 'name'
											uid: 3333
											gid: 5555
											permissions: os_extensions.new_permissions_from_octets('r--------')!
											details: ExpectedFsFileEntry{
												content: 'something'
											}
										},
										ExpectedFsEntry{
											name: 'url'
											uid: 3333
											gid: 5555
											permissions: os_extensions.new_permissions_from_octets('r--------')!
											details: ExpectedFsFileEntry{
												content: 'http://a.b.c'
											}
										},
									]
								}
							},
						]
					}
				},
			]
		}
	}

	base_test_mounting_passman_in_foreground_actually_exposes_requested_file(pass_man_state,
		perms, default_root_expect, expects)!
}
