fu window#quit#main() abort "{{{1
    " If we are in the command-line window, we want to close the latter,
    " and return without doing anything else (no session save).
    "
    "         ┌ return ':' in a command-line window,
    "         │ nothing in a regular buffer
    "         │
    if !empty(getcmdwintype()) | q | return | endif

    " a sign may be left in the sign column if you close an undotree diff panel with `:q` or `:close`
    if bufname('%') =~# '^diffpanel_\d\+$'
        return plugin#undotree#close_diff_panel()
    endif

    " If we're recording a macro, don't close the window; stop the recording.
    if reg_recording() isnot# '' | return feedkeys('q', 'in')[-1] | endif

    " In Nvim, a floating window has a number, and thus increases the value of `winnr('$')`.{{{
    " This is not the case for a popup window in Vim.
    "
    " Because of that, in Nvim, if we  press `SPC q` while only 1 regular window
    " – as  well as 1 floating  window – is  opened, `E444` is raised  (the code
    " path ends up executing `:close` instead of `:qall!`).
    " We need  to ignore  floating windows  when computing  the total  number of
    " windows opened  in the current  tab page; we do  this by making  sure that
    " `nvim_win_get_config(1234)` does *not* have the key `anchor`.
    "
    " From `:h nvim_open_win()`:
    "
    " > •  `anchor` : Decides which corner of the float to place at (row,col):
    " >   • "NW" northwest (default)
    " >   • "NE" northeast
    " >   • "SW" southwest
    " >   • "SE" southeast
    "
    " ---
    "
    " Is there a better way to detect whether a window is a float?
    "}}}
    if has('nvim')
        let winnr_max = len(filter(range(1, winnr('$')),
            \ {_,v -> !has_key(nvim_win_get_config(win_getid(v)), 'anchor')}))
    else
        let winnr_max = winnr('$')
    endif

    " Quit everything if:{{{
    "
    "    - there's only 1 window in 1 tabpage
    "    - there're only 2 windows in 1 tabpage, one of which is a location list window
    "    - there're only 2 windows in 1 tabpage, the remaining one is a diff window
    "}}}
    if tabpagenr('$') == 1
       \ && (
       \         winnr_max == 1
       \      || winnr_max == 2
       \         && (
       \                index(map(getwininfo(), {_,v -> v.loclist}), 1) >= 0
       \             || getwinvar(winnr() == 1 ? 2 : 1, '&diff')
       \            )
       \    )
        qall!

    " In neovim, we could also test the existence of `b:terminal_job_pid`.
    elseif &bt is# 'terminal'
        " A popup terminal is a special case.{{{
        "
        " We don't want to wipe the buffer; just close the window.
        "}}}
        if window#util#is_popup()
            if has('nvim') | close | else | call popup_close(win_getid()) | endif
        else
            bw!
        endif

    else
        let was_loclist = get(b:, 'qf_is_loclist', 0)
        " if the window we're closing is associated to a ll window, close the latter too
        " We could also install an autocmd in our vimrc:{{{
        "
        "     au QuitPre * ++nested if &bt isnot# 'quickfix' | lclose | endif
        "
        " Inspiration:
        " https://github.com/romainl/vim-qf/blob/5f971f3ed7f59ff11610c00b8a1e343e2dbae510/plugin/qf.vim#L64-L65
        "
        " But in this  case, we couldn't close the current  window with `:close`
        " at the end of the function.
        " We would have to use `:q`, because `:close` doesn't emit `QuitPre`.
        " For the moment, I prefer to use `:close` because it doesn't close
        " a window if it's the last one.
        "}}}
        lclose

        " if we were already in a loclist window, then `:lclose` has closed it,
        " and there's nothing left to close
        if was_loclist | return | endif

        " same thing for preview window, but only in a help buffer outside of
        " preview winwow
        if &bt is# 'help' && !&previewwindow | pclose | endif

        try
            if tabpagenr('$') == 1
                let wininfo = getwininfo()
                call filter(wininfo, {_,v -> v.winid != win_getid()})
                call filter(map(wininfo, {_,v -> getbufvar(v.bufnr, '&ft')}), {_,v -> v !=# 'help'})
                if empty(wininfo)
                    " Why `:close` instead of `:quit`?{{{
                    "
                    "     $ vim
                    "     :h
                    "     C-w w
                    "     :q
                    "
                    " Vim quits entirely instead of only closing the window.
                    " It considers help buffers as unimportant.
                    "
                    " `:close` doesn't close a window if it's the last one.
                    "}}}
                    " Why adding a bang if `&l:bh is# 'wipe'`?{{{
                    "
                    " To avoid E37.
                    " Vim refuses to wipe a modified buffer without a bang.
                    " But  if I've  set 'bh'  to  'wipe', it's  probably not  an
                    " important buffer (ex: the one opened by `:DebugVimrc`).
                    " So, I don't want to be bothered by an error.
                    "}}}
                    exe 'close'..(&l:bh is# 'wipe' ? '!' : '')
                    return
                endif
            endif
            " Don't replace `:q` with `:close`.{{{
            "
            " `:q` fires `QuitPre`; not `:close`.
            "
            " We need `QuitPre`  to be fired so  that `window#unclose#save()` is
            " automatically called  to save the  current layout, and be  able to
            " undo the closing.
            "}}}
            q
        catch
            return lg#catch()
        endtry
    endif
endfu

