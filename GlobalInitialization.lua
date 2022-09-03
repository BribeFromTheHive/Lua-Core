do  --Global Initialization 4.0.0.2

    --4.0 introduces "OnLibraryInit", which will delay the running of the function
    --until certain variable(s) are present in the global table. This means that
    --only Global Initialization needs to be placed as the top trigger in your map,
    --and any resources which use OnLibraryInit to wait for each other can be found
    --in any order below that.
    
    --Special thanks to Tasyen, Forsakn, Troll-Brain and Eikonium
    
    --change this assignment to false or nil if you don't want to print any caught errors at the start of the game.
    --You can change the color code to a different hex code if you want.
    local _ERROR = "ff5555"
    
    local prePrint,run={},{}
    local initInitializers
    local oldPrint=print
    local newPrint=function(s)
        if prePrint then
            initInitializers()
            prePrint[#prePrint+1]=s
        else
            oldPrint(s)
        end
    end
    print = newPrint
    
    local displayError=_ERROR and function(errorMsg)
        print("|cff".._ERROR..errorMsg.."|r")
    end or DoNothing
    
    local initHandlerQueue, handleQueuedInitializers
    
    initInitializers=function()
        initInitializers = DoNothing
        local function hook(oldFunc, userFunc, chunk)
            local old=_G[oldFunc]
            if old then
                _G[oldFunc]=function()
                    old()
                    run[userFunc]()
                    chunk()
                end
            else
                run[userFunc]()
                chunk()
            end
        end
        local checkStr=function(s) return _G[s] and s end
        --try to hook anything that could be called before InitBlizzard to see if we can initialize even sooner
        local hookAt =
            checkStr("InitSounds") or
            checkStr("CreateRegions") or
            checkStr("CreateCameras") or
            checkStr("InitUpgrades") or
            checkStr("InitTechTree") or
            checkStr("CreateAllDestructables") or
            checkStr("CreateAllItems") or
            checkStr("CreateAllUnits") or
            checkStr("InitBlizzard")
        local oldMain=_G[hookAt]
        _G[hookAt]=function()
            run["OnMainInit"](true)
            oldMain()
            hook("InitGlobals", "OnGlobalInit", function()
                hook("InitCustomTriggers", "OnTrigInit", function()
                    hook("RunInitializationTriggers", "OnMapInit", function()
                        TimerStart(CreateTimer(), 0.00, false, function()
                            DestroyTimer(GetExpiredTimer())
                            run["OnGameStart"]()
                            run=nil
                            if initHandlerQueue then
                                if #initHandlerQueue>0 then
                                    displayError("OnLibraryInit has failed to run "..#initHandlerQueue.." initializers.")
                                end
                                initHandlerQueue=nil
                            end
                            for i=1, #prePrint do oldPrint(prePrint[i]) end
                            prePrint=nil
                            if print==newPrint then print=oldPrint end --restore the function only if no other functions have overriden it.
                        end)
                    end)
                end)
            end)
        end
    end
    
    local function callUserInitFunction(f, name)
        local _,fail = pcall(f)
        if fail then
            displayError(name.." error: "..fail)
        end
    end
    
    local function setupAPIandHandlers(name)
        local funcs={}
        --Add On..Init to the global API for users to call.
        _G[name]=function(func)
            funcs[#funcs+1]=type(func)=="function" and func or load(func)
            initInitializers()
        end
        --Create a handler function to run all initializers pertaining to this initialization level.
        run[name]=function(unsafe)
            for _,f in ipairs(funcs) do
                callUserInitFunction(f, name)
            end
            funcs=nil;_G[name]=nil
            --Needed to add the "unsafe" boolean in 4.0.0.2 due to potential bugs with OnMainInit.
            --This effectively combines OnLibraryInit with OnGlobalInit.
            if handleQueuedInitializers and not unsafe then handleQueuedInitializers() end
        end
    end
    setupAPIandHandlers("OnMainInit")    -- Runs "before" InitBlizzard is called. Meant for assigning things like hooks.
    setupAPIandHandlers("OnGlobalInit")  -- Runs once all GUI variables are instantiated.
    setupAPIandHandlers("OnTrigInit")    -- Runs once all InitTrig_ are called.
    setupAPIandHandlers("OnMapInit")     -- Runs once all Map Initialization triggers are run.
    setupAPIandHandlers("OnGameStart")   -- Runs once the game has actually started.
    
    ---OnLibraryInit is a new function that allows your initialization to wait until others items exist.
    ---This is comparable to vJass library requirements in that you can specify your "library" to wait for
    ---those other libraries to be initialized, before initializing your own.
    ---For example, if you want to ensure your script is processed after "GlobalRemap" has been declared,
    ---you would use:
    ---OnLibraryInit("GlobalRemap", function() print "my library is initializing after GlobalRemap was declared" end)
    ---
    ---To include multiple requirements, pass a string table:
    ---OnLibraryInit({"GlobalRemap", "LinkedList", "MDTable"}, function() print "my library has waited for 3 requirements" end)
    ---@param whichInit string|string[]
    ---@param initFunc fun()
    function OnLibraryInit(whichInit, initFunc)
        if not initHandlerQueue then
            initInitializers()
            initHandlerQueue={} ---@type function[] fun():boolean
            handleQueuedInitializers=function()
                local runRecursively,tempQ
                tempQ,initHandlerQueue=initHandlerQueue,{}
                
                for _,func in ipairs(tempQ) do
                    --If the queued initializer returns true, we can remove it.
                    if func() then
                        runRecursively=true
                    else
                        table.insert(initHandlerQueue, func)
                    end
                end
                if runRecursively and #initHandlerQueue > 0 then
                    --Something was initialized, which might mean that further systems can now be initialized.
                    handleQueuedInitializers()
                end
            end
        end
        local initName=""
        local runInit;runInit=function()
            runInit=nil --nullify itself to prevent potential recursive calls during initFunc's execution.
            
            callUserInitFunction(initFunc, initName)
            return true
        end
        local initFuncHandler
        if type(whichInit)=="string" then
            initName=whichInit
            initFuncHandler=function() return runInit and rawget(_G, whichInit) and runInit() end
        elseif type(whichInit)=="table" then
            initFuncHandler=function()
                if runInit then
                    local result=true
                    for _,ini in ipairs(whichInit) do
                        --check all strings in the table and make sure they exist in _G
                        result=result and rawget(_G, ini)
                    end
                    --run the initializer if all strings have been loaded into _G.
                    return result and runInit()
                end
            end
        else
            displayError("Invalid requirement type passed to OnLibraryInit")
            return
        end
        table.insert(initHandlerQueue, initFuncHandler)
    end
end
