vim9script noclear
# ---------------------------------------------------------------------
# minpac: A minimal package manager for Vim 8 (and Neovim)
#
# Maintainer:   Ken Takata
# Last Change:  2020-08-22
# License:      VIM License
# URL:          https://github.com/k-takata/minpac
# ---------------------------------------------------------------------

var joblist: list<number>
var remain_jobs: number
var finish_update_hook: any

# Get a list of package/plugin directories.
def minpac#impl#getpackages(...l: list<any>): list<string>
  var packname: string = get(l, 0, '')
  var packtype: string = get(l, 1, '')
  var plugname: string = get(l, 2, '')
  var nameonly: bool = get(l, 3, false)

  if packname == '' | packname = '*' | endif
  if packtype == '' | packtype = '*' | endif
  if plugname == '' | plugname = '*' | endif

  var pat: string
  if packtype == 'NONE'
    pat = 'pack/' .. packname
  else
    pat = 'pack/' .. packname .. '/' .. packtype .. '/' .. plugname
  endif

  var ret: list<string> = globpath(&packpath, pat, false, true)
    ->filter((_, v: string): bool => isdirectory(v))
  if nameonly
    ret->map((_, v: string): string => v->substitute('^.*[/\\]', '', ''))
  endif
  return ret
enddef


def EchoxVerbose(
  level: number,
  echocmd: string,
  type: string,
  msg: string
)
  if g:minpac#opt.verbose >= level
    if g:minpac#opt.progress_open == 'none'
      if type == 'warning'
        echohl WarningMsg
      elseif type == 'error'
        echohl ErrorMsg
      endif
      execute echocmd .. " '" .. msg->substitute("'", "''", 'g') .. "'"
      echohl None
    else
      minpac#progress#add_msg(type, msg)
    endif
  endif
enddef

def EchoVerbose(
  level: number,
  type: string,
  msg: string
)
  EchoxVerbose(level, 'echo', type, msg)
enddef

def EchomVerbose(
  level: number,
  type: string,
  msg: string
)
  EchoxVerbose(level, 'echom', type, msg)
enddef

def EchoerrVerbose(
  level: number,
  msg: string
)
  EchoxVerbose(level, 'echoerr', 'error', msg)
enddef


if has('win32')
  def QuoteCmds(cmds: list<string>): string
    # If space (or brace) is found, surround the argument with "".
    # Assuming double quotations are not used elsewhere.
    # (Brace needs to be quoted for msys2/git.)
    return cmds->map((_, v: string): string => (v =~ '[ {]') ? '"' .. v .. '"' : v)->join(' ')
  enddef
else
  def QuoteCmds(cmds: list<string>): list<string>
    return cmds
  enddef
endif

# Replacement for system().
# This doesn't open an extra window on MS-Windows.
def minpac#impl#system(cmds: list<string>): list<any>
  var out: list<string>
  var ret: number = -1
  var quote_cmds: any = QuoteCmds(cmds)
  EchomVerbose(4, '', 'system: cmds=' .. string(quote_cmds))
  var job: number = quote_cmds
    ->minpac#job#start({on_stdout: (id: number, mes: list<string>, ev: string): list<string> => out->extend(mes)})
  if job > 0
    # It worked!
    ret = [job]->minpac#job#wait()[0]
    sleep 5m    # Wait for out_cb. (not sure this is enough.)
  endif
  return [ret, out]
enddef

# Execute git command on the specified plugin directory.
def ExecPluginCmd(
  name: string,
  cmd: list<string>,
  mes: string
): string

  var pluginfo: dict<any> = g:minpac#pluglist[name]
  var dir: dict<any> = pluginfo.dir
  var res: list<any> = minpac#impl#system([g:minpac#opt.git, '-C', dir] + cmd)
  if res[0] == 0 && len(res[1]) > 0
    EchomVerbose(4, '', mes .. ': ' .. res[1][0])
    return res[1][0]
  else
    # Error
    return ''
  endif
enddef

# Get the revision of the specified plugin.
def minpac#impl#get_plugin_revision(name: string): string
  var rev: any = minpac#git#get_revision(g:minpac#pluglist[name].dir)
  if rev != v:null
    EchomVerbose(4, '', 'revision: ' .. rev)
    return rev
  endif
  return ExecPluginCmd(name, ['rev-parse', 'HEAD'], 'revision')
enddef

# Get the exact tag name of the specified plugin.
def GetPluginTag(name: string): string
  return ExecPluginCmd(name, ['describe', '--tags', '--exact-match'], 'tag')
enddef

# Get the latest tag name of the specified plugin. Sorted by version number.
def GetPluginLatestTag(name: string, tag: string): string
  return ExecPluginCmd(name, ['tag', '--list', '--sort=-version:refname', tag], 'latest tag')
enddef

# Get the branch name of the specified plugin.
def GetPluginBranch(name: string): string
  var branch: any = minpac#git#get_branch(g:minpac#pluglist[name].dir)
  if branch != v:null
    EchomVerbose(4, '', 'branch: ' .. branch)
    return branch
  endif
  return ExecPluginCmd(name, ['symbolic-ref', '--short', 'HEAD'], 'branch')
enddef


var updated_plugins: number
var installed_plugins: number
var error_plugins: number
def DecrementJobCount()
  --remain_jobs
  if remain_jobs == 0
    # `minpac#update()` is finished.
    InvokeHook('finish-update', [updated_plugins, installed_plugins], finish_update_hook)

    if has('nvim') && exists(':UpdateRemotePlugins') == 2
          && (updated_plugins > 0 || installed_plugins > 0)
      execute 'UpdateRemotePlugins'
    endif

    # Show the status.
    if error_plugins + updated_plugins + installed_plugins > 0
      if g:minpac#opt.progress_open != 'none'
        EchomVerbose(1, '', '')   # empty line
      endif
    endif
    if error_plugins > 0
      EchomVerbose(1, 'warning', 'Error plugins: ' .. error_plugins)
    else
      var mes: string = 'All plugins are up to date.'
      if updated_plugins + installed_plugins > 0
        mes ..= ' (Updated: ' .. updated_plugins .. ', Newly installed: ' .. installed_plugins .. ')'
      endif
      EchomVerbose(1, '', mes)
    endif
    if g:minpac#opt.progress_open != 'none'
      EchomVerbose(1, '', '(Type "q" to close this window. Type "s" to open the status window.)')
    endif

    # Open the status window.
    if updated_plugins + installed_plugins > 0
      if g:minpac#opt.status_auto
        minpac#status()
      endif
    endif

    # Restore the pager.
    if save_more != -1
      &more = save_more
      save_more = -1
    endif
  endif
enddef
var save_more: any = -1

var Chdir: func
if exists('*chdir')
  Chdir = function('chdir')
else
  def Chdir(dir: string): string
    var cdcmd: string
    if has('nvim')
      cdcmd = haslocaldir() ? 'lcd' : (haslocaldir(-1, 0) ? 'tcd' : 'cd')
    else
      cdcmd = haslocaldir() ? ((haslocaldir() == 1) ? 'lcd' : 'tcd') : 'cd'
    endif
    var pwd: string = getcwd()
    execute cdcmd .. ' ' .. fnameescape(dir)
    return pwd
  enddef
endif

def InvokeHook(
  hooktype: string,
  args: list<any>,
  hook: any
)

  if hook == ''
    return
  endif

  var pwd: string
  if hooktype == 'post-update'
    var name: string = args[0]
    var pluginfo: dict<any> = g:minpac#pluglist[name]
    noautocmd pwd = Chdir(pluginfo.dir)
  endif
  try
    if typename(hook) =~ '^func'
      call(hook, [hooktype] + args)
    elseif typename(hook) == 'string'
      Execute(hook)
    endif
  catch
    EchomVerbose(1, 'error', v:throwpoint)
    EchomVerbose(1, 'error', v:exception)
  finally
    if hooktype == 'post-update'
      noautocmd Chdir(pwd)
    endif
  endtry
enddef
function Execute(cmd)
  execute a:cmd
endfunction

def IsHelptagsOld(dir: string): bool
  var txts: list<string> = glob(dir .. '/*.txt', true, true) + glob(dir .. '/*.[a-z][a-z]x', true, true)
  var tags: list<string> = glob(dir .. '/tags', true, true) + glob(dir .. '/tags-[a-z][a-z]', true, true)
  var txt_newest: number = txts
    ->mapnew(((_, v: string): number => getftime(v)))
    ->max()
  var tag_oldest: number = tags
    ->mapnew(((_, v: string): number => getftime(v)))
    ->min()
  return txt_newest > tag_oldest
enddef

def GenerateHelptags(dir: string)
  var docdir: string = dir .. '/doc'
  if IsHelptagsOld(docdir)
    silent! execute 'helptags ' .. fnameescape(docdir)
  endif
enddef

def AddRtp(dir: string)
  if empty(&rtp)
    &rtp = dir
  else
    &rtp ..= ',' .. dir
  endif
enddef

if has('win32')
  def CreateLink(target: string, link: string)
    if isdirectory(target)
      delete(target)
    endif
    minpac#impl#system(['cmd.exe', '/c', 'mklink', '/J',
          link->substitute('/', '\', 'g'),
          target->substitute('/', '\', 'g')])
  enddef
else
  def CreateLink(target: string, link: string)
    minpac#impl#system(['ln', '-sf', target, link])
  enddef
endif

def HandleSubdir(pluginfo: dict<any>)
  var workdir: string
  if pluginfo.type == 'start'
    workdir = g:minpac#opt.minpac_start_dir_sub
  else
    workdir = g:minpac#opt.minpac_opt_dir_sub
  endif
  if !isdirectory(workdir)
    mkdir(workdir, 'p')
  endif
  noautocmd var pwd: string = Chdir(workdir)
  try
    if !isdirectory(pluginfo.name)
      CreateLink(pluginfo.dir .. '/' .. pluginfo.subdir,
            pluginfo.name)
    endif
  finally
    noautocmd Chdir(pwd)
  endtry
enddef

def JobExitCb(
  self: dict<any>,
  id: number,
  errcode: number,
  event: string
)

  joblist->filter((_, v: number): bool => v != id)

  var err: number = 1
  var pluginfo: dict<any> = g:minpac#pluglist[self.name]
  pluginfo.stat.errcode = errcode

  if errcode == 0
    var dir: string = pluginfo.dir
    # Check if the plugin directory is available.
    if isdirectory(dir)
      # Check if it is actually updated (or installed).
      var updated: bool = true
      if pluginfo.stat.prev_rev != '' && pluginfo.stat.upd_method != 2
        if pluginfo.stat.prev_rev == minpac#impl#get_plugin_revision(self.name)
          updated = false
        endif
      endif

      if updated
        var cmd: list<string>
        if pluginfo.stat.upd_method == 2
          var rev: string = pluginfo.rev
          if rev == ''
            # If no branch or tag is specified, consider as the master branch.
            rev = 'master'
          endif
          if self.seq == 0
            # Check out the specified revison (or branch).
            if rev =~ '\*'
              # If it includes '*', consider as the latest matching tag.
              rev = GetPluginLatestTag(self.name, rev)
              if rev == ''
                ++error_plugins
                EchomVerbose(1, 'error', 'Error while updating "' .. self.name .. '".  No tags found.')
                DecrementJobCount()
                return
              endif
            endif
            cmd = [g:minpac#opt.git, '-C', dir, 'checkout', rev, '--']
            EchomVerbose(3, '', 'Checking out the revison: ' .. self.name .. ': ' .. rev)
            StartJob(cmd, self.name, self.seq + 1)
            return
          elseif self.seq == 1 && GetPluginBranch(self.name) == rev
            # Checked out the branch. Update to the upstream.
            cmd = [g:minpac#opt.git, '-C', dir, 'merge', '--quiet', '--ff-only', '@{u}']
            EchomVerbose(3, '', 'Update to the upstream: ' .. self.name)
            StartJob(cmd, self.name, self.seq + 1)
            return
          endif
        endif
        if pluginfo.stat.submod == 0
          pluginfo.stat.submod = 1
          if filereadable(dir .. '/.gitmodules')
            # Update git submodule.
            cmd = [g:minpac#opt.git, '-C', dir, 'submodule', '--quiet',
                    'update', '--init', '--recursive']
            EchomVerbose(3, '', 'Updating submodules: ' .. self.name)
            StartJob(cmd, self.name, self.seq + 1)
            return
          endif
        endif

        GenerateHelptags(dir)

        if pluginfo.subdir != ''
          HandleSubdir(pluginfo)
        endif

        if has('nvim') && isdirectory(dir .. '/rplugin')
          # Required for :UpdateRemotePlugins.
          AddRtp(dir)
        endif

        InvokeHook('post-update', [self.name], pluginfo.do)
      else
        # Even the plugin is not updated, generate helptags if it is not found.
        GenerateHelptags(dir)
      endif

      if pluginfo.stat.installed
        if updated
          ++updated_plugins
          EchomVerbose(1, '', 'Updated: ' .. self.name)
        else
          EchomVerbose(3, '', 'Already up-to-date: ' .. self.name)
        endif
      else
        ++installed_plugins
        EchomVerbose(1, '', 'Installed: ' .. self.name)
      endif
      err = 0
    endif
  endif

  if err
    ++error_plugins
    EchomVerbose(1, 'error', 'Error while updating "' .. self.name .. '".  Error code: ' .. errcode)
  endif

  DecrementJobCount()
enddef

def JobErrCb(
  self: dict<any>,
  id: number,
  message: list<string>,
  event: string
)

  var mes: list<string> = copy(message)
  if len(mes) > 0 && mes[-1] == ''
    # Remove the last empty line. It is redundant.
    mes->remove(-1)
  endif
  for l: string in mes
    var line = l->substitute("\t", '        ', 'g')
    g:minpac#pluglist[self.name].stat.lines->add(line)
    EchomVerbose(2, 'warning', self.name .. ': ' .. line)
  endfor
enddef

def StartJob(
  cmds: list<string>,
  name: string,
  seq: number
)

  if len(joblist) > 1
    sleep 20m
  endif
  if g:minpac#opt.jobs > 0
    while len(joblist) >= g:minpac#opt.jobs
      sleep 500m
    endwhile
  endif

  var quote_cmds: any = QuoteCmds(cmds)
  EchomVerbose(4, '', 'start_job: cmds=' .. string(quote_cmds))
  var opts: dict<any> = {
    name: name,
    seq: seq
  }
  opts.on_exit = function(JobExitCb, [opts])
  opts.on_stderr = function(JobErrCb, [opts])
  var job: number = quote_cmds->minpac#job#start(opts)
  if job > 0
    # It worked!
  else
    EchomVerbose(1, 'error', 'Fail to execute: ' .. cmds[0])
    DecrementJobCount()
    return
  endif
  joblist += [job]
enddef

def IsSameCommit(a: string, b: string): bool
  var min: number = [len(a), len(b)]->min() - 1
  return a[0 : min] == b[0 : min]
enddef

# Check the status of the plugin.
# return: 0: No need to update.
#         1: Need to update by pull.
#         2: Need to update by fetch & checkout.
def CheckPluginStatus(name: string): number
  var pluginfo: dict<any> = g:minpac#pluglist[name]
  pluginfo.stat.prev_rev = minpac#impl#get_plugin_revision(name)
  var branch: string = GetPluginBranch(name)

  if pluginfo.rev == ''
    # No branch or tag is specified.
    if branch == ''
      # Maybe a detached head. Need to update by fetch & checkout.
      return 2
    else
      # Need to update by pull.
      return 1
    endif
  endif
  if branch == pluginfo.rev
    # Same branch. Need to update by pull.
    return 1
  endif
  if GetPluginTag(name) == pluginfo.rev
    # Same tag. No need to update.
    return 0
  endif
  if IsSameCommit(pluginfo.stat.prev_rev, pluginfo.rev)
    # Same commit ID. No need to update.
    return 0
  endif

  # Need to update by fetch & checkout.
  return 2
enddef

# Check whether the type was changed. If it was changed, rename the directory.
def PreparePluginDir(pluginfo: dict<any>)
  var dir: string = pluginfo.dir
  if !isdirectory(dir)
    var dirtmp: string
    if pluginfo.type == 'start'
      dirtmp = dir->substitute('/start/\ze[^/]\+$', '/opt/', '')
    else
      dirtmp = dir->substitute('/opt/\ze[^/]\+$', '/start/', '')
    endif
    if isdirectory(dirtmp)
      # The type was changed (start <-> opt).
      rename(dirtmp, dir)
    endif
  endif

  # Check subdir.
  if pluginfo.subdir != ''
    var name: string = pluginfo.name
    var subdir: string
    var otherdir: string
    if pluginfo.type == 'start'
      subdir = g:minpac#opt.minpac_start_dir_sub .. '/' .. name
      otherdir = g:minpac#opt.minpac_opt_dir_sub .. '/' .. name
    else
      subdir = g:minpac#opt.minpac_opt_dir_sub .. '/' .. name
      otherdir = g:minpac#opt.minpac_start_dir_sub .. '/' .. name
    endif
    if isdirectory(otherdir) && !isdirectory(subdir)
      # The type was changed (start <-> opt).
      delete(otherdir)
      HandleSubdir(pluginfo)
    endif
  endif
enddef

# Update a single plugin.
def UpdateSinglePlugin(name: string, force: bool)
  if !g:minpac#pluglist->has_key(name)
    EchoerrVerbose(1, 'Plugin not registered: ' .. name)
    DecrementJobCount()
    return
  endif

  var pluginfo: dict<any> = g:minpac#pluglist[name]
  var dir: string = pluginfo.dir
  var url: string = pluginfo.url
  pluginfo.stat.errcode = 0
  pluginfo.stat.lines = []
  pluginfo.stat.prev_rev = ''
  pluginfo.stat.submod = 0

  PreparePluginDir(pluginfo)
  var cmd: list<string>
  if isdirectory(dir)
    pluginfo.stat.installed = 1
    if pluginfo.frozen && !force
      EchomVerbose(3, '', 'Skipped: ' .. name)
      DecrementJobCount()
      return
    endif

    var ret: number = CheckPluginStatus(name)
    pluginfo.stat.upd_method = ret
    if ret == 0
      # No need to update.
      EchomVerbose(3, '', 'Already up-to-date: ' .. name)
      DecrementJobCount()
      return
    elseif ret == 1
      # Same branch. Update by pull.
      EchoVerbose(3, '', 'Updating (pull): ' .. name)
      cmd = [g:minpac#opt.git, '-C', dir, 'pull', '--quiet']
      if pluginfo.pullmethod ==# 'autostash'
        cmd += ['--rebase', '--autostash']
      else
        cmd += ['--ff-only', '--rebase=false']
      endif
    elseif ret == 2
      # Different branch. Update by fetch & checkout.
      EchoVerbose(3, '', 'Updating (fetch): ' .. name)
      cmd = [g:minpac#opt.git, '-C', dir, 'fetch', '--depth', '999999']
    endif
  else
    pluginfo.stat.installed = 0
    if pluginfo.rev == ''
      pluginfo.stat.upd_method = 1
    else
      pluginfo.stat.upd_method = 2
    endif
    EchoVerbose(3, '', 'Cloning ' .. name)

    cmd = [g:minpac#opt.git, 'clone', '--quiet', url, dir, '--no-single-branch']
    if pluginfo.depth > 0 && pluginfo.rev == ''
      cmd += ['--depth=' .. pluginfo.depth]
    endif
    if pluginfo.branch != ''
      cmd += ['--branch=' .. pluginfo.branch]
    endif
  endif
  StartJob(cmd, name, 0)
enddef

def StartUpdate(
  names: list<string>,
  force: bool,
  id: number
)
  for name: string in names
    UpdateSinglePlugin(name, force)
  endfor
enddef

# Update all or specified plugin(s).
writefile([], '/tmp/log')
def minpac#impl#update(...l: list<any>)
  if g:minpac#opt.progress_open != 'none'
    minpac#progress#open(['## minpac update progress ##', ''])
  endif

  var opt: dict<any> = get(l, 1, {})
    ->copy()
    ->extendnew({do: ''}, 'keep')
  var force: bool
  var names: list<string>
  if len(l) == 0 || (l[0]->typename() == 'string' && l[0] == '')
    names = g:minpac#pluglist->keys()
  elseif l[0]->typename() == 'string'
    names = [l[0]]
    force = 1
  elseif l[0]->typename() =~ '^list'
    names = l[0]
    force = 1
  else
    EchoerrVerbose(1, 'Wrong parameter type. Must be a String or a List of Strings.')
    return
  endif

  if remain_jobs > 0
    EchomVerbose(1, '', 'Previous update has not been finished.')
    return
  endif
  remain_jobs = len(names)
  error_plugins = 0
  updated_plugins = 0
  installed_plugins = 0
  finish_update_hook = opt.do

  if g:minpac#opt.progress_open == 'none'
    # Disable the pager temporarily to avoid jobs being interrupted.
    save_more = &more
    set nomore
  endif

  timer_start(1, function(StartUpdate, [names, force]))
enddef


# Check if the dir matches specified package name and plugin names.
def MatchPlugin(
  dir: string,
  packname: string,
  plugnames: list<string>
): bool

  var plugname: string = '\%(' .. plugnames->join('\|') .. '\)'
  plugname = plugname
    ->substitute('\.', '\\.', 'g')
    ->substitute('\*', '.*', 'g')
    ->substitute('?', '.', 'g')
  var pat: string
  if plugname =~ '/'
    pat = '/pack/' .. packname .. '\%(-sub\)\?' .. '/' .. plugname .. '$'
  else
    pat = '/pack/' .. packname .. '\%(-sub\)\?' .. '/\%(start\|opt\)/' .. plugname .. '$'
  endif
  if has('win32')
    pat = pat->substitute('/', '[/\\\\]', 'g')
    # case insensitive matching
    return dir =~? pat
  else
    # case sensitive matching
    return dir =~ pat
  endif
enddef

# Remove plugins that are not registered.
def minpac#impl#clean(...l: list<string>)
  var plugin_dirs: list<string> = minpac#getpackages(g:minpac#opt.package_name)
        + minpac#getpackages(g:minpac#opt.package_name .. '-sub')

  var to_remove: list<string>
  if len(l) > 0
    # Going to remove only specified plugins.
    var names: any
    if l[0]->typename() == 'string'
      names = [l[0]]
    elseif l[0]->typename() =~ '^list'
      names = l[0]
    else
      echoerr 'Wrong parameter type. Must be a String or a List of Strings.'
      return
    endif
    to_remove = plugin_dirs
      ->filter((_, v: string): bool => MatchPlugin(v, g:minpac#opt.package_name, names))
  else
    # Remove all plugins that are not registered.
    var safelist: list<string> = g:minpac#pluglist
      ->keys()
      ->map((_, v: string): string => g:minpac#pluglist[v].type .. '/' .. v)
          + ['opt/minpac']  # Don't remove itself.
    to_remove = plugin_dirs
      ->filter((_, v: string): bool => !MatchPlugin(v, g:minpac#opt.package_name, safelist))
  endif

  if len(to_remove) == 0
    echo 'Already clean.'
    return
  endif

  # Show the list of plugins to be removed.
  for item: string in to_remove
    echo item
  endfor

  var dir: string = (len(to_remove) > 1) ? 'directories' : 'directory'

  if !g:minpac#opt.confirm || input('Removing the above ' .. dir .. '. [y/N]? ') =~ '^[yY]'
    echo "\n"
    var err: number
    for item: string in to_remove
      if delete(item, 'rf') != 0
        echohl ErrorMsg
        echom 'Clean failed: ' .. item
        echohl None
        err = 1
      endif
    endfor
    if has('nvim') && exists(':UpdateRemotePlugins') == 2
      execute('UpdateRemotePlugins')
    endif
    if err == 0
      echo 'Successfully cleaned.'
    endif
  else
    echo "\n"  .. 'Not cleaned.'
  endif
enddef

def minpac#impl#is_update_ran(): bool
  return installed_plugins != 0
enddef

# vim: set ts=8 sw=2 et:
