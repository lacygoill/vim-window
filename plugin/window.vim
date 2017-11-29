if exists('g:loaded_window')
    finish
endif
let g:loaded_window = 1

" Autocmds {{{1

augroup my_preview_window
    au!
    au WinLeave * if &l:pvw | call s:scroll_preview_mappings(1) | endif
augroup END

" When we switch buffers in the same window, sometimes the view is altered.
" We want it to be preserved.
"
" Inspiration:
"         https://stackoverflow.com/a/31581929/8243465
"
" Similar_issue:
" The position in the changelist is local to the window. It should be local
" to the buffer. We want it to be also preserved when switching buffers.

augroup preserve_view_and_pos_in_changelist
    au!
    au BufWinLeave * call s:save_view() | call s:save_change_position()
    au BufWinEnter * call s:restore_change_position() | call s:restore_view()
    " You must restore the view AFTER the position in the change list.
    " Otherwise it wouldn't be restored correctly.
augroup END

augroup window_height
    au!
    if has('nvim')
        " In  Neovim, when  we open  a  terminal and  BufWinEnter is  fired,
        " `&l:buftype` is not yet set.
        au TermOpen * if winnr('$') > 1 | resize 10 | endif
    else
        " In Vim,  the OptionSet event (to  set 'buftype') is not  fired …
        " weird
        au BufWinEnter * if &l:buftype ==# 'terminal' && winnr('$') > 1 | resize 10 | endif
    endif
    " The preview window is special, when you open one, 2 WinEnter are fired;{{{
    " one when you:
    "
    "         1. enter preview window (&l:pvw is NOT yet set)
    "         2. go back to original window (now, &l:pvw IS set in the preview window)
"}}}
    au WinEnter * call s:set_window_height()
augroup END

" Functions {{{1
fu! s:if_special_get_id_and_height(i,v) abort "{{{2
"     │                            │ │
"     │                            │ └─ a window id
"     │                            │
"     │                            └─ an index in a list of window ids
"     │
"     └─ if it's a special window, get me its ID and the desired height

    return getwinvar(a:v, '&pvw', 0)
    \?         [ a:v, &pvh ]
    \:     getbufvar(winbufnr(a:v), '&bt', '') ==# 'terminal'
    \?         [ a:v, 10 ]
    \:     getbufvar(winbufnr(a:v), '&bt', '') ==# 'quickfix'
    \?         [ a:v, min([ 10, len(getbufline(winbufnr(a:v),
    \                                          1, 10))
    \                     ])
    \          ]
    \:         []
endfu

fu! s:ignore_this_window(nr) abort "{{{2
    " You want a condition to test whether a window is maximized vertically?{{{
    " Try this:
    "
    "         ┌ no viewport above/below:
    "         │
    "         │         every time you open a viewport above/below
    "         │         the difference increases by 2,
    "         │         for the new stl + the visible line in the other viewport
    "         │
    "         ├───────────────────────────────┐
    "         &lines - winheight(a:nr) <= &ch+2
    "                                  └┤ └─┤ │
    "                                   │   │ └ status line + tabline
    "                                   │   │
    "                                   │   └ command-line
    "                                   │
    "                                   └ there could be a tabline,
    "                                     if there are several tabpages,
    "                                     or not (if there's a single tabpage)
"}}}
    "
    "                               ┌ the window is NOT maximized horizontally
    "      ┌────────────────────────┤
    return winwidth(a:nr) != &columns || winnr('$') <= 1
    "                                    └─────────────┤
    "                                                  └ or it's alone in the tab page
endfu

fu! s:save_change_position() abort "{{{2
    let changelist = split(execute('changes'), '\n')
    let b:my_change_position = index(changelist, matchstr(changelist, '^>'))
    if b:my_change_position == -1
        let b:my_change_position = 100
    endif
endfu

fu! s:save_view() abort "{{{2
" Save current view settings on a per-window, per-buffer basis.
    if !exists('w:saved_views')
        let w:saved_views = {}
    endif
    let w:saved_views[bufnr('%')] = winsaveview()
endfu

fu! s:scroll_preview_mappings(later) abort "{{{2
    if a:later
        augroup my_scroll_preview_window
            au!
            au WinEnter * call s:scroll_preview_mappings(0)
        augroup END
    else
        nno <buffer> <nowait> <silent> J :<c-u>exe window#scroll_preview(1)<cr>
        nno <buffer> <nowait> <silent> K :<c-u>exe window#scroll_preview(0)<cr>
        au!  my_scroll_preview_window
        aug! my_scroll_preview_window
    endif
endfu

fu! s:set_window_height() abort "{{{2
    " Goal:{{{
    "
    " Maximize  the  height of  all  windows,  except  the  ones which  are  not
    " horizontally maximized.
    "
    " Preview/qf/terminal windows  which are horizontally maximized  should have
    " their height fixed to:
    "
    "         • &pvh for the preview window
    "         • 10 for a qf/terminal window
"}}}
    " Issue:{{{
    " Create a tab page with a qf window + a terminal.
    " The terminal is  big when we switch  to the qf window, then  small when we
    " switch back to the terminal.
    "
    " More generally, I think this undesired change of height occur whenever we move
    " in a tab page where there are several windows, but ALL are special.
    " This is  a unique  and probably  rare case. So, I  don't think  it's worth
    " trying and fix it.
"}}}

    " if we enter a special window, set its height and stop
    if &l:pvw || &l:buftype =~# '^\%(quickfix\|terminal\)$'
        " but make sure it's horizontally maximized,
        " and not alone in the tab page
        if winwidth(0) == &columns && winnr('$') > 1
            exe 'resize '.(&l:pvw
            \?                 &l:pvh
            \:             &l:bt ==# 'quickfix'
            \?                 min([ 10, line('$') ])
            \:             10)
        endif
        return
    else
        " if we enter a regular window, maximize it, but don't stop yet
        wincmd _
    endif

    " If we've maximized a  regular window, we may have altered  the height of a
    " special window somewhere else in the current tab page.
    " In this case, we need to reset their height.
    let special_windows = filter(map(
    \                                gettabinfo(tabpagenr())[0].windows,
    \                                function('s:if_special_get_id_and_height')
    \                               ),
    \                            { k,v ->     v != []
    \                                     && !s:ignore_this_window(v[0])
    \                            })

    for [ id, height ] in special_windows
        exe win_id2win(id).'wincmd w | resize '.height.' | wincmd p'
    endfor
endfu

fu! s:restore_change_position() abort "{{{2
    "  ┌─ from `:h :sil`:
    "  │                  When [!] is added, […], commands and mappings will
    "  │                  not be aborted when an error is detected.
    "  │
    "  │  If our position in the list is somewhere in the middle, `99g;` will
    "  │  raise an error.
    "  │  Without `sil!`, `norm!` would stop typing the key sequence.
    "  │
    sil! exe 'norm! '.(exists('b:my_change_position') ? '99g;' : '99g,')
    \                .(b:my_change_position - 1) .'g,'
endfu

fu! s:restore_view() abort "{{{2
" Restore current view settings.
    let n = bufnr('%')
    if exists('w:saved_views') && has_key(w:saved_views, n)
        if !&l:diff
            call winrestview(w:saved_views[n])
        endif
        unlet w:saved_views[n]
    endif
endfu

" Mappings {{{1
" C-hjkl               move across windows/tmux panes {{{2

nno <silent> <c-h>    :<c-u>call window#navigate('h')<cr>
nno <silent> <c-j>    :<c-u>call window#navigate('j')<cr>
nno <silent> <c-k>    :<c-u>call window#navigate('k')<cr>
nno <silent> <c-l>    :<c-u>call window#navigate('l')<cr>

" q  Q  u                                               {{{2

nno <silent>  <space>q  :<c-u>exe my_lib#quit()<cr>
" FIXME:{{{
" When  an  instruction causes  several  errors,  and  it's  executed in  a  try
" conditional, the  first error can be  catched and converted into  an exception
" with `v:exception` (:h except-several-errors).
" However, for  some reason,  I can't display  its message.  All  I have  is the
" hit-enter prompt,  which usually accompanies  a multi-line message (as  if Vim
" was trying to display all the error messages).
"
" MWE:
" Create a modified buffer, and source this mapping:
"
"         nno cd :exe Func()<cr>
"
"         fu! Func() abort
"             try
"                 qall
"             catch
"                 return 'echoerr '.string(v:exception)
"             endtry
"             return ''
"         endfu
"
" Press `cd`.
"}}}
" Temporary_solution:{{{
" Call the  function silently, to  bypass the hit-enter prompt. And,  inside the
" function, when  an error  occurs, call  a timer to  display the  message right
" afterwards.
"}}}
nno <silent>  <space>Q  :<c-u>sil! call window#quit_everything()<cr>
nno <silent>  <space>u  :<c-u>exe my_lib#restore_closed_window(v:count1)<cr>

" Z                    simpler window prefix {{{2

" we need the recursiveness, so that, when we type, we can replace <c-w>
" with Z in custom mappings (own+third party)
"
" Watch:
"
"        nno  <c-w><cr>  :echo 'hello'<cr>
"        nno  Z          <c-w>
"                Z cr    ✘
"
"        nno  <c-w><cr>  :echo 'hello'<cr>
"        nmap Z          <c-w>
"                Z cr    ✔
"
" Indeed,  once `Z`  has been  expanded into  `C-w`, we  may need  to expand  it
" FURTHER for custom mappings using `C-w` in their lhs.
nmap Z <c-w>

" Z(  Z{  Z}           open/close window preview {{{2

nno <silent> Z(  :<c-u>exe window#open_preview(1)<cr>
nno <silent> Z{  :<c-u>exe window#open_preview(0)<cr>
nno          Z}  <c-w>z

" Zh  Zl  Zj  Zk       split in any direction {{{2

nno <silent>   Zh     :<c-u>setl nowrap <bar> leftabove vsplit  <bar> setl nowrap<cr>
nno <silent>   Zl     :<c-u>setl nowrap <bar> rightbelow vsplit <bar> setl nowrap<cr>
nno <silent>   Zj     :<c-u>belowright split<cr>
nno <silent>   Zk     :<c-u>aboveleft split<cr>

nmap           <c-w>h  Zh
nmap           <c-w>l  Zl
nmap           <c-w>j  Zj
nmap           <c-w>k  Zk

" ZH  ZL  Zv           disable 'wrap' in vert splits when splitting or moving a window {{{2

" disable wrapping of long lines when we create a vertical split
nno  <silent>  Zv      :<c-u>setl nowrap <bar> vsplit <bar> setl nowrap<cr>
nmap           <c-w>v  Zv

" Alternative:
"
"     augroup nowrap_in_vert_splits
"         au!
"         au WinLeave * if winwidth(0) != &columns | setl nowrap | endif
"         au WinEnter * if winwidth(0) != &columns | setl nowrap | endif
"     augroup END
"
" Pro:
" Will probably cover more cases.
"
" Con:
" WinLeave/WinEnter is not fired after moving a window.

nno <expr> <silent>  ZH      window#disable_wrap_when_moving_to_vert_split('H')
nno <expr> <silent>  ZL      window#disable_wrap_when_moving_to_vert_split('L')
nmap                 <c-w>L  ZL
nmap                 <c-w>H  ZH

" ZQ {{{2

" Our `SPC q` mapping is special, it creates a session file so that we can undo
" the closing of the window. `ZQ` should behave in the same way.

nmap ZQ <space>q

" Options {{{1

" when we create a new horizontal viewport, it should be displayed at the
" bottom of the screen
set splitbelow

" and a new vertical one should be displayed on the right
set splitright
