if Timed then --https://www.hiveworkshop.com/threads/timed-call-and-echo.339222/

-- Arcing Text Tag Lua v1.0, created by Maker, converted by Bribe, features requested by Ugabunda and Kusanagi Kuro
-- 
--   public static ArcingTextTag lastCreated
--   - Get the last created ArcingTextTag
--   public real scaling
--   - Set the size ratio of the texttag - 1.00 is the default
--   public real timeScaling
--   - Set the duration ratio of the texttag - 1.00 is the default
OnGlobalInit(1, function() ArcingTextTag = {}

    local SIZE_MIN        = 0.018         ---@type real     -- Minimum size of text
    local SIZE_BONUS      = 0.012         ---@type real     -- Text size increase
    local TIME_LIFE       = 1.0           ---@type real     -- How long the text lasts
    local TIME_FADE       = 0.8           ---@type real     -- When does the text start to fade
    local Z_OFFSET        = 50            ---@type real     -- Height above unit
    local Z_OFFSET_BON    = 50            ---@type real     -- How much extra height the text gains
    local VELOCITY        = 2             ---@type real     -- How fast the text moves in x/y plane
    local ANGLE           = bj_PI/2       ---@type real     -- Movement angle of the tex                                    -- ANGLE_RND is true
    local ANGLE_RND       = true          ---@type boolean  -- Is the angle random or fixed
    
    ArcingTextTag.lastCreated = nil       ---@type texttag
    
    ---ArcingTextTag.createEx
    ---@param s string
    ---@param u unit
    ---@param duration real
    ---@param size real
    ---@param p real
    ---@return texttag
    function ArcingTextTag.createEx(s, u, duration, size, p)
        local a = ANGLE_RND and GetRandomReal(0, 2*bj_PI) or ANGLE
        
        local scale = size
        local timeScale = RMaxBJ(duration, 0.001)
        
        local x = GetUnitX(u)
        local y = GetUnitY(u)
        local t = TIME_LIFE*timeScale
        local as = Sin(a)*VELOCITY
        local ac = Cos(a)*VELOCITY
        
        local tt
        if IsUnitVisible(u, p) then
            tt = CreateTextTag()
            SetTextTagPermanent(tt, false)
            SetTextTagLifespan(tt, t)
            SetTextTagFadepoint(tt, TIME_FADE*timeScale)
            SetTextTagText(tt, s, SIZE_MIN*size)
            SetTextTagPos(tt, x, y, Z_OFFSET)
        end
        
        Timed.echo(function(node)
            if tt then
                p = Sin(bj_PI*((t - node.elapsed) / timeScale))
                x = x + ac
                y = y + as
                SetTextTagPos(tt, x, y, Z_OFFSET + Z_OFFSET_BON*p)
                SetTextTagText(tt, s, (SIZE_MIN + SIZE_BONUS*p)*scale)
            end
            return node.elapsed >= t
        end)
        
        ArcingTextTag.lastCreated = tt
        
        return tt
    end

    ---ArcingTextTag.create
    ---@param s string
    ---@param u unit
    ---@return texttag
    function ArcingTextTag.create(s, u)
        return ArcingTextTag.createEx(s, u, TIME_LIFE, 1, GetLocalPlayer())
    end
end)

end