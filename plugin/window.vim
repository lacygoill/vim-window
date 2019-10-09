if exists('g:loaded_window')
    finish
endif
let g:loaded_window = 1

" Init {{{1

" Default height
let s:D_HEIGHT = 10
" Terminal window
let s:T_HEIGHT = 10
" Quickfix window
let s:Q_HEIGHT = 10
" file “Running” current line (websearch, tmuxprompt)
let s:R_HEIGHT = 5

" Autocmds {{{1

" When we switch buffers in the same window, sometimes the view is altered.
" We want it to be preserved.
"
" Inspiration: https://stackoverflow.com/a/31581929/8243465
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
        au TermOpen     * if !s:is_alone_in_tabpage() | exe 'resize ' . s:T_HEIGHT | endif
    else
        au TerminalOpen * if !s:is_alone_in_tabpage() | exe 'resize ' . s:T_HEIGHT | endif
    endif
    " Why `BufWinEnter`?{{{
    "
    " This is useful when splitting a window to open a ‘websearch’ file.
    " When that happens, and `WinEnter` is fired, the filetype has not yet been set.
    " So `s:set_window_height()` will not properly set the height of the window.
    "
    " OTOH, when `BufWinEnter` is fired, the filetype *has* been set.
    "}}}
    au BufWinEnter,WinEnter * call s:set_window_height()
augroup END

" Functions {{{1
fu! s:if_special_get_nr_and_height(v) abort "{{{2
"     │                            │
"     │                            └ a window number
"     │
"     └ if it's a special window, get me its number and the desired height

    return getwinvar(a:v, '&pvw', 0)
        \ ?     [a:v, &pvh]
        \ : index(['tmuxprompt', 'websearch'], getbufvar(winbufnr(a:v), '&ft', '')) >= 0
        \ ?     [a:v, s:R_HEIGHT]
        \ : &l:diff
        \ ?     [a:v, s:get_diff_height(a:v)]
        \ : getbufvar(winbufnr(a:v), '&bt', '') is# 'terminal'
        \ ?     [a:v, s:T_HEIGHT]
        \ : getbufvar(winbufnr(a:v), '&bt', '') is# 'quickfix'
        \ ?     [a:v, min([s:Q_HEIGHT, len(getbufline(winbufnr(a:v), 1, s:Q_HEIGHT))])]
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
    return fmod(lines,2) == 0 || (a:0 ? a:1 : winnr()) != 1
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
    "    ┌─────────┬───────────┐
    "    │ preview │ regular A │
    "    ├─────────┴───────────┤
    "    │      regular B      │
    "    └─────────────────────┘
    "
    "    ┌───────────┬───────────┐
    "    │ regular A │           │
    "    ├───────────┤ regular B │
    "    │  preview  │           │
    "    └───────────┴───────────┘
    "}}}
    " Interesting_PR:{{{
    " The current code of the function should work most of the time.
    " But not always. It's based on a heuristic.
    "
    " We may be able to make it work all the time if one day this PR is merged:
    " https://github.com/vim/vim/pull/2521
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
    "                                  ├┘ ├─┘ │
    "                                  │  │   └ status line + tabline
    "                                  │  │
    "                                  │  └ command-line
    "                                  │
    "                                  └ there could be a tabline,
    "                                    if there are several tabpages,
    "                                    or not (if there's a single tabpage)
"}}}
endfu

fu! s:is_alone_in_tabpage() abort "{{{2
    return winnr('$') <= 1
endfu

fu! s:is_special() abort "{{{2
    return &l:pvw
      \ || &l:diff
      \ || &ft is# 'gitcommit' || index(['tmuxprompt', 'websearch'], &ft) >= 0
      \ || &bt =~# '^\%(quickfix\|terminal\)$'
endfu

fu! s:is_wide() abort "{{{2
    return winwidth(0) >= &columns/2
endfu

fu! s:make_window_small() abort "{{{2
    exe 'resize '.(&l:pvw
    \ ?                &l:pvh
    \ :            &bt is# 'quickfix'
    \ ?                min([s:Q_HEIGHT, line('$')])
    \ :            &l:diff
    \ ?                s:get_diff_height()
    \ :            index(['tmuxprompt', 'websearch'], &ft) >= 0
    \ ?                s:R_HEIGHT
    \ :            s:D_HEIGHT)
endfu

fu! s:save_change_position() abort "{{{2
    let changelist = get(getchangelist('%'), 0, [])
    let b:my_change_position = get(getchangelist('%'), 1, -1)
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

fu! s:set_window_height() abort "{{{2
    " Goal:{{{
    "
    " Maximize  the  height of  all  windows,  except  the  ones which  are  not
    " horizontally maximized.
    "
    " Preview/qf/terminal windows  which are horizontally maximized  should have
    " their height fixed to:
    "
    "    - &pvh for the preview window
    "    - 10 for a qf/terminal window
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
    "    1. enters the preview window (&l:pvw is *not* yet set)
    "    2. goes back to the original window (now, &l:pvw *is* set in the preview window)
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
    if &l:pvw | return | endif

    if getcmdwintype() isnot# '' | exe 'resize '..&cwh | return | endif

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
    "     && v[0] != winnr_orig
    "
    " Finally, there're  some special cases,  where we  don't want to  reset the
    " height of a special window.
    " We delegate the logic to handle these in `s:height_should_be_reset()`:
    "
    "     && !s:height_should_be_reset(v[0])
    "}}}
    let special_windows = filter(map(
        \     range(1, winnr('$')),
        \     {_,v -> s:if_special_get_nr_and_height(v)}
        \    ),
        \ {_,v ->    v    !=# []
        \         && v[0] != winnr_orig
        \         && s:height_should_be_reset(v[0])
        \ })

    for [winnr, height] in special_windows
        " Why this check?{{{
        "
        " If there's  no window above nor  below the current window,  and we set
        " its height to a few lines only, then the layout becomes wrong.
        "
        " Try this to understand:
        "
        "     10wincmd _
        "}}}
        if lg#window#has_neighbor('up', winnr) || lg#window#has_neighbor('down', winnr)
            " FIXME:
            " Focusing the window to resize it may have unexpected effects.
            " It would be better to find a way to resize it without altering the
            " current focus.
            noa exe winnr.'windo resize '.height
        endif
    endfor

    " Why `silent!` ?{{{
    "
    " Sometimes, E788 is raised.
    " MWE:
    "     $ vim +'sp | Man man | wincmd p' ~/.vim/vimrc
    "     " press `gt`
    "}}}
    sil! noa exe winnr_prev.'wincmd w'
    sil! noa exe winnr_orig.'wincmd w'
endfu

fu! s:restore_change_position() abort "{{{2
    if !exists('b:my_change_position')
        " Why this guard `!empty(...)`?{{{
        "
        " Without, it creates a little noise when we debug Vim with `:set vbs=2 vfile=/tmp/log`:
        "
        "     E664: changelist is empty
        "     Error detected while processing function <SNR>103_restore_change_position:
        "}}}
        if !empty(get(getchangelist(0), 0, []))
            " Why `g,` after `99g,`?{{{
            "
            " To be sure `v:count`  is properly reset to `0` as  soon as `:norm` has
            " been executed by the autocmd, even if it happens via a timer.
            " It should not be necessary anymore:
            " https://github.com/vim/vim/commit/b0f42ba60d9e6d101d103421ba0c351811615c15
            "
            " But could still be useful for Neovim.
            "}}}
            sil! norm! 99g,g,
        endif
        return
    endif
    "  ┌ from `:h :sil`:
    "  │                 When [!] is added, […], commands and mappings will
    "  │                 not be aborted when an error is detected.
    "  │
    "  │  If our position in the list is somewhere in the middle, `99g;` will
    "  │  raise an error.
    "  │  Without `sil!`, `norm!` would stop typing the key sequence.
    "  │
    sil! exe 'norm! 99g;'
    \ .(b:my_change_position == 1 ? 'g,' : (b:my_change_position - 2).'g,g,')
    " TODO: Simplify the code once Neovim has integrated the patch `8.0.1817`:{{{
    "
    "     sil! exe 'norm! 99g;'
    "     \ .(b:my_change_position == 1 ? 'g,' : (b:my_change_position - 1).'g,')
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
" }}}1
" Mappings {{{1
" C-hjkl               move across windows {{{2

nno  <silent><unique>  <c-h>  :<c-u>call window#navigate_or_resize('h')<cr>
nno  <silent><unique>  <c-j>  :<c-u>call window#navigate_or_resize('j')<cr>
nno  <silent><unique>  <c-k>  :<c-u>call window#navigate_or_resize('k')<cr>
nno  <silent><unique>  <c-l>  :<c-u>call window#navigate_or_resize('l')<cr>

" M-hjkl du gg G       scroll preview window {{{2

nno <silent><unique> <m-h> :<c-u>call window#scroll_preview('h')<cr>
nno <silent><unique> <m-j> :<c-u>call window#scroll_preview('j')<cr>
nno <silent><unique> <m-k> :<c-u>call window#scroll_preview('k')<cr>
nno <silent><unique> <m-l> :<c-u>call window#scroll_preview('l')<cr>

nno <silent><unique> <m-d> :<c-u>call window#scroll_preview('c-d')<cr>
" Why don't you install a mapping for `M-u`?{{{
"
" It would conflict with the `M-u` mapping from `vim-readline`.
" As a workaround, we've overloaded the latter.
" We make it check whether a preview window is opened in the current tab page:
"
"    - if there is one, it scrolls half a page up in the preview window
"    - otherwise, it upcases the text up to the end of the next/current word
"}}}

nno <silent><unique> <m-g><m-g> :<c-u>call window#scroll_preview('gg')<cr>
nno <silent><unique> <m-g>G     :<c-u>call window#scroll_preview('G')<cr>

" SPC q  Q  U  z                                               {{{2

" Provide a `<plug>` mapping to access our `lg#window#quit()` function, so that
" we can call it more easily from other plugins.
" Why don't you use `:norm 1 q` to quit in your plugins?{{{
"
" Yes, we did this in the past:
"
"     :nno <buffer> q :norm 1 q<cr>
"
" But it seems to cause too many issues.
" We  had  one  in  the  past  involving  an  interaction  between  `:norm`  and
" `feedkeys()` with the 't' flag.
"
" I also had a `E169: Command too recursive` error, but I can't reproduce anymore.
" I suspect the issue was somewhere else (maybe the `<space>q` was not installed
" while we  were debugging  sth); nevertheless, the  error message  is confusing.
"
" And the mapping in itself can  be confusing to understand/debug; I much prefer
" a mapping where the lhs is not repeated in the rhs.
"}}}
nmap <silent><unique>  <space>q  <plug>(my_quit)
nno  <silent><unique>  <plug>(my_quit)  :<c-u>call lg#window#quit()<cr>
xno  <silent><unique>  <space>q  :<c-u>call lg#window#quit()<cr>
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
"     nno cd :exe Func()<cr>
"
"     fu! Func() abort
"         try
"             qall
"         catch
"             return 'echoerr '.string(v:exception)
"         endtry
"         return ''
"     endfu
"
" Press `cd`.
"}}}
" Temporary_solution:{{{
" Call the  function silently, to  bypass the hit-enter prompt. And,  inside the
" function, when  an error  occurs, call  a timer to  display the  message right
" afterwards.
"}}}
nno  <silent><unique>  <space>Q  :<c-u>sil! call window#quit_everything()<cr>
xno  <silent><unique>  <space>Q  :<c-u>sil! call window#quit_everything()<cr>
" Why not `SPC u`?{{{
"
" We often type it by accident.
" When  that happens,  it's  very distracting,  because it  takes  some time  to
" recover the original layout.
"
" Let's try `SPC U`; it should be harder to press by accident.
"}}}
nno  <silent><unique>  <space>U  :<c-u>call lg#window#restore_closed(v:count1)<cr>
nno  <silent><unique>  <space>u  <nop>

nno  <silent><unique>  <space>z  :<c-u>call window#zoom_toggle()<cr>

" z (prefix) {{{2
" z<  z>               open/focus/close terminal window {{{3

nno  <silent><unique>  z<  :<c-u>call window#terminal_open()<cr>
nno  <silent><unique>  z>  :<c-u>call window#terminal_close()<cr>

"z(  z)  z[  z]                        qf/ll    window {{{3

nno  <silent><unique>  z(  :<c-u>exe lg#window#qf_open('qf')<cr>
nno  <silent><unique>  z)  :<c-u>cclose<cr>

nno  <silent><unique>  z[  :<c-u>exe lg#window#qf_open('loc')<cr>
nno  <silent><unique>  z]  :<c-u>lclose<cr>

" z{  z}                                preview  window {{{3

nno  <silent><unique>  z{  :<c-u>call window#preview_open()<cr>
nno          <unique>  z}  <c-w>z

" z C-[hjkl]           resize window (repeatable with ; ,) {{{3

" Why using the `z` prefix instead of the `Z` one?{{{
"
" Easier to type.
"
" Z C-h would mean pressing the right shift with our right pinky,
" then the left control with our left pinky.
" That's 2 pinkys, on different hands; too awkward.
"}}}
" Pressing the lhs repeatedly is too difficult!{{{
"
" You don't have to.
" You only need to press the prefix key  once; after that, for a short period of
" time (1s atm), you can just press `C-[hjkl]` to resize in any direction.
"
" Btw, this is consistent with how we resize panes in tmux.
"}}}
nno  <silent><unique>  z<c-h>  :<c-u>call window#resize('h')<cr>
nno  <silent><unique>  z<c-j>  :<c-u>call window#resize('j')<cr>
nno  <silent><unique>  z<c-k>  :<c-u>call window#resize('k')<cr>
nno  <silent><unique>  z<c-l>  :<c-u>call window#resize('l')<cr>

" z[hjkl]              split in any direction {{{3

nno  <silent><unique>  zh  :<c-u>setl nowrap <bar> leftabove vsplit  <bar> setl nowrap<cr>
nno  <silent><unique>  zl  :<c-u>setl nowrap <bar> rightbelow vsplit <bar> setl nowrap<cr>
nno  <silent><unique>  zj  :<c-u>belowright split<cr>
nno  <silent><unique>  zk  :<c-u>aboveleft split<cr>

nmap  <unique>  <c-w>h  zh
nmap  <unique>  <c-w>l  zl
nmap  <unique>  <c-w>j  zj
nmap  <unique>  <c-w>k  zk

"}}}2
" Z (prefix) {{{2
" Z                    simpler window prefix {{{3

" Why a *recursive* mapping?{{{
"
" We need the recursiveness, so that, when we type, we can replace <c-w>
" with Z in custom mappings (own+third party).
"
" MWE:
"
"     nno  <c-w><cr>  :echo 'hello'<cr>
"     nno  Z          <c-w>
"     " press 'Z cr': doesn't work ✘
"
"     nno  <c-w><cr>  :echo 'hello'<cr>
"     nmap Z          <c-w>
"     " press 'Z cr': works ✔
"
" Indeed,  once `Z`  has been  expanded into  `C-w`, we  may need  to expand  it
" *further* for custom mappings using `C-w` in their lhs.
"}}}
nmap <unique> Z <c-w>
" Why no `<unique>`?{{{
"
" `vim-sneak` installs a `Z` mapping:
"
"     xmap Z <Plug>Sneak_S
"
" See: `~/.vim/plugged/vim-sneak/plugin/sneak.vim`
"}}}
xmap          Z <c-w>

" ZF, ZGF, ...         open path in split window/tabpage and unfold {{{3

" `C-w f`, `C-w F`, `C-w gf`, ... I'm confused!{{{
"
" Some default normal commands can open a path in another split window or tabpage.
" They all start with the prefix `C-w`.
"
" To understand which suffix must be pressed, see:
"
"    ┌────┬──────────────────────────────────────────────────────────────┐
"    │ f  │ split window                                                 │
"    ├────┼──────────────────────────────────────────────────────────────┤
"    │ F  │ split window, taking into account line indicator like `:123` │
"    ├────┼──────────────────────────────────────────────────────────────┤
"    │ gf │ tabpage                                                      │
"    ├────┼──────────────────────────────────────────────────────────────┤
"    │ gF │ tabpage, taking into account line indicator like `:123`      │
"    └────┴──────────────────────────────────────────────────────────────┘
"}}}
nno <c-w>f <c-w>fzv
nno <c-w>F <c-w>Fzv

nno <c-w>gf <c-w>gfzv
nno <c-w>gF <c-w>gFzv
nno <c-w>GF <c-w>GFzv
" easier to press `ZGF` than `ZgF`

xno <c-w>f <c-w>fzv
xno <c-w>F <c-w>Fzv

xno <c-w>gf <c-w>gfzv
xno <c-w>gF <c-w>gFzv
xno <c-w>GF <c-w>GFzv

" TODO:
" Implement a `<C-w>F` visual mapping which would take into account a line address.
" Like `<C-w>F` does in normal mode.
"
" Also, move all mappings which open a path into a dedicated plugin (`vim-gf`).

" ZH  ZL  Zv           disable 'wrap' in vert splits when splitting or moving a window {{{3

" disable wrapping of long lines when we create a vertical split
nno   <silent><unique>  Zv      :<c-u>setl nowrap <bar> vsplit <bar> setl nowrap<cr>
nmap          <unique>  <c-w>v  Zv

" Alternative:
"
"     augroup nowrap_in_vert_splits
"         au!
"         au WinLeave * if winwidth(0) != &columns | setl nowrap | endif
"         au WinEnter * if winwidth(0) != &columns | setl nowrap | endif
"     augroup END
"
" Pro: Will probably cover more cases.
"
" Con: WinLeave/WinEnter is not fired after moving a window.

nno   <silent><unique>  ZH      :<c-u>call window#disable_wrap_when_moving_to_vert_split('H')<cr>
nno   <silent><unique>  ZL      :<c-u>call window#disable_wrap_when_moving_to_vert_split('L')<cr>
nmap          <unique>  <c-w>L  ZL
nmap          <unique>  <c-w>H  ZH

" ZQ  ZZ {{{3

" Our `SPC q` mapping is special, it creates a session file so that we can undo
" the closing of the window. `ZQ` should behave in the same way.

nmap  <unique>  ZQ  <space>q

" Restore original `ZZ` (C-w Z doesn't do anything).
nno <plug>(my_ZZ_update) :<c-u>update<cr>
nmap <silent> ZZ <plug>(my_ZZ_update)<plug>(my_quit)
" }}}1
" Options {{{1

" Why setting these options?{{{
"
" When opening a file with long lines, I prefer to do it:
"
"    - on the right if it's vertical
"    - at the bottom if it's horizontal
"
" Rationale:
" When you read a book, the next page is on the right, not on the left.
" When you read a pdf, the next page is below, not above.
"
" ---
"
" However, when displaying  a buffer with short lines (ex: TOC),  I prefer to do
" it on the  left.
"
" Rationale:
" When you write annotations in  a page, you do it  in the left margin.
"
" ---
"
" Bottom Line:
" `set splitbelow` and `set splitright`  seem to define good default directions.
" Punctually  though, we  may  need  `:topleft` or  `:leftabove`  to change  the
" direction.
"}}}

" when we create a new horizontal viewport, it should be displayed at the
" bottom of the screen
set splitbelow

" and a new vertical one should be displayed on the right
set splitright

" Do *not* reset `'equalalways'`!{{{
"
" It would raise `E36` whenever you run `:helpgrep` and the qfl has less than 3 entries.
" Indeed, `:helpgrep` would try to split the qf window to display the first entry.
" But if the window has only 2 lines, and Vim can't resize the windows, it can't
" make more room for the new window.
"
" As a result, you  would never be able to visit any of the 1  or 2 entries of a
" short qfl.
"
" MWE:
"
"     $ vim -Nu NONE +'set noequalalways' +'au QuickFixCmdPost * botright cwindow2' +'helpgrep readnews'
"     E36: Not enough room~
"
"     $ vim -Nu NONE +'set noequalalways' +2sp +sp
"     E36: Not enough room~
"
" ---
"
" If  you  wanted  to fix  this  issue,  you  would  probably have  to  refactor
" `qf#open()`, `s:make_window_small()` and  `s:set_window_height()`, so that the
" minimal height of a window is 3 or more, but never 1 or 2.

"}}}
"   If I find a workaround, how would `'equalalways'` be useful?{{{
"
" When you split a window, by default, all the windows are automatically resized
" to have the same sizes; same thing when you close a window.
" Although, this doesn't seem to be the case when you close a help window.
"
" We disable this feature.
" When we split/close a window, the sizes of the other windows are not affected.
"
" ---
"
" See also this comment:
"
" > If you are talking  about how Gpush forces a resize of  every window, does
" > `:set noequalalways` solve it for you? I  was always frustrated how closing a
" > window causes vim to  resize every split equally, blew my  mind when I found
" > out it was  a design choice that  could be disabled. Used to think  it was a
" > limitation of its window handling or something.
"
" Source: https://www.reddit.com/r/vim/comments/bha7yk/how_to_precisely_control_restore_layouts/elrict0/
"}}}
"     set equalalways

