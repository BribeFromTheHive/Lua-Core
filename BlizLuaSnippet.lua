function __jarray(default)
    return setmetatable({}, {
        __index = function()
            return default
        end
    })
end

function math.randomseed(seed)
    return SetRandomSeed(seed // 1)
end
function math.random(m, n)
    if m and n then
        return GetRandomInt(m // 1, n // 1)
    elseif m then
        return GetRandomInt(1, m // 1)
    else
        return GetRandomReal(0.0, 1.0)
    end
end
if DisplayTextToPlayer then
    function print(...)
        local sb = {}
        for i = 1, select('#', ...) do
            sb[i] = tostring(select(i, ...))
        end
        DisplayTextToPlayer(GetLocalPlayer(), 0, 0, table.concat(sb, '    '))
    end
end

function FourCC(id)
    return 0x1000000 * string.byte(id:sub(1,1)) +
             0x10000 * string.byte(id:sub(2,2)) +
               0x100 * string.byte(id:sub(3,3)) +
                       string.byte(id:sub(4,4))
end