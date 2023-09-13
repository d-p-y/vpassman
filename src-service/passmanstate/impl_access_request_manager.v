module passmanstate

import rand

pub fn (mut m AccessRequestManager) reject_all_pending_and_future() {
	m.auto_reject_mode = true

	for x in m.get_pending_requests() {
		m.reply_to_request(x.id, false) or { println('unable to reject item id=${x.id} ${err}') }
	}
}

pub fn (mut m AccessRequestManager) subscribe(listener FnAction) fn () {
	$if debug {
		println('!!!locking start')
	}
	lock m.lck {
		m.listeners << listener
	}
	$if debug {
		println('!!!locking stop')
	}

	return listener
}

pub fn (mut m AccessRequestManager) unsubscribe(listener FnAction) {
	mut found := false

	$if debug {
		println('!!!locking start')
	}
	lock m.lck {
		for i, e in m.listeners {
			if e == listener {
				found = true
				m.listeners.delete(i)
				break
			}
		}
	}
	$if debug {
		println('!!!locking stop')
	}

	$if debug {
		println('unsubscribe success?=${found}')
	}
}

pub fn (mut m AccessRequestManager) notify_subscribers() {
	mut copy := []FnAction{}

	$if debug {
		println('!!!locking start')
	}
	rlock m.lck {
		copy = m.listeners.clone()
	}
	$if debug {
		println('!!!locking stop')
	}

	for l in copy {
		l()
	}
}

pub fn (mut m AccessRequestManager) get_pending_requests() []AccessRequestWithId {
	mut result := []AccessRequestWithId{}

	$if debug {
		println('!!!locking start in get_pending_requests')
	}
	rlock m.lck {
		result = []AccessRequestWithId{cap: m.pending_requests.len}

		for k, v in m.pending_requests {
			result << AccessRequestWithId{
				id: k
				request: v
			}
		}
	}
	$if debug {
		println('!!!locking stop in get_pending_requests')
	}

	$if debug {
		println('get_pending_requests')
	}
	$if debug {
		dump(result)
	}

	return result
}

// add_request returns id
fn (mut m AccessRequestManager) add_request(req &AccessRequest) string {
	id := rand.uuid_v4()
	$if debug {
		println('about to add_request req=${req} id=${id}')
	}

	$if debug {
		println('!!!locking start')
	}
	lock m.lck {
		m.pending_requests[id] = req
	}
	$if debug {
		println('!!!locking stop')
	}

	$if debug {
		println('add_request OK')
	}
	return id
}

pub fn (mut m AccessRequestManager) reply_to_request(request_id string, response bool) ! {
	$if debug {
		println('about to reply_to_request request_id=${request_id} response=${response}')
	}

	mut request := unsafe { &AccessRequest(nil) }

	// minimise locking as request reply will likely follow with another request
	$if debug {
		println('!!!locking start')
	}
	lock m.lck {
		if req := m.pending_requests[request_id] {
			m.pending_requests.delete(request_id)
			request = req
		}
	}
	$if debug {
		println('!!!locking stop')
	}

	$if debug {
		println('add_request about to reply')
	}

	has_request := unsafe { request != nil }

	if has_request {
		req := request
		policy_result := if response { AccessDecision.granted } else { AccessDecision.denied }
		m.audit.audit_access(policy_result, .interactive, req.path, req.subject, req.oper,
			req.executor)

		req.response <- response

		$if debug {
			println('add_request replied ok')
		}
		return
	}

	$if debug {
		println('add_request no request pending id=${request_id}')
	}
	return error('no pending request with id=${request_id}')
}

// implement IAccessPrompt
fn (mut m AccessRequestManager) request_has_access_reply(path string, subject &FileSystemItem, oper FsOperation, executor &Accessor) chan bool {
	$if debug {
		println('request_has_access_reply auto_reject_mode?=${m.auto_reject_mode}')
	}
	if m.auto_reject_mode {
		res := chan bool{cap: 1}
		res <- false
		return res
	}

	req := AccessRequest{
		executor: executor
		folder: subject.origin
		response: chan bool{cap: 1}
		path: path
		oper: oper
		subject: subject
	}
	m.add_request(req)

	m.notify_subscribers()

	return req.response
}
