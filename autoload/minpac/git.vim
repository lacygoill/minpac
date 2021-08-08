vim9script noclear
# ---------------------------------------------------------------------
# minpac: A minimal package manager for Vim 8 (and Neovim)
#
# Maintainer:   Ken Takata
# Last Change:  2020-02-01
# License:      VIM License
# URL:          https://github.com/k-takata/minpac
# ---------------------------------------------------------------------

def Isabsolute(dir: string): bool
  return dir =~ '^/' || (has('win32') && dir =~? '^\%(\\\|[A-Z]:\)')
enddef

def GetGitdir(dir: string): string
  var gitdir: string = dir .. '/.git'
  if isdirectory(gitdir)
    return gitdir
  endif
  try
    var line = readfile(gitdir)[0]
    if line =~ '^gitdir: '
      gitdir = line[8 :]
      if !Isabsolute(gitdir)
        gitdir = dir .. '/' .. gitdir
      endif
      if isdirectory(gitdir)
        return gitdir
      endif
    endif
  catch
  endtry
  return ''
enddef

def minpac#git#get_revision(dir: string): any
  var gitdir: string = GetGitdir(dir)
  if gitdir == ''
    return v:null
  endif
  try
    var line: string = readfile(gitdir .. '/HEAD')[0]
    if line =~ '^ref: '
      var ref: string = line[5 :]
      if filereadable(gitdir .. '/' .. ref)
        return readfile(gitdir .. '/' .. ref)[0]
      endif
      for l: string in readfile(gitdir .. '/packed-refs')
        line = l
        if line =~ ' ' .. ref
          return substitute(line, '^\([0-9a-f]*\) ', '\1', '')
        endif
      endfor
    endif
    return line
  catch
  endtry
  return v:null
enddef

def minpac#git#get_branch(dir: string): any
  var gitdir: string = GetGitdir(dir)
  if gitdir == ''
    return v:null
  endif
  try
    var line: string = readfile(gitdir .. '/HEAD')[0]
    if line =~ '^ref: refs/heads/'
      return line[16 :]
    endif
    return ''
  catch
    return v:null
  endtry
  return ''
enddef

# vim: set ts=8 sw=2 et:
