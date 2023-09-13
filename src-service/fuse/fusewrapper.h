#ifndef FUSEWRAPPER_H
#define FUSEWRAPPER_H

#define FUSE_USE_VERSION 31

#include <fuse.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>
#include <fcntl.h>
#include <stddef.h>
#include <assert.h>
#include <stdbool.h>

enum FILE_SYSTEM_ITEM_TYPE {
	FILE_SYSTEM_ITEM_TYPE_FILE=1,
	FILE_SYSTEM_ITEM_TYPE_DIRECTORY=2
};

enum OPEN_MODE {
	OPEN_MODE_READ_ONLY = 1,
	OPEN_MODE_WRITE_ONLY,
	OPEN_MODE_READ_WRITE
};

struct fusewrapper_getattr_reply {
	unsigned int uid;
	unsigned int gid;
	unsigned int permissions_stat_h_bits;
	int result;
	enum FILE_SYSTEM_ITEM_TYPE item_type;
	int file_size_bytes;
};

struct fusewrapper_fuse_args {
	bool allow_other_users;
	bool foreground;
	bool single_thread;
	char *exe_path;
	char *mount_destination;
};

struct fusewrapper_common_params {
	const char *path;
	unsigned int requested_by_uid;
	unsigned int requested_by_gid;
	unsigned int requested_by_pid;
};

void fusewrapper_populate_common_params_from(struct fusewrapper_common_params *outp, const char *path, struct fuse_context *inp_ctx);

struct fusewrapper_impl_t {
	int (*readdir)(struct fusewrapper_common_params *common, void (*filler)(char *));
	void (*getattr)(struct fusewrapper_common_params *common, struct fusewrapper_getattr_reply *reply);

	int (*open)(struct fusewrapper_common_params *common, enum OPEN_MODE mode);
	int (*read)(struct fusewrapper_common_params *common, off_t offset, size_t bytes_to_read, void (*submit_read_result)(char *, size_t) );
};

struct fusewrapper_impl_holder_t {
	bool exit_requested;
	struct fusewrapper_impl_t *impl;
};

struct fuse_args *fusewrapper_fuse_args_alloc_and_init(struct fusewrapper_fuse_args *args);
struct fuse_operations *fusewrapper_fuse_alloc_fuse_operations();
int fusewrapper_mount(struct fuse_args *args, struct fuse_operations *ops, struct fusewrapper_impl_holder_t *impl);

#endif
