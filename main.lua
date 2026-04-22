local World     = require "world"
local Player    = require "player"
local Enemy     = require "enemy"
local Camera    = require "camera"
local Particles = require "particles"
local Levels    = require "levels"
local Network   = require "network"
local Bullet    = require "bullet"

-- ── Game state ───────────────────────────────────────────────────────────────
-- States: "menu"  "lobby"  "playing"  "game_over"
local state = "menu"

-- Per-level cache of { world, enemies, stars }. Lazily populated; each player
-- lives in their own level's world so they can race independently.
local levelInstances = {}

-- Current render view (= local player's level). These are aliases into
-- levelInstances for whatever level the local player is currently on.
-- `bullets` on host/solo aliases the current level's bullet list; on client
-- it's rebuilt each STATE snapshot from the host's flat bullet array.
local world, enemies, bgStars, bullets
local camera, particles
local players = {}
local totalCoins   = 0
local currentLevel = 1          -- local player's level (for rendering)
local localPlayerId = 1

local net = nil
local isHost = true
local freezeReadySound = nil
local _prevFreezeCd = 0  -- local player's previous-frame freeze cooldown
-- Global mode flag: classic platformer vs gun-enabled. Toggled from menu.
-- Synced from host to clients via JOIN and LEVEL messages.
local gunMode = false

-- Lobby UI
local lobbyInput = ""
local lobbyMode  = nil
local lobbyMsg   = ""
local LEVEL_BANNER_TIME = 1.8

-- ── Level instance helpers ───────────────────────────────────────────────────

local function makeStarsFor(w)
    local s = {}
    for _ = 1, 80 do
        table.insert(s, {
            x = math.random(0, w.width  * w.tileSize),
            y = math.random(0, w.height * w.tileSize),
            r = math.random() * 0.5 + 0.5,
        })
    end
    return s
end

local function getLevelInstance(lvl)
    local inst = levelInstances[lvl]
    if inst then return inst end
    local data = Levels[lvl]
    local w = World.new(data)
    local es = {}
    for idx, sp in ipairs(data.enemies or {}) do
        local e = Enemy.new(w, sp[1], sp[2])
        e.id    = idx
        e.level = lvl
        es[#es+1] = e
    end
    inst = { world = w, enemies = es, bullets = {}, stars = makeStarsFor(w) }
    levelInstances[lvl] = inst
    return inst
end

local function setLocalView(lvl)
    currentLevel = lvl
    local inst = getLevelInstance(lvl)
    world   = inst.world
    enemies = inst.enemies
    bullets = inst.bullets
    bgStars = inst.stars
    camera  = Camera.new(world)
    totalCoins = world:countCoins()
end

local function playersOnLevel(lvl)
    local list = {}
    for _, p in ipairs(players) do
        if p.level == lvl and not p.eliminated then
            list[#list+1] = p
        end
    end
    return list
end

local function allEnemiesFlat()
    local list = {}
    for lvl, inst in pairs(levelInstances) do
        for _, e in ipairs(inst.enemies) do
            e.level = lvl
            list[#list+1] = e
        end
    end
    return list
end

local function allBulletsFlat()
    local list = {}
    for lvl, inst in pairs(levelInstances) do
        for _, b in ipairs(inst.bullets) do
            b.level = lvl
            list[#list+1] = b
        end
    end
    return list
end

-- Move a player onto a given level (creates instance, sets spawn, wires world).
local function placePlayerOnLevel(p, lvl)
    p.level = lvl
    local inst = getLevelInstance(lvl)
    p:resetForLevel(inst.world)
    p.bannerTimer = LEVEL_BANNER_TIME
end

local function addPlayer(id)
    local p = Player.new(world, id)
    p.level = 1
    players[id] = p
    return p
end

local function activePlayers()
    local list = {}
    for _, p in ipairs(players) do
        if p then list[#list+1] = p end
    end
    return list
end

local function allPlayersDone()
    local any = false
    for _, p in ipairs(players) do
        any = true
        if not p.eliminated and not p.won then return false end
    end
    return any
end

local function allPlayersEliminated()
    for _, p in ipairs(players) do
        if not p.eliminated then return false end
    end
    return #players > 0
end

local function resetLevelInstances()
    levelInstances = {}
end

-- Send the current removed-coin tiles for `lvl` to a single peer so their
-- fresh client-side world matches the shared server state (the other player
-- may have been running around collecting there already).
local function syncCoinsToPeer(peerId, lvl)
    if not net or not isHost then return end
    local inst = levelInstances[lvl]
    if not inst then return end
    local src = Levels[lvl] and Levels[lvl].map
    if not src then return end
    for r = 1, inst.world.height do
        local srcRow = src[r]
        local wrRow  = inst.world.map[r]
        if srcRow and wrRow then
            for c = 1, inst.world.width do
                if srcRow[c] == World.T_COIN and wrRow[c] == World.T_EMPTY then
                    net:sendCoinRemovalTo(peerId, c, r, lvl)
                end
            end
        end
    end
end

-- ── Initialization ───────────────────────────────────────────────────────────

local function initSolo()
    players = {}
    resetLevelInstances()
    particles = Particles.new()
    localPlayerId = 1
    isHost        = true
    net           = nil
    setLocalView(1)
    local p = Player.new(world, 1)
    p.level = 1
    players[1] = p
end

-- ── Network helpers ──────────────────────────────────────────────────────────

local function applyNetworkState(data)
    -- Format: STATE | playerCount
    --   | [id level x y vx vy lives elim dead won facing ground walkFrame coins] xN
    --   | enemyCount
    --   | [level eid ex ey dead deadTimer] xM
    local i = 2
    local pcount = data[i]; i = i + 1
    for _ = 1, pcount do
        local id       = data[i];   i = i + 1
        local lvl      = data[i];   i = i + 1
        local x        = data[i];   i = i + 1
        local y        = data[i];   i = i + 1
        local vx       = data[i];   i = i + 1
        local vy       = data[i];   i = i + 1
        local lives    = data[i];   i = i + 1
        local elim     = data[i]==1; i = i + 1
        local dead     = data[i]==1; i = i + 1
        local won      = data[i]==1; i = i + 1
        local facing   = data[i];   i = i + 1
        local onGround = data[i]==1; i = i + 1
        local walkFrame= data[i];   i = i + 1
        local coins    = data[i];   i = i + 1
        local freezeCd = tonumber(data[i]) or 0; i = i + 1
        if not players[id] then
            players[id] = Player.new(world, id)
            players[id].level = lvl
        end
        local p = players[id]
        local wasDead  = p.dead
        local prevLevel = p.level
        p.lives = lives; p.dead = dead
        p.eliminated = elim; p.won = won; p.coins = coins
        p.level = lvl
        p.freezeCooldown = freezeCd
        if id == localPlayerId then
            -- If the host advanced us to a new level, switch our view.
            if lvl ~= currentLevel then
                setLocalView(lvl)
                p.world = world
                p.bannerTimer = LEVEL_BANNER_TIME
                p.invTimer = 2.5
                p.x = x; p.y = y; p.vx = vx; p.vy = vy
            elseif dead and not wasDead then
                p.x = x; p.y = y; p.vx = vx; p.vy = vy
                p.respawnTimer = 1.5
            elseif wasDead and not dead then
                p.x = x; p.y = y; p.vx = 0; p.vy = 0
                p.invTimer = 2.5
            else
                -- Client-side prediction with smooth reconciliation. Under
                -- latency the client is always slightly ahead of the host
                -- snapshot, so hard-snapping every frame feels like rubber-
                -- banding. Small drift: blend gently toward the server pos.
                -- Large drift (teleport/warp): hard-snap.
                local dx, dy = x - p.x, y - p.y
                local d2 = dx*dx + dy*dy
                if d2 > 128*128 then
                    p.x = x; p.y = y; p.vx = vx; p.vy = vy
                else
                    p.x = p.x + dx * 0.18
                    p.y = p.y + dy * 0.18
                    -- Velocity: trust server more, blends in grounding/jumps.
                    p.vx = p.vx * 0.5 + vx * 0.5
                    p.vy = p.vy * 0.5 + vy * 0.5
                end
            end
        else
            -- Remote players: snapshot the host-authoritative position as a
            -- target; the main loop lerps toward it each frame so motion is
            -- smooth between the 60Hz STATE ticks instead of stepping.
            p.targetX, p.targetY = x, y
            if not p._hasInit then
                p.x = x; p.y = y; p._hasInit = true
            end
            p.vx = vx; p.vy = vy
            p.facing = facing; p.onGround = onGround; p.walkFrame = walkFrame
        end
    end
    local ecount = data[i]; i = i + 1
    -- Only enemies on the local player's level matter for our view. Track
    -- which ids we saw so we can prune removed enemies from the local list.
    local seen = {}
    for _ = 1, ecount do
        local elvl = data[i]; i = i + 1
        local eid  = data[i]; i = i + 1
        local ex   = data[i]; i = i + 1
        local ey   = data[i]; i = i + 1
        local edead= data[i]==1; i = i + 1
        local edt  = data[i]; i = i + 1
        local efroz= data[i]==1; i = i + 1
        local eft  = tonumber(data[i]) or 0; i = i + 1
        if elvl == currentLevel then
            seen[eid] = true
            local found
            for _, e in ipairs(enemies) do
                if e.id == eid then found = e; break end
            end
            if found then
                found.x = ex; found.y = ey
                found.dead = edead; found.deadTimer = edt
                found.frozen = efroz; found.frozenTimer = eft
            end
        end
    end
    local k = 1
    while k <= #enemies do
        if seen[enemies[k].id] then k = k + 1 else table.remove(enemies, k) end
    end

    -- Bullets: fully replace the local list each snapshot (they're ephemeral
    -- and unordered, no need to track ids).
    local bcount = data[i]; i = i + 1
    if bcount then
        local newBullets = {}
        for _ = 1, bcount do
            local blvl = data[i]; i = i + 1
            local bx   = data[i]; i = i + 1
            local by   = data[i]; i = i + 1
            local bvx  = data[i]; i = i + 1
            local btyp = data[i]; i = i + 1
            if blvl == currentLevel then
                local bw = btyp == Bullet.TYPE_FREEZE and 10 or 6
                local bh = btyp == Bullet.TYPE_FREEZE and 6 or 4
                newBullets[#newBullets+1] = {x=bx, y=by, vx=bvx, w=bw, h=bh, type=btyp}
            end
        end
        bullets = newBullets
        -- Keep the current level instance's bullet list in sync so a later
        -- setLocalView call (or host/solo draw path) reads the same data.
        local inst = levelInstances[currentLevel]
        if inst then inst.bullets = newBullets end
    end
end

-- ── Love callbacks ───────────────────────────────────────────────────────────

function love.load()
    love.graphics.setDefaultFilter("nearest", "nearest")
    math.randomseed(os.time())
    -- Minimal init so we can draw the menu immediately
    setLocalView(1)
    particles = Particles.new()

    -- Procedural two-tone ding for when the freeze power is available again.
    local rate = 44100
    local dur  = 0.35
    local samples = math.floor(rate * dur)
    local sd = love.sound.newSoundData(samples, rate, 16, 1)
    for i = 0, samples - 1 do
        local t = i / rate
        -- First tone (880Hz) for first half, then second tone (1320Hz).
        local freq = t < dur/2 and 880 or 1320
        local localT = t < dur/2 and t or (t - dur/2)
        local env = math.exp(-localT * 12)
        local s = math.sin(2 * math.pi * freq * localT) * env * 0.4
        sd:setSample(i, s)
    end
    freezeReadySound = love.audio.newSource(sd, "static")
end

local function advancePlayerIfWon(p)
    if not p.won then return end
    if p.level >= #Levels then
        -- Final level: stay won (finished).
        return
    end
    -- Advance this player to next level individually.
    local nextLvl = p.level + 1
    placePlayerOnLevel(p, nextLvl)
    p.won = false
    if p.id == localPlayerId then
        setLocalView(nextLvl)
        p.world = world
    end
    if net and isHost and p.id ~= localPlayerId then
        -- The remote peer is about to setLocalView(nextLvl) on their side
        -- (driven by p.level in the next STATE snapshot). Their world there
        -- will start fresh, so replay the coin-tile removals that already
        -- happened on that level before they arrived.
        syncCoinsToPeer(p.id, nextLvl)
    end
end

function love.update(dt)
    dt = math.min(dt, 0.05)

    if state == "menu"     then return end
    if state == "lobby"    then updateLobby(dt); return end
    if state == "game_over" then return end

    -- ── playing ──────────────────────────────────────────────────────────────

    if net then
        if isHost then
            local lp = players[localPlayerId]
            if lp then lp:readLocalKeys() end
            local evts = net:hostUpdate(dt, activePlayers(), world, allEnemiesFlat(), currentLevel, allBulletsFlat())
            for _, ev in ipairs(evts) do
                if ev.type == "join" then
                    if not players[ev.id] then addPlayer(ev.id) end
                    -- Mid-game join: the new peer is stuck in lobby waiting
                    -- for a LEVEL signal, and needs the shared coin state for
                    -- the level they're about to load.
                    net:sendLevelTo(ev.id, 1)
                    syncCoinsToPeer(ev.id, 1)
                elseif ev.type == "leave" then
                    if players[ev.id] then players[ev.id].eliminated = true end
                elseif ev.type == "input" then
                    local p = players[ev.id]
                    if p then
                        p.input.left  = ev.left
                        p.input.right = ev.right
                        p.input.jump  = ev.jump
                        p.input.run   = ev.run
                        p.input.fire  = ev.fire or false
                        if ev.jumpPressed then p.input.jumpPressed = true end
                        if ev.firePressed then p.input.firePressed = true end
                        if ev.freezePressed then p.input.freezePressed = true end
                    end
                end
            end
        else
            local lp = players[localPlayerId]
            if lp then lp:readLocalKeys() end
            local inp = lp and lp.input or {left=false,right=false,jump=false,run=false,jumpPressed=false,fire=false,firePressed=false}
            local prevCoins = lp and lp.coins or 0

            local evts = net:clientUpdate(dt, inp)
            for _, ev in ipairs(evts) do
                if ev.type == "state" then
                    applyNetworkState(ev.data)
                elseif ev.type == "coin" then
                    -- Apply coin removal to the matching level's world. The
                    -- host fires sync COIN msgs for a newly-entered level
                    -- *before* the STATE snapshot that flips p.level, so the
                    -- client may not have the instance yet — create it now
                    -- so the removal lands and persists for when we setLocalView.
                    local inst = levelInstances[ev.level] or getLevelInstance(ev.level)
                    inst.world:setTile(ev.tx, ev.ty, World.T_EMPTY)
                elseif ev.type == "level" then
                    -- Host -> client lobby-to-playing signal. Start level 1.
                    setLocalView(ev.num or 1)
                    if ev.gunMode ~= nil then gunMode = ev.gunMode end
                elseif ev.type == "disconnect" then
                    lobbyMsg = "Disconnected from host"
                    state = "menu"
                end
            end

            if lp and lp.coins > prevCoins then
                particles:spawn(lp.x + lp.w/2, lp.y, {1,0.9,0}, 8, 140)
            end

            if lp and not lp.eliminated and not lp.dead then
                lp:updateMovement(dt)
            end
            -- Smooth remote players toward their server-authoritative target
            -- between 60Hz STATE ticks (keeps motion from stepping).
            for _, p in ipairs(players) do
                if p and p.id ~= localPlayerId and p.targetX then
                    local k = math.min(1, dt * 18)
                    p.x = p.x + (p.targetX - p.x) * k
                    p.y = p.y + (p.targetY - p.y) * k
                    if p.bannerTimer and p.bannerTimer > 0 then
                        p.bannerTimer = p.bannerTimer - dt
                    end
                end
            end
            if lp and lp.bannerTimer > 0 then lp.bannerTimer = lp.bannerTimer - dt end
            particles:update(dt)
            local sw, sh = love.graphics.getDimensions()
            if lp then camera:follow({lp}, sw, sh) end
            if lp then
                local cd = lp.freezeCooldown or 0
                if _prevFreezeCd > 0 and cd <= 0 and freezeReadySound and not gunMode then
                    freezeReadySound:stop(); freezeReadySound:play()
                end
                _prevFreezeCd = cd
            end
            return
        end
    else
        local lp = players[localPlayerId]
        if lp then lp:readLocalKeys() end
    end

    -- Host / Solo: full simulation.
    -- Each player simulates against their own level's world. checkGoal +
    -- coin collection happen inside Player:update using p.world.
    for _, p in ipairs(players) do
        if p and not p.eliminated then
            -- Make sure p.world matches p.level (in case it was just set).
            local inst = getLevelInstance(p.level)
            p.world = inst.world
            local prevCoins = p.coins
            p:update(dt)
            if p.coins > prevCoins then
                particles:spawn(p.x + p.w/2, p.y, {1,0.9,0}, 8, 140)
            end
            if p.bannerTimer > 0 then p.bannerTimer = p.bannerTimer - dt end
        end
    end

    -- Advance any players who hit the goal (per-player, independent).
    for _, p in ipairs(players) do
        if p and not p.eliminated then advancePlayerIfWon(p) end
    end

    -- Broadcast coin removals per level.
    if net and isHost then
        for lvl, inst in pairs(levelInstances) do
            if #inst.world.pendingRemovals > 0 then
                for _, pos in ipairs(inst.world.pendingRemovals) do
                    net:broadcastCoinRemoval(pos[1], pos[2], lvl)
                end
                inst.world.pendingRemovals = {}
            end
        end
    else
        -- Solo: clear pendingRemovals so they don't accumulate forever.
        for _, inst in pairs(levelInstances) do
            inst.world.pendingRemovals = {}
        end
    end

    -- PvP stomp checks: only within the same level.
    for lvl, _ in pairs(levelInstances) do
        local group = playersOnLevel(lvl)
        for _, attacker in ipairs(group) do
            for _, victim in ipairs(group) do
                if attacker ~= victim then
                    local wasEliminated = victim.eliminated
                    victim:checkStompedBy(attacker)
                    if victim.eliminated and not wasEliminated then
                        particles:spawn(victim.x + victim.w/2, victim.y, {1,0.3,0.3}, 12, 160)
                    end
                end
            end
        end
    end

    -- Spawn bullets for any player whose update() set _pendingShot.
    -- Gated by gunMode so classic mode never produces bullets even if the
    -- client spammed the fire key.
    for _, p in ipairs(players) do
        if p and not p.eliminated and p._pendingShot then
            p._pendingShot = false
            if gunMode then
                local inst = getLevelInstance(p.level)
                local bx = p.facing == 1 and (p.x + p.w) or (p.x - 6)
                local by = p.y + p.h/2 - 2
                local b = Bullet.new(bx, by, p.facing, p.id)
                b.level = p.level
                inst.bullets[#inst.bullets+1] = b
            end
        end
        if p and not p.eliminated and p._pendingFreezeShot then
            p._pendingFreezeShot = false
            if not gunMode then
                local inst = getLevelInstance(p.level)
                local bx = p.facing == 1 and (p.x + p.w) or (p.x - 10)
                local by = p.y + p.h/2 - 3
                local b = Bullet.new(bx, by, p.facing, p.id, Bullet.TYPE_FREEZE)
                b.level = p.level
                inst.bullets[#inst.bullets+1] = b
            end
        end
    end

    -- Enemy updates: each level's enemies see only players on that level.
    for lvl, inst in pairs(levelInstances) do
        local group = playersOnLevel(lvl)
        local i = 1
        while i <= #inst.enemies do
            local e = inst.enemies[i]
            e.level = lvl
            local alive = e:update(dt, group)
            if not alive then
                particles:spawn(e.x + 12, e.y + 12, {0.6,0.3,0}, 10, 100)
                table.remove(inst.enemies, i)
            else
                i = i + 1
            end
        end
        -- Bullets: collide with world tiles / enemies. Enemy kills happen
        -- inside Bullet:update (sets e.dead; the enemy loop above will reap
        -- it next tick after the death animation).
        local bi = 1
        while bi <= #inst.bullets do
            if inst.bullets[bi]:update(dt, inst.world, inst.enemies) then
                bi = bi + 1
            else
                table.remove(inst.bullets, bi)
            end
        end
    end

    particles:update(dt)

    -- Camera: follow local player (or all players in solo).
    local sw, sh = love.graphics.getDimensions()
    if net then
        local lp = players[localPlayerId]
        if lp then camera:follow({lp}, sw, sh) end
    else
        local lp = players[localPlayerId]
        if lp then camera:follow({lp}, sw, sh) end
    end

    -- Sync local view to local player's level (in case it changed).
    local lp = players[localPlayerId]
    if lp and lp.level ~= currentLevel then
        setLocalView(lp.level)
        lp.world = world
    end

    -- Freeze-ready chime: cooldown ticked from >0 to <=0 for local player.
    if lp then
        local cd = lp.freezeCooldown or 0
        if _prevFreezeCd > 0 and cd <= 0 and freezeReadySound and not gunMode then
            freezeReadySound:stop(); freezeReadySound:play()
        end
        _prevFreezeCd = cd
    end

    -- Global end conditions.
    if allPlayersEliminated() then
        state = "game_over"
    elseif allPlayersDone() then
        state = "game_over"
    end
end

function updateLobby(dt)
    if not net then return end
    if isHost then
        local evts = net:hostUpdate(dt, {}, world, {}, currentLevel)
        for _, ev in ipairs(evts) do
            if ev.type == "join" then
                addPlayer(ev.id)
                lobbyMsg = "Player " .. ev.id .. " joined! (" .. (#activePlayers()) .. " total)"
            end
        end
    else
        local evts = net:clientUpdate(dt, {left=false,right=false,jump=false,run=false,jumpPressed=false})
        for _, ev in ipairs(evts) do
            if ev.type == "join" then
                localPlayerId = ev.id
                addPlayer(ev.id)
                if ev.gunMode ~= nil then gunMode = ev.gunMode end
                lobbyMsg = "Connected! You are Player " .. ev.id ..
                    " (" .. (gunMode and "GUN" or "CLASSIC") .. " mode). Waiting for host..."
            elseif ev.type == "level" then
                setLocalView(ev.num or 1)
                if ev.gunMode ~= nil then gunMode = ev.gunMode end
                state = "playing"
            end
        end
    end
end

function love.draw()
    local sw, sh = love.graphics.getDimensions()

    if state == "menu"  then drawMenu(sw, sh);  return end
    if state == "lobby" then drawLobby(sw, sh); return end

    local cx, cy = camera.x, camera.y
    local sky = world.skyTop or {0.38, 0.6, 0.95}
    local skyb= world.skyBot or {0.55, 0.75, 1.0}

    love.graphics.setColor(sky)
    love.graphics.rectangle("fill", 0, 0, sw, sh * 0.6)
    love.graphics.setColor(skyb)
    love.graphics.rectangle("fill", 0, sh * 0.6, sw, sh * 0.4)

    love.graphics.setColor(1, 1, 1, 0.7)
    for _, s in ipairs(bgStars) do
        local sx = (s.x - cx * 0.1) % sw
        local sy = (s.y - cy * 0.1) % sh
        love.graphics.circle("fill", sx, sy, s.r)
    end

    world:draw(cx, cy, sw, sh)
    for _, e in ipairs(enemies) do e:draw(cx, cy) end
    if bullets then
        for _, b in ipairs(bullets) do
            if b.type == Bullet.TYPE_FREEZE then
                love.graphics.setColor(0.7, 0.95, 1.0)
                love.graphics.rectangle("fill", b.x - cx, b.y - cy, b.w or 10, b.h or 6)
                love.graphics.setColor(0.4, 0.8, 1.0, 0.6)
                love.graphics.rectangle("fill",
                    b.x - cx - ((b.vx or 0) > 0 and 6 or -(b.w or 10)),
                    b.y - cy + 1, 6, (b.h or 6) - 2)
            else
                love.graphics.setColor(1, 0.95, 0.3)
                love.graphics.rectangle("fill", b.x - cx, b.y - cy, b.w or 6, b.h or 4)
                love.graphics.setColor(1, 0.7, 0, 0.5)
                love.graphics.rectangle("fill",
                    b.x - cx - ((b.vx or 0) > 0 and 4 or -(b.w or 6)),
                    b.y - cy + 1, 4, (b.h or 4) - 2)
            end
        end
    end
    particles:draw(cx, cy)
    -- Only render players on our level.
    for _, p in ipairs(players) do
        if p and p.level == currentLevel then p:draw(cx, cy, gunMode) end
    end

    drawHUD(sw, sh)

    -- Per-player "Level N" banner on local player.
    local lp = players[localPlayerId]
    if lp and lp.bannerTimer and lp.bannerTimer > 0 then
        local alpha = math.min(1, lp.bannerTimer / 0.4)
        love.graphics.setColor(0, 0, 0, 0.5 * alpha)
        love.graphics.rectangle("fill", sw/2 - 180, sh/2 - 40, 360, 70, 12, 12)
        love.graphics.setColor(1, 0.9, 0.1, alpha)
        love.graphics.printf("LEVEL " .. lp.level, 0, sh/2 - 30, sw, "center")
        love.graphics.setColor(1, 1, 1, alpha)
        love.graphics.printf(Levels[lp.level] and Levels[lp.level].name or "", 0, sh/2 - 5, sw, "center")
    end

    if state == "game_over" then
        love.graphics.setColor(0, 0, 0, 0.65)
        love.graphics.rectangle("fill", sw/2-200, sh/2-80, 400, 150, 12, 12)
        if allPlayersEliminated() then
            love.graphics.setColor(1, 0.3, 0.3)
            love.graphics.printf("GAME OVER", 0, sh/2 - 60, sw, "center")
        else
            love.graphics.setColor(0.3, 1, 0.4)
            love.graphics.printf("RACE COMPLETE!", 0, sh/2 - 60, sw, "center")
        end
        local yy = sh/2 - 20
        for _, p in ipairs(players) do
            if p then
                love.graphics.setColor(p.color)
                love.graphics.printf("P" .. p.id .. ": L" .. p.level .. "  " .. p.coins .. " coins",
                    0, yy, sw, "center")
                yy = yy + 20
            end
        end
        love.graphics.setColor(1, 1, 1)
        if net then
            love.graphics.printf("ESC for menu", 0, sh/2 + 50, sw, "center")
        else
            love.graphics.printf("Press R to play again  |  ESC for menu", 0, sh/2 + 50, sw, "center")
        end
    end
end

local function drawHeart(x, y, size, r, g, b, a)
    love.graphics.setColor(r, g, b, a or 1)
    local s = size * 0.5
    love.graphics.circle("fill", x - s*0.5, y, s * 0.65)
    love.graphics.circle("fill", x + s*0.5, y, s * 0.65)
    love.graphics.polygon("fill",
        x - s, y + s*0.2,
        x + s, y + s*0.2,
        x,     y + s*1.6)
end

function drawHUD(sw, sh)
    local font   = love.graphics.getFont()
    local lp     = players[localPlayerId]
    local hudLvl = (lp and lp.level) or currentLevel
    local lvlTxt = "World " .. math.ceil(hudLvl/4) .. "-" .. ((hudLvl-1)%4+1) .. ": " .. Levels[hudLvl].name

    -- Freeze power indicator (top-center).
    if (not gunMode) and lp then
        local cd = lp.freezeCooldown or 0
        local txt, col
        if cd <= 0 then
            txt = "FREEZE READY [Q]"
            col = {0.5, 0.95, 1.0}
        else
            txt = string.format("FREEZE: %ds", math.ceil(cd))
            col = {0.5, 0.5, 0.55}
        end
        local w = font:getWidth(txt) + 20
        love.graphics.setColor(0, 0, 0, 0.55)
        love.graphics.rectangle("fill", sw/2 - w/2, 6, w, 22, 5, 5)
        love.graphics.setColor(col)
        love.graphics.printf(txt, sw/2 - w/2, 10, w, "center")
    end
    local barW   = font:getWidth(lvlTxt) + 20
    love.graphics.setColor(0, 0, 0, 0.55)
    love.graphics.rectangle("fill", 6, 6, barW, 22, 5, 5)
    love.graphics.setColor(1, 1, 0.5)
    love.graphics.print(lvlTxt, 16, 10)

    local cardW, cardH = 190, 36
    local yy = 36
    for _, p in ipairs(players) do
        if p then
            love.graphics.setColor(0, 0, 0, 0.55)
            love.graphics.rectangle("fill", 6, yy, cardW, cardH, 5, 5)

            love.graphics.setColor(p.color[1], p.color[2], p.color[3])
            love.graphics.rectangle("fill", 6, yy, 5, cardH, 5, 0)

            local label = "P" .. p.id .. "  L" .. (p.level or 1)
            if     p.eliminated then label = label .. " OUT"
            elseif p.won        then label = label .. " WIN"
            elseif p.dead       then label = label .. " x"
            end
            love.graphics.setColor(1, 1, 1)
            love.graphics.print(label, 16, yy + 4)

            local maxLives = 3
            local hx = 16
            local hy = yy + cardH - 14
            for i = 1, maxLives do
                local full = i <= p.lives
                if full then
                    drawHeart(hx, hy, 8, 0.95, 0.2, 0.2)
                else
                    drawHeart(hx, hy, 8, 0.4, 0.4, 0.4, 0.7)
                end
                hx = hx + 14
            end

            love.graphics.setColor(1, 0.85, 0)
            love.graphics.circle("fill", cardW - 22, yy + cardH/2, 6)
            love.graphics.setColor(0.8, 0.6, 0)
            love.graphics.circle("line", cardW - 22, yy + cardH/2, 6)
            love.graphics.setColor(1, 1, 1)
            love.graphics.print(tostring(p.coins), cardW - 13, yy + cardH/2 - 7)

            yy = yy + cardH + 4
        end
    end
end

function drawMenu(sw, sh)
    love.graphics.setColor(0.1, 0.1, 0.2)
    love.graphics.rectangle("fill", 0, 0, sw, sh)
    love.graphics.setColor(1, 0.9, 0.1)
    love.graphics.printf("PLATFORMER", 0, sh/2 - 100, sw, "center")
    love.graphics.setColor(1, 1, 1)
    love.graphics.printf("[S]  Solo Play", 0, sh/2 - 30, sw, "center")
    love.graphics.printf("[H]  Host Multiplayer", 0, sh/2, sw, "center")
    love.graphics.printf("[J]  Join Game (LAN)", 0, sh/2 + 30, sw, "center")
    love.graphics.setColor(gunMode and {0.4, 1, 0.4} or {0.8, 0.8, 0.8})
    love.graphics.printf("[G]  Gun Mode: " .. (gunMode and "ON" or "OFF"),
        0, sh/2 + 70, sw, "center")
    love.graphics.setColor(0.6, 0.6, 0.6)
    love.graphics.printf("Arrows/WASD move  -  Space jump  -  Shift run" ..
        (gunMode and "  -  Ctrl/F shoot" or "  -  Q freeze enemy"),
        0, sh/2 + 100, sw, "center")
    love.graphics.printf("ESC to quit", 0, sh/2 + 130, sw, "center")
end

function drawLobby(sw, sh)
    love.graphics.setColor(0.05, 0.05, 0.15)
    love.graphics.rectangle("fill", 0, 0, sw, sh)

    if lobbyMode == "host" then
        love.graphics.setColor(1, 0.9, 0.1)
        love.graphics.printf("HOSTING", 0, sh/2 - 110, sw, "center")
        love.graphics.setColor(1, 1, 1)
        local ip = getLocalIP()
        love.graphics.printf("Your IP: " .. ip, 0, sh/2 - 70, sw, "center")
        love.graphics.printf("Port: 6789", 0, sh/2 - 45, sw, "center")
        love.graphics.setColor(0.8, 1, 0.8)
        love.graphics.printf(lobbyMsg, 0, sh/2, sw, "center")
        love.graphics.setColor(1, 1, 1)
        love.graphics.printf("Players: " .. #activePlayers(), 0, sh/2 + 30, sw, "center")
        love.graphics.printf("[ENTER] Start Game    [ESC] Cancel", 0, sh/2 + 70, sw, "center")
    else
        love.graphics.setColor(1, 0.9, 0.1)
        love.graphics.printf("JOIN GAME", 0, sh/2 - 110, sw, "center")
        love.graphics.setColor(1, 1, 1)
        love.graphics.printf("Enter host IP address:", 0, sh/2 - 50, sw, "center")
        love.graphics.setColor(0.2, 0.2, 0.3)
        love.graphics.rectangle("fill", sw/2 - 120, sh/2 - 10, 240, 30, 6, 6)
        love.graphics.setColor(1, 1, 1)
        love.graphics.printf(lobbyInput .. "_", sw/2 - 110, sh/2 - 4, 220, "left")
        love.graphics.setColor(0.8, 1, 0.8)
        love.graphics.printf(lobbyMsg, 0, sh/2 + 30, sw, "center")
        love.graphics.setColor(0.7, 0.7, 0.7)
        love.graphics.printf("[ENTER] Connect    [ESC] Cancel", 0, sh/2 + 60, sw, "center")
    end
end

function getLocalIP()
    local ok, socket = pcall(require, "socket")
    if ok then
        local s = socket.udp()
        s:setpeername("8.8.8.8", 80)
        local ip = s:getsockname()
        s:close()
        return ip or "127.0.0.1"
    end
    return "127.0.0.1"
end

function love.keypressed(key)
    if key == "escape" then
        if state == "menu" then
            love.event.quit()
        elseif state == "lobby" then
            if net then net:destroy(); net = nil end
            state = "menu"
        else
            if net then net:destroy(); net = nil end
            state = "menu"
        end
        return
    end

    if state == "menu" then
        if key == "s" then
            initSolo()
            state = "playing"
        elseif key == "h" then
            players = {}
            resetLevelInstances()
            particles = Particles.new()
            setLocalView(1)
            localPlayerId = 1
            isHost        = true
            local p = Player.new(world, 1); p.level = 1
            players[1]    = p
            net           = Network.newHost()
            net.gunMode   = gunMode
            lobbyMode     = "host"
            lobbyMsg      = "Waiting for players..."
            state         = "lobby"
        elseif key == "j" then
            lobbyMode  = "join"
            lobbyInput = ""
            lobbyMsg   = ""
            state      = "lobby"
        elseif key == "g" then
            gunMode = not gunMode
        end
        return
    end

    if state == "lobby" then
        if lobbyMode == "host" then
            if key == "return" then
                if net then net:broadcastLevel(currentLevel) end
                state = "playing"
            end
        else
            if key == "return" then
                local ip = lobbyInput == "" and "127.0.0.1" or lobbyInput
                players    = {}
                resetLevelInstances()
                particles  = Particles.new()
                setLocalView(1)
                isHost     = false
                net        = Network.newClient(ip)
                lobbyMsg   = "Connecting to " .. ip .. "..."
            elseif key == "backspace" then
                lobbyInput = lobbyInput:sub(1, -2)
            end
        end
        return
    end

    if state == "game_over" then
        if key == "r" and not net then
            initSolo()
            state = "playing"
        end
        return
    end

    if state == "playing" then
        -- R restarts only in solo. In multiplayer it's a no-op so a stray
        -- keypress can't tear down the live network session.
        if key == "r" and not net then
            initSolo()
            state = "playing"
        end
    end
end

function love.textinput(t)
    if state == "lobby" and lobbyMode == "join" then
        if t:match("[%d%.]") then
            lobbyInput = lobbyInput .. t
        end
    end
end
