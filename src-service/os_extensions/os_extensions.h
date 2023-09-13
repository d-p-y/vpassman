#ifndef OS_EXTENSIONS_H
#define OS_EXTENSIONS_H

#include <stdbool.h>
#include <sys/stat.h>
#include <syslog.h>
#include <unistd.h>
#include <sys/types.h>
#include <pwd.h>
#include <string.h>

enum FileItemType {
    FileItemType_regular_file=1,
    FileItemType_directory,
    FileItemType_block,
    FileItemType_character,
    FileItemType_pipe,
    FileItemType_link,
    FileItemType_socket
};

enum FileItemType st_mode_to_item_type(mode_t st_mode);

int get_user_rwx_octet(struct stat *inp);
int get_group_rwx_octet(struct stat *inp);
int get_other_rwx_octet(struct stat *inp);

bool is_suid(struct stat *inp);
bool is_sgid(struct stat *inp);

int syslog_get_facility_user();

int get_syslog_level_emerg();
int get_syslog_level_alert();
int get_syslog_level_crit();
int get_syslog_level_err();
int get_syslog_level_warning();
int get_syslog_level_notice();
int get_syslog_level_info();
int get_syslog_level_debug();

char *maybe_get_username_by_uid(uid_t uid);

#endif
