--[==[
Global Initialization 'Lite' by Bribe
Last updated 24 Oct 2022

Limited API:
OnGlobalInit(function()
    print "All udg_ variables have been initialized"
end)
OnTrigInit(function()
    print "All InitTrig_ functions have been called"
end)
OnMapInit(function()
    print "All Map Initialization events have run"
end)
OnGameStart(function()
    print "The game has now started"
end) ]==]
do
--change this assignment to false or nil if you don't want to print any caught errors at the start of the game.
--You can otherwise change the color code to a different hex code if you want.
local _ERROR           = "ff5555"

local throwError, errorQueue
if _ERROR then
    errorQueue = {}
    throwError = rawget(_G, "ThrowError") or function(errorMsg)
        table.insert(errorQueue, "|cff".._ERROR..errorMsg.."|r")
    end
end

local runInitializer = {}
local oldInitBlizzard = InitBlizzard
InitBlizzard = function()
    oldInitBlizzard()

    --Try to hook, if the variable doesn't exist, run the initializer immediately. Once either have executed, call the continue function.
    local function tryHook(whichHook, whichInit, continue)
        local hookedFunction = rawget(_G, whichHook)
        if hookedFunction then
            _G[whichHook] = function()
                hookedFunction()
                runInitializer[whichInit]()
                continue()
            end
        else
            runInitializer[whichInit]()
            continue()
        end
    end
    tryHook("InitGlobals", "OnGlobalInit", function()
        tryHook("InitCustomTriggers", "OnTrigInit", function()
            tryHook("RunInitializationTriggers", "OnMapInit", function()
                
                --Use a timer to mark when the game has actually started.
                TimerStart(CreateTimer(), 0, false, function()
                    DestroyTimer(GetExpiredTimer())

                    runInitializer["OnGameStart"]()
                    runInitializer=nil
                    if _ERROR then
                        for _,msg in ipairs(errorQueue) do
                            print(msg) --now that the game has started, call the queued error messages.
                        end
                        errorQueue=nil
                    end
                end)
            end)
        end)
    end)
end

---Handle logic for initialization functions that wait for certain initialization points during the map's loading sequence.
---@param initName string
---@return fun(userFunc:function) OnInit --Calls userFunc during the defined initialization stage.
local function createInitAPI(initName)
    local userInitFunctionList = {}
    
    --Create a handler function to run all initializers pertaining to this particular sequence.
    runInitializer[initName]=function()
        for _,initFunc in ipairs(userInitFunctionList) do
            if _ERROR then
                if try then
                    try(initFunc) --https://www.hiveworkshop.com/threads/debug-utils-ingame-console-etc.330758/post-3552846
                else
                    xpcall(initFunc, function(msg)
                        xpcall(error, throwError, "\nGlobal Initialization Error with "..initName..":\n"..msg, 4)
                    end)
                end
            else
                pcall(initFunc)
            end
        end
        userInitFunctionList=nil
        _G[initName] = nil
    end

    ---Calls initFunc during the specified loading process.
    ---@param initFunc function
    return function(initFunc)
        if type(initFunc) == "function" then
            table.insert(userInitFunctionList, initFunc)
        elseif _ERROR then
            throwError("bad argument to '" .. initName.."' (function expected, got "..type(initFunc)..")")
        end
    end
end
OnGlobalInit = createInitAPI("OnGlobalInit")  -- Runs once all GUI variables are instantiated.
OnTrigInit   = createInitAPI("OnTrigInit")    -- Runs once all InitTrig_ are called.
OnMapInit    = createInitAPI("OnMapInit")     -- Runs once all Map Initialization triggers are run.
OnGameStart  = createInitAPI("OnGameStart")   -- Runs once the game has actually started.
end
