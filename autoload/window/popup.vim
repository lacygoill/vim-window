vim9script noclear

# Init {{{1

var next_line_is_folded: bool
var should_scroll_tmux_previous_pane: bool

const INVALIDATE_CACHE: number = 500

const AOF_KEY2NORM: dict<string> = {
    j: 'j',
    k: 'k',
    h: '5zh',
    l: '5zl',
    C-d: "\<C-D>",
    C-u: "\<C-U>",
    gg: 'gg',
    G: 'G',
}

# Interface {{{1
def window#popup#closeAll() #{{{2
    var view: dict<number>
    var topline: number
    # If we're in a popup window, it will be closed; we want to preserve the view in the *previous* window.{{{
    #
    # Not the view in the *current* window.
    #
    # Unfortunately, we  can't get the  last line address  of the cursor  in the
    # previous window; we could save it via a `WinLeave` autocmd, but it doesn't
    # seem worth the hassle.
    #
    # OTOH, we can get the topline, which for the moment is good enough.
    #}}}
    if window#util#isPopup()
        var wininfo: list<dict<any>> = winnr('#')->win_getid()->getwininfo()
        if !empty(wininfo)
            topline = wininfo[0]['topline']
        endif
    else
        view = winsaveview()
    endif

    # `true` to close a popup terminal and avoid `E994`
    popup_clear(true)

    if topline != 0
        var scrolloff_save: number = &l:scrolloff
        &l:scrolloff = 0
        execute 'normal! ' .. topline .. 'GztM'
        #                                    ^
        # middle of the window to minimize the distance from the original cursor position
        &l:scrolloff = scrolloff_save
    elseif !empty('view')
        winrestview(view)
    endif
enddef

def window#popup#scroll(lhs: string) #{{{2
    if window#util#hasPreview()
        ScrollPreview(lhs)
        return
    endif

    var popup: number = window#util#latestPopup()
    if popup != 0
        ScrollPopup(lhs, popup)
        return
    endif

    if exists('$TMUX')
        if ScrollTmuxPreviousPane(lhs)
            return
        endif
    endif

    if lhs == 'C-u'
        # We've pressed `M-u`, but there is nothing to scroll:
        # upcase the text up to the end of the current/next word.
        readline#changeCaseSetup(true)
        &operatorfunc = 'readline#changeCaseWord'
        normal! g@l
    endif
enddef
#}}}1
# Core {{{1
def ScrollPreview(lhs: string) #{{{2
    var curwin: number = win_getid()
    # go to preview window
    noautocmd wincmd P

    # Useful to see where we are.{{{
    #
    # Would not be necessary if we *scrolled* with `C-e`/`C-y`.
    # But it is necessary because we *move* with `j`/`k`.
    #
    # We can't use `C-e`/`C-y`; it wouldn't work as expected because of `zMzv`.
    #}}}
    if !&l:cursorline
        &l:cursorline = true
        # If we  re-display the previewed buffer  later in a regular  window, we
        # don't want Vim to automatically set `'cursorline'`.
        autocmd BufWinEnter <buffer> ++once &l:cursorline = false
    endif

    # move/scroll
    execute GetScrollingCmd(lhs, curwin)

    # get back to previous window
    noautocmd win_gotoid(curwin)
enddef

def ScrollPopup(lhs: string, winid: number) #{{{2
    # let us see the current line in the popup
    setwinvar(winid, '&cursorline', true)
    GetScrollingCmd(lhs, winid)->win_execute(winid)
enddef

def ScrollTmuxPreviousPane(lhs: string): bool #{{{2
# Ask tmux to scroll the previous pane if:{{{
#
#    - it runs a shell
#    - it's in copy-mode
#    - the current pane is not maximized
#    - the scrolling is vertical
#}}}
    if index(['j', 'k', 'gg', 'G', 'C-d', 'C-u'], lhs) < 0
        return false
    endif
    if !should_scroll_tmux_previous_pane
        var tmux_cmd: string =
             'tmux display -p -t "{last}" "#{pane_current_command}"'
            .. '\; display -p             "#{window_zoomed_flag}"'
        # `system()` is too slow when we keep pressing a key; so we cache its output.
        silent should_scroll_tmux_previous_pane =
            system(tmux_cmd)
                ->trim("\n") =~ '^\%(ba\|z\)\=sh\n0$'
        # Invalidate the cache after an arbitrary short time.
        timer_start(INVALIDATE_CACHE, (_) => {
            should_scroll_tmux_previous_pane = false
        })
    endif
    if should_scroll_tmux_previous_pane
        printf('tmux lastp ; copy-mode ; send -X %s ; lastp', {
            k: 'scroll-up',
            j: 'scroll-down-and-cancel',
            gg: 'history-top',
            G: 'history-bottom',
            C-d: 'halfpage-down',
            C-u: 'halfpage-up',
        }[lhs])->job_start()
        return true
    endif
    return false
enddef

def GetScrollingCmd(lhs: string, winid: number): string #{{{2
    # FIXME: `zRj` sometimes fails to move the cursor.{{{
    #
    # It only happens when the height of the popup is not limited.
    #
    # MWE:
    #
    #     let winid = ['some text']->repeat(&lines * 2)->popup_create({})
    #     call setwinvar(winid, '&cursorline', v:true)
    #     call setwinvar(winid, '&number', v:true)
    #     call win_execute(winid, 'normal! ' .. &lines .. 'G')
    #     call win_execute(winid, 'normal! zRj')
    #
    # That's why here, we need to return `zR` only if really necessary.
    # Otherwise, we can't scroll beyond the first screen of a long popup window.
    #}}}
    win_execute(winid, 'next_line_is_folded = foldclosed(line(".") + 1) != -1')
    return 'silent! normal! ' .. (next_line_is_folded ? 'zR' : '')
        # make `M-j` and `M-k` scroll through *screen* lines, not buffer lines
        .. (index(['j', 'k'], lhs) >= 0 ? 'g' : '')
        .. AOF_KEY2NORM[lhs]
        .. (next_line_is_folded ? 'zMzv' : '')
    # `zMzv` may cause the distance between the current line and the first line of the window to change unexpectedly.{{{
    #
    # If that bothers you, you could improve the function.
    # See how we handled the issue in `MoveAndOpenFold()` from:
    #
    #     ~/.vim/pack/mine/opt/toggleSettings/plugin/toggleSettings.vim
    #}}}
enddef
#}}}1
