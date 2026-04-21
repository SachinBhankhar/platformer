local Levels = {}

local E, S, C, G, X = 0, 1, 2, 3, 4  -- tile ids

local function solid()
    local r = {} for i=1,50 do r[i]=S end return r
end
local function empty()
    local r = {} for i=1,50 do r[i]=E end
    r[1]=S; r[50]=S  -- border walls
    return r
end
local function span(row, c1, c2, val)
    for c=c1,c2 do row[c]=val end return row
end
local function put(row, c, val) row[c]=val return row end

-- Ground row with optional pit gaps (list of {c1,c2} open columns)
local function ground(gaps)
    local r = solid()
    if gaps then
        for _, g in ipairs(gaps) do
            for c = g[1], g[2] do r[c] = E end
        end
    end
    return r
end

-- ────────────────────────────────────────────────────────────────────────────
-- WORLD 1
-- ────────────────────────────────────────────────────────────────────────────

Levels[1] = {
    name = "World 1-1: Green Hills",
    skyTop = {0.38, 0.6, 0.95},
    skyBot = {0.55, 0.75, 1.0},
    groundColor = {0.3, 0.6, 0.2},
    enemies = {{12,10},{26,10},{38,10}},
    map = (function()
        local r3 = empty(); span(r3, 9,11,C); span(r3,14,16,C); span(r3,22,24,C)
        local r4 = empty(); span(r4, 9,13,S); span(r4,20,24,C); span(r4,28,32,C)
        local r5 = empty(); span(r5,20,25,S)
        local r6 = empty()
        local r7 = empty(); span(r7,5,6,C); span(r7,9,10,C); span(r7,18,19,C); span(r7,29,30,C); span(r7,38,39,C)
        local r8 = empty(); span(r8,4,8,S); span(r8,16,20,S); span(r8,27,31,S)
        local r9 = empty()
        local r10= empty()
        for c=3,47,2 do put(r10,c,C) end
        put(r10,47,G)
        return {solid(),empty(),r3,r4,r5,r6,r7,r8,r9,r10,solid(),solid(),solid()}
    end)(),
}

Levels[2] = {
    name = "World 1-2: Step Up",
    skyTop = {0.38, 0.6, 0.95},
    skyBot = {0.55, 0.75, 1.0},
    groundColor = {0.3, 0.6, 0.2},
    enemies = {{9,10},{22,10},{35,10},{45,10}},
    map = (function()
        local r3 = empty(); span(r3,3,4,C);  span(r3,14,15,C); span(r3,25,26,C); span(r3,36,37,C)
        local r4 = empty(); span(r4,3,6,S);  span(r4,13,17,S); span(r4,24,28,S); span(r4,35,39,S)
        local r5 = empty(); span(r5,8,9,C);  span(r5,19,20,C); span(r5,30,31,C)
        local r6 = empty(); span(r6,7,10,S); span(r6,18,22,S); span(r6,29,33,S)
        local r7 = empty(); span(r7,4,5,C);  span(r7,13,14,C); span(r7,23,24,C); span(r7,33,34,C); span(r7,42,43,C)
        local r8 = empty(); span(r8,3,7,S);  span(r8,12,16,S); span(r8,22,26,S); span(r8,32,36,S); span(r8,41,45,S)
        local r9 = empty()
        local r10= empty(); for c=3,47,3 do put(r10,c,C) end; put(r10,47,G)
        return {solid(),empty(),r3,r4,r5,r6,r7,r8,r9,r10,solid(),solid(),solid()}
    end)(),
}

Levels[3] = {
    name = "World 1-3: Mind the Gap",
    skyTop = {0.35, 0.55, 0.9},
    skyBot = {0.5,  0.7,  1.0},
    groundColor = {0.3, 0.6, 0.2},
    enemies = {{8,10},{19,10},{32,9},{44,10}},
    map = (function()
        local r3 = empty(); span(r3,4,5,C);  span(r3,15,16,C); span(r3,26,27,C); span(r3,37,38,C)
        local r4 = empty(); span(r4,3,7,S);  span(r4,14,18,S); span(r4,25,29,S); span(r4,36,40,S)
        local r5 = empty()
        local r6 = empty(); span(r6,8,9,C);  span(r6,20,21,C); span(r6,31,32,C); span(r6,42,43,C)
        local r7 = empty(); span(r7,7,11,S); span(r7,19,23,S); span(r7,30,34,S); span(r7,41,45,S)
        local r8 = empty()
        local r9 = empty(); span(r9,3,5,C);  span(r9,12,14,C); span(r9,22,24,C); span(r9,32,34,C); span(r9,42,44,C)
        local r10= empty(); for c=3,46,4 do put(r10,c,C) end; put(r10,47,G)
        local r11= ground({{7,10},{18,21},{29,32},{40,43}})
        return {solid(),empty(),r3,r4,r5,r6,r7,r8,r9,r10,r11,solid(),solid()}
    end)(),
}

Levels[4] = {
    name = "World 1-4: Spike Run",
    skyTop = {0.3, 0.5, 0.85},
    skyBot = {0.45, 0.65, 0.95},
    groundColor = {0.35, 0.55, 0.2},
    enemies = {{10,10},{22,8},{36,10},{46,10}},
    map = (function()
        local r3 = empty(); span(r3,5,6,C);  span(r3,13,14,C); span(r3,22,23,C); span(r3,31,32,C); span(r3,40,41,C)
        local r4 = empty(); span(r4,4,8,S);  span(r4,12,16,S); span(r4,21,25,S); span(r4,30,34,S); span(r4,39,43,S)
        local r5 = empty()
        local r6 = empty(); span(r6,8,9,C);  span(r6,19,20,C); span(r6,30,31,C); span(r6,40,41,C)
        local r7 = empty(); span(r7,7,11,S); span(r7,18,22,S); span(r7,29,33,S); span(r7,39,43,S)
        local r8 = empty()
        local r9 = empty(); span(r9,3,4,C);  span(r9,11,12,C); span(r9,20,21,C); span(r9,29,30,C); span(r9,38,39,C); span(r9,46,47,C)
        local r10= empty(); for c=3,46,3 do put(r10,c,C) end; put(r10,47,G)
        local r11= solid()
        span(r11,5,7,X); span(r11,15,17,X); span(r11,25,27,X); span(r11,35,37,X); span(r11,43,45,X)
        return {solid(),empty(),r3,r4,r5,r6,r7,r8,r9,r10,r11,solid(),solid()}
    end)(),
}

-- ────────────────────────────────────────────────────────────────────────────
-- WORLD 2
-- ────────────────────────────────────────────────────────────────────────────

Levels[5] = {
    name = "World 2-1: Sky Land",
    skyTop = {0.5,  0.3,  0.85},
    skyBot = {0.65, 0.45, 1.0},
    groundColor = {0.65, 0.55, 0.25},
    enemies = {{9,9},{22,7},{37,9},{46,11}},
    map = (function()
        local r3 = empty(); span(r3,3,4,C);  span(r3,12,13,C); span(r3,22,23,C); span(r3,32,33,C); span(r3,42,43,C)
        local r4 = empty(); span(r4,2,5,S);  span(r4,11,14,S); span(r4,21,24,S); span(r4,31,34,S); span(r4,41,44,S)
        local r5 = empty(); span(r5,7,8,C);  span(r5,17,18,C); span(r5,27,28,C); span(r5,37,38,C)
        local r6 = empty(); span(r6,6,9,S);  span(r6,16,19,S); span(r6,26,29,S); span(r6,36,39,S)
        local r7 = empty(); span(r7,3,4,C);  span(r7,12,13,C); span(r7,22,23,C); span(r7,33,34,C); span(r7,43,44,C)
        local r8 = empty(); span(r8,2,5,S);  span(r8,11,14,S); span(r8,21,24,S); span(r8,32,35,S); span(r8,42,45,S)
        local r9 = empty(); put(r9,46,C);    put(r9,47,G)
        local r10= empty(); span(r10,44,49,S)
        local r11= ground({{3,6},{9,12},{15,18},{21,24},{27,30},{33,36}})
        return {solid(),empty(),r3,r4,r5,r6,r7,r8,r9,r10,r11,solid(),solid()}
    end)(),
}

Levels[6] = {
    name = "World 2-2: Storm Clouds",
    skyTop = {0.25, 0.25, 0.45},
    skyBot = {0.4,  0.4,  0.6},
    groundColor = {0.5, 0.4, 0.3},
    enemies = {{7,10},{17,8},{28,10},{38,8},{46,10}},
    map = (function()
        local r3 = empty(); span(r3,3,4,C);  span(r3,10,11,C); span(r3,18,19,C); span(r3,26,27,C); span(r3,34,35,C); span(r3,42,43,C)
        local r4 = empty(); span(r4,2,5,S);  span(r4,9,12,S);  span(r4,17,20,S); span(r4,25,28,S); span(r4,33,36,S); span(r4,41,44,S)
        local r5 = empty()
        local r6 = empty(); span(r6,6,7,C);  span(r6,13,14,C); span(r6,21,22,C); span(r6,29,30,C); span(r6,37,38,C)
        local r7 = empty(); span(r7,5,8,S);  span(r7,12,15,S); span(r7,20,23,S); span(r7,28,31,S); span(r7,36,39,S)
        local r8 = empty()
        local r9 = empty(); span(r9,3,4,C);  span(r9,11,12,C); span(r9,19,20,C); span(r9,27,28,C); span(r9,35,36,C); span(r9,45,46,C)
        local r10= empty(); for c=3,46,3 do put(r10,c,C) end; put(r10,47,G)
        local r11= solid()
        span(r11,4,6,X); span(r11,13,15,X); span(r11,22,24,X); span(r11,31,33,X); span(r11,40,42,X)
        return {solid(),empty(),r3,r4,r5,r6,r7,r8,r9,r10,r11,solid(),solid()}
    end)(),
}

Levels[7] = {
    name = "World 2-3: Spike Gauntlet",
    skyTop = {0.15, 0.15, 0.35},
    skyBot = {0.28, 0.28, 0.5},
    groundColor = {0.4, 0.3, 0.2},
    enemies = {{9,8},{20,6},{31,8},{43,6}},
    map = (function()
        local r3 = empty(); span(r3,4,5,C);  span(r3,12,13,C); span(r3,21,22,C); span(r3,30,31,C); span(r3,39,40,C)
        local r4 = empty(); span(r4,3,6,S);  span(r4,11,14,S); span(r4,20,23,S); span(r4,29,32,S); span(r4,38,41,S)
        local r5 = empty()
        local r6 = empty(); span(r6,7,8,C);  span(r6,16,17,C); span(r6,25,26,C); span(r6,34,35,C); span(r6,43,44,C)
        local r7 = empty(); span(r7,6,9,S);  span(r7,15,18,S); span(r7,24,27,S); span(r7,33,36,S); span(r7,42,45,S)
        local r8 = empty()
        local r9 = empty(); span(r9,3,4,C);  span(r9,10,11,C); span(r9,18,19,C); span(r9,26,27,C); span(r9,34,35,C); span(r9,44,45,C)
        local r10= empty(); for c=3,46,2 do put(r10,c,C) end; put(r10,47,G)
        local r11= solid()
        span(r11,3,4,X);  span(r11,9,11,X); span(r11,17,19,X); span(r11,25,27,X); span(r11,33,35,X); span(r11,42,44,X)
        return {solid(),empty(),r3,r4,r5,r6,r7,r8,r9,r10,r11,solid(),solid()}
    end)(),
}

Levels[8] = {
    name = "World 2-4: Final Chaos",
    skyTop = {0.08, 0.08, 0.18},
    skyBot = {0.15, 0.12, 0.28},
    groundColor = {0.38, 0.28, 0.18},
    enemies = {{7,10},{13,8},{20,10},{27,6},{34,10},{40,8},{46,10}},
    map = (function()
        local r3 = empty()
        for c=2,49,2 do put(r3,c,C) end
        local r4 = empty(); span(r4,2,49,S)  -- full ceiling platform with coin row above
        local r5 = empty()
        local r6 = empty(); span(r6,4,5,C);  span(r6,11,12,C); span(r6,18,19,C); span(r6,25,26,C); span(r6,32,33,C); span(r6,39,40,C); span(r6,46,47,C)
        local r7 = empty(); span(r7,3,6,S);  span(r7,10,13,S); span(r7,17,20,S); span(r7,24,27,S); span(r7,31,34,S); span(r7,38,41,S); span(r7,45,48,S)
        local r8 = empty()
        local r9 = empty(); span(r9,6,7,C);  span(r9,14,15,C); span(r9,21,22,C); span(r9,28,29,C); span(r9,35,36,C); span(r9,44,45,C)
        local r10= empty(); for c=3,46,2 do put(r10,c,C) end; put(r10,47,G)
        local r11= solid()
        span(r11,3,4,X); span(r11,8,10,X); span(r11,15,17,X); span(r11,22,24,X); span(r11,29,31,X); span(r11,36,38,X); span(r11,43,45,X)
        return {solid(),empty(),r3,r4,r5,r6,r7,r8,r9,r10,r11,solid(),solid()}
    end)(),
}

return Levels
