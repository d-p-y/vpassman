module main

import fuse
import model
import os_extensions
import os

const (
	default_root_expect = RootDirExpectations{
		uid: 1100
		gid: 2100
		permissions: os_extensions.UnixFilePermissions{
			user_r: true
			user_x: true
		}
	}
)

fn testsuite_begin() ! {
	assert os.is_dir(mount_point_path)

	assert os.is_file(existing_text_file_path)
	assert suid_mycat_exe_path != ''

	assert this_exe_path != ''

	assert this_username != ''
	assert suid_username_first != ''
	assert suid_username_second != ''

	assert suid_username_second != suid_username_first
	assert this_username != suid_username_first
	assert this_username != suid_username_second

	unmount_if_needed()!
}

fn testsuite_end() ! {
	unmount_if_needed()!
}

fn test_is_mounted_simple() ! {
	content := r'sysfs /sys sysfs rw,nosuid,nodev,noexec,relatime 0 0
proc /proc proc rw,nosuid,nodev,noexec,relatime 0 0
udev /dev devtmpfs rw,nosuid,relatime,size=8095672k,nr_inodes=2023918,mode=755,inode64 0 0
devpts /dev/pts devpts rw,nosuid,noexec,relatime,gid=5,mode=620,ptmxmode=000 0 0
tmpfs /run tmpfs rw,nosuid,nodev,noexec,relatime,size=1630432k,mode=755,inode64 0 0
/dev/sda3 / ext4 rw,relatime,errors=remount-ro 0 0
securityfs /sys/kernel/security securityfs rw,nosuid,nodev,noexec,relatime 0 0
tmpfs /dev/shm tmpfs rw,nosuid,nodev,inode64 0 0
tmpfs /run/lock tmpfs rw,nosuid,nodev,noexec,relatime,size=5120k,inode64 0 0
cgroup2 /sys/fs/cgroup cgroup2 rw,nosuid,nodev,noexec,relatime,nsdelegate,memory_recursiveprot 0 0
pstore /sys/fs/pstore pstore rw,nosuid,nodev,noexec,relatime 0 0
efivarfs /sys/firmware/efi/efivars efivarfs rw,nosuid,nodev,noexec,relatime 0 0
bpf /sys/fs/bpf bpf rw,nosuid,nodev,noexec,relatime,mode=700 0 0
systemd-1 /proc/sys/fs/binfmt_misc autofs rw,relatime,fd=29,pgrp=1,timeout=0,minproto=5,maxproto=5,direct,pipe_ino=23024 0 0
mqueue /dev/mqueue mqueue rw,nosuid,nodev,noexec,relatime 0 0
hugetlbfs /dev/hugepages hugetlbfs rw,relatime,pagesize=2M 0 0
debugfs /sys/kernel/debug debugfs rw,nosuid,nodev,noexec,relatime 0 0
tracefs /sys/kernel/tracing tracefs rw,nosuid,nodev,noexec,relatime 0 0
fusectl /sys/fs/fuse/connections fusectl rw,nosuid,nodev,noexec,relatime 0 0
configfs /sys/kernel/config configfs rw,nosuid,nodev,noexec,relatime 0 0
none /run/credentials/systemd-sysusers.service ramfs ro,nosuid,nodev,noexec,relatime,mode=700 0 0
/dev/sda2 /boot/efi vfat rw,relatime,fmask=0077,dmask=0077,codepage=437,iocharset=iso8859-1,shortname=mixed,errors=remount-ro 0 0
tmpfs /run/user/1000 tmpfs rw,nosuid,nodev,relatime,size=1630428k,nr_inodes=407607,mode=700,uid=1000,gid=1000,inode64 0 0
portal /run/user/1000/doc fuse.portal rw,nosuid,nodev,relatime,user_id=1000,group_id=1000 0 0
'

	assert !fuse.is_mounted_using_custom_proc_self_mounts('/foo', model.new_maybe_some(content))!

	// not implemented as a naive grep
	assert !fuse.is_mounted_using_custom_proc_self_mounts('/run/user/100', model.new_maybe_some(content))!
	assert fuse.is_mounted_using_custom_proc_self_mounts('/run/user/1000', model.new_maybe_some(content))!

	// last line processed too
	assert fuse.is_mounted_using_custom_proc_self_mounts('/run/user/1000/doc', model.new_maybe_some(content))!
}

fn test_is_mounted_special_characters() ! {
	content := r'sysfs /sys sysfs rw,nosuid,nodev,noexec,relatime 0 0
proc /proc proc rw,nosuid,nodev,noexec,relatime 0 0
udev /dev devtmpfs rw,nosuid,relatime,size=8095680k,nr_inodes=2023920,mode=755,inode64 0 0
devpts /dev/pts devpts rw,nosuid,noexec,relatime,gid=5,mode=620,ptmxmode=000 0 0
tmpfs /run tmpfs rw,nosuid,nodev,noexec,relatime,size=1630432k,mode=755,inode64 0 0
/dev/sda3 / ext4 rw,relatime,errors=remount-ro 0 0
securityfs /sys/kernel/security securityfs rw,nosuid,nodev,noexec,relatime 0 0
tmpfs /dev/shm tmpfs rw,nosuid,nodev,inode64 0 0
tmpfs /run/lock tmpfs rw,nosuid,nodev,noexec,relatime,size=5120k,inode64 0 0
cgroup2 /sys/fs/cgroup cgroup2 rw,nosuid,nodev,noexec,relatime,nsdelegate,memory_recursiveprot 0 0
pstore /sys/fs/pstore pstore rw,nosuid,nodev,noexec,relatime 0 0
efivarfs /sys/firmware/efi/efivars efivarfs rw,nosuid,nodev,noexec,relatime 0 0
bpf /sys/fs/bpf bpf rw,nosuid,nodev,noexec,relatime,mode=700 0 0
systemd-1 /proc/sys/fs/binfmt_misc autofs rw,relatime,fd=29,pgrp=1,timeout=0,minproto=5,maxproto=5,direct,pipe_ino=19888 0 0
mqueue /dev/mqueue mqueue rw,nosuid,nodev,noexec,relatime 0 0
hugetlbfs /dev/hugepages hugetlbfs rw,relatime,pagesize=2M 0 0
debugfs /sys/kernel/debug debugfs rw,nosuid,nodev,noexec,relatime 0 0
tracefs /sys/kernel/tracing tracefs rw,nosuid,nodev,noexec,relatime 0 0
fusectl /sys/fs/fuse/connections fusectl rw,nosuid,nodev,noexec,relatime 0 0
configfs /sys/kernel/config configfs rw,nosuid,nodev,noexec,relatime 0 0
none /run/credentials/systemd-sysusers.service ramfs ro,nosuid,nodev,noexec,relatime,mode=700 0 0
/dev/sda2 /boot/efi vfat rw,relatime,fmask=0077,dmask=0077,codepage=437,iocharset=iso8859-1,shortname=mixed,errors=remount-ro 0 0
tmpfs /run/user/1000 tmpfs rw,nosuid,nodev,relatime,size=1630428k,nr_inodes=407607,mode=700,uid=1000,gid=1000,inode64 0 0
portal /run/user/1000/doc fuse.portal rw,nosuid,nodev,relatime,user_id=1000,group_id=1000 0 0
fuse_fundamentals_test /mnt/special/mountpoint_spec_chars_start\134\040\011*?\012done fuse.fuse_fundamentals_test rw,nosuid,nodev,relatime,user_id=1000,group_id=1000 0 0
'

	assert fuse.is_mounted_using_custom_proc_self_mounts('/mnt/special/mountpoint_spec_chars_start\\ \t*?\ndone',
		model.new_maybe_some(content))!
}

fn test_multiple_mounting_and_unmounting_in_foreground_works() ! {
	println('#-#-# start #-#-# test_multiple_mounting_and_unmounting_in_foreground_works()')

	base_test_mounting_in_foreground_actually_exposes_requested_file(default_root_expect,
		ExpectedFsEntry{
		name: 'test.txt'
		uid: 3333
		gid: 5555
		permissions: os_extensions.new_permissions_from_octets('r--------')!
		details: ExpectedFsFileEntry{
			content: 'somecontent'
		}
	})!

	$if debug {
		println('\n\nNOTE unmounted, now another phase\n\n')
	}

	//-gc none needed otherwise it gets stuck
	base_test_mounting_in_foreground_actually_exposes_requested_file(default_root_expect,
		ExpectedFsEntry{
		name: 'test.txt'
		uid: 3333
		gid: 5555
		permissions: os_extensions.new_permissions_from_octets('r--------')!
		details: ExpectedFsFileEntry{
			content: 'somecontent'
		}
	})!
}

fn test_mounting_in_foreground_actually_exposes_requested_file() ! {
	println('#-#-# start #-#-# test_mounting_in_foreground_actually_exposes_requested_file()')

	base_test_mounting_in_foreground_actually_exposes_requested_file(default_root_expect,
		ExpectedFsEntry{
		name: 'test.txt'
		uid: 3333
		gid: 5555
		permissions: os_extensions.new_permissions_from_octets('r--------')!
		details: ExpectedFsFileEntry{
			content: 'somecontent'
		}
	})!
}

fn test_mounting_in_foreground_actually_exposes_two_files() ! {
	println('#-#-# start #-#-# test_mounting_in_foreground_actually_exposes_two_files()')

	base_test_mounting_in_foreground_actually_exposes_requested_file(default_root_expect,
		ExpectedFsEntry{
		name: 'test2.txt'
		uid: 3333
		gid: 5555
		permissions: os_extensions.new_permissions_from_octets('rw-------')!
		details: ExpectedFsFileEntry{
			content: 'some2content'
		}
	}, ExpectedFsEntry{
		name: 'test1.txt'
		uid: 3333
		gid: 5555
		permissions: os_extensions.new_permissions_from_octets('r-x------')!
		details: ExpectedFsFileEntry{
			content: 'some1content'
		}
	})!
}

// TODO file in subdir

fn test_unicode_content_is_preserved() ! {
	println('#-#-# start #-#-# test_unicode_content_is_preserved()')

	base_test_mounting_in_foreground_actually_exposes_requested_file(default_root_expect,
		ExpectedFsEntry{
		name: 'test.txt'
		uid: 3333
		gid: 5555
		permissions: os_extensions.new_permissions_from_octets('r--------')!
		details: ExpectedFsFileEntry{
			content: r'¥€$ąęПЖДäüöß'
		}
	})!

	base_test_mounting_in_foreground_actually_exposes_requested_file(default_root_expect,
		ExpectedFsEntry{
		name: 't e s t.txt'
		uid: 3333
		gid: 5555
		permissions: os_extensions.new_permissions_from_octets('r--------')!
		details: ExpectedFsFileEntry{
			content: 'ПЖД\n¥\t€ €\n'
		}
	})!
}

fn test_unicode_file_name_is_preserved() ! {
	println('#-#-# start #-#-# test_unicode_file_name_is_preserved()')

	base_test_mounting_in_foreground_actually_exposes_requested_file(default_root_expect,
		ExpectedFsEntry{
		name: 'П ЖД.€'
		uid: 3333
		gid: 5555
		permissions: os_extensions.new_permissions_from_octets('r--------')!
		details: ExpectedFsFileEntry{
			content: 'ęПß'
		}
	})!
}

fn test_permissions_are_working() ! {
	println('#-#-# start #-#-# test_permissions_are_working()')

	perms := [
		'r--------',
		'-w-------',
		'--x------',
		'r--r-----',
		'r---w----',
		'r----x---',
		'r-----r--',
		'r------w-',
		'r-------x',
	]

	for i, perm in perms {
		$if debug {
			println('testing perm=${perm}')
		}

		base_test_mounting_in_foreground_actually_exposes_requested_file(default_root_expect,
			ExpectedFsEntry{
			name: 'test.txt'
			uid: (3333 + u32(i))
			gid: (5555 + u32(i))
			permissions: os_extensions.new_permissions_from_octets(perm)!
			details: ExpectedFsFileEntry{
				content: 'x'
			}
		})!
	}
}

// TODO test if common.requested_by_* is actually passed
