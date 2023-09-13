#include "fusewrapper.h"
#include <sys/mount.h>

const char *STR_DASH_S = "-s";
const char *STR_DASH_F = "-f";
const char *STR_DASH_O = "-o";
const char *STR_ALLOW_OTHER = "allow_other";

const int READDIR_NO_SUCH_DIR = -ENOENT;
const int READDIR_NO_MORE_ITEMS = 0;

int readdir_no_such_dir() {
	return READDIR_NO_SUCH_DIR;
}

int readdir_no_more_items() {
	return READDIR_NO_MORE_ITEMS;
}

const int GETATTR_NO_SUCH_DIR = -ENOENT;
const int GETATTR_SUCCESS = 0;

int getattr_no_such_dir() {
	return GETATTR_NO_SUCH_DIR;
}

int getattr_success() {
	return GETATTR_SUCCESS;
}


const int OPEN_NO_SUCH_FILE = -ENOENT;
const int OPEN_PERMISSION_DENIED = -EACCES;
const int OPEN_SUCCESS = 0;

int open_no_such_file() {
	return OPEN_NO_SUCH_FILE;
}

int open_permission_denied() {
	return OPEN_PERMISSION_DENIED;
}

int open_success() {
	return OPEN_SUCCESS;
}

const int READ_NO_SUCH_FILE = -ENOENT;

int read_no_such_file() {	
	return READ_NO_SUCH_FILE;
}

struct fuse_args *fusewrapper_fuse_args_alloc_and_init(struct fusewrapper_fuse_args *args) {
    struct fuse_args *result;
   
	int fuse_args_size = sizeof(struct fuse_args);
    result = calloc(1, fuse_args_size);

	if (result == NULL) {
		printf("memory not allocated");
		exit(1); //panic
	}

	result->allocated = 0;
    result->argc = 2 + (args->allow_other_users ? 2 : 0) + (args->foreground ? 1 : 0) + (args->single_thread ? 1 : 0);
    
	result->argv = calloc(result->argc, sizeof(char*));

	if (result->argv == NULL) {
		printf("memory not allocated");
		exit(1); //panic
	}

	int i = 0;
	result->argv[i++] = args->exe_path; //foreground

	if (args->allow_other_users) {
		result->argv[i++] = strdup(STR_DASH_O);//TODO memory leak
		result->argv[i++] = strdup(STR_ALLOW_OTHER);//TODO memory leak
	}
	
	if (args->foreground) {
		result->argv[i++] = strdup(STR_DASH_F);//TODO memory leak
	}
    if (args->single_thread) {
		result->argv[i++] = strdup(STR_DASH_S); //TODO memory leak
	}
    
    result->argv[i++] = args->mount_destination;
    
    return result;
}

void fusewrapper_populate_common_params_from(
		struct fusewrapper_common_params *outp, const char *path, struct fuse_context *inp_ctx) {

	outp->path = path;
	outp->requested_by_uid = inp_ctx->uid;
	outp->requested_by_gid = inp_ctx->gid;
	outp->requested_by_pid = inp_ctx->pid;
}

int hello_getattr(const char *path, struct stat *stbuf, struct fuse_file_info *fi) {
	memset(stbuf, 0, sizeof(struct stat));

	struct fuse_context *ctx = fuse_get_context();

	if (ctx->private_data == NULL) {
		printf("fuse_get_context in getattr has null private_data\n");
		return GETATTR_NO_SUCH_DIR;
	}

	struct fusewrapper_impl_holder_t *impl_holder = (struct fusewrapper_impl_holder_t *)ctx->private_data;

	if (impl_holder->exit_requested) {
		//fuse_session_exit(ctx->fuse);	
		fuse_exit(ctx->fuse);
		//fuse_destroy(ctx->fuse);
		return GETATTR_NO_SUCH_DIR;
	}

	//printf("invoking impl got from private_data\n");

	if (impl_holder->impl == NULL || impl_holder->impl->getattr == NULL) {
		printf("getattr impl is null\n");
		return GETATTR_NO_SUCH_DIR;
	}

	//printf("invoking getattr impl got from private_data\n");
	struct fusewrapper_getattr_reply reply;

	struct fusewrapper_common_params common;
	fusewrapper_populate_common_params_from(&common, path, ctx);
	(impl_holder->impl->getattr)(&common, &reply);

	if (reply.result != GETATTR_SUCCESS) {
		return reply.result;
	}

	switch(reply.item_type) {
		case FILE_SYSTEM_ITEM_TYPE_DIRECTORY:
			stbuf->st_mode = S_IFDIR | reply.permissions_stat_h_bits;
			stbuf->st_nlink = 2;
			break;

		case FILE_SYSTEM_ITEM_TYPE_FILE:
			stbuf->st_mode = S_IFREG | reply.permissions_stat_h_bits;
			stbuf->st_nlink = 1;
			stbuf->st_size = reply.file_size_bytes;
			break;

		default:
			printf("getattr reply.item_type is unsupported\n");
			exit(1);
	}

	stbuf->st_uid = reply.uid;
	stbuf->st_gid = reply.gid;

	return reply.result;
}

int hello_readdir(const char *path, void *buf, fuse_fill_dir_t filler, off_t offset, struct fuse_file_info *fi, enum fuse_readdir_flags flags) {
	struct fuse_context *ctx = fuse_get_context();

	if (ctx->private_data == NULL) {
		printf("fuse_get_context in readdir has null private_data\n");
		return READDIR_NO_SUCH_DIR;
	}
	//printf("invoking readdir impl got from private_data\n");

	struct fusewrapper_impl_holder_t *impl_holder = (struct fusewrapper_impl_holder_t *)ctx->private_data;

	if (impl_holder->impl == NULL || impl_holder->impl->readdir == NULL) {
		printf("readdir impl is null\n");
		return READDIR_NO_SUCH_DIR;
	}

	if (impl_holder->exit_requested) {
		printf("illegal as exit was requested\n");
		return READDIR_NO_SUCH_DIR;
	}

	void adder(char *pfilename) {
		filler(buf, pfilename, NULL, 0, 0);
	}

	struct fusewrapper_common_params common;
	fusewrapper_populate_common_params_from(&common, path, ctx);

	return (impl_holder->impl->readdir)(&common, adder);
}

int hello_open(const char *path, struct fuse_file_info *fi) {
	struct fuse_context *ctx = fuse_get_context();

	if (ctx->private_data == NULL) {
		printf("fuse_get_context in open has null private_data\n");
		return READDIR_NO_SUCH_DIR;
	}
	//printf("invoking open impl got from private_data\n");

	struct fusewrapper_impl_holder_t *impl_holder = (struct fusewrapper_impl_holder_t *)ctx->private_data;

	if (impl_holder->impl == NULL || impl_holder->impl->open == NULL) {
		printf("open impl is null\n");
		return OPEN_NO_SUCH_FILE;
	}

	if (impl_holder->exit_requested) {
		printf("illegal as exit was requested\n");
		return READDIR_NO_SUCH_DIR;
	}

	enum OPEN_MODE mode;

	switch ((fi->flags & O_ACCMODE)) {
		case O_RDONLY:
			mode = OPEN_MODE_READ_ONLY; 
			break;

		case O_WRONLY:
			mode = OPEN_MODE_WRITE_ONLY; 
			break;

		case O_RDWR:
			mode = OPEN_MODE_READ_WRITE; 
			break;

		default: 
			return OPEN_NO_SUCH_FILE;
	}

	struct fusewrapper_common_params common;
	fusewrapper_populate_common_params_from(&common, path, ctx);

	return (impl_holder->impl->open)(&common, mode);
}

int hello_read(const char *path, char *buf, size_t bytes_to_read, off_t offset, struct fuse_file_info *fi) {
	struct fuse_context *ctx = fuse_get_context();

	if (ctx->private_data == NULL) {
		printf("fuse_get_context in read has null private_data\n");
		return READDIR_NO_SUCH_DIR;
	}
	//printf("invoking read impl got from private_data\n");

	struct fusewrapper_impl_holder_t *impl_holder = (struct fusewrapper_impl_holder_t *)ctx->private_data;

	if (impl_holder->impl == NULL || impl_holder->impl->read == NULL) {
		printf("read impl is null\n");
		return READ_NO_SUCH_FILE;
	}

	if (impl_holder->exit_requested) {
		printf("illegal as exit was requested\n");
		return READDIR_NO_SUCH_DIR;
	}
	
	void post_content(char *inp, size_t len) {
		memcpy(buf, inp, len);
	}

	struct fusewrapper_common_params common;
	fusewrapper_populate_common_params_from(&common, path, ctx);

	return (impl_holder->impl->read)(&common, offset, bytes_to_read, post_content);
}

struct fuse_operations *fusewrapper_fuse_alloc_fuse_operations() {
    struct fuse_operations *result;
    
	size_t size_of_fuse_operations = sizeof(struct fuse_operations);

    result = calloc(1, size_of_fuse_operations); //TODO add free somewhere

	//printf("fuse_alloc_fuse_operations() size_of_fuser_operations=%zu success?=%i\n", size_of_fuse_operations, result != NULL);

    result->readdir = hello_readdir;
    result->read = hello_read;
    result->open = hello_open;
    result->getattr = hello_getattr;
    return result;
}

int fusewrapper_mount(struct fuse_args *args, struct fuse_operations *ops, struct fusewrapper_impl_holder_t *impl) {
	return fuse_main(args->argc, args->argv, ops, impl);	
}
