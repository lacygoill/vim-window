fu! window#disable_wrap_when_moving_to_vert_split(dir) abort "{{{1
    call setwinvar(winnr('#'), '&wrap', 0)
    exe 'wincmd '.a:dir
    setl nowrap
    return ''
endfu

fu! s:get_terminal_buffer() abort "{{{1
    let buflist = tabpagebuflist(tabpagenr())
    call filter(buflist, {i,v -> getbufvar(v, '&bt', '') is# 'terminal'})
    return get(buflist, 0 , 0)
endfu

fu! window#navigate(dir) abort "{{{1
    try
        exe 'wincmd '.a:dir
    catch
        return lg#catch_error()
    endtry
endfu

fu! window#preview_open() abort "{{{1
    " if we're already in the preview window, get back to previous window
    if &l:pvw
        wincmd p
        return
    endif

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
        return lg#catch_error()
    endtry
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

fu! window#resize(key) abort "{{{1
    let orig_win = winnr()

    if a:key =~# '[hl]'
        noautocmd wincmd l
        let new_win = winnr()
        exe 'noautocmd '.orig_win.'wincmd w'

        let on_far_right = new_win != orig_win

        " Why returning different keys depending on the position of the window?{{{
        "
        " `C-w <` moves a border of a vertical window:
        "
        "     • to the right, for the left  border of the   window  on the far right
        "     • to the left,  for the right border of other windows
        "
        " 2 reasons for these inconsistencies:
        "
        "     • Vim can't move the right border of the window on the far
        "       right, it would resize the whole “frame“, so it needs to
        "       manipulate the left border
        "
        "     • the left border of the  window on the far right is moved to
        "       the left instead of the right, to increase the visible size of
        "       the window, like it does in the other windows
        "}}}
        if on_far_right
            let keys = a:key is# 'h'
            \?             "\<c-w>3<"
            \:             "\<c-w>3>"
        else
            let keys = a:key is# 'h'
            \?             "\<c-w>3>"
            \:             "\<c-w>3<"
        endif

    else
        noautocmd wincmd j
        let new_win = winnr()
        exe 'noautocmd '.orig_win.'wincmd w'

        let on_far_bottom = new_win != orig_win

        if on_far_bottom
            let keys = a:key is# 'k'
            \?             "\<c-w>3-"
            \:             "\<c-w>3+"
        else
            let keys = a:key is# 'k'
            \?             "\<c-w>3+"
            \:             "\<c-w>3-"
        endif
    endif

    call feedkeys(keys, 'in')
endfu

fu! window#scroll_preview(is_fwd) abort "{{{1
    if empty(filter(map(range(1, winnr('$')),
    \                   { i,v -> getwinvar(v, '&l:pvw') }),
    \               { i,v -> v ==# 1 }))
        sil! unmap <buffer> J
        sil! unmap <buffer> K
        sil! exe 'norm! '.(a:is_fwd ? 'J' : 'K')
    else
        " go to preview window
        noa exe "norm! \<c-w>P"
        "                              ┌ scroll down
        "                         ┌────┤
        exe 'norm! '.(a:is_fwd ? "\<c-e>L" : "\<c-y>H")
        "                               │
        "                               └ go to last line of window

        " unfold and get back
        " note: for some reason the double backticks breaks `J`,
        " that's why we don't use it when we move forward
        exe 'norm! zv'.(a:is_fwd ? '' : '``')
        " get back to previous window
        noa exe "norm! \<c-w>p"
    endif
    return ''
endfu

fu! window#terminal_close() abort "{{{1
    let term_buffer = s:get_terminal_buffer()
    if term_buffer != 0
        noa call win_gotoid(bufwinid(term_buffer))
        " Why executing this autocmd?{{{
        "
        " In a terminal buffer, we disable the meta keys. When we give the focus
        " to another buffer, BufLeave is fired, and a custom autocmd restores the
        " meta keys.
        "
        " But if we're in the terminal window when we press `z>` to close it,
        " BufLeave hasn't been fired yet since the meta keys were disabled.
        "
        " So, they are not re-enabled. We need to make sure the autocmd is fired
        " before wiping the terminal buffer with `lg#window#quit()`.
        "}}}
        " Why checking its existence?{{{
        "
        " We don't install it in Neovim.
        "}}}
        if exists('#toggle_keysyms_in_terminal#bufleave')
            do toggle_keysyms_in_terminal BufLeave
        endif
        noa call lg#window#quit()
        noa wincmd p
    endif
endfu

fu! window#terminal_open() abort "{{{1
    let term_buffer = s:get_terminal_buffer()
    if term_buffer != 0
        let id = bufwinid(term_buffer)
        call win_gotoid(id)
        return
    endif

    let mod = lg#window#get_modifier()

    let how_to_open = has('nvim')
    \?                    mod.' split | terminal'
    \:                    mod.' terminal'

    let resize = mod =~# '^vert'
    \?               ' | vert resize 30 | resize 30'
    \:               ''

    exe printf('exe %s %s', string(how_to_open), resize)
endfu
