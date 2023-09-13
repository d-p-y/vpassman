module sqlite_memfd_vfs

import db.sqlite
import rand
import os

const (
	max_file_name_len     = 256

	// https://www2.sqlite.org/c3ref/constlist.html
	sqlite_open_exclusive = 0x00000010
	sqlite_open_create    = 0x00000004
	sqlite_open_readonly  = 0x00000001
	sqlite_open_readwrite = 0x00000002
)

[heap]
struct FileNameAndOpenFd {
	name string
	fd   int
}

[heap]
pub struct MemFdBasedVfs {
mut:
	base sqlite.Sqlite3_vfs
pub:
	name string
pub mut:
	known_sqlfiles map[int]FileNameAndOpenFd // sqlite_open_* to extra fopen() result
}

struct SqliteVfsFileType {
	type_as_flag int
}

struct MemFdOpenedFile {
mut:
	base      sqlite.Sqlite3_file
	fd        int
	file_type SqliteVfsFileType
	file_name string
	parent    &MemFdBasedVfs
}

struct OpenFlagsSimplified {
mut:
	can_be_created bool
	must_exist     bool
}

// note that O_EXCL is not really used https://mijailovic.net/2017/08/27/sqlite-adventures/
fn get_sqlite_open_flags_as_os_open_flags(inp_flags int) OpenFlagsSimplified {
	mut result := OpenFlagsSimplified{}

	if inp_flags & sqlite_memfd_vfs.sqlite_open_create != 0 {
		result.can_be_created = true
	}

	if inp_flags & sqlite_memfd_vfs.sqlite_open_readonly != 0 {
		result.must_exist = true
	}

	if inp_flags & sqlite_memfd_vfs.sqlite_open_readwrite != 0 {
		result.must_exist = true
	}

	return result
}

fn get_sqliteopentype_of_typefromxopenflag(type_from_xopen_flag int) !SqliteVfsFileType {
	if type_from_xopen_flag & sqlite.sqlite_open_main_db != 0 {
		return SqliteVfsFileType{sqlite.sqlite_open_main_db}
	}
	if type_from_xopen_flag & sqlite.sqlite_open_temp_db != 0 {
		return SqliteVfsFileType{sqlite.sqlite_open_temp_db}
	}
	if type_from_xopen_flag & sqlite.sqlite_open_transient_db != 0 {
		return SqliteVfsFileType{sqlite.sqlite_open_transient_db}
	}
	if type_from_xopen_flag & sqlite.sqlite_open_main_journal != 0 {
		return SqliteVfsFileType{sqlite.sqlite_open_main_journal}
	}
	if type_from_xopen_flag & sqlite.sqlite_open_temp_journal != 0 {
		return SqliteVfsFileType{sqlite.sqlite_open_temp_journal}
	}
	if type_from_xopen_flag & sqlite.sqlite_open_subjournal != 0 {
		return SqliteVfsFileType{sqlite.sqlite_open_subjournal}
	}
	if type_from_xopen_flag & sqlite.sqlite_open_super_journal != 0 {
		return SqliteVfsFileType{sqlite.sqlite_open_super_journal}
	}
	if type_from_xopen_flag & sqlite.sqlite_open_wal != 0 {
		return SqliteVfsFileType{sqlite.sqlite_open_wal}
	}

	return error('could not identify sqlite_open_* type from flag ${type_from_xopen_flag:x}')
}

fn (mut t MemFdBasedVfs) preserve_file_if_needed(f &MemFdOpenedFile, mode OpenFlagsSimplified) ! {
	$if debug {
		println('preserve_file_if_needed()')
	}

	assert f.fd >= 0

	$if debug {
		println('type_as_flag=${f.file_type} mode=${mode}')
	}

	$if debug {
		println('known files before mutation')
		dump(t.known_sqlfiles)
	}

	if _ := t.known_sqlfiles[f.file_type.type_as_flag] {
		$if debug {
			println('already preserved name=${f.file_name}')
		}
	} else {
		$if debug {
			println('preserving')
		}

		if mode.must_exist && !mode.can_be_created {
			return error('failed because sqlite requested to open existing db')
		}

		expected_location := '/proc/self/fd/${f.fd}'
		preserved_fd := C.open(expected_location.str, 0, os.o_rdonly) // don't create

		if preserved_fd < 0 {
			return error('open() failed for path=${expected_location}')
		}

		t.known_sqlfiles[f.file_type.type_as_flag] = &FileNameAndOpenFd{
			name: f.file_name
			fd: preserved_fd
		}
	}

	$if debug {
		println('known files after mutation')
		dump(t.known_sqlfiles)
	}
}

fn (mut t MemFdBasedVfs) forget_file(filename string) ! {
	$if debug {
		println('forget_file() filename=${filename}')
	}

	$if debug {
		println('known files before mutation')
		dump(t.known_sqlfiles)
	}

	mut found := false

	for k, v in t.known_sqlfiles {
		if v.name == filename {
			$if debug {
				println('file known, forgetting it')
			}

			res := C.close(v.fd)

			if res != 0 {
				return error('close(${v.fd}) failed')
			}
			t.known_sqlfiles.delete(k)
			found = true
			break
		}
	}

	if !found {
		$if debug {
			println('file not known')
		}
		return error('file ${filename} is not known')
	}

	$if debug {
		println('known files after mutation')
		dump(t.known_sqlfiles)
	}
}

fn (mut t MemFdBasedVfs) has_file(name string) bool {
	$if debug {
		println('has_file() name=${name}')
	}

	$if debug {
		println('known files')
		dump(t.known_sqlfiles)
	}

	for _, v in t.known_sqlfiles {
		if v.name == name {
			$if debug {
				println('has_file knows it')
			}
			return true
		}
	}

	$if debug {
		println("has_file doesn't know it")
	}
	return false
}

fn to_vfs(t &sqlite.Sqlite3_vfs) &MemFdBasedVfs {
	unsafe {
		p := t.pAppData
		assert 0 != p
		return &MemFdBasedVfs(p)
	}
}

fn to_file(t &sqlite.Sqlite3_file) &MemFdOpenedFile {
	unsafe {
		assert 0 != t
		return &MemFdOpenedFile(t)
	}
}

fn memfd_vfs_open(raw_vfs &sqlite.Sqlite3_vfs, file_name_or_null_for_tempfile &char, vfs_opened_file &sqlite.Sqlite3_file, in_flags int, out_flags &int) int {
	$if debug {
		println('memfd_vfs_open()')
	}

	mut is_temp := false
	mut file_name := ''

	unsafe {
		if file_name_or_null_for_tempfile == nil {
			is_temp = true
			file_name = rand.uuid_v4()
		} else {
			file_name = cstring_to_vstring(file_name_or_null_for_tempfile)
		}
	}
	mut vfs := to_vfs(raw_vfs)
	mut file := to_file(vfs_opened_file)

	file.parent = vfs

	$if debug {
		println('memfd_vfs_open: opening temp?=${is_temp} name=${file_name}')
	}

	file.fd = C.memfd_create(file_name.str, 0)

	if file.fd < 0 {
		// TODO set last_error
		return sqlite.sqlite_cantopen
	}

	file.file_type = get_sqliteopentype_of_typefromxopenflag(in_flags) or {
		println(err)
		// TODO set last_error

		C.close(file.fd)

		return sqlite.sqlite_cantopen
	}
	file.file_name = file_name.clone()

	open_mode := get_sqlite_open_flags_as_os_open_flags(in_flags)

	vfs.preserve_file_if_needed(file, open_mode) or {
		println(err)
		// TODO set last_error
		C.close(file.fd)

		return sqlite.sqlite_cantopen
	}

	mth := &sqlite.Sqlite3_io_methods{
		iVersion: 1
		xClose: fn (raw_file &sqlite.Sqlite3_file) int {
			$if debug {
				println('memfd xClose called')
			}

			mut file := to_file(raw_file)

			res := C.close(file.fd)

			if res != 0 {
				// TODO set last_error
				return sqlite.sqlite_error // TODO determine if it is a proper one
			}

			// TODO remove from vfs.files

			return sqlite.sqlite_ok
		}
		xRead: fn (raw_file &sqlite.Sqlite3_file, output voidptr, amount int, offset i64) int {
			$if debug {
				println('memfd xRead')
			}

			assert amount > 0

			mut file := to_file(raw_file)

			actual_offset := C.lseek(file.fd, offset, seek_set)
			if actual_offset != offset {
				return sqlite.sqlite_ioerr_read
			}

			// TODO use pread?
			result := C.read(file.fd, output, amount)

			if result < 0 {
				// TODO set last_error
				return sqlite.sqlite_ioerr_read
			}

			if result == amount {
				return sqlite.sqlite_ok
			}

			unsafe {
				o := &u8(output)
				C.memset(&o[result], 0, amount - result)
			}
			return sqlite.sqlite_ioerr_short_read
		}
		xWrite: fn (raw_file &sqlite.Sqlite3_file, buf voidptr, amount int, offset i64) int {
			$if debug {
				println('memfd xWrite')
			}

			assert amount > 0

			mut file := to_file(raw_file)

			// TODO use pwrite?
			actual_offset := C.lseek(file.fd, offset, seek_set)
			if actual_offset != offset {
				return sqlite.sqlite_ioerr_write
			}

			result := C.write(file.fd, buf, amount)

			return if result == amount { sqlite.sqlite_ok } else { sqlite.sqlite_ioerr_write }
		}
		xTruncate: fn (raw_file &sqlite.Sqlite3_file, size i64) int {
			$if debug {
				println('memfd xTruncate')
			}

			return sqlite.sqlite_ok
		}
		xSync: fn (raw_file &sqlite.Sqlite3_file, flags int) int {
			$if debug {
				println('memfd xSync')
			}

			mut file := to_file(raw_file)

			result := C.fsync(file.fd)

			return if result == 0 { sqlite.sqlite_ok } else { sqlite.sqlite_ioerr_fsync }
		}
		xFileSize: fn (raw_file &sqlite.Sqlite3_file, mut output &i64) int {
			$if debug {
				println('memfd xFileSize')
			}

			mut file := to_file(raw_file)

			stat := C.stat{}

			result := C.fstat(file.fd, &stat)

			if result != 0 {
				return sqlite.sqlite_ioerr_fstat
			}

			unsafe {
				*output = i64(stat.st_size)
			}
			return sqlite.sqlite_ok
		}
		xLock: fn (file &sqlite.Sqlite3_file, elock int) int {
			$if debug {
				println('memfd xLock')
			}

			return sqlite.sqlite_ok
		}
		xUnlock: fn (file &sqlite.Sqlite3_file, elock int) int {
			$if debug {
				println('memfd xUnlock')
			}

			return sqlite.sqlite_ok
		}
		xCheckReservedLock: fn (file &sqlite.Sqlite3_file, pResOut &int) int {
			$if debug {
				println('memfd xCheckReservedLock')
			}

			return sqlite.sqlite_ok
		}
		xFileControl: fn (file &sqlite.Sqlite3_file, op int, arg voidptr) int {
			$if debug {
				println('memfd xFileControl')
			}

			return 0
		}
		xSectorSize: fn (file &sqlite.Sqlite3_file) int {
			$if debug {
				println('memfd xSectorSize')
			}

			return 0
		}
		xDeviceCharacteristics: fn (file &sqlite.Sqlite3_file) int {
			$if debug {
				println('memfd xDeviceCharacteristics')
			}

			return 0
		}
	}

	unsafe {
		file.base.pMethods = mth

		//*out_flags = in_flags
	}
	return sqlite.sqlite_ok
}

fn memfd_vfs_delete(raw_vfs &sqlite.Sqlite3_vfs, name &char, sync_dir int) int {
	filename := unsafe { cstring_to_vstring(name).clone() }
	$if debug {
		println('memfd_vfs_delete() name=${filename}')
	}

	mut vfs := to_vfs(raw_vfs)

	vfs.forget_file(filename) or {
		println(err)
		return sqlite.sqlite_ioerr_delete
	}

	return sqlite.sqlite_ok
}

fn memfd_vfs_access(raw_vfs &sqlite.Sqlite3_vfs, zPath &char, flags int, mut pResOut &int) int {
	filename := unsafe { cstring_to_vstring(zPath).clone() }
	$if debug {
		println('memfd_vfs_access() path=${filename}')
	}

	mut vfs := to_vfs(raw_vfs)

	pResOut = if vfs.has_file(filename) { 1 } else { 0 }

	return sqlite.sqlite_ok
}

fn memfd_vfs_getlasterror(vfs &sqlite.Sqlite3_vfs, i int, o &char) int {
	$if debug {
		println('memfd_vfs_getlasterror()')
	}

	return sqlite.sqlite_ok
}

// get_files returns file name to file content
pub fn (mut t MemFdBasedVfs) get_files() !map[string]string {
	mut result := map[string]string{}

	for _, f in t.known_sqlfiles {
		pth := '/proc/self/fd/${f.fd}'
		content := os.read_file(pth) or { return error('unable to read file=${pth} error=${err}') }
		result[f.name] = content
	}

	return result
}

pub fn create_memfdbasedvfs(vfs_name string) !&MemFdBasedVfs {
	default_vfs := sqlite.get_default_vfs() or { return error('could not get default vfs') }

	mut result := &MemFdBasedVfs{
		name: vfs_name
		base: &sqlite.Sqlite3_vfs{
			iVersion: 2
			szOsFile: int(sizeof(MemFdOpenedFile))
			mxPathname: sqlite_memfd_vfs.max_file_name_len
			zName: 0
			pAppData: 0
			xOpen: memfd_vfs_open
			xDelete: memfd_vfs_delete
			xAccess: memfd_vfs_access
			xGetLastError: memfd_vfs_getlasterror
			xFullPathname: default_vfs.xFullPathname
			xDlOpen: default_vfs.xDlOpen
			xDlError: default_vfs.xDlError
			xDlSym: default_vfs.xDlSym
			xDlClose: default_vfs.xDlClose
			xRandomness: default_vfs.xRandomness
			xSleep: default_vfs.xSleep
			xCurrentTime: default_vfs.xCurrentTime
			xCurrentTimeInt64: default_vfs.xCurrentTimeInt64
		}
	}

	result.base.pAppData = result
	result.base.zName = result.name.str

	return result
}

pub fn (mut t MemFdBasedVfs) register_as_nondefault() ! {
	t.base.register_as_nondefault() or { return error('register_as_nondefault failed') }
}

pub fn (mut t MemFdBasedVfs) unregister() ! {
	t.unregister()!
}
