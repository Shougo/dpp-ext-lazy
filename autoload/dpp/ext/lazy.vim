function dpp#ext#lazy#_on_default_event(event) abort
  let idx = s:get_index()
  let plugins = []

  let path = '<afile>'->expand()
  " For ":edit ~".
  if path->fnamemodify(':t') ==# '~'
    let path = '~'
  endif
  let path = path->dpp#util#_expand()

  const ft_list = &l:filetype ==# '' ? [] : &l:filetype->split('\.')
  if !ft_list->empty()
    let ft_seen = {}
    for ft in ft_list
      for plugin in idx.by_ft->get(ft, [])
        if !ft_seen->has_key(plugin.name)
          let ft_seen[plugin.name] = v:true
          call add(plugins, plugin)
        endif
      endfor
    endfor
  endif

  for plugin in idx.on_path
    if !(plugin->get('on_path', [])->dpp#util#_convert2list()
          \ ->filter({ _, p -> path =~? p })->empty())
      call add(plugins, plugin)
    endif
  endfor
  for plugin in idx.on_if
    if plugin.on_if->eval()
      call add(plugins, plugin)
    endif
  endfor

  call s:source_events(a:event, plugins)
endfunction
function dpp#ext#lazy#_on_event(event) abort
  const has_event = exists('##' .. a:event)
  let event_plugins = s:get_index().by_event->get(a:event, [])
  if event_plugins->empty()
    if has_event
      execute 'autocmd! dpp-ext-lazy-on_event' a:event
    else
      execute 'autocmd! dpp-ext-lazy-on_event User' a:event
    endif
    return
  endif

  let plugins = []
  for plugin in event_plugins
    if !plugin->has_key('on_if') || plugin.on_if->eval()
      call add(plugins, plugin)
    endif
  endfor
  call s:source_events(a:event, plugins)
endfunction
function s:source_events(event, plugins) abort
  if empty(a:plugins)
    return
  endif

  const has_event = exists('##' .. a:event)
  const already_sourced = g:dpp#ext#lazy#sourced_events
        \ ->get(a:event, v:false)
  const prev_autocmd = already_sourced ? ''
        \ : ('autocmd ' .. (has_event ? '' : 'User ') .. a:event)
        \   ->execute()

  const sourced = dpp#source(a:plugins)
  if sourced->empty()
    return
  endif

  let g:dpp#ext#lazy#sourced_events[a:event] = v:true

  const new_autocmd = already_sourced ? ''
        \ : ('autocmd ' .. (has_event ? '' : 'User '))->execute()

  if a:event ==# 'InsertCharPre'
    " Queue this key again
    call feedkeys(v:char)
    let v:char = ''
  else
    if '#BufReadCmd'->exists() && a:event ==# 'BufNew'
      " For BufReadCmd plugins
      silent! doautocmd <nomodeline> BufReadCmd
    endif
    if ('#' .. a:event)->exists()
          \ && (already_sourced || prev_autocmd !=# new_autocmd)
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

  const key = a:name->matchstr('^[^#]*', '', '')
  if has_key(g:dpp#ext#_called_vim, key)
    return
  endif

  " To prevent infinite loop.
  let g:dpp#ext#_called_vim[key] = v:true

  const function_prefix = a:name->substitute('[^#]*$', '', '')
  let plugins = []
  let seen = {}
  let idx = s:get_index()

  " by_func_prefix: function_prefix starts with norm#
  " (only when there is a #)
  if function_prefix !=# ''
    const func_prefix_key = a:name->matchstr('^[^#]\+')
    for plugin in idx.by_func_prefix->get(func_prefix_key, [])
      if !seen->has_key(plugin.name)
        let seen[plugin.name] = v:true
        call add(plugins, plugin)
      endif
    endfor
  endif

  " by_func_name: on_func[0] == a:name
  " (preserves original ->index() == 0 semantics)
  for plugin in idx.by_func_name->get(a:name, [])
    if !seen->has_key(plugin.name)
      let seen[plugin.name] = v:true
      call add(plugins, plugin)
    endif
  endfor

  if plugins->empty()
    return
  endif

  call dpp#source(plugins, function_prefix)
endfunction

function dpp#ext#lazy#_on_lua(name, mod_root) abort
  if g:dpp#ext#_called_lua->has_key(a:mod_root)
    return
  endif

  " Prevent infinite loop
  let g:dpp#ext#_called_lua[a:mod_root] = v:true

  call dpp#source(s:get_index().by_lua->get(a:mod_root, []))
endfunction

function dpp#ext#lazy#_on_pre_cmd(command) abort
  if (':' .. a:command)->exists() == 2
    " Remove the dummy command.
    silent! execute 'delcommand' a:command
  endif

  const lower_cmd = a:command->tolower()
  let idx = s:get_index()

  " Collect plugins matching by exact on_cmd entry (O(1) lookup)
  let seen = {}
  let plugins = []
  for plugin in idx.by_cmd->get(lower_cmd, [])
    let seen[plugin.name] = v:true
    call add(plugins, plugin)
  endfor

  " Collect plugins matching by compact normalized name prefix
  " Use the first-char map to avoid scanning the full prefix list
  if !lower_cmd->empty()
    const first = lower_cmd[0]
    for [cmd_prefix_key, plugin] in idx.cmd_prefix_map->get(first, [])
      if !seen->has_key(plugin.name) && lower_cmd->stridx(cmd_prefix_key) == 0
        let seen[plugin.name] = v:true
        call add(plugins, plugin)
      endif
    endfor
  endif

  call dpp#source(plugins)
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
  const leader = g:->get('mapleader', '\')
  const localleader = g:->get('maplocalleader', '\')
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
      let mapping = mapping->substitute('\c<Leader>', leader, 'g')
      let mapping = mapping->substitute('\c<LocalLeader>', localleader, 'g')
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
  for plugin in s:get_index().on_root
    for root in plugin.on_root->dpp#util#_convert2list()
      if !root->findfile(';')->empty()
        call dpp#source(plugin.name)
        break
      endif
    endfor
  endfor
endfunction


function! s:get_index() abort
  if !exists('g:dpp#ext#lazy#index')
    call s:build_index()
  endif
  return g:dpp#ext#lazy#index
endfunction

function! s:build_index() abort
  if !exists('g:dpp#ext#lazy#sourced_events')
    let g:dpp#ext#lazy#sourced_events = {}
  endif

  let idx = #{
        \   by_event: {},
        \   by_ft: {},
        \   by_cmd: {},
        \   by_lua: {},
        \   by_func_prefix: {},
        \   by_func_name: {},
        \   on_path: [],
        \   on_if: [],
        \   on_root: [],
        \   cmd_prefix: [],
        \   cmd_prefix_map: {},
        \ }

  for plugin in dpp#util#_get_lazy_plugins()
    " by_event
    for event in plugin->get('on_event', [])->dpp#util#_convert2list()
      if !idx.by_event->has_key(event)
        let idx.by_event[event] = []
      endif
      call add(idx.by_event[event], plugin)
    endfor

    " by_ft
    for ft in plugin->get('on_ft', [])->dpp#util#_convert2list()
      if !idx.by_ft->has_key(ft)
        let idx.by_ft[ft] = []
      endif
      call add(idx.by_ft[ft], plugin)
    endfor

    " by_cmd (keyed by lowercased command name)
    for cmd in plugin->get('on_cmd', [])->dpp#util#_convert2list()
      let lower_cmd = cmd->tolower()
      if !idx.by_cmd->has_key(lower_cmd)
        let idx.by_cmd[lower_cmd] = []
      endif
      call add(idx.by_cmd[lower_cmd], plugin)
    endfor

    " by_lua (keyed by on_lua entry as-is, matching _on_lua's a:mod_root)
    for mod in plugin->get('on_lua', [])->dpp#util#_convert2list()
      if !idx.by_lua->has_key(mod)
        let idx.by_lua[mod] = []
      endif
      call add(idx.by_lua[mod], plugin)
    endfor

    " by_func_prefix: all plugins keyed by normalized name
    " (hyphens -> underscores)
    let func_prefix_norm = plugin->dpp#util#_get_normalized_name()
          \ ->substitute('-', '_', 'g')
    if !idx.by_func_prefix->has_key(func_prefix_norm)
      let idx.by_func_prefix[func_prefix_norm] = []
    endif
    call add(idx.by_func_prefix[func_prefix_norm], plugin)

    " by_func_name: keyed by on_func[0]
    " (preserves original ->index()==0 semantics)
    let on_func_list = plugin->get('on_func', [])->dpp#util#_convert2list()
    if !on_func_list->empty()
      let func0 = on_func_list[0]
      if !idx.by_func_name->has_key(func0)
        let idx.by_func_name[func0] = []
      endif
      call add(idx.by_func_name[func0], plugin)
    endif

    " on_path: plugins with on_path patterns
    " (need runtime pattern matching)
    if !plugin->get('on_path', [])->dpp#util#_convert2list()->empty()
      call add(idx.on_path, plugin)
    endif

    " on_if: plugins with on_if but without on_event
    if !plugin->has_key('on_event') && plugin->has_key('on_if')
      call add(idx.on_if, plugin)
    endif

    " cmd_prefix: [cmd_prefix_key, plugin]
    " pairs for prefix matching in _on_pre_cmd
    let cmd_prefix_key = plugin->dpp#util#_get_normalized_name()
          \ ->tolower()->substitute('[_-]', '', 'g')
    call add(idx.cmd_prefix, [cmd_prefix_key, plugin])
    " cmd_prefix_map: keyed by first character for faster lookup
    if !cmd_prefix_key->empty()
      let cmd_prefix_first = cmd_prefix_key[0]
      if !idx.cmd_prefix_map->has_key(cmd_prefix_first)
        let idx.cmd_prefix_map[cmd_prefix_first] = []
      endif
      call add(idx.cmd_prefix_map[cmd_prefix_first], [cmd_prefix_key, plugin])
    endif

    " on_root: plugins with on_root entries
    if !plugin->get('on_root', [])->dpp#util#_convert2list()->empty()
      call add(idx.on_root, plugin)
    endif
  endfor

  let g:dpp#ext#lazy#index = idx
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
        \ on_map->items()->mapnew({ _, val -> [val[0]->split('\zs'),
        \       val[1]->dpp#util#_convert2list()]}) :
        \ on_map->mapnew({ _, val -> type(val) == v:t_list ?
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
