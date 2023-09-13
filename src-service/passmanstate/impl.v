module passmanstate

const (
	slash_lookalike                = [u8(0xe2), u8(0x81), u8(0x84)].bytestr()
	full_path_of_pid_tool_exe_path = $env('VPASSMAN_FULLPATHOFPID_EXE_PATH')
)

// TODO make it configurable and part of PassManExportSettings
pub fn sanitize_slashes(inp string) string {
	return inp.replace('/', passmanstate.slash_lookalike)
}
