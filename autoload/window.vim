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
        call my_lib#catch_error()
    endtry
endfu

fu! window#open_preview() abort "{{{1
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
        call my_lib#catch_error()
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
