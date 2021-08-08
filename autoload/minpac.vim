vim9script noclear
# ---------------------------------------------------------------------
# minpac: A minimal package manager for Vim 8 (and Neovim)
#
# Maintainer:   Ken Takata
# Last Change:  2020-08-22
# License:      VIM License
# URL:          https://github.com/k-takata/minpac
# ---------------------------------------------------------------------

# Get a list of package/plugin directories.
def minpac#getpackages(...l: list<any>): list<string>
  return call('minpac#impl#getpackages', l)
enddef


def EnsureInitialization()
  if !exists('g:minpac#opt')
    echohl WarningMsg
    echom 'Minpac has not been initialized. Use the default values.'
    echohl None
    minpac#init()
  endif
enddef

# Initialize minpac.
def minpac#init(...l: list<dict<any>>)
  var opt: dict<any> = get(l, 0, {})
    ->copy()
    ->extend({
      dir: '',
      package_name: 'minpac',
      git: 'git',
      depth: 1,
      jobs: 8,
      verbose: 2,
      confirm: true,
      progress_open: 'horizontal',
      status_open: 'horizontal',
      status_auto: false
    }, 'keep')

  g:minpac#opt = opt
  g:minpac#pluglist = {}

  var packdir: string = opt.dir
  if packdir == ''
    # If 'dir' is not specified, the first directory of 'packpath' is used.
    packdir = split(&packpath, ',')[0]
  endif

  opt.minpac_dir = packdir .. '/pack/' .. opt.package_name
  opt.minpac_start_dir = opt.minpac_dir .. '/start'
  opt.minpac_opt_dir = opt.minpac_dir .. '/opt'

  # directories for 'subdir'
  opt.minpac_dir_sub = packdir .. '/pack/' .. opt.package_name .. '-sub'
  opt.minpac_start_dir_sub = opt.minpac_dir_sub .. '/start'
  opt.minpac_opt_dir_sub = opt.minpac_dir_sub .. '/opt'

  if !isdirectory(packdir)
    Echoerr('Pack directory not available: ' .. packdir)
    return
  endif
  if !isdirectory(opt.minpac_start_dir)
    mkdir(opt.minpac_start_dir, 'p')
  endif
  if !isdirectory(opt.minpac_opt_dir)
    mkdir(opt.minpac_opt_dir, 'p')
  endif
enddef


# Register the specified plugin.
def minpac#add(plugname: string, ...l: list<dict<any>>)
  EnsureInitialization()
  var opt: dict<any> = get(l, 0, {})
  ->copy()
  ->extendnew({
     name: '',
     type: 'start',
     depth: g:minpac#opt.depth,
     frozen: false,
     branch: '',
     rev: '',
     do: '',
     subdir: '',
     pullmethod: ''
  }, 'keep')

  # URL
  if plugname =~? '^[-._0-9a-z]\+\/[-._0-9a-z]\+$'
    opt.url = 'https://github.com/' .. plugname .. '.git'
  else
    opt.url = plugname
  endif

  # Name of the plugin
  if opt.name == ''
    opt.name = matchstr(opt.url, '[/\\]\zs[^/\\]\+$')
    opt.name = substitute(opt.name, '\C\.git$', '', '')
  endif
  if opt.name == ''
    Echoerr('Cannot extract the plugin name. (' .. plugname .. ')')
    return
  endif

  # Loading type / Local directory
  if opt.type == 'start'
    opt.dir = g:minpac#opt.minpac_start_dir .. '/' .. opt.name
  elseif opt.type == 'opt'
    opt.dir = g:minpac#opt.minpac_opt_dir .. '/' .. opt.name
  else
    Echoerr(plugname .. ": Wrong type (must be 'start' or 'opt'): " .. opt.type)
    return
  endif

  # Check pullmethod
  if opt.pullmethod != '' && opt.pullmethod != 'autostash'
    Echoerr(plugname .. ": Wrong pullmethod (must be empty or 'autostash'): " .. opt.pullmethod)
    return
  endif

  # Initialize the status
  opt.stat = {errcode: 0, lines: [], prev_rev: '', installed: -1}

  # Add to pluglist
  g:minpac#pluglist[opt.name] = opt
enddef

# Need a legacy function because of this:
#
#    > When an expression is compiled the command is not available.
#    > Keeping this as a context for a possible error or exception would add overhead,
#    > which isn't justified.
#
# Source: https://github.com/vim/vim/issues/8698
function Echoerr(msg)
  echoerr a:msg
endfunction


# Update all or specified plugin(s).
def minpac#update(...l: list<any>)
  EnsureInitialization()
  call('minpac#impl#update', l)
enddef


# Remove plugins that are not registered.
def minpac#clean(...l: list<string>)
  EnsureInitialization()
  call('minpac#impl#clean', l)
enddef

def minpac#status(config: dict<string> = {})
  EnsureInitialization()
  var opt: dict<string> = config
    ->copy()
    ->extend({open: g:minpac#opt.status_open}, 'keep')
  minpac#status#get(opt)
enddef


# Get information of specified plugin. Mainly for debugging.
def minpac#getpluginfo(name: string): dict<any>
  EnsureInitialization()
  return g:minpac#pluglist[name]
enddef


# Get a list of plugin information. Mainly for debugging.
def minpac#getpluglist(): dict<dict<any>>
  return g:minpac#pluglist
enddef

# vim: set ts=8 sw=2 et:
