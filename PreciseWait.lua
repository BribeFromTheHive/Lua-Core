OnLibraryInit("AddHook", function() -- https://www.hiveworkshop.com/threads/hook.339153
    --Precise Wait v1.4.1.0
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
    
    AddHook("PolledWait", wait, _WAIT_PRIORITY)
    AddHook("TriggerSleepAction", wait, _WAIT_PRIORITY)
    
    local oldSync
    oldSync = AddHook("SyncSelections",
    function()
        local thread = coroutine.running()
        if thread then
            function SyncSelectionsHelper() --this function gets re-declared each time, so calling it via ExecuteFunc will still reference the correct thread.
                oldSync()
                coroutine.resume(thread)
            end
            ExecuteFunc("SyncSelectionsHelper")
            coroutine.yield(thread)
        end
    end)
    
    local oldAdd, init
    oldAdd = AddHook("TriggerAddAction", function(trig, func)
        if GlobalRemap and not init then
            init = true

            --This enables GUI to access WaitIndex as a "local" index for their arrays, which allows
            --the simplest fully-instanciable data attachment in WarCraft 3's GUI history. However,
            --using it as an array index will cause memory leaks over time, unless you also install
            --the GUI Repair Collection: https://www.hiveworkshop.com/threads/gui-repair-collection.317084/

            GlobalRemap("udg_WaitIndex", coroutine.running)
        end
        --Return a function that will actually be added as the triggeraction, which itself wraps the actual function in a coroutine.
        return oldAdd(trig, function() coroutine.resume(coroutine.create(func)) end)
    end, _ACTION_PRIORITY)
    
end) --End of library PolledWait
