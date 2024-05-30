function! urrw#scheme_handler#try_read(handler, readspec)
	let l:handler = a:handler
	let l:readspec = a:readspec
	let [l:handler, l:readspec] = urrw#scheme_handler#_prepare_args(l:handler, l:readspec, 'read')
	let l:do_continue = v:false
	let l:op = ''
	while v:true
		let l:method = ''
		let l:do_continue = l:op == 'continue'
		if !l:do_continue && has_key(l:handler, 'before_rw')
			let l:method = 'before_rw'
		elseif has_key(l:handler, 'read')
			let l:method = 'read'
		endif
		if l:method != ''
			" TODO check that 'self' is properly set with square
			" bracket notation
			let l:result = l:handler[l:method](l:readspec)
			let l:op = l:result.operation
			if l:op == 'done'
				return
			elseif l:op == 'continue'
				continue
			elseif l:op == 'redirect'
				let [l:handler, l:readspec] = urrw#scheme_handler#_handle_redirect(l:handler, l:readspec, l:result)
			elseif l:op == 'read_command'
				let [l:handler, l:readspec] = urrw#scheme_handler#_handle_read_command(l:handler, l:readspec, l:result)
			elseif l:op == 'read_file'
				let [l:handler, l:readspec] = urrw#scheme_handler#_handle_read_file(l:handler, l:readspec, l:result)
			elseif l:op == 'set_lines'
				let [l:handler, l:readspec] = urrw#scheme_handler#_handle_set_lines(l:handler, l:readspec, l:result)
			else
				throw 'Unknown scheme handler operation: ' . l:op
			end
		else
			let [l:handler, l:readspec] = urrw#scheme_handler#_handle_no_read(l:handler, l:readspec)
		endif
	endwhile
endfunction

function! urrw#scheme_handler#_prepare_args(handler, rwspec, method)
	let l:rwspec = copy(a:rwspec)
	if get(l:rwspec, 'buffer_rename', v:false) && l:rwspec.target == 'buffer'
		let l:buf = get(l:rwspec, 'buffer', '%')
		let l:rwspec.on_set_url = urrw#scheme_handler#_buffer_rename_handler(l:buf)
		if bufname(l:buf) == ''
			call l:rwspec.on_set_url(l:rwspec.url)
		endif
	endif
	return [a:handler, l:rwspec]
endfunction

function! urrw#scheme_handler#_buffer_rename_handler(buf)
	let l:storage = {}
	let l:buf = a:buf
	function! l:storage.set_url(url) closure
		" TODO switch buffer
		exe 'file ' . fnameescape(a:url)
	endfunction
	return l:storage.set_url
endfunction

function! urrw#scheme_handler#_handle_redirect(handler, rwspec, method_result)
	let l:handler = a:handler
	let l:rwspec = copy(a:rwspec)
	let l:method_result = a:method_result
	let l:redir_count = get(l:rwspec, 'redirect_count', 0)
	let l:redir_count += 1
	if has_key(l:rwspec, 'max_redirect_count')
		if l:redir_count > l:rwspec.max_redirect_count
			throw 'Too many redirects'
		endif
	endif
	let l:rwspec.redirect_count = l:redir_count
	if !has_key(l:rwspec, 'redirect_chain')
		let l:rwspec.redirect_chain = []
	endif
	call add(l:rwspec.redirect_chain, copy(l:method_result))
	if has_key(l:method_result, 'url')
		let [l:handler, l:rwspec] = urrw#scheme_handler#_handle_redirect_url(l:handler, l:rwspec, l:method_result)
	endif
	let l:handler = get(l:method_result, 'handler', l:handler)  " TODO select handlers based on url scheme?
	return [l:handler, l:rwspec]
endfunction

function! urrw#scheme_handler#_handle_redirect_url(handler, rwspec, method_result)
	let l:handler = a:handler
	let l:rwspec = copy(a:rwspec)
	let l:method_result = a:method_result
	let l:url = l:method_result.url
	" TODO check whether this context is authorized to load this url
	let l:policy = get(l:method_result, 'redirect_policy', 'set_url')
	if l:policy == 'set_url'
		if has_key(l:rwspec, 'on_set_url')
			call l:rwspec.on_set_url(l:url)
		endif
	elseif l:policy == 'no_set_url'
		" Do nothing
	elseif l:policy == 'no_set_url_further'
		if has_key(l:rwspec, 'on_set_url')
			unlet l:rwspec.on_set_url
		endif
	else
		throw 'Unknown redirect policy: ' . l:policy
	endif
	let l:rwspec.url = l:url
	return [l:handler, l:rwspec]
endfunction

function! urrw#scheme_handler#_handle_read_command(handler, readspec, method_result)
	let l:handler = a:handler
	let l:readspec = a:readspec
	let l:method_result = copy(a:method_result)
	let l:cmd = urrw#scheme_handler#command_as_string(l:method_result.command)
	let l:method_result.operation = 'set_lines'
	" Input ranges should be handled inside the command
	let l:method_result.lines = systemlist(l:cmd, get(l:method_result, 'command_input', []))
	return urrw#scheme_handler#_handle_set_lines(l:handler, l:readspec, l:method_result)
endfunction

function! urrw#scheme_handler#command_as_string(cmd)
	if type(a:cmd) == type('')
		return a:cmd
	elseif type(a:cmd) == type([])
		return join(map(copy(a:cmd), {_, el -> shellescape(el)}))
	else
		throw 'Command is neither string nor list'
	endif
endfunction

function! urrw#scheme_handler#_handle_read_file(handler, readspec, method_result)
	let l:handler = a:handler
	let l:readspec = a:readspec
	let l:method_result = copy(a:method_result)
	let l:filename = l:method_result.filename
	let l:method_result.operation = 'set_lines'
	" TODO Input ranges: if defined, use _handle_read_command with
	" head/tail/dd
	" TODO When do we need binary?
	let l:method_result.lines = readfile(l:filename, 'b')
	return urrw#scheme_handler#_handle_set_lines(l:handler, l:readspec, l:method_result)
endfunction

let s:done_handler = {
	\ 'before_rw': {rwspec -> {'operation': 'done'}},
	\ }

function! urrw#scheme_handler#_handle_set_lines(handler, readspec, method_result)
	let l:handler = a:handler
	let l:readspec = a:readspec
	let l:method_result = a:method_result
	let l:target = l:readspec.target
	" echom l:target
	if l:target == 'callback'
		call l:readspec.set_lines_callback(l:method_result.lines)
	elseif l:target == 'buffer'
		call urrw#scheme_handler#_handle_set_lines_buffer(handler, readspec, method_result)
	else
		throw 'Unknown target: ' . l:target
	endif
	let l:handler = get(l:method_result, 'handler', s:done_handler)
	return [l:handler, l:readspec]
endfunction

function! urrw#scheme_handler#_handle_set_lines_buffer(handler, readspec, method_result)
	let l:handler = a:handler
	let l:readspec = a:readspec
	let l:method_result = a:method_result
	" TODO better
	let l:buf = get(l:readspec, 'buffer', '%')
	call appendbufline(l:buf, 0, l:method_result.lines)
endfunction
