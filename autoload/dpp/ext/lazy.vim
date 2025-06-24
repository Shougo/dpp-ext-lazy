function dpp#ext#lazy#_on_default_event(event) abort
  let lazy_plugins = dpp#util#_get_lazy_plugins()
  let plugins = []

  let path = '<afile>'->expand()
  " For ":edit ~".
  if path->fnamemodify(':t') ==# '~'
    let path = '~'
  endif
  let path = path->dpp#util#_expand()

  for filetype in &l:filetype->split('\.')
    let plugins += lazy_plugins->copy()
          \ ->filter({ _, val ->
          \   val->get('on_ft', [])
          \   ->dpp#util#_convert2list()
          \   ->index(filetype) >= 0
          \ })
  endfor

  let plugins += lazy_plugins->copy()
        \ ->filter({ _, val ->
        \   !(val->get('on_path', [])->dpp#util#_convert2list()->copy()
        \   ->filter({ _, val -> path =~? val })->empty())
        \ })
  let plugins += lazy_plugins->copy()
        \ ->filter({ _, val ->
        \   !(val->has_key('on_event')) && val->has_key('on_if')
        \   && val.on_if->eval()
        \ })

  call s:source_events(a:event, plugins)
endfunction
function dpp#ext#lazy#_on_event(event) abort
  let lazy_plugins = dpp#util#_get_lazy_plugins()
        \ ->filter({ _, val ->
        \   val->get('on_event', [])
        \   ->dpp#util#_convert2list()
        \   ->index(a:event) >= 0
        \ })
  if lazy_plugins->empty()
    if exists('##' .. a:event)
      execute 'autocmd! dpp-ext-lazy' a:event
    else
      execute 'autocmd! dpp-ext-lazy User' a:event
    endif
    return
  endif

  let plugins = lazy_plugins->copy()
        \ ->filter({ _, val ->
        \   !(val->has_key('on_if')) || val.on_if->eval()
        \ })
  call s:source_events(a:event, plugins)
endfunction
function s:source_events(event, plugins) abort
  if empty(a:plugins)
    return
  endif

  const prev_autocmd =
        \ ('autocmd ' .. (exists('##' .. a:event) ? '' : 'User ') .. a:event)
        \ ->execute()

  const sourced = dpp#source(a:plugins)
  if sourced->empty()
    return
  endif

  const new_autocmd =
        \ ('autocmd ' .. (exists('##' .. a:event) ? '' : 'User '))
        \ ->execute()

  if a:event ==# 'InsertCharPre'
    " Queue this key again
    call feedkeys(v:char)
    let v:char = ''
  else
    if '#BufReadCmd'->exists() && a:event ==# 'BufNew'
      " For BufReadCmd plugins
      silent! doautocmd <nomodeline> BufReadCmd
    endif
    if ('#' .. a:event)->exists() && prev_autocmd !=# new_autocmd
      execute 'silent! doautocmd <nomodeline>' a:event
    elseif ('#User#' .. a:event)->exists()
      execute 'silent! doautocmd <nomodeline> User' a:event
    endif
  endif
endfunction

function dpp#ext#lazy#_on_func(name) abort
  if a:name->stridx('dpp#') ==# 0
    return
  endif

  const function_prefix = a:name->substitute('[^#]*$', '', '')
  call dpp#source(dpp#util#_get_lazy_plugins()
        \ ->filter({ _, val ->
        \   function_prefix->stridx(
        \             val->dpp#util#_get_normalized_name() .. '#') == 0
        \   || val->get('on_func', [])
        \      ->dpp#util#_convert2list()
        \      ->index(a:name) == 0
        \ }), function_prefix)
endfunction

function dpp#ext#lazy#_on_lua(name, mod_root) abort
  if g:dpp#ext#_called_lua->has_key(a:name)
    return
  endif

  " Prevent infinite loop
  let g:dpp#ext#_called_lua[a:name] = v:true

  call dpp#source(dpp#util#_get_lazy_plugins()
        \ ->filter({ _, val ->
        \   val->get('on_lua', [])
        \   ->dpp#util#_convert2list()
        \   ->index(a:mod_root) >= 0
        \ }))
endfunction

function dpp#ext#lazy#_on_pre_cmd(command) abort
  if (':' .. a:command)->exists() == 2
    " Remove the dummy command.
    silent! execute 'delcommand' a:command
  endif

  call dpp#source(
        \ dpp#util#_get_lazy_plugins()
        \  ->filter({ _, val ->
        \    val->get('on_cmd', [])
        \    ->dpp#util#_convert2list()->copy()
        \    ->map({ _, val2 -> tolower(val2) })
        \    ->index(a:command->tolower()) >= 0
        \    || a:command->tolower()
        \    ->stridx(val->dpp#util#_get_normalized_name()->tolower()
        \    ->substitute('[_-]', '', 'g')) == 0
        \  }))
endfunction

function dpp#ext#lazy#_on_cmd(command, name, args, bang, line1, line2) abort
  if (':' .. a:command)->exists() == 2
    " Remove the dummy command.
    silent! execute 'delcommand' a:command
  endif

  call dpp#source(a:name)

  if (':' .. a:command)->exists() != 2
    call dpp#util#_error(printf('command %s is not found.', a:command))
    return
  endif

  const range = (a:line1 == a:line2) ? '' :
        \ (a:line1 == "'<"->line() && a:line2 == "'>"->line()) ?
        \ "'<,'>" : a:line1 .. ',' .. a:line2

  try
    execute range.a:command.a:bang a:args
  catch /^Vim\%((\a\+)\)\=:E481/
    " E481: No range allowed
    execute a:command.a:bang a:args
  endtry
endfunction

function dpp#ext#lazy#_on_map(mapping, name, mode) abort
  const cnt = v:count > 0 ? v:count : ''

  const input = s:get_input()

  const sourced = dpp#source(a:name)
  if sourced->empty()
    " Prevent infinite loop
    silent! execute a:mode.'unmap' a:mapping
  endif

  if a:mode ==# 'v' || a:mode ==# 'x'
    call feedkeys('gv', 'n')
  elseif a:mode ==# 'o' && v:operator !=# 'c'
    const save_operator = v:operator
    call feedkeys("\<Esc>", 'in')

    " Cancel waiting operator mode.
    call feedkeys(save_operator, 'imx')
  endif

  call feedkeys(cnt, 'n')

  if a:mode ==# 'o' && v:operator ==# 'c'
    " NOTE: This is the dirty hack.
    execute s:mapargrec(a:mapping .. input, a:mode)->matchstr(
          \ ':<C-u>\zs.*\ze<CR>')
  else
    let mapping = a:mapping
    while mapping =~# '<[[:alnum:]_-]\+>'
      let mapping = mapping->substitute('\c<Leader>',
            \ g:->get('mapleader', '\'), 'g')
      let mapping = mapping->substitute('\c<LocalLeader>',
            \ g:->get('maplocalleader', '\'), 'g')
      let ctrl = mapping->matchstr('<\zs[[:alnum:]_-]\+\ze>')
      execute 'let mapping = mapping->substitute(
            \ "<' .. ctrl .. '>", "\<' .. ctrl .. '>", "")'
    endwhile

    if a:mode ==# 't'
      call feedkeys('i', 'n')
    endif
    call feedkeys(mapping .. input, 'm')
  endif

  return ''
endfunction

function dpp#ext#lazy#_on_root() abort
  for plugin in dpp#util#_get_lazy_plugins()
        \  ->filter({ _, val -> !val->get('on_root', [])->empty() })

    for root in plugin.on_root->dpp#util#_convert2list()
      if !root->findfile(';')->empty()
        call dpp#source(plugin.name)
        break
      endif
    endfor
  endfor
endfunction


function! s:get_input() abort
  let input = ''
  const termstr = '<M-_>'

  call feedkeys(termstr, 'n')

  while 1
    let char = getchar()
    let input ..= (char->type() == v:t_number) ? char->nr2char() : char

    let idx = input->stridx(termstr)
    if idx >= 1
      let input = input[: idx - 1]
      break
    elseif idx == 0
      let input = ''
      break
    endif
  endwhile

  return input
endfunction

function dpp#ext#lazy#_dummy_complete(arglead, cmdline, cursorpos) abort
  " Load plugins
  call dpp#ext#lazy#_on_pre_cmd(a:cmdline->matchstr('\h\w*'))

  return a:arglead
endfunction

function s:mapargrec(map, mode) abort
  let arg = a:map->maparg(a:mode)
  while arg->maparg(a:mode) !=# ''
    let arg = arg->maparg(a:mode)
  endwhile
  return arg
endfunction

function dpp#ext#lazy#_generate_dummy_commands(plugin) abort
  let dummys = []
  let state_lines = []

  for name in a:plugin->get('on_cmd', [])->dpp#util#_convert2list()
        \ ->filter({ _, val -> val =~# '^\h\w*$' })
    " Define dummy commands.
    let raw_cmd = 'silent! command '
          \ .. '-complete=custom,dpp#ext#lazy#_dummy_complete'
          \ .. ' -bang -bar -range -nargs=* ' .. name
          \ .. printf(" call dpp#ext#lazy#_on_cmd(%s, %s, <q-args>,
          \  '<bang>'->expand(), '<line1>'->expand(), '<line2>'->expand())",
          \   name->string(), a:plugin.name->string())

    call add(dummys, name)
    call add(state_lines, raw_cmd)
  endfor

  return #{
        \   dummys: dummys,
        \   stateLines: state_lines,
        \ }
endfunction
function dpp#ext#lazy#_generate_dummy_mappings(plugin) abort
  let state_lines = []
  let dummys = []
  let state_lines = []
  const normalized_name = a:plugin->dpp#util#_get_normalized_name()
  const on_map = a:plugin->get('on_map', [])

  let items =
        \ on_map->type() == v:t_string ? [[['n', 'x', 'o'], [on_map]]] :
        \ on_map->type() == v:t_dict ?
        \ on_map->items()->map({ _, val -> [val[0]->split('\zs'),
        \       val[1]->dpp#util#_convert2list()]}) :
        \ on_map->copy()->map({ _, val -> type(val) == v:t_list ?
        \       [val[0]->split('\zs'), val[1:]] :
        \       [['n', 'x', 'o'], [val]]
        \  })

  for [modes, mappings] in items
    if mappings ==# ['<Plug>']
      " Use plugin name.
      let mappings = ['<Plug>(' .. normalized_name]
      if normalized_name->stridx('-') >= 0
        " The plugin mappings may use "_" instead of "-".
        call add(mappings, '<Plug>('
              \ .. normalized_name->substitute('-', '_', 'g'))
      endif
    endif

    for mapping in mappings
      " Define dummy mappings.
      let prefix = printf('dpp#ext#lazy#_on_map(%s, %s,',
            \ mapping->substitute('<', '<lt>', 'g')->string(),
            \ a:plugin.name->string())
      for mode in modes
        let escape = has('nvim') ? "\<C-\>\<C-n>" : "\<C-l>N"
        let raw_map = mode.'noremap <unique><silent> '.mapping
              \ .. (mode ==# 'c' ? " \<C-r>=" :
              \     mode ==# 'i' ? " \<C-o>:call " :
              \     mode ==# 't' ? " " .. escape .. ":call " :
              \     " :\<C-u>call ")
              \ .. prefix .. mode->string() .. ')<CR>'

        call add(dummys, [mode, mapping])
        call add(state_lines, raw_map)
      endfor
    endfor
  endfor

  return #{
        \   dummys: dummys,
        \   stateLines: state_lines,
        \ }
endfunction
function dpp#ext#lazy#_generate_on_lua(plugin) abort
  return a:plugin.on_lua
        \ ->dpp#util#_convert2list()
        \ ->map({ _, val -> val->matchstr('^[^./]\+') })
        \ ->map({ _, mod ->
        \   printf("let g:dpp#ext#_on_lua_plugins[%s] = v:true",
        \          mod->string())
        \ })
endfunction
