fu window#popup#close_all() abort
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
        call map(map(range(1, winnr('$')), {_,v -> win_getid(v)}),
            \ {_,v -> nvim_win_is_valid(v) && has_key(nvim_win_get_config(v), 'anchor') && nvim_win_close(v, 1)})
            "         ^^^^^^^^^^^^^^^^^^^^
            "         necessary{{{
            "
            " Otherwise, `E5555`  is raised when  the current window is  a float
            " displaying a terminal buffer.
            "
            " I think  that's because our  current implementation of  a toggling
            " terminal creates 2 windows: one for  the terminal, and one for the
            " border.  And  we have a  one-shot autocmd which closes  the border
            " when the  terminal is  closed; it  probably interferes  here; i.e.
            " when  Nvim tries  to close  the border,  the autocmd  has done  it
            " already.
            "}}}
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

