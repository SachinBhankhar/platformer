local Camera = {}
Camera.__index = Camera

function Camera.new(world)
    local self = setmetatable({}, Camera)
    self.x     = 0
    self.y     = 0
    self.world = world
    return self
end

-- Follow the midpoint of all active (non-eliminated) players
function Camera:follow(players, screenW, screenH)
    local T    = self.world.tileSize
    local maxX = self.world.width  * T - screenW
    local maxY = self.world.height * T - screenH

    local sumX, sumY, count = 0, 0, 0
    for _, p in ipairs(players) do
        if not p.eliminated then
            sumX  = sumX + p.x + p.w / 2
            sumY  = sumY + p.y + p.h / 2
            count = count + 1
        end
    end

    if count == 0 then return end

    local midX = sumX / count
    local midY = sumY / count

    local targetX = midX - screenW * 0.45
    local targetY = midY - screenH * 0.5

    self.x = self.x + (targetX - self.x) * 0.12
    self.y = self.y + (targetY - self.y) * 0.10

    self.x = math.max(0, math.min(self.x, maxX))
    self.y = math.max(0, math.min(self.y, maxY))
end

return Camera
