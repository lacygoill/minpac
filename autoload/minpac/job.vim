vim9script noclear
# Author: Prabir Shrestha <mail at prabir dot me>
# Website: https://github.com/prabirshrestha/async.vim
# License: The MIT License {{{
#   The MIT License (MIT)
#
#   Copyright (c) 2016 Prabir Shrestha
#
#   Permission is hereby granted, free of charge, to any person obtaining a copy
#   of this software and associated documentation files (the "Software"), to deal
#   in the Software without restriction, including without limitation the rights
#   to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
#   copies of the Software, and to permit persons to whom the Software is
#   furnished to do so, subject to the following conditions:
#
#   The above copyright notice and this permission notice shall be included in all
#   copies or substantial portions of the Software.
#
#   THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
#   IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
#   FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
#   AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
#   LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
#   OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
#   SOFTWARE.
# }}}

var jobidseq: number
var jobs: dict<dict<any>> # { job, opts, type: 'vimjob|nvimjob'}
var job_type_nvimjob: string = 'nvimjob'
var job_type_vimjob: string = 'vimjob'
var job_error_unsupported_job_type: number = -2 # unsupported job type

def JobSupportedTypes(): list<string>
    var supported_types: list<string>
    if has('nvim')
        supported_types += [job_type_nvimjob]
    endif
    if !has('nvim') && has('job') && has('channel') && has('lambda')
        supported_types += [job_type_vimjob]
    endif
    return supported_types
enddef

def JobSupportsType(type: string): bool
    return JobSupportedTypes()->index(type) >= 0
enddef

def OutCb(
    jobid: number,
    opts: dict<any>,
    job: channel,
    data: string
)
    if opts->has_key('on_stdout')
        opts.on_stdout(jobid, data->split("\n", true), 'stdout')
    endif
enddef

def ErrCb(
    jobid: number,
    opts: dict<any>,
    job: channel,
    data: string
)
    if opts->has_key('on_stderr')
        opts.on_stderr(jobid, data->split("\n", true), 'stderr')
    endif
enddef

def ExitCb(
    jobid: number,
    opts: dict<any>,
    job: job,
    status: number
)
    if opts->has_key('on_exit')
        opts.on_exit(jobid, status, 'exit')
    endif
    if jobs->has_key(jobid)
        jobs->remove(jobid)
    endif
enddef

def OnStdout(
    jobid: number,
    data: string,
    event: string
)
    if jobs->has_key(jobid)
        var jobinfo: dict<any> = jobs[jobid]
        if jobinfo.opts->has_key('on_stdout')
            jobinfo.opts.on_stdout(jobid, data, event)
        endif
    endif
enddef

def OnStderr(
    jobid: number,
    data: string,
    event: string
)
    if jobs->has_key(jobid)
        var jobinfo: dict<any> = jobs[jobid]
        if jobinfo.opts->has_key('on_stderr')
            jobinfo.opts.on_stderr(jobid, data, event)
        endif
    endif
enddef

def OnExit(
    jobid: number,
    status: string,
    event: string
)
    if jobs->has_key(jobid)
        var jobinfo: dict<any> = jobs[jobid]
        if jobinfo.opts->has_key('on_exit')
            jobinfo.opts.on_exit(jobid, status, event)
        endif
    endif
enddef

def JobStart(
    cmd: list<string>,
    opts: dict<any>
): number

    var jobtypes: list<string> = JobSupportedTypes()
    var jobtype: string

    if opts->has_key('type')
        if opts.type->typename() == 'string'
            if !JobSupportsType(opts.type)
                return job_error_unsupported_job_type
            endif
            jobtype = opts.type
        else
            jobtypes = opts.type
        endif
    endif

    if empty(jobtype)
        # find the best jobtype
        for jobtype2 in jobtypes
            if JobSupportsType(jobtype2)
                jobtype = jobtype2
            endif
        endfor
    endif

    if jobtype == ''
        return job_error_unsupported_job_type
    endif

    var jobid: number
    if jobtype == job_type_nvimjob
        var job: number = call('jobstart', [cmd, {
            on_stdout: OnStdout,
            on_stderr: OnStderr,
            on_exit: OnExit,
        }])
        if job <= 0
            return job
        endif
        jobid = job # nvimjobid and internal jobid is same
        jobs[jobid] = {
            type: job_type_nvimjob,
            opts: opts,
        }
        jobs[jobid].job = job
    elseif jobtype == job_type_vimjob
        ++jobidseq
        jobid = jobidseq
        var job: job = cmd
            ->job_start({
                out_cb: function(OutCb, [jobid, opts]),
                err_cb: function(ErrCb, [jobid, opts]),
                exit_cb: function(ExitCb, [jobid, opts]),
                mode: 'raw',
            })
        if job_status(job) !=? 'run'
            return -1
        endif
        jobs[jobid] = {
            type: job_type_vimjob,
            opts: opts,
            job: job,
            channel: job_getchannel(job),
            buffer: ''
        }
    else
        return job_error_unsupported_job_type
    endif

    return jobid
enddef

def JobStop(jobid: number)
    if jobs->has_key(jobid)
        var jobinfo: dict<any> = jobs[jobid]
        if jobinfo.type == job_type_nvimjob
            call('jobstop', [jobid])
        elseif jobinfo.type == job_type_vimjob
            job_stop(jobs[jobid].job)
        endif
        if jobs->has_key(jobid)
            jobs->remove(jobid)
        endif
    endif
enddef

def JobSend(jobid: number, data: string)
    var jobinfo: dict<any> = jobs[jobid]
    if jobinfo.type == job_type_nvimjob
        call('jobsend', [jobid, data])
    elseif jobinfo.type == job_type_vimjob
        jobinfo.buffer ..= data
        FlushVimSendraw(jobid, v:null)
    endif
enddef

def FlushVimSendraw(jobid: number, _)
    # https://github.com/vim/vim/issues/2548
    # https://github.com/natebosch/vim-lsc/issues/67#issuecomment-357469091
    var jobinfo: dict<any> = jobs[jobid]
    if len(jobinfo.buffer) <= 1'024
        ch_sendraw(jobinfo.channel, jobinfo.buffer)
        jobinfo.buffer = ''
    else
        var to_send: string = jobinfo.buffer[: 1'023]
        jobinfo.buffer = jobinfo.buffer[1'024 :]
        ch_sendraw(jobinfo.channel, to_send)
        timer_start(1, function(FlushVimSendraw, [jobid]))
    endif
enddef

def JobWaitSingle(
    jobid: number,
    atimeout: number,
    start: list<number>
): number

    if !jobs->has_key(jobid)
        return -3
    endif

    var jobinfo: dict<any> = jobs[jobid]
    if jobinfo.type == job_type_nvimjob
        var timeout: float = atimeout - start->reltime()->reltimefloat() * 1'000
        return call('jobwait', [[jobid], float2nr(timeout)])[0]
    elseif jobinfo.type == s:job_type_vimjob
        var timeout: float = atimeout / 1000.0
        try
            while timeout < 0 || start->reltime()->reltimefloat() < timeout
                var info: dict<any> = job_info(jobinfo.job)
                if info.status == 'dead'
                    return info.exitval
                elseif info.status == 'fail'
                    return -3
                endif
                sleep 1m
            endwhile
        catch /^Vim:Interrupt$/
            return -2
        endtry
    endif
    return -1
enddef

def JobWait(
    jobids: list<number>,
    timeout: number
): list<number>

    var start: list<number> = reltime()
    var exitcode: number
    var ret: list<number>
    for jobid: number in jobids
        if exitcode != -2  # Not interrupted.
            exitcode = JobWaitSingle(jobid, timeout, start)
        endif
        ret += [exitcode]
    endfor
    return ret
enddef

# public apis {{{
def minpac#job#start(
    cmd: list<string>,
    opts: dict<any>
): number
    return JobStart(cmd, opts)
enddef

def minpac#job#stop(jobid: number)
    JobStop(jobid)
enddef

def minpac#job#send(jobid: number, data: string)
    JobSend(jobid, data)
enddef

def minpac#job#wait(
    jobids: list<number>,
    timeout = -1
): list<number>
    return JobWait(jobids, timeout)
enddef

