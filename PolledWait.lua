if Hook then -- https://www.hiveworkshop.com/threads/hook.339153
    --PolledWait 1.3.2.0
    --This overrides the default functionality of TriggerSleepAction,
    --SyncSelections, PolledWait and TriggerAction.
    
    local _PRIORITY = -1 --Specify the hook priority for hooking TriggerAddAction (higher numbers run earlier in the sequence).
    
    local function wait(hook)
        local thread = coroutine.running()
        if thread and not hook.skip then
            hook.skip = true
            local t = CreateTimer()
            TimerStart(t, hook.args[1], false, 
            function()
                DestroyTimer(t)
                coroutine.resume(thread)
            end)
            coroutine.yield(thread)
        end
    end
    
    Hook.add("PolledWait", wait)
    Hook.add("TriggerSleepAction", wait)
    
    local oldSync
    oldSync = Hook.add("SyncSelections",
    function(hook)
        local thread = coroutine.running()
        if thread and not hook.skip then
            hook.skip = true
            function SyncSelectionsHelper()
                oldSync()
                coroutine.resume(thread)
            end
            ExecuteFunc("SyncSelectionsHelper")
            coroutine.yield(thread)
        end
    end)
    
    if not EnableWaits then --Ensures compatibility with Lua Fast Triggers
        Hook.add("TriggerAddAction",
        function(hook)
            local func = hook.args[2]
            hook.args[2] = --Override the function parameter itself and allow the original native to run within the hook.
            function()
                coroutine.resume(coroutine.create(
                function()
                    func()
                end))
            end
        end, _PRIORITY)
    end
end