if Debug then Debug.beginFile "Total Initialization" end
--——————————————————————————————————————————————————————
-- Total Initialization version 5.3 Preview
-- Created by: Bribe
-- Contributors: Eikonium, HerlySQR, Tasyen, Luashine, Forsakn
-- Inspiration: Almia, ScorpioT1000, Troll-Brain
--————————————————————————————————————————————————————————————
---@class OnInit
---@field overload  OnInitFunc
---@field root      OnInitFunc
---@field config    OnInitFunc
---@field main      OnInitFunc
---@field global    OnInitFunc
---@field trig      OnInitFunc
---@field map       OnInitFunc
---@field final     OnInitFunc
---@field module    OnInitFunc
OnInit = {}

---@alias OnInitCallback fun(require?: Require):any?
---@alias OnInitFunc fun(initCallback_or_libraryName: OnInitCallback|string, initCallback?: OnInitCallback, debugLineNum?: integer)

---@generic Require.name: function
---@alias OnInitRequirement async fun(requirementName:`Require.name`, explicitSource?: table):Require.name

--"Require" only works within an OnInit callback.
--
--Syntax for strict requirements that throw errors if not found: Require "SomeLibrary"
--
--Syntax for requirements that give up if the required library or variable are not found: Require.optionally "SomeLibrary"
---@class Require: { [string]: OnInitRequirement }
---@field overload OnInitRequirement
---@field strict OnInitRequirement
Require = {}

do
    local library = {} --You can change this to false if you don't use "Require" nor the OnInit.library API.

    ---@diagnostic disable: global-in-nil-env, assign-type-mismatch

    --CONFIGURABLE LEGACY API FUNCTION:
    local function assignLegacyAPI(_ENV, OnInit)
        OnGlobalInit = OnInit; OnTrigInit = OnInit.trig; OnMapInit = OnInit.map; OnGameStart = OnInit.final              --Global Initialization Lite API
        --OnMainInit = OnInit.main; OnLibraryInit = OnInit.library; OnGameInit = OnInit.final                            --short-lived experimental API
        --onGlobalInit = OnInit; onTriggerInit = OnInit.trig; onInitialization = OnInit.map; onGameStart = OnInit.final  --original Global Initialization API
        --OnTriggerInit = OnInit.trig; OnInitialization = OnInit.map                                                     --Forsakn's Ordered Indices API
    end
    --END CONFIGURABLES

    local _G, rawget, insert = _G, rawget, table.insert

    local call   = try or pcall --'try' is extremely useful; found on https://www.hiveworkshop.com/threads/debug-utils-ingame-console-etc.330758/post-3552846
    local fCall  = library and function(...) coroutine.wrap(call)(...) end or call

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
                for _,func in pairs(library.modules) do
                    func(true) --run errors for modules that aren't required.
                end
            end
            OnInit=nil;Require=nil
        end)
    end
    local function addUserFunc(initName, libraryName, func, debugLineNum, incDebugLevel)
        if not func then
            func = libraryName
        else
            assert(type(libraryName)=="string")
            if debugLineNum and Debug then
                Debug.beginFile(libraryName, incDebugLevel and 7 or 6, debugLineNum)
            end
            if library then
                func = library:create(libraryName, func)
            end
        end
        assert(type(func) == "function")
        initFuncQueue[initName] = initFuncQueue[initName] or {}
        insert(initFuncQueue[initName], func)
        if initName == "root" then
            runInitializers "root"
        end
    end
    local function createInit(name)
        ---Calls the user's initialization function during the map's loading process. The first argument should either be the init function,
        ---or it should be the string to give the initializer a name (works similarly to a module name/identically to a vJass library name).
        ---
        ---To use requirements, call Require "LibraryName" or Require.optionally "LibraryName". Alternatively, the callback function can take
        ---the "Require" table as a single parameter: OnInit(function(import) import "ThisIsTheSameAsRequire" end).
        ---
        ---OnInit is called after InitGlobals and is the standard point to initialize......
        ---OnInit.trig is called after InitCustomTriggers, and is useful for removing hooks that should only apply to GUI events......
        ---OnInit.map is the last point in initialization before the loading screen is completed......
        ---OnInit.final occurs immediately after the loading screen has disappeared, and the game has started.
        ---@param libraryNameOrInitFunc string|fun(require?:Require):any
        ---@param userInitFunc? fun(require?:Require):any
        ---@param debugLineNum? integer
        ---@param incDebugLevel? boolean
        return function(libraryNameOrInitFunc, userInitFunc, debugLineNum, incDebugLevel)
            addUserFunc(name, libraryNameOrInitFunc, userInitFunc, debugLineNum, incDebugLevel)
        end
    end
    OnInit.global = createInit "InitGlobals"
    OnInit.trig   = createInit "InitCustomTriggers"
    OnInit.map    = createInit "RunInitializationTriggers"
    OnInit.final  = createInit "MarkGameStarted"

    setmetatable(OnInit, {__call = function(self, libraryNameOrInitFunc, userInitFunc, debugLineNum)
        if userInitFunc or type(libraryNameOrInitFunc)=="function" then
            self.global(libraryNameOrInitFunc, userInitFunc, debugLineNum, true) --Calling OnInit directly defaults to OnInit.global (AKA OnGlobalInit)
        elseif libraryNameOrInitFunc == "end" then
            return Debug and Debug.getLine(3)
        elseif library then
            library:declare(libraryNameOrInitFunc) --API handler for OnInit "Custom initializer"
        else
            error("Bad OnInit args: "..tostring(libraryNameOrInitFunc) .. ", " .. tostring(userInitFunc))
        end
    end})

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
        library.modules  = {}
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
        ---@async
        function library:declare(name)
            declareName(name, true)                 --declare itself as a loaded library.
            local co = coroutine.running()
            insert(self.declared, function() coroutine.resume(co) end)
            coroutine.yield(co) --yields the calling function until after all currently-queued initializers have run.
        end
        local processRequirement
        ---@async
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
                source, requirement = processRequirement(subSource, source), subReq --If the container is nil, yield until it is not.
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
                    if library.modules[requirement] then
                        library.modules[requirement]()
                    end
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
                    error("Missing Requirement: "..requirement) --handle the error within the user's function to get an accurate stack trace via the "try" function.
                end
            end
            return loadRequirement(true)
        end
        function Require.strict(name, explicitSource) return processRequirement(nil, name, explicitSource) end
        setmetatable(Require, { __call = processRequirement, __index = function() return processRequirement end })

        local module  = createInit "module"

        ---@param name string
        ---@param func? fun(require?:Require):any
        ---@param debugLineNum? integer
        OnInit.module = function(name, func, debugLineNum)
            if func then
                local userFunc = func
                func = function(require)
                    local co = coroutine.running()
                    library.modules[name] = function()
                        library.modules[name] = nil
                        coroutine.resume(co)
                    end
                    if coroutine.yield() then
                        error("Module declared but not required: "..name) --works similarly to Go; if you don't need a module, then don't include it in your map.
                    end
                    return userFunc(require)
                end
            end
            module(name, func, debugLineNum)
        end
    end

    if assignLegacyAPI then --This block handles legacy code.
        ---Allows packaging multiple requirements into one table and queues the initialization for later.
        ---@param initList table|string
        ---@param userFunc function
        ---@async
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
            for key in pairs(legacyTable) do rawset(_G, key, nil) end
        end)
    end
end
if Debug then Debug.endFile() end
