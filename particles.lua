-- Lightweight particle system for coin collect / death sparks
local Particles = {}
Particles.__index = Particles

function Particles.new()
    local self = setmetatable({}, Particles)
    self.pool = {}
    return self
end

function Particles:spawn(x, y, color, count, speed)
    for _ = 1, count do
        local angle = math.random() * math.pi * 2
        local s = speed * (0.5 + math.random() * 0.5)
        table.insert(self.pool, {
            x = x, y = y,
            vx = math.cos(angle) * s,
            vy = math.sin(angle) * s - speed * 0.5,
            life = 0.5 + math.random() * 0.3,
            maxLife = 0.8,
            r = color[1], g = color[2], b = color[3],
        })
    end
end

function Particles:update(dt)
    local i = 1
    while i <= #self.pool do
        local p = self.pool[i]
        p.life = p.life - dt
        if p.life <= 0 then
            table.remove(self.pool, i)
        else
            p.x  = p.x  + p.vx * dt
            p.y  = p.y  + p.vy * dt
            p.vy = p.vy + 600 * dt
            i = i + 1
        end
    end
end

function Particles:draw(camX, camY)
    for _, p in ipairs(self.pool) do
        local alpha = math.max(0, p.life / 0.8)
        love.graphics.setColor(p.r, p.g, p.b, alpha)
        love.graphics.rectangle("fill", p.x - camX - 3, p.y - camY - 3, 6, 6)
    end
end

return Particles
