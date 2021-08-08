vim9script noclear

# Tests for minpac.

set rtp^=..
set packpath=.
runtime plugin/minpac.vim

# Tests for minpac#init()
def g:Test_minpac_init()
  delete('pack', 'rf')

  # NOTE: The variables g:minpac#opt and g:minpac#pluglist are not the part
  # of public APIs.  Users should not access these variables.  They should
  # be used only for testing and/or debugging.

  # Default setting
  minpac#init()
  assert_true(isdirectory('pack/minpac/start'))
  assert_true(isdirectory('pack/minpac/opt'))
  assert_equal('git', g:minpac#opt.git)
  assert_equal(1, g:minpac#opt.depth)
  assert_equal(8, g:minpac#opt.jobs)
  assert_equal(2, g:minpac#opt.verbose)
  assert_equal('horizontal', g:minpac#opt.progress_open)
  assert_equal('horizontal', g:minpac#opt.status_open)
  assert_equal(false, g:minpac#opt.status_auto)
  assert_equal({}, minpac#getpluglist())

  g:minpac#pluglist.foo = 'bar'

  # Change settings
  minpac#init({
    package_name: 'm',
    git: 'foo',
    depth: 10,
    jobs: 2,
    verbose: 1,
    progress_open: 'tab',
    status_open: 'vertical',
    status_auto: true,
  })
  assert_true(isdirectory('pack/m/start'))
  assert_true(isdirectory('pack/m/opt'))
  assert_equal('foo', g:minpac#opt.git)
  assert_equal(10, g:minpac#opt.depth)
  assert_equal(2, g:minpac#opt.jobs)
  assert_equal(1, g:minpac#opt.verbose)
  assert_equal('tab', g:minpac#opt.progress_open)
  assert_equal('vertical', g:minpac#opt.status_open)
  assert_equal(true, g:minpac#opt.status_auto)
  assert_equal({}, minpac#getpluglist())

  delete('pack', 'rf')
enddef

# Tests for minpac#add() and minpac#getpluginfo()
def g:Test_minpac_add()
  delete('pack', 'rf')

  minpac#init()

  # Default
  minpac#add('k-takata/minpac')
  var p: dict<any> = minpac#getpluginfo('minpac')
  assert_equal('https://github.com/k-takata/minpac.git', p.url)
  assert_match('/pack/minpac/start/minpac$', p.dir)
  assert_equal(false, p.frozen)
  assert_equal('start', p.type)
  assert_equal('', p.branch)
  assert_equal(1, p.depth)
  assert_equal('', p.do)
  assert_equal('', p.rev)
  assert_equal('', p.subdir)
  assert_equal('', p.pullmethod)

  # With configuration
  minpac#add('k-takata/minpac', {
    type: 'opt',
    frozen: true,
    branch: 'master',
    depth: 10,
    rev: 'abcdef',
    subdir: 'dir',
    pullmethod: 'autostash',
  })
  p = minpac#getpluginfo('minpac')
  assert_equal('https://github.com/k-takata/minpac.git', p.url)
  assert_match('/pack/minpac/opt/minpac$', p.dir)
  assert_equal(true, p.frozen)
  assert_equal('opt', p.type)
  assert_equal('master', p.branch)
  assert_equal(10, p.depth)
  assert_equal('', p.do)
  assert_equal('abcdef', p.rev)
  assert_equal('dir', p.subdir)
  assert_equal('autostash', p.pullmethod)

  # SSH URL
  minpac#add('git@github.com:k-takata/minpac.git', {name: 'm'})
  p = minpac#getpluginfo('m')
  assert_equal('git@github.com:k-takata/minpac.git', p.url)
  assert_match('/pack/minpac/start/m$', p.dir)

  # Non GitHub URL with ".git"
  minpac#add('https://example.com/foo.git')
  p = minpac#getpluginfo('foo')
  assert_equal('https://example.com/foo.git', p.url)

  # Non GitHub URL w/o ".git"
  minpac#add('https://example.com/bar')
  p = minpac#getpluginfo('bar')
  assert_equal('https://example.com/bar', p.url)

  # Wrong type
  try
    minpac#add('k-takata/minpac', {type: 'foo'})
  catch
    assert_exception('echoerr')
  endtry

  delete('pack', 'rf')
enddef

# Tests for minpac#getpackages()
def Getnames(plugs: list<string>): list<string>
  return plugs->map((_, v: string): string => v->substitute('^.*[/\\]', '', ''))->sort()
enddef
def g:Test_minpac_getpackages()
  delete('pack', 'rf')

  var plugs: list<string> =<< trim END
    ./pack/minpac/start/plug0
    ./pack/minpac/start/plug1
    ./pack/minpac/opt/plug2
    ./pack/minpac/opt/plug3
    ./pack/foo/start/plug4
    ./pack/foo/start/plug5
    ./pack/foo/opt/plug6
    ./pack/foo/opt/plug7
  END
  for dir: string in plugs
    mkdir(dir, 'p')
  endfor

  # All plugins
  var p: list<string> = minpac#getpackages()
  var exp: list<string> = plugs[:]
  assert_equal(sort(exp), sort(p))
  # name only
  p = minpac#getpackages('', '', '', 1)
  assert_equal(Getnames(exp), sort(p))

  # All packages
  p = minpac#getpackages('', 'NONE')
  exp = ['./pack/foo', './pack/minpac']
  assert_equal(sort(exp), sort(p))
  # name only
  p = minpac#getpackages('', 'NONE', '', 1)
  assert_equal(Getnames(exp), sort(p))

  # Plugins under minpac
  p = minpac#getpackages('minpac')
  exp = plugs[0 : 3]
  assert_equal(sort(exp), sort(p))
  # name only
  p = minpac#getpackages('minpac', '', '', 1)
  assert_equal(Getnames(exp), sort(p))

  # 'start' plugins
  p = minpac#getpackages('', 'start')
  exp = plugs[0 : 1] + plugs[4 : 5]
  assert_equal(sort(exp), sort(p))
  # name only
  p = minpac#getpackages('', 'start', '', 1)
  assert_equal(Getnames(exp), sort(p))

  # 'opt' plugins
  p = minpac#getpackages('*', 'opt', '')
  exp = plugs[2 : 3] + plugs[6 : 7]
  assert_equal(sort(exp), sort(p))
  # name only
  p = minpac#getpackages('*', 'opt', '', 1)
  assert_equal(Getnames(exp), sort(p))

  # Plugins with 'plug1*' name
  p = minpac#getpackages('', '', 'plug1*')
  exp = plugs[1 : 1]
  assert_equal(sort(exp), sort(p))
  # name only
  p = minpac#getpackages('', '', 'plug1', 1)
  assert_equal(Getnames(exp), sort(p))

  # No match
  p = minpac#getpackages('minpac', 'opt', 'plug1*')
  exp = []
  assert_equal(sort(exp), sort(p))

  # name only
  p = minpac#getpackages('minpac', 'opt', 'plug1*', 1)
  assert_equal(Getnames(exp), sort(p))

  delete('pack', 'rf')
enddef

# Tests for minpac#update()
def g:Test_minpac_update()
  delete('pack', 'rf')

  minpac#init()

  # minpac#update() with hooks using Strings.
  minpac#add('k-takata/minpac', {
    type: 'opt',
    do: 'let g:post_update = 1'
  })

  g:post_update = 0
  g:finish_update = 0
  minpac#update('', {do: 'let g:finish_update = 1'})
  while g:finish_update == 0
    sleep 100m
  endwhile

  assert_equal(1, g:post_update)
  assert_true(isdirectory('pack/minpac/opt/minpac'))

  # minpac#update() with hooks using Funcrefs.
  minpac#add('k-takata/hg-vim', {do: (hooktype: string, name: string): list<any> => [
    assert_equal('post-update', hooktype, 'hooktype'),
    assert_equal('hg-vim', name, 'name'),
    execute('spost_update = 1'),
    spost_update
  ]})

  sfinish_update = 0

  minpac#update('', {do: (hooktype: string, updated: number, installed: number): list<any> => [
    assert_equal('finish-update', hooktype, 'hooktype'),
    assert_equal(0, updated, 'updated'),
    assert_equal(1, installed, 'installed'),
    execute('sfinish_update = 1'),
    sfinish_update
  ]})

  while sfinish_update == 0
    sleep 100m
  endwhile

  assert_equal(1, spost_update)
  assert_true(isdirectory('pack/minpac/start/hg-vim'))

  delete('pack', 'rf')
enddef
var sfinish_update: number
var spost_update: number

# Tests for minpac#clean()
def g:Test_minpac_clean()
  delete('pack', 'rf')

  minpac#init()

  var plugs: list<string> =<< trim END
    pack/minpac/start/plug0
    pack/minpac/start/plug1
    pack/minpac/opt/plug2
    pack/minpac/opt/plug3
    pack/minpac/start/minpac
    pack/minpac/opt/minpac
  END
  for dir: string in plugs
    mkdir(dir, 'p')
  endfor

  # Just type Enter. All plugins should not be removed.
  feedkeys(":call minpac#clean()\<CR>\<CR>", 'x')
  for dir: string in plugs
    isdirectory(dir)->assert_true()
  endfor

  # Register some plugins
  minpac#add('foo', {name: 'plug0'})
  minpac#add('bar/plug2', {type: 'opt'})
  minpac#add('baz/plug3')

  # Type y and Enter. Unregistered plugins should be removed.
  # 'opt/minpac' should not be removed even it is not registered.
  feedkeys(":call minpac#clean()\<CR>y\<CR>", 'x')
  assert_equal(1, isdirectory(plugs[0]))
  assert_equal(0, isdirectory(plugs[1]))
  assert_equal(1, isdirectory(plugs[2]))
  assert_equal(0, isdirectory(plugs[3]))
  assert_equal(0, isdirectory(plugs[4]))
  assert_equal(1, isdirectory(plugs[5]))

  # Specify a plugin. It should be removed even it is registered.
  feedkeys(":call minpac#clean('plug0')\<CR>y\<CR>", 'x')
  assert_equal(0, isdirectory(plugs[0]))
  assert_equal(1, isdirectory(plugs[2]))
  assert_equal(1, isdirectory(plugs[5]))

  # 'opt/minpac' can be also removed when it is specified.
  minpac#add('k-takata/minpac', {'type': 'opt'})
  feedkeys(":call minpac#clean('minpa?')\<CR>y\<CR>", 'x')
  assert_equal(1, isdirectory(plugs[2]))
  assert_equal(0, isdirectory(plugs[5]))

  # Type can be also specified.
  # Not match
  minpac#clean('start/plug2')
  assert_equal(1, isdirectory(plugs[2]))

  # Match
  feedkeys(":call minpac#clean('opt/plug*')\<CR>y\<CR>", 'x')
  assert_equal(0, isdirectory(plugs[2]))

  delete('pack', 'rf')
enddef

# vim: ts=8 sw=2 sts=2
