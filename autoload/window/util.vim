fu window#util#is_popup(...) abort "{{{1
    let n = a:0 ? win_getid(a:1) : win_getid()
    return has('nvim') && has_key(nvim_win_get_config(n), 'anchor')
        \ || !has('nvim') && win_gettype(n) is# 'popup'
endfu

