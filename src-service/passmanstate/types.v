module passmanstate

import fuse
import os_extensions
import db.sqlite

pub enum AttributeIdentifierKind {
	url = 1
	email
	password
	connection_string
	token
	username
	login
	note
}

[heap]
pub struct AttributeIdentifierStandard {
	identifier_kind AttributeIdentifierKind
}

[heap]
pub struct AttributeIdentifierCustom {
pub:
	attribute_name string
}

type AttributeIdentifier = AttributeIdentifierCustom | AttributeIdentifierStandard

[heap]
pub struct PassManItemAttribute {
mut:
	identifier AttributeIdentifier
	value      string
}

[heap]
struct PassManItemAttachment {
	file_name string
	content   []byte
}

[heap]
pub struct PassManFolder {
pub mut:
	name               string
	uuid_to_attribute  map[string]PassManItemAttribute
	uuid_to_attachment map[string]PassManItemAttachment

	access AccessCustomPolicy = AccessCustomPolicy{
		used: false
	}
}

[heap]
pub struct Dir {
pub:
	children []&FileSystemItem
}

[heap]
pub struct Accessor {
pub:
	username string
	exe_path string
}

[heap]
pub struct File {
pub:
	content string
}

type DirOrFile = Dir | File

// TODO refactor into two enums probably
pub enum AccessPolicy {
	never_allowed
	ask // interactively so blocks for long time
	executed_by_owner_username
	executed_by_owner_username_and_path_matches // should not be used for default policy
	user_and_path_matches // should not be used for default policy
}

[heap]
pub struct AccessCustomPolicy {
pub:
	used     bool
	policy   AccessPolicy
	username string
	exe_path string
}

[heap]
pub struct FileSystemItem {
pub:
	name        string
	uid         u32
	gid         u32
	permissions os_extensions.UnixFilePermissions
	details     &DirOrFile
	origin      &PassManFolder = unsafe { nil }
}

pub enum FsOperation {
	get_attribute
	list_dir
	include_in_listing
	open_file
	read_file
}

enum AccessDecision {
	granted
	denied
	interaction_required
}

[heap]
pub struct PassManExportSettings {
pub:
	uid                                 u32
	gid                                 u32
	dir                                 os_extensions.UnixFilePermissions
	file                                os_extensions.UnixFilePermissions
	maybe_get_full_path_of_pid_tool_exe string
}

pub enum FolderField {
	name = 1
	wip_other_property
}

pub enum CustomAttrField {
	name = 1
	value = 2
}

// TODO come up with better name
// TODO add max file size (to prevent buggy programs trying to add huge values)
// TODO add max attribute name length (to prevent buggy programs trying to add huge values)
[heap]
pub struct PassManState {
pub mut:
	name           string
	owner_username string
	// don't bother with access to directories such as /secret that don't on their own contain anything secret
	verify_access_for_directories_unrelated_to_passman_folders bool
	// accept the fact that some program may learn that there exists specific directory related to passman folder BUT don't give rights to read it. Helpful to avoid implicit getattr-to-dir before actual next access check request (such as read file)
	verify_access_for_getattr_on_directory_related_to_passman_folders bool = true
	access                                                            AccessPolicy = AccessPolicy.executed_by_owner_username

	uuid_to_folder map[string]PassManFolder // as user may have created duplicates, dict key is treated so there are no duplicates
	// TODO history records from which folders and their attributes are calculated plus some additional "conflict resolution records array"
}

interface IAccessCompute {
	compute_has_access(path string, subject &FileSystemItem, op FsOperation, executor &Accessor) AccessDecision
}

interface IAccessPrompt {
mut:
	request_has_access_reply(path string, subject &FileSystemItem, oper FsOperation, executor &Accessor) chan bool
}

enum DecisionOrigin {
	policy // calculated
	interactive // user
}

interface IAccessAudit {
	audit_access(decision AccessDecision, decision_origin DecisionOrigin, path string, subject &FileSystemItem, op FsOperation, executor &Accessor)
}

[heap]
pub struct CustomAccessPrompt {
	impl fn (path string, subject &FileSystemItem, oper FsOperation, executor &Accessor) chan bool [required]
}

// implements request_has_access_reply
fn (t &CustomAccessPrompt) request_has_access_reply(path string, subject &FileSystemItem, oper FsOperation, executor &Accessor) chan bool {
	return t.impl(path, subject, oper, executor)
}

[heap]
pub struct CustomAccessAudit {
	impl fn (decision AccessDecision, decision_origin DecisionOrigin, path string, subject &FileSystemItem, op FsOperation, executor &Accessor) [required]
}

// implements IAccessAudit
fn (t &CustomAccessAudit) audit_access(decision AccessDecision, decision_origin DecisionOrigin, path string, subject &FileSystemItem, op FsOperation, executor &Accessor) {
	t.impl(decision, decision_origin, path, subject, op, executor)
}

[heap]
pub struct EmptyAccessAudit {}

// implements IAccessAudit
fn (t &EmptyAccessAudit) audit_access(decision AccessDecision, decision_origin DecisionOrigin, path string, subject &FileSystemItem, op FsOperation, executor &Accessor) {
	$if debug {
		println('audit_access: DISABLED for decision=${decision} decision_origin=${decision_origin} path=${path} op=${op} executor=${executor} subject=${subject.name}')
	}
}

[heap]
struct AlwaysGrantedAccessCompute {}

// implements IAccessCompute
fn (t AlwaysGrantedAccessCompute) compute_has_access(path string, subject &FileSystemItem, op FsOperation, executor &Accessor) AccessDecision {
	$if debug {
		println('compute_has_access: always-granting for path=${path} op=${op} executor=${executor} subject=${subject.name}')
	}

	return .granted
}

[heap]
struct AlwaysDeniedAccessCompute {}

// implements IAccessCompute
fn (t AlwaysDeniedAccessCompute) compute_has_access(path string, subject &FileSystemItem, op FsOperation, executor &Accessor) AccessDecision {
	$if debug {
		println('compute_has_access: always-denying for path=${path} op=${op} executor=${executor} subject=${subject.name}')
	}

	return .denied
}

[heap]
struct DenyingAccessPrompt {}

// implements IAccessPrompt
fn (mut t DenyingAccessPrompt) request_has_access_reply(path string, subject &FileSystemItem, oper FsOperation, executor &Accessor) chan bool {
	$if debug {
		println('DenyingAccessPrompt request_has_access_reply')
	}

	result := chan bool{cap: 1}
	result <- false
	return result
}

[heap]
pub struct PassManStateWiredToFuse {
pub mut:
	passman    &PassManState
	root       &FileSystemItem
	settings   PassManExportSettings
	fuse_state &fuse.FuseState

	audit                 IAccessAudit   [required]
	request_access_prompt IAccessPrompt  [required]
	access_compute        IAccessCompute [required]
}

[heap]
struct AccessRequest {
pub:
	executor &Accessor
	folder   &PassManFolder
	response chan bool
	// origin when triggered via fuse
	path    string
	oper    FsOperation
	subject &FileSystemItem
	// TODO origin when triggered via other API (such as dbus)
}

pub fn (r &AccessRequest) maybe_get_folder_name() string {
	unsafe {
		return if r.folder == nil { '' } else { r.folder.name }
	}
}

pub struct AccessRequestWithId {
pub:
	request &AccessRequest
	id      string
}

struct MyMutex {
	manual_dummy_pad bool // needed due to https://github.com/vlang/v/issues/16234
}

type FnAction = fn ()

[heap]
pub struct AccessRequestManager {
	lck   shared MyMutex
	audit &IAccessAudit  [required]
mut:
	listeners        []FnAction
	pending_requests map[string]&AccessRequest
	auto_reject_mode bool // for unmounting
}

[table: 'change_origin']
pub struct ChangeOrigin {
pub:
	id            int    [primary; sql: serial]
	computer_name string [sql_type: 'TEXT']
	user_name     string [sql_type: 'TEXT']
}

[table: 'change']
struct Change {
pub:
	id                                              int // to make orm happy
	utc_when                                        u64    [notnull]
	origin_id                                       int    [notnull]
	type_insert_update_delete                       u8     [notnull]
	subject_type_folder_stdattr_custattr_attachment int    [notnull]
	subject_subtype_for_ins_upd                     string [notnull]
	subject_uuid                                    string [notnull]
	parent_folder_uuid_for_ins_attr                 string
	subject_value_for_ins_upd                       string
}

enum InsertUpdateDelete {
	insert = 1
	update = 2
	delete = 3
}

enum SubjectType {
	folder = 1
	custom_attribute = 2
	standard_attribute = 3
	attachment = 4
}

[heap]
struct PassManDbStorage {
pub mut:
	db                   sqlite.DB
	last_unix_time_milli u64
}
