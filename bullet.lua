local Bullet = {}
Bullet.__index = Bullet

local SPEED = 600
local LIFE  = 0.8
local W, H  = 6, 4

function Bullet.new(x, y, dir, ownerId)
    local self = setmetatable({}, Bullet)
    self.x = x
    self.y = y
    self.w = W
    self.h = H
    self.vx = dir * SPEED
    self.life = LIFE
    self.ownerId = ownerId or 0
    return self
end

-- Returns true if the bullet should stay alive.
function Bullet:update(dt, world, enemies)
    self.life = self.life - dt
    if self.life <= 0 then return false end

    self.x = self.x + self.vx * dt

    -- Tile collision: die on solid.
    local T = world.tileSize
    local probeX = self.vx > 0 and (self.x + self.w) or self.x
    local tx = math.floor(probeX / T) + 1
    local ty = math.floor((self.y + self.h/2) / T) + 1
    if world:isSolid(tx, ty) then return false end

    -- Enemy hit.
    for _, e in ipairs(enemies) do
        if not e.dead and
           self.x < e.x + e.w and self.x + self.w > e.x and
           self.y < e.y + e.h and self.y + self.h > e.y then
            e.dead = true
            e.deadTimer = 0
            return false
        end
    end

    return true
end

function Bullet:draw(camX, camY)
    love.graphics.setColor(1, 0.95, 0.3)
    love.graphics.rectangle("fill", self.x - camX, self.y - camY, self.w, self.h)
    love.graphics.setColor(1, 0.7, 0, 0.5)
    love.graphics.rectangle("fill",
        self.x - camX - (self.vx > 0 and 4 or -self.w),
        self.y - camY + 1, 4, self.h - 2)
end

return Bullet
