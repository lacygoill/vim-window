if exists('g:autoloaded_window')
    finish
endif
let g:autoloaded_window = 1

" Interface {{{1
fu window#disable_wrap_when_moving_to_vert_split(dir) abort "{{{2
    call setwinvar(winnr('#'), '&wrap', 0)
    exe 'wincmd '..a:dir
    setl nowrap
    return ''
endfu

fu window#navigate(dir) abort "{{{2
    " Purpose:{{{
    "
    "     $ vim -Nu NONE +'sp|vs|vs|wincmd l'
    "     :wincmd j
    "     :wincmd k
    "
    "     $ vim -Nu NONE +'vs|sp|sp|wincmd j'
    "     :wincmd l
    "     :wincmd h
    "
    " In both cases, you don't focus back the middle window; that's jarring.
    "}}}
    if s:previous_window_is_in_same_direction(a:dir)
        try | wincmd p | catch | return lg#catch() | endtry
    else
        try | exe 'wincmd '..a:dir | catch | return lg#catch() | endtry
    endif
endfu

fu s:previous_window_is_in_same_direction(dir) abort
    let [cnr, pnr] = [winnr(), winnr('#')]
    if a:dir is# 'h'
        let leftedge_current_window = win_screenpos(cnr)[1]
        let rightedge_previous_window = win_screenpos(pnr)[1] + winwidth(pnr) - 1
        return leftedge_current_window - 1 == rightedge_previous_window + 1
    elseif a:dir is# 'l'
        let rightedge_current_window = win_screenpos(cnr)[1] + winwidth(cnr) - 1
        let leftedge_previous_window = win_screenpos(pnr)[1]
        return rightedge_current_window + 1 == leftedge_previous_window - 1
    elseif a:dir is# 'j'
        let bottomedge_current_window = win_screenpos(cnr)[0] + winheight(cnr) - 1
        let topedge_previous_window = win_screenpos(pnr)[0]
        return bottomedge_current_window + 1 == topedge_previous_window - 1
    elseif a:dir is# 'k'
        let topedge_current_window = win_screenpos(cnr)[0]
        let bottomedge_previous_window = win_screenpos(pnr)[0] + winheight(pnr) - 1
        return topedge_current_window - 1 == bottomedge_previous_window + 1
    endif
endfu

fu window#preview_open() abort "{{{2
    " if we're already in the preview window, get back to previous window
    if &l:pvw
        wincmd p
        return
    endif

    " Try to display a possible tag under the cursor in a new preview window.
    try
        wincmd }
        wincmd P
        norm! zMzvzz
        wincmd p
    catch
        return lg#catch()
    endtry
endfu

fu window#quit_everything() abort "{{{2
    try
        " We must force the wiping the terminal buffers if we want to be able to quit.
        if !has('nvim')
            let term_buffers = term_list()
            if !empty(term_buffers)
                exe 'bw! '..join(term_buffers)
            endif
        endif
        qall
    catch
        let exception = string(v:exception)
        call timer_start(0, {-> execute(['echohl ErrorMsg', 'echo '..exception, 'echohl NONE'], '')})
        "                                                            │
        "                            can't use `string(v:exception)` ┘
        "
        " …  because when  the timer  will be  executed `v:exception`  will be
        " empty; we  need to save `v:exception`  in a variable: any  scope would
        " probably works, but a function-local one is the most local.
        " Here, it works because a lambda can access its outer scope.
        " This seems to indicate that the callback of a timer is executed in the
        " context of the function where it was started.
    endtry
endfu

fu window#resize(key) abort "{{{2
    let winnr = winnr()
    if a:key =~# '[hl]'
        " Why returning different keys depending on the position of the window?{{{
        "
        " `C-w <` moves a border of a vertical window:
        "
        "    - to the right, for the left border of the window on the far right
        "    - to the left, for the right border of other windows
        "
        " 2 reasons for these inconsistencies:
        "
        "    - Vim can't move the right border of the window on the far
        "      right, it would resize the whole “frame“, so it needs to
        "      manipulate the left border
        "
        "    - the left border of the  window on the far right is moved to
        "      the left instead of the right, to increase the visible size of
        "      the window, like it does in the other windows
        "}}}
        if winnr('l') != winnr
            let keys = a:key is# 'h'
                   \ ?     "\<c-w>3<"
                   \ :     "\<c-w>3>"
        else
            let keys = a:key is# 'h'
                   \ ?     "\<c-w>3>"
                   \ :     "\<c-w>3<"
        endif

    else
        if winnr('j') != winnr
            let keys = a:key is# 'k'
                   \ ?     "\<c-w>3-"
                   \ :     "\<c-w>3+"
        else
            let keys = a:key is# 'k'
                   \ ?     "\<c-w>3+"
                   \ :     "\<c-w>3-"
        endif
    endif

    call feedkeys(keys, 'in')
endfu

fu window#terminal_close() abort "{{{2
    let term_buffer = s:get_terminal_buffer()
    if term_buffer == 0 | return | endif
    let curwin = win_getid()
    noa call win_gotoid(bufwinid(term_buffer))
    noa call window#quit#main()
    noa call win_gotoid(curwin)
endfu

fu window#terminal_open() abort "{{{2
    let term_buffer = s:get_terminal_buffer()
    if term_buffer != 0
        let id = bufwinid(term_buffer)
        call win_gotoid(id)
        return
    endif

    let mod = lg#window#get_modifier()

    let how_to_open = has('nvim')
                  \ ?     mod..' split | terminal'
                  \ :     mod..' terminal'

    let resize = mod =~# '^vert'
             \ ?     ' | vert resize 30 | resize 30'
             \ :     ''

    exe printf('exe %s %s', string(how_to_open), resize)
endfu

fu window#zoom_toggle() abort "{{{2
    if winnr('$') == 1 | return | endif

    if exists('t:zoom_restore') && win_getid() == t:zoom_restore.winid
        exe get(t:zoom_restore, 'cmd', '')
        unlet t:zoom_restore
    else
        let t:zoom_restore = {'cmd': winrestcmd(), 'winid': win_getid()}
        wincmd |
        wincmd _
    endif
endfu

"}}}1
" Utilities {{{1
fu s:get_terminal_buffer() abort "{{{2
    let buflist = tabpagebuflist(tabpagenr())
    call filter(buflist, {_,v -> getbufvar(v, '&bt', '') is# 'terminal'})
    return get(buflist, 0 , 0)
endfu

