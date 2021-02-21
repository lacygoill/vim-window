vim9script noclear

if exists('loaded') | finish | endif
var loaded = true

import Catch from 'lg.vim'

def window#quit#main() #{{{1
    # If we are in the command-line window, we want to close the latter,
    # and return without doing anything else (no session save).
    #
    #   ┌ return ':' in a command-line window,
    #   │ nothing in a regular buffer
    #   │
    if !getcmdwintype()->empty()
        q
        return
    endif

    # a sign may be left in the sign column if you close an undotree diff panel with `:q` or `:close`
    if bufname('%') =~ '^diffpanel_\d\+$'
        plugin#undotree#closeDiffPanel()
        return
    endif

    # If we're recording a macro, don't close the window; stop the recording.
    if reg_recording() != ''
        feedkeys('q', 'in')
        return
    endif

    var winnr_max: number = winnr('$')

    # Quit everything if:{{{
    #
    #    - there's only 1 window in 1 tabpage
    #    - there're only 2 windows in 1 tabpage, one of which is a location list window
    #    - there're only 2 windows in 1 tabpage, the remaining one is a diff window
    #}}}
    if tabpagenr('$') == 1
        && (winnr_max == 1
            || winnr_max == 2
            && (getwininfo()
                    ->mapnew((_, v: dict<any>): number => v.loclist)
                    ->index(1) >= 0
                || (winnr() == 1 ? 2 : 1)->getwinvar('&diff')))
        qall!

    elseif &bt == 'terminal'
        # A popup terminal is a special case.{{{
        #
        # We don't want to wipe the buffer; just close the window.
        #}}}
        if window#util#isPopup()
            win_getid()->popup_close()
        else
            bw!
        endif

    else
        var was_loclist: bool = get(b:, 'qf_is_loclist', false)
        # if the window we're closing is associated to a ll window, close the latter too
        # We could also install an autocmd in our vimrc:{{{
        #
        #     au QuitPre * ++nested if &bt != 'quickfix' | lclose | endif
        #
        # Inspiration:
        # https://github.com/romainl/vim-qf/blob/5f971f3ed7f59ff11610c00b8a1e343e2dbae510/plugin/qf.vim#L64-L65
        #
        # But in this  case, we couldn't close the current  window with `:close`
        # at the end of the function.
        # We would have to use `:q`, because `:close` doesn't emit `QuitPre`.
        # For the moment, I prefer to use `:close` because it doesn't close
        # a window if it's the last one.
        #}}}
        lclose

        # if we were already in a loclist window, then `:lclose` has closed it,
        # and there's nothing left to close
        if was_loclist
            return
        endif

        # same thing for preview window, but only in a help buffer outside of
        # preview winwow
        if &bt == 'help' && !&previewwindow
            pclose
        endif

        try
            if tabpagenr('$') == 1
                if getwininfo()
                    ->filter((_, v: dict<any>): bool => v.winid != win_getid())
                    ->mapnew((_, v: dict<any>): string => getbufvar(v.bufnr, '&ft'))
                    ->filter((_, v: string): bool => v != 'help')
                    ->empty()
                    # Why `:close` instead of `:quit`?{{{
                    #
                    #     $ vim
                    #     :h
                    #     C-w w
                    #     :q
                    #
                    # Vim quits entirely instead of only closing the window.
                    # It considers help buffers as unimportant.
                    #
                    # `:close` doesn't close a window if it's the last one.
                    #}}}
                    # Why adding a bang if `&l:bh == 'wipe'`?{{{
                    #
                    # To avoid E37.
                    # Vim refuses to wipe a modified buffer without a bang.
                    # But  if I've  set 'bh'  to  'wipe', it's  probably not  an
                    # important buffer (ex: the one opened by `:DebugVimrc`).
                    # So, I don't want to be bothered by an error.
                    #}}}
                    exe 'close' .. (&l:bh == 'wipe' ? '!' : '')
                    return
                endif
            endif
            # Don't replace `:quit` with `:close`.{{{
            #
            # `:quit` fires `QuitPre`; not `:close`.
            #
            # We need `QuitPre`  to be fired so  that `window#unclose#save()` is
            # automatically called  to save the  current layout, and be  able to
            # undo the closing.
            #}}}
            quit
        catch
            Catch()
            return
        endtry
    endif
enddef

