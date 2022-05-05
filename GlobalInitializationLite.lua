do
    -- Global Initialization Lite 1.0 by Bribe, with special thanks to Tasyen, Forsakn and Troll-Brain
 
    local initStr = {
        "InitBlizzard",
        "InitGlobals",
        "InitCustomTriggers",
        "RunInitializationTriggers"
    }
    
    local userFuncs = {} ---@type function[]
    local function Init(userFunc, index)
        for i = index, 1, -1 do
            local gf = _G[initStr[i]]
            if gf then
                local uf = userFuncs[i]
                if uf then
                    userFuncs[i] = function() uf() ; userFunc() end
                else
                    userFuncs[i] = userFunc
                    _G[initStr[i]] = function() gf() ; userFuncs[i]() end
                end
                break
            end
        end
    end

    ---@param func function
    function OnGlobalInit(func) -- Runs once all GUI variables are instantiated.
        Init(func, 2)
    end

    ---@param func function
    function OnTrigInit(func) -- Runs once all InitTrig_ are called
        Init(func, 3)
    end
    
    ---@param func function
    function OnMapInit(func) -- Runs once all Map Initialization triggers are run
        Init(func, 4)
    end
    
    local startFunc

    ---@param func function
    function OnGameStart(func) -- Runs once the game has actually started
        local sf = startFunc
        if sf then
            startFunc = function() sf(); func() end
        else
            startFunc = func
            local oldBliz = InitBlizzard
            InitBlizzard = function()
                oldBliz()
                local t = CreateTimer()
                TimerStart(t, 0.00, false,
                function()
                    DestroyTimer(t)
                    startFunc()
                    startFunc   = nil
                    OnGlobalInit= nil
                    OnTrigInit  = nil
                    OnMapInit   = nil
                    OnGameStart = nil
                    userFuncs   = nil
                end)
            end
        end
    end
end --End of Global Initialization