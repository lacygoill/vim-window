if exists('g:loaded_window')
    finish
endif
let g:loaded_window = 1

" Autocmds {{{1

augroup my_preview_window
    au!
    au WinLeave * if &l:pvw | call s:scroll_preview_mappings('on_winenter') | endif
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
    au BufWinLeave * if !s:is_special() | call s:save_view() | call s:save_change_position() | endif
    au BufWinEnter * if !s:is_special() | call s:restore_change_position() | call s:restore_view() | endif
    " You must restore the view AFTER the position in the change list.
    " Otherwise it wouldn't be restored correctly.
augroup END

augroup window_height
    au!
    if has('nvim')
        au TermOpen     * if !s:is_alone_in_tabpage() | resize 10 | endif
    else
        au TerminalOpen * if !s:is_alone_in_tabpage() | resize 10 | endif
    endif
    au WinEnter * call s:set_window_height()
augroup END

" Functions {{{1
fu! s:if_special_get_nr_and_height(i,v) abort "{{{2
"     │                            │ │
"     │                            │ └─ a window number
"     │                            │
"     │                            └─ an index in a list of window numbers
"     │
"     └─ if it's a special window, get me its number and the desired height

    return getwinvar(a:v, '&pvw', 0)
       \ ?     [ a:v, &pvh ]
       \ : &l:diff
       \ ?     [ a:v, s:get_diff_height(a:v) ]
       \ : getbufvar(winbufnr(a:v), '&bt', '') is# 'terminal'
       \ ?     [ a:v, 10 ]
       \ : getbufvar(winbufnr(a:v), '&bt', '') is# 'quickfix'
       \ ?     [ a:v, min([ 10, len(getbufline(winbufnr(a:v),
       \                                       1, 10))
       \                  ])
       \       ]
       \ :     []
endfu

fu! s:get_diff_height(...) abort "{{{2
    " Purpose:{{{
    " Return the height of a horizontal window whose 'diff' option is enabled.
    "
    " Should  return half  the  height of  the  screen,  so that  we  can see  2
    " viewports on the same file.
    "
    " If the available  number of lines is odd, example  29, should consistently
    " return the bigger half to the upper viewport.
    " Otherwise, when we would change the focus between the two viewports, their
    " heights would constantly change ([15,14] → [14,15]), which is jarring.
    "}}}

    "                          ┌ the two statuslines of the two diff'ed windows{{{
    "                          │
    "                          │    ┌ if there're several tabpages, there's a tabline;
    "                          │    │ we must take its height into account
    "                          │    │}}}
    let lines = &lines - &ch - 2 - (tabpagenr('$') > 1 ? 1 : 0)
    return fmod(lines,2) ==# 0 || (a:0 ? a:1 : winnr()) !=# 1
       \ ?     lines/2
       \ :     lines/2 + 1
endfu

fu! s:height_should_be_reset(nr) abort "{{{2
    " Tests:{{{
    " Whatever change you perform on this  function, make sure the height of the
    " windows are correct after executing:
    "
    "     :vert pedit $MYVIMRC
    "
    " Also, when  moving from  the preview  window to the  regular window  A, in
    " these layouts:
    "
    "       ┌─────────┬───────────┐
    "       │ preview │ regular A │
    "       ├─────────┴───────────┤
    "       │      regular B      │
    "       └─────────────────────┘
    "
    "       ┌───────────┬───────────┐
    "       │ regular A │           │
    "       ├───────────┤ regular B │
    "       │  preview  │           │
    "       └───────────┴───────────┘
    "}}}
    " Interesting_PR:{{{
    " The current code of the function should work most of the time.
    " But not always. It's based on a heuristic.
    "
    " We may be able to make it work all the time if one day this PR is merged:
    "
    "         https://github.com/vim/vim/pull/2521
    "
    " It adds a few VimL functions which  would allow us to test the geometry of
    " the neighbouring windows.
    " We could  use them  to determine  whether we're  working with  two windows
    " piled in a column or in a line.
    "}}}

    " Rationale:
    " We want to reset the height of a special window when it's wide enough.{{{
    "
    " A window with a small width could be a  TOC, and so need a lot of space on
    " the vertical axis to make up for it.
    "}}}
    " We want to reset the height of a preview window when the width of the current window is small enough. {{{
    "
    " If we open a nerdtree-like file  explorer, its window will probably have a
    " small width.
    " Thus, when we will preview a file from the latter, the preview window will
    " have a small width too.
    " Thus, the `winwidth(a:nr) >= &columns/2` test will fail.
    " Thus, this window's height won't be reset.
    " Besides, when Vim  goes back from the preview window  to the original one,
    " it will maximize  the latter (if it's a regular  one), which will minimize
    " the preview window.
    " The same issue happens with a vim-plug window.
    "}}}
    return winwidth(a:nr) >= &columns/2
    \ ||  (getwinvar(a:nr, '&pvw', 0) && winwidth(0) <= &columns/2)

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
endfu

fu! s:is_alone_in_tabpage() abort "{{{2
    return winnr('$') <= 1
endfu

fu! s:is_special() abort "{{{2
    return &l:pvw
      \ || &l:diff
      \ || &bt =~# '^\%(quickfix\|terminal\)$'
      \ || expand('%:p:t') is# 'COMMIT_EDITMSG'
endfu

fu! s:is_wide() abort "{{{2
    return winwidth(0) >= &columns/2
endfu

fu! s:make_window_small() abort "{{{2
    exe 'resize '.(&l:pvw
    \ ?                &l:pvh
    \ :            &bt is# 'quickfix'
    \ ?                min([ 10, line('$') ])
    \ :            &l:diff
    \ ?                s:get_diff_height()
    \ :            10)
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

fu! s:scroll_preview_mappings(when) abort "{{{2
    if a:when is# 'on_winenter'
        augroup my_scroll_preview_window
            au!
            au WinEnter * call s:scroll_preview_mappings('now')
        augroup END
    else
        try
            " TODO:
            " Once  you've  re-implemented  `vim-submode`, add  the  ability  to
            " invoke a callback when we leave a submode.
            " And use this feature to restore  the possible buffer-local J and K
            " mappings.
            " Right now, the K mapping we install here conflicts with dirvish's K.
            " Besides, K could be used in a custom buffer-local mapping (to look
            " up some  info in documentation, in  a special way); we  need to be
            " able to NOT definitively overwrite such a custom mapping.

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
        finally
            au!  my_scroll_preview_window
            aug! my_scroll_preview_window
        endtry
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

    " Why this check?{{{
    "
    " Suppose we preview a file from a file explorer.
    " Chances are  the file explorer, and  thus the preview window,  are not
    " horizontally maximized.
    "
    " If  we focus  the  preview window,  its  height won't  be  set by  the
    " previous `if` statement, because it's not horizontally maximized.
    " As a result, it will be treated like a regular window and maximized.
    " We don't want that.
    "}}}
    " Ok, but how will the height of a preview window will be set then?{{{
    "
    " The preview window is a special case.
    " When you open one, 2 WinEnter are fired; when Vim:
    "
    "         1. enters the preview window (&l:pvw is NOT yet set)
    "         2. goes back to the original window (now, &l:pvw IS set in the preview window)
    "
    " When the first WinEnter is fired, `&l:pvw` is not set.
    " Thus, the function should maximize it.
    "
    " When the second WinEnter is fired, we'll get back to the original window.
    " It'll probably be a regular window, and thus be maximized.
    " As a result, the preview window will be minimized (1 line high).
    " But, the code at the end of this function should restore the height of
    " the preview window.
    "
    " So, in the end, the height of the preview window is correctly set.
    "}}}

    if &l:pvw
        return
    endif

    if    s:is_special()
    \ &&  s:is_wide()
    \ && !s:is_alone_in_tabpage()
        if lg#window#has_neighbor('up') || lg#window#has_neighbor('down')
            return s:make_window_small()
        " If there's no window above or below, resetting the height of a special
        " window would lead to a big cmdline.
        else
            return
        endif
    else
        " if we enter a regular window, maximize it, but don't stop yet
        wincmd _
    endif

    " If we've maximized a  regular window, we may have altered  the height of a
    " special window somewhere else in the current tab page.
    " In this case, we need to reset their height.
    let winnr_orig = winnr()
    " Why?{{{
    "
    " To resize the size of a window, we'll need to temporarily focus it.
    " This will alter  the value of `winnr('#')`, on which  we sometimes rely to
    " get the number of the previously focused window.
    "}}}
    let winnr_prev = winnr('#')
    " What's the output of `map()`?{{{
    "
    " All numbers (and the corresponding desired heights) of all special windows
    " in the current tabpage.
    "}}}
    " Why invoking `filter()`?{{{
    "
    " Each regular window will have produced an empty list in the output of `map()`.
    " An empty list will cause an error in the next `for` loop.
    " So we need to remove them.
    "
    " Also, we shouldn't  reset the height of the current  window; we've already
    " just set its height (`wincmd _`).
    " Only the heights of the other windows:
    "
    "         && v[0] !=# winnr_orig
    "
    " Finally, there're  some special cases,  where we  don't want to  reset the
    " height of a special window.
    " We delegate the logic to handle these in `s:height_should_be_reset()`:
    "
    "         && !s:height_should_be_reset(v[0])
    "}}}
    let special_windows = filter(map(
                               \     range(1, winnr('$')),
                               \     {i,v -> s:if_special_get_nr_and_height(i,v)}
                               \    ),
                               \ { i,v ->    v    !=# []
                               \          && v[0] !=# winnr_orig
                               \          && s:height_should_be_reset(v[0])
                               \ })

    for [ winnr, height ] in special_windows
        " Why this check?{{{
        "
        " If there's  no window above nor  below the current window,  and we set
        " its height to a few lines only, then the layout becomes wrong.
        "
        " Try this to understand:
        "
        "         10wincmd _
        "}}}
        if lg#window#has_neighbor('up', winnr) || lg#window#has_neighbor('down', winnr)
            " FIXME:
            " Focusing the window to resize it may have unexpected effects.
            " It would be better to find a way to resize it without altering the
            " current focus.
            noa exe winnr.'windo resize '.height
        endif
    endfor

    noa exe winnr_prev.'wincmd w'
    noa exe winnr_orig.'wincmd w'
endfu

fu! s:restore_change_position() abort "{{{2
    if !exists('b:my_change_position')
        sil! norm! 99g,g,
        "              │
        "              └ Why?{{{
        "
        " To be sure `v:count`  is properly reset to `0` as  soon as `:norm` has
        " been executed by the autocmd, even if it happens via a timer.
        " It should not be necessary anymore:
        "
        "     https://github.com/vim/vim/commit/b0f42ba60d9e6d101d103421ba0c351811615c15
        "
        " But could still be useful for Neovim.
        "}}}
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
    sil! exe 'norm! 99g;'
    \ .(b:my_change_position ==# 1 ? 'g,' : (b:my_change_position - 2).'g,g,')
    " TODO: Simplify the code once Neovim has integrated the patch `8.0.1817`:{{{
    "
    "     sil! exe 'norm! 99g;'
    "     \ .(b:my_change_position ==# 1 ? 'g,' : (b:my_change_position - 1).'g,')
    "}}}
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

" SPC q  Q  u  z                                               {{{2

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

nno  <silent><unique>  <space>z  :<c-u>call window#zoom_toggle()<cr>

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

" Zf                   open visually selected file {{{2

xno  <silent>  Zf  <c-w>f

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

" Restore original `ZZ` (C-w Z doesn't do anything).
nno  <silent>  ZZ  :<c-u>exe (v:count) ? 'x!' : 'x'<cr>

" ZGF                  easier C-w gF {{{2

" Especially useful when we use `Z` instead of `C-w`.
" Compare:
"     ZgF
" vs
"     ZGF

nno  <c-w>GF  <c-w>gF

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
