vim9script noclear

if true
  # This is executed only with the eval feature
  set nocompatible
  set viminfo=
  def Count(match: string, type: string)
    if type == 'executed'
      g:executed += (match->str2nr() + 0)
    elseif type == 'failed'
      g:failed += match->str2nr() + 0
    elseif type == 'skipped'
      ++g:skipped
      g:skipped_output->extend(["\t" .. match])
    endif
  enddef

  g:executed = 0
  g:skipped = 0
  g:failed = 0
  g:skipped_output = []
  g:failed_output = []
  var output: list<string> = ['']

  if $TEST_FILTER != ''
    g:skipped_output->extend(["\tAll tests not matching $TEST_FILTER: '" .. $TEST_FILTER .. "'"])
  endif

  try
    # This uses the :s command to just fetch and process the output of the
    # tests, it doesn't actually replace anything.
    # And it uses "silent" to avoid reporting the number of matches.
    silent :% s/Executed\s\+\zs\d\+\ze\s\+tests\?/\=Count(submatch(0), 'executed')/egn
    silent :% s/^SKIPPED \zs.*/\=submatch(0)->Count('skipped')/egn
    silent :% s/^\(\d\+\)\s\+FAILED:/\=submatch(1)->Count('failed')/egn

    output->extend(['Skipped:'])
    output->extend(skipped_output)

    output->extend([
      '',
      '-------------------------------',
      printf('Executed: %5d Tests', g:executed),
      printf(' Skipped: %5d Tests', g:skipped),
      printf('  %s: %5d Tests', g:failed == 0 ? 'Failed' : 'FAILED', g:failed),
      '',
    ])
    if filereadable('test.log')
      # outputs and indents the failed test result
      output->extend(['', 'Failures: '])
      var sfailed_output = readfile('test.log')
        ->filter((_, v: string): bool => !empty(v))
      output->extend(sfailed_output->map((_, v: string): string => "\t" .. v))
      # Add a final newline
      output->extend([''])
    endif

  catch  # Catch-all
  finally
    output->writefile('test_result.log')  # overwrites an existing file
  endtry
endif

q!
