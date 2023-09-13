module sqlite_memfd_vfs

#define _GNU_SOURCE

#include <sys/mman.h>

const (
	seek_set = 0
	seek_cur = 1
	seek_end = 2
)

fn C.memfd_create(name &char, flags u32) int

fn C.fsync(fd int) int
fn C.fstat(fd int, output &C.stat) int

fn C.lseek(fd int, offset i64, seek_origin int) int
fn C.read(fd int, output voidptr, amount int) int
fn C.write(fd int, input voidptr, amount int) int
