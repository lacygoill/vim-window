if exists('g:loaded_window')
    finish
endif
let g:loaded_window = 1

" Free keys:{{{
"
" By default `C-w [hjkl]` move the focus to a neighbouring window.
" We don't use those; we use `C-[hjkl]` instead.
" So you can map them to anything you like.
"}}}

" Init {{{1

" Default height
const s:D_HEIGHT = 10
" Terminal window
const s:T_HEIGHT = 10
" Quickfix window
const s:Q_HEIGHT = 10
" file “Running” current line (tmuxprompt, websearch)
const s:R_HEIGHT = 5
const s:R_FT = ['tmuxprompt', 'websearch']

" Autocmds {{{1

" When we switch buffers in the same window, sometimes the view is altered.
" We want it to be preserved.
"
" Inspiration: https://stackoverflow.com/a/31581929/8243465
"
" Similar_issue:
" The position in the changelist is local to the window. It should be local
" to the buffer. We want it to be also preserved when switching buffers.

augroup preserve_view_and_pos_in_changelist | au!
    au BufWinLeave * if !s:is_special() | call s:save_view() | call s:save_change_position() | endif
    au BufWinEnter * if !s:is_special() | call s:restore_change_position() | call s:restore_view() | endif
    " You must restore the view *after* the position in the change list.
    " Otherwise it wouldn't be restored correctly.
augroup END

augroup window_height | au!
    exe 'au '..(has('nvim') ? 'TermOpen' : 'TerminalWinOpen')..' * call s:set_terminal_height()'
    " Why `BufWinEnter`?{{{
    "
    " This is useful when splitting a window to open a "websearch" file.
    " When that happens, and `WinEnter` is fired, the filetype has not yet been set.
    " So `s:set_window_height()` will not properly set the height of the window.
    "
    " OTOH, when `BufWinEnter` is fired, the filetype *has* been set.
    "}}}
    " Why `VimResized`?{{{
    "
    " Split the Vim window horizontally and focus the top window.
    " Split the tmux window horizontally.
    " Close the tmux pane which you've just opened.
    " Notice how the height of the current Vim window is not maximized anymore.
    "}}}
    au BufWinEnter,WinEnter,VimResized * call s:set_window_height()
    " Why ?{{{
    "
    " After running  `:PluginsToCommit` and  pushing a  commit by  pressing `Up`
    " from a fugitive buffer, the current window is not maximized anymore.
    "}}}
    au User Fugitive call s:set_window_height()
    " TODO: This autocmd is only necessary in Nvim, probably because of a missing Vim patch (8.1.2227 ?).
    " Try to remove it in the future.
    if has('nvim')
        " Purpose:{{{
        "
        "     $ vim ~/.shrc
        "     :sp
        "     :call system('tmux splitw \; lastp')
        "     " press `q:`
        "     :call system('tmux killp -t :.-')
        "     " press `q` to close command-line window: the height of the focused window is not maximized
        "
        " This example is fixed in Vim (but not in Nvim) if you disable `'ea'`.
        "
        " MWE:
        "
        "     " open xterm without tmux
        "     $ nvim -Nu NONE +'au WinEnter * wincmd _' +'bo sp' +'set lines=10' +'call feedkeys("q:", "in")'
        "     :set lines=30
        "     :q
        "
        " The  height  of  the new  focused  window  is  6  (height of  the  old
        " command-line window + 2).
        " The `+2` comes from the status line and the text line of the above window.
        " If you  set `'wmh'` to 0,  the height of  the new focused window  is 7
        " (height of the old command-line window + 1).
        "
        " If you replace `bo sp` with `sp`:
        "
        "    - the previous window changes from 2 to 1
        "    - the issue is not triggered
        "
        " ---
        "
        " You really need  a timer; I tried to install  a one-shot autocmd after
        " `CmdWinLeave` is fired, listening to  various events, but none of them
        " worked (except for `CursorHold` which is too late for my liking).
        "}}}
        au CmdWinLeave * call timer_start(0, {-> s:set_window_height()})
    endif
augroup END

augroup unclose_window | au!
    au QuitPre * call window#unclose#save()
augroup END

if has('nvim')
    " https://github.com/neovim/neovim/issues/11313
    augroup fix_winline | au!
        au WinLeave * if !get(g:, 'SessionLoad', 0)
            \ | let w:fix_winline = {'winline': winline(), 'pos': getcurpos()}
            \ | endif
        au WinEnter * au CursorMoved * ++once call s:fix_winline()
    augroup END
else
    augroup customize_preview_popup | au!
        au BufWinEnter * call s:customize_preview_popup()
    augroup END
endif

" Functions {{{1
fu s:customize_preview_popup() abort "{{{2
    let winid = win_getid()
    if win_gettype(winid) isnot# 'popup' | return | endif
    call setwinvar(winid, '&wincolor', 'Normal')
    " less noise
    let opts = #{
        \ borderchars: ['─', '│', '─', '│', '┌', '┐', '┘', '└'],
        \ close: 'none',
        \ resize: v:false,
        \ scrollbar: v:false,
        \ title: '',
        \ }
    " Why to delay until the next `WinLeave`?{{{
    "
    " For some reason, the title would not be cleared without the delay.
    " I guess Vim sets it slightly later.
    "}}}
    exe printf('au WinLeave * ++once call popup_setoptions(%d, %s)', winid, opts)
endfu

fu s:fix_winline() abort "{{{2
    if !exists('w:fix_winline') | return | endif
    " TODO: If one day Nvim fixes this issue, make sure it also fixes the MWE which follows.{{{
    "
    " Perform this check with all your configuration.
    " And perform a check with a fold starting on the second line of `/tmp/x.vim`
    " (I had a similar issue in the past which could only be reproduced when
    " a fold started on the second line).
    "}}}
    " Sometimes, the original position is lost.{{{
    "
    " MWE:
    "
    "     $ printf -- 'a\nb' >/tmp/x.vim; nvim -Nu NONE +'filetype on|set wmh=0|au BufWinEnter,WinEnter * noa wincmd _' +'au FileType * noa wincmd p|noa wincmd p' +1 /tmp/x.vim
    "     :sp /tmp/y.vim
    "     :wincmd w
    "     " the cursor is on line 2, while originally it was on line 1
    "}}}
    if getcurpos() != w:fix_winline.pos
        call setpos('.', w:fix_winline.pos)
    endif
    let offset = w:fix_winline.winline - winline()
    if offset == 0 | return | endif
    exe 'norm! '..abs(offset)..(offset > 0 ? "\<c-y>" : "\<c-e>")
endfu

fu s:get_diff_height(...) abort "{{{2
    " Purpose:{{{
    " Return the height of a horizontal window whose 'diff' option is enabled.
    "
    " Should  return half  the  height of  the  screen,  so that  we  can see  2
    " viewports on the same file.
    "
    " If the available  number of lines is odd, example  29, should consistently
    " return the bigger half to the upper viewport.
    " Otherwise, when we would change the focus between the two viewports, their
    " heights would constantly change ([15,14] ↔ [14,15]), which is jarring.
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

fu s:height_should_be_reset(nr) abort "{{{2
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
endfu

fu s:if_special_get_nr_height_topline(v) abort "{{{2
"    │                                │
"    │                                └ a window number
"    │
"    └ if it's a special window, get me its number, its desired height, and its current topline

    let info = getwinvar(a:v, '&pvw', 0)
        \ ?     [a:v, &pvh]
        \ : index(s:R_FT, getbufvar(winbufnr(a:v), '&ft', '')) >= 0
        \ ?     [a:v, s:R_HEIGHT]
        \ : &l:diff
        \ ?     [a:v, s:get_diff_height(a:v)]
        \ : getbufvar(winbufnr(a:v), '&bt', '') is# 'terminal' && !window#util#is_popup(a:v)
        \ ?     [a:v, s:T_HEIGHT]
        \ : getbufvar(winbufnr(a:v), '&bt', '') is# 'quickfix'
        \ ?     [a:v, min([s:Q_HEIGHT, max([&wmh+2, len(getbufline(winbufnr(a:v), 1, s:Q_HEIGHT))])])]
        \ :     []
    " to understand the purpose of `&wmh+2`, see our comments around `'set noequalalways'`
    return empty(info) ? [] : info  + [getwininfo(win_getid(a:v))[0].topline]
endfu

fu s:is_alone_in_tabpage() abort "{{{2
    return winnr('$') <= 1
endfu

fu s:is_special() abort "{{{2
    return &l:pvw
      \ || &l:diff
      \ || &ft is# 'gitcommit' || index(s:R_FT, &ft) >= 0
      \ || &bt =~# '^\%(quickfix\|terminal\)$'
endfu

fu s:is_wide() abort "{{{2
    return winwidth(0) >= &columns/2
endfu

fu s:is_maximized_vertically() abort "{{{2
    " Every time you open a  window above/below, the difference between `&lines`
    " and `winheight(0)` increases by 2:
    " 1 for the new stl + 1 for the visible line in the other window
    return (&lines - winheight(0)) <= (&ch + 1 + (tabpagenr('$') > 1))
    "                                  ├─┘   │   ├──────────────────┘
    "                                  │     │   └ tabline
    "                                  │     │
    "                                  │     └ status line
    "                                  │
    "                                  └ command-line
endfu

fu s:make_window_small() abort "{{{2
    " to understand the purpose of `&wmh+2`, see our comments around `'set noequalalways'`
    noa exe 'res '..(&l:pvw
        \ ?              &l:pvh
        \ :          &bt is# 'quickfix'
        \ ?              min([s:Q_HEIGHT, max([line('$'), &wmh + 2])])
        \ :          &l:diff
        \ ?              s:get_diff_height()
        \ :          index(s:R_FT, &ft) >= 0
        \ ?              s:R_HEIGHT
        \ :          s:D_HEIGHT)
endfu

fu s:save_change_position() abort "{{{2
    let changelist = get(getchangelist('%'), 0, [])
    let b:_change_position = get(getchangelist('%'), 1, -1)
    if b:_change_position == -1
        let b:_change_position = 100
    endif
endfu

fu s:save_view() abort "{{{2
" Save current view settings on a per-window, per-buffer basis.
    if !exists('w:saved_views')
        let w:saved_views = {}
    endif
    let w:saved_views[bufnr('%')] = winsaveview()
endfu

fu s:set_window_height() abort "{{{2
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

    " Why the `#is_popup()` guard?{{{
    "
    " In Nvim, we don't want to maximize a floating window.
    "}}}
    " Why the `&l:pvw` guard?{{{
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
    "   Ok, but how will the height of a preview window will be set then?{{{
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
    if &l:pvw || window#util#is_popup()
        return
    endif

    if getcmdwintype() isnot# '' | noa exe 'res '..&cwh | return | endif

    let curwinnr = winnr()
    if s:is_special() && s:is_wide() && !s:is_alone_in_tabpage()
        if winnr('j') != curwinnr || winnr('k') != curwinnr
            call s:make_window_small()
        endif
        " If there's no window above or below, resetting the height of a special
        " window would lead to a big cmdline.
        return
    endif

    " If we're going to maximize a regular  window, we may alter the height of a
    " special window somewhere else in the current tab page.
    " In this case, we need to reset their height.
    " What's the output of `map()`?{{{
    "
    " All numbers of all special windows in  the current tabpage, as well as the
    " corresponding desired heights and original toplines.
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
    "     && v[0] != curwinnr
    "
    " Finally, there're  some special cases,  where we  don't want to  reset the
    " height of a special window.
    " We delegate the logic to handle these in `s:height_should_be_reset()`:
    "
    "     && !s:height_should_be_reset(v[0])
    "}}}
    let special_windows = filter(map(
        \ range(1, winnr('$')),
        \ {_,v -> s:if_special_get_nr_height_topline(v)}),
        \ {_,v -> v !=# []
        \      && v[0] != curwinnr
        \      && s:height_should_be_reset(v[0])})

    " if we enter a regular window, maximize it
    noa wincmd _

    " Why does `'so'` need to be temporarily reset?{{{
    "
    " We may need to restore the position  of the topline in a special window by
    " scrolling with `C-e` or `C-y`.
    "
    " When that happens, if `&so` has a  non-zero value, we may scroll more than
    " what we expect.
    "
    " MWE:
    "
    "     $ vim -Nu NONE +'set so=3|helpg foobar' +'cw|2q'
    "     :clast | wincmd _ | 2res 10
    "     :call win_execute(win_getid(2), "norm! \<c-y>")
    "
    " After the first Ex command, the last line of the qf buffer is the topline.
    " The second Ex  command should scroll one line upward;  but in practice, it
    " scrolls 4 lines upward (`1 + &so`).
    "
    " It could be a bug, because I can't always reproduce.
    " For example, if you scroll back so that the last line is again the topline:
    "
    "     :call win_execute(win_getid(2), "norm! 4\<c-e>")
    "
    " Then, invoke `win_execute()` exactly as  when you triggered the unexpected
    " scrolling earlier:
    "
    "     :call win_execute(win_getid(2), "norm! \<c-y>")
    "
    " This time, Vim scrolls only 1 line upward.
    "
    " ---
    "
    " Sth else is weird:
    "
    "     $ vim -Nu NONE +'set so=3|helpg foobar' +'cw|2q'
    "     :clast
    "
    " The last line of the qf buffer is the *last* line of the window.
    "
    "     :wincmd _ | 2res 10
    "
    " The last line of the qf buffer is the *first* line of the window.
    "
    "     :wincmd w | exe "norm! 6\<c-y>" | wincmd w
    "
    " The last line of the qf buffer is the last line of the window.
    "
    "     :wincmd _ | 2res 10
    "
    " The last line of the qf buffer is *still* the last line of the window.
    "
    " So, we  have a unique  command (`:wincmd  _ | 2res  10`) which can  have a
    " different effect on  the qf window; and  the difference is not  due to the
    " view in the latter, because it's always  the same (the last line of the qf
    " buffer is the last line of the window).
    "}}}
    " Warning:{{{
    "
    " In Vim, `'so'` is global-local (in Nvim, it's still global).
    " So, to be  completely reliable, we would probably need  to reset the local
    " value of the option.
    " It's not an issue at the moment, because we only set the global value, but
    " keep that in mind.
    "}}}
    let so_save = &so | noa set so=0
    " Why the `s:has_neighbor_above_or_below()` guard?{{{
    "
    " If there's no  window above nor below  the current window, and  we set its
    " height to a few lines only, then the command-line height becomes too big.
    "
    " Try this to understand:
    "
    "     10wincmd _
    "}}}
    call map(special_windows, {_,v -> s:has_neighbor_above_or_below(v[0]) && s:fix_special_window(v)})
    noa let &so = so_save
endfu

fu s:has_neighbor_above_or_below(winnr) abort
    " TODO: Once Nvim supports `win_execute()`, rewrite the function like this:{{{
    "
    "     call win_execute(win_getid(a:winnr), 'let has_above = winnr("k") != winnr()')
    "     call win_execute(win_getid(a:winnr), 'let has_below = winnr("j") != winnr()')
    "     return has_above || has_below
    "}}}
    let has_above = lg#win_execute(win_getid(a:winnr), 'echo winnr("k") != winnr()')[1:]
    let has_below = lg#win_execute(win_getid(a:winnr), 'echo winnr("j") != winnr()')[1:]
    return has_above || has_below
endfu

fu s:fix_special_window(v) abort
    let [winnr, height, orig_topline] = a:v
    " restore the height
    noa exe winnr..'res '..height
    " restore the original topline
    let id = win_getid(winnr)
    let offset = getwininfo(id)[0].topline - orig_topline
    if offset
        call lg#win_execute(id, 'noa norm! '..abs(offset)..(offset > 0 ? "\<c-y>" : "\<c-e>"))
    endif
endfu

fu s:set_terminal_height() abort "{{{2
    if !s:is_alone_in_tabpage() && !s:is_maximized_vertically() && !window#util#is_popup()
        noa exe 'res '..s:T_HEIGHT
    endif
endfu

fu s:restore_change_position() abort "{{{2
    if !exists('b:_change_position')
        " Why this guard `!empty(...)`?{{{
        "
        " Without, it creates a little noise when we debug Vim with `:set vbs=2 vfile=/tmp/log`:
        "
        "     E664: changelist is empty
        "     Error detected while processing function <SNR>103_restore_change_position:
        "}}}
        if !empty(get(getchangelist(0), 0, []))
            sil! norm! 99g,
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
    \ ..(b:_change_position == 1 ? 'g,' : (b:_change_position - 1)..'g,')
endfu

fu s:restore_view() abort "{{{2
" Restore current view settings.
    let n = bufnr('%')
    if exists('w:saved_views') && has_key(w:saved_views, n)
        if !&l:diff
            call winrestview(w:saved_views[n])
        endif
        unlet w:saved_views[n]
    else
        " `:h last-position-jump`
        if line("'\"") >= 1 && line("'\"") <= line('$') && &ft !~# 'commit'
            norm! g`"
        endif
    endif
endfu
" }}}1
" Mappings {{{1
" C-[hjkl]             move across windows {{{2

nno <silent><unique> <c-h> :<c-u>call window#navigate('h')<cr>
nno <silent><unique> <c-j> :<c-u>call window#navigate('j')<cr>
nno <silent><unique> <c-k> :<c-u>call window#navigate('k')<cr>
nno <silent><unique> <c-l> :<c-u>call window#navigate('l')<cr>

" M-[hjkl] du gg G     scroll popup (or preview) window {{{2

sil! call lg#map#meta('h', ':<c-u>call window#popup#scroll("h")<cr>', 'n', 'su')
sil! call lg#map#meta('j', ':<c-u>call window#popup#scroll("j")<cr>', 'n', 'su')
sil! call lg#map#meta('k', ':<c-u>call window#popup#scroll("k")<cr>', 'n', 'su')
sil! call lg#map#meta('l', ':<c-u>call window#popup#scroll("l")<cr>', 'n', 'su')

sil! call lg#map#meta('d', ':<c-u>call window#popup#scroll("c-d")<cr>', 'n', 'su')
" Why don't you install a mapping for `M-u`?{{{
"
" It would conflict with the `M-u` mapping from `vim-readline`.
" As a workaround, we've overloaded the latter.
" We make it  check whether a preview  or popup window is opened  in the current
" tab page:
"
"    - if there is one, it scrolls half a page up in the latter
"    - otherwise, it upcases the text up to the end of the next/current word
"}}}

sil! call lg#map#meta('g', ':<c-u>call window#popup#scroll("gg")<cr>', 'n', 'su')
sil! call lg#map#meta('G', ':<c-u>call window#popup#scroll("G")<cr>', 'n', 'su')

" SPC (prefix) {{{2

" Provide a  `<plug>` mapping  to access  our `window#quit#main()`  function, so
" that we can call it more easily from other plugins.
" Why don't you use `:norm 1 q` to quit in your plugins?{{{
"
" Yes, we did this in the past:
"
"     :nno <buffer> q :norm 1 q<cr>
"
" But it seems to cause too many issues.
" We  had  one  in  the  past  involving  an  interaction  between  `:norm`  and
" `feedkeys()` with the `t` flag.
"
" I also had a `E169: Command too recursive` error, but I can't reproduce anymore.
" I suspect the issue was somewhere else (maybe the `<space>q` was not installed
" while we  were debugging  sth); nevertheless, the  error message  is confusing.
"
" And the mapping in itself can  be confusing to understand/debug; I much prefer
" a mapping where the lhs is not repeated in the rhs.
"}}}
nmap <silent><unique> <space>q <plug>(my_quit)
nno <silent><unique> <plug>(my_quit) :<c-u>call window#quit#main()<cr>
xno <silent><unique> <space>q :<c-u>call window#quit#main()<cr>
nno <silent><unique> <space>Q :<c-u>qa!<cr>
xno <silent><unique> <space>Q :<c-u>qa!<cr>
" Why not `SPC u`?{{{
"
" We often type it by accident.
" When  that happens,  it's  very distracting,  because it  takes  some time  to
" recover the original layout.
"
" Let's try `SPC U`; it should be harder to press by accident.
"}}}
nno <silent><unique> <space>U :<c-u>call window#unclose#restore(v:count1)<cr>
nno <silent><unique> <space>u <nop>

nno <silent><unique> <space>z :<c-u>call window#zoom_toggle()<cr>

" C-w (prefix) {{{2

" update window's height – with `do WinEnter` – when we move it at the very top/bottom
nno <silent><unique> <c-w>J :<c-u>wincmd J<bar>do <nomodeline> WinEnter<cr>
nno <silent><unique> <c-w>K :<c-u>wincmd K<bar>do <nomodeline> WinEnter<cr>

" disable `'wrap'` when turning a split into a vertical one
" Alternative:{{{
"
"     augroup nowrap_in_vert_splits | au!
"         au WinLeave * if winwidth(0) != &columns | setl nowrap | endif
"         au WinEnter * if winwidth(0) != &columns | setl nowrap | endif
"     augroup END
"
" Pro: Will probably cover more cases.
"
" Con: WinLeave/WinEnter is not fired after moving a window.
"}}}
nno <silent><unique> <c-w>H :<c-u>call window#disable_wrap_when_moving_to_vert_split('H')<cr>
nno <silent><unique> <c-w>L :<c-u>call window#disable_wrap_when_moving_to_vert_split('L')<cr>

" open path in split window/tabpage and unfold
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
"}}}2
" z (prefix) {{{2
" z <>              open/focus/close terminal window {{{3

" Why `do WinEnter`?{{{
"
" To update the height of the focused window.
" Atm, we have an autocmd listening  to `WinEnter` which maximizes the height of
" windows displaying a non-special buffer.
"
" So, if  we are in such  a window, we expect  its height to still  be maximized
" after closing a terminal/qf/preview window.
" But that's not what happens without `do WinEnter`:
"
"     $ vim +'sp|helpg foobar'
"     :wincmd t
"     :cclose
"}}}
nno <silent><unique> z< :<c-u>call window#terminal_open()<cr>
nno <silent><unique> z> :<c-u>call window#terminal_close()<bar>do <nomodeline> WinEnter<cr>

"z ()  z []                         qf/ll    window {{{3

nno <silent><unique> z( :<c-u>call lg#window#qf_open_or_focus('qf')<cr>
nno <silent><unique> z) :<c-u>cclose<bar>do <nomodeline> WinEnter<cr>

nno <silent><unique> z[ :<c-u>call lg#window#qf_open_or_focus('loc')<cr>
nno <silent><unique> z] :<c-u>lclose<bar>do <nomodeline> WinEnter<cr>

" z {}                               preview  window {{{3

nno <silent><unique> z{ :<c-u>call window#preview_open()<cr>
nno <silent><unique> z} <c-w>z:do <nomodeline> WinEnter<cr>

" zp                close all popup/foating windows {{{3

nno <silent><unique> zp :<c-u>call window#popup#close_all()<cr>

" z C-[hjkl]        resize window {{{3

" Why using the `z` prefix instead of the `Z` one?{{{
"
" Easier to type.
"
" `Z C-h`  would mean pressing  the right shift with  our right pinky,  then the
" left control with our left pinky.
" That's 2 pinkys, on different hands; too awkward.
"}}}
" Why `<plug>` mappings?{{{
"
" Useful to make them repeatable from another script, via functions provided by `vim-submode`.
"}}}
nmap <unique> z<c-h> <plug>(window-resize-h)
nmap <unique> z<c-j> <plug>(window-resize-j)
nmap <unique> z<c-k> <plug>(window-resize-k)
nmap <unique> z<c-l> <plug>(window-resize-l)

nno <silent> <plug>(window-resize-h) :<c-u>call window#resize('h')<cr>
nno <silent> <plug>(window-resize-j) :<c-u>call window#resize('j')<cr>
nno <silent> <plug>(window-resize-k) :<c-u>call window#resize('k')<cr>
nno <silent> <plug>(window-resize-l) :<c-u>call window#resize('l')<cr>

" z[hjkl]           split in any direction {{{3

nno <silent><unique> zh :<c-u>setl nowrap <bar> leftabove vsplit  <bar> setl nowrap<cr>
nno <silent><unique> zl :<c-u>setl nowrap <bar> rightbelow vsplit <bar> setl nowrap<cr>
nno <silent><unique> zj :<c-u>belowright split<cr>
nno <silent><unique> zk :<c-u>aboveleft split<cr>
"}}}2
" Z (prefix) {{{2
" Z                 simpler window prefix {{{3

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

" ZQ  ZZ {{{3

" Our `SPC q` mapping is special, it creates a session file so that we can undo
" the closing of the window. `ZQ` should behave in the same way.

nmap <unique> ZQ <space>q

" If we press `ZZ`, Vim will remap the keys into `C-w Z`, which doesn't do anything.
" We need to restore `ZZ` original behavior.
nmap <silent> ZZ <plug>(my_ZZ_update)<plug>(my_quit)
nno <plug>(my_ZZ_update) :<c-u>update<cr>
" }}}1
" Options {{{1

" Purpose:{{{
"
" When you split a window, by default, all the windows are automatically resized
" to have the same height.
" Also when you close a window; although,  this doesn't seem to be the case when
" you close a help window.
"
" This  is annoying  in  various  situations, because  it  can *un*maximize  the
" current window, and *un*squash the non-focused windows.
"
" For example, suppose that:
"
"    - you have 2 horizontal splits
"    - you open our custom file explorer fex (`-t`)
"    - you move your cursor on a file path
"    - you open it in a vertical split (`C-w f`)
"    - you close the latter (`:q`)
"
" The original 2 horizontal splits are unexpectedly resized.
"
" All of this  shows that it's a general issue which can  affect you in too many
" circumstances.
" Trying to handle  each of them is a  waste of time; let's fix  the root cause;
" let's disable `'ea'`.
"}}}
set noequalalways
" Which pitfall should I be aware of when resetting `'ea'`?{{{
"
" It can  cause `E36`  to be  raised whenever  you try  to visit  a qf  entry by
" pressing Enter in the qf window, while the latter is only 1 line high.
"
" Example:
"
"     $ vim +'helpg Arthur!'
"     :res 1
"     " press Enter
"
" Indeed, Vim tries to split the qf window to display the entry.
" But if  the window is only  1 line high, and  Vim can't resize any  window, it
" can't make more room for the new one.
"
" MWE:
"
"     $ vim -Nu NONE +'set noea' +'au QuickFixCmdPost * bo cwindow2' +'helpg readnews'
"     E36: Not enough room~
"
"     $ vim -Nu NONE +'set noea' +2sp +sp
"     E36: Not enough room~
"
" In the last example, the final `:sp` raises `E36`, because:
"
"    - creating a second window would require 2 lines
"      (one for the text – because `'wmh'` is 1 – and one for the status line)
"
"    - the top window would still need 2 lines (one for the text, and one for its status line)
"
"    - the top window occupies 3 lines, which is not enough for 2 + 2 lines;
"      it needs to be resized, but Vim can't because `'ea'` is reset
"
" ---
"
" That's why we make sure – here and  in `vim-qf` – that the qf window is always
" at least `&wmh+2` lines high.
"}}}

" Why setting `'splitbelow'` and `'splitright'`?{{{
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
" when we create a new horizontal viewport, it should be displayed at the bottom of the screen
set splitbelow
" and a new vertical one should be displayed on the right
set splitright

" let us squash an unfocused window to 0 lines
set winminheight=0
" let us squash an unfocused window to 0 columns (useful when we zoom a window with `SPC z`)
set winminwidth=0

augroup set_preview_popup_heights | au!
    au VimEnter,VimResized * call s:set_preview_popup_heights()
augroup END

fu s:set_preview_popup_heights() abort
    let &previewheight = &lines/3
    if !has('nvim')
        " make commands which by default would open a preview window, use a popup instead
        "     let &previewpopup = 'height:'..&pvh..',width:'..(&columns*2/3)

        " TODO: It causes an issue with some of our commands/mappings; like `!m` for example.
        "
        " This is because  `debug#log#output()` runs `:wincmd P`  which is forbidden
        " when the preview window is also a popup window.
        " Adapt your  code (everywhere) so that  it works whether you  use a regular
        " preview window, or a popup preview window.
    endif
endfu

