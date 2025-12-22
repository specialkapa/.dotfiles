if exists('g:autoloaded_db_adapter_sqlserver_azure_ad')
  finish
endif
let g:autoloaded_db_adapter_sqlserver_azure_ad = 1

function! s:server(url) abort
  let host = get(a:url, 'host', '')
  let port = get(a:url, 'port', '')
  if host ==# ''
    return ''
  endif
  return port ==# '' ? host : host . ',' . port
endfunction

function! s:param_bool(params, key) abort
  if !has_key(a:params, a:key)
    return 0
  endif
  let val = tolower(string(a:params[a:key]))
  return index(['1', 'true', 'yes', 'on'], val) >= 0
endfunction

function! s:database_from_path(url) abort
  let path = get(a:url, 'path', '')
  if empty(path)
    return ''
  endif
  if path[0] ==# '/'
    let path = path[1:]
  endif
  return path
endfunction

" --- REPL / :DB with no range ----------------------------------------
function! db#adapter#sqlserver#interactive(url) abort
  let l:url = db#url#parse(a:url)
  let l:params = get(l:url, 'params', {})
  let l:db = s:database_from_path(l:url)

  " Azure AD mode (sqlcmd -G)
  if has_key(l:params, 'azure_ad_auth')
    let l:cmd = ['sqlcmd', '-S', s:server(l:url)]

    if s:param_bool(l:params, 'encrypt')
      call add(l:cmd, '-N')
    endif
    if !empty(l:db)
      call extend(l:cmd, ['-d', l:db])
    endif

    call add(l:cmd, '-G')
    return l:cmd
  endif

  " Default behaviour
  let l:cmd = ['sqlcmd', '-S', s:server(l:url)]

  if s:param_bool(l:params, 'encrypt')
    call add(l:cmd, '-N')
  endif
  if s:param_bool(l:params, 'trustServerCertificate')
    call add(l:cmd, '-C')
  endif

  if has_key(l:url, 'user')
    call extend(l:cmd, ['-U', l:url.user])
    if has_key(l:url, 'password') && !empty(l:url.password)
      call extend(l:cmd, ['-P', l:url.password])
    endif
  else
    call add(l:cmd, '-E')
  endif

  if !empty(l:db)
    call extend(l:cmd, ['-d', l:db])
  endif

  return l:cmd
endfunction

" --- Non-interactive / file or range mode ----------------------------
" Used by :%DB, '<,'>DB, and DBUI when it detects an adapter #input().
function! db#adapter#sqlserver#input(url, input) abort
  let l:url = db#url#parse(a:url)
  let l:params = get(l:url, 'params', {})
  let l:db = s:database_from_path(l:url)

  " Azure AD mode (sqlcmd -G -i <file>)
  if has_key(l:params, 'azure_ad_auth')
    let l:cmd = ['sqlcmd', '-S', s:server(l:url)]

    if s:param_bool(l:params, 'encrypt')
      call add(l:cmd, '-N')
    endif
    if !empty(l:db)
      call extend(l:cmd, ['-d', l:db])
    endif

    call add(l:cmd, '-G')
    call extend(l:cmd, ['-i', a:input])
    return l:cmd
  endif

  " Default behaviour for non-Azure connections
  let l:cmd = ['sqlcmd', '-S', s:server(l:url)]

  if s:param_bool(l:params, 'encrypt')
    call add(l:cmd, '-N')
  endif
  if s:param_bool(l:params, 'trustServerCertificate')
    call add(l:cmd, '-C')
  endif

  if has_key(l:url, 'user')
    call extend(l:cmd, ['-U', l:url.user])
    if has_key(l:url, 'password') && !empty(l:url.password)
      call extend(l:cmd, ['-P', l:url.password])
    endif
  else
    call add(l:cmd, '-E')
  endif

  if !empty(l:db)
    call extend(l:cmd, ['-d', l:db])
  endif

  call extend(l:cmd, ['-i', a:input])
  return l:cmd
endfunction

