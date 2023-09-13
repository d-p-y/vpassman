import sqlite_memfd_vfs
import db.sqlite
import os

fn test_inmemoryvfs_actually_works() ! {
	default_vfs := sqlite.get_default_vfs() or { return error('could not get default vfs') }
	default_vfs_name := unsafe { cstring_to_vstring(default_vfs.zName).clone() }

	mut vfs := sqlite_memfd_vfs.create_memfdbasedvfs('myfs')!

	vfs.register_as_nondefault()!

	// normally this would be written to disk
	mut db := sqlite.connect_full('foo.db', [.readwrite, .create], vfs.name)!

	db.exec("create table users (id integer primary key, name text default '');")!
	db.exec("insert into users (name) values ('Sam')")!
	assert db.last_insert_rowid() > 0

	nr_users := db.q_int('select count(*) from users')!
	assert nr_users == 1

	db.close()!

	files := vfs.get_files()!

	assert files.len == 1

	// TODO find temp dir
	tmp_path := '/tmp/blah.db'
	os.write_file(tmp_path, files.values()[0])!
	mut db2 := sqlite.connect_full(tmp_path, [.readwrite, .create], default_vfs_name)!

	nr_users2 := db2.q_int('select count(*) from users')!
	assert nr_users2 == 1

	db2.close()!

	os.rm(tmp_path)!

	// TODO vfs.unregister()! causes some memory problem
}

fn test_inmemoryvfs_rejects_request_to_open_nonexisting_db() ! {
	default_vfs := sqlite.get_default_vfs() or { return error('could not get default vfs') }
	default_vfs_name := unsafe { cstring_to_vstring(default_vfs.zName).clone() }

	mut vfs := sqlite_memfd_vfs.create_memfdbasedvfs('myfs')!

	vfs.register_as_nondefault()!

	// normally this would be written to disk
	_ := sqlite.connect_full('foo.db', [.readwrite], vfs.name) or {
		assert err.msg().contains('unable to open database file')

		return
	}
	panic('expected opening to fail due to unknown db')

	// TODO vfs.unregister()!
}
