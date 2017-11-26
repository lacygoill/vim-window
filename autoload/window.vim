fu! window#get_modifier_to_open_window() abort "{{{1
"   └─────┤
"         └ public so that it can be called in `vim-qf` (`qf#open()` in autoload/),
"           and in our vimrc
    let origin = winnr()

    " are we at the bottom of the tabpage?
    wincmd b
    if winnr() == origin
        let mod = 'botright'
    else
        wincmd p
        " or maybe at the top?
        wincmd t
        if winnr() == origin
            let mod = 'topleft'
        else
            " ok we're in a middle window
            wincmd p
            let mod = 'vert belowright'
        endif
    endif

    return mod
endfu
