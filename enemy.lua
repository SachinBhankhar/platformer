local Enemy = {}
Enemy.__index = Enemy

local SPEED         = 35
local GRAVITY       = 1200
local STOMP_KILL_VY = -350

function Enemy.new(world, tx, ty)
    local T = world.tileSize
    local self = setmetatable({}, Enemy)
    self.world     = world
    self.x         = (tx - 1) * T + 4
    self.y         = (ty - 1) * T
    self.w         = 24
    self.h         = 24
    self.vx        = -SPEED
    self.vy        = 0
    self.dead      = false
    self.deadTimer = 0
    return self
end

-- players is a list of player objects
function Enemy:update(dt, players)
    if self.dead then
        self.deadTimer = self.deadTimer + dt
        return self.deadTimer < 0.4
    end

    self.vy = self.vy + GRAVITY * dt

    local nx, ny, nvx, nvy, ground =
        self.world:move(self.x, self.y, self.w, self.h, self.vx * dt, self.vy * dt)
    self.x  = nx;  self.y  = ny
    self.vy = nvy / dt

    if nvx == 0 then self.vx = -self.vx end

    if ground then
        self.vy = 0
        local T = self.world.tileSize
        local frontX  = self.vx > 0 and (self.x + self.w + 1) or (self.x - 1)
        local belowTX = math.floor(frontX / T) + 1
        local belowTY = math.floor((self.y + self.h + 1) / T) + 1
        if not self.world:isSolid(belowTX, belowTY) then
            self.vx = -self.vx
        end
    end

    -- Check all players
    for _, player in ipairs(players) do
        if not player.dead and not player.won and not player.eliminated then
            if self:overlaps(player) then
                local playerFeet = player.y + player.h
                local enemyMid   = self.y + self.h / 2
                if player.vy > 0 and playerFeet <= enemyMid + 10 then
                    self.dead = true
                    player.vy = STOMP_KILL_VY
                    player.coins = player.coins + 1
                    return true
                else
                    player:die()
                end
            end
        end
    end

    return true
end

function Enemy:overlaps(obj)
    return self.x < obj.x + obj.w and
           self.x + self.w > obj.x and
           self.y < obj.y + obj.h and
           self.y + self.h > obj.y
end

function Enemy:draw(camX, camY)
    local px = self.x - camX
    local py = self.y - camY

    if self.dead then
        love.graphics.setColor(0.6, 0.3, 0.0, 1 - self.deadTimer / 0.4)
        love.graphics.rectangle("fill", px, py + self.h - 8, self.w, 8)
        return
    end

    love.graphics.setColor(0.6, 0.3, 0.0)
    love.graphics.ellipse("fill", px + self.w/2, py + self.h/2 + 4, self.w/2, self.h/2 - 2)

    love.graphics.setColor(1, 1, 1)
    love.graphics.circle("fill", px + 6,  py + self.h/2 - 2, 4)
    love.graphics.circle("fill", px + 18, py + self.h/2 - 2, 4)
    love.graphics.setColor(0, 0, 0)
    love.graphics.circle("fill", px + 7,  py + self.h/2 - 2, 2)
    love.graphics.circle("fill", px + 17, py + self.h/2 - 2, 2)

    love.graphics.setColor(0.4, 0.2, 0.0)
    love.graphics.ellipse("fill", px + 6,  py + self.h - 1, 6, 4)
    love.graphics.ellipse("fill", px + 18, py + self.h - 1, 6, 4)
end

return Enemy
