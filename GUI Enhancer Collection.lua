--The GUI Enhancer Collection: a HiveWorkshop community effort to improve the Trigger Editor experience.
--Updated: 03 Sep 2022

function TriggerRegisterDestDeathInRegionEvent(trig, r)
    --Removes the limit on the number of destructables that can be registered.
    EnumDestructablesInRect(r, nil, function() TriggerRegisterDeathEvent(trig, GetEnumDestructable()) end)
end
function IsUnitDeadBJ(u)  return not UnitAlive(u) end
function IsUnitAliveBJ(u) return     UnitAlive(u) end --use the reliable native instead of the life checks

function SetUnitPropWindowBJ(whichUnit, propWindow)
    --Allows the Prop Window to be set to zero to allow unit movement to be suspended.
    SetUnitPropWindow(whichUnit, math.rad(propWindow))
end
    
if OnLibraryInit then OnLibraryInit("GlobalRemap", function()
    GlobalRemap("udg_INFINITE_LOOP", function() return -1 end) --a readonly variable for infinite looping in GUI.
end) end

do
    local cache={}
    function Trig2Func(whichTrig)
        local func=cache[whichTrig]
        if not func then
            func=function()if IsTriggerEnabled(whichTrig)and TriggerEvaluate(whichTrig)then TriggerExecute(whichTrig)end end
            cache[whichTrig]=func
        end
        return func
    end
end

do
    --[[-----------------------------------------------------------------------------------------
    __jarray expander 1.2 by Bribe
    
    This snippet will ensure that objects used as indices in udg_ arrays will be automatically
    cleaned up when the garbage collector runs, and tries to re-use metatables whenever possible.
    -------------------------------------------------------------------------------------------]]
    local mts,cleaner = {},{__mode="k"}
    --without the cleaner variable, tables with non-nilled values pointing to dynamic objects will never be garbage collected.

    ---Re-define __jarray.
    ---@param default? any
    ---@param tab? table
    ---@return table
    function __jarray(default, tab)
        local mt
        if default then
            mt=mts[default]
            if not mt then
                mt={__index=function() return default end, __mode="k"}
                mts[default]=mt
            end
        else
            mt=cleaner
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
    function LoopJArray(whichTable, func)
        for i=rawget(whichTable, 0)~=nil and 0 or 1, #whichTable do
            func(i, rawget(whichTable, i))
        end
    end
end

do
--[[---------------------------------------------------------------------------------------------
  
    RegisterAnyPlayerUnitEvent v1.2.0.0 by Bribe
    
    RegisterAnyPlayerUnitEvent cuts down on handle count for alread-registered events, plus has
    this has the benefit for Lua users to just use function calls.
    
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
        local removeFunc=RegisterAnyPlayerUnitEvent(event, Trig2Func(trig))
        if GlobalRemap then
            if not trigFuncs then
                trigFuncs={}
                --requires https://github.com/BribeFromTheHive/Lua-Core/blob/main/Global%20Variable%20Remapper.lua
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
    local func=whichStat==bj_HEROSTAT_STR and SetHeroStr or
               whichStat==bj_HEROSTAT_AGI and SetHeroAgi or SetHeroInt
	func(whichHero, value, true)
end
CommentString=nil --delete this. World Editor hasn't used it in decades.

--The next addition comes from HerlySQL, and is purely optional as it is intended to optimize rather than add new functionality:
StringIdentity                          = GetLocalizedString
GetEntireMapRect                        = GetWorldBounds
GetHandleIdBJ                           = GetHandleId
StringHashBJ                            = StringHash
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
GroupTrainOrderByIdBJ                   = GroupImmediateOrderById -- I think they just wanted a better name
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
FlushParentHashtableBJ                  = FlushParentHashtable
SaveGameCheckPointBJ                    = SaveGameCheckpoint
LoadGameBJ                              = LoadGame
RenameSaveDirectoryBJ                   = RenameSaveDirectory
RemoveSaveDirectoryBJ                   = RemoveSaveDirectory
CopySaveGameBJ                          = CopySaveGame
IssueTargetOrderBJ                      = IssueTargetOrder
IssuePointOrderLocBJ                    = IssuePointOrderLoc
IssueTargetDestructableOrder            = IssueTargetOrder -- This was just to type casting
IssueTargetItemOrder                    = IssueTargetOrder -- This was just to type casting
IssueImmediateOrderBJ                   = IssueImmediateOrder
GroupTargetOrderBJ                      = GroupTargetOrder
GroupPointOrderLocBJ                    = GroupPointOrderLoc
GroupImmediateOrderBJ                   = GroupImmediateOrder
GroupTargetDestructableOrder            = GroupTargetOrder -- This was just to type casting
GroupTargetItemOrder                    = GroupTargetOrder -- This was just to type casting
GetDyingDestructable                    = GetTriggerDestructable -- I think they just wanted a better name
GetAbilityName                          = GetObjectName -- I think they just wanted a better name

-- end of GUI Enhancer Collection
