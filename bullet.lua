local Bullet = {}
Bullet.__index = Bullet

local SPEED = 600
local LIFE  = 0.8
local W, H  = 6, 4

local FREEZE_SPEED    = 480
local FREEZE_LIFE     = 1.0
local FREEZE_DURATION = 5.0

Bullet.TYPE_NORMAL = 1
Bullet.TYPE_FREEZE = 2

function Bullet.new(x, y, dir, ownerId, btype)
    local self = setmetatable({}, Bullet)
    self.type = btype or Bullet.TYPE_NORMAL
    self.x = x
    self.y = y
    if self.type == Bullet.TYPE_FREEZE then
        self.w = 10
        self.h = 6
        self.vx = dir * FREEZE_SPEED
        self.life = FREEZE_LIFE
    else
        self.w = W
        self.h = H
        self.vx = dir * SPEED
        self.life = LIFE
    end
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
            if self.type == Bullet.TYPE_FREEZE then
                e.frozen = true
                e.frozenTimer = FREEZE_DURATION
            else
                e.dead = true
                e.deadTimer = 0
            end
            return false
        end
    end

    return true
end

function Bullet:draw(camX, camY)
    if self.type == Bullet.TYPE_FREEZE then
        -- Icy shaft: pale blue core + lighter trail.
        love.graphics.setColor(0.7, 0.95, 1.0)
        love.graphics.rectangle("fill", self.x - camX, self.y - camY, self.w, self.h)
        love.graphics.setColor(0.4, 0.8, 1.0, 0.6)
        love.graphics.rectangle("fill",
            self.x - camX - (self.vx > 0 and 6 or -self.w),
            self.y - camY + 1, 6, self.h - 2)
    else
        love.graphics.setColor(1, 0.95, 0.3)
        love.graphics.rectangle("fill", self.x - camX, self.y - camY, self.w, self.h)
        love.graphics.setColor(1, 0.7, 0, 0.5)
        love.graphics.rectangle("fill",
            self.x - camX - (self.vx > 0 and 4 or -self.w),
            self.y - camY + 1, 4, self.h - 2)
    end
end

return Bullet
