--[==[
Total Initialization v5.2 by Bribe

Your one-stop shop for initialization and requirements.

Special thanks:
    @Eikonium for the "try" function and for challenging bad API approaches, leading me to discovering far better API for this resource.
    @HerlySQR for GetStackTrace, which makes debugging a much more straightforward process.
    @Tasyen for helping me to better understand the "main" function, and for discovering MarkGameStarted can be hooked for OnInit.final's needs.
    @Luashine for showing how I can implement OnInit.config, which - in turn - led to an actual OnInit.main (previous attempts had failed)
    @Forsakn and Troll-Brain for help with early debugging (primarily with the pairs desync issue)

For laying the framework for requirements in WarCraft 3 Lua:
    @Almia's https://www.hiveworkshop.com/threads/lua-module-system.335222/
    @ScorpioT1000's https://github.com/Indaxia/wc3-wlpm-module-manager/blob/master/wlpm-module-manager.lua
    @Troll-Brain's https://www.hiveworkshop.com/threads/lua-require-ersatz.326584/
--------------
CONFIGURABLES:       ]==]
do
    --change this assignment to false or nil if you don't want to print any caught errors at the start of the game.
    --You can otherwise change the color code to a different hex code if you want.
    local _ERROR  = "ff5555"
    
    local library = true --Change this to false if you don't use "Require" nor the OnInit.library API.
    
    --END CONFIGURABLES
    -------------------
    OnInit = {} --new, cleaner API introduced in version 5
    
    local _G     = _G
    local rawget = rawget
    local insert = table.insert
    
    local runInitializer = {}

    local function callQueuedFunctions(list, ...)
        for _,func in ipairs(list) do
            func(...)
        end
    end
    do
        local function init(whichInit, continue)
            if whichInit then
                runInitializer[whichInit]()
            end
            if continue then continue() end
        end
        local function hook(whichHook, whichInit, continue, source)
            source = source or _G
            if rawget(source, whichHook) then
                local hooked = rawget(source, whichHook)
                source[whichHook] = function()
                    hooked()
                    init(whichInit, continue)
                end
            else
                init(whichInit, continue)
            end
        end
        hook("InitBlizzard", nil, function()
            hook("InitGlobals", "global", function()
                hook("InitCustomTriggers", "trig", function()
                    hook("RunInitializationTriggers", "map")
                end)
            end)
        end)
        hook("MarkGameStarted", "final", function()
            if _ERROR and library then
                callQueuedFunctions(library.initQueue, nil, true) --print errors for missing requirements.
            end
            OnInit =nil
            Require=nil
        end)
    end
    ---Handle logic for initialization functions that wait for certain initialization points during the map's loading sequence.
    local function createInitAPI(name, legacy)
        local userInitFunctionList = {}
        
        --Create a handler function to run all initializers pertaining to this particular sequence.
        runInitializer[name]=function(killRoot)
            callQueuedFunctions(userInitFunctionList)
            userInitFunctionList = name=="root" and not killRoot and {} or nil
            if legacy then
                _G[legacy] = nil
            end
            if library then
                library.initialize()
            end
        end
    
        ---Calls userFunc during the map loading process.
        ---@param nameOrFunc function|string
        ---@param initFunc? function
        OnInit[name] = function(nameOrFunc, initFunc)
            local userFunc
            if initFunc then
                if library and nameOrFunc then --disregard 'nil' first parameter.
                    assert(type(nameOrFunc)=="string")
                    assert(library.loaded[nameOrFunc]==nil) --must not be re-declared.
                    library.loaded[nameOrFunc] = false --mark it as declared but not loaded.
                    userFunc = function()
                        library.storeData(nameOrFunc, initFunc(Require)) --pack requirements to allow multiple values to be communicated.
                        if library.loaded[nameOrFunc].n==0 then
                            library.storeData(nameOrFunc, true) --No values were returned; therefore simply pack the value of "true"
                        end
                    end
                else
                    userFunc = function() initFunc(Require) end
                end
            else
                userFunc = nameOrFunc
            end
            assert(type(userFunc) == "function")
            local function wrapper()
                if _ERROR and try then
                    try(userFunc) --Extremely useful; found on https://www.hiveworkshop.com/threads/debug-utils-ingame-console-etc.330758/post-3552846
                else
                    pcall(userFunc)
                end
            end
            insert(userInitFunctionList, function()
                if library then
                    coroutine.resume(coroutine.create(wrapper))
                else
                    wrapper()
                end
            end)
        end
        return OnInit[name]
    end
    OnGlobalInit  = createInitAPI("global", "OnGlobalInit")  -- Runs once all GUI variables are instantiated.
    OnTrigInit    = createInitAPI("trig",   "OnTrigInit")    -- Runs once all InitTrig_ are called.
    OnMapInit     = createInitAPI("map",    "OnMapInit")     -- Runs once all Map Initialization triggers are run.
    OnGameStart   = createInitAPI("final",  "OnGameStart")   -- Runs once the game has actually started.
    
    OnInit.__call = function(init, name, callback)
        if callback or type(name)=="function" then
            return init.global(name, callback) --Calling OnInit directly defaults to OnInit.global (AKA OnGlobalInit)
        elseif library then
            library.storeData(name, true) --declare this sequence so others can require it.
            local co = coroutine.running()
            insert(library.yielded, function() coroutine.resume(co) end)
            coroutine.yield(co) --yields the calling function until after all currently-queued initializers have run.
        end
    end
    setmetatable(OnInit, OnInit)
    do --if you don't need the initializers for "root", "config" and "main", you can delete this do...end block.
        local gmt = getmetatable(_G) or getmetatable(setmetatable(_G, {}))
        local ___newindex = gmt.__newindex or rawset
        local newIndex
        newIndex = function(g, key, val)
            if key == "main" or key == "config" then
                if key == "main" then
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
        local root     = createInitAPI("root")                   -- Runs immediately during the Lua root, but is yieldable (allowing requirements) and pcalled.
        OnInit.root    = function(...)
            root(...)
            runInitializer.root()
        end
        createInitAPI("config")                                  -- Runs when "config" is called. Credit to @Luashine: https://www.hiveworkshop.com/threads/inject-main-config-from-we-trigger-code-like-jasshelper.338201/
        createInitAPI("main")                                    -- Runs when "main" is called. Idea from @Tasyen: https://www.hiveworkshop.com/threads/global-initialization.317099/post-3374063
    end
    if library then
        library = {
            initQueue    = {},
            loaded       = {},
            yielded      = {},
            storeData    = function(name, ...) library.loaded[name] = table.pack(...) end,
            initialize   = function()
                if library.initQueue[1] then
                    local continue, tempQueue, forceOptional
                    ::initLibraries::
                    repeat
                        continue=false
                        library.initQueue, tempQueue = {}, library.initQueue
                        
                        for _,func in ipairs(tempQueue) do
                            if func(forceOptional) then
                                continue=true --Something was initialized; therefore further systems might be able to initialize.
                            else
                                insert(library.initQueue, func) --If the queued initializer returns false, that means its requirement wasn't met, so we re-queue it.
                            end
                        end
                    until not continue or not library.initQueue[1]
                    if library.yielded[1] then
                        library.yielded, tempQueue = {}, library.yielded
                        callQueuedFunctions(tempQueue) --unfreeze any custom initializers.
                    elseif not forceOptional then
                        forceOptional = true
                        return
                    end
                    goto initLibraries
                end
            end
        }
        local processRequirement
        processRequirement = function(optional, requirement, explicitSource)
            if type(optional) == "string" then
                optional, requirement, explicitSource = true, optional, requirement --optional requirement (processed by the __index method)
            else
                optional = false --strict requirement (processed by the __call method)
            end
            local source = explicitSource or _G
            assert(type(source)=="table")
            assert(type(requirement)=="string")
            ::reindex::
            local subSource, subReq = requirement:match("([\x25w_]+)\x25.(.+)") --Check if user is requiring using "table.property" syntax
            if subSource and subReq then
                source, requirement = processRequirement(optional, subSource, source), subReq --If the container is nil, yield until it is not.
                if type(source)=="table" then
                    explicitSource = source
                    goto reindex --check for further nested properties ("table.property.subProperty.anyOthers").
                else
                    return --The source table for the requirement wasn't found, so disregard the rest (this only happens with optional requirements).
                end
            end
            local function getResult(dumpResult)
                local result = rawget(source, requirement)
                if not result and not explicitSource then
                    result = library.loaded[requirement]
                    if dumpResult and type(result)=="table" then
                        return table.unpack(result, 1, result.n) --using unpack allows any number of values to be returned by the required library.
                    end
                end
                return result
            end
            local co, result
            local function checkReqs(forceOptional, printErrors)
                if not result then
                    result = getResult()
                    result = result or optional and (result==nil or forceOptional)
                    if result then
                        if co then coroutine.resume(co) end --resume only if it was yielded in the first place.
                        return result
                    elseif printErrors then
                        print(_ERROR.."OnInit missing requirement: "..requirement)
                    end
                end
            end
            if not checkReqs() then --only yield if the requirement doesn't already exist.
                co = coroutine.running()
                insert(library.initQueue, checkReqs)
                coroutine.yield(co)
            end
            return getResult(true)
        end
        Require = { __call = processRequirement, __index = function() return processRequirement end }
        setmetatable(Require, Require)

        ---Allows packaging multiple requirements into one table and queues the initialization for later.
        ---@param initList table|string
        ---@param userFunc function
        function OnInit.library(initList, userFunc)
            local typeOf = type(initList)
            assert(typeOf=="table" or typeOf=="string")
            assert(type(userFunc) == "function")
            OnInit(initList.name, function(use)
                if typeOf=="string" then
                    use(initList)
                else
                    for _,initName in ipairs(initList) do
                        use(initName)
                    end
                    if initList.optional then
                        for _,initName in ipairs(initList.optional) do
                            use.lazily(initName)
                        end
                    end
                end
                return userFunc(use)
            end)
        end
    end
end
