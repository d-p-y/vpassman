#include "os_extensions.h"

int get_user_rwx_octet(struct stat *inp) {
    return
        ((inp->st_mode & S_IRUSR) ? 4 : 0) +
        ((inp->st_mode & S_IWUSR) ? 2 : 0) +
        ((inp->st_mode & S_IXUSR) ? 1 : 0);
}

int get_group_rwx_octet(struct stat *inp) {
    return
        ((inp->st_mode & S_IRGRP) ? 4 : 0) +
        ((inp->st_mode & S_IWGRP) ? 2 : 0) +
        ((inp->st_mode & S_IXGRP) ? 1 : 0);
}

int get_other_rwx_octet(struct stat *inp) {
    return
        ((inp->st_mode & S_IROTH) ? 4 : 0) +
        ((inp->st_mode & S_IWOTH) ? 2 : 0) +
        ((inp->st_mode & S_IXOTH) ? 1 : 0);
}

bool is_suid(struct stat *inp) {
    return S_ISUID & inp->st_mode;
}

bool is_sgid(struct stat *inp) {
    return S_ISGID & inp->st_mode;
}

int syslog_get_facility_user() {
    return LOG_USER;
}

int get_syslog_level_emerg() {
    return LOG_EMERG;
}

int get_syslog_level_alert() {
    return LOG_ALERT;
}

int get_syslog_level_crit() {
    return LOG_CRIT;
}

int get_syslog_level_err() {
    return LOG_ERR;
}

int get_syslog_level_warning() {
    return LOG_WARNING;
}

int get_syslog_level_notice() {
    return LOG_NOTICE;
}

int get_syslog_level_info() {
    return LOG_INFO;
}

int get_syslog_level_debug() {
    return LOG_DEBUG;
}

char *maybe_get_username_by_uid(uid_t uid) {
    struct passwd buf_and_result;

    //man 3 getpwuid
    int buflen = 16384;
    char buf[16384];
    struct passwd *success = NULL;

    int fres = getpwuid_r(uid, &buf_and_result, &buf[0], buflen, &success);

    if (fres != 0 || success == NULL) {
        return NULL;
    }

    return strdup(buf_and_result.pw_name);
}

enum FileItemType st_mode_to_item_type(mode_t st_mode) {
    if (S_ISDIR(st_mode) != 0) {
        return FileItemType_directory;
    }

    if (S_ISBLK(st_mode) != 0) {
        return FileItemType_block;
    }

    if (S_ISCHR(st_mode) != 0) {
        return FileItemType_character;
    }

    if (S_ISFIFO(st_mode) != 0) {
        return FileItemType_pipe;
    }

    if (S_ISLNK(st_mode) != 0) {
        return FileItemType_link;
    }

    if (S_ISSOCK(st_mode) != 0) {
        return FileItemType_socket;
    }

    return FileItemType_regular_file;
}
