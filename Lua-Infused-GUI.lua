--[[
    Lua-Infused GUI with automatic memory leak resolution: Modernizing the experience for a better future for users of the Trigger Editor.

    Credits:
        Bribe, Tasyen, Dr Super Good, HerlySQR

    Transforming rects, locations, groups, forces and BJ hashtable wrappers into Lua tables, which are automatically garbage collected.

    Provides RegisterAnyPlayerUnitEvent to cut down on handle count and simplify syntax for Lua users while benefitting GUI.

    Provides GUI.enumUnitsInRect/InRange/Selected/etc. which replaces the first parameter with a function (which takes a unit), for immediate action without needing a separate group variable.
    
    Provides GUI.loopArray for safe iteration over a __jarray
    
    Updated: 7 Nov 2022

    Uses optionally:
        https://github.com/BribeFromTheHive/Lua-Core/blob/main/Total%20Initialization.lua
        https://github.com/BribeFromTheHive/Lua-Core/blob/main/Hook.lua
        https://github.com/BribeFromTheHive/Lua-Core/blob/main/Global%20Variable%20Remapper.lua
        https://github.com/BribeFromTheHive/Lua-Core/blob/main/UnitEvent.lua
--]]
GUI = {}
do
--Configurables
local _USE_GLOBAL_REMAP = false --set to true if you want GUI to have extended functionality such as "udg_HashTableArray" (which gives GUI an infinite supply of shared hashtables)
local _USE_UNIT_EVENT   = false --set to true if you have UnitEvent in your map and want to automatically remove units from their unit groups if they are removed from the game.

--Define common variables to be utilized throughout the script.
local _G = _G
local unpack = table.unpack
do
    --[[-----------------------------------------------------------------------------------------
    __jarray expander by Bribe
    
    This snippet will ensure that objects used as indices in udg_ arrays will be automatically
    cleaned up when the garbage collector runs, and tries to re-use metatables whenever possible.
    -------------------------------------------------------------------------------------------]]
    local mts = {}
    local weakKeys = {__mode="k"} --ensures tables with non-nilled objects as keys will be garbage collected.

    ---Re-define __jarray.
    ---@param default? any
    ---@param tab? table
    ---@return table
    __jarray=function(default, tab)
        local mt
        if default then
            mts[default]=mts[default] or {
                __index=function()
                    return default
                end,
                __mode="k"
            }
            mt=mts[default]
        else
            mt=weakKeys
        end
        return setmetatable(tab or {}, mt)
    end
    --have to do a wide search for all arrays in the variable editor. The WarCraft 3 _G table is HUGE,
    --and without editing the war3map.lua file manually, it is not possible to rewrite it in advance.
    for k,v in pairs(_G) do
        if type(v) == "table" and string.sub(k, 1, 4)=="udg_" then
            __jarray(v[0], v)
        end
    end
    ---Add this safe iterator function for jarrays.
    ---@param whichTable table
    ---@param func fun(index:integer, value:any)
    function GUI.loopArray(whichTable, func)
        for i=rawget(whichTable, 0)~=nil and 0 or 1, #whichTable do
            func(i, rawget(whichTable, i))
        end
    end
end
--[=============[
  • HASHTABLES •
--]=============]
do --[[
    GUI hashtable converter by Tasyen and Bribe
    
    Converts GUI hashtables API into Lua Tables, overwrites StringHashBJ and GetHandleIdBJ to permit
    typecasting, bypasses the 256 hashtable limit by avoiding hashtables, provides the variable
    "HashTableArray", which automatically creates hashtables for you as needed (so you don't have to
    initialize them each time).
]]
    function StringHashBJ(s) return s end
    function GetHandleIdBJ(id) return id end

    local function load(whichHashTable,parentKey)
        local index = whichHashTable[parentKey]
        if not index then
            index=__jarray()
            whichHashTable[parentKey]=index
        end
        return index
    end
    if _USE_GLOBAL_REMAP then
        OnInit(function(import)
            local remap = import "GlobalRemapArray"
            local hashes = __jarray()
            remap("udg_HashTableArray", function(index)
                return load(hashes, index)
            end)
        end)
    end
    
    local last
    GetLastCreatedHashtableBJ=function() return last end
    function InitHashtableBJ() last=__jarray() ; return last end
    
    local function saveInto(value, childKey, parentKey, whichHashTable)
        if childKey and parentKey and whichHashTable then
            load(whichHashTable, parentKey)[childKey] = value
        end
    end
    local function loadFrom(childKey, parentKey, whichHashTable, default)
        if childKey and parentKey and whichHashTable then
            local val = load(whichHashTable, parentKey)[childKey]
            return val ~= nil and val or default
        end
    end
    SaveIntegerBJ = saveInto
    SaveRealBJ = saveInto
    SaveBooleanBJ = saveInto
    SaveStringBJ = saveInto
    
    local function createDefault(default)
        return function(childKey, parentKey, whichHashTable)
            return loadFrom(childKey, parentKey, whichHashTable, default)
        end
    end
    local loadNumber = createDefault(0)
    LoadIntegerBJ = loadNumber
    LoadRealBJ = loadNumber
    LoadBooleanBJ = createDefault(false)
    LoadStringBJ = createDefault("")
    
    do
        local sub = string.sub
        for key in pairs(_G) do
            if sub(key, -8)=="HandleBJ" then
                local str=sub(key, 1,4)
                if str=="Save" then     _G[key] = saveInto
                elseif str=="Load" then _G[key] = loadFrom end
            end
        end
    end
    function HaveSavedValue(childKey, _, parentKey, whichHashTable)
        return load(whichHashTable, parentKey)[childKey] ~= nil
    end
    FlushParentHashtableBJ = function(whichHashTable)
        for key in pairs(whichHashTable) do
            whichHashTable[key]=nil
        end
    end
    function FlushChildHashtableBJ(whichHashTable, parentKey)
        whichHashTable[parentKey]=nil
    end
end
--[===========================[
  • LOCATIONS (POINTS IN GUI) •
--]===========================]
do
    local oldLocation, location = Location
    do
        local oldRemove = RemoveLocation
        local oldGetX   = GetLocationX
        local oldGetY   = GetLocationY
        local oldRally  = GetUnitRallyPoint
        function GetUnitRallyPoint(unit)
            local removeThis = oldRally(unit) --Actually needs to create a location for a brief moment, as there is no GetUnitRallyX/Y
            local loc = {oldGetX(removeThis), oldGetY(removeThis)}
            oldRemove(removeThis)
            return loc
        end
    end

    RemoveLocation = DoNothing
    function Location(x,y)
        return {x,y}
    end
    do
        local oldMoveLoc = MoveLocation
        local oldGetZ=GetLocationZ
        function GUI.getCoordZ(x,y)
            GUI.getCoordZ = function(x,y)
                oldMoveLoc(location, x, y)
                return oldGetZ(location)
            end
            location = oldLocation(x,y)
            return oldGetZ(location)
        end
        
    end
    function GetLocationX(loc) return loc[1] end
    function GetLocationY(loc) return loc[2] end
    function GetLocationZ(loc)
        return GUI.getCoordZ(loc[1], loc[2])
    end
    function MoveLocation(loc, x, y)
        loc[1]=x
        loc[2]=y
    end
    local function fakeCreate(varName, suffix)
        local getX=_G[varName.."X"]
        local getY=_G[varName.."Y"]
        _G[varName..(suffix or "Loc")]=function(obj) return {getX(obj), getY(obj)} end
    end
    fakeCreate("GetUnit")
    fakeCreate("GetOrderPoint")
    fakeCreate("GetSpellTarget")
    fakeCreate("CameraSetupGetDestPosition")
    fakeCreate("GetCameraTargetPosition")
    fakeCreate("GetCameraEyePosition")
    fakeCreate("BlzGetTriggerPlayerMouse", "Position")
    fakeCreate("GetStartLocation")

    BlzSetSpecialEffectPositionLoc = function(effect, loc)
        local x,y=loc[1],loc[2]
        BlzSetSpecialEffectPosition(effect, x, y, GUI.getCoordZ(x,y))
    end
    ---@param oldVarName string
    ---@param newVarName string
    ---@param index integer needed to determine which of the parameters calls for a location.
    local function hook(oldVarName, newVarName, index)
        local new = _G[newVarName]
        local func
        if index==1 then
            func=function(loc, ...)
                return new(loc[1], loc[2], ...)
            end
        elseif index==2 then
            func=function(a, loc, ...)
                return new(a, loc[1], loc[2], ...)
            end
        else--index==3
            func=function(a, b, loc, ...)
                return new(a, b, loc[1], loc[2], ...)
            end
        end
        _G[oldVarName] = func
    end
    hook("IsLocationInRegion",                  "IsPointInRegion", 2)
    hook("IsUnitInRangeLoc",                    "IsUnitInRangeXY", 2)
    hook("IssuePointOrderLoc",                  "IssuePointOrder", 3)
          IssuePointOrderLocBJ                  =IssuePointOrderLoc
    hook("IssuePointOrderByIdLoc",              "IssuePointOrderById", 3)
    hook("IsLocationVisibleToPlayer",           "IsVisibleToPlayer", 1)
    hook("IsLocationFoggedToPlayer",            "IsFoggedToPlayer", 1)
    hook("IsLocationMaskedToPlayer",            "IsMaskedToPlayer", 1)
    hook("CreateFogModifierRadiusLoc",          "CreateFogModifierRadius", 3)
    hook("AddSpecialEffectLoc",                 "AddSpecialEffect", 2)
    hook("AddSpellEffectLoc",                   "AddSpellEffect", 3)
    hook("AddSpellEffectByIdLoc",               "AddSpellEffectById", 3)
    hook("SetBlightLoc",                        "SetBlight", 2)
    hook("DefineStartLocationLoc",              "DefineStartLocation", 2)
    hook("GroupEnumUnitsInRangeOfLoc",          "GroupEnumUnitsInRange", 2)
    hook("GroupEnumUnitsInRangeOfLocCounted",   "GroupEnumUnitsInRangeCounted", 2)
    hook("GroupPointOrderLoc",                  "GroupPointOrder", 3)
          GroupPointOrderLocBJ                  =GroupPointOrderLoc
    hook("GroupPointOrderByIdLoc",              "GroupPointOrderById", 3)
    hook("MoveRectToLoc",                       "MoveRectTo", 2)
    hook("RegionAddCellAtLoc",                  "RegionAddCell", 2)
    hook("RegionClearCellAtLoc",                "RegionClearCell", 2)
    hook("CreateUnitAtLoc",                     "CreateUnit", 3)
    hook("CreateUnitAtLocByName",               "CreateUnitByName", 3)
    hook("SetUnitPositionLoc",                  "SetUnitPosition", 2)
    hook("ReviveHeroLoc",                       "ReviveHero", 2)
    hook("SetFogStateRadiusLoc",                "SetFogStateRadius", 3)
    
    ---@param min table location
    ---@param max table location
    ---@return rect newRect
    RectFromLoc = function(min, max)
        return Rect(min[1], min[2], max[1], max[2])
    end
    ---@param whichRect rect
    ---@param min table location
    ---@param max table location
    SetRectFromLoc = function(whichRect, min, max)
        SetRect(whichRect, min[1], min[2], max[1], max[2])
    end
end
--[=============================[
  • GROUPS (UNIT GROUPS IN GUI) •
--]=============================]
do
    local mainGroup = bj_lastCreatedGroup
    DestroyGroup(bj_suspendDecayFleshGroup)
    DestroyGroup(bj_suspendDecayBoneGroup)
    DestroyGroup=DoNothing

    CreateGroup=function() return {indexOf={}} end
    bj_lastCreatedGroup=CreateGroup()
    bj_suspendDecayFleshGroup=CreateGroup()
    bj_suspendDecayBoneGroup=CreateGroup()

    local groups
    if _USE_UNIT_EVENT then
        groups = {}
        function GroupClear(group)
            if group then
                local u
                for i=1, #group do
                    u=group[i]
                    groups[u]=nil
                    group.indexOf[u]=nil
                    group[i]=nil
                end
            end
        end
    else
        function GroupClear(group)
            if group then
                for i=1, #group do
                    group.indexOf[group[i]]=nil
                    group[i]=nil
                end
            end
        end
    end
    function GroupAddUnit(group, unit)
        if group and unit and not group.indexOf[unit] then
            local pos = #group+1
            group.indexOf[unit]=pos
            group[pos]=unit
            if groups then
                groups[unit] = groups[unit] or __jarray()
                groups[unit][group]=true
            end
        end
    end
    function GroupRemoveUnit(group, unit)
        local indexOf = group and unit and group.indexOf
        if indexOf then
            local pos = indexOf[unit]
            if pos then
                local size = #group
                if pos ~= size then
                    indexOf[group[size]] = pos
                end
                group[size]=nil
                indexOf[unit]=nil
                if groups then
                    groups[unit][group]=nil
                end
            end
        end
    end
    function IsUnitInGroup(unit, group)
        return unit and group and group.indexOf[unit]
    end
    function FirstOfGroup(group)
        return group and group[1]
    end

    local enumUnit
    GetEnumUnit=function() return enumUnit end

    function GUI.forGroup(group, code)
        for i=1, #group do
            code(group[i])
        end
    end
    ForGroup = function(group, code)
        if group and code then
            local old = enumUnit
            GUI.forGroup(group, function(unit)
                enumUnit=unit
                code()
            end)
            enumUnit=old
        end
    end
    do
        local oldUnitAt=BlzGroupUnitAt
        function BlzGroupUnitAt(group, index)
            return group and group[index+1]
        end
        local oldGetSize=BlzGroupGetSize
        local function groupAction(code)
            for i=0, oldGetSize(mainGroup)-1 do
                code(oldUnitAt(mainGroup, i))
            end
        end
        for _,name in ipairs({
            "OfType",
            "OfPlayer",
            "OfTypeCounted",
            "InRect",
            "InRectCounted",
            "InRange",
            "InRangeOfLoc",
            "InRangeCounted",
            "InRangeOfLocCounted",
            "Selected"
        }) do
            local varStr = "GroupEnumUnits"..name
            local old=_G[varStr]
            _G[varStr]=function(group, ...)
                if group then
                    old(mainGroup, ...)
                    GroupClear(group)
                    groupAction(function(unit)
                        GroupAddUnit(group, unit)
                    end)
                end
            end
            --Provide API for Lua users who just want to efficiently run code, without caring about the group itself.
            GUI["enumUnits"..name]=function(code, ...)
                old(mainGroup, ...)
                groupAction(code)
            end
        end
    end
    
    for _,name in ipairs {
        "ImmediateOrder",
        "ImmediateOrderById",
        "PointOrder",
        "PointOrderById",
        "TargetOrder",
        "TargetOrderById"
    } do
        local new = _G["Issue"..name]
        _G["Group"..name]=function(group, ...)
            for i=1, #group do
                new(group[i], ...)
            end
        end
    end
    GroupTrainOrderByIdBJ = GroupImmediateOrderById

    BlzGroupGetSize=function(group) return group and #group or 0 end
    
    function GroupAddGroup(group, add)
        if not group or not add then return end
        GUI.forGroup(add, function(unit)
            GroupAddUnit(group, unit)
        end)
    end
    function GroupRemoveGroup(group, remove)
        if not group or not remove then return end
        GUI.forGroup(remove, function(unit)
            GroupRemoveUnit(group, unit)
        end)
    end

    GroupPickRandomUnit=function(group)
        return group and group[1] and group[GetRandomInt(1,#group)] or 0
    end
    IsUnitGroupEmptyBJ=function(group)
        return not group or not group[1]
    end
    
    ForGroupBJ=ForGroup
    CountUnitsInGroup=BlzGroupGetSize
    BlzGroupAddGroupFast=GroupAddGroup
    BlzGroupRemoveGroupFast=GroupRemoveGroup
    GroupPickRandomUnitEnum=nil
    CountUnitsInGroupEnum=nil
    GroupAddGroupEnum=nil
    GroupRemoveGroupEnum=nil

    if groups then
        OnInit(function(import)
            import "UnitEvent"
            UnitEvent.onRemoval(function(data)
                local u = data.unit
                local g = groups[u]
                if g then
                    for _,group in pairs(g) do
                        GroupRemoveUnit(group,u)
                    end
                end
            end)
        end)
    end
end
--[========================[
  • RECTS (REGIONS IN GUI) •
--]========================]
do
    local oldRect, rect = Rect
    function Rect(...) return {...} end
    
    local oldSetRect = SetRect
    function SetRect(r, mix, miy, max, may)
        r[1]=mix
        r[2]=miy
        r[3]=max
        r[4]=may
    end

    do
        local oldWorld = GetWorldBounds
        local getMinX=GetRectMinX
        local getMinY=GetRectMinY
        local getMaxX=GetRectMaxX
        local getMaxY=GetRectMaxY
        local remover = RemoveRect
        RemoveRect=DoNothing
        local newWorld
        function GetWorldBounds()
            if not newWorld then
                local w = oldWorld()
                newWorld = {getMinX(w),getMinY(w),getMaxX(w),getMaxY(w)}
                remover(w)
            end
            return {unpack(newWorld)}
        end
        GetEntireMapRect = GetWorldBounds
    end
    function GetRectMinX(r) return r[1] end
    function GetRectMinY(r) return r[2] end
    function GetRectMaxX(r) return r[3] end
    function GetRectMaxY(r) return r[4] end
    function GetRectCenterX(r) return (r[1] + r[3])/2 end
    function GetRectCenterY(r) return (r[2] + r[4])/2 end

    function MoveRectTo(r, x, y)
        x = x - GetRectCenterX(r)
        y = y - GetRectCenterY(r)
        SetRect(r, r[1]+x, r[2]+y, r[3]+x, r[4]+y)
    end

    ---@param varName string
    ---@param index integer needed to determine which of the parameters calls for a rect.
    local function hook(varName, index)
        local old = _G[varName]
        local func
        if index==1 then
            func=function(rct, ...)
                oldSetRect(rect, unpack(rct))
                return old(rect, ...)
            end
        elseif index==2 then
            func=function(a, rct, ...)
                oldSetRect(rect, unpack(rct))
                return old(a, rect, ...)
            end
        else--index==3
            func=function(a, b, rct, ...)
                oldSetRect(rect, unpack(rct))
                return old(a, b, rect, ...)
            end
        end
        _G[varName] = function(...)
            if not rect then rect = oldRect(0,0,32,32) end
            _G[varName] = func
            return func(...)
        end
    end
    hook("EnumDestructablesInRect", 1)
    hook("EnumItemsInRect", 1)
    hook("AddWeatherEffect", 1)
    hook("SetDoodadAnimationRect", 1)
    hook("GroupEnumUnitsInRect", 2)
    hook("GroupEnumUnitsInRectCounted", 2)
    hook("RegionAddRect", 2)
    hook("RegionClearRect", 2)
    hook("SetBlightRect", 2)
    hook("SetFogStateRect", 3)
    hook("CreateFogModifierRect", 3)
end
--[===============================[
  • FORCES (PLAYER GROUPS IN GUI) •
--]===============================]
do
    local oldForce, mainForce, initForce = CreateForce
    initForce = function()
        initForce = DoNothing
        mainForce = oldForce()
    end
    CreateForce=function() return {indexOf={}} end
    DestroyForce=DoNothing
    local oldClear=ForceClear
    function ForceClear(force)
        if force then
            for i,val in ipairs(force) do
                force.indexOf[val]=nil
                force[i]=nil
            end
        end
    end
    do
        local oldCripple = CripplePlayer
        local oldAdd=ForceAddPlayer
        CripplePlayer = function(player,force,flag)
            if player and force then
                initForce()
                for _,val in ipairs(force) do
                    oldAdd(mainForce, val)
                end
                oldCripple(player, mainForce, flag)
                oldClear(mainForce)
            end
        end
    end
    function ForceAddPlayer(force, player)
        if force and player and not force.indexOf[player] then
            local pos = #force+1
            force.indexOf[player]=pos
            force[pos]=player
        end
    end
    function ForceRemovePlayer(force, player)
        local pos = force and player and force.indexOf[player]
        if pos then
            force.indexOf[player]=nil
            local top = #force
            if pos ~= top then
                force[pos] = force[top]
                force.indexOf[force[top]] = pos
            end
            force[top] = nil
        end
    end
    function BlzForceHasPlayer(force, player)
        return force and player and force.indexOf[player]
    end
    function IsPlayerInForce(player, force)
        return player and force and force.indexOf[player]
    end
    function IsUnitInForce(unit, force)
        return unit and force and force.indexOf[GetOwningPlayer(unit)]
    end

    local enumPlayer
    local oldForForce = ForForce
    local oldEnumPlayer = GetEnumPlayer
    GetEnumPlayer=function() return enumPlayer end

    ForForce = function(force, code)
        local old = enumPlayer
        for _,player in ipairs(force) do
            enumPlayer=player
            code()
        end
        enumPlayer=old
    end

    local function funnelEnum(force)
        ForceClear(force)
        initForce()
        oldForForce(mainForce, function()
            ForceAddPlayer(force, oldEnumPlayer())
        end)
        oldClear(mainForce)
    end
    local function hookEnum(varStr)
        local old=_G[varStr]
        _G[varStr]=function(force, ...)
            initForce()
            old(mainForce, ...)
            funnelEnum(force)
        end
    end
    hookEnum("ForceEnumPlayers")
    hookEnum("ForceEnumPlayersCounted")
    hookEnum("ForceEnumAllies")
    hookEnum("ForceEnumEnemies")
    CountPlayersInForceBJ=function(force) return #force end
    CountPlayersInForceEnum=nil
    
    GetForceOfPlayer=function(player)
        --No longer leaks. There was no reason to dynamically create forces to begin with.
        return bj_FORCE_PLAYER[GetPlayerId(player)]
    end
end

--Blizzard forgot to add this, but still enabled it for GUI. Therefore, I've extracted and simplified the code from DebugIdInteger2IdString
function BlzFourCC2S(value)
    local result = ""
    for _=1,4 do
        result = string.char(value % 256) .. result
        value = value // 256
    end
    return result
end

function TriggerRegisterDestDeathInRegionEvent(trig, r)
    --Removes the limit on the number of destructables that can be registered.
    EnumDestructablesInRect(r, nil, function() TriggerRegisterDeathEvent(trig, GetEnumDestructable()) end)
end
IsUnitAliveBJ=UnitAlive --use the reliable native instead of the life checks
function IsUnitDeadBJ(u) return not UnitAlive(u) end

function SetUnitPropWindowBJ(whichUnit, propWindow)
    --Allows the Prop Window to be set to zero to allow unit movement to be suspended.
    SetUnitPropWindow(whichUnit, math.rad(propWindow))
end

if _USE_GLOBAL_REMAP then
    OnInit(function(import)
        import "GlobalRemap"
        GlobalRemap("udg_INFINITE_LOOP", function() return -1 end) --a readonly variable for infinite looping in GUI.
    end)
end

do
    local cache=__jarray()
    function GUI.wrapTrigger(whichTrig)
        local func=cache[whichTrig]
        if not func then
            func=function()if IsTriggerEnabled(whichTrig)and TriggerEvaluate(whichTrig)then TriggerExecute(whichTrig)end end
            cache[whichTrig]=func
        end
        return func
    end
end
do
--[[---------------------------------------------------------------------------------------------
    RegisterAnyPlayerUnitEvent by Bribe
    
    RegisterAnyPlayerUnitEvent cuts down on handle count for alread-registered events, plus has
    the benefit for Lua users to just use function calls.
    
    Adds a third parameter to the RegisterAnyPlayerUnitEvent function: "skip". If true, disables
    the specified event, while allowing a single function to run discretely. It also allows (if
    Global Variable Remapper is included) GUI to un-register a playerunitevent by setting
    udg_RemoveAnyUnitEvent to the trigger they wish to remove.

    The "return" value of RegisterAnyPlayerUnitEvent calls the "remove" method. The API, therefore,
    has been reduced to just this one function (in addition to the bj override).
-----------------------------------------------------------------------------------------------]]
    local fStack,tStack,oldBJ = {},{},TriggerRegisterAnyUnitEventBJ
    
    function RegisterAnyPlayerUnitEvent(event, userFunc, skip)
        if skip then
            local t = tStack[event]
            if t and IsTriggerEnabled(t) then
                DisableTrigger(t)
                userFunc()
                EnableTrigger(t)
            else
                userFunc()
            end
        else
            local funcs,insertAt=fStack[event],1
            if funcs then
                insertAt=#funcs+1
                if insertAt==1 then EnableTrigger(tStack[event]) end
            else
                local t=CreateTrigger()
                oldBJ(t, event)
                tStack[event],funcs = t,{}
                fStack[event]=funcs
                TriggerAddCondition(t, Filter(function()
                    for _,func in ipairs(funcs)do func()end
                end))
            end
            funcs[insertAt]=userFunc
            return function()
                local total=#funcs
                for i=1,total do
                    if funcs[i]==userFunc then
                        if     total==1 then DisableTrigger(tStack[event]) --no more events are registered, disable the event (for now).
                        elseif total> i then funcs[i]=funcs[total] end     --pop just the top index down to this vacant slot so we don't have to down-shift the entire stack.
                        funcs[total]=nil --remove the top entry.
                        return true
                    end
                end
            end
        end
    end
    
    local trigFuncs
    function TriggerRegisterAnyUnitEventBJ(trig, event)
        local removeFunc=RegisterAnyPlayerUnitEvent(event, GUI.wrapTrigger(trig))
        if _USE_GLOBAL_REMAP then
            if not trigFuncs then
                trigFuncs=__jarray()
                GlobalRemap("udg_RemoveAnyUnitEvent", nil, function(t)
                    if  trigFuncs[t] then
                        trigFuncs[t]()
                        trigFuncs[t]=nil
                    end
                end)
            end
            trigFuncs[trig]=removeFunc
        end
        return removeFunc
    end
end

---Modify to allow requests for negative hero stats, as per request from Tasyen.
---@param whichHero unit
---@param whichStat integer
---@param value integer
function SetHeroStat(whichHero, whichStat, value)
	(whichStat==bj_HEROSTAT_STR and SetHeroStr or whichStat==bj_HEROSTAT_AGI and SetHeroAgi or SetHeroInt)(whichHero, value, true)
end
--The next part of the code is purely optional, as it is intended to optimize rather than add new functionality
CommentString                           = nil
RegisterDestDeathInRegionEnum           = nil

--This next list comes from HerlySQR, and its purpose is to eliminate useless wrapper functions (only where the parameters aligned):
StringIdentity                          = GetLocalizedString
TriggerRegisterTimerExpireEventBJ       = TriggerRegisterTimerExpireEvent
TriggerRegisterDialogEventBJ            = TriggerRegisterDialogEvent
TriggerRegisterUpgradeCommandEventBJ    = TriggerRegisterUpgradeCommandEvent
RemoveWeatherEffectBJ                   = RemoveWeatherEffect
DestroyLightningBJ                      = DestroyLightning
GetLightningColorABJ                    = GetLightningColorA
GetLightningColorRBJ                    = GetLightningColorR
GetLightningColorGBJ                    = GetLightningColorG
GetLightningColorBBJ                    = GetLightningColorB
SetLightningColorBJ                     = SetLightningColor
GetAbilityEffectBJ                      = GetAbilityEffectById
GetAbilitySoundBJ                       = GetAbilitySoundById
ResetTerrainFogBJ                       = ResetTerrainFog
SetSoundDistanceCutoffBJ                = SetSoundDistanceCutoff
SetSoundPitchBJ                         = SetSoundPitch
AttachSoundToUnitBJ                     = AttachSoundToUnit
KillSoundWhenDoneBJ                     = KillSoundWhenDone
PlayThematicMusicBJ                     = PlayThematicMusic
EndThematicMusicBJ                      = EndThematicMusic
StopMusicBJ                             = StopMusic
ResumeMusicBJ                           = ResumeMusic
VolumeGroupResetImmediateBJ             = VolumeGroupReset
WaitForSoundBJ                          = TriggerWaitForSound
ClearMapMusicBJ                         = ClearMapMusic
DestroyEffectBJ                         = DestroyEffect
GetItemLifeBJ                           = GetWidgetLife -- This was just to type casting
SetItemLifeBJ                           = SetWidgetLife -- This was just to type casting
UnitRemoveBuffBJ                        = UnitRemoveAbility -- The buffs are abilities
GetLearnedSkillBJ                       = GetLearnedSkill
UnitDropItemPointBJ                     = UnitDropItemPoint
UnitDropItemTargetBJ                    = UnitDropItemTarget
UnitUseItemDestructable                 = UnitUseItemTarget -- This was just to type casting
UnitInventorySizeBJ                     = UnitInventorySize
SetItemInvulnerableBJ                   = SetItemInvulnerable
SetItemDropOnDeathBJ                    = SetItemDropOnDeath
SetItemDroppableBJ                      = SetItemDroppable
SetItemPlayerBJ                         = SetItemPlayer
ChooseRandomItemBJ                      = ChooseRandomItem
ChooseRandomNPBuildingBJ                = ChooseRandomNPBuilding
ChooseRandomCreepBJ                     = ChooseRandomCreep
String2UnitIdBJ                         = UnitId -- I think they just wanted a better name
GetIssuedOrderIdBJ                      = GetIssuedOrderId
GetKillingUnitBJ                        = GetKillingUnit
IsUnitHiddenBJ                          = IsUnitHidden
IssueTrainOrderByIdBJ                   = IssueImmediateOrderById -- I think they just wanted a better name
IssueUpgradeOrderByIdBJ                 = IssueImmediateOrderById -- I think they just wanted a better name
GetAttackedUnitBJ                       = GetTriggerUnit -- I think they just wanted a better name
SetUnitFlyHeightBJ                      = SetUnitFlyHeight
SetUnitTurnSpeedBJ                      = SetUnitTurnSpeed
GetUnitDefaultPropWindowBJ              = GetUnitDefaultPropWindow
SetUnitBlendTimeBJ                      = SetUnitBlendTime
SetUnitAcquireRangeBJ                   = SetUnitAcquireRange
UnitSetCanSleepBJ                       = UnitAddSleep
UnitCanSleepBJ                          = UnitCanSleep
UnitWakeUpBJ                            = UnitWakeUp
UnitIsSleepingBJ                        = UnitIsSleeping
IsUnitPausedBJ                          = IsUnitPaused
SetUnitExplodedBJ                       = SetUnitExploded
GetTransportUnitBJ                      = GetTransportUnit
GetLoadedUnitBJ                         = GetLoadedUnit
IsUnitInTransportBJ                     = IsUnitInTransport
IsUnitLoadedBJ                          = IsUnitLoaded
IsUnitIllusionBJ                        = IsUnitIllusion
SetDestructableInvulnerableBJ           = SetDestructableInvulnerable
IsDestructableInvulnerableBJ            = IsDestructableInvulnerable
SetDestructableMaxLifeBJ                = SetDestructableMaxLife
WaygateIsActiveBJ                       = WaygateIsActive
QueueUnitAnimationBJ                    = QueueUnitAnimation
SetDestructableAnimationBJ              = SetDestructableAnimation
QueueDestructableAnimationBJ            = QueueDestructableAnimation
DialogSetMessageBJ                      = DialogSetMessage
DialogClearBJ                           = DialogClear
GetClickedButtonBJ                      = GetClickedButton
GetClickedDialogBJ                      = GetClickedDialog
DestroyQuestBJ                          = DestroyQuest
QuestSetTitleBJ                         = QuestSetTitle
QuestSetDescriptionBJ                   = QuestSetDescription
QuestSetCompletedBJ                     = QuestSetCompleted
QuestSetFailedBJ                        = QuestSetFailed
QuestSetDiscoveredBJ                    = QuestSetDiscovered
QuestItemSetDescriptionBJ               = QuestItemSetDescription
QuestItemSetCompletedBJ                 = QuestItemSetCompleted
DestroyDefeatConditionBJ                = DestroyDefeatCondition
DefeatConditionSetDescriptionBJ         = DefeatConditionSetDescription
FlashQuestDialogButtonBJ                = FlashQuestDialogButton
DestroyTimerBJ                          = DestroyTimer
DestroyTimerDialogBJ                    = DestroyTimerDialog
TimerDialogSetTitleBJ                   = TimerDialogSetTitle
TimerDialogSetSpeedBJ                   = TimerDialogSetSpeed
TimerDialogDisplayBJ                    = TimerDialogDisplay
LeaderboardSetStyleBJ                   = LeaderboardSetStyle
LeaderboardGetItemCountBJ               = LeaderboardGetItemCount
LeaderboardHasPlayerItemBJ              = LeaderboardHasPlayerItem
DestroyLeaderboardBJ                    = DestroyLeaderboard
LeaderboardDisplayBJ                    = LeaderboardDisplay
LeaderboardSortItemsByPlayerBJ          = LeaderboardSortItemsByPlayer
LeaderboardSortItemsByLabelBJ           = LeaderboardSortItemsByLabel
PlayerGetLeaderboardBJ                  = PlayerGetLeaderboard
DestroyMultiboardBJ                     = DestroyMultiboard
SetTextTagPosUnitBJ                     = SetTextTagPosUnit
SetTextTagSuspendedBJ                   = SetTextTagSuspended
SetTextTagPermanentBJ                   = SetTextTagPermanent
SetTextTagAgeBJ                         = SetTextTagAge
SetTextTagLifespanBJ                    = SetTextTagLifespan
SetTextTagFadepointBJ                   = SetTextTagFadepoint
DestroyTextTagBJ                        = DestroyTextTag
ForceCinematicSubtitlesBJ               = ForceCinematicSubtitles
DisplayCineFilterBJ                     = DisplayCineFilter
SaveGameCacheBJ                         = SaveGameCache
FlushGameCacheBJ                        = FlushGameCache
SaveGameCheckPointBJ                    = SaveGameCheckpoint
LoadGameBJ                              = LoadGame
RenameSaveDirectoryBJ                   = RenameSaveDirectory
RemoveSaveDirectoryBJ                   = RemoveSaveDirectory
CopySaveGameBJ                          = CopySaveGame
IssueTargetOrderBJ                      = IssueTargetOrder
IssueTargetDestructableOrder            = IssueTargetOrder -- This was just to type casting
IssueTargetItemOrder                    = IssueTargetOrder -- This was just to type casting
IssueImmediateOrderBJ                   = IssueImmediateOrder
GroupTargetOrderBJ                      = GroupTargetOrder
GroupImmediateOrderBJ                   = GroupImmediateOrder
GroupTargetDestructableOrder            = GroupTargetOrder -- This was just to type casting
GroupTargetItemOrder                    = GroupTargetOrder -- This was just to type casting
GetDyingDestructable                    = GetTriggerDestructable -- I think they just wanted a better name
GetAbilityName                          = GetObjectName -- I think they just wanted a better name

end
