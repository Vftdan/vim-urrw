" Port of some python urllib functions
" Should not be used in untrusted or sensitive contexts
" "URI" means "URI reference", unless the opposite is specified
" TODO always distinguish codepoint and byte indices when working with strings

let s:MAX_CACHE_SIZE = 20
let s:_parse_cache = {}
let s:override_scheme_chars = {}  " char -> {v:true, v:false}

" Copied from urllib3. We may not use it by using a scheme-invariant handling
" or by specifying these options when registering each scheme.
let s:uses_relative = {'': v:true,
	\ 'wais': v:true,
	\ 'file': v:true,
	\ 'https': v:true,
	\ 'shttp': v:true,
	\ 'mms': v:true,
	\ 'http': v:true,
	\ 'gopher': v:true,
	\ 'nntp': v:true,
	\ 'imap': v:true,
	\ 'prospero': v:true,
	\ 'rtsp': v:true,
	\ 'rtspu': v:true,
	\ 'sftp': v:true,
	\ 'svn': v:true,
	\ 'svn+ssh': v:true,
	\ 'ws': v:true,
	\ 'wss': v:true,
	\ 'gemini': v:true,
	\ }

let s:uses_netloc = {'': v:true,
	\ 'ftp': v:true,
	\ 'http': v:true,
	\ 'gopher': v:true,
	\ 'nntp': v:true,
	\ 'telnet': v:true,
	\ 'imap': v:true,
	\ 'wais': v:true,
	\ 'file': v:true,
	\ 'mms': v:true,
	\ 'https': v:true,
	\ 'shttp': v:true,
	\ 'snews': v:true,
	\ 'prospero': v:true,
	\ 'rtsp': v:true,
	\ 'rtspu': v:true,
	\ 'rsync': v:true,
	\ 'svn': v:true,
	\ 'svn+ssh': v:true,
	\ 'sftp': v:true,
	\ 'nfs': v:true,
	\ 'git': v:true,
	\ 'git+ssh': v:true,
	\ 'ws': v:true,
	\ 'wss': v:true,
	\ 'gemini': v:true,
	\ }

let s:uses_params = {'': v:true,
	\ 'ftp': v:true,
	\ 'hdl': v:true,
	\ 'prospero': v:true,
	\ 'http': v:true,
	\ 'imap': v:true,
	\ 'https': v:true,
	\ 'shttp': v:true,
	\ 'rtsp': v:true,
	\ 'rtspu': v:true,
	\ 'sip': v:true,
	\ 'sips': v:true,
	\ 'mms': v:true,
	\ 'sftp': v:true,
	\ 'tel': v:true,
	\ 'data': v:true,
	\ }

function! s:is_all_digit(s)
	for l:c in split(a:s, '\zs')
		if l:c < '0' || l:c > '9'
			return v:false
		endif
	endfor
	return v:true
endfunction

function! urrw#urlutil#_is_scheme_char(c)
	let l:override = get(s:override_scheme_chars, a:c, v:null)
	if type(l:override) != type(v:null)
		return l:override
	endif
	if 'a' <= a:c && a:c <= 'z'
		return v:true
	endif
	if 'A' <= a:c && a:c <= 'Z'
		return v:true
	endif
	if '0' <= a:c && a:c <= '9'
		return v:true
	endif
	return a:c == '+' || a:c == '-' || a:c == '.'
endfunction

function! urrw#urlutil#urlparse(url, options)
	" Create a dictionary of 6 url substrings
	" (scheme ":")? ("//" netloc)? path? (";" params)? ("?" query)? ("#" fragment)?
	" components don't include prefix/suffix markers (but path includes leading slash)
	" additional boolean "has_..." entries are used to distinguish parsed and default value
	" if result.has_netloc is trueish, bet result.netloc is zero-length, url is of ((scheme ":")? "///" ...) form
	if type(a:url) != 1
		return urrw#urlutil#urlparse(a:url . '', a:options)
	endif
	if type(a:options) != 4
		return urrw#urlutil#urlparse(a:url, {})
	endif
	let l:scheme = get(a:options, 'scheme', '')
	let l:allow_fragments = get(a:options, 'allow_fragments', 1)
	let l:allow_leading_netloc = get(a:options, 'allow_leading_netloc', 1)
	if type(l:scheme) != 1
		let l:scheme = l:scheme ? l:scheme . '' : ''
	endif
	let l:cache_key = json_encode([a:url, l:scheme, l:allow_fragments ? v:true : v:false, l:allow_leading_netloc ? v:true : v:false])
	let l:cached = get(s:_parse_cache, l:cache_key, v:null)
	if type(l:cached) != type(v:null)
		return copy(l:cached)
	endif
	if len(s:_parse_cache) > s:MAX_CACHE_SIZE
		let s:_parse_cache = {}
	endif
	let l:netloc = ''
	let l:query = ''
	let l:fragment = ''
	let l:params = ''
	let l:scheme = a:scheme
	let l:scheme_end = stridx(a:url, ':')
	echom 'initial scheme_end = ' . l:scheme_end
	if l:scheme_end > 0
		let l:scheme = a:url[: l:scheme_end - 1]
		for l:c in split(l:scheme, '\zs')
			if !urrw#urlutil#_is_scheme_char(l:c)
				echom 'Not scheme char: ' . l:c
				let l:scheme_end = -1
				let l:scheme = ''
				break
			endif
		endfor
	endif
	echom 'scheme_end = ' . l:scheme_end
	" Does not include colon, but includes potential double slash
	let l:after_scheme = a:url[l:scheme_end + 1 :]
	if l:scheme_end > 0
		" Ensure that l:after_scheme is not a port
		" urllib/parse.py does this. Is this a special netloc-only case?
		" Should we also handle ipv6, i. e. any hosts of form ("[" ... ":" ... "]")?
		" urllib may default to http(s), but we default to unencoded file path, so we may not need it anyway?
		" colons are not ususally allowed in filenames, but may be on some OSes or filesystems they are?
		" X11 port has a syntax of (display_number ("." screen_number)?), but it doesn't conform to URI spec ( https://datatracker.ietf.org/doc/html/rfc3986#section-3.2.3 )
		" X11 however also uses ((protocol "/")? hostname) instead of ((protocol ":")? "//" hostname), so it may be irrelevant & treated completely as a path
		" On the other hand path can be used to build an underlying URI like ("x11:" (protocol "/")? hostname ":" display_number ("." screen_number)?) -> (protocol "://" hostname ":" calc(display_number + offset)), where offset = 6000 for tcp (xcb.h, X_TCP_PORT), screen_number is still probably not a part of underlying
		" Protocol values "tcp", "inet", "inet6" all open tcp socket at ("tcp://" hostname ":" calc(display_number + X_TCP_PORT))
		" Protocol value "unix", hostname is an absolute path & display_number is ignored or the path is ("/tmp/.X11-unix/X" display_number) (or equivalent for other OSes)
		" Therefore: dot is not a part of a port
		" FIXME breaks urls without netloc and numeric path
		" Should we consider alphabetic aliases for ports?
		if len(l:after_scheme) && s:is_all_digit(l:after_scheme)
			let l:scheme_end = -1
			let l:scheme = a:scheme
			let l:after_scheme = a:url
		endif
	endif
	let l:netloc_end = 0
	let l:has_netloc = l:after_scheme[: 1] == '//'
	if l:has_netloc
		let l:after_scheme = l:after_scheme[2 :]
		let l:netloc_end = len(l:after_scheme)
		" Are netloc and params separated by a slash?
		for l:c in ['/', '?', '#']
			let l:maybe_netloc_end = stridx(l:after_scheme, l:c)
			if l:maybe_netloc_end >= 0
				let l:netloc_end = min([l:netloc_end, l:maybe_netloc_end])
			endif
		endfor
		let l:netloc = l:netloc_end > 0 ? l:after_scheme[: l:netloc_end - 1] : ''
		let l:after_netloc = l:after_scheme[l:netloc_end :]
	else
		let l:after_netloc = l:after_scheme
	endif
	" l:after_netloc currently includes leading slash/question mark/hash character
	let l:fragment_start = len(l:after_netloc)
	if l:allow_fragments
		let l:maybe_fragment_start = stridx(l:after_netloc, '#')
		if l:maybe_fragment_start >= 0
			let l:fragment_start = l:maybe_fragment_start
		endif
		let l:fragment = l:after_netloc[l:fragment_start + 1 :]
		let l:after_netloc = l:fragment_start > 0 ? l:after_netloc[: l:fragment_start - 1] : ''
	endif
	let l:query_start = len(l:after_netloc)
	let l:maybe_query_start = stridx(l:after_netloc, '?')
	if l:maybe_query_start >= 0
		let l:query_start = l:maybe_query_start
	endif
	let l:query = l:after_netloc[l:query_start + 1 :]
	let l:after_netloc = l:query_start > 0 ? l:after_netloc[: l:query_start - 1] : ''
	" TODO normalize & validate netloc?
	let l:path = l:after_netloc
	let l:params_start = -1
	if get(s:uses_params, l:scheme, v:false)
		let l:params_start = match(l:path, '\v\;[^\/]*$')
		if l:params_start >= 0
			let l:params = l:path[l:params_start + 1 :]
			let l:path = l:params_start > 0 ? l:path[: l:params_start - 1] : ''
		endif
	endif
	let l:result = {
		\ "has_scheme": l:scheme_end >= 0,
		\ "scheme": l:scheme,
		\ "has_netloc": l:has_netloc,
		\ "netloc": l:netloc,
		\ "path": l:path,
		\ "has_params": l:params_start >= 0,
		\ "params": l:params,
		\ "has_query": l:maybe_query_start >= 0,
		\ "query": l:query,
		\ "has_fragment": a:allow_fragments && l:maybe_fragment_start >= 0,
		\ "fragment": l:fragment,
		\ }
	let s:_parse_cache[l:cache_key] = l:result
	return copy(l:result)
endfunction

function! urrw#urlutil#urlunparse(parsed, ...)
	" Convert dictionary returned by urlparse into url string
	" If absolute is truish, don't skip missing components
	let l:absolute = v:false
	if a:0 >= 1
		let l:absolute = a:1
	endif
	let l:builder = []
	if l:absolute || a:parsed.has_scheme
		call add(l:builder, a:parsed.scheme)
		call add(l:builder, ':')
	endif
	if l:absolute || a:parsed.has_netloc
		call add(l:builder, '//')
		call add(l:builder, a:parsed.netloc)
	endif
	call add(l:builder, a:parsed.path)
	if (l:absolute && get(s:uses_params, a:parsed.scheme, v:false)) || a:parsed.has_params
		call add(l:builder, ';')
		call add(l:builder, a:parsed.params)
	endif
	if l:absolute || a:parsed.has_query
		call add(l:builder, '?')
		call add(l:builder, a:parsed.query)
	endif
	if l:absolute || a:parsed.has_fragment
		call add(l:builder, '#')
		call add(l:builder, a:parsed.fragment)
	endif
	return join(l:builder, '')
endfunction

function! urrw#urlutil#pathsimplify(path)
	" More aggressive than vim's simplify()
	" Performs percent reencoding, so when used with non-url paths, non-slash chracters should be percent-encoded
	let l:old = map(split(a:path, '/', 1), {_, n -> urrw#urlutil#decode_url_component(n)})
	let l:new = []
	for l:node in l:old
		if l:node == '.'
			continue
		endif
		if l:node == '..'
			while len(l:new) > 1 && l:new[-1] == '' 
				" Treat multiple slashes as a single slash when traversing up
				call remove(l:new, -1)
			endwhile
			if len(l:new) > 1 && l:new[-1] != '..'
				call remove(l:new, -1)
				continue
			elseif len(l:new) == 1
				if l:new[0] == ''
					" Root
					continue
				elseif l:new[0] == '.'
					call remove(l:new, -1)
					" Don't continue
				else
					" Relative
					if l:new[0] != '..'
						" Path shouldn't be an empty string
						" echom 'set dot ' . json_encode(l:new)
						let l:new[0] = '.'
						continue
					endif
				endif
				" Also relative
			endif
		endif
		call add(l:new, urrw#urlutil#encode_url_component(l:node))
	endfor
	if len(l:new) == 0
		" Path shouldn't be an empty string
		call add(l:new, '.')
		call add(l:new, '')
	endif
	return join(l:new, '/')
endfunction

function! urrw#urlutil#pathjoin(base, path)
	" Should /%2e/ and /%2e%2e/ be treated as /./ and /../ ?
	" If they should, how should %2f be treated in that case?
	" We only handle unix paths, i. e. absolute paths start with '/'
	" Should we also treat paths starting with <name>':/' as absolute?
	" Apply urljoin to them?
	" Example url: 'jdbc:sqlite:/some/path.sq3'
	"              'urn:ietf:rfc:2648'
	let l:scheme_or_disk_end = stridx(a:base, ':')
	if l:scheme_or_disk_end > 0
		let l:scheme_or_disk = a:base[: l:scheme_or_disk_end - 1]
		for l:c in split(l:scheme_or_disk, '\zs')
			if !urrw#urlutil#_is_scheme_char(l:c)
				let l:scheme_or_disk_end = -1
				let l:scheme_or_disk = ''
				break
			endif
		endfor
	endif
	if l:scheme_or_disk_end > 0
		return urrw#urlutil#urljoin(a:base, a:path)
	end
	let l:base = a:base
	if l:base[-1] != '/'
		" Filename should be removed
		let l:base .= '/../'
	endif
	if a:path[0] == '/'
		" Absolute path
		let l:base = ''
	endif
	let l:path = a:path
	let l:tmp = substitute(l:path[-7:], '\V\c%2e', '.', 'g')
	if l:tmp[-2:] == '/.' || l:tmp[-2:] == '.' || l:tmp[-3:] == '/..' || l:tmp[-3:] == '..'
		" '.' and '..' can only be directories
		let l:path .= '/'
	endif
	return urrw#urlutil#pathsimplify(l:base . l:path)
endfunction

function! urrw#urlutil#urljoin(base, url, ...)
	" urljoin together with pathjoin conform to examples from https://en.wikipedia.org/wiki/Uniform_Resource_Identifier#Resolution
	" Options
	"  * base_scheme - what scheme to use, if base doesn't have one
	"    useful vim value: 'file'
	"    Example:
	"        urrw#urlutil#urljoin(@%, l:new_url, {'base_scheme': 'file'})
	echo 'Enter urljoin' . json_encode([a:base, a:url])
	let l:options = {}
	if a:0 >= 1
		let l:options = a:1
	endif
	if type(a:base) != 1 || len(a:base) == 0
		if type(a:url) != 1
			return ''
		endif
		return a:url
	endif
	if type(a:url) != 1 || len(a:url) == 0
		if type(a:base) != 1
			return ''
		endif
		return a:base
	endif
	let l:parsed_base = urrw#urlutil#urlparse(a:base, get(l:options, 'base_scheme'), 1)
	echom 'l:parsed_base = ' . json_encode(l:parsed_base)
	let l:parsed_url = urrw#urlutil#urlparse(a:url, l:parsed_base.scheme, 1)
	if l:parsed_base.scheme != l:parsed_url.scheme
		" Should we add a non-standard way to switch protocols while preserving netloc
		return a:url
	end
	if get(s:uses_netloc, l:parsed_url.scheme, v:false)
		if l:parsed_url.has_netloc
			let l:parsed_url.has_scheme = l:parsed_url.has_scheme || l:parsed_base.has_scheme
			return urrw#urlutil#urlunparse(l:parsed_url)
		else
			let l:parsed_url.has_netloc = l:parsed_base.has_netloc
			let l:parsed_url.netloc = l:parsed_base.netloc
		endif
	endif
	if !l:parsed_url.has_params && len(l:parsed_url.path) == 0
		let l:parsed_url.path = l:parsed_base.path
		let l:parsed_url.has_params = l:parsed_base.has_params
		let l:parsed_url.params = l:parsed_base.params
		let l:parsed_url.has_scheme = l:parsed_url.has_scheme || l:parsed_base.has_scheme
		let l:parsed_url.has_netloc = get(s:uses_netloc, l:parsed_url.scheme, v:false)
		if !l:parsed_url.has_query
			let l:parsed_url.has_query = l:parsed_base.has_query
			let l:parsed_url.query = l:parsed_base.query
			if !l:parsed_url.has_fragment
				let l:parsed_url.has_fragment = l:parsed_base.has_fragment
				let l:parsed_url.fragment = l:parsed_base.fragment
			endif
		endif
		return urrw#urlutil#urlunparse(l:parsed_url)
	endif

	let l:parsed_url.path = urrw#urlutil#pathjoin(l:parsed_base.path, l:parsed_url.path)
	if len(l:parsed_base.path) == 0
		let l:parsed_url.has_params = l:parsed_base.has_params
		let l:parsed_url.params = l:parsed_base.params
	endif
	let l:parsed_url.has_scheme = l:parsed_url.has_scheme || l:parsed_base.has_scheme
	let l:parsed_url.has_netloc = l:parsed_url.has_netloc || l:parsed_url.has_scheme && get(s:uses_netloc, l:parsed_url.scheme, v:false)
	return urrw#urlutil#urlunparse(l:parsed_url)
endfunction

function! urrw#urlutil#decode_url_component(comp, ...)
	" Should we replace '+' with '%20' before decoding?
	let l:options = {}
	if a:0 >= 1
		let l:options = a:1
	endif
	let l:encoded = a:comp
	if get(l:options, 'space_plus', v:false)
		let l:encoded = substitute(l:encoded, '\V+', '%20', 'g')
	endif
	" return substitute(a:comp, '\v\%(\x{2})', {m -> nr2char(str2nr(m[1], 16), 0)}, 'g')
	" nr2char() doesn't work with bytes in neovim, but evaling string
	" literal allows to do it
	return substitute(l:encoded, '\v\%(\x{2})', {m -> eval(printf('"\x%s"', m[1]))}, 'g')
endfunction

function! s:str_to_char8_array(s)
	let l:arr = []
	for l:i in range(len(a:s))
		call add(l:arr, a:s[l:i])
	endfor
	return l:arr
endfunction

function! s:url_encode_all(s)
	let l:bytes = s:str_to_char8_array(a:s)
	call map(l:bytes, {_, c -> printf('%%%02X', char2nr(c))})
	return join(l:bytes, '')
endfunction

function! urrw#urlutil#encode_url_component(comp, ...)
	let l:options = {}
	if a:0 >= 1
		let l:options = a:1
	endif
	let l:ptn = get(l:options, 'char_re', '\v[^A-Za-z0-9.!~*' . "'" . '()_-]')
	let l:encoded = substitute(a:comp, l:ptn, {m -> s:url_encode_all(m[0])}, 'g')
	if get(l:options, 'space_plus', v:false)
		let l:encoded = substitute(l:encoded, '\V\c%20', '+', 'g')
	endif
	return l:encoded
endfunction

function! urrw#urlutil#encode_url_path_segment(seg)
	" Should we also preserve semicolons? How would work with parameters?
	return urrw#urlutil#encode_url_component(a:seg, {'char_re': '\v[^:@A-Za-z0-9.!$&~*+,=' . "'" . '()_-]'})
endfunction

function! urrw#urlutil#encode_url_path(path)
	return urrw#urlutil#encode_url_component(a:path, {'char_re': '\v[^/:@A-Za-z0-9.!$&~*+,=' . "'" . '()_-]'})
endfunction

function! urrw#urlutil#parse_netloc(netloc)
	" Splits the argument into components and decodes them:
	" (user (":" password)? "@")? (host | "[" host "]") (":" port)?
	" Only percent-encoding is decoded, punnycode isn't
	" has a boolean entry "host_bracketed"
	let l:userinfo_end = stridx(a:netloc, '@')
	let l:userinfo = l:userinfo_end > 0 ? a:netloc[: l:userinfo_end - 1] : ''
	let l:host_port = a:netloc[l:userinfo_end + 1 :]
	" Only 0 is allowed, we will move the brackets to host ends during
	" unparsing in case of broken url
	" Port cannot be bracketed
	let l:left_bracket_pos = stridx(l:host_port, '[')
	let l:is_host_bracketed = l:left_bracket_pos >= 0
	let l:after_right_bracket = 0
	if l:is_host_bracketed
		let l:after_right_bracket = stridx(l:host_port, ']', l:left_bracket_pos) + 1
	endif
	let l:host = l:host_port
	let l:port = ''
	let l:port_start = stridx(l:host_port, ':', l:after_right_bracket)
	if l:port_start >= 0
		let l:host = l:port_start > 0 ? l:host_port[: l:port_start - 1] : ''
		let l:port = l:host_port[l:port_start + 1 :]
	endif
	let l:host = substitute(l:host, '[\[\]]', '', 'g')
	" don't encode colons during unparsing if bracketed
	let l:host = urrw#urlutil#decode_url_component(l:host)
	" Port can only contain decimal digits, so decoding is not needed

	" It is used in ssh URI scheme draft & isn't a subset of the standard URL syntax, but may be useful for some applications
	let l:conn_params = ''
	let l:conn_params_start = stridx(l:userinfo, ';')
	if l:conn_params_start >= 0
		let l:conn_params = l:userinfo[l:conn_params_start + 1 :]
		let l:userinfo = l:conn_params_start > 0 ? l:userinfo[: l:conn_params_start - 1] : ''
	endif
	let l:conn_params_list = urrw#urlutil#parse_parameters(l:conn_params, ',')

	let l:user = l:userinfo
	let l:password = ''
	let l:password_start = stridx(l:userinfo, ':')
	if l:password_start >= 0
		let l:user = l:password_start > 0 ? l:userinfo[: l:password_start - 1] : ''
		let l:password = l:userinfo[l:password_start + 1 :]
	endif
	let l:user = urrw#urlutil#decode_url_component(l:user)
	let l:password = urrw#urlutil#decode_url_component(l:password)
	return {
		\ 'user': l:user,
		\ 'password': l:password,
		\ 'connection_params': l:conn_params_list,
		\ 'host_bracketed': l:is_host_bracketed,
		\ 'host': l:host,
		\ 'port': l:port,
		\ }
endfunction


function! urrw#urlutil#unparse_netloc(parsed)
	let l:user = get(a:parsed, 'user', '')
	let l:password = get(a:parsed, 'password', '')
	let l:conn_params_list = get(a:parsed, 'connection_params', [])
	let l:host = get(a:parsed, 'host', '')
	let l:port = get(a:parsed, 'port', '')
	let l:is_host_bracketed = get(a:parsed, 'host_bracketed', v:false)

	let l:user = urrw#urlutil#encode_url_component(l:user)
	let l:password = urrw#urlutil#encode_url_component(l:password)
	if l:is_host_bracketed
		let l:host = '[' . urrw#urlutil#encode_url_component(l:host, {
			\ 'char_re': '\v[^:A-Za-z0-9.!~*' . "'" . '()_-]',
			\ }) . ']'
	else
		let l:host = urrw#urlutil#encode_url_component(l:host)
	endif

	let l:userinfo = l:user
	if len(l:password) > 0
		let l:userinfo .= ':' . l:password
	endif
	let l:conn_params = urrw#urlutil#unparse_parameters(l:conn_params_list, ',')
	if len(l:conn_params) > 0
		let l:userinfo .= ';' . l:conn_params
	endif

	let l:host_port = l:host
	if len(l:port) > 0
		let l:host_port .= ':' . l:port
	endif

	return len(l:userinfo) > 0 ? l:userinfo . '@' . l:host_port : l:host_port
endfunction

function! urrw#urlutil#parse_parameters(params_string, param_delim)
	" Separates the string by delimiter param_delim (the most frequently used value is '&' used e. g. in http querys, but some URI schemes may also use ',' or ';')
	" If each parameter is converted into a singleton- or pair- list, depending on whether it contains '=' character, each list element is percent-decoded
	" These lists are stored into a single list that is returned by the function
	" This function doesn't define how repeated keys should be handled & whether parameters may be reordered, that's why it doesn't construct a dictionary
	let l:parsed = []
	let l:params_string = a:params_string
	while len(l:params_string) > 0
		let l:param_end = stridx(l:params_string, a:param_delim)
		if l:param_end >= 0
			" Use max for empty delimited (mainly to avoid infinite loop) (most likely is not useful)
			let l:param = l:param_end > 0 ? l:params_string[: l:param_end - len(a:param_delim)] : len(a:param_delim) > 0 ? '' : l:params_string[0]
			let l:params_string = l:params_string[l:param_end + max([len(a:param_delim), 1]) :]
		else
			let l:param = l:params_string
			let l:params_string = ''
		endif
		let l:key = l:param
		let l:value = v:null
		let l:value_start = stridx(l:param, '=')
		if l:value_start >= 0
			let l:key = l:value_start > 0 ? l:param[: l:value_start - 1] : ''
			let l:value = l:param[l:value_start + 1 :]
		endif

		let l:key = urrw#urlutil#decode_url_component(l:key)
		if type(l:value) == 1
			let l:value = urrw#urlutil#decode_url_component(l:value)
		endif

		let l:tup = type(l:value) == 1 ? [l:key, l:value] : [l:key]
		call add(l:parsed, l:tup)
	endwhile
	return l:parsed
endfunction

function! urrw#urlutil#unparse_parameters(parsed, param_delim)
	let l:builder = []
	for l:tup in a:parsed
		let l:param = join(map(copy(l:tup), {_, s -> urrw#urlutil#encode_url_component(s)}), '=')
		call add(l:builder, l:param)
	endfor
	return join(l:builder, a:param_delim)
endfunction

" Example:
" urrw#urlutil#urlunparse({'has_scheme': 1, 'scheme': 'zip', 'has_netloc': 1, 'netloc': urrw#urlutil#unparse_netloc({'host': 'https://example.com/archive.zip', 'host_bracketed': 1}), 'path': '/path/inside/archive/file.txt', 'has_params': 0, 'params': '', 'has_query': 0, 'query': 0, 'has_fragment': 1, 'fragment': ':2:10'})
" Gnome (gvfs) uses "archive" as url scheme & doesn't bracket the host, sometimes host may be encoded two times (?), but otherwise has the same url format
" Perhaps, archive+zip could be the optimal scheme?
" Colons in fragments can be used to tell vim line & column to place cursor at
" They are allowed fragment characters, but we are unlikely to use fragments as intended
" Also we can use double hash character to delimit url from line & column
