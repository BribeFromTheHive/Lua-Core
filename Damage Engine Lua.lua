if  Hook        -- https://www.hiveworkshop.com/threads/hook.339153
and Timed then  -- https://www.hiveworkshop.com/threads/timed-call-and-echo.339222/

--[[--------------------------------------------------------------------------------------
    
    Lua Damage Engine Version 2.0.0.0
    
    Documentation is found in the code, not in this header.
    
    I'd like to give very special thanks to Eikonium for equipping me with the debugging
    tools I needed to get Lua Damage Engine published. I'd also like to thank MindWorX and
    Eikonium for getting me started with VSCode, which has changed my (programming) life.

    If you want GUI functionality, you also will need the following library:
    Global Variable Remapper    - https://www.hiveworkshop.com/threads/global-variable-remapper
    
----------------------------------------------------------------------------------------]]

OnGlobalInit(1, function() Damage = {}

---@class damageEvent : LinkedListHead

---@class damageEventRegistry : LinkedListNode

---@class damageInstance:table

--[[--------------------------------------------------------------------------------------
    Configurable variables are listed below
----------------------------------------------------------------------------------------]]
    
    local _USE_GUI          = GlobalRemap
    
    local _USE_EXTRA        = _USE_GUI  --If you don't use DamageEventLevel/DamageEventAOE/SourceDamageEvent, set this to false
    local _USE_ARMOR_MOD    = true      --If you do not modify nor detect armor/defense, set this to false
    local _USE_MELEE_RANGE  = true      --If you do not detect melee nor ranged damage, set this to false
    
    local _LIMBO            = 16        --When manually-enabled recursion is enabled via Damage.recurion, the engine will never go deeper than LIMBO.
    local _DEATH_VAL        = 0.405     --In case M$ or Bliz ever change this, it'll be a quick fix here.
    
    local _TYPE_CODE        = 1         --Must be the same as udg_DamageTypeCode, or 0 if you prefer to disable the automatic flag.
    local _TYPE_PURE        = 2         --Must be the same as udg_DamageTypePure
    
    --These variables coincide with Blizzard's "limitop" type definitions.
    local _FILTER_ATTACK    = 0     --LESS_THAN
    local _FILTER_MELEE     = 1     --LESS_THAN_OR_EQUAL
    local _FILTER_OTHER     = 2     --EQUAL
    local _FILTER_RANGED    = 3     --GREATER_THAN_OR_EQUAL
    local _FILTER_SPELL     = 4     --GREATER_THAN
    local _FILTER_CODE      = 5     --NOT_EQUAL
    
    local CheckUnitType = IsUnitType
    local t1, t2, t3    ---@type trigger
    local current       = nil   ---@type damageInstance
    local userIndex     = nil   ---@type damageEventRegistry
    local checkConfig
    do
        local GetUnitItem   = UnitItemInSlot
        local GetItemType   = GetItemTypeId
        local GUTI          = GetUnitTypeId
        local GUAL          = GetUnitAbilityLevel
        local GRR           = GetRandomReal
        local function checkItem(u,  id) 
            if CheckUnitType(u, UNIT_TYPE_HERO) then
                for i = 0, UnitInventorySize(u) - 1 do
                    if GetItemType(GetUnitItem(u, i)) == id then return true end
                end
            end
        end
        checkConfig = function() if not userIndex.configured then return true
        
--[[--------------------------------------------------------------------------------------
    Mapmakers should comment-out any of the below lines that they will never need to check
    for, and move the most common checks to the top of the list.
----------------------------------------------------------------------------------------]]
            
            elseif userIndex.sourceType  and GUTI(current.source) ~= userIndex.sourceType then
            elseif userIndex.targetType  and GUTI(current.target) ~= userIndex.targetType then
            elseif userIndex.sourceBuff  and GUAL(current.source, userIndex.sourceBuff) == 0 then
            elseif userIndex.targetBuff  and GUAL(current.target, userIndex.targetBuff) == 0 then
            elseif userIndex.failChance  and GRR(0.00, 1.00) <= userIndex.failChance then
            elseif userIndex.userType    and current.userType ~= userIndex.userType then
            elseif userIndex.source      and userIndex.source ~= current.source then
            elseif userIndex.target      and userIndex.target ~= current.target then
            elseif userIndex.attackType  and userIndex.attackType ~= current.attackType then
            elseif userIndex.damageType  and userIndex.damageType ~= current.damageType then
            elseif userIndex.sourceItem  and not checkItem(current.source, userIndex.sourceItem) then
            elseif userIndex.targetItem  and not checkItem(current.target, userIndex.targetItem) then
            elseif userIndex.sourceClass and not CheckUnitType(current.source, userIndex.sourceClass) then
            elseif userIndex.targetClass and not CheckUnitType(current.target, userIndex.targetClass) then
            elseif current.damage >= userIndex.damageMin then
            
--[[--------------------------------------------------------------------------------------
    Configuration section is over. The rest of the library is hard-coded.
----------------------------------------------------------------------------------------]]
            
                --print("Configuration passed")
                return true
            end
            --print("Checking failed")
        end
    end 
    
--[[--------------------------------------------------------------------------------------
    Readonly variables are defined below.
----------------------------------------------------------------------------------------]]
    
    local readonly          = {}
    
    readonly.index          = function() return current end         --Damage.index is the currently-running damage table that contains properties like source/target/damage.
    
    local lastRegistered    = nil                                   ---@type damageEventRegistry
    readonly.lastRegistered = function() return lastRegistered end  --Damage.lastRegistered identifies whatever damage event was most recently added.
    
    readonly.userIndex      = function() return userIndex end       --Damage.userIndex identifies the registry table for the damage function that's currently running.
    
    local sourceStacks      = 1
    readonly.sourceStacks   = function() return sourceStacks end    --Damage.sourceStacks holds how many times a single unit was hit from the same source using the same attack. AKA udg_DamageEventLevel.
    
    local sourceAOE         = 1
    readonly.sourceAOE      = function() return sourceAOE end       --Damage.sourceAOE holds how many units were hit by the same source using the same attack. AKA udg_DamageEventAOE.

    local originalSource
    readonly.originalSource = function() return originalSource end  --Damage.originalSource tracks whatever source unit started the current series of damage event(s). AKA udg_AOEDamageSource.
    
    local originalTarget
    readonly.originalTarget = function() return originalTarget end  --Damage.originalTarget tracks whatever target unit was first hit by the original source. AKA udg_EnhancedDamageTarget.
    
    local _DAMAGING         = LinkedList.create()   ---@type damageEvent
    readonly.damagingEvent  = function() return _DAMAGING end
    
    local _ARMOR            = LinkedList.create()   ---@type damageEvent
    readonly.armorEvent     = function() return _ARMOR end
    
    local _DAMAGED          = LinkedList.create()   ---@type damageEvent
    readonly.damagedEvent   = function() return _DAMAGED end
    
    local _ZERO             = LinkedList.create()   ---@type damageEvent
    readonly.zeroEvent      = function() return _ZERO end
    
    local _AFTER            = LinkedList.create()   ---@type damageEvent
    readonly.afterEvent     = function() return _AFTER end
    
    local _LETHAL           = LinkedList.create()   ---@type damageEvent
    readonly.lethalEvent    = function() return _LETHAL end
    
    local _SOURCE           = LinkedList.create()   ---@type damageEvent
    readonly.sourceEvent    = function() return _SOURCE end
    
    local GetUnitLife       = GetWidgetLife
    local SetUnitLife       = SetWidgetLife
    local Alive             = UnitAlive
    local disableT          = DisableTrigger
    local enableT           = EnableTrigger
    local hasLethal         ---@type boolean
    local hasSource         ---@type boolean
    
    ---@class damageEvent

    ---@class damageEventRegistry
    ---@field minAOE        integer
    ---@field filters       boolean[]
    ---@field targetClass   unittype
    ---@field sourceClass   unittype
    ---@field targetItem    itemtype
    ---@field sourceItem    itemtype
    ---@field sourceType    unittype
    ---@field targetType    unittype
    ---@field targetBuff    integer
    ---@field sourceBuff    integer
    ---@field source        unit
    ---@field target        unit
    ---@field attackType    attacktype
    ---@field damageType    damagetype
    ---@field weaponType    weapontype
    ---@field damageMin     number
    ---@field userType      integer
    ---@field trig          trigger
    ---@field eFilter       integer
    ---@field trigFrozen    boolean
    ---@field levelsDeep    integer

    ---@class damageInstance
    ---@field source        unit
    ---@field target        unit
    ---@field damage        real
    ---@field prevAmt       real
    ---@field isAttack      boolean
    ---@field isRanged      boolean
    ---@field isMelee       boolean
    ---@field attackType    attacktype
    ---@field damageType    damagetype
    ---@field weaponType    weapontype
    ---@field isCode        boolean
    ---@field isSpell       boolean
    ---@field recursiveFunc damageEventRegistry[]
    ---@field userType      integer
    ---@field armorPierced  real
    ---@field prevArmorT    integer
    ---@field armorType     integer
    ---@field prevDefenseT  integer
    ---@field defenseType   integer


    local dreaming ---@type boolean
    ---Turn on (true) or off (false or nil) Damage Engine
    ---@param on boolean
    function Damage.enable(on)
        if on then
            if dreaming then enableT(t3)
            else enableT(t1); enableT(t2) end
        else
            if dreaming then disableT(t3)
            else disableT(t1); disableT(t2) end
        end
    end
    
    local breakCheck = {}   ---@type function[]
    local override          ---@type boolean
    
    breakCheck[_DAMAGING]   = function() return override or current.userType == _TYPE_PURE end
    breakCheck[_ARMOR]      = function() return current.damage <= 0.00 end
    breakCheck[_LETHAL]     = function() return hasLethal and Damage.life > _DEATH_VAL end
    
    ---@return boolean
    local function damageOrAfter() return current.damageType == DAMAGE_TYPE_UNKNOWN end
    breakCheck[_DAMAGED]    = damageOrAfter
    breakCheck[_AFTER]      = damageOrAfter
    
    local function defaultCheck() end
    
    ---Common function to run any major event in the system.
    ---@param head damageEventRegistry
    ---@return boolean ran_yn
    local function runEvent(head)
        local check = breakCheck[head] or defaultCheck
        if dreaming or check() then
            return
        end
        userIndex = head.next
        if userIndex ~= head then
            Damage.enable(false)
            enableT(t3)
            dreaming = true
            
            --print("Start of event running")
            repeat
                if not userIndex.trigFrozen and userIndex.filters[userIndex.eFilter] and checkConfig() and not hasSource or (head ~= _SOURCE or (userIndex.minAOE and sourceAOE > userIndex.minAOE)) then
                    userIndex.func()
                end
                userIndex = userIndex.next
            until userIndex == head or check()
            --print("End of event running")
            
            dreaming = nil
            Damage.enable(true)
            disableT(t3)
        end
        return true
    end
    
--[[--------------------------------------------------------------------------------------
    Creates a new table for the damage properties for each particular event sequence.
----------------------------------------------------------------------------------------]]
    
    ---Create a new damage instance
    ---@param src unit
    ---@param tgt unit
    ---@param amt number
    ---@param a boolean
    ---@param r boolean
    ---@param at attacktype
    ---@param dt damagetype
    ---@param wt weapontype
    ---@param fromCode boolean
    ---@return damageInstance
    local function create(src, tgt, amt, a, r, at, dt, wt, fromCode)
        local d = { ---@type damageInstance
            source              = src,
            target              = tgt,
            damage              = amt,
            isAttack            = a or _USE_GUI and udg_NextDamageIsAttack,
            isRanged            = r,
            attackType          = at, 
            damageType          = dt, 
            weaponType          = wt, 
            prevAmt             = amt,
            userAmt             = amt
        }
        d.isSpell               = at == ATTACK_TYPE_NORMAL and not d.isAttack
        if fromCode or Damage.nextType or d.damageType == DAMAGE_TYPE_MIND or (d.damageType == DAMAGE_TYPE_UNKNOWN and d.damage ~= 0.00) or (_USE_GUI and (udg_NextDamageIsAttack or udg_NextDamageIsRanged or udg_NextDamageIsMelee or udg_NextDamageWeaponT)) then
            d.isCode            = true
            d.userType          = Damage.nextType or _TYPE_CODE
            Damage.nextType     = nil
            if _USE_MELEE_RANGE and not d.isSpell then
                d.isMelee       = _USE_GUI and udg_NextDamageIsMelee or (a and not r)
                d.isRanged      = _USE_GUI and udg_NextDamageIsRanged or (a and r)
            end
            d.eFilter           = _FILTER_CODE
            if _USE_GUI then
                udg_NextDamageIsAttack      = nil
                if udg_NextDamageWeaponT then
                    d.weaponType            = ConvertWeaponType(udg_NextDamageWeaponT)
                    udg_NextDamageWeaponT   = nil
                end
                if _USE_MELEE_RANGE then
                    udg_NextDamageIsMelee   = nil
                    udg_NextDamageIsRanged  = nil
                end
            end
        else
            d.userType          = 0
        end
        return d
    end
    
    local GetDamage         = GetEventDamage
    local createFromEvent
    do
        local GetSource     = GetEventDamageSource
        local GetTarget     = GetTriggerUnit
        local GetIsAttack   = BlzGetEventIsAttack
        local GetAttackType = BlzGetEventAttackType
        local GetDamageType = BlzGetEventDamageType
        local GetWeaponType = BlzGetEventWeaponType
        
        ---Create a damage event from a naturally-occuring event.
        ---@param isCode? boolean
        ---@return damageInstance
        function createFromEvent(isCode)
            local d = create(GetSource(), GetTarget(), GetDamage(), GetIsAttack(), false, GetAttackType(), GetDamageType(), GetWeaponType(), isCode)
            if not d.isCode then
                if d.damageType == DAMAGE_TYPE_NORMAL and d.isAttack then
                    if _USE_MELEE_RANGE then
                        d.isMelee       = CheckUnitType(d.source, UNIT_TYPE_MELEE_ATTACKER)
                        d.isRanged      = CheckUnitType(d.source, UNIT_TYPE_RANGED_ATTACKER)
                        if d.isMelee and d.isRanged then
                            d.isMelee   = d.weaponType  -- Melee units play a sound when damaging. In naturally-occuring cases where a
                            d.isRanged  = not d.isMelee -- unit is both ranged and melee, the ranged attack plays no sound.
                        end
                        if d.isMelee then
                            d.eFilter   = _FILTER_MELEE
                        elseif d.isRanged then
                            d.eFilter   = _FILTER_RANGED
                        else
                            d.eFilter   = _FILTER_ATTACK
                        end
                    else
                        d.eFilter       = _FILTER_ATTACK
                    end
                else
                    if d.isSpell then
                        d.eFilter   = _FILTER_SPELL
                    else
                        d.eFilter   = _FILTER_OTHER
                    end
                end
            end
            return d
        end
    end
    
    local alarmSet
    Damage.targets = udg_DamageEventAOEGroup
    
    local function onAOEEnd()
        if _USE_EXTRA then
            runEvent(_SOURCE)
            sourceAOE       = 1
            sourceStacks    = 1
            originalTarget  = nil
            originalSource  = nil
            GroupClear(Damage.targets)
        end
    end
    
    ---Handle any desired armor modification.
    ---@param reset? boolean
    local function setArmor(reset)
        if _USE_ARMOR_MOD then
            local pierce    ---@type real
            local at        ---@type integer
            local dt        ---@type integer
            if reset then
                pierce  =   current.armorPierced
                at      =   current.prevArmorT
                dt      =   current.prevDefenseT
            else
                pierce  =  -current.armorPierced
                at      =   current.armorType
                dt      =   current.defenseType
            end
            if pierce ~= 0.00 then --Changed condition thanks to bug reported by BLOKKADE
                BlzSetUnitArmor(current.target, BlzGetUnitArmor(current.target) + pierce)
            end
            if current.prevArmorT ~= current.armorType then
                BlzSetUnitIntegerField(current.target, UNIT_IF_ARMOR_TYPE, at)
            end
            if current.prevDefenseT ~= current.defenseType then
                BlzSetUnitIntegerField(current.target, UNIT_IF_DEFENSE_TYPE, dt)
            end
        end
    end
    
    local proclusGlobal     = {}                ---@type boolean[]
    local fischerMorrow     = {}                ---@type boolean[]
    local SetEventDamage    = BlzSetEventDamage
    
    local doPreEvents
    do
        local SetEventAttackType     = BlzSetEventAttackType
        local SetEventDamageType     = BlzSetEventDamageType
        local SetEventWeaponType     = BlzSetEventWeaponType
        
        ---Setup pre-events before running any user-facing damage events.
        ---@param d damageInstance
        ---@param natural? boolean
        ---@return boolean isZeroDamage_yn
        doPreEvents = function(d, natural)
            if _USE_ARMOR_MOD then
                d.armorType      = BlzGetUnitIntegerField(d.target, UNIT_IF_ARMOR_TYPE)
                d.defenseType    = BlzGetUnitIntegerField(d.target, UNIT_IF_DEFENSE_TYPE)
                d.prevArmorT     = d.armorType
                d.prevDefenseT   = d.defenseType
                d.armorPierced   = 0.00
            end
            current             = d
            
            proclusGlobal[d.source] = true
            fischerMorrow[d.target] = true
            
            if d.damage == 0.00 then
                return true
            end
            override = d.damageType == DAMAGE_TYPE_UNKNOWN
            runEvent(_DAMAGING)
            if natural then
                SetEventAttackType(d.attackType)
                SetEventDamageType(d.damageType)
                SetEventWeaponType(d.weaponType)
                SetEventDamage(d.damage)
            end
            setArmor()
        end
    end
    
    local function afterDamage() 
        if current then
            runEvent(_AFTER)
            current = nil
        end
        override = nil
    end
    
    local canKick                   = true
    local sleepLevel                = 0
    local totem, kicking, eventsRun
    local prepped                   = nil       ---@type damageInstance
    local recursiveStack            = {}        ---@type damageInstance[]
    local UDT                       = UnitDamageTarget
    
    local function finish()
        if eventsRun then
            eventsRun = nil
            afterDamage()
        end
        current = nil
        override = nil
        if canKick and not kicking then
            if #recursiveStack > 0 then
                kicking = true
                local i = 1
                local exit
                repeat
                    sleepLevel  = sleepLevel + 1
                    exit        = #recursiveStack
                    repeat
                        prepped = recursiveStack[i]
                        if Alive(prepped.target) then
                            doPreEvents(prepped) --don't evaluate the pre-event
                            if prepped.damage > 0.00 then
                                disableT(t1) --Force only the after armor event to run.
                                enableT(t2)  --in case the user forgot to re-enable this
                                totem = true
                                UDT(prepped.source, prepped.target, prepped.damage, prepped.isAttack, prepped.isRanged, prepped.attackType, prepped.damageType, prepped.weaponType)
                            else
                                runEvent(_DAMAGED)
                                if prepped.damage < 0.00 then
                                    --No need for BlzSetEventDamage here
                                    SetUnitLife(prepped.target, GetUnitLife(prepped.target) - prepped.damage)
                                end
                                setArmor(true)
                            end
                            afterDamage()
                        end
                        i = i + 1
                    until (i >= exit)
                until (i >= #recursiveStack)
            end
            for i = 1, #recursiveStack do
                recursiveStack[i].recursiveFunc.trigFrozen  = nil
                recursiveStack[i].recursiveFunc.levelsDeep  = 0
                recursiveStack[i] = nil
            end
            sleepLevel      = 0
            prepped, kicking, dreaming = nil, nil, nil
            Damage.enable(true)
            
            proclusGlobal = {} ---@type boolean[]
            fischerMorrow = {} ---@type boolean[]
            --print("Cleared up the groups")
        end
    end
    
    local function failsafeClear()
        setArmor(true)
        canKick = true
        kicking, totem = nil, nil
        runEvent(_DAMAGED)
        eventsRun = true
        finish()
    end
    
    local lastInstance       ---@type damageInstance
    local attacksImmune = {} ---@type boolean[]
    local damagesImmune = {} ---@type boolean[]
    
    t1 = CreateTrigger()
    TriggerRegisterAnyUnitEventBJ(t1, EVENT_PLAYER_UNIT_DAMAGING)
    TriggerAddCondition(t1, Filter(function()
        local d = createFromEvent()
        --print("Pre-damage event running for " .. GetUnitName(GetTriggerUnit()))
        if alarmSet then
            if totem then --WarCraft 3 didn't run the DAMAGED event despite running the DAMAGING event.
                if d.damageType == DAMAGE_TYPE_SPIRIT_LINK or d.damageType == DAMAGE_TYPE_DEFENSIVE or d.damageType == DAMAGE_TYPE_PLANT then
                    lastInstance    = current
                    totem           = nil
                    canKick         = nil
                else
                    failsafeClear() --Not an overlapping event - just wrap it up
                end
            else
                finish() --wrap up any previous damage index
            end
            
            if _USE_EXTRA then
                if d.source ~= originalSource then
                    onAOEEnd()
                    originalSource = d.source
                    originalTarget = d.target
                elseif d.target == originalTarget then
                    sourceStacks = sourceStacks + 1
                elseif not IsUnitInGroup(d.target, Damage.targets) then
                    sourceAOE = sourceAOE + 1
                end
            end
        else
            alarmSet = true
            Timed.call(
            function()
                alarmSet, dreaming = nil, nil
                Damage.enable(true)
                if totem then
                    failsafeClear() --WarCraft 3 didn't run the DAMAGED event despite running the DAMAGING event.
                else
                    canKick = true
                    kicking = nil
                    finish()
                end
                onAOEEnd()
                current = nil
                --print("Timer wrapped up")
            end)
            if _USE_EXTRA then
                originalSource  = d.source
                originalTarget  = d.target
            end
        end
        if _USE_EXTRA then GroupAddUnit(Damage.targets, d.target) end
        if doPreEvents(d, true) then
            runEvent(_ZERO)
            canKick = true
            finish()
        end
        totem = not lastInstance or attacksImmune[d.attackType] or damagesImmune[d.damageType] or not CheckUnitType(d.target, UNIT_TYPE_MAGIC_IMMUNE)
    end))
    
    t2 = CreateTrigger()
    TriggerRegisterAnyUnitEventBJ(t2, EVENT_PLAYER_UNIT_DAMAGED)
    TriggerAddCondition(t2, Filter(function() 
        local r = GetDamage()
        local d = current
        --print("Second damage event running for " .. GetUnitName(GetTriggerUnit()))
        if prepped                              then prepped = nil
        elseif dreaming or d.prevAmt == 0.00    then return
        elseif totem                            then totem = nil
        else
            afterDamage()
            d               = lastInstance
            current         = d
            lastInstance    = nil
            canKick         = true
        end
        setArmor(true)
        d.userAmt = d.damage
        d.damage = r
        
        if r > 0.00 then
            runEvent(_ARMOR)
            if hasLethal or d.userType < 0 then
                Damage.life = GetUnitLife(d.target) - d.damage
                if Damage.life <= _DEATH_VAL then
                    if hasLethal then
                        runEvent(_LETHAL)
                        
                        d.damage = GetUnitLife(d.target) - Damage.life
                    end
                    if d.userType < 0 and Damage.life <= _DEATH_VAL then
                        SetUnitExploded(d.target, true)
                    end
                end
            end
        end
        if d.damageType ~= DAMAGE_TYPE_UNKNOWN then runEvent(_DAMAGED) end
        SetEventDamage(d.damage)
        eventsRun = true
        if d.damage == 0.00 then finish() end
    end))
    
    --Call to enable recursive damage on your trigger.
    function Damage.inception() userIndex.inceptionTrig = true end
    
    ---add a recursive damage instance
    ---@param d damageInstance
    local function addRecursive(d) 
        if d.damage ~= 0.00 then
            d.recursiveFunc = userIndex
            if kicking and proclusGlobal[d.source] and fischerMorrow[d.target] then
                if not userIndex.inceptionTrig then
                    userIndex.trigFrozen = true
                elseif not userIndex.trigFrozen and userIndex.levelsDeep < sleepLevel then
                    userIndex.levelsDeep = userIndex.levelsDeep + 1
                    userIndex.trigFrozen = userIndex.levelsDeep >= _LIMBO
                end
            end
            recursiveStack[#recursiveStack + 1] = d
            --print("recursiveStack: " .. #recursiveStack .. " levelsDeep: " .. userIndex.levelsDeep .. " sleepLevel: " .. sleepLevel)
        end
    end
    
    t3 = CreateTrigger()
    TriggerRegisterAnyUnitEventBJ(t3, EVENT_PLAYER_UNIT_DAMAGING)
    TriggerAddCondition(t3, Filter(function()
        addRecursive(createFromEvent(true))
        SetEventDamage(0.00)
    end))
    disableT(t3)
    
    ---register a new damage event via Damage.register(Damage.damagingEvent, function() print "a unit is dealing damage" end)
    ---@param head damageEvent
    ---@param func function
    ---@param lbs? number
    ---@param filt? integer
    ---@param trig? trigger
    ---@return damageEventRegistry
    function Damage.register(head, func, lbs, filt, trig)
        filt = filt or _FILTER_OTHER
        if trig and lastRegistered and lastRegistered.trig and lastRegistered.trig == trig then
            lastRegistered.filters[filt]= true
            return
        end
        
        hasLethal                       = hasLethal or head == _LETHAL
        hasSource                       = hasSource or head == _SOURCE
        
        local insertAt = head
        for node in head:loop() do if node.weight > lbs then insertAt = node; break end end
        
        local id                        = insertAt:insert() ---@type damageEventRegistry
        lastRegistered                  = id
        
        id.filters                      = {}
        if filt == _FILTER_OTHER then 
            id.filters[_FILTER_ATTACK]  = true
            id.filters[_FILTER_MELEE]   = true
            id.filters[_FILTER_OTHER]   = true
            id.filters[_FILTER_RANGED]  = true
            id.filters[_FILTER_SPELL]   = true
            id.filters[_FILTER_CODE]    = true
        elseif filt == _FILTER_ATTACK then
            id.filters[_FILTER_ATTACK]  = true
            id.filters[_FILTER_MELEE]   = true
            id.filters[_FILTER_RANGED]  = true
        else
            id.filters[filt]            = true
        end
        id.levelsDeep                   = 0
        id.trig                         = trig
        lbs                             = lbs or 1.00
        id.weight                       = lbs
        id.func                         = func
        
        --print("Registered new event to " .. var)
        return lastRegistered
    end
    ---Remove registered damage event by index
    ---@param index damageEventRegistry
    ---@return boolean removed_yn
    function Damage.remove(index)
        if lastRegistered == index then lastRegistered = nil end
        return index:remove()
    end
    
    Hook.addSimple("TriggerRegisterVariableEvent",
    function(whichTrig, varName, opCode, limitVal)
        local index = ((varName == "udg_DamageModifierEvent" and limitVal < 4)  or varName == "udg_PreDamageEvent")     and _DAMAGING   or
            (varName == "udg_DamageModifierEvent"                               or varName == "udg_ArmorDamageEvent")   and _ARMOR      or
            ((varName == "udg_DamageEvent" and limitVal == 2 or limitVal == 0)  or varName == "udg_ZeroDamageEvent")    and _ZERO       or
            (varName == "udg_DamageEvent"                                       or varName == "udg_OnDamageEvent")      and _DAMAGED    or
            varName == "udg_AfterDamageEvent"                                                                           and _AFTER      or
            varName == "udg_LethalDamageEvent"                                                                          and _LETHAL     or
            (varName == "udg_AOEDamageEvent"                                    or varName == "udg_SourceDamageEvent")  and _SOURCE
        if index then
            local id = Damage.register(index, function() if IsTriggerEnabled(whichTrig) then ConditionalTriggerExecute(whichTrig) end end, limitVal, GetHandleId(opCode), whichTrig)
            if index == _SOURCE then
                id.minAOE = (varName == "udg_AOEDamageEvent" and 1)             or (varName == "udg_SourceDamageEvent" and 0)
            end
            return "skip hook"
        end
    end)
    
    for i = 0, 26 do udg_CONVERTED_DAMAGE_TYPE[i] = ConvertDamageType(i) end
    
    --For filling an array with values from a table.
    ---@param arr table
    ---@param tbl table
    ---@param offset? integer
    local function fillArray(arr, tbl, offset)
        for i, v in ipairs(tbl) do arr[i + (offset or -1)] = v end
    end
    
    --For filling a group of similarly-named variables.
    ---@param prefix string
    ---@param tbl table
    ---@param offset? integer
    local function fillVars(prefix, tbl, offset)
        for i, v in ipairs(tbl) do _G[prefix .. v] = i + (offset or -1) end
    end
    
    local list
    if _USE_GUI then
        udg_DamageTypeDebugStr[0]   = "UNKNOWN"
        udg_DamageTypeDebugStr[4]   = "NORMAL"
        udg_DamageTypeDebugStr[5]   = "ENHANCED"
        udg_DAMAGE_TYPE_UNKNOWN     = 0
        udg_DAMAGE_TYPE_NORMAL      = 4
        udg_DAMAGE_TYPE_ENHANCED    = 5
    end
    damagesImmune[0]            = true
    damagesImmune[4]            = true
    damagesImmune[5]            = true
    fillArray(damagesImmune, {false,  false,    false,      true,     true,     false,    false,   false,   true,   false,   false,   false,  false,     false,        true,          true,          false,          false,        true}, 7)
    if _USE_GUI then
        list =               {"FIRE", "COLD", "LIGHTNING", "POISON", "DISEASE", "DIVINE", "MAGIC", "SONIC", "ACID", "FORCE", "DEATH", "MIND", "PLANT", "DEFENSIVE", "DEMOLITION", "SLOW_POISON", "SPIRIT_LINK", "SHADOW_STRIKE", "UNIVERSAL"}
        fillArray(udg_DamageTypeDebugStr, list, 7)
        fillVars("udg_DAMAGE_TYPE_", list, 7)
    end
    fillArray(attacksImmune, { false,    true,      true,    true,    false,   true,    true})
    if _USE_GUI then
        list               = {"SPELLS", "NORMAL", "PIERCE", "SIEGE", "MAGIC", "CHAOS", "HERO"}
        fillArray(udg_AttackTypeDebugStr, list)
        fillVars("udg_ATTACK_TYPE_", list)
        
        fillArray(udg_WeaponTypeDebugStr, {"NONE", "METAL_LIGHT_CHOP", "METAL_MEDIUM_CHOP", "METAL_HEAVY_CHOP", "METAL_LIGHT_SLICE", "METAL_MEDIUM_SLICE", "METAL_HEAVY_SLICE", "METAL_MEDIUM_BASH", "METAL_HEAVY_BASH", "METAL_MEDIUM_STAB", "METAL_HEAVY_STAB", "WOOD_LIGHT_SLICE", "WOOD_MEDIUM_SLICE", "WOOD_HEAVY_SLICE", "WOOD_LIGHT_BASH", "WOOD_MEDIUM_BASH", "WOOD_HEAVY_BASH", "WOOD_LIGHT_STAB", "WOOD_MEDIUM_STAB", "CLAW_LIGHT_SLICE", "CLAW_MEDIUM_SLICE", "CLAW_HEAVY_SLICE", "AXE_MEDIUM_CHOP", "ROCK_HEAVY_BASH"})
        fillVars("udg_WEAPON_TYPE_",      {"NONE",     "ML_CHOP",           "MM_CHOP",           "MH_CHOP",          "ML_SLICE",           "MM_SLICE",           "MH_SLICE",          "MM_BASH",          "MH_BASH",          "MM_STAB",          "MH_STAB",          "WL_SLICE",          "WM_SLICE",         "WH_SLICE",         "WL_BASH",          "WM_BASH",         "WH_BASH",         "WL_STAB",         "WM_STAB",          "CL_SLICE",          "CM_SLICE",          "CH_SLICE",         "AM_CHOP",         "RH_BASH"})
        
        list = {"LIGHT", "MEDIUM", "HEAVY", "FORTIFIED", "NORMAL", "HERO", "DIVINE", "UNARMORED"}
        fillArray(udg_DefenseTypeDebugStr, list)
        fillVars("udg_DEFENSE_TYPE_", list)
        
        list = {"NONE", "FLESH", "METAL", "WOOD", "ETHEREAL", "STONE"}
        fillArray(udg_ArmorTypeDebugStr, list)
        fillVars("udg_ARMOR_TYPE_", list)
        
        fillVars("udg_UNIT_CLASS_", {"HERO", "DEAD", "STRUCTURE", "FLYING", "GROUND", "ATTACKS_FLYING", "ATTACKS_GROUND", "MELEE", "RANGED", "GIANT", "SUMMONED", "STUNNED", "PLAGUED", "SNARED", "UNDEAD", "MECHANICAL", "PEON", "SAPPER", "TOWNHALL", "ANCIENT", "TAUREN", "POISONED", "POLYMORPHED", "SLEEPING", "RESISTANT", "ETHEREAL", "MAGIC_IMMUNE"})
        
        for i = 0, 6 do udg_CONVERTED_ATTACK_TYPE[i] = ConvertAttackType(i) end
    end
    
    ---Apply damage directly via Damage Engine
    ---@param src unit
    ---@param tgt unit
    ---@param amt real
    ---@param a boolean
    ---@param r boolean
    ---@param at attacktype
    ---@param dt damagetype
    ---@param wt weapontype
    ---@return damageInstance
    function Damage.apply(src, tgt, amt, a, r, at, dt, wt)
        local d ---@type damageInstance
        if dreaming then
            d = create(src, tgt, amt, a, r, at, dt, wt, true)
            addRecursive(d)
        else
            UDT(src, tgt, amt, a, r, at, dt, wt)
            d = current
            finish()
        end
        return d
    end
    ---Deal spell damage using the below simple criteria
    ---@param src unit
    ---@param tgt unit
    ---@param amt real
    ---@param dt damagetype
    ---@return damageInstance
    function Damage.applySpell(src,  tgt,  amt, dt)
        return Damage.apply(src, tgt, amt, nil, nil, nil, dt, nil)
    end
    function Damage.applyAttack(src, tgt, amt, ranged, at, wt)
        return Damage.apply(src, tgt, amt, true, ranged, at, DAMAGE_TYPE_NORMAL, wt)
    end
    
--[[--------------------------------------------------------------------------------------
    The below section defines how GUI interacts with Damage Engine and vice-versa. This is
a breakthrough in coding thanks to the innovation brought forth via Global Variable Remapper.
----------------------------------------------------------------------------------------]]
    
    if _USE_GUI then
        ---Remap damageInstance types of variables (DamageEventSource/Target/Amount/etc)
        ---@param oldVarStr string
        ---@param newVarStr string
        ---@param get? boolean
        ---@param set? boolean
        local function map(oldVarStr, newVarStr, get, set)
            GlobalRemap(oldVarStr, get and function() return current[newVarStr] end, set and function(val) current[newVarStr] = val end)
        end
        map("udg_DamageEventAmount", "damage", true, true)
        map("udg_DamageEventType", "userType", true, true)
        if _USE_ARMOR_MOD then
            map("udg_DamageEventArmorPierced", "armorPierced", true, true)
            map("udg_DamageEventArmorT", "armorType", true, true)
            map("udg_DamageEventDefenseT", "defenseType", true, true)
        end
        map("udg_DamageEventSource", "source", true)
        map("udg_DamageEventTarget", "target", true)
        map("udg_DamageEventPrevAmt", "prevAmt", true)
        map("udg_DamageEventUserAmt", "userAmt", true)
        map("udg_IsDamageAttack", "isAttack", true)
        map("udg_IsDamageCode", "isCode", true)
        map("udg_IsDamageSpell", "isSpell", true)
        if _USE_MELEE_RANGE then 
            map("udg_IsDamageMelee", "isMelee", true)
            map("udg_IsDamageRanged", "isRanged", true)
        end
        GlobalRemap("udg_DamageEventAOE", function() return sourceAOE end)
        GlobalRemap("udg_DamageEventLevel", function() return sourceStacks end)
        GlobalRemap("udg_AOEDamageSource", function() return originalSource end)
        GlobalRemap("udg_EnhancedDamageTarget", function() return originalTarget end)
        
        GlobalRemap("udg_LethalDamageHP", function() return Damage.life end, function(var) Damage.life = var end)
        
        GlobalRemap("udg_DamageEventAttackT", function() return GetHandleId(current.attackType) end, function(var) current.attackType  = ConvertAttackType(var) end)
        GlobalRemap("udg_DamageEventDamageT", function() return GetHandleId(current.damageType) end, function(var) current.damageType  = ConvertDamageType(var) end)
        GlobalRemap("udg_DamageEventWeaponT", function() return GetHandleId(current.weaponType) end, function(var) current.weaponType  = ConvertWeaponType(var) end)
        
        --New GUI vars unique to version 2.0: boolean DamageEngineEnabled, boolean DamageFilterConfigured, real DamageEventUserAmt
        
        GlobalRemap("udg_DamageEngineEnabled", nil, function(val) Damage.enable(val) end)
        GlobalRemap("udg_NextDamageType", nil, function(val) Damage.nextType = val end)
        GlobalRemap("udg_RemoveDamageEvent", nil, function() Damage.remove(userIndex) end)
        GlobalRemap("udg_DamageFilterSourceC", nil, function(val) current.sourceClass = ConvertUnitType(val) end)
        GlobalRemap("udg_DamageFilterTargetC", nil, function(val) current.targetClass = ConvertUnitType(val) end)
        
        ---Remap damageEventRegistry type variables (DamageFilterSource/Target/MinAmount/etc)
        ---@param oldVarStr string
        ---@param newVarStr string
        local function configVar(oldVarStr, newVarStr)
            GlobalRemap(oldVarStr, nil,
            function(val)
                userIndex[newVarStr] = val
            end)
        end
        configVar("udg_DamageFilterSource", "source")
        configVar("udg_DamageFilterTarget", "target")
        configVar("udg_DamageFilterSourceT", "sourceType")
        configVar("udg_DamageFilterTargetT", "targetType")
        configVar("udg_DamageFilterType", "userType")
        configVar("udg_DamageFilterAttackT", "attackType")
        configVar("udg_DamageFilterDamageT", "damageType")
        configVar("udg_DamageFilterSourceI", "sourceItem")
        configVar("udg_DamageFilterTargetI", "targetItem")
        configVar("udg_DamageFilterMinAmount", "damageMin")
        configVar("udg_DamageFilterSourceA", "sourceBuff")
        configVar("udg_DamageFilterSourceB", "sourceBuff")
        configVar("udg_DamageFilterTargetA", "targetBuff")
        configVar("udg_DamageFilterTargetB", "targetBuff")
        configVar("udg_DamageFilterFailChance", "failChance")
        
        GlobalRemap("udg_DamageFilterRunChance", nil,
        function(val)
            userIndex.failChance = 1.00 - val
        end)
        GlobalRemap("udg_DamageFilterConfigured",
        function()
            local c = userIndex.configured
            if not c then
                userIndex.configured = 0
                return false
            elseif c == 0 then
                userIndex.configured = 1
                return checkConfig()
            end
            return true
        end)
        
--[[--------------------------------------------------------------------------------------
    Set references to readonly variables for public use.
----------------------------------------------------------------------------------------]]
        
        setmetatable(Damage, {
            __index =
            function(tbl, key)
                local index = readonly[key]
                if index then return index() end
                return rawget(tbl, key)
            end,
            
            __newindex =
            function(tbl, key, val)
                if readonly[key] then return end
                rawset(tbl, key, val)
            end
        })
    end
end)
end