vim9script noclear

if exists('loaded') | finish | endif
var loaded = true

# Free keys:{{{
#
# By default `C-w [hjkl]` move the focus to a neighbouring window.
# We don't use those; we use `C-[hjkl]` instead.
# So you can map them to anything you like.
#}}}

# Init {{{1

import MapMeta from 'lg/map.vim'
import QfOpenOrFocus from 'lg/window.vim'

# Default height
const D_HEIGHT = 10
# Terminal window
const T_HEIGHT = 10
# Quickfix window
const Q_HEIGHT = 10
# file “Running” current line (tmuxprompt, websearch)
const R_HEIGHT = 5
const R_FT = ['tmuxprompt', 'websearch']

# Autocmds {{{1

# When we switch buffers in the same window, sometimes the view is altered.
# We want it to be preserved.
#
# Inspiration: https://stackoverflow.com/a/31581929/8243465
#
# Similar_issue:
# The position in the changelist is local  to the window.  It should be local to
# the buffer.  We want it to be also preserved when switching buffers.

augroup PreserveViewAndPosInChangelist | au!
    au BufWinLeave * if !IsSpecial() | SaveView() | SaveChangePosition() | endif
    au BufWinEnter * if !IsSpecial() | RestoreChangePosition() | RestoreView() | endif
    # You must restore the view *after* the position in the change list.
    # Otherwise it wouldn't be restored correctly.
augroup END

augroup WindowHeight | au!
    # Why `BufWinEnter`?{{{
    #
    # This is useful when splitting a window to open a "websearch" file.
    # When that happens, and `WinEnter` is fired, the filetype has not yet been set.
    # So `SetWindowHeight()` will not properly set the height of the window.
    #
    # OTOH, when `BufWinEnter` is fired, the filetype *has* been set.
    #}}}
    # Why `VimResized`?{{{
    #
    # Split the Vim window horizontally and focus the top window.
    # Split the tmux window horizontally.
    # Close the tmux pane which you've just opened.
    # Notice how the height of the current Vim window is not maximized anymore.
    #}}}
    au BufWinEnter,WinEnter,VimResized * SetWindowHeight()

    au TerminalWinOpen * SetTerminalHeight()

    # necessary since 8.2.0911
    au CmdWinEnter * exe 'res ' .. &cwh

    # Why ?{{{
    #
    # After running  `:PluginsToCommit` and  pushing a  commit by  pressing `Up`
    # from a fugitive buffer, the current window is not maximized anymore.
    #}}}
    au User Fugitive SetWindowHeight()
augroup END

augroup UncloseWindow | au!
    au QuitPre * window#unclose#save()
augroup END

augroup CustomizePreviewPopup | au!
    au BufWinEnter * CustomizePreviewPopup()
augroup END

# Functions {{{1
def CustomizePreviewPopup() #{{{2
    var winid = win_getid()
    if win_gettype(winid) != 'popup' | return | endif
    setwinvar(winid, '&wincolor', 'Normal')
    # less noise
    var opts = {
        borderchars: ['─', '│', '─', '│', '┌', '┐', '┘', '└'],
        close: 'none',
        resize: false,
        scrollbar: false,
        title: '',
        }
    # Why to delay until the next `WinLeave`?{{{
    #
    # For some reason, the title would not be cleared without the delay.
    # I guess Vim sets it slightly later.
    #}}}
    exe printf('au WinLeave * ++once call popup_setoptions(%d, %s)', winid, opts)
enddef

def GetDiffHeight(n = winnr()): number #{{{2
    # Purpose:{{{
    # Return the height of a horizontal window whose 'diff' option is enabled.
    #
    # Should  return half  the  height of  the  screen,  so that  we  can see  2
    # viewports on the same file.
    #
    # If the available  number of lines is odd, example  29, should consistently
    # return the bigger half to the upper viewport.
    # Otherwise, when we would change the focus between the two viewports, their
    # heights would constantly change ([15, 14] ↔ [14, 15]), which is jarring.
    #}}}

    #                          ┌ the two statuslines of the two diff'ed windows{{{
    #                          │
    #                          │    ┌ if there're several tabpages, there's a tabline;
    #                          │    │ we must take its height into account
    #                          │    │}}}
    var lines = &lines - &ch - 2 - (tabpagenr('$') > 1 ? 1 : 0)
    return fmod(lines, 2) == 0 || n != 1
        ?     lines / 2
        :     lines / 2 + 1
enddef

def HeightShouldBeReset(n: number): bool #{{{2
    # Tests:{{{
    # Whatever change you perform on this  function, make sure the height of the
    # windows are correct after executing:
    #
    #     :vert pedit $MYVIMRC
    #
    # Also, when  moving from  the preview  window to the  regular window  A, in
    # these layouts:
    #
    #    ┌─────────┬───────────┐
    #    │ preview │ regular A │
    #    ├─────────┴───────────┤
    #    │      regular B      │
    #    └─────────────────────┘
    #
    #    ┌───────────┬───────────┐
    #    │ regular A │           │
    #    ├───────────┤ regular B │
    #    │  preview  │           │
    #    └───────────┴───────────┘
    #}}}
    # Interesting_PR:{{{
    # The current code of the function should work most of the time.
    # But not always.  It's based on a heuristic.
    #
    # We may be able to make it work all the time if one day this PR is merged:
    # https://github.com/vim/vim/pull/2521
    #
    # It adds a few VimL functions which  would allow us to test the geometry of
    # the neighbouring windows.
    # We could  use them  to determine  whether we're  working with  two windows
    # piled in a column or in a line.
    #}}}

    # Rationale:
    # We want to reset the height of a special window when it's wide enough.{{{
    #
    # A window with a small width could be a  TOC, and so need a lot of space on
    # the vertical axis to make up for it.
    #}}}
    # We want to reset the height of a preview window when the width of the current window is small enough. {{{
    #
    # If we open a nerdtree-like file  explorer, its window will probably have a
    # small width.
    # Thus, when we will preview a file from the latter, the preview window will
    # have a small width too.
    # Thus, the `winwidth(a:n) >= &columns/2` test will fail.
    # Thus, this window's height won't be reset.
    # Besides, when Vim  goes back from the preview window  to the original one,
    # it will maximize  the latter (if it's a regular  one), which will minimize
    # the preview window.
    # The same issue happens with a vim-plug window.
    #}}}
    return winwidth(n) >= &columns / 2
      ||  (getwinvar(n, '&pvw', 0) && winwidth(0) <= &columns / 2)
enddef

def IfSpecialGetNrHeightTopline(v: number): list<number> #{{{2
#   │                           │
#   │                           └ a window number
#   │
#   └ if it's a special window, get me its number, its desired height, and its current topline

    var info = getwinvar(v, '&pvw', 0)
        ?     [v, &pvh]
        : index(R_FT, winbufnr(v)->getbufvar('&ft', '')) >= 0
        ?     [v, R_HEIGHT]
        : &l:diff
        ?     [v, GetDiffHeight(v)]
        : winbufnr(v)->getbufvar('&bt', '') == 'terminal' && !window#util#isPopup(v)
        ?     [v, T_HEIGHT]
        : winbufnr(v)->getbufvar('&bt', '') == 'quickfix'
        ?     [v, [Q_HEIGHT, [&wmh + 2, winbufnr(v)->getbufline(1, Q_HEIGHT)->len()]->max()]->min()]
        :     []
    # to understand the purpose of `&wmh+2`, see our comments around `'set noequalalways'`
    return empty(info) ? [] : info  + [win_getid(v)->getwininfo()[0].topline]
enddef

def IsAloneInTabpage(): bool #{{{2
    return winnr('$') <= 1
enddef

def IsSpecial(): bool #{{{2
    return &l:pvw
        || &l:diff
        || &ft == 'gitcommit' || index(R_FT, &ft) >= 0
        || &bt =~ '^\%(quickfix\|terminal\)$'
enddef

def IsWide(): bool #{{{2
    return winwidth(0) >= &columns / 2
enddef

def IsMaximizedVertically(): bool #{{{2
    # Every time you open a  window above/below, the difference between `&lines`
    # and `winheight(0)` increases by 2:
    # 1 for the new stl + 1 for the visible line in the other window
    return (&lines - winheight(0)) <= (&ch + 1 + (tabpagenr('$') > 1 ? 1 : 0))
    #                                  ├─┘   │   ├─────────────────────────┘
    #                                  │     │   └ tabline
    #                                  │     │
    #                                  │     └ status line
    #                                  │
    #                                  └ command-line
enddef

def MakeWindowSmall() #{{{2
    # to understand the purpose of `&wmh+2`, see our comments around `'set noequalalways'`
    noa exe 'res ' .. (&l:pvw
        ?              &l:pvh
        :          &bt == 'quickfix'
        ?              min([Q_HEIGHT, max([line('$'), &wmh + 2])])
        :          &l:diff
        ?              GetDiffHeight()
        :          index(R_FT, &ft) >= 0
        ?              R_HEIGHT
        :          D_HEIGHT)
enddef

def SaveChangePosition() #{{{2
    b:_last_change_position = getchangelist('%')->get(1, 100)
enddef

def SaveView() #{{{2
# Save current view settings on a per-window, per-buffer basis.
    if !exists('w:saved_views')
        w:saved_views = {}
    endif
    w:saved_views[bufnr('%')] = winsaveview()
enddef

def SetWindowHeight() #{{{2
    # Goal:{{{
    #
    # Maximize  the  height of  all  windows,  except  the  ones which  are  not
    # horizontally maximized.
    #
    # Preview/qf/terminal windows  which are horizontally maximized  should have
    # their height fixed to:
    #
    #    - &pvh for the preview window
    #    - 10 for a qf/terminal window
    #}}}
    # Problem:{{{
    # Create a tab page with a qf window + a terminal.
    # The terminal is  big when we switch  to the qf window, then  small when we
    # switch back to the terminal.
    #
    # More generally, I think this undesired change of height occur whenever we move
    # in a tab page where there are several windows, but ALL are special.
    # This is  a unique and  probably rare case.  So,  I don't think  it's worth
    # trying and fix it.
    #}}}

    # Why the `#is_popup()` guard?{{{
    #
    # `wincmd _` would raise `E994` in a popup terminal.
    #
    # Note: Not when the  current tab page would contain only  1 window, because
    # in that case `!IsAloneInTabpage()` would be false.
    #}}}
    # Why the `&l:pvw` guard?{{{
    #
    # Suppose we preview a file from a file explorer.
    # Chances are  the file explorer, and  thus the preview window,  are not
    # horizontally maximized.
    #
    # If  we focus  the  preview window,  its  height won't  be  set by  the
    # previous `if` statement, because it's not horizontally maximized.
    # As a result, it will be treated like a regular window and maximized.
    # We don't want that.
    #}}}
    #   Ok, but how will the height of a preview window will be set then?{{{
    #
    # The preview window is a special case.
    # When you open one, 2 WinEnter are fired; when Vim:
    #
    #    1. enters the preview window (&l:pvw is *not* yet set)
    #    2. goes back to the original window (now, &l:pvw *is* set in the preview window)
    #
    # When the first WinEnter is fired, `&l:pvw` is not set.
    # Thus, the function should maximize it.
    #
    # When the second WinEnter is fired, we'll get back to the original window.
    # It'll probably be a regular window, and thus be maximized.
    # As a result, the preview window will be minimized (1 line high).
    # But, the code at the end of this function should restore the height of
    # the preview window.
    #
    # So, in the end, the height of the preview window is correctly set.
    #}}}
    if &l:pvw || window#util#isPopup()
        return
    endif

    if getcmdwintype() != '' | exe 'noa res ' .. &cwh | return | endif

    var curwinnr = winnr()
    if IsSpecial() && IsWide() && !IsAloneInTabpage()
        if winnr('j') != curwinnr || winnr('k') != curwinnr
            MakeWindowSmall()
        endif
        # If there's no window above or below, resetting the height of a special
        # window would lead to a big cmdline.
        return
    endif

    # If we're going to maximize a regular  window, we may alter the height of a
    # special window somewhere else in the current tab page.
    # In this case, we need to reset their height.
    # What's the output of `map()`?{{{
    #
    # All numbers of all special windows in  the current tabpage, as well as the
    # corresponding desired heights and original toplines.
    #}}}
    # Why invoking `filter()`?{{{
    #
    # Each regular window will have produced an empty list in the output of `map()`.
    # An empty list will cause an error in the next `for` loop.
    # So we need to remove them.
    #
    # Also, we shouldn't  reset the height of the current  window; we've already
    # just set its height (`wincmd _`).
    # Only the heights of the other windows:
    #
    #     && v[0] != curwinnr
    #
    # Finally, there're  some special cases,  where we  don't want to  reset the
    # height of a special window.
    # We delegate the logic to handle these in `HeightShouldBeReset()`:
    #
    #     && !HeightShouldBeReset(v[0])
    #}}}
    var special_windows = range(1, winnr('$'))
        ->map((_, v) => IfSpecialGetNrHeightTopline(v))
        ->filter((_, v) => v != []
              && v[0] != curwinnr
              && HeightShouldBeReset(v[0]))

    # if we enter a regular window, maximize it
    noa wincmd _

    # Why does `'so'` need to be temporarily reset?{{{
    #
    # We may need to restore the position  of the topline in a special window by
    # scrolling with `C-e` or `C-y`.
    #
    # When that happens, if `&so` has a  non-zero value, we may scroll more than
    # what we expect.
    #
    # MWE:
    #
    #     $ vim -Nu NONE +'set so=3|helpg foobar' +'cw|2q'
    #     :clast | wincmd _ | 2res 10
    #     :call win_execute(win_getid(2), "norm! \<c-y>")
    #
    # After the first Ex command, the last line of the qf buffer is the topline.
    # The second Ex  command should scroll one line upward;  but in practice, it
    # scrolls 4 lines upward (`1 + &so`).
    #
    # It could be a bug, because I can't always reproduce.
    # For example, if you scroll back so that the last line is again the topline:
    #
    #     :call win_execute(win_getid(2), "norm! 4\<c-e>")
    #
    # Then, invoke `win_execute()` exactly as  when you triggered the unexpected
    # scrolling earlier:
    #
    #     :call win_execute(win_getid(2), "norm! \<c-y>")
    #
    # This time, Vim scrolls only 1 line upward.
    #
    # ---
    #
    # Sth else is weird:
    #
    #     $ vim -Nu NONE +'set so=3|helpg foobar' +'cw|2q'
    #     :clast
    #
    # The last line of the qf buffer is the *last* line of the window.
    #
    #     :wincmd _ | 2res 10
    #
    # The last line of the qf buffer is the *first* line of the window.
    #
    #     :wincmd w | exe "norm! 6\<c-y>" | wincmd w
    #
    # The last line of the qf buffer is the last line of the window.
    #
    #     :wincmd _ | 2res 10
    #
    # The last line of the qf buffer is *still* the last line of the window.
    #
    # So, we  have a unique  command (`:wincmd  _ | 2res  10`) which can  have a
    # different effect on  the qf window; and  the difference is not  due to the
    # view in the latter, because it's always  the same (the last line of the qf
    # buffer is the last line of the window).
    #}}}
    # Warning:{{{
    #
    # `'so'` is global-local.
    # So, to be  completely reliable, we would probably need  to reset the local
    # value of the option.
    # It's not an issue at the moment, because we only set the global value, but
    # keep that in mind.
    #}}}
    var so_save = &so | noa set so=0
    # Why the `HasNeighborAboveOrBelow()` guard?{{{
    #
    # If there's no  window above nor below  the current window, and  we set its
    # height to a few lines only, then the command-line height becomes too big.
    #
    # Try this to understand:
    #
    #     10wincmd _
    #}}}
    map(special_windows, (_, v) => [HasNeighborAboveOrBelow(v[0]), FixSpecialWindow(v)])
    noa &so = so_save
enddef

def HasNeighborAboveOrBelow(winnr: number): bool
    win_execute(win_getid(winnr), 'has_above = winnr("k") != winnr()')
    win_execute(win_getid(winnr), 'has_below = winnr("j") != winnr()')
    return has_above || has_below
enddef
var has_above: bool
var has_below: bool

def FixSpecialWindow(v: list<number>)
    var winnr: number
    var height: number
    var orig_topline: number
    [winnr, height, orig_topline] = v
    # restore the height
    exe 'noa :' .. winnr .. 'res ' .. height
    # restore the original topline
    var id = win_getid(winnr)
    var offset = getwininfo(id)[0].topline - orig_topline
    if offset != 0
        win_execute(id, 'noa norm! ' .. abs(offset) .. (offset > 0 ? "\<c-y>" : "\<c-e>"))
    endif
enddef

def SetTerminalHeight() #{{{2
    if !IsAloneInTabpage() && !IsMaximizedVertically() && !window#util#isPopup()
        exe 'noa res ' .. T_HEIGHT
    endif
enddef

def RestoreChangePosition() #{{{2
    var changelist = getchangelist('%')
    if empty(changelist)
        return
    endif
    var changes: list<dict<number>>
    var curpos: number
    [changes, curpos] = changelist
    if empty(changes)
        return
    endif
    var cnt: number
    if exists('b:_last_change_position')
        cnt = b:_last_change_position - curpos
    else
        cnt = len(changes) - curpos - 1
    endif
    if cnt == 0
        return
    endif
    exe 'sil! norm! ' .. abs(cnt) .. (cnt > 0 ? 'g,' : 'g;')
enddef

fu RestoreView() abort "{{{2
" Restore current view settings.
    let n = bufnr('%')
    if exists('w:saved_views') && has_key(w:saved_views, n)
        if !&l:diff
            call winrestview(w:saved_views[n])
        endif
        unlet! w:saved_views[n]
    else
        " `:h last-position-jump`
        if line("'\"") >= 1 && line("'\"") <= line('$') && &ft !~# 'commit'
            norm! g`"
        endif
    endif
endfu
# }}}1
# Mappings {{{1
# C-[hjkl]             move across windows {{{2

nno <unique> <c-h> <cmd>call window#navigate('h')<cr>
nno <unique> <c-j> <cmd>call window#navigate('j')<cr>
nno <unique> <c-k> <cmd>call window#navigate('k')<cr>
nno <unique> <c-l> <cmd>call window#navigate('l')<cr>

# M-[hjkl] du gg G     scroll popup (or preview) window {{{2

sil! call s:MapMeta('h', '<cmd>call window#popup#scroll("h")<cr>', 'n', 'u')
sil! call s:MapMeta('j', '<cmd>call window#popup#scroll("j")<cr>', 'n', 'u')
sil! call s:MapMeta('k', '<cmd>call window#popup#scroll("k")<cr>', 'n', 'u')
sil! call s:MapMeta('l', '<cmd>call window#popup#scroll("l")<cr>', 'n', 'u')

sil! call s:MapMeta('d', '<cmd>call window#popup#scroll("c-d")<cr>', 'n', 'u')
# Why don't you install a mapping for `M-u`?{{{
#
# It would conflict with the `M-u` mapping from `vim-readline`.
# As a workaround, we've overloaded the latter.
# We make it  check whether a preview  or popup window is opened  in the current
# tab page:
#
#    - if there is one, it scrolls half a page up in the latter
#    - otherwise, it upcases the text up to the end of the next/current word
#}}}

sil! call s:MapMeta('g', '<cmd>call window#popup#scroll("gg")<cr>', 'n', 'u')
sil! call s:MapMeta('G', '<cmd>call window#popup#scroll("G")<cr>', 'n', 'u')

# SPC (prefix) {{{2

# Provide a  `<plug>` mapping  to access  our `window#quit#main()`  function, so
# that we can call it more easily from other plugins.
# Why don't you use `:norm 1 q` to quit in your plugins?{{{
#
# Yes, we did this in the past:
#
#     :nno <buffer> q <cmd>norm 1 q<cr>
#
# But it seems to cause too many issues.
# We  had  one  in  the  past  involving  an  interaction  between  `:norm`  and
# `feedkeys()` with the `t` flag.
#
# I also had a `E169: Command too recursive` error, but I can't reproduce anymore.
# I suspect the issue was somewhere else (maybe the `<space>q` was not installed
# while we  were debugging  sth); nevertheless, the  error message  is confusing.
#
# And the mapping in itself can  be confusing to understand/debug; I much prefer
# a mapping where the lhs is not repeated in the rhs.
#}}}
nmap <unique> <space>q <plug>(my_quit)
nno <unique> <plug>(my_quit) <cmd>call window#quit#main()<cr>
xno <unique> <space>q <c-\><c-n><cmd>call window#quit#main()<cr>
nno <unique> <space>Q <cmd>qa!<cr>
xno <unique> <space>Q <cmd>qa!<cr>
# Why not `SPC u`?{{{
#
# We often type it by accident.
# When  that happens,  it's  very distracting,  because it  takes  some time  to
# recover the original layout.
#
# Let's try `SPC U`; it should be harder to press by accident.
#}}}
nno <unique> <space>U <cmd>call window#unclose#restore(v:count1)<cr>
nno <unique> <space>u <nop>

nno <unique> <space>z <cmd>call window#zoomToggle()<cr>

# C-w (prefix) {{{2

# update window's height – with `do WinEnter` – when we move it at the very top/bottom
nno <unique> <c-w>J <cmd>wincmd J<bar>do <nomodeline> WinEnter<cr>
nno <unique> <c-w>K <cmd>wincmd K<bar>do <nomodeline> WinEnter<cr>

# disable `'wrap'` when turning a split into a vertical one
# Alternative:{{{
#
#     augroup NowrapInVertSplits | au!
#         au WinLeave * if winwidth(0) != &columns | setl nowrap | endif
#         au WinEnter * if winwidth(0) != &columns | setl nowrap | endif
#     augroup END
#
# Pro: Will probably cover more cases.
#
# Con: WinLeave/WinEnter is not fired after moving a window.
#}}}
nno <unique> <c-w>H <cmd>call window#disableWrapWhenMovingToVertSplit('H')<cr>
nno <unique> <c-w>L <cmd>call window#disableWrapWhenMovingToVertSplit('L')<cr>

# open path in split window/tabpage and unfold
# `C-w f`, `C-w F`, `C-w gf`, ... I'm confused!{{{
#
# Some default normal commands can open a path in another split window or tabpage.
# They all start with the prefix `C-w`.
#
# To understand which suffix must be pressed, see:
#
#    ┌────┬──────────────────────────────────────────────────────────────┐
#    │ f  │ split window                                                 │
#    ├────┼──────────────────────────────────────────────────────────────┤
#    │ F  │ split window, taking into account line indicator like `:123` │
#    ├────┼──────────────────────────────────────────────────────────────┤
#    │ gf │ tabpage                                                      │
#    ├────┼──────────────────────────────────────────────────────────────┤
#    │ gF │ tabpage, taking into account line indicator like `:123`      │
#    └────┴──────────────────────────────────────────────────────────────┘
#}}}
nno <c-w>f <c-w>fzv
nno <c-w>F <c-w>Fzv

nno <c-w>gf <c-w>gfzv
nno <c-w>gF <c-w>gFzv
nno <c-w>GF <c-w>GFzv
# easier to press `ZGF` than `ZgF`

xno <c-w>f <c-w>fzv
xno <c-w>F <c-w>Fzv

xno <c-w>gf <c-w>gfzv
xno <c-w>gF <c-w>gFzv
xno <c-w>GF <c-w>GFzv

# TODO:
# Implement a `<C-w>F` visual mapping which would take into account a line address.
# Like `<C-w>F` does in normal mode.
#
# Also, move all mappings which open a path into a dedicated plugin (`vim-gf`).
#}}}2
# z (prefix) {{{2
# z <>              open/focus/close terminal window {{{3
#
# Why `do WinEnter`?{{{
#
# To update the height of the focused window.
# Atm, we have an autocmd listening  to `WinEnter` which maximizes the height of
# windows displaying a non-special buffer.
#
# So, if  we are in such  a window, we expect  its height to still  be maximized
# after closing a terminal/qf/preview window.
# But that's not what happens without `do WinEnter`:
#
#     $ vim +'sp|helpg foobar'
#     :wincmd t
#     :cclose
#}}}
nno <unique> z< <cmd>call window#terminalOpen()<cr>
nno <unique> z> <cmd>call window#terminalClose()<bar>do <nomodeline> WinEnter<cr>

# z ()  z []                         qf/ll    window {{{3

nno <unique> z( <cmd>call <sid>QfOpenOrFocus('qf')<cr>
nno <unique> z) <cmd>cclose<bar>do <nomodeline> WinEnter<cr>

nno <unique> z[ <cmd>call <sid>QfOpenOrFocus('loc')<cr>
nno <unique> z] <cmd>lclose<bar>do <nomodeline> WinEnter<cr>

# z {}                               preview  window {{{3

nno <unique> z{ <cmd>call window#previewOpen()<cr>
nno <unique> z} <c-w>z<cmd>do <nomodeline> WinEnter<cr>

# zp                close all popup/foating windows {{{3

nno <unique> zp <cmd>call window#popup#closeAll()<cr>

# z C-[hjkl]        resize window {{{3

# Why using the `z` prefix instead of the `Z` one?{{{
#
# Easier to type.
#
# `Z C-h`  would mean pressing  the right shift with  our right pinky,  then the
# left control with our left pinky.
# That's 2 pinkys, on different hands; too awkward.
#}}}
# Why `<plug>` mappings?{{{
#
# Useful to make them repeatable from another script, via functions provided by `vim-submode`.
#}}}
nmap <unique> z<c-h> <plug>(window-resize-h)
nmap <unique> z<c-j> <plug>(window-resize-j)
nmap <unique> z<c-k> <plug>(window-resize-k)
nmap <unique> z<c-l> <plug>(window-resize-l)

nno <plug>(window-resize-h) <cmd>call window#resize('h')<cr>
nno <plug>(window-resize-j) <cmd>call window#resize('j')<cr>
nno <plug>(window-resize-k) <cmd>call window#resize('k')<cr>
nno <plug>(window-resize-l) <cmd>call window#resize('l')<cr>

# z[hjkl]           split in any direction {{{3

nno <unique> zh <cmd>setl nowrap <bar> leftabove vsplit  <bar> setl nowrap<cr>
nno <unique> zl <cmd>setl nowrap <bar> rightbelow vsplit <bar> setl nowrap<cr>
nno <unique> zj <cmd>belowright split<cr>
nno <unique> zk <cmd>aboveleft split<cr>
#}}}2
# Z (prefix) {{{2
# Z                 simpler window prefix {{{3

# Why a *recursive* mapping?{{{
#
# We need the recursiveness, so that, when we type, we can replace <c-w>
# with Z in custom mappings (own+third party).
#
# MWE:
#
#     nno <c-w><cr> <cmd>echo 'hello'<cr>
#     nno Z <c-w>
#     " press 'Z cr': doesn't work ✘
#
#     nno <c-w><cr> <cmd>echo 'hello'<cr>
#     nmap Z <c-w>
#     " press 'Z cr': works ✔
#
# Indeed,  once `Z`  has been  expanded into  `C-w`, we  may need  to expand  it
# *further* for custom mappings using `C-w` in their lhs.
#}}}
nmap <unique> Z <c-w>
# Why no `<unique>`?{{{
#
# `vim-sneak` installs a `Z` mapping:
#
#     xmap Z <Plug>Sneak_S
#
# See: `~/.vim/plugged/vim-sneak/plugin/sneak.vim`
#}}}
xmap          Z <c-w>

# ZQ  ZZ {{{3

# Our `SPC q` mapping is special, it creates a session file so that we can undo
# the closing of the window. `ZQ` should behave in the same way.

nmap <unique> ZQ <space>q

# If we press `ZZ`, Vim will remap the keys into `C-w Z`, which doesn't do anything.
# We need to restore `ZZ` original behavior.
nmap ZZ <plug>(my_ZZ_update)<plug>(my_quit)
nno <plug>(my_ZZ_update) <cmd>update<cr>
# }}}1
# Options {{{1

# Purpose:{{{
#
# When you split a window, by default, all the windows are automatically resized
# to have the same height.
# Also when you close a window; although,  this doesn't seem to be the case when
# you close a help window.
#
# This  is annoying  in  various  situations, because  it  can *un*maximize  the
# current window, and *un*squash the non-focused windows.
#
# For example, suppose that:
#
#    - you have 2 horizontal splits
#    - you open our custom file explorer fex (`-t`)
#    - you move your cursor on a file path
#    - you open it in a vertical split (`C-w f`)
#    - you close the latter (`:q`)
#
# The original 2 horizontal splits are unexpectedly resized.
#
# All of this  shows that it's a general issue which can  affect you in too many
# circumstances.
# Trying to handle  each of them is a  waste of time; let's fix  the root cause;
# let's disable `'ea'`.
#}}}
set noequalalways
# Which pitfall should I be aware of when resetting `'ea'`?{{{
#
# It can  cause `E36`  to be  raised whenever  you try  to visit  a qf  entry by
# pressing Enter in the qf window, while the latter is only 1 line high.
#
# Example:
#
#     $ vim +'helpg Arthur!'
#     :res 1
#     " press Enter
#
# Indeed, Vim tries to split the qf window to display the entry.
# But if  the window is only  1 line high, and  Vim can't resize any  window, it
# can't make more room for the new one.
#
# MWE:
#
#     $ vim -Nu NONE +'set noea' +'au QuickFixCmdPost * bo cwindow2' +'helpg readnews'
#     E36: Not enough room~
#
#     $ vim -Nu NONE +'set noea' +2sp +sp
#     E36: Not enough room~
#
# In the last example, the final `:sp` raises `E36`, because:
#
#    - creating a second window would require 2 lines
#      (one for the text – because `'wmh'` is 1 – and one for the status line)
#
#    - the top window would still need 2 lines (one for the text, and one for its status line)
#
#    - the top window occupies 3 lines, which is not enough for 2 + 2 lines;
#      it needs to be resized, but Vim can't because `'ea'` is reset
#
# ---
#
# That's why we make sure – here and  in `vim-qf` – that the qf window is always
# at least `&wmh+2` lines high.
#}}}

# Why setting `'splitbelow'` and `'splitright'`?{{{
#
# When opening a file with long lines, I prefer to do it:
#
#    - on the right if it's vertical
#    - at the bottom if it's horizontal
#
# Rationale:
# When you read a book, the next page is on the right, not on the left.
# When you read a pdf, the next page is below, not above.
#
# ---
#
# However, when displaying  a buffer with short lines (ex: TOC),  I prefer to do
# it on the  left.
#
# Rationale:
# When you write annotations in  a page, you do it  in the left margin.
#
# ---
#
# Bottom Line:
# `set splitbelow` and `set splitright`  seem to define good default directions.
# Punctually  though, we  may  need  `:topleft` or  `:leftabove`  to change  the
# direction.
#}}}
# when we create a new horizontal viewport, it should be displayed at the bottom of the screen
set splitbelow
# and a new vertical one should be displayed on the right
set splitright

# let us squash an unfocused window to 0 lines
set winminheight=0
# let us squash an unfocused window to 0 columns (useful when we zoom a window with `SPC z`)
set winminwidth=0

augroup SetPreviewPopupHeights | au!
    au VimEnter,VimResized * SetPreviewPopupHeights()
augroup END

def SetPreviewPopupHeights()
    &previewheight = &lines / 3
    # make commands which by default would open a preview window, use a popup instead
    #
    #     &previewpopup = printf('highlight:Normal,height:%d,width:%d', &pvh, (&columns * 2 / 3))

    # TODO: It causes an issue with some of our commands/mappings; like `!m` for example.
    #
    # This is because  `debug#log#output()` runs `:wincmd P`  which is forbidden
    # when the preview window is also a popup window.
    # Adapt your  code (everywhere) so that  it works whether you  use a regular
    # preview window, or a popup preview window.
enddef

