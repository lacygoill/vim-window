fu! window#disable_wrap_when_moving_to_vert_split(dir) abort "{{{1
    call setwinvar(winnr('#'), '&wrap', 0)
    exe 'wincmd '.a:dir
    setl nowrap
    return ''
endfu

fu! window#get_modifier_to_open_window() abort "{{{1
"   └─────┤
"         └ public so that it can be called in `vim-qf` (`qf#open()` in autoload/),
"           and in our vimrc
    let origin = winnr()

    " are we at the bottom of the tabpage?
    noautocmd wincmd b
    if winnr() == origin
        let mod = 'botright'
    else
        noautocmd wincmd p
        " or maybe at the top?
        noautocmd wincmd t
        if winnr() == origin
            let mod = 'topleft'
        else
            " ok we're in a middle window
            noautocmd wincmd p
            let mod = 'vert belowright'
        endif
    endif

    return mod
endfu

fu! window#navigate(dir) abort "{{{1
    try
        exe 'wincmd '.a:dir
    catch
        return my_lib#catch_error()
    endtry
endfu

fu! window#preview_open() abort "{{{1
    " Check whether a preview window is already opened in the current tab page.
    let win_ids = gettabinfo(tabpagenr())[0].windows
    call filter(win_ids, {i,v -> getwinvar(v, '&pvw', 0)})
    " If there's one, give it the focus.
    if !empty(win_ids)
        call win_gotoid(win_ids[0])
        return
    endif
    " Otherwise, let's try to  display a possible tag under the  cursor in a new
    " preview window.
    try
        exe "norm! \<c-w>}\<c-w>PzMzvzz\<c-w>p"
        " OLD:{{{
        "
        " Previously, we mapped  this function to 2 mappings: z< and z{
        " Each one passed a different argument (`auto_close`) to the function.
        " When the  argument, `auto_close`,  was 1, we  installed an  autocmd to
        " automatically close the preview window when we moved the cursor.
        "
        "     if a:auto_close
        "         augroup close_preview_after_motion
        "             au!
        "             "              ┌─ don't use `<buffer>` because I suspect `CursorMoved`
        "             "              │  could happen in another buffer; example, after `gf`
        "             "              │  or sth similar
        "             "              │  we want the preview window to be closed no matter
        "             "              │  where the cursor moves
        "             "              │
        "             au CursorMoved * pclose
        "                           \| wincmd _
        "                           \| exe 'au! close_preview_after_motion'
        "                           \| aug! close_preview_after_motion
        "         augroup END
        "     endif
        "
        " I think  that was too much. One  mapping should be enough. It  frees a
        " key binding, and restores symmetry. Indeed, `z>` was not used.
        "}}}
    catch
        return my_lib#catch_error()
    endtry
endfu

fu! window#qf_open(type, focus_qf) abort "{{{1
    " Can we use `wincmd p` to focus the qf window, after populating a qfl?{{{
    "
    " No. It's not reliable.
    "
    " For example, suppose we've executed a command which has populated the qfl,
    " and opened  the qf  window. The previous  window will,  indeed, be  the qf
    " window. Because it  seems that after  Vim has opened  it, it gets  back to
    " whatever window we were originally in.
    "
    " But  then,  from  the  qf  window,  suppose  we  execute  another  command
    " populating the  qfl.  This time,  the qf window  will NOT be  the previous
    " window but the current one.
    "}}}

    " a:focus_qf == 0 && a:type ==# 'qf'
    if a:type ==# 'qf' && !a:focus_qf
        return 'wincmd p'
    endif

    " a:focus_qf == 1 && a:type ==# 'qf'
    " a:focus_qf == 1 && a:type ==# 'loc'
    if a:focus_qf
        "
        "   ┌ dictionary: {'winid': 42}
        "   │
        let id = call(a:type ==# 'loc'
        \                ?    'getloclist'
        \                :    'getqflist',
        \                a:type ==# 'loc'
        \                ?    [0, {'winid':0}]
        \                :    [   {'winid':0}])
        if empty(id)
            return (a:type ==# 'loc' ? 'l' : 'c').'window'
        endif
        let id = id.winid

    " a:focus_qf == 0 && a:type ==# 'loc'
    else
        let win_ids = gettabinfo(tabpagenr())[0].windows
        let loc_id  = win_getid()
        let id      = get(filter(copy(win_ids), {i,v ->    get(getloclist(v, {'winid': 0}), 'winid', 0)
        \                                               == loc_id
        \                                               && v != loc_id })
        \                 ,0,0)
    endif

    if id != 0
        call win_gotoid(id)
    endif
    return ''
endfu

fu! window#quit_everything() abort "{{{1
    try
        " We must force the wiping the terminal buffers if we want to be able to quit.
        if !has('nvim')
            let term_buffers = term_list()
            if !empty(term_buffers)
                exe 'bw! '.join(term_buffers)
            endif
        endif
        qall
    catch
        let exception = string(v:exception)
        call timer_start(0, {-> execute('echohl ErrorMsg | echo '.exception.' | echohl NONE', '')})
        "                                                         │
        "                         can't use `string(v:exception)` ┘
        "
        " …  because when  the timer  will be  executed `v:exception`  will be
        " empty; we  need to save `v:exception`  in a variable: any  scope would
        " probably works, but a function-local one is the most local.
        " Here, it works because a lambda can access its outer scope.
        " This seems to indicate that the callback of a timer is executed in the
        " context of the function where it was started.
    endtry
endfu

fu! window#scroll_preview(fwd) abort "{{{1
    if empty(filter(map(range(1, winnr('$')),
    \                   { i,v -> getwinvar(v, '&l:pvw') }),
    \               { i,v -> v == 1 }))
        sil! unmap <buffer> J
        sil! unmap <buffer> K
        sil! exe 'norm! '.(a:fwd ? 'J' : 'K')
    else
        " go to preview window
        exe "norm! \<c-w>P"
        "                           ┌ scroll down
        "                      ┌────┤
        exe 'norm! '.(a:fwd ? "\<c-e>L" : "\<c-y>H")
        "                            │
        "                            └ go to last line of window

        " unfold and get back
        " note: for some reason the double backticks breaks `J`,
        " that's why we don't use it when we move forward
        exe 'norm! zv'.(a:fwd ? '' : '``')
        " get back to previous window
        exe "norm! \<c-w>p"
    endif
    return ''
endfu

fu! window#terminal_close() abort "{{{1
    let buflist = tabpagebuflist(tabpagenr())
    call filter(buflist, {i,v -> getbufvar(v, '&bt', '') ==# 'terminal'})
    if !empty(buflist)
        noautocmd call win_gotoid(bufwinid(buflist[0]))
        noautocmd call my_lib#quit()
        noautocmd wincmd p
    endif
endfu

fu! window#terminal_open() abort "{{{1
    let mod = window#get_modifier_to_open_window()

    let how_to_open = has('nvim')
    \?                    mod.' split | terminal'
    \:                    mod.' terminal'

    let resize = mod =~# '^vert'
    \?               ' | vert resize 30 | resize 30'
    \:               ''

    exe printf('exe %s %s', string(how_to_open), resize)
endfu
