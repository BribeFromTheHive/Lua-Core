OnGlobalInit("PreciseWait", function()

    local hook  = Require.optional "AddHook"     --https://www.hiveworkshop.com/threads/hook.339153
    local remap = Require.optional "GlobalRemap" --https://www.hiveworkshop.com/threads/global-variable-remapper-the-future-of-gui.339308/

    --Precise Wait v1.5.1.0
    --This changes the default functionality of TriggerAddAction, PolledWait
    --and (because they don't work with manual coroutines) TriggerSleepAction and SyncSelections.
    
    local _ACTION_PRIORITY  =  1 --Specify the hook priority for hooking TriggerAddAction (higher numbers run earlier in the sequence).
    local _WAIT_PRIORITY    = -2 --The hook priority for TriggerSleepAction/PolledWait
    
    local function wait(duration)
        local thread = coroutine.running()
        if thread then
            local t = CreateTimer()
            TimerStart(t, duration, false, function()
                DestroyTimer(t)
                coroutine.resume(thread)
            end)
            coroutine.yield(thread)
        end
    end

    if remap then
        --This enables GUI to access WaitIndex as a "local" index for their arrays, which allows
        --the simplest fully-instanciable data attachment in WarCraft 3's GUI history. However,
        --using it as an array index will cause memory leaks over time, unless you also install
        --Lua-Infused GUI: https://www.hiveworkshop.com/threads/lua-infused-gui-automatic-group-location-rect-and-force-leak-prevention.317084/

        remap("udg_WaitIndex", coroutine.running)
    end
    if not hook then
        hook = function(varName, userFunc)
            local old = rawget(_G, varName)
            rawset(_G, varName, userFunc)
            return old
        end
    end
    
    hook("PolledWait", wait, _WAIT_PRIORITY)
    hook("TriggerSleepAction", wait, _WAIT_PRIORITY)
    
    hook("SyncSelections", function()
        local thread = coroutine.running()
        if thread then
            function SyncSelectionsHelper() --this function gets re-declared each time, so calling it via ExecuteFunc will still reference the correct thread.
                SyncSelections.original()
                coroutine.resume(thread)
            end
            ExecuteFunc("SyncSelectionsHelper")
            coroutine.yield(thread)
        end
    end)
    
    hook("TriggerAddAction", function(trig, func)
        --Return a function that will actually be added as the triggeraction, which itself wraps the actual function in a coroutine.
        return TriggerAddAction.original(trig, function() coroutine.resume(coroutine.create(func)) end)
    end, _ACTION_PRIORITY)
    
end)
