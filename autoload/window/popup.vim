if exists('g:autoloaded_window#popup')
    finish
endif
let g:autoloaded_window#popup = 1

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

    try
        " `v:true` to close a popup terminal and avoid `E994`
        call popup_clear(v:true)
    " `E994` may still happen in some weird circumstances;
    " example: https://github.com/vim/vim/issues/5744
    catch /^Vim\%((\a\+)\)\=:E994:/
        return lg#catch()
    endtry

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
    else
        let popup = window#util#latest_popup()
        if popup != 0
            call s:scroll_popup(a:lhs, popup)
        endif
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

fu s:scroll_popup(lhs, winid) abort "{{{2
    " let us see the current line in the popup
    call setwinvar(a:winid, '&cursorline', 1)
    let cmd = s:get_scrolling_cmd(a:lhs)
    call win_execute(a:winid, cmd)
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
