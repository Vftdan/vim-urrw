function! TestUrljoin()
	" https://en.wikipedia.org/wiki/Uniform_Resource_Identifier#Resolution
	let l:old_errors = v:errors
	try
		let l:base = 'http://a/b/c/d;p?q'
		let l:cases = [
			\ ['g:h'    , 'g:h'],
			\ ['g'      , 'http://a/b/c/g'],
			\ ['./g'    , 'http://a/b/c/g'],
			\ ['g/'     , 'http://a/b/c/g/'],
			\ ['/g'     , 'http://a/g'],
			\ ['//g'    , 'http://g'],
			\ ['?y'     , 'http://a/b/c/d;p?y'],
			\ ['g?y'    , 'http://a/b/c/g?y'],
			\ ['#s'     , 'http://a/b/c/d;p?q#s'],
			\ ['g#s'    , 'http://a/b/c/g#s'],
			\ ['g?y#s'  , 'http://a/b/c/g?y#s'],
			\ [';x'     , 'http://a/b/c/;x'],
			\ ['g;x'    , 'http://a/b/c/g;x'],
			\ ['g;x?y#s', 'http://a/b/c/g;x?y#s'],
			\ [''       , 'http://a/b/c/d;p?q'],
			\ ['.'      , 'http://a/b/c/'],
			\ ['./'     , 'http://a/b/c/'],
			\ ['..'     , 'http://a/b/'],
			\ ['../'    , 'http://a/b/'],
			\ ['../g'   , 'http://a/b/g'],
			\ ['../..'  , 'http://a/'],
			\ ['../../' , 'http://a/'],
			\ ['../../g', 'http://a/g'],
			\ ]
		for [l:rel, l:res] in l:cases
			call assert_equal(l:res, urrw#urlutil#urljoin(l:base, l:rel))
		endfor
		echohl ErrorMsg
		for l:e in v:errors
			echom l:e
		endfor
		echohl None
	finally
		let v:errors = l:old_errors
	endtry
endfunction
