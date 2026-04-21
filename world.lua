local World = {}
World.__index = World

local TILE = 32

local T_EMPTY  = 0
local T_SOLID  = 1
local T_COIN   = 2
local T_GOAL   = 3
local T_SPIKE  = 4

local tileColors = {
    [T_SOLID] = {0.55, 0.35, 0.15},
    [T_COIN]  = {1.0,  0.85, 0.0},
    [T_GOAL]  = {0.0,  0.8,  0.0},
    [T_SPIKE] = {0.8,  0.1,  0.1},
}

function World.new(levelData)
    local self = setmetatable({}, World)
    self.map = {}
    self.tileSize = TILE
    local src = levelData.map
    self.width  = #src[1]
    self.height = #src
    for r = 1, self.height do
        self.map[r] = {}
        for c = 1, self.width do
            self.map[r][c] = src[r][c]
        end
    end
    -- store sky / ground colors from level
    self.skyTop     = levelData.skyTop     or {0.38, 0.6,  0.95}
    self.skyBot     = levelData.skyBot     or {0.55, 0.75, 1.0}
    self.groundColor= levelData.groundColor or {0.55, 0.35, 0.15}
    tileColors[T_SOLID] = self.groundColor
    self.pendingRemovals = {}
    return self
end

function World:isSolid(tx, ty)
    if ty < 1 or ty > self.height or tx < 1 or tx > self.width then
        return ty > self.height
    end
    local t = self.map[ty][tx]
    return t == T_SOLID or t == T_SPIKE
end

function World:getTile(tx, ty)
    if ty < 1 or ty > self.height or tx < 1 or tx > self.width then return T_EMPTY end
    return self.map[ty][tx]
end

function World:setTile(tx, ty, id)
    if ty >= 1 and ty <= self.height and tx >= 1 and tx <= self.width then
        self.map[ty][tx] = id
    end
end

function World:move(x, y, w, h, dx, dy)
    local onGround   = false
    local hitCeiling = false
    local isSpike    = false
    local T = self.tileSize

    x = x + dx
    local x1 = math.floor(x / T) + 1
    local x2 = math.floor((x + w - 1) / T) + 1
    local y1 = math.floor(y / T) + 1
    local y2 = math.floor((y + h - 1) / T) + 1
    for ty = y1, y2 do
        for tx = x1, x2 do
            if self:isSolid(tx, ty) then
                if self:getTile(tx, ty) == T_SPIKE then isSpike = true end
                if dx > 0 then x = (tx - 1) * T - w
                else            x = tx * T end
                dx = 0
                break
            end
        end
    end

    y = y + dy
    x1 = math.floor(x / T) + 1
    x2 = math.floor((x + w - 1) / T) + 1
    y1 = math.floor(y / T) + 1
    y2 = math.floor((y + h - 1) / T) + 1
    for ty = y1, y2 do
        for tx = x1, x2 do
            if self:isSolid(tx, ty) then
                if self:getTile(tx, ty) == T_SPIKE then isSpike = true end
                if dy > 0 then
                    y = (ty - 1) * T - h
                    onGround = true
                else
                    y = ty * T
                    hitCeiling = true
                end
                dy = 0
                break
            end
        end
    end

    x = math.max(0, math.min(x, self.width * T - w))

    return x, y, dx, dy, onGround, hitCeiling, isSpike
end

function World:collectCoin(px, py, w, h)
    local T = self.tileSize
    local x1 = math.floor(px / T) + 1
    local x2 = math.floor((px + w - 1) / T) + 1
    local y1 = math.floor(py / T) + 1
    local y2 = math.floor((py + h - 1) / T) + 1
    local collected = 0
    for ty = y1, y2 do
        for tx = x1, x2 do
            if self:getTile(tx, ty) == T_COIN then
                self:setTile(tx, ty, T_EMPTY)
                collected = collected + 1
                self.pendingRemovals[#self.pendingRemovals+1] = {tx, ty}
            end
        end
    end
    return collected
end

function World:checkGoal(px, py, w, h)
    local T = self.tileSize
    local x1 = math.floor(px / T) + 1
    local x2 = math.floor((px + w - 1) / T) + 1
    local y1 = math.floor(py / T) + 1
    local y2 = math.floor((py + h - 1) / T) + 1
    for ty = y1, y2 do
        for tx = x1, x2 do
            if self:getTile(tx, ty) == T_GOAL then return true end
        end
    end
    return false
end

function World:countCoins()
    local n = 0
    for r = 1, self.height do
        for c = 1, self.width do
            if self.map[r][c] == T_COIN then n = n + 1 end
        end
    end
    return n
end

function World:draw(camX, camY, screenW, screenH)
    local T = self.tileSize
    local c1 = math.max(1, math.floor(camX / T) + 1)
    local c2 = math.min(self.width,  math.ceil((camX + screenW) / T) + 1)
    local r1 = math.max(1, math.floor(camY / T) + 1)
    local r2 = math.min(self.height, math.ceil((camY + screenH) / T) + 1)

    for r = r1, r2 do
        for c = c1, c2 do
            local tid = self.map[r][c]
            if tid ~= T_EMPTY then
                local col = tileColors[tid] or {0.5, 0.5, 0.5}
                love.graphics.setColor(col)
                local px = (c - 1) * T - camX
                local py = (r - 1) * T - camY
                love.graphics.rectangle("fill", px, py, T, T)
                love.graphics.setColor(0, 0, 0, 0.3)
                love.graphics.rectangle("line", px, py, T, T)
                if tid == T_COIN then
                    love.graphics.setColor(1, 1, 1, 0.5)
                    love.graphics.circle("fill", px + T/2, py + T/2, T/5)
                end
                if tid == T_GOAL then
                    love.graphics.setColor(0.0, 0.5, 0.0)
                    love.graphics.rectangle("fill", px + T/2 - 2, py, 4, T)
                    love.graphics.setColor(1, 0.8, 0)
                    love.graphics.polygon("fill",
                        px + T/2 + 2, py,
                        px + T/2 + 14, py + 8,
                        px + T/2 + 2, py + 16)
                end
                if tid == T_SPIKE then
                    love.graphics.setColor(1, 0.2, 0.2)
                    love.graphics.polygon("fill",
                        px + T/2, py,
                        px + T, py + T,
                        px, py + T)
                end
            end
        end
    end
end

World.TILE_SIZE = TILE
World.T_EMPTY   = T_EMPTY
World.T_SOLID   = T_SOLID
World.T_COIN    = T_COIN
World.T_GOAL    = T_GOAL
World.T_SPIKE   = T_SPIKE

return World
