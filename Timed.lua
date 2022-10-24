--[[--------------------------------------------------------------------------------------
    Timed Call and Echo v2.0.1.0 by Bribe, special thanks to Eikonium and Jesus4Lyf
    
    Allows automatic timer tracking for the most common use cases (one-shot timers, and
    repeating timers that merge together for optimization).
----------------------------------------------------------------------------------------]]
do
    local _DEFAULT_ECHO_TIMEOUT = 0.03125
    local _EXIT_WHEN_FACTOR = 0.5 --Will potentially stop the echo before it has fully run
                                  --its course (via rounding). Set to 0 to disable. Can also override this from the Timed.echo 5th parameter.
    local zeroList, _ZERO_TIMER
    local timerLists = {}
    local insert = table.insert
    
Timed = {
    --[[--------------------------------------------------------------------------------------
        Name: Timed.call
        Args: [delay, ]userFunc
        Desc: After "delay" seconds, call "userFunc". Delay defaults to 0 seconds.
    ----------------------------------------------------------------------------------------]]
    ---@param delay? number
    ---@param userFunc function
    ---@return fun(doNotDestroy:boolean):number removalFunc -> only gets returned if the delay is > 0.
    call=function(delay, userFunc)
        if type(delay)=="function" then
            userFunc,delay=delay,userFunc
        end
        if not delay or delay <= 0 then
            if zeroList then
                insert(zeroList, userFunc)
            else
                zeroList = {userFunc}
                _ZERO_TIMER = _ZERO_TIMER or CreateTimer()
                TimerStart(_ZERO_TIMER, 0, false, function()
                    local tempList = zeroList
                    zeroList = nil
                    for _, func in ipairs(tempList) do func() end
                end)
            end
        else
            local t = CreateTimer()
            TimerStart(t, delay, false, function()
                DestroyTimer(t)
                t=nil
                userFunc()
            end)
            return function(doNotDestroy)
                local result = 0
                if t then
                    result = TimerGetRemaining(t)
                    if not doNotDestroy then
                        PauseTimer(t)
                        DestroyTimer(t)
                        t=nil
                    end
                end
                return result
            end
        end
    end,

    --[[--------------------------------------------------------------------------------------
    Name: Timed.echo
    Args: [timeout, duration,] userFunc
    Desc: Calls userFunc every "timeout" seconds until userFunc returns true.
        -> will also stop calling userFunc if the duration is reached.
        -> Returns a function you can call to manually stop echoing the userFunc.
    --------------------------------------------------------------------------------------
    Note: This merges all matching timeouts together, so it is advisable only to use this
        for smaller numbers (e.g. <.3 seconds) where the difference is less noticeable.
    ----------------------------------------------------------------------------------------]]
    ---@param timeout? number
    ---@param duration? number
    ---@param userFunc fun():boolean -- if true, echo will stop
    ---@param onExpire? function     -- If the duration is specified and expiration occurs naturally, call this function.
    ---@param tolerance? number      -- Ranges from 0-1. If the duration is specified, the tolerance helps to measure the accuracy of the final tick.
    ---@return function remove_func
    echo=function(timeout, duration, userFunc, onExpire, tolerance)
        if type(timeout) == "function" then
            --parames align to original API of (function[,timeout])
            userFunc,timeout,duration=timeout,duration,userFunc
        elseif not userFunc then
            --params were (timeout,userFunc)
            userFunc,duration=duration,nil
        --else params were exactly as defined.
        end
        local wrapper = function()
            return not userFunc or userFunc() --this wrapper function allows manual removal to be understood and processed accordingly.
        end
        timeout = timeout or _DEFAULT_ECHO_TIMEOUT
        if duration then
            local old=wrapper
            local exitwhen = timeout*(tolerance or _EXIT_WHEN_FACTOR)
            wrapper=function() --this wrapper function enables automatic removal once the duration is reached.
                if not old() then
                    duration = duration - timeout
                    if duration >= exitwhen then
                        return
                    elseif onExpire then
                        print(duration, exitwhen)
                        onExpire()
                    end
                end
                return true
            end
        else
            duration=0
        end
        local timerList = timerLists[timeout]
        if timerList then
            local remaining = TimerGetRemaining(timerList.timer)
            if remaining >= timeout * 0.50 then
                duration = duration + timeout --The delay is large enough to execute on the next tick, therefore increase the duration to avoid double-deducting.
                insert(timerList, wrapper)
            elseif timerList.queue then
                insert(timerList.queue, wrapper)
            else
                timerList.queue = {wrapper}
            end
            duration = duration - remaining --decrease the duration to compensate for the extra remaining time before the next tick.
        else
            timerList = {wrapper}
            timerLists[timeout] = timerList
            timerList.timer = CreateTimer()
            TimerStart(timerList.timer, timeout, true, function()
                local top=#timerList
                for i=top,1,-1 do
                    if timerList[i]() then --The userFunc is to be removed:
                        if i~=top then
                            timerList[i]=timerList[top]
                        end
                        timerList[top]=nil
                        top=top-1
                    end
                end
                if timerList.queue then --Now we can add the queued items to the main list
                    for i,func in ipairs(timerList.queue) do
                        timerList[top+i]=func
                    end
                    timerList.queue = nil
                elseif top == 0 then --list is empty; clear its data.
                    timerLists[timeout] = nil
                    PauseTimer(timerList.timer)
                    DestroyTimer(timerList.timer)
                end
            end)
        end
        return function(doNotDestroy)
            if not doNotDestroy then
                userFunc=nil
            end
            return duration
        end
    end
}
end
