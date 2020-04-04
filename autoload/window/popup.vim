" Init {{{1

const s:AOF_KEY2NORM = {
    \ 'j': 'j',
    \ 'k': 'k',
    \ 'h': '5zh',
    \ 'l': '5zl',
    \ 'c-d': "\<c-d>",
    \ 'c-u': "\<c-u>",
    \ 'gg': 'gg',
    \ 'G': 'G',
    \ }

" Interface {{{1
fu window#popup#close_all() abort "{{{2
    " If we're in a popup window, it will be closed; we want to preserve the view in the *previous* window.{{{
    "
    " Not the view in the *current* window.
    "
    " Unfortunately, we  can't get the  last line address  of the cursor  in the
    " previous window; we could save it via a `WinLeave` autocmd, but it doesn't
    " seem worth the hassle.
    "
    " OTOH, we can get the topline, which for the moment is good enough.
    "}}}
    if window#util#is_popup()
        let wininfo = getwininfo(win_getid(winnr('#')))
        if !empty(wininfo)
            let topline = wininfo[0].topline
        endif
    else
        let view = winsaveview()
    endif

    if !has('nvim')
        " `popup_clear()` doesn't close a terminal popup (`E994`)
        let g = 0 | while g < 99 | let g += 1
            try
                call popup_close(win_getid())
            catch /^Vim\%((\a\+)\)\=:E99[34]:/
                break
            endtry
        endwhile
        try
            call popup_clear()
        " `E994` may still happen in some weird circumstances;
        " example: https://github.com/vim/vim/issues/5744
        catch /^Vim\%((\a\+)\)\=:E994:/
            return lg#catch()
        endtry
    else
        " Why not `nvim_list_wins()`?{{{
        "
        " Yeah, it could replace:
        "
        "     map(range(1, winnr('$')), {_,v -> win_getid(v)})
        "
        " But it would  list *all* windows, and thus the  code would close *all*
        " floating windows.  We don't want that; we only want to close all
        " floating windows in the *current tab page*.
        "
        " We want that for 2 reasons.
        "
        " It's consistent with  `popup_clear()` which only closes  popups in the
        " current tab page (and global popups).
        "
        " The purpose of `=d` is to fix  some issue in what is currently visible
        " on the  screen; whatever  is displayed  on another  tab page  is *not*
        " currently visible;  therefore, there  is no  reason to  close anything
        " outside the current tab page.
        "}}}
        for winid in map(range(1, winnr('$')), {_,v -> win_getid(v)})
            if has_key(nvim_win_get_config(winid), 'anchor')
                " `sil!` to suppress `E5555`.{{{
                "
                " Otherwise, `E5555`  is raised when  the current window is  a float
                " displaying a terminal buffer.
                "
                " I think it may be raised because of our current implementation
                " of borders around floating windows.
                " We create an extra float just for the border.
                " And we  have a one-shot  autocmd which closes the  border when
                " the text  float is closed;  it probably interferes  here; i.e.
                " when Nvim tries  to close the border, the autocmd  has done it
                " already.
                "
                " Note that an `nvim_win_is_valid()` guard wouldn't work here.
                " Unless you use it in combination with a timer.
                "}}}
                sil! call nvim_win_close(winid, 1)
            endif
        endfor
    endif

    if exists('topline')
        let so_save = &l:so
        setl so=0
        exe 'norm! '..topline..'GztM'
        "                          ^
        "                          middle of the window to minimize the distance from the original cursor position
        let &l:so = so_save
    elseif exists('view')
        call winrestview(view)
    endif
endfu

fu window#popup#scroll(lhs) abort "{{{2
    if window#util#has_preview()
        call s:scroll_preview(a:lhs)
    elseif window#util#has_popup()
        call s:scroll_popup(a:lhs)
    endif
endfu
"}}}1
" Core {{{1
fu s:scroll_preview(lhs) abort "{{{2
    let curwin = win_getid()
    " go to preview window
    noa wincmd P

    " Useful to see where we are.{{{
    "
    " Would not be necessary if we *scrolled* with `C-e`/`C-y`.
    " But it is necessary because we *move* with `j`/`k`.
    "
    " We can't use `C-e`/`C-y`; it wouldn't work as expected because of `zMzv`.
    "}}}
    if !&l:cul | setl cul | endif

    " move/scroll
    exe s:get_scrolling_cmd(a:lhs)

    " get back to previous window
    noa call win_gotoid(curwin)
endfu

fu s:scroll_popup(lhs) abort "{{{2
    if !exists('t:_lastpopup') | return | endif
    " let us see the current line in the popup
    call setwinvar(t:_lastpopup, '&cursorline', 1)
    let cmd = s:get_scrolling_cmd(a:lhs)
    if has('nvim')
        sil! call lg#win_execute(t:_lastpopup, cmd)
    else
        call win_execute(t:_lastpopup, cmd)
    endif
endfu

fu s:get_scrolling_cmd(lhs) abort "{{{2
    return 'sil! norm! zR'
        "\ make `M-j` and `M-k` scroll through *screen* lines, not buffer lines
        \ ..(index(['j', 'k'], a:lhs) >= 0 ? 'g' : '')
        \ ..s:AOF_KEY2NORM[a:lhs]
        \ ..'zMzv'
    " `zMzv` may cause the distance between the current line and the first line of the window to change unexpectedly.{{{
    "
    " If that bothers you, you could improve the function.
    " See how we handled the issue in `s:move_and_open_fold()` from:
    "
    "     ~/.vim/plugged/vim-toggle-settings/autoload/toggle_settings.vim
    "}}}
endfu
"}}}1
