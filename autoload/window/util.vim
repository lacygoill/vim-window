fu window#util#is_popup(...) abort "{{{1
    let n = win_getid(a:0 ? a:1 : 0)
    return has('nvim') && has_key(nvim_win_get_config(n), 'anchor')
        \ || !has('nvim') && win_gettype(n) is# 'popup'
endfu

