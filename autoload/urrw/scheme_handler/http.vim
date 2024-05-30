function! urrw#scheme_handler#http#handler_read(handler, readspec)
	" TODO: ranges
	let l:url = a:readspec.url
	let l:cmd = urrw#scheme_handler#command_as_string(['curl', '-i', l:url])
	let l:lines = systemlist(l:cmd)
	let l:http_status = []
	let l:body = []
	for l:i in range(len(l:lines))
		let l:ln = trim(l:lines[l:i])
		if l:i == 0
			let l:http_status = split(l:ln)
			continue
		endif
		if l:ln == ''
			" End of headers
			let l:body = l:lines[l:i + 1 :]
			break
		endif
		let l:header = matchlist(l:ln, '\v^([^\:]+)\:(.*)$')
		if len(l:header) < 3
			continue
		endif
		let l:key = tolower(trim(l:header[1]))
		let l:value = trim(l:header[2])
		if l:key == ''
			continue
		endif
		if l:key == 'location'
			return {'operation': 'redirect', 'url': urrw#urlutil#urljoin(l:url, l:value)}
		endif
	endfor
	return {'operation': 'set_lines', 'lines': l:body}
endfunction

function! urrw#scheme_handler#http#create_handler()
	let l:handler = {}
	function! l:handler.read(readspec) dict
		return urrw#scheme_handler#http#handler_read(self, a:readspec)
	endfunction
	return l:handler
endfunction
