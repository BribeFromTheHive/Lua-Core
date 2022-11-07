--[==[
Total Initialization v5.1 by Bribe

Your one-stop shop for initialization and requirements.

Special thanks:
    @Eikonium for the "try" function and for challenging bad API approaches and leading me to discovering far simpler API for this resource.
    @HerlySQR for GetStackTrace, which makes debugging a much more straightforward process.
    @Tasyen for helping me to better understand the "main" function, and for discovering MarkGameStarted can be hooked for OnInit.final's needs.
    @Luashine for showing how I can implement OnInit.config, which - in turn - led to an actual OnInit.main (previous attempts had failed)
    @Forsakn and Troll-Brain for help with early debugging (primarily with the pairs desync issue)

For laying the framework for requirements in WarCraft 3 Lua:
    @Almia's https://www.hiveworkshop.com/threads/lua-module-system.335222/
    @ScorpioT1000's https://github.com/Indaxia/wc3-wlpm-module-manager/blob/master/wlpm-module-manager.lua
    @Troll-Brain's https://www.hiveworkshop.com/threads/lua-require-ersatz.326584/

What this does:
    Allows you to postpone the initialization of your script until a specific point in the loading sequence.
    Additionally, all callback functions in this resource are safely called via xpcall or pcall, giving you highly valuable debugging information.
    Also provides the ability to Require another resource. This functions similarly to Lua's "require" method, which was disabled in the WarCraft 3 environment.

Why not just use do...end blocks in the Lua root?
    • Creating WarCraft 3 objects in the Lua root is dangerous as it causes desyncs.
    • The Lua root is an unstable place to initialize (e.g. it doesn't allow "print", which makes debugging extremely difficult)
    • do...end blocks force you to organize your triggers from top to bottom based on their requirements.
    • The Lua root is not split into separate pcalls, which means that failures can easily crash the entire loading sequence without showing an error message.
    • The Lua root is not yieldable, which means you need to do everything immediately or hook onto something like InitBlizzard or MarkGameStarted to await these loading steps.

What is the sequence of events?
    1) The Lua root runs.
    2) OnInit functions that require nothing - or - already have their requirements fulfilled in the Lua root.
    3) OnInit functions that have their requirements fulfilled based on other OnInit declarations.
    4) OnInit "custom" initializers run sequentially, prolonging the initialization queue.
    5) Repeat step 2-4 until all executables are loaded and all subsequent initializers have run.
    6) OnInit.final is the final initializer, which is called after the loading screen has transitioned into the actual game screen.
    7) Display error messages for missing requirements.

Basic API for initializer functions:
    OnInit.root(function() print "This is called immediately" end)
    OnInit.config(function() print "This is called during the map config process (in game lobby)" end)
    OnInit.main(function() print "This is called during the loading screen" end)
    OnInit(function() print "All udg_ variables have been initialized" end)
    OnInit.trig(function() print "All InitTrig_ functions have been called" end)
    OnInit.map(function() print "All Map Initialization events have run" end)
    OnInit.final(function() print "The game has now started" end)

Note: You can optionally include a string as an argument to give your initializer a name. This is useful in two scenarios:
    1) If you don't add anything to the global API but want it to be useful as a requirment.
    2) If you want it to be accurately defined for initializers that optionally require it.

API for Requirements:
    local someLibrary = Require "SomeLibrary"
    > Imitates Lua's built-in (but disabled in WarCraft 3) "require" function, provided that you use it from an OnInit callback function.

    local optionalRequirement = Require.lazy "OptionalRequirement"
    > Similar to the Require method, but will only wait if the optional requirement was declared in an OnInit string parameter. This name can be
    > whatever suits you (optional/lazy/nonStrict), as it uses the __index method rather than limit itself to one keyword.
    
    OnInit "My custom initializer"
    > Allows you to define a custom initializer for other resources to require. This is an extension of the "named" initializers that can be provided,
    > except that it allows you to have multiple different initialization points in your script that will yield to allow other libraries to catch up,
    > before continuing on with the rest of the script. The main reason I wrote this was to handle vJass2Lua Runtime Environment's complex translation
    > of JassHelper's initialization flow.
--------------
CONFIGURABLES:       ]==]
do
--change this assignment to false or nil if you don't want to print any caught errors at the start of the game.
--You can otherwise change the color code to a different hex code if you want.
local _ERROR           = "ff5555"

local _USE_COROUTINES  = true --Change this to false if you don't use the "Require" API.
local _USE_LIBRARY_API = true --Change this to false if you don't use the "library" API.

local _CUSTOM_INIT     = "custom initializer" --Used internally; must not overlap with externally-named libraries

--END CONFIGURABLES
-------------------
OnInit = {} --new, cleaner API introduced in version 5

local _G     = _G
local rawget = rawget
local insert = table.insert

local function doesVariableExist(name, source)
    return rawget(source or _G, name)~=nil
end

local library
local customInits = 0
if _USE_LIBRARY_API then
    library = {
        declarations = {},
        initQueue    = {},
        loaded       = {},
        initiallyMissingRequirements = _ERROR and {},
        initialize = function()
            if library.initQueue[1] then
                
                local continue, tempInitQueue, forceOptional
                ::initLibraries::
                repeat
                    continue=false
                    
                    library.initQueue, tempInitQueue = {}, library.initQueue
                    
                    for _,func in ipairs(tempInitQueue) do
                        if func(forceOptional) then
                            --Something was initialized; therefore further systems might be able to initialize.
                            continue=true
                        else
                            --If the queued initializer returns false, that means it did not run, so we re-add it.
                            insert(library.initQueue, func)
                        end
                    end
                until not continue or not library.initQueue[1]
                if customInits > 0 then
                    library.loaded[_CUSTOM_INIT]=true
                elseif not forceOptional then
                    forceOptional = true
                else
                    return
                end
                goto initLibraries
            end
        end
    }
end

local runInitializer = {}
do
    local gmt = getmetatable(_G) or getmetatable(setmetatable(_G, {}))
    local ___newindex = gmt.__newindex or rawset
    local newIndex
    newIndex = function(g, key, val)
        if key == "main" or key == "config" then
            if key == "config" then
                runInitializer.root(true)
            end
            ___newindex(g, key, function()
                if key == "main" and gmt.__newindex == newIndex then
                    gmt.__newindex = ___newindex --restore the original __newindex if no further hooks on __newindex exist.
                end
                runInitializer[key]()
                val()
            end)
        else
            ___newindex(g, key, val)
        end
    end
    gmt.__newindex = newIndex
end
local _InitBlizzard = InitBlizzard
InitBlizzard = function()
    _InitBlizzard()

    --Try to hook. If the variable doesn't exist, run the initializer immediately. Once either have executed, call the continue function.
    local function hook(whichHook, whichInit, continue)
        local function callback()
            runInitializer[whichInit]()
            if continue then continue() end
        end
        if rawget(_G, whichHook) then
            local hooked = rawget(_G, whichHook)
            _G[whichHook] = function()
                hooked()
                callback()
            end
        else
            callback()
        end
    end
    hook("InitGlobals", "global", function()
        hook("InitCustomTriggers", "trig", function()
            hook("RunInitializationTriggers", "map")
        end)
    end)
end
local _MarkGameStarted = MarkGameStarted
MarkGameStarted = function()
    _MarkGameStarted()
    runInitializer.final()
    runInitializer=nil
    if _ERROR and _USE_LIBRARY_API and library.initQueue[1] then
        for _,ini in ipairs(library.initiallyMissingRequirements) do
            if not doesVariableExist(ini) and not library.loaded[ini] then
                print("OnInit.library missing requirement: "..ini)
            end
        end
    end
    library=nil
end

local function callUserInitFunction(initFunc, name, initName)
    local function initFuncWrapper()
        local function funcWrapper()
            if _USE_LIBRARY_API and initName then
                -- Cache the return value of the loaded resource, or just flag it as true.
                library.loaded[initName] = initFunc(Require) or rawget(_G, initName) or true -- Return values of false or nil are discarded and replaced with true.
                --print("loaded ".. tostring(initName).. " as ".. tostring(library.loaded[initName]))
            else
                initFunc(Require)
            end
        end
        if _ERROR then
            if try then
                try(funcWrapper) --https://www.hiveworkshop.com/threads/debug-utils-ingame-console-etc.330758/post-3552846
            else
                xpcall(funcWrapper, function(msg)
                    xpcall(error, print, "\nInitialization Error with "..name..":\n"..msg, 4)
                end)
            end
        else
            pcall(funcWrapper)
        end
    end
    if _USE_COROUTINES then
        coroutine.resume(coroutine.create(initFuncWrapper))
    else
        initFuncWrapper()
    end
end

---Handle logic for initialization functions that wait for certain initialization points during the map's loading sequence.
local function createInitAPI(name, legacy)
    local userInitFunctionList = {}
    
    --Create a handler function to run all initializers pertaining to this particular sequence.
    runInitializer[name]=function(killRoot)
        local function initialize()
            for _,f in ipairs(userInitFunctionList) do
                callUserInitFunction(f, name, _USE_LIBRARY_API and library.declarations[f])
            end
            userInitFunctionList = name=="root" and not killRoot and {} or nil
            if legacy then
                _G[legacy] = nil
            end
        end
        if _USE_LIBRARY_API then
            initialize()
            library.initialize()
        else
            initialize()
        end
    end

    ---Calls userFunc during the map loading process.
    ---@param nameOrFunc function|string
    ---@param initFunc? function
    OnInit[name] = function(nameOrFunc, initFunc)
        local initFuncName, userFunc
        if initFunc then
            initFuncName = nameOrFunc
            if _USE_LIBRARY_API and library.loaded[initFuncName]~=nil then
                error("Library redeclared: "..initFuncName)
            end
            userFunc = initFunc
        else
            userFunc=nameOrFunc
        end
        if type(userFunc) == "function" then
            insert(userInitFunctionList, userFunc)
            if _USE_LIBRARY_API and initFuncName then
                library.declarations[userFunc] = initFuncName
                library.loaded[initFuncName] = false
            end
        else
            error("bad argument to '" .. name.."' (function expected, got "..type(userFunc)..")")
        end
    end
    return OnInit[name]
end
do
    local root = createInitAPI("root")                   -- Runs immediately during the Lua root, but is yieldable (allowing requirements) and pcalled.
    OnInit.root = function(...)
        root(...)
        runInitializer.root()
    end
end
createInitAPI("config")                                  -- Runs when "config" is called. Credit to @Luashine: https://www.hiveworkshop.com/threads/inject-main-config-from-we-trigger-code-like-jasshelper.338201/
createInitAPI("main")                                    -- Runs when "main" is called. Idea from @Tasyen: https://www.hiveworkshop.com/threads/global-initialization.317099/post-3374063
OnGlobalInit  = createInitAPI("global", "OnGlobalInit")  -- Runs once all GUI variables are instantiated.
OnTrigInit    = createInitAPI("trig",   "OnTrigInit")    -- Runs once all InitTrig_ are called.
OnMapInit     = createInitAPI("map",    "OnMapInit")     -- Runs once all Map Initialization triggers are run.
OnGameStart   = createInitAPI("final",  "OnGameStart")   -- Runs once the game has actually started.

OnInit.__call = function(init, name, callback)
    if callback or type(name)=="function" then
        return init.global(name, callback) --Calling OnInit directly defaults to OnInit.global (AKA OnGlobalInit)
    else
        --yields the calling function until after all currently-queued initializers have run, declaring a name for its sequence so others can require it.
        local co = coroutine.running()
        init.library({_CUSTOM_INIT}, function()
            library.loaded[_CUSTOM_INIT]=false
            customInits = customInits - 1
            coroutine.resume(co)
        end)
        library.loaded[name] = true
        customInits = customInits + 1
        coroutine.yield(co)
    end
end
setmetatable(OnInit, OnInit)

if _USE_LIBRARY_API then

    ---Needed for functionality of Require, Require.optional and OnInit functions which declare a name string.
    ---@param whichInit string|table
    ---@param userFunc fun()
    function OnInit.library(whichInit, userFunc, source)
        source = source or _G
        local  nameOfInit
        local  typeOfInit =         type(whichInit)
        if     typeOfInit=="string" then whichInit = {whichInit}
        elseif typeOfInit~="table" then
            error("bad argument #1 to 'OnInit.library' (table expected, got "..typeOfInit..")")
        else
            nameOfInit = whichInit.name
            if nameOfInit then
                library.loaded[nameOfInit]=false
            end
        end
        if not userFunc or type(userFunc)~="function" then
            error("bad argument #2 to 'OnInit.library' (function expected, got "..type(userFunc)..")")
        end
        if _ERROR then
            for _,initName in ipairs(whichInit) do
                if initName ~= _CUSTOM_INIT and not doesVariableExist(initName, source) then
                    insert(library.initiallyMissingRequirements, initName)
                end
            end
        end
        insert(library.initQueue, function(forceOptional)
            if whichInit then
                for _,initName in ipairs(whichInit) do
                    --check all strings in the table and make sure they exist in _G or were already initialized by OnInit.library with a non-global name.
                    if not doesVariableExist(initName, source) and not library.loaded[initName] then return end
                end
                if not forceOptional and whichInit.optional then
                    for _,initName in ipairs(whichInit.optional) do
                        --If the item isn't yet initialized, but is queued to initialize, then we postpone the initialization.
                        --Declarations would be made in the Lua root, so if optional dependencies are not found by the time
                        --OnInit.library runs its triggers, we can assume that it doesn't exist in the first place.
                        if not doesVariableExist(initName, source) and library.loaded[initName]==false then return end
                    end
                end
                whichInit = nil --flag as nil to prevent recursive calls.
                
                --run the initializer if all requirements either exist in _G or have been fully declared.
                callUserInitFunction(userFunc, "library", nameOfInit)
                return true
            end
        end)
    end
end

if _USE_LIBRARY_API and _USE_COROUTINES then
    local function addReq(optional, ...)
        local packed = {...}
        local req = packed[1]
        local source = _G
        if type(req) == "string" then
            local index, prop = req:match("([\x25w_]+)\x25.(.*)")
            if index and prop then
                source, req = rawget(_G, index), prop --user is requiring using "table.property" syntax
                source = source or addReq(optional, index) --If the source is nil, yield until it is not.
                if not source then
                    return --The source table for the requirement wasn't found, so disregard the rest (this only happens with optional requirements).
                end
            end
        end
        if not doesVariableExist(req, source) and not optional or library.loaded[req]==false then
            local co = coroutine.running()
            OnInit.library(optional and {optional=packed} or packed, function() coroutine.resume(co) end, source)
            coroutine.yield(co)
        end
        return library.loaded[req] or rawget(source, req)
    end
    local function optional(...) return addReq(true,  ...) end
    Require = {
        __call  = function(_, ...) return addReq(false, ...) end,
        __index = function() return optional end
    }
    setmetatable(Require, Require)
end

end
