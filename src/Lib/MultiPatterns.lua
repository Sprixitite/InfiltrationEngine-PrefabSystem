--[[
    MultiPatterns // Pattern branches for Lua

    © Sprixitite, 2026
]]

local MultiPatterns = {}
MultiPatterns.__index = MultiPatterns

local function toMultiFragments(pat)
    local ESCAPING = false

    local TOK_SKIP = 0
    local SCOPE_LVL = 0

    local toks = {}
    local scope = toks

    local tok = ""

    local scope_push = function(capture)
        local new = { Parent = scope }
        scope[#scope+1] = new
        scope = new
        SCOPE_LVL = SCOPE_LVL + 1
    end

    local scope_pop = function()
        if SCOPE_LVL < 1 then
            error("Malformed MultiPattern! Attempted to close top-level scope with '>'!")
        end
        local old = scope
        scope = old.Parent
        old.Parent = nil

        local oldSize = #old
        if oldSize == 1 then
            scope[#scope] = old[1]
        end

        SCOPE_LVL = SCOPE_LVL - 1
    end

    local tok_end = function()
        if tok == "" then return end
        scope[#scope+1] = tok
        tok = ""
    end

    for i=1, #pat do
        TOK_SKIP = TOK_SKIP - 1

        local c = string.sub(pat, i  , i  )

        if c == '%' and not ESCAPING then
            ESCAPING = true
        elseif c == '<' and not ESCAPING then
            tok_end()
            scope_push()
            TOK_SKIP = 1
        elseif c == '>' and SCOPE_LVL > 0 and not ESCAPING then
            tok_end()
            scope_pop()
            TOK_SKIP = 1
        elseif c == '|' and SCOPE_LVL > 0 and not ESCAPING then
            tok_end()
            TOK_SKIP = 1
        else
            ESCAPING = false
        end

        if TOK_SKIP < 1 then
            tok = tok .. c
        end

        if i == #pat then
            if SCOPE_LVL > 0 then
                error("Incomplete MultiPattern - expected '>'x" .. i .. " but found end of string!")
            end
            tok_end()
        end
    end

    return toks	
end

local function toObjects(fragments)
    for i, fragment in ipairs(fragments) do
        if type(fragment) == "table" then
            fragments[i] = toObjects(fragment)
        end
    end

    return { _Fragments = fragments }
end

function MultiPatterns.new(pattern)
    return setmetatable(
        toObjects(toMultiFragments(pattern)),
        MultiPatterns
    )
end

function MultiPatterns.concat(...)
    local n = select('#', ...)
    local varargs = { ... }
    if n == 0 then return nil end
    if n == 1 then return MultiPatterns.new(varargs[1]) end

    local str = "<"
    for i=1, n do
        str = str .. tostring(varargs[i])
        if i ~= n then str = str .. '|' end
    end
    str = str .. '>'

    return MultiPatterns.new(str)
end

local function try_str_match_and_capture(str, pat, init)
    local i, j, cap1 = string.find(str, pat, init)
    if i == nil then
        return false, nil, nil, nil
    end

    local match = string.sub(str, i, j)
    if cap1 == nil then
        return true, j, match, {}
    end

    return true, j, match, { string.match(str, pat, init) }
end

local function match_or(self, str, cursor)
    for _, pat in ipairs(self._Fragments) do
        local patT = type(pat)
        if patT == "table" then
            local success, newCursor, match, captures = match_or(pat, str, cursor)
            if success then
                return true, newCursor, match, captures
            end
        elseif patT == "string" then
            local success, newCursor, match, captures = try_str_match_and_capture(str, pat, cursor)
            if success then
                return true, newCursor, match, captures
            end
        else
            error("Internal error in MultiPatterns! Match fragment was not table or string!")
        end
    end

    return false, nil, nil, nil
end

local function match_sequence(self, str, cursor)
    local seq_match = ""
    local captures = {}

    local add_captures = function(tbl)
        local n = #captures
        for i=1, #tbl do
            captures[n+i] = tbl[i]
        end
    end

    for _, pat in ipairs(self._Fragments) do
        local patT = type(pat)
        local fragmentMatched = false
        if patT == "table" then
            local success, newCursor, match, captures = match_or(pat, str, cursor)

            if success then
                fragmentMatched = true
                cursor = newCursor
                seq_match = seq_match .. match
                add_captures(captures)
            end

        elseif patT == "string" then
            local success, newCursor, match, captures = try_str_match_and_capture(str, pat, cursor)

            if success then
                fragmentMatched = true
                cursor = newCursor
                seq_match = seq_match .. match
                add_captures(captures)
            end
        else
            error("Internal error in MultiPatterns! Match fragment was not table or string!")
        end

        if not fragmentMatched then
            return false, nil, nil
        end
    end

    return true, seq_match, captures
end

function MultiPatterns.match(self, str, want_match, want_captures)
    local want_stdlike = not (want_match or want_captures)
    local want_all     = (want_match and want_captures)

    local success, match, captures = match_sequence(self, str, 1)

    if not success then return nil end

    if want_all then return match, unpack(captures) end
    if want_stdlike then
        if #captures > 0 then return unpack(captures) end
        return match
    end

    if want_match then
        return match
    elseif want_captures then
        return unpack(captures)
    end
end

return MultiPatterns