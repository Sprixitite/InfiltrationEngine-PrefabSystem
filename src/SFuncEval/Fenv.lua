local Fenv = {}

function Fenv.new(funcs)
    local i = 0
    return setmetatable(
        {},
        {
            __index = function(tbl, k)
                i = i + 1
                if i == 2 then return funcs[k] end
                return k
            end,
        }
    )
end

return Fenv