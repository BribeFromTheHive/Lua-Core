-- Total Initialization v5.2.1 by Bribe

-- Your one-stop shop for initialization and requirements.

do  --CONFIGURABLES:
    local library = {} --Change this to false if you don't use "Require" nor the OnInit.library API.

    local function assignLegacyAPI(_ENV, OnInit)                                                                        ---@diagnostic disable-next-line: global-in-nil-env
        OnGlobalInit = OnInit; OnTrigInit = OnInit.trig; OnMapInit = OnInit.map; OnGameStart = OnInit.final              --Global Initialization Lite API
        --OnMainInit = OnInit.main; OnLibraryInit = OnInit.library; OnGameInit = OnInit.final                            --short-lived experimental API
        --onGlobalInit = OnInit; onTriggerInit = OnInit.trig; onInitialization = OnInit.map; onGameStart = OnInit.final  --original Global Initialization API
        --OnTriggerInit = OnInit.trig; OnInitialization = OnInit.map                                                     --Forsakn's Ordered Indices API
    end
    --END CONFIGURABLES

    OnInit = {}
    
    local _G, rawget, insert = _G, rawget, table.insert

    local call   = try or pcall --'try' is extremely useful; found on https://www.hiveworkshop.com/threads/debug-utils-ingame-console-etc.330758/post-3552846
    local fCall  = library and function(...)
        coroutine.wrap(call)(...)
    end or call

    local initFuncQueue = {}
    local function runInitializers(name, continue)
        if initFuncQueue[name] then
            for _,func in ipairs(initFuncQueue[name]) do
                fCall(func, Require)
            end
            initFuncQueue[name] = nil
        end
        if library  then library:resume() end
        if continue then continue()       end
    end
    do
        local function hook(hookName, continue)
            local hookedFunc = rawget(_G, hookName)
            if hookedFunc then
                rawset(_G, hookName, function()
                    hookedFunc()
                    runInitializers(hookName, continue)
                end)
            else
                runInitializers(hookName, continue)
            end
        end
        hook("InitGlobals", function()
            hook("InitCustomTriggers", function()
                hook("RunInitializationTriggers")
            end)
        end)
        hook("MarkGameStarted", function()
            if library then
                for _,func in ipairs(library.yielded) do
                    func(nil, true) --run errors for missing requirements.
                end
            end
            OnInit=nil;Require=nil  --remove API from _G
        end)
    end
    local function addUserFunc(initName, libraryName, func)
        if not func then
            func = libraryName
        elseif library then
            func = library:create(libraryName, func)
        end
        assert(type(func) == "function")
        initFuncQueue[initName] = initFuncQueue[initName] or {}
        insert(initFuncQueue[initName], func)
        if initName == "root" then
            runInitializers "root"
        end
    end
    local function createInit(name)
        ---Calls the user's initialization function during the map's loading process.
        ---@param libraryNameOrInitFunc string|function
        ---@param userInitFunc? fun(Require?:table):any
        return function(libraryNameOrInitFunc, userInitFunc)
            addUserFunc(name, libraryNameOrInitFunc, userInitFunc)
        end
    end
    OnInit.global = createInit "InitGlobals"
    OnInit.trig   = createInit "InitCustomTriggers"
    OnInit.map    = createInit "RunInitializationTriggers"
    OnInit.final  = createInit "MarkGameStarted"
    
    function OnInit:__call(libraryNameOrInitFunc, userInitFunc)
        if userInitFunc or type(libraryNameOrInitFunc)=="function" then ---@diagnostic disable-next-line: param-type-mismatch
            self.global(libraryNameOrInitFunc, userInitFunc) --Calling OnInit directly defaults to OnInit.global (AKA OnGlobalInit)
        elseif library then
            library:declare(libraryNameOrInitFunc) --API handler for OnInit "Custom initializer"
        end
    end
    setmetatable(OnInit, OnInit)

    do --if you don't need the initializers for "root", "config" and "main", you can delete this do...end block.
        local gmt = getmetatable(_G) or getmetatable(setmetatable(_G, {}))
        local ___newindex = gmt.__newindex or rawset
        local newIndex
        function newIndex(g, key, val)
            if key == "main" or key == "config" then
                if key == "main" then
                    runInitializers "root"
                end
                ___newindex(g, key, function()
                    if key == "main" and gmt.__newindex == newIndex then
                        gmt.__newindex = ___newindex --restore the original __newindex if no further hooks on __newindex exist.
                    end
                    runInitializers(key)
                    val()
                end)
            else
                ___newindex(g, key, val)
            end
        end
        gmt.__newindex = newIndex
        OnInit.root    = createInit "root"   -- Runs immediately during the Lua root, but is yieldable (allowing requirements) and pcalled.
        OnInit.config  = createInit "config" -- Runs when "config" is called. Credit to @Luashine: https://www.hiveworkshop.com/threads/inject-main-config-from-we-trigger-code-like-jasshelper.338201/
        OnInit.main    = createInit "main"   -- Runs when "main" is called. Idea from @Tasyen: https://www.hiveworkshop.com/threads/global-initialization.317099/post-3374063
    end
    if library then
        library.packed   = {}
        library.yielded  = {}
        library.declared = {}
        function library:pack(name, ...) self.packed[name] = table.pack(...) end
        function library:resume()
            if self.yielded[1] then
                local continue, tempQueue, forceOptional
                ::initLibraries::
                repeat
                    continue=false
                    self.yielded, tempQueue = {}, self.yielded
                    
                    for _,func in ipairs(tempQueue) do
                        if func(forceOptional) then
                            continue=true --Something was initialized; therefore further systems might be able to initialize.
                        else
                            insert(self.yielded, func) --If the queued initializer returns false, that means its requirement wasn't met, so we re-queue it.
                        end
                    end
                until not continue or not self.yielded[1]
                if self.declared[1] then
                    self.declared, tempQueue = {}, self.declared
                    for _,func in ipairs(tempQueue) do
                        func() --unfreeze any custom initializers.
                    end
                elseif not forceOptional then
                    forceOptional = true
                else
                    return
                end
                goto initLibraries
            end
        end
        local function declareName(name, initialValue)
            assert(type(name)=="string")
            assert(library.packed[name]==nil)
            library.packed[name] = initialValue and {true,n=1}
        end
        function library:create(name, userFunc)
            assert(type(userFunc)=="function")
            declareName(name, false)                --declare itself as a non-loaded library.
            return function()
                self:pack(name, userFunc(Require))  --pack return values to allow multiple values to be communicated.
                if self.packed[name].n==0 then
                    self:pack(name, true)           --No values were returned; therefore simply package the value as "true"
                end
            end
        end
        function library:declare(name)
            declareName(name, true)                 --declare itself as a loaded library.
            local co = coroutine.running()
            insert(self.declared, function() coroutine.resume(co) end)
            coroutine.yield(co) --yields the calling function until after all currently-queued initializers have run.
        end
        local processRequirement
        function processRequirement(optional, requirement, explicitSource)
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
            local function loadRequirement(unpack)
                local package = rawget(source, requirement)
                if not package and not explicitSource then
                    package = library.packed[requirement]
                    if unpack and type(package)=="table" then
                        return table.unpack(package, 1, package.n) --using unpack allows any number of values to be returned by the required library.
                    end
                end
                return package
            end
            local co, loaded
            local function checkReqs(forceOptional, printErrors)
                if not loaded then
                    loaded = loadRequirement()
                    loaded = loaded or optional and (loaded==nil or forceOptional)
                    if loaded then
                        if co then coroutine.resume(co) end --resume only if it was yielded in the first place.
                        return loaded
                    elseif printErrors then
                        coroutine.resume(co, true)
                    end
                end
            end
            if not checkReqs() then --only yield if the requirement doesn't already exist.
                co = coroutine.running()
                insert(library.yielded, checkReqs)
                if coroutine.yield(co) then
                    error("missing requirement: "..requirement) --handle the error within the user's function to get an accurate stack trace via the "try" function.
                end
            end
            return loadRequirement(true)
        end
        Require = { __call = processRequirement, __index = function() return processRequirement end }
        setmetatable(Require, Require)
    end
    if assignLegacyAPI then --This block handles legacy code.
        ---Allows packaging multiple requirements into one table and queues the initialization for later.
        ---@param initList table|string
        ---@param userFunc function
        function OnInit.library(initList, userFunc)
            local typeOf = type(initList)
            assert(typeOf=="table" or typeOf=="string")
            assert(type(userFunc) == "function")
            local function caller(use)
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
            end
            if initList.name then OnInit(initList.name, caller) else OnInit(caller) end
        end

        local legacyTable = {}
        assignLegacyAPI(legacyTable, OnInit)
        for key,func in pairs(legacyTable) do rawset(_G, key, func) end
        OnInit.final(function()
            for key in pairs(legacyTable) do _G[key] = nil end
        end)
    end
end
