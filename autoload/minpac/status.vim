vim9script noclear
# ---------------------------------------------------------------------
# minpac: A minimal package manager for Vim 8 (and Neovim)
#
# Maintainer:   Ken Takata
# Created By:   Kristijan Husak
# Last Change:  2020-01-28
# License:      VIM License
# URL:          https://github.com/k-takata/minpac
# ---------------------------------------------------------------------

var results: list<dict<any>>
var bufnr: number
var git_sign: number = -1   # Support --no-show-signature option.

def minpac#status#get(opt: dict<string>)
  var bufname: string = '[minpac status]'
  if bufnr != 0
    execute 'silent! bwipe ' .. bufnr
  endif
  var is_update_ran: bool = minpac#impl#is_update_ran()
  var update_count: number
  var install_count: number
  var error_count: number
  var result: list<dict<any>>
  for name: string in g:minpac#pluglist->keys()
    var pluginfo: dict<any> = g:minpac#pluglist[name]
    var dir: string = pluginfo.dir
    var plugin: dict<any> = {name: name, lines: [], status: ''}

    if !isdirectory(dir)
      plugin.status = 'Not installed'
    else
      var cmd: list<string> = [g:minpac#opt.git, '-C', dir, 'log',
            '--color=never', '--pretty=format:%h <<<<%D>>>> %s (%cr)', 'HEAD...HEAD@{1}'
            ]
      var commits: list<any> = minpac#impl#system(cmd + (s:git_sign ? ['--no-show-signature'] : []))
      if git_sign == -1
        if commits[0] == 128
          git_sign = 0
          commits = minpac#impl#system(cmd)
        else
          git_sign = 1
        endif
      endif

      plugin.lines = commits[1]->filter((_, v: string): bool => v != '')
      plugin.lines->map((_, v: string): string =>
        v->substitute( '^[0-9a-f]\{4,} \zs<<<<\(.*\)>>>> ',
            (m: list<string>): string => m[1] =~ '^tag: ' ? '(' .. m[1] .. ') ' : '', ''))

      if !is_update_ran
        plugin.status = 'OK'
      elseif pluginfo.stat.prev_rev != '' && pluginfo.stat.prev_rev != minpac#impl#get_plugin_revision(name)
        ++update_count
        plugin.status = 'Updated'
      elseif pluginfo.stat.installed == 0
        ++install_count
        plugin.status = 'Installed'
      elseif pluginfo.stat.errcode != 0
        ++error_count
        plugin.status = 'Error (' .. pluginfo.stat.errcode .. ')'
      endif
    endif

    result->add(plugin)
  endfor

  # Show items with most lines (commits) first.
  result->sort((first: dict<any>, second: dict<any>): number => len(second.lines) - len(first.lines))
  results = result

  var content: list<string>

  if is_update_ran
    content->add(update_count .. ' updated. ' .. install_count .. ' installed. ' .. error_count .. ' failed.')
    content->add('')
  endif

  for item: dict<any> in result
    if item.status == ''
      continue
    endif

    content->add('- ' .. item.name .. ' - ' .. item.status)
    if item.status =~ '^Error'
      for line: string in g:minpac#pluglist[item.name].stat.lines
        content->add(' msg: ' .. line)
      endfor
    else
      for line: string in item.lines
        content->add(' * ' .. line)
      endfor
    endif
    content->add('')
  endfor
  if len(content) > 0 && content[-1] == ''
    content->remove(-1)
  endif

  if opt.open == 'vertical'
    vertical topleft new
  elseif opt.open == 'horizontal'
    topleft new
  elseif opt.open == 'tab'
    tabnew
  endif
  setfiletype minpac
  content->append(1)
  :1 delete _
  Syntax()
  Mappings()
  setlocal buftype=nofile bufhidden=wipe nobuflisted nolist noswapfile nowrap cursorline nomodifiable nospell
  silent file `=bufname`
  bufnr = bufnr('')
enddef


def Syntax()
  syntax clear
  syn match minpacDash /^-/
  syn match minpacName /\(^- \)\@<=.*/ contains=minpacStatus
  syn match minpacStatus /\(-.*\)\@<=-\s.*$/ contained
  syn match minpacStar /^\s\*/ contained
  syn match minpacCommit /^\s\*\s[0-9a-f]\{7,9} .*/ contains=minpacRelDate,minpacSha,minpacStar
  syn match minpacSha /\(\s\*\s\)\@<=[0-9a-f]\{4,}/ contained nextgroup=minpacTag
  syn match minpacTag / (tag: [^)]*)/ contained
  syn match minpacRelDate /([^)]*)$/ contained
  syn match minpacWarning /^ msg: .*/

  hi def link minpacDash    Special
  hi def link minpacStar    Boolean
  hi def link minpacName    Function
  hi def link minpacSha     Identifier
  hi def link minpacTag     PreProc
  hi def link minpacRelDate Comment
  hi def link minpacStatus  Constant
  hi def link minpacWarning WarningMsg
enddef

def Mappings()
  nnoremap <silent><buffer> <CR> :call <SID>OpenSha()<CR>
  nnoremap <silent><buffer> q :q<CR>
  nnoremap <silent><buffer> <C-j> :call <SID>NextPackage()<CR>
  nnoremap <silent><buffer> <C-k> :call <SID>PrevPackage()<CR>
enddef

def NextPackage(): number
  return search('^-\s.*$')
enddef

def PrevPackage(): number
  return search('^-\s.*$', 'b')
enddef

def OpenSha()
  var sha: string = getline('.')
    ->matchstr('^\s\*\s\zs[0-9a-f]\{7,9}')
  if empty(sha)
    return
  endif

  var name: string = FindNameBySha(sha)

  if empty(name)
    return
  endif

  var pluginfo: dict<any> = g:minpac#pluglist[name]
  silent execute 'pedit ' .. sha
  wincmd p
  setlocal previewwindow filetype=git buftype=nofile nobuflisted modifiable
  var sha_content: list<any> = minpac#impl#system([g:minpac#opt.git, '-C', pluginfo.dir, 'show',
            '--no-color', '--pretty=medium', sha
            ])

  sha_content[1]->append(1)
  :1 delete _
  setlocal nomodifiable
  nnoremap <silent><buffer> q :q<CR>
enddef

def FindNameBySha(sha: string): string
  for result: dict<any> in results
    for commit: string in result.lines
      if commit =~? '^' .. sha
        return result.name
      endif
    endfor
  endfor

  return ''
enddef

# vim: set ts=8 sw=2 et:
