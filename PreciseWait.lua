OnInit("PreciseWait", function(require)        --https://github.com/BribeFromTheHive/Lua-Core/blob/main/Total_Initialization.lua

    local hook  = require.lazily "AddHook"     --https://github.com/BribeFromTheHive/Lua-Core/blob/main/Hook.lua
    local remap = require.lazily "GlobalRemap" --https://github.com/BribeFromTheHive/Lua-Core/blob/main/Global_Variable_Remapper.lua
    if remap then
        require.recommends "GUI"               --https://github.com/BribeFromTheHive/Lua-Core/blob/main/Lua-Infused-GUI.lua
    end
    
    --Precise Wait v1.5.3.0
    --This changes the default functionality of TriggerAddAction, PolledWait
    --and (because they don't work with manual coroutines) TriggerSleepAction and SyncSelections.
    
    local _ACTION_PRIORITY  =  1 --Specify the hook priority for hooking TriggerAddAction (higher numbers run earlier in the sequence).
    local _WAIT_PRIORITY    = -2 --The hook priority for TriggerSleepAction/PolledWait
    local _SYNC_HELPER_NAME = "SyncSelectionsHelper" --Used for ensuring SyncSelections works correctly. Must not interfere with any externally-named globals.

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
        --Lua-Infused GUI.
        remap("udg_WaitIndex", coroutine.running)
    end
    if not hook then
        hook = function(varName, userFunc)
            local old = rawget(_G, varName)
            rawset(_G, varName, userFunc)
            return old
        end
    end
    ---@diagnostic disable: redundant-parameter
    hook("PolledWait", wait, _WAIT_PRIORITY)
    hook("TriggerSleepAction", wait, _WAIT_PRIORITY)
    
    hook("SyncSelections", function()
        local thread = coroutine.running()
        if thread then
            _G[_SYNC_HELPER_NAME] = function() --this function gets re-declared each time, so calling it via ExecuteFunc will still reference the correct thread.
                SyncSelections.original()
                coroutine.resume(thread)
            end
            ExecuteFunc(_SYNC_HELPER_NAME)
            coroutine.yield(thread)
        end
    end)

    hook("TriggerAddAction", function(trig, func)
        --Return a function that will actually be added as the triggeraction, which itself wraps the actual function in a coroutine.
        return TriggerAddAction.original(trig, Debug and function() coroutine.wrap(Debug.try)(func) end or function() coroutine.wrap(func)() end)
    end, _ACTION_PRIORITY)
end, OnInit'end')
