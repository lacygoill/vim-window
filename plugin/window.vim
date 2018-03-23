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
        " `&bt` is not yet set.
        au TermOpen * if !s:is_alone_in_tabpage() | resize 10 | endif
    else
        " In Vim,  the OptionSet event (to  set 'buftype') is not  fired …
        " weird
        au TerminalOpen * if !s:is_alone_in_tabpage() | resize 10 | endif
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
    \:     getbufvar(winbufnr(a:v), '&bt', '') is# 'terminal'
    \?         [ a:v, 10 ]
    \:     getbufvar(winbufnr(a:v), '&bt', '') is# 'quickfix'
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
    return !s:is_horizontally_maximized(a:nr) || s:is_alone_in_tabpage()
endfu

fu! s:is_alone_in_tabpage() abort "{{{2
    return winnr('$') <= 1
endfu

fu! s:is_horizontally_maximized(...) abort "{{{2
    return winwidth(a:0 ? a:1 : 0) ==# &columns
endfu

fu! s:is_special() abort "{{{2
    return &l:pvw || &bt =~# '^\%(quickfix\|terminal\)$' || expand('%:p:t') is# 'COMMIT_EDITMSG'
endfu

fu! s:make_window_small() abort "{{{2
    exe 'resize '.(&l:pvw
    \?                 &l:pvh
    \:             &bt is# 'quickfix'
    \?                 min([ 10, line('$') ])
    \:             10)
endfu

fu! s:save_change_position() abort "{{{2
    let changelist = split(execute('changes'), '\n')
    let b:my_change_position = index(changelist, matchstr(changelist, '^>'))
    if b:my_change_position ==# -1
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

fu! s:scroll_preview(is_fwd) abort "{{{2
    if getwinvar(winnr('#'), '&l:pvw', 0)
        return ":\<c-u>exe window#scroll_preview(".a:is_fwd.")\<cr>"
    else
        call feedkeys(a:is_fwd ? 'j' : 'k', 'int')
    endif
    return ''
endfu

fu! s:scroll_preview_mappings(later) abort "{{{2
    if a:later
        augroup my_scroll_preview_window
            au!
            au WinEnter * call s:scroll_preview_mappings(0)
        augroup END
    else
        try
            " Create mappings  to be able to  scroll in preview window  with `j` and
            " `k`, after an initial `J` or `K`.
            call submode#enter_with('scroll-preview', 'n', 'bs',  'J', ':<c-u>exe window#scroll_preview(1)<cr>')
            call submode#enter_with('scroll-preview', 'n', 'bs',  'K', ':<c-u>exe window#scroll_preview(0)<cr>')
            call submode#map(       'scroll-preview', 'n', 'brs', 'j', '<plug>(scroll_preview_down)')
            call submode#map(       'scroll-preview', 'n', 'brs', 'k', '<plug>(scroll_preview_up)')
            "                                               │
            "                                               └ local to the current buffer

        catch
            " Alternative (in case `vim-submode` isn't enabled):
            nno  <buffer><nowait><silent>  J  :<c-u>exe window#scroll_preview(1)<cr>
            nno  <buffer><nowait><silent>  K  :<c-u>exe window#scroll_preview(0)<cr>
            " TODO:
            " Remove  this   `try`  conditional  once  `vim-submode`   has  been
            " implemented in `vim-lg`.
        endtry

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

    if   s:is_special()
    \&&  s:is_horizontally_maximized()
    \&& !s:is_alone_in_tabpage()
        call s:make_window_small()
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
    \                            { i,v ->     v !=# []
    \                                     && !s:ignore_this_window(v[0])
    \                            })

    for [ id, height ] in special_windows
        exe win_id2win(id).'wincmd w | resize '.height.' | wincmd p'
    endfor
endfu

fu! s:restore_change_position() abort "{{{2
    if !exists('b:my_change_position')
        sil! norm! 99g,
        return
    endif
    "  ┌─ from `:h :sil`:
    "  │                  When [!] is added, […], commands and mappings will
    "  │                  not be aborted when an error is detected.
    "  │
    "  │  If our position in the list is somewhere in the middle, `99g;` will
    "  │  raise an error.
    "  │  Without `sil!`, `norm!` would stop typing the key sequence.
    "  │
    sil! exe 'norm! 99g;'.(b:my_change_position - 1).'g,'
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
" <plug> {{{2

nno  <expr>  <plug>(scroll_preview_down)  <sid>scroll_preview(1)
nno  <expr>  <plug>(scroll_preview_up)    <sid>scroll_preview(0)

" C-hjkl               move across windows/tmux panes {{{2

nno  <silent><unique>  <c-h>  :<c-u>call window#navigate('h')<cr>
nno  <silent><unique>  <c-j>  :<c-u>call window#navigate('j')<cr>
nno  <silent><unique>  <c-k>  :<c-u>call window#navigate('k')<cr>
nno  <silent><unique>  <c-l>  :<c-u>call window#navigate('l')<cr>

" SPC q  Q  u                                               {{{2

nno  <silent><unique>  <space>q  :<c-u>call lg#window#quit()<cr>
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
nno  <silent><unique>  <space>Q  :<c-u>sil! call window#quit_everything()<cr>
nno  <silent><unique>  <space>u  :<c-u>call lg#window#restore_closed(v:count1)<cr>

" z<  z>               open/focus/close terminal window {{{2

nno  <silent><unique>  z<  :<c-u>call window#terminal_open()<cr>
nno  <silent><unique>  z>  :<c-u>call window#terminal_close()<cr>

"z(  z)  z[  z]                        qf/ll    window {{{2

nno  <silent><unique>  z(  :<c-u>exe lg#window#qf_open('qf')<cr>
nno  <silent><unique>  z)  :<c-u>cclose<cr>

nno  <silent><unique>  z[  :<c-u>exe lg#window#qf_open('loc')<cr>
nno  <silent><unique>  z]  :<c-u>lclose<cr>

" z{  z}                                preview  window {{{2

nno  <silent><unique>  z{  :<c-u>call window#preview_open()<cr>
nno          <unique>  z}  <c-w>z

" Z                    simpler window prefix {{{2

" we need the recursiveness, so that, when we type, we can replace <c-w>
" with Z in custom mappings (own+third party)
"
" MWE:
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
nmap  <unique>  Z  <c-w>

" Z C-h C-j C-k C-l    resize window (repeatable with ; ,) {{{2

nno  <silent><unique>  Z<c-h>  :<c-u>call window#resize('h')<cr>
nno  <silent><unique>  Z<c-j>  :<c-u>call window#resize('j')<cr>
nno  <silent><unique>  Z<c-k>  :<c-u>call window#resize('k')<cr>
nno  <silent><unique>  Z<c-l>  :<c-u>call window#resize('l')<cr>

" Zh  Zl  Zj  Zk       split in any direction {{{2

nno  <silent><unique>  Zh  :<c-u>setl nowrap <bar> leftabove vsplit  <bar> setl nowrap<cr>
nno  <silent><unique>  Zl  :<c-u>setl nowrap <bar> rightbelow vsplit <bar> setl nowrap<cr>
nno  <silent><unique>  Zj  :<c-u>belowright split<cr>
nno  <silent><unique>  Zk  :<c-u>aboveleft split<cr>

" We often press `zj` instead of `Zj`, when we want to split the window.
nmap         <unique>  zh  Zh
nmap         <unique>  zj  Zj
nmap         <unique>  zk  Zk
nmap         <unique>  zl  Zl

nmap  <unique>  <c-w>h  Zh
nmap  <unique>  <c-w>l  Zl
nmap  <unique>  <c-w>j  Zj
nmap  <unique>  <c-w>k  Zk

" ZH  ZL  Zv           disable 'wrap' in vert splits when splitting or moving a window {{{2

" disable wrapping of long lines when we create a vertical split
nno   <silent><unique>  Zv      :<c-u>setl nowrap <bar> vsplit <bar> setl nowrap<cr>
nmap          <unique>  <c-w>v  Zv

" Alternative:
"
"     augroup nowrap_in_vert_splits
"         au!
"         au WinLeave * if winwidth(0) !=# &columns | setl nowrap | endif
"         au WinEnter * if winwidth(0) !=# &columns | setl nowrap | endif
"     augroup END
"
" Pro:
" Will probably cover more cases.
"
" Con:
" WinLeave/WinEnter is not fired after moving a window.

nno   <silent><unique>  ZH      :<c-u>call window#disable_wrap_when_moving_to_vert_split('H')<cr>
nno   <silent><unique>  ZL      :<c-u>call window#disable_wrap_when_moving_to_vert_split('L')<cr>
nmap          <unique>  <c-w>L  ZL
nmap          <unique>  <c-w>H  ZH

" ZQ  ZZ {{{2

" Our `SPC q` mapping is special, it creates a session file so that we can undo
" the closing of the window. `ZQ` should behave in the same way.

nmap  <unique>  ZQ  <space>q

" When we press `ZZ`, we don't want Vim to press `C-w Z` (closing preview window).
" Restore original `ZZ`.
nno  <silent>  ZZ  :<c-u>x<cr>

" Options {{{1

" Why setting these options?{{{
"
" When opening a file with long lines, I prefer to do it:
"
"     • on the right if it's vertical
"     • at the bottom if it's horizontal
"
" Rationale:
" When you read a book, the next page is on the right, not on the left.
" When you read a pdf, the next page is below, not above.
"
"
" However, when displaying  a buffer with short lines (ex: TOC),  I prefer to do
" it on the  left.
"
" Rationale:
" When you write annotations in  a page, you do it  in the left margin.
"
"
" Bottom Line:
" `set splitbelow` and `set splitright`  seem to define good default directions.
" Punctually  though, we  may  `need  `:topleft` or  :leftabove`  to change  the
" direction.
"}}}

" when we create a new horizontal viewport, it should be displayed at the
" bottom of the screen
set splitbelow

" and a new vertical one should be displayed on the right
set splitright
