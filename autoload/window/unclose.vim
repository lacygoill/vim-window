if exists('g:autoloaded_window#unclose')
    finish
endif
let g:autoloaded_window#unclose = 1

" Init {{{1

" maximum numbers of windows which can be unclosed
const s:MAX_UNDO = 30

" Interface {{{1
fu window#unclose#save() abort "{{{2
    let layout = {}

    let layout.windows = winlayout()
    call s:winid2bufnr(layout.windows)

    let layout.resizecmd = winrestcmd()
    let layout.tabpagenr = tabpagenr()
    let layout.activewindow = winnr()
    let layout.was_onlywindow = winnr('$') == 1
    let layout.view = winsaveview()

    let s:undo_layouts = get(s:, 'undo_layouts', []) + [layout]

    " make sure `s:undo_layouts` doesn't grow too much
    if len(s:undo_layouts) > s:MAX_UNDO
        let s:undo_layouts = s:undo_layouts[len(s:undo_layouts) - s:MAX_UNDO :]
    endif
endfu

fu window#unclose#restore(cnt) abort "{{{2
    if get(s:, 'undo_layouts', [])->empty()
        return
    endif

    let layout = s:undo_layouts[-1]

    " recreate a closed tab page
    if layout.was_onlywindow
        exe (layout.tabpagenr - 1) .. 'tabnew'
    endif

    " make sure we're in the right tab page
    try
        exe layout.tabpagenr .. 'tabnext'
    " Sometimes, `E16` is raised.{{{
    "
    " Because `layout.tabpagenr` might not match an existing tab page.
    "
    " MWE:
    "
    "     $ vim -S <(cat <<'EOF'
    "         tabe /tmp/file
    "         sp
    "         q
    "         tabclose
    "         call feedkeys(' U')
    "     EOF
    "     )
    "
    " The issue is  that if you close a  tab page with a command  which does not
    " fire `QuitPre` (like `:tabclose`), then  the last saved layout pertains to
    " a window which was not alone in a tab page; as a result, the previous `if`
    " block does not restore the tab page.
    "
    " We should save the layout right before a tab page is closed, but we cannot
    " listen to `TabClosed`, because it's fired too late:
    "
    "     $ vim -S <(cat <<'EOF'
    "         e ~/.shrc
    "         tabe ~/.bashrc
    "         call feedkeys(' q U')
    "     EOF
    "     )
    "
    " The second tab displays `~/.shrc`; it should display `~/.bashrc`.
    "}}}
    " FIXME: There are still cases where `:tabclose` prevents us from getting back the right layout.{{{
    "
    "     $ vim -S <(cat <<'EOF'
    "         e /tmp/file1
    "         sp /tmp/file2
    "         let id = win_getid()
    "         tabe /tmp/file3
    "         call win_gotoid(id)
    "         q
    "         tabclose
    "     EOF
    "     )
    "
    "     " press:  SPC u
    "     " expected:  we get back 2 tab pages
    "     " actual:  we only have 1 tab page
    "
    " Maybe we  need to save the  layout when a tab  page is closed as  a whole.
    " But `TabClosed` seems to be fired too late (in the context of the tab page
    " where the focus switches to).
    " When a  tab page is  closed, Vim fires `TabLeave`  (in the context  of the
    " closed tab page), `TabClosed`, then `TabEnter`.
    "
    " I've tried to  install autocmds listening to all these  events and come up
    " with a mechanism  to save the layout  when a tab is really  closed, and in
    " the right context,  but it doesn't work  well.  One of the  reason is that
    " even when  `TabLeave` is fired the  layout is already incorrect  (we're in
    " the right tab page, but `winnr('$')` returns 1 even if the closed tab page
    " contains more than 1 window).
    "}}}
    catch /^Vim\%((\a\+)\)\=:E16:/
        exe (layout.tabpagenr - 1) .. 'tabnew'
        exe layout.tabpagenr .. 'tabnext'
    endtry

    " start from a single empty window
    new | only
    let newbuf = bufnr('%')

    " restore windows (with correct buffers in them)
    call s:apply_layout(layout.windows)
    " restore active window
    exe layout.activewindow .. 'wincmd w'
    " restore view
    call winrestview(layout.view)
    " restore windows geometry
    exe layout.resizecmd

    " remove used layout
    let s:undo_layouts = s:undo_layouts[:-2]

    if bufexists(newbuf)
        exe 'bw! ' .. newbuf
    endif
endfu
" }}}1
" Core {{{1
fu s:winid2bufnr(layout) abort "{{{2
    " add bufnr to leaf{{{
    "
    "     ['leaf', 123] → ['leaf', 456]
    "              ^-^             ^-^
    "              winid            bufnr
    "}}}
    if a:layout[0] is# 'leaf'
        let a:layout[1] = winbufnr(a:layout[1])
    else
        for child_layout in a:layout[1]
            call s:winid2bufnr(child_layout)
        endfor
    endif
endfu

fu s:apply_layout(layout) abort "{{{2
    if a:layout[0] is# 'leaf'
        let bufnr = a:layout[1]
        if bufexists(bufnr)
            exe 'b ' .. bufnr
        endif
    else
        let split_method = #{col: 'sp', row: 'vs'}[a:layout[0]]
        if split_method is# 'sp' && &spr || split_method is# 'vs' && &sb
            let split_method = 'rightb ' .. split_method
        elseif split_method is# 'sp' && &nospr || split_method is# 'vs' && &nosb
            let split_method = 'lefta ' .. split_method
        endif

        " recreate windows for a row or column of the original layout, and save their ids
        let winids = [win_getid()]
        for child_layout in a:layout[1][1:]
        "                              ├──┘{{{
        "                              └ split n-1 times
        "}}}
            exe split_method
            let winids += [win_getid()]
        endfor

        " recurse on child windows
        call len(winids)
            \ ->range()
            \ ->map('win_gotoid(winids[v:key]) + s:apply_layout(a:layout[1][v:key])')
        "            │                           │
        "            │                           └ and load the buffer it displayed,
        "            │                             or split it again if it contained child windows
        "            └ focus a recreated window
    endif
endfu

