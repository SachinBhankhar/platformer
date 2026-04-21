-- Host-authoritative LAN multiplayer using enet (bundled with LÖVE 11.4)
-- Host runs full simulation; clients send inputs, receive full state each frame.
local Network = {}
Network.__index = Network

local enet = require "enet"
local netmsg = require "netmsg"
local PORT = 6789
local TICK_RATE = 60  -- state broadcasts per second from host
local DISCOVERY_PORT = 6790

local pack       = netmsg.pack
local unpack_msg = netmsg.unpack

-- ── Constructor ──────────────────────────────────────────────────────────────

function Network.newHost()
    local self = setmetatable({}, Network)
    self.isHost   = true
    self.host     = enet.host_create("*:" .. PORT, 16)
    self.peers    = {}   -- peer -> player_id
    self.nextId   = 2    -- host is always player 1
    self.tickTimer = 0
    -- UDP broadcast socket for LAN discovery
    self.udpHost  = enet.host_create("*:" .. DISCOVERY_PORT, 4)
    print("[NET] Hosting on port " .. PORT)
    return self
end

function Network.newClient(ip)
    local self = setmetatable({}, Network)
    self.isHost   = false
    self.host     = enet.host_create()
    self.server   = self.host:connect(ip .. ":" .. PORT)
    self.myId     = nil   -- assigned by host on connect
    self.state    = nil   -- latest game state from host
    self.inputs   = {left=false,right=false,jump=false,run=false,jumpPressed=false}
    print("[NET] Connecting to " .. ip .. ":" .. PORT)
    return self
end

-- Discover hosts on LAN via UDP broadcast (returns list of IPs)
function Network.discover(timeout)
    timeout = timeout or 1.0
    local hosts = {}
    local sock = enet.host_create()
    -- broadcast probe
    local broadcaster = sock:connect("255.255.255.255:" .. DISCOVERY_PORT)
    broadcaster:send("DISCOVER", 0, "unreliable")
    local deadline = love.timer.getTime() + timeout
    while love.timer.getTime() < deadline do
        local event = sock:service(50)
        if event and event.type == "receive" and event.data:sub(1,4) == "HOST" then
            local ip = tostring(event.peer):match("^([^:]+)")
            hosts[ip] = true
        end
    end
    sock:destroy()
    local list = {}
    for ip in pairs(hosts) do list[#list+1] = ip end
    return list
end

-- ── Host update ──────────────────────────────────────────────────────────────

-- Call each frame. Returns list of {type, peer_or_id, data} events.
function Network:hostUpdate(dt, players, world, enemies, currentLevel)
    local events = {}

    -- Handle discovery broadcast
    if self.udpHost then
        local ev = self.udpHost:service(0)
        while ev do
            if ev.type == "receive" and ev.data == "DISCOVER" then
                ev.peer:send("HOST", 0, "unreliable")
            end
            ev = self.udpHost:service(0)
        end
    end

    -- Handle enet events. Wrap in pcall — service() can raise on an ungraceful
    -- peer disconnect or malformed packet, and we don't want that to crash the
    -- host mid-game (observed on level transitions).
    while true do
        local ok, ev = pcall(function() return self.host:service(0) end)
        if not ok then
            print("[NET] service error: " .. tostring(ev))
            break
        end
        if not ev then break end
        if ev.type == "connect" then
            local id = self.nextId
            self.nextId = self.nextId + 1
            self.peers[ev.peer] = id
            -- Tell new client their ID and current level
            ev.peer:send(pack({"JOIN", id, currentLevel}), 0, "reliable")
            events[#events+1] = {type="join", id=id, peer=ev.peer}
            print("[NET] Player " .. id .. " joined")
        elseif ev.type == "disconnect" then
            local id = self.peers[ev.peer]
            if id then
                events[#events+1] = {type="leave", id=id}
                self.peers[ev.peer] = nil
                print("[NET] Player " .. id .. " left")
            end
        elseif ev.type == "receive" then
            local ok2, d = pcall(unpack_msg, ev.data)
            if ok2 and d[1] == "INPUT" then
                local id = self.peers[ev.peer]
                events[#events+1] = {type="input", id=id, left=d[2]==1, right=d[3]==1, jump=d[4]==1, run=d[5]==1, jumpPressed=d[6]==1}
            end
        end
    end

    -- Broadcast state at tick rate
    self.tickTimer = self.tickTimer + dt
    if self.tickTimer >= 1/TICK_RATE then
        self.tickTimer = 0
        local msg = self:buildStateMsg(players, enemies, currentLevel)
        for peer, _ in pairs(self.peers) do
            peer:send(msg, 0, "unreliable")
        end
    end

    return events
end

function Network:buildStateMsg(players, enemies, currentLevel)
    local parts = {"STATE", currentLevel, #players}
    for _, p in ipairs(players) do
        parts[#parts+1] = p.id
        parts[#parts+1] = math.floor(p.x)
        parts[#parts+1] = math.floor(p.y)
        parts[#parts+1] = math.floor(p.vx)
        parts[#parts+1] = math.floor(p.vy)
        parts[#parts+1] = p.lives
        parts[#parts+1] = p.eliminated and 1 or 0
        parts[#parts+1] = p.dead and 1 or 0
        parts[#parts+1] = p.won and 1 or 0
        parts[#parts+1] = p.facing
        parts[#parts+1] = p.onGround and 1 or 0
        parts[#parts+1] = p.walkFrame
        parts[#parts+1] = p.coins
    end
    parts[#parts+1] = #enemies
    for _, e in ipairs(enemies) do
        parts[#parts+1] = e.id or 0
        parts[#parts+1] = math.floor(e.x)
        parts[#parts+1] = math.floor(e.y)
        parts[#parts+1] = e.dead and 1 or 0
        parts[#parts+1] = string.format("%.2f", e.deadTimer)
    end
    return pack(parts)
end

-- ── Client update ────────────────────────────────────────────────────────────

-- Returns events: {type="state", ...} or {type="join", id=N, level=N}
function Network:clientUpdate(dt, inputs)
    local events = {}

    -- Send inputs every frame. jumpPressed is edge-triggered for one frame,
    -- so send reliably on that edge — otherwise a single dropped UDP packet
    -- eats the jump and the client's prediction diverges from the host.
    if self.myId then
        local msg = pack({"INPUT", inputs.left, inputs.right, inputs.jump, inputs.run, inputs.jumpPressed})
        local chan = inputs.jumpPressed and "reliable" or "unreliable"
        self.server:send(msg, 0, chan)
    end

    while true do
        local ok, ev = pcall(function() return self.host:service(0) end)
        if not ok then
            print("[NET] service error: " .. tostring(ev))
            break
        end
        if not ev then break end
        if ev.type == "receive" then
            local ok2, d = pcall(unpack_msg, ev.data)
            if ok2 then
                if d[1] == "JOIN" then
                    self.myId = d[2]
                    events[#events+1] = {type="join", id=d[2], level=d[3]}
                    print("[NET] Assigned player ID " .. d[2])
                elseif d[1] == "STATE" then
                    events[#events+1] = {type="state", data=d}
                elseif d[1] == "LEVEL" then
                    events[#events+1] = {type="level", num=d[2]}
                elseif d[1] == "COIN" then
                    events[#events+1] = {type="coin", tx=d[2], ty=d[3]}
                end
            end
        elseif ev.type == "disconnect" then
            events[#events+1] = {type="disconnect"}
        end
    end

    return events
end

-- Broadcast a coin tile removal to all clients (host only)
function Network:broadcastCoinRemoval(tx, ty)
    local msg = pack({"COIN", tx, ty})
    for peer, _ in pairs(self.peers) do
        peer:send(msg, 0, "reliable")
    end
end

-- Broadcast level change to all clients (host only)
function Network:broadcastLevel(num)
    for peer, _ in pairs(self.peers) do
        peer:send(pack({"LEVEL", num}), 0, "reliable")
    end
end

function Network:destroy()
    if self.udpHost then self.udpHost:destroy() end
    if self.host then self.host:destroy() end
end

return Network
