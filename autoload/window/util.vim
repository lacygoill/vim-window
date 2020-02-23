fu window#util#is_popup() abort "{{{1
    return has('nvim') && has_key(nvim_win_get_config(0), 'anchor')
        \ || !has('nvim') && win_gettype() is# 'popup'
endfu

