local Player = {}
Player.__index = Player

local WALK_SPEED    = 180
local RUN_SPEED     = 300
local ACCEL         = 1000
local FRICTION      = 1000
local JUMP_FORCE    = -480
local GRAVITY_UP    = 800
local GRAVITY_DOWN  = 1200
local COYOTE_FRAMES = 8
local JUMP_BUFFER   = 8
local STOMP_VY      = -350
local MAX_LIVES     = 3

-- Distinct colors for up to 8 players
local PLAYER_COLORS = {
    {0.9, 0.1, 0.1},   -- 1 red
    {0.1, 0.4, 0.9},   -- 2 blue
    {0.1, 0.8, 0.2},   -- 3 green
    {0.9, 0.7, 0.0},   -- 4 yellow
    {0.8, 0.1, 0.8},   -- 5 magenta
    {0.0, 0.8, 0.8},   -- 6 cyan
    {1.0, 0.5, 0.0},   -- 7 orange
    {0.5, 0.0, 0.9},   -- 8 purple
}

function Player.new(world, id)
    local T = world.tileSize
    local self = setmetatable({}, Player)
    self.world  = world
    self.id     = id or 1
    self.level  = 1
    self.bannerTimer = 0  -- shows "Level N" overlay briefly after advancing
    self.color  = PLAYER_COLORS[((id or 1) - 1) % #PLAYER_COLORS + 1]
    self.x      = (1 + (id or 1)) * T
    self.y      = 9 * T
    self.w      = 22
    self.h      = 28
    self.vx     = 0
    self.vy     = 0
    self.facing = 1
    self.onGround     = false
    self.coyoteTimer  = 0
    self.jumpBuffer   = 0
    self.coins        = 0
    self.lives        = MAX_LIVES
    self.dead         = false
    self.eliminated   = false
    self.won          = false
    self.respawnTimer = 0
    self.startX = self.x
    self.startY = self.y
    self.walkTimer = 0
    self.walkFrame = 0
    -- Spawn protection: shared-world levels may already have enemies patrolling
    -- when a new player drops in, so give everyone a grace period.
    self.invTimer  = 2.5
    -- input state (filled by local keyboard or network)
    self.input = {left=false, right=false, jump=false, run=false, jumpPressed=false,
                  fire=false, firePressed=false}
    self._prevJump = false
    self._prevFire = false
    self.fireCooldown = 0
    self._pendingShot = false  -- set by update; consumed by main to spawn bullet
    return self
end

function Player:readLocalKeys()
    local keys = love.keyboard
    local inp = self.input
    inp.left  = keys.isDown("left")  or keys.isDown("a")
    inp.right = keys.isDown("right") or keys.isDown("d")
    inp.run   = keys.isDown("lshift") or keys.isDown("rshift")
    inp.jump  = keys.isDown("space") or keys.isDown("up") or keys.isDown("w")
    inp.jumpPressed = inp.jump and not self._prevJump
    self._prevJump = inp.jump
    inp.fire = keys.isDown("lctrl") or keys.isDown("rctrl") or keys.isDown("f")
    inp.firePressed = inp.fire and not self._prevFire
    self._prevFire = inp.fire
end

-- Movement-only update used by the client for local prediction.
-- No coin collection or goal detection — host is authoritative for those.
function Player:updateMovement(dt)
    if self.eliminated then return end

    if self.dead then
        self.respawnTimer = self.respawnTimer - dt
        self.vy = self.vy + GRAVITY_DOWN * dt
        self.y  = self.y + self.vy * dt
        if self.respawnTimer <= 0 then
            self:respawn()
        end
        return
    end

    if self.invTimer > 0 then self.invTimer = self.invTimer - dt end
    if self.fireCooldown > 0 then self.fireCooldown = self.fireCooldown - dt end

    local inp = self.input
    -- Locally predict the firing cooldown so the muzzle flash & kick render
    -- on the client at the moment of input. Host remains authoritative for
    -- bullet spawning.
    if inp.firePressed and self.fireCooldown <= 0 then
        self.fireCooldown = 0.25
    end
    local topSpeed = inp.run and RUN_SPEED or WALK_SPEED
    local moving = false
    if inp.left then
        self.vx = self.vx - ACCEL * dt
        if self.vx < -topSpeed then self.vx = -topSpeed end
        self.facing = -1
        moving = true
    elseif inp.right then
        self.vx = self.vx + ACCEL * dt
        if self.vx > topSpeed then self.vx = topSpeed end
        self.facing = 1
        moving = true
    end
    if not moving then
        local sign = self.vx > 0 and 1 or -1
        self.vx = self.vx - sign * math.min(FRICTION * dt, math.abs(self.vx))
    end

    local grav = (self.vy < 0) and GRAVITY_UP or GRAVITY_DOWN
    self.vy = self.vy + grav * dt
    if not inp.jump and self.vy < -150 then
        self.vy = self.vy + GRAVITY_UP * 2 * dt
    end

    self.jumpBuffer  = math.max(0, self.jumpBuffer  - 1)
    self.coyoteTimer = math.max(0, self.coyoteTimer - 1)
    if inp.jumpPressed and self.coyoteTimer > 0 then
        self.vy = JUMP_FORCE; self.coyoteTimer = 0; self.jumpBuffer = 0
    elseif inp.jumpPressed then
        self.jumpBuffer = JUMP_BUFFER
    end
    if self.jumpBuffer > 0 and self.coyoteTimer > 0 then
        self.vy = JUMP_FORCE; self.coyoteTimer = 0; self.jumpBuffer = 0
    end
    inp.jumpPressed = false  -- consume the edge; latch fills it again on next press

    local nx, ny, nvx, nvy, ground, ceiling, spike =
        self.world:move(self.x, self.y, self.w, self.h, self.vx * dt, self.vy * dt)
    self.x = nx; self.y = ny
    self.vx = nvx / dt; self.vy = nvy / dt
    if ceiling then self.vy = math.max(0, self.vy) end
    if ground then self.vy = 0; self.coyoteTimer = COYOTE_FRAMES end
    self.onGround = ground

    -- Do NOT call die() here — host owns `lives` and `dead`. If the client
    -- hits a spike or falls, the host will see it too and broadcast dead=true;
    -- applyNetworkState will then flip our state and snap position.

    if moving and self.onGround then
        self.walkTimer = self.walkTimer + dt
        if self.walkTimer > 0.12 then
            self.walkTimer = 0
            self.walkFrame = (self.walkFrame + 1) % 2
        end
    else
        self.walkFrame = 0
        self.walkTimer = 0
    end
end

function Player:update(dt)
    if self.eliminated then return end

    if self.dead then
        self.respawnTimer = self.respawnTimer - dt
        -- still apply gravity/movement so the death bounce looks right
        self.vy = self.vy + GRAVITY_DOWN * dt
        self.y  = self.y + self.vy * dt
        if self.respawnTimer <= 0 then
            self:respawn()
        end
        return
    end

    if self.invTimer > 0 then self.invTimer = self.invTimer - dt end
    if self.fireCooldown > 0 then self.fireCooldown = self.fireCooldown - dt end

    local inp = self.input

    -- Fire a bullet (host-authoritative: main loop consumes _pendingShot).
    if inp.firePressed and self.fireCooldown <= 0 then
        self._pendingShot = true
        self.fireCooldown = 0.25
    end
    inp.firePressed = false

    -- Horizontal
    local topSpeed = inp.run and RUN_SPEED or WALK_SPEED
    local moving = false
    if inp.left then
        self.vx = self.vx - ACCEL * dt
        if self.vx < -topSpeed then self.vx = -topSpeed end
        self.facing = -1
        moving = true
    elseif inp.right then
        self.vx = self.vx + ACCEL * dt
        if self.vx > topSpeed then self.vx = topSpeed end
        self.facing = 1
        moving = true
    end

    if not moving then
        local sign = self.vx > 0 and 1 or -1
        self.vx = self.vx - sign * math.min(FRICTION * dt, math.abs(self.vx))
    end

    -- Gravity
    local grav = (self.vy < 0) and GRAVITY_UP or GRAVITY_DOWN
    self.vy = self.vy + grav * dt

    -- Variable jump
    if not inp.jump then
        if self.vy < -150 then
            self.vy = self.vy + GRAVITY_UP * 2 * dt
        end
    end

    -- Timers
    self.jumpBuffer  = math.max(0, self.jumpBuffer  - 1)
    self.coyoteTimer = math.max(0, self.coyoteTimer - 1)

    -- Jump trigger
    if inp.jumpPressed and self.coyoteTimer > 0 then
        self.vy = JUMP_FORCE
        self.coyoteTimer = 0
        self.jumpBuffer  = 0
    elseif inp.jumpPressed then
        self.jumpBuffer = JUMP_BUFFER
    end
    if self.jumpBuffer > 0 and self.coyoteTimer > 0 then
        self.vy = JUMP_FORCE
        self.coyoteTimer = 0
        self.jumpBuffer  = 0
    end
    inp.jumpPressed = false  -- consume the edge; latch/readLocalKeys refills it

    -- Move + collide
    local nx, ny, nvx, nvy, ground, ceiling, spike =
        self.world:move(self.x, self.y, self.w, self.h, self.vx * dt, self.vy * dt)
    self.x  = nx;  self.y  = ny
    self.vx = nvx / dt;  self.vy = nvy / dt
    if ceiling then self.vy = math.max(0, self.vy) end
    if ground then
        self.vy = 0
        self.coyoteTimer = COYOTE_FRAMES
    end
    self.onGround = ground

    -- Spike / fall death
    if spike or self.y > self.world.height * self.world.tileSize + 64 then
        self:die()
        return
    end

    -- Coins
    local c = self.world:collectCoin(self.x, self.y, self.w, self.h)
    self.coins = self.coins + c

    -- Goal
    if self.world:checkGoal(self.x, self.y, self.w, self.h) then
        self.won = true
    end

    -- Walk anim
    if moving and self.onGround then
        self.walkTimer = self.walkTimer + dt
        if self.walkTimer > 0.12 then
            self.walkTimer = 0
            self.walkFrame = (self.walkFrame + 1) % 2
        end
    else
        self.walkFrame = 0
        self.walkTimer = 0
    end
end

-- Check if another player stomps this one. Returns true if stomp happened.
function Player:checkStompedBy(attacker)
    if attacker == self then return false end
    if attacker.eliminated or attacker.dead then return false end
    if self.eliminated or self.dead then return false end
    if self.invTimer > 0 then return false end

    -- AABB overlap
    local overlap = attacker.x < self.x + self.w and
                    attacker.x + attacker.w > self.x and
                    attacker.y < self.y + self.h and
                    attacker.y + attacker.h > self.y

    if not overlap then return false end

    -- Stomp: attacker falling, attacker feet above victim mid
    local attackerFeet = attacker.y + attacker.h
    local victimMid    = self.y + self.h / 2
    if attacker.vy > 0 and attackerFeet <= victimMid + 10 then
        attacker.vy = STOMP_VY
        attacker.coins = attacker.coins + 2
        self:die(true)  -- true = PvP kill
        return true
    end

    -- Side collision — attacker gets pushed back (no damage)
    return false
end

function Player:die(pvpKill)
    if self.dead or self.eliminated then return end
    if self.invTimer > 0 then return end
    self.lives = self.lives - 1
    self.dead  = true
    self.respawnTimer = 1.5
    self.vy = -300
    self.vx = 0
    if self.lives <= 0 then
        self.eliminated = true
    end
end

function Player:respawn()
    if self.eliminated then return end
    self.x        = self.startX
    self.y        = self.startY
    self.vx       = 0
    self.vy       = 0
    self.dead     = false
    self.won      = false
    self.invTimer = 2.5
end

function Player:resetForLevel(world)
    self.world  = world
    local T = world.tileSize
    self.x      = (1 + self.id) * T
    self.y      = 9 * T
    self.startX = self.x
    self.startY = self.y
    self.vx     = 0
    self.vy     = 0
    self.dead   = false
    self.won    = false
    self.onGround = false
    self.coyoteTimer = 0
    self.jumpBuffer  = 0
    self.walkFrame   = 0
    self.walkTimer   = 0
    -- Spawn protection: the level's enemies may have been patrolling for a
    -- while before this player arrived, so without this they can spawn right
    -- on top of one and die instantly.
    self.invTimer    = 2.5
end

function Player:draw(camX, camY, showGun)
    if self.eliminated then return end

    local px = self.x - camX
    local py = self.y - camY
    local c  = self.color

    if self.dead then
        love.graphics.setColor(c[1], c[2], c[3], 0.4)
        love.graphics.rectangle("fill", px, py, self.w, self.h)
        return
    end

    -- Spawn-protection flash: visible half the time at reduced alpha
    local alpha = 1
    if self.invTimer > 0 then
        alpha = (math.floor(self.invTimer * 10) % 2 == 0) and 0.3 or 0.85
    end

    -- Body
    love.graphics.setColor(c[1], c[2], c[3], alpha)
    love.graphics.rectangle("fill", px, py + 10, self.w, self.h - 10)

    -- Hat (darker shade)
    love.graphics.setColor(c[1]*0.6, c[2]*0.6, c[3]*0.6, alpha)
    love.graphics.rectangle("fill", px - 2, py, self.w + 4, 14)

    -- Player number badge
    love.graphics.setColor(1, 1, 1, alpha)
    love.graphics.print(self.id, px + self.w/2 - 3, py + 2)

    -- Eyes
    local eyeX = self.facing == 1 and (px + self.w - 7) or (px + 4)
    love.graphics.setColor(1, 1, 1, alpha)
    love.graphics.rectangle("fill", eyeX, py + 3, 5, 5)
    love.graphics.setColor(0, 0, 0, alpha)
    love.graphics.rectangle("fill", eyeX + (self.facing == 1 and 2 or 0), py + 4, 3, 3)

    -- Gun (drawn before legs so it sits at hip-level, extending forward)
    if showGun and not self.dead then
        local hipY   = py + self.h - 14
        local barrelLen = 10
        local bodyLen   = 6
        local kick = self.fireCooldown and self.fireCooldown > 0.15 and 2 or 0
        local baseX = self.facing == 1 and (px + self.w - 2 - kick)
                                        or (px + 2 + kick)
        -- Grip
        love.graphics.setColor(0.25, 0.25, 0.28, alpha)
        love.graphics.rectangle("fill",
            self.facing == 1 and baseX or baseX - bodyLen,
            hipY, bodyLen, 5)
        -- Barrel
        love.graphics.setColor(0.55, 0.55, 0.6, alpha)
        love.graphics.rectangle("fill",
            self.facing == 1 and (baseX + bodyLen - 1) or (baseX - bodyLen - barrelLen + 1),
            hipY + 1, barrelLen, 3)
        -- Muzzle flash during the first ~0.1s of cooldown after firing
        if self.fireCooldown and self.fireCooldown > 0.15 then
            love.graphics.setColor(1, 0.9, 0.3, alpha)
            local muzzleX = self.facing == 1
                and (baseX + bodyLen + barrelLen - 1)
                or  (baseX - bodyLen - barrelLen - 2)
            love.graphics.rectangle("fill", muzzleX, hipY, 4, 5)
        end
    end

    -- Legs
    love.graphics.setColor(c[1]*0.5, c[2]*0.5, c[3]*0.5)
    if self.onGround and self.walkFrame == 1 then
        love.graphics.rectangle("fill", px,              py + self.h - 6, 9, 6)
        love.graphics.rectangle("fill", px + self.w - 9, py + self.h - 2, 9, 2)
    else
        love.graphics.rectangle("fill", px,              py + self.h - 6, 9, 6)
        love.graphics.rectangle("fill", px + self.w - 9, py + self.h - 6, 9, 6)
    end

    -- Lives indicators (hearts above head)
    for i = 1, self.lives do
        love.graphics.setColor(1, 0.2, 0.2)
        love.graphics.rectangle("fill", px + (i-1)*8 - 2, py - 10, 6, 5)
    end
end

return Player
