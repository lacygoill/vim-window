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

fu! s:get_terminal_buffer() abort "{{{1
    let buflist = tabpagebuflist(tabpagenr())
    call filter(buflist, {i,v -> getbufvar(v, '&bt', '') ==# 'terminal'})
    return get(buflist, 0 , 0)
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

fu! window#qf_open(type) abort "{{{1
    let we_are_in_qf = &l:bt ==# 'quickfix'

    if !we_are_in_qf
        "
        "   ┌ dictionary: {'winid': 42}
        "   │
        let id = a:type ==# 'loc'
        \            ?    getloclist(0, {'winid':0})
        \            :    getqflist(   {'winid':0})
        if get(id, 'winid', 0) == 0
            " Why :[cl]open? Are they valid commands here?{{{
            "
            " Probably not, because these commands  don't populate the qfl, they
            " just  open the  qf  window.
            "
            " However,  we  use   these  names  in  the   autocmd  listening  to
            " `QuickFixCmdPost` in `vim-qf`,  to decide whether we  want to open
            " the  qf window  unconditionally (:[cl]open),  or on  the condition
            " that the qfl contains at least 1 valid entry (`:[cl]window`).
            "
            " It allows us to do this in any plugin populating the qfl:
            "
            "         doautocmd <nomodeline> QuickFixCmdPost grep
            "             → open  the qf window  on the condition  it contains
            "               at  least 1 valid entry
            "
            "         doautocmd <nomodeline> QuickFixCmdPost copen
            "             → open the qf window unconditionally
            "}}}
            " Could we write sth simpler?{{{
            "
            " Yes:
            "         return (a:type ==# 'loc' ? 'l' : 'c').'open'
            "
            " But, it wouldn't  open the qf window like our  autocmd in `vim-qf`
            " does.
            "}}}
            exe 'doautocmd <nomodeline> QuickFixCmdPost '.(a:type ==# 'loc' ? 'l' : 'c').'open'
            return ''
        endif
        let id = id.winid

    " if we are already in the qf window, get back to the previous one
    elseif we_are_in_qf && a:type ==# 'qf'
            return 'wincmd p'

    " if we are already in the ll window, get to the associated window
    elseif we_are_in_qf && a:type ==# 'loc'
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
    let term_buffer = s:get_terminal_buffer()
    if term_buffer != 0
        noautocmd call win_gotoid(bufwinid(term_buffer))
        noautocmd call my_lib#quit()
        noautocmd wincmd p
    endif
endfu

fu! window#terminal_open() abort "{{{1
    let term_buffer = s:get_terminal_buffer()
    if term_buffer != 0
        let id = bufwinid(term_buffer)
        call win_gotoid(id)
        return
    endif

    let mod = window#get_modifier_to_open_window()

    let how_to_open = has('nvim')
    \?                    mod.' split | terminal'
    \:                    mod.' terminal'

    let resize = mod =~# '^vert'
    \?               ' | vert resize 30 | resize 30'
    \:               ''

    exe printf('exe %s %s', string(how_to_open), resize)
endfu
