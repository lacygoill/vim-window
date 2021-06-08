vim9script noclear

def window#util#isPopup(n: number = win_getid()): bool #{{{1
    return win_gettype(n) == 'popup'
enddef

def window#util#latestPopup(): number #{{{1
    return popup_list()->max()
enddef

def window#util#hasPreview(): bool #{{{1
    # Why is this a public function?{{{
    #
    # To be able to invoke it from the readline plugin (`window#popup#scroll()`).
    #}}}
    # What if we have a preview *popup*?{{{
    #
    # Then we want this function to return false, because when it's true, we use
    # `wincmd P`  to focus the  window, which fails  (`E441`) when the  tab page
    # only  contains a  preview popup.   For  Vim, a  preview popup  is *not*  a
    # preview window, even though it has the 'previewwindow' flag set.
    #
    # It turns out that `#has_preview()` *does* return false in that case.
    # That's because  – to find  the preview window –  it iterates over  all the
    # windows which have a number; a popup doesn't have a number (an id yes, but
    # number != id).
    #
    # So, the  function returns what  we want, even if  the preview window  is a
    # popup; all is good.
    #}}}
    return range(1, winnr('$'))
        ->mapnew((_, v: number): bool => getwinvar(v, '&previewwindow'))
        ->index(true) >= 0
enddef

