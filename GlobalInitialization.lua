if Hook then --https://www.hiveworkshop.com/threads/hook.339153
    
    -- Global Initialization 2.2.2.0 by Bribe, with special thanks to Tasyen, Forsakn and Troll-Brain
    
    local sFuncs
    local function Flush()
        if sFuncs then return end
        sFuncs = {}
        Hook.add("InitBlizzard",
        function()
            local t = CreateTimer()
            TimerStart(t, 0.00, false,
            function()
                DestroyTimer(t)
                for _, f in ipairs(sFuncs) do f() end
                sFuncs          = nil
                OnGlobalInit    = nil
                OnTrigInit      = nil
                OnMapInit       = nil
                OnGameStart     = nil
                Hook.flush("InitBlizzard")
                Hook.flush("InitGlobals")
                Hook.flush("InitCustomTriggers")
                Hook.flush("RunInitializationTriggers")
            end)
        end)
    end
    
    local function Init(str, backup, func, priority)
        if not func or type(func) == "number" then
            func, priority = priority, func or true
        end
        if not Hook.add(str, func, priority) then
            backup(priority, func)
        end
        Flush()
    end
    
    ---@param priority number | function
    ---@param func? function
    function OnGlobalInit(priority, func) -- Runs once all GUI variables are instantiated.
        Init("InitGlobals", function(priority, func) Hook.add("InitBlizzard", func, priority) end, func, priority)
    end
    
    ---@param priority number | function
    ---@param func? function
    function OnTrigInit(priority, func) -- Runs once all InitTrig_ are called
        Init("InitCustomTriggers", OnGlobalInit, func, priority)
    end
    
    ---@param priority number | function
    ---@param func? function
    function OnMapInit(priority, func) -- Runs once all Map Initialization triggers are run
        Init("RunInitializationTriggers", OnTrigInit, func, priority)
    end
    
    ---@param func function
    function OnGameStart(func) -- Runs once the game has actually started
        Flush()
        sFuncs[#sFuncs + 1] = func
    end
end --End of Global Initialization