vim9script noclear

if exists('loaded') | finish | endif
var loaded = true

# Init {{{1

const AOF_KEY2NORM: dict<string> = {
    j: 'j',
    k: 'k',
    h: '5zh',
    l: '5zl',
    c-d: "\<c-d>",
    c-u: "\<c-u>",
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
            topline = wininfo[0].topline
        endif
    else
        view = winsaveview()
    endif

    # `true` to close a popup terminal and avoid `E994`
    popup_clear(true)

    if topline != 0
        var so_save: number = &l:so
        setl so=0
        exe 'norm! ' .. topline .. 'GztM'
        #                              ^
        # middle of the window to minimize the distance from the original cursor position
        &l:so = so_save
    elseif !empty('view')
        winrestview(view)
    endif
enddef

def window#popup#scroll(lhs: string) #{{{2
    if window#util#hasPreview()
        ScrollPreview(lhs)
    else
        var popup: number = window#util#latestPopup()
        if popup != 0
            ScrollPopup(lhs, popup)
        endif
    endif
enddef
#}}}1
# Core {{{1
def ScrollPreview(lhs: string) #{{{2
    var curwin: number = win_getid()
    # go to preview window
    noa wincmd P

    # Useful to see where we are.{{{
    #
    # Would not be necessary if we *scrolled* with `C-e`/`C-y`.
    # But it is necessary because we *move* with `j`/`k`.
    #
    # We can't use `C-e`/`C-y`; it wouldn't work as expected because of `zMzv`.
    #}}}
    if !&l:cul
        setl cul
    endif

    # move/scroll
    exe GetScrollingCmd(lhs)

    # get back to previous window
    noa win_gotoid(curwin)
enddef

def ScrollPopup(lhs: string, winid: number) #{{{2
    # let us see the current line in the popup
    setwinvar(winid, '&cursorline', true)
    GetScrollingCmd(lhs)->win_execute(winid)
enddef

def GetScrollingCmd(lhs: string): string #{{{2
    return 'sil! norm! zR'
        # make `M-j` and `M-k` scroll through *screen* lines, not buffer lines
        .. (index(['j', 'k'], lhs) >= 0 ? 'g' : '')
        .. AOF_KEY2NORM[lhs]
        .. 'zMzv'
    # `zMzv` may cause the distance between the current line and the first line of the window to change unexpectedly.{{{
    #
    # If that bothers you, you could improve the function.
    # See how we handled the issue in `MoveAndOpenFold()` from:
    #
    #     ~/.vim/plugged/vim-toggle-settings/autoload/toggle_settings.vim
    #}}}
enddef
#}}}1
