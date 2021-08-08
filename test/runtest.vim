vim9script noclear

# This script is sourced while editing the .vim file with the tests.
# When the script is successful the .res file will be created.
# Errors are appended to the test.log file.
#
# To execute only specific test functions, add a second argument.  It will be
# matched against the names of the Test_ function.  E.g.:
#       ../vim -u NONE -S runtest.vim test_channel.vim open_delay
# The output can be found in the "messages" file.
#
# If the environment variable $TEST_FILTER is set then only test functions
# matching this pattern are executed.  E.g. for sh/bash:
#     export TEST_FILTER=Test_channel
# For csh:
#     setenv TEST_FILTER Test_channel
#
# While working on a test you can make $TEST_NO_RETRY non-empty to not retry:
#     export TEST_NO_RETRY=yes
#
# To ignore failure for tests that are known to fail in a certain environment,
# set $TEST_MAY_FAIL to a comma separated list of function names.  E.g. for
# sh/bash:
#     export TEST_MAY_FAIL=Test_channel_one,Test_channel_other
# The failure report will then not be included in the test.log file and
# "make test" will not fail.
#
# The test script may contain anything, only functions that start with
# "Test_" are special.  These will be invoked and should contain assert
# functions.  See test_assert.vim for an example.
#
# It is possible to source other files that contain "Test_" functions.  This
# can speed up testing, since Vim does not need to restart.  But be careful
# that the tests do not interfere with each other.
#
# If an error cannot be detected properly with an assert function add the
# error to the `v:errors` list:
#     v:errors->add('test foo failed: Cannot find xyz')
#
# If preparation for each Test_ function is needed, define a SetUp function.
# It will be called before each Test_ function.
#
# If cleanup after each Test_ function is needed, define a TearDown function.
# It will be called after each Test_ function.
#
# When debugging a test it can be useful to add messages to v:errors:
#     v:errors->add('this happened')

var start_time: list<number>
# In the GUI we can always change the screen size.
if has('gui_running')
  set columns=80 lines=25
endif

# Check that the screen size is at least 24 x 80 characters.
if &lines < 24 || &columns < 80
  var error: string = 'Screen size too small! Tests require at least 24 lines with 80 characters, got '
    .. &lines .. ' lines with ' .. &columns .. ' characters'
  echoerr error
  split test.log
  :$ put =error
  write
  split messages
  append('$', '')
  append('$', 'From ' .. expand('%') .. ':')
  append('$', error)
  write
  qa!
endif

if has('reltime')
  start_time = reltime()
endif

# Common with all tests on all systems.
source setup.vim

# For consistency run all tests with 'nocompatible' set.
# This also enables use of line continuation.
set nocompatible viminfo+=nviminfo

# Use utf-8 by default, instead of whatever the system default happens to be.
# Individual tests can overrule this at the top of the file and use
# g:orig_encoding if needed.
g:orig_encoding = &encoding
set encoding=utf-8

# REDIR_TEST_TO_NULL has a very permissive SwapExists autocommand which is for
# the test_name.vim file itself. Replace it here with a more restrictive one,
# so we still catch mistakes.
var test_script_fname: string = expand('%')
autocmd! SwapExists * HandleSwapExists()
def HandleSwapExists()
  if exists('g:ignoreSwapExists')
    return
  endif
  # Ignore finding a swap file for the test script (the user might be
  # editing it and do ":make test_name") and the output file.
  # Report finding another swap file and chose 'q' to avoid getting stuck.
  if expand('<afile>') == 'messages' || expand('<afile>') =~ test_script_fname
    v:swapchoice = 'e'
  else
    assert_report('Unexpected swap file: ' .. v:swapname)
    v:swapchoice = 'q'
  endif
enddef

# Avoid stopping at the "hit enter" prompt
set nomore

# Output all messages in English.
lang mess C

# suppress menu translation
if has('gui_running') && exists('did_install_default_menus')
  source $VIMRUNTIME/delmenu.vim
  set langmenu=none
  source $VIMRUNTIME/menu.vim
endif

# Always use forward slashes.
set shellslash

var srcdir: string = expand('%:p:h:h')

var t_bold: string
var t_normal: string
if has('win32')
  # avoid prompt that is long or contains a line break
  $PROMPT = '$P$G'
  # On MS-Windows t_md and t_me are Vim specific escape sequences.
  t_bold = "\x1b[1m"
  t_normal = "\x1b[m"
else
  t_bold = &t_md
  t_normal = &t_me
endif

if has('mac')
  # In MacOS, when starting a shell in a terminal, a bash deprecation warning
  # message is displayed. This breaks the terminal test. Disable the warning
  # message.
  $BASH_SILENCE_DEPRECATION_WARNING = 1
endif

# Prepare for calling test_garbagecollect_now().
v:testing = 1

# Support function: get the alloc ID by name.
def GetAllocId(name: string): number
  execute 'split ' .. srcdir .. '/alloc.h'
  var top: number = search('typedef enum')
  if top == 0
    v:errors->add('typedef not found in alloc.h')
  endif
  var lnum: number = search('aid_' .. name .. ',')
  if lnum == 0
    v:errors->add('Alloc ID ' .. name .. ' not defined')
  endif
  close
  return lnum - top - 1
enddef

def RunTheTest(test: string)
  if exists(':echoconsole') == 2
    echoconsole 'Executing ' .. test
  else
    echo 'Executing ' .. test
  endif

  var func_start: list<number>
  if has('reltime')
    func_start = reltime()
  endif

  # Avoid stopping at the "hit enter" prompt
  set nomore

  # Avoid a three second wait when a message is about to be overwritten by the
  # mode message.
  set noshowmode

  # Clear any overrides.
  if exists('*test_override')
    test_override('ALL', 0)
  endif

  # Some tests wipe out buffers.  To be consistent, always wipe out all
  # buffers.
  :% bwipe!

  # The test may change the current directory. Save and restore the
  # directory after executing the test.
  var save_cwd: string = getcwd()

  if exists('*SetUp')
    try
      g:SetUp()
    catch
      v:errors->add('Caught exception in SetUp() before ' .. test .. ': ' .. v:exception .. ' @ ' .. v:throwpoint)
    endtry
  endif

  if test =~ 'Test_nocatch_'
    # Function handles errors itself.  This avoids skipping commands after the
    # error.
    g:skipped_reason = ''
    execute 'call ' .. test
    if g:skipped_reason != ''
      messages->add('    Skipped')
      skipped->add('SKIPPED ' .. test .. ': ' .. g:skipped_reason)
    endif
  else
    try
      autocmd VimLeavePre * EarlyExit(g:testfunc)
      execute 'call ' .. test
      autocmd! VimLeavePre
    catch /^\cskipped/
      messages->add('    Skipped')
      skipped->add('SKIPPED ' .. test .. ': ' .. v:exception->substitute('^\S*\s\+', '',  ''))
    catch
      v:errors->add('Caught exception in ' .. test .. ': ' .. v:exception .. ' @ ' .. v:throwpoint)
    endtry
  endif

  # In case 'insertmode' was set and something went wrong, make sure it is
  # reset to avoid trouble with anything else.
  set noinsertmode

  if exists('*TearDown')
    try
      g:TearDown()
    catch
      v:errors->add('Caught exception in TearDown() after ' .. test .. ': ' .. v:exception .. ' @ ' .. v:throwpoint)
    endtry
  endif

  # Clear any autocommands and put back the catch-all for SwapExists.
  autocmd!
  autocmd SwapExists * HandleSwapExists()

  # Check for and close any stray popup windows.
  if has('popupwin')
    assert_equal([], popup_list())
    popup_clear(true)
  endif

  # Close any extra tab pages and windows and make the current one not modified.
  while tabpagenr('$') > 1
    var winid: number = win_getid()
    quit!
    if winid == win_getid()
      echoerr 'Could not quit window'
      break
    endif
  endwhile

  while true
    var wincount: number = winnr('$')
    if wincount == 1
      break
    endif
    bwipe!
    if wincount == winnr('$')
      # Did not manage to close a window.
      only!
      break
    endif
  endwhile

  execute 'cd ' .. save_cwd

  var message: string = 'Executed ' .. test
  if has('reltime')
    message ..= repeat(' ', 50 - len(message))
    var time: list<number> = reltime(func_start)
    if has('float') && reltimefloat(time) > 0.1
      message = t_bold .. message
    endif
    message ..= ' in ' .. reltimestr(time) .. ' seconds'
    if has('float') && reltimefloat(time) > 0.1
      message ..= t_normal
    endif
  endif
  messages->add(message)
  ++done
enddef

def AfterTheTest(func_name: string)
  if len(v:errors) > 0
    if may_fail_list->match('^' .. func_name) >= 0
      ++fail_expected
      errors_expected->add('Found errors in ' .. g:testfunc .. ':')
      errors_expected->extend(v:errors)
    else
      ++fail
      errors->add('Found errors in ' .. g:testfunc .. ':')
      errors->extend(v:errors)
    endif
    v:errors = []
  endif
enddef

def EarlyExit(test: string)
  # It's OK for the test we use to test the quit detection.
  if test != 'Test_zz_quit_detected()'
    v:errors->add('Test caused Vim to exit: ' .. test)
  endif

  FinishTesting()
enddef

# This function can be called by a test if it wants to abort testing.
def FinishTesting()
  AfterTheTest('')

  # Don't write viminfo on exit.
  set viminfo=

  # Clean up files created by setup.vim
  delete('XfakeHOME', 'rf')

  if fail == 0 && fail_expected == 0
    # Success, create the .res file so that make knows it's done.
    execute 'split ' .. fnamemodify(g:testname, ':r') .. '.res'
    write
  endif
  if len(errors) > 0
    # Append errors to test.log
    split test.log
    append('$', '')
    append('$', 'From ' .. g:testname .. ':')
    append('$', errors)
    write
  endif

  var message: string
  if done == 0
    if filtered > 0
      message = "NO tests match $TEST_FILTER: '" .. $TEST_FILTER .. "'"
    else
      message = 'NO tests executed'
    endif
  else
    if filtered > 0
      messages->add('Filtered ' .. filtered .. ' tests with $TEST_FILTER')
    endif
    message = 'Executed ' .. done .. (done > 1 ? ' tests' : ' test')
  endif

  if done > 0 && has('reltime')
    message = t_bold .. message .. repeat(' ', 40 - len(message))
    message ..= ' in ' .. start_time->reltime()->reltimestr() .. ' seconds'
    message ..= t_normal
  endif

  echo message
  messages->add(message)
  if fail > 0
    message = fail .. ' FAILED:'
    echo message
    messages->add(message)
    messages->extend(errors)
  endif

  if fail_expected > 0
    message = fail_expected .. ' FAILED (matching $TEST_MAY_FAIL):'
    echo message
    messages->add(message)
    messages->extend(errors_expected)
  endif

  # Add SKIPPED messages
  messages->extend(skipped)

  # Append messages to the file "messages"
  split messages
  append('$', '')
  append('$', 'From ' .. g:testname .. ':')
  append('$', messages)
  write

  qall!
enddef

# Source the test script.  First grab the file name, in case the script
# navigates away.  g:testname can be used by the tests.
g:testname = expand('%')
var done = 0
var fail = 0
var fail_expected = 0
var errors = []
var errors_expected = []
var messages = []
var skipped = []
if expand('%') =~ 'test_vimscript.vim'
  # this test has intentional errors, don't use try/catch.
  source %
else
  try
    source %
  catch /^\cskipped/
    messages->add('    Skipped')
    skipped->add('SKIPPED ' .. expand('%') .. ': ' .. v:exception->substitute('^\S*\s\+', '',  ''))
  catch
    ++fail
    errors->add('Caught exception: ' .. v:exception .. ' @ ' .. v:throwpoint)
  endtry
endif

# Names of flaky tests.
var flaky_tests = [
      ]

# Locate Test_ functions and execute them.
redir @q
silent def /^Test_
redir END

var tests = @q
  ->substitute('\(function\|def\) \(\k*()\)', '\2', 'g')
  ->split()

# If there is an extra argument filter the function names against it.
if argc() > 1
  tests->filter((_, v: string): bool => v =~ argv(1))
endif

# If the environment variable $TEST_FILTER is set then filter the function
# names against it.
var filtered: number
if $TEST_FILTER != ''
  filtered = len(tests)
  tests->filter((_, v: string): bool => v =~ $TEST_FILTER)
  filtered -= len(tests)
endif

var may_fail_list: list<string>

if $TEST_MAY_FAIL != ''
  # Split the list at commas and add () to make it match g:testfunc.
  may_fail_list = $TEST_MAY_FAIL
    ->split(',')
    ->map((_, v: string): string => v .. '()')
endif

var prev_error: string
# Execute the tests in alphabetical order.
for g:testfunc in sort(tests)
  # Silence, please!
  silent! set belloff=all
  var total_errors: list<string>
  g:run_nr = 1

  # A test can set g:test_is_flaky to retry running the test.
  g:test_is_flaky = 0

  RunTheTest(g:testfunc)

  # Repeat a flaky test.  Give up when:
  # - $TEST_NO_RETRY is not empty
  # - it fails again with the same message
  # - it fails five times (with a different message)
  if len(v:errors) > 0
        && $TEST_NO_RETRY == ''
        && (index(flaky_tests, g:testfunc) >= 0
             || g:test_is_flaky)
    while true
      messages->add('Found errors in ' .. g:testfunc .. ':')
      messages->extend(v:errors)

      total_errors->add('Run ' .. g:run_nr .. ':')
      total_errors->extend(v:errors)

      if g:run_nr == 5 || prev_error == v:errors[0]
        total_errors->add('Flaky test failed too often, giving up')
        v:errors = total_errors
        break
      endif

      messages->add('Flaky test failed, running it again')

      # Flakiness is often caused by the system being very busy.  Sleep a
      # couple of seconds to have a higher chance of succeeding the second
      # time.
      sleep 2

      prev_error = v:errors[0]
      v:errors = []
      ++g:run_nr

      RunTheTest(g:testfunc)

      if len(v:errors) == 0
        # Test passed on rerun.
        break
      endif
    endwhile
  endif

  AfterTheTest(g:testfunc)
endfor

FinishTesting()

# vim: shiftwidth=2 sts=2 expandtab
