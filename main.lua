local World     = require "world"
local Player    = require "player"
local Enemy     = require "enemy"
local Camera    = require "camera"
local Particles = require "particles"
local Levels    = require "levels"
local Network   = require "network"

-- ── Game state ───────────────────────────────────────────────────────────────
-- States: "menu"  "lobby"  "playing"  "level_complete"  "game_over"
local state = "menu"

local world, camera, particles
local players  = {}
local enemies  = {}
local bgStars  = {}
local totalCoins  = 0
local currentLevel = 1
local localPlayerId = 1  -- which player this machine controls

local net = nil          -- Network object (nil = solo, else host or client)
local isHost = true      -- true for solo or host

-- Lobby UI
local lobbyInput   = ""     -- typed IP when joining
local lobbyMode    = nil    -- "host" or "join"
local lobbyMsg     = ""
local levelTransTimer = 0
local LEVEL_TRANS_DELAY = 2.5

-- ── Helpers ──────────────────────────────────────────────────────────────────

local function makeStars()
    bgStars = {}
    for _ = 1, 80 do
        table.insert(bgStars, {
            x = math.random(0, world.width  * world.tileSize),
            y = math.random(0, world.height * world.tileSize),
            r = math.random() * 0.5 + 0.5,
        })
    end
end

local function spawnEnemies(levelData)
    enemies = {}
    for idx, sp in ipairs(levelData.enemies or {}) do
        local e = Enemy.new(world, sp[1], sp[2])
        e.id = idx  -- stable id so the client can match after host removals
        table.insert(enemies, e)
    end
end

local function findEnemy(id)
    for _, e in ipairs(enemies) do
        if e.id == id then return e end
    end
end

local function loadLevel(num)
    currentLevel = num
    local lvl = Levels[num]
    world = World.new(lvl)
    camera = Camera.new(world)
    totalCoins = world:countCoins()
    spawnEnemies(lvl)
    makeStars()
    -- Reset all players for new level (keep lives & coins)
    for _, p in ipairs(players) do
        p:resetForLevel(world)
    end
end

local function addPlayer(id)
    local p = Player.new(world, id)
    players[id] = p
    return p
end

local function initSolo()
    players = {}
    world   = World.new(Levels[1])
    camera  = Camera.new(world)
    particles = Particles.new()
    totalCoins = world:countCoins()
    spawnEnemies(Levels[1])
    makeStars()
    currentLevel   = 1
    localPlayerId  = 1
    isHost         = true
    net            = nil
    local p = Player.new(world, 1)
    players[1] = p
end

local function allPlayersWon()
    local active = 0
    for _, p in ipairs(players) do
        if not p.eliminated then
            active = active + 1
            if not p.won then return false end
        end
    end
    return active > 0
end

local function allPlayersEliminated()
    for _, p in ipairs(players) do
        if not p.eliminated then return false end
    end
    return #players > 0
end

local function activePlayers()
    local list = {}
    for _, p in ipairs(players) do
        if p then list[#list+1] = p end
    end
    return list
end

-- ── Network helpers ───────────────────────────────────────────────────────────

local function applyNetworkState(data)
    -- data format: STATE | levelNum | playerCount | [id x y vx vy lives elim dead won facing ground walkFrame coins] x N | enemyCount | [ex ey dead deadTimer] x M
    local i = 2
    local lvl = data[i]; i = i + 1
    if lvl ~= currentLevel then
        loadLevel(lvl)
    end
    local pcount = data[i]; i = i + 1
    for _ = 1, pcount do
        local id       = data[i];   i = i + 1
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
        if not players[id] then
            players[id] = Player.new(world, id)
        end
        local p = players[id]
        local wasDead = p.dead
        p.lives = lives; p.dead = dead
        p.eliminated = elim; p.won = won; p.coins = coins
        if id == localPlayerId then
            -- Client-side prediction with server reconciliation: trust local
            -- prediction while it stays close to the host, snap when it drifts.
            -- Always snap on death/respawn transitions (prediction can't know).
            if dead and not wasDead then
                p.x = x; p.y = y; p.vx = vx; p.vy = vy
                p.respawnTimer = 1.5
            elseif wasDead and not dead then
                p.x = x; p.y = y; p.vx = 0; p.vy = 0
                p.invTimer = 2.5
            else
                local dx, dy = p.x - x, p.y - y
                if dx*dx + dy*dy > 24*24 then
                    p.x = x; p.y = y; p.vx = vx; p.vy = vy
                end
            end
        else
            -- Remote players: full sync, host is authoritative.
            p.x = x; p.y = y; p.vx = vx; p.vy = vy
            p.facing = facing; p.onGround = onGround; p.walkFrame = walkFrame
        end
    end
    local ecount = data[i]; i = i + 1
    -- Sync enemies by stable id. The host removes enemies after their death
    -- animation, so any local enemy whose id isn't in the snapshot is gone.
    local seen = {}
    for _ = 1, ecount do
        local eid  = data[i]; i = i + 1
        local ex   = data[i]; i = i + 1
        local ey   = data[i]; i = i + 1
        local dead = data[i]==1; i = i + 1
        local dt   = data[i]; i = i + 1
        seen[eid] = true
        local e = findEnemy(eid)
        if e then
            e.x = ex; e.y = ey
            e.dead = dead; e.deadTimer = dt
        end
    end
    local k = 1
    while k <= #enemies do
        if seen[enemies[k].id] then k = k + 1 else table.remove(enemies, k) end
    end
end

-- ── Love callbacks ────────────────────────────────────────────────────────────

function love.load()
    love.graphics.setDefaultFilter("nearest", "nearest")
    math.randomseed(os.time())
    -- Minimal init so we can draw the menu immediately
    world     = World.new(Levels[1])
    camera    = Camera.new(world)
    particles = Particles.new()
    makeStars()
end

function love.update(dt)
    dt = math.min(dt, 0.05)

    if state == "menu" then return end

    if state == "lobby" then
        updateLobby(dt)
        return
    end

    if state == "level_complete" then
        levelTransTimer = levelTransTimer - dt
        if levelTransTimer <= 0 then
            if currentLevel < #Levels then
                local nextLvl = currentLevel + 1
                loadLevel(nextLvl)
                if net and isHost then
                    net:broadcastLevel(nextLvl)
                end
                state = "playing"
            else
                state = "game_over"
            end
        end
        return
    end

    if state == "game_over" then return end

    -- ── playing ──────────────────────────────────────────────────────────────

    -- Network tick
    if net then
        if isHost then
            local lp = players[localPlayerId]
            if lp then lp:readLocalKeys() end
            local evts = net:hostUpdate(dt, activePlayers(), world, enemies, currentLevel)
            for _, ev in ipairs(evts) do
                if ev.type == "join" then
                    if not players[ev.id] then
                        addPlayer(ev.id)
                    end
                elseif ev.type == "leave" then
                    if players[ev.id] then
                        players[ev.id].eliminated = true
                    end
                elseif ev.type == "input" then
                    local p = players[ev.id]
                    if p then
                        p.input.left  = ev.left
                        p.input.right = ev.right
                        p.input.jump  = ev.jump
                        p.input.run   = ev.run
                        -- Latch jumpPressed: multiple INPUT packets can arrive
                        -- between sim ticks, and we must not let a later
                        -- `false` packet erase a pending jump edge.
                        if ev.jumpPressed then p.input.jumpPressed = true end
                    end
                end
            end
        else
            -- Client: read local keys, let host know
            local lp = players[localPlayerId]
            if lp then lp:readLocalKeys() end
            local inp = lp and lp.input or {left=false,right=false,jump=false,run=false,jumpPressed=false}

            -- Snapshot coins before applying host state
            local prevCoins = lp and lp.coins or 0

            local evts = net:clientUpdate(dt, inp)
            for _, ev in ipairs(evts) do
                if ev.type == "state" then
                    applyNetworkState(ev.data)
                elseif ev.type == "coin" then
                    world:setTile(ev.tx, ev.ty, World.T_EMPTY)
                elseif ev.type == "level" then
                    loadLevel(ev.num)
                elseif ev.type == "disconnect" then
                    lobbyMsg = "Disconnected from host"
                    state = "menu"
                end
            end

            -- Spawn coin particles when host confirms a collection
            if lp and lp.coins > prevCoins then
                particles:spawn(lp.x + lp.w/2, lp.y, {1,0.9,0}, 8, 140)
            end

            -- Client-side prediction: simulate local player's movement for
            -- instant input response. applyNetworkState reconciles against
            -- the host and snaps if drift exceeds threshold.
            if lp and not lp.eliminated and not lp.dead then
                lp:updateMovement(dt)
            end
            particles:update(dt)
            local sw, sh = love.graphics.getDimensions()
            if lp then camera:follow({lp}, sw, sh) end
            return
        end
    else
        -- Solo: read keys for player 1
        local lp = players[localPlayerId]
        if lp then lp:readLocalKeys() end
    end

    -- Host / Solo: full simulation
    local aList = activePlayers()

    for _, p in ipairs(aList) do
        if not p.eliminated then
            local prevCoins = p.coins
            p:update(dt)
            if p.coins > prevCoins then
                particles:spawn(p.x + p.w/2, p.y, {1,0.9,0}, 8, 140)
            end
        end
    end

    -- Broadcast coin removals to clients
    if net and isHost and #world.pendingRemovals > 0 then
        for _, pos in ipairs(world.pendingRemovals) do
            net:broadcastCoinRemoval(pos[1], pos[2])
        end
        world.pendingRemovals = {}
    end

    -- PvP stomp checks
    for _, attacker in ipairs(aList) do
        for _, victim in ipairs(aList) do
            if attacker ~= victim then
                local wasEliminated = victim.eliminated
                victim:checkStompedBy(attacker)
                if victim.eliminated and not wasEliminated then
                    particles:spawn(victim.x + victim.w/2, victim.y, {1,0.3,0.3}, 12, 160)
                end
            end
        end
    end

    -- Enemies
    local i = 1
    while i <= #enemies do
        local alive = enemies[i]:update(dt, aList)
        if not alive then
            particles:spawn(enemies[i].x + 12, enemies[i].y + 12, {0.6,0.3,0}, 10, 100)
            table.remove(enemies, i)
        else
            i = i + 1
        end
    end

    particles:update(dt)

    local sw, sh = love.graphics.getDimensions()
    local followList
    if net then
        -- Multiplayer: always follow only the local player
        local lp = players[localPlayerId]
        followList = lp and {lp} or {}
    else
        followList = aList
    end
    if #followList > 0 then
        camera:follow(followList, sw, sh)
    end

    -- State transitions
    if allPlayersWon() then
        if currentLevel < #Levels then
            state = "level_complete"
            levelTransTimer = LEVEL_TRANS_DELAY
        else
            state = "game_over"
        end
    elseif allPlayersEliminated() then
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
                lobbyMsg = "Connected! You are Player " .. ev.id .. ". Waiting for host..."
            elseif ev.type == "level" then
                -- Host started the game
                loadLevel(ev.num)
                state = "playing"
            end
        end
    end
end

function love.draw()
    local sw, sh = love.graphics.getDimensions()

    if state == "menu" then
        drawMenu(sw, sh)
        return
    end

    if state == "lobby" then
        drawLobby(sw, sh)
        return
    end

    local cx, cy = camera.x, camera.y
    local sky = world.skyTop or {0.38, 0.6, 0.95}
    local skyb= world.skyBot or {0.55, 0.75, 1.0}

    -- Sky
    love.graphics.setColor(sky)
    love.graphics.rectangle("fill", 0, 0, sw, sh * 0.6)
    love.graphics.setColor(skyb)
    love.graphics.rectangle("fill", 0, sh * 0.6, sw, sh * 0.4)

    -- Stars
    love.graphics.setColor(1, 1, 1, 0.7)
    for _, s in ipairs(bgStars) do
        local sx = (s.x - cx * 0.1) % sw
        local sy = (s.y - cy * 0.1) % sh
        love.graphics.circle("fill", sx, sy, s.r)
    end

    world:draw(cx, cy, sw, sh)
    for _, e in ipairs(enemies) do e:draw(cx, cy) end
    particles:draw(cx, cy)
    for _, p in ipairs(players) do
        if p then p:draw(cx, cy) end
    end

    drawHUD(sw, sh)

    if state == "level_complete" then
        love.graphics.setColor(0, 0, 0, 0.6)
        love.graphics.rectangle("fill", sw/2-180, sh/2-50, 360, 90, 12, 12)
        love.graphics.setColor(1, 0.9, 0.1)
        love.graphics.printf("LEVEL CLEAR!", 0, sh/2 - 36, sw, "center")
        love.graphics.setColor(1, 1, 1)
        love.graphics.printf("Next: " .. (Levels[currentLevel+1] and Levels[currentLevel+1].name or "???"), 0, sh/2, sw, "center")
    end

    if state == "game_over" then
        love.graphics.setColor(0, 0, 0, 0.65)
        love.graphics.rectangle("fill", sw/2-200, sh/2-80, 400, 150, 12, 12)
        if allPlayersEliminated() then
            love.graphics.setColor(1, 0.3, 0.3)
            love.graphics.printf("GAME OVER", 0, sh/2 - 60, sw, "center")
        else
            love.graphics.setColor(0.3, 1, 0.4)
            love.graphics.printf("YOU WIN!", 0, sh/2 - 60, sw, "center")
        end
        -- Show scores
        local yy = sh/2 - 20
        for _, p in ipairs(players) do
            if p then
                love.graphics.setColor(p.color)
                love.graphics.printf("P" .. p.id .. ": " .. p.coins .. " coins", 0, yy, sw, "center")
                yy = yy + 20
            end
        end
        love.graphics.setColor(1, 1, 1)
        love.graphics.printf("Press R to play again  |  ESC for menu", 0, sh/2 + 50, sw, "center")
    end
end

local function drawHeart(x, y, size, r, g, b, a)
    love.graphics.setColor(r, g, b, a or 1)
    -- Two circles + triangle approximation of a heart
    local s = size * 0.5
    love.graphics.circle("fill", x - s*0.5, y, s * 0.65)
    love.graphics.circle("fill", x + s*0.5, y, s * 0.65)
    love.graphics.polygon("fill",
        x - s, y + s*0.2,
        x + s, y + s*0.2,
        x,     y + s*1.6)
end

function drawHUD(sw, sh)
    -- Level name bar
    local font   = love.graphics.getFont()
    local lvlTxt = "World " .. math.ceil(currentLevel/4) .. "-" .. ((currentLevel-1)%4+1) .. ": " .. Levels[currentLevel].name
    local barW   = font:getWidth(lvlTxt) + 20
    love.graphics.setColor(0, 0, 0, 0.55)
    love.graphics.rectangle("fill", 6, 6, barW, 22, 5, 5)
    love.graphics.setColor(1, 1, 0.5)
    love.graphics.print(lvlTxt, 16, 10)

    -- Per-player cards
    local cardW, cardH = 170, 36
    local yy = 36
    for _, p in ipairs(players) do
        if p then
            -- Card background
            love.graphics.setColor(0, 0, 0, 0.55)
            love.graphics.rectangle("fill", 6, yy, cardW, cardH, 5, 5)

            -- Player color stripe on left
            love.graphics.setColor(p.color[1], p.color[2], p.color[3])
            love.graphics.rectangle("fill", 6, yy, 5, cardH, 5, 0)

            -- Player label
            local label = "P" .. p.id
            if     p.eliminated then label = label .. " OUT"
            elseif p.won        then label = label .. " WIN"
            elseif p.dead       then label = label .. " ×"
            end
            love.graphics.setColor(1, 1, 1)
            love.graphics.print(label, 16, yy + 4)

            -- Hearts (lives)
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

            -- Coin icon + count
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
    love.graphics.setColor(0.6, 0.6, 0.6)
    love.graphics.printf("ESC to quit", 0, sh/2 + 80, sw, "center")
end

function drawLobby(sw, sh)
    love.graphics.setColor(0.05, 0.05, 0.15)
    love.graphics.rectangle("fill", 0, 0, sw, sh)

    if lobbyMode == "host" then
        love.graphics.setColor(1, 0.9, 0.1)
        love.graphics.printf("HOSTING", 0, sh/2 - 110, sw, "center")
        love.graphics.setColor(1, 1, 1)
        -- Show local IP hint
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
        -- Input box
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
    -- LÖVE doesn't have a direct IP API; best effort via UDP
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
            -- Host
            players = {}
            world   = World.new(Levels[1])
            camera  = Camera.new(world)
            particles = Particles.new()
            spawnEnemies(Levels[1])
            makeStars()
            currentLevel  = 1
            localPlayerId = 1
            isHost        = true
            players[1]    = Player.new(world, 1)
            net           = Network.newHost()
            lobbyMode     = "host"
            lobbyMsg      = "Waiting for players..."
            state         = "lobby"
        elseif key == "j" then
            lobbyMode  = "join"
            lobbyInput = ""
            lobbyMsg   = ""
            state      = "lobby"
        end
        return
    end

    if state == "lobby" then
        if lobbyMode == "host" then
            if key == "return" then
                -- Start the game, tell clients
                if net then net:broadcastLevel(currentLevel) end
                state = "playing"
            end
        else
            -- join mode: handle IP input
            if key == "return" then
                local ip = lobbyInput == "" and "127.0.0.1" or lobbyInput
                players    = {}
                world      = World.new(Levels[1])
                camera     = Camera.new(world)
                particles  = Particles.new()
                spawnEnemies(Levels[1])
                makeStars()
                currentLevel  = 1
                isHost        = false
                net           = Network.newClient(ip)
                lobbyMsg      = "Connecting to " .. ip .. "..."
            elseif key == "backspace" then
                lobbyInput = lobbyInput:sub(1, -2)
            end
        end
        return
    end

    if state == "game_over" then
        if key == "r" then
            if net then net:destroy(); net = nil end
            initSolo()
            state = "playing"
        end
        return
    end

    if state == "playing" then
        if key == "r" then
            if net then net:destroy(); net = nil end
            initSolo()
            state = "playing"
        end
    end
end

function love.textinput(t)
    if state == "lobby" and lobbyMode == "join" then
        -- Only allow IP characters
        if t:match("[%d%.]") then
            lobbyInput = lobbyInput .. t
        end
    end
end
