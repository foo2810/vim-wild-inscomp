" Copyright (c) 2023 hogedamari
" Released under the MIT license
" License notice:
" https://github.com/foo2810/vim-wild-inscomp/blob/main/LICENSE

if exists("g:loaded_wild_ins_comp")
    finish
endif
let g:loaded_wild_ins_comp = 1

set completeopt=""

" imap <C-L> <C-N><Cmd>call g:WIC_ins_comp(1)<CR>
" imap <C-K> <C-P><Cmd>call g:WIC_ins_comp(-1)<CR>
imap <C-N> <C-N><Cmd>call g:WIC_ins_comp(1)<CR>
imap <C-P> <C-P><Cmd>call g:WIC_ins_comp(-1)<CR>
imap <C-E> <C-E><Cmd>call g:WIC_exit()<CR>

augroup ins_comp_wildmenu
    au!
    au InsertLeave * call g:WIC_exit()
    au InsertCharPre * call g:WIC_exit()
    au ModeChanged * call g:WIC_exit()
augroup END


" @direction 1 or -1. 1 imply "forward", -1 imply "backward"
function! g:WIC_ins_comp(direction) abort
    let l:comp_info = complete_info()

    if !exists("b:WIC_flg")
        let b:WIC_flg = 0
    endif

    " In first execution, variables are initialized
    if !b:WIC_flg
        " In vim's ins-completion, information of complete_info() is different
        " for forward match (Ctrl+P) and backward match (Ctrl+N).
        " To consider this difference, the mode is saved.
        if a:direction == 1
            let b:WIC_word_list = deepcopy(map(l:comp_info["items"], 'v:val["word"]'))
            let b:WIC_mode = "forward"
        else
            let b:WIC_word_list = deepcopy(map(l:comp_info["items"], 'v:val["word"]'))
            let b:WIC_mode = "backward"
        endif

        let b:WIC_flg = 1
        call g:WIC_init()
        call g:WIC_draw()
        return
    endif

    " -1 indicates not selecting candidate  (original word is selected)
    let b:WIC_cidx = l:comp_info["selected"]

    if b:WIC_cidx == -1
        if b:WIC_mode == "forward"
            let b:WIC_win_sidx = 0
            let b:WIC_win_eidx = s:WIC_get_next_window_fw(b:WIC_word_list, b:WIC_win_sidx, 0)
        elseif b:WIC_mode == "backward"
            let b:WIC_win_eidx = len(b:WIC_word_list) - 1
            let b:WIC_win_sidx = s:WIC_get_next_window_bw(b:WIC_word_list, b:WIC_win_eidx, len(b:WIC_word_list) - 1)
        else
            throw printf("BUGON: unexpected mode - %s (g:WIC_ins_comp)", b:WIC_mode)
        endif
    else
        if b:WIC_mode == "backward"
            " Consistent Ctrl+L and Ctrl+K actions in forward and backward matching.
            " This is the same behavior as completeopt="menu".
            let b:WIC_cidx = len(b:WIC_word_list) - b:WIC_cidx - 1
        endif
        call g:WIC_update(a:direction)
    endif

    call g:WIC_draw()
endfunction

" Initialize inner states
function g:WIC_init() abort
    if b:WIC_mode == "forward"
        let b:WIC_win_sidx = 0
        let b:WIC_cidx = b:WIC_win_sidx
        let b:WIC_win_eidx = s:WIC_get_next_window_fw(b:WIC_word_list, b:WIC_win_sidx, 0)
    elseif b:WIC_mode == "backward"
        let b:WIC_win_eidx = len(b:WIC_word_list) - 1
        let b:WIC_cidx = b:WIC_win_eidx
        let b:WIC_win_sidx = s:WIC_get_next_window_bw(b:WIC_word_list, b:WIC_win_eidx, len(b:WIC_word_list)-1)
    else
        throw printf("BUGON: unexpected mode - %s (g:WIC_init)", b:WIC_mode)
    endif

    " save status line
    let b:WIC_save_status_line = &statusline
endfunction

" Exit process
function! g:WIC_exit() abort
    if !exists("b:WIC_flg")
        return
    endif
    if b:WIC_flg == 1
        " recover status line
        execute "set statusline=" . escape(b:WIC_save_status_line, ' ')

        let b:WIC_flg = 0
        let b:data = []
        let b:WIC_cidx = 0

        let b:WIC_win_sidx = -1
        let b:WIC_win_eidx = -1
    endif
endfunction


" Update inner states
" @direction 1 or -1. 1 imply "forward", -1 imply "backward"
function g:WIC_update(direction) abort
    let b:rel_cidx = b:WIC_cidx - b:WIC_win_sidx

    " In case the next candidate is outside the window,
    " the window is updated to include the next one.
    if b:rel_cidx >= b:WIC_win_eidx - b:WIC_win_sidx + 1
        let l:dist = b:rel_cidx - (b:WIC_win_eidx - b:WIC_win_sidx)
        let b:WIC_win_eidx = b:WIC_win_eidx + l:dist
        let b:WIC_win_sidx = s:WIC_get_next_window_bw(b:WIC_word_list, b:WIC_win_eidx, b:WIC_cidx)
        call g:WIC_draw()
        return
    endif

    " In case the prev candidate is outside the window,
    " the window is updated to include the prev one.
    if b:rel_cidx <= - 1
        let l:dist = abs(b:rel_cidx)
        let b:WIC_win_sidx = b:WIC_win_sidx - l:dist
        let b:WIC_win_eidx = s:WIC_get_next_window_fw(b:WIC_word_list, b:WIC_win_sidx, b:WIC_cidx)
        call g:WIC_draw()
        return
    endif
endfunction

" Redraw status line
function! g:WIC_draw() abort
    let l:sline = s:WIC_gen_status_line(b:WIC_word_list, b:WIC_win_sidx, b:WIC_win_eidx, b:WIC_cidx)
    execute "setlocal statusline=" . escape(l:sline, ' ')
endfunction


" --- Helper functions ---
" Generate string of status line
" @words    all word candidates
" @w_sidx   start index of window
" @w_eidx   end index of window (word of w_eidx is included in window)
" @cidx     current selected index in entire candidates
"
" Return string of status line
function! s:WIC_gen_status_line(words, w_sidx, w_eidx, cidx) abort
    let l:tmp_words = deepcopy(a:words[a:w_sidx:a:w_eidx])

    if a:cidx >= 0
        let l:tmp_words[a:cidx-a:w_sidx] = printf("%%#WildMenu#%s%%*", l:tmp_words[a:cidx-a:w_sidx])
    endif
    return join(l:tmp_words, ' ')
endfunction


" Search forward from given starting index for candidates that can be
" displayed on the status line.
" e.g.
" aaa bbb ccc ddd eee fff ggg hhh iii jjj kkk
"         |--------->
"      w_sidx
" @words    all word candidates
" @w_sidx   start index of window
" @cidx     current selected index in entire candidates
" 
" Return end index of window
function s:WIC_get_next_window_fw(words, w_sidx, cidx) abort
    let l:win_width = winwidth(0)    " Window width

    for i in range(a:w_sidx, len(a:words)-1)
        let l:tmp_sline = s:WIC_gen_status_line(a:words, a:w_sidx, i, a:cidx)
        let l:w_eidx = i
        if len(l:tmp_sline) > l:win_width
            if l:w_eidx == a:w_sidx
                " If length of one word is larger than window width,
                " the only word is displayed.
                return l:w_eidx
            else
                return l:w_eidx - 1
            endif
        endif
    endfor

    return l:w_eidx
endfunction


" Search backward from given end index for candidates that can be
" displayed on the status line.
" e.g.
" aaa bbb ccc ddd eee fff ggg hhh iii jjj kkk
"                         <---------|
"                                 w_eidx
" @words    all word candidates
" @w_eidx   end index of window
" @cidx     current selected index in entire candidates
" 
" Return start index of window
function s:WIC_get_next_window_bw(words, w_eidx, cidx) abort
    let l:win_width = winwidth(0)    " Window width

    let l:w_sidx = a:w_eidx
    while 1
        " Break loop after searching to the top of the list backward
        if l:w_sidx == -1
            return l:w_sidx + 1
        endif

        let l:tmp_sline = s:WIC_gen_status_line(a:words, l:w_sidx, a:w_eidx, a:cidx)
        if len(l:tmp_sline) > l:win_width
            if l:w_sidx == a:w_eidx
                " If length of one word is larger than window width,
                " the only word is displayed.
                return l:w_sidx
            else
                return l:w_sidx + 1
            endif
        endif

        let l:w_sidx = l:w_sidx - 1
    endwhile
endfunction

