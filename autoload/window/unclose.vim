vim9script noclear

if exists('loaded') | finish | endif
var loaded = true

# Init {{{1

var undo_layouts: list<dict<any>>

# maximum numbers of windows which can be unclosed
const MAX_UNDO: number = 30

# Interface {{{1
def window#unclose#save() #{{{2
    var layout: dict<any>

    layout.windows = winlayout()
    Winid2bufnr(layout.windows)

    layout.resizecmd = winrestcmd()
    layout.tabpagenr = tabpagenr()
    layout.activewindow = winnr()
    layout.was_onlywindow = winnr('$') == 1
    layout.view = winsaveview()

    undo_layouts += [layout]

    # make sure `undo_layouts` doesn't grow too much
    if len(undo_layouts) > MAX_UNDO
        undo_layouts = undo_layouts[len(undo_layouts) - MAX_UNDO : ]
    endif
enddef

def window#unclose#restore(cnt: number) #{{{2
    if undo_layouts->empty()
        return
    endif

    var layout: dict<any> = undo_layouts[-1]

    # recreate a closed tab page
    if layout.was_onlywindow
        execute ':' .. (layout.tabpagenr - 1) .. 'tabnew'
    endif

    # make sure we're in the right tab page
    try
        execute ':' .. layout.tabpagenr .. 'tabnext'
    # Sometimes, `E16` is raised.{{{
    #
    # Because `layout.tabpagenr` might not match an existing tab page.
    #
    # MWE:
    #
    #     $ vim -S <(cat <<'EOF'
    #         tabedit /tmp/file
    #         split
    #         quit
    #         tabclose
    #         call feedkeys(' U')
    #     EOF
    #     )
    #
    # The issue is  that if you close a  tab page with a command  which does not
    # fire `QuitPre` (like `:tabclose`), then  the last saved layout pertains to
    # a window which was not alone in a tab page; as a result, the previous `if`
    # block does not restore the tab page.
    #
    # We should save the layout right before a tab page is closed, but we cannot
    # listen to `TabClosed`, because it's fired too late:
    #
    #     $ vim -S <(cat <<'EOF'
    #         edit ~/.shrc
    #         tabedit ~/.bashrc
    #         call feedkeys(' q U')
    #     EOF
    #     )
    #
    # The second tab displays `~/.shrc`; it should display `~/.bashrc`.
    #}}}
    catch /^Vim\%((\a\+)\)\=:E16:/
        execute ':' .. (layout.tabpagenr - 1) .. 'tabnew'
        execute ':' .. layout.tabpagenr .. 'tabnext'
    endtry

    # start from a single empty window
    new | only
    var newbuf: number = bufnr('%')

    # restore windows (with correct buffers in them)
    ApplyLayout(layout.windows)
    # restore active window
    win_getid(layout.activewindow)->win_gotoid()
    # restore view
    winrestview(layout.view)
    # restore windows geometry
    execute layout.resizecmd

    # remove used layout
    undo_layouts = undo_layouts[: -2]

    if bufexists(newbuf)
        execute 'bwipeout! ' .. newbuf
    endif
enddef
# }}}1
# Core {{{1
def Winid2bufnr(layout: list<any>) #{{{2
    # add bufnr to leaf{{{
    #
    #     ['leaf', 123] → ['leaf', 456]
    #              ^^^             ^^^
    #              winid            bufnr
    #}}}
    if layout[0] == 'leaf'
        layout[1] = winbufnr(layout[1])
    else
        for child_layout in layout[1]
            Winid2bufnr(child_layout)
        endfor
    endif
enddef

def ApplyLayout(layout: list<any>) #{{{2
    if layout[0] == 'leaf'
        var bufnr: number = layout[1]
        if bufexists(bufnr)
            execute 'buffer ' .. bufnr
        endif
    else
        var split_method: string = {col: 'split', row: 'vsplit'}[layout[0]]
        if split_method == 'split' && &splitright
        || split_method == 'vsplit' && &splitbelow
            split_method = 'rightbelow ' .. split_method

        elseif split_method == 'split' && !&splitright
        || split_method == 'vsplit' && !&splitbelow
            split_method = 'leftabove ' .. split_method
        endif

        # recreate windows for a row or column of the original layout, and save their ids
        var winids: list<number> = [win_getid()]
        for child_layout in layout[1][1 :]
        #                            ├───┘{{{
        #                            └ split n-1 times
        #}}}
            execute split_method
            winids += [win_getid()]
        endfor

        # recurse on child windows
        len(winids)
            ->range()
            ->mapnew((i: number, _) => {
                # focus a recreated window
                winids[i]->win_gotoid()
                # and load  the buffer  it displayed,  or split  it again  if it
                # contained child windows
                layout[1][i]->ApplyLayout()
            })
    endif
enddef

