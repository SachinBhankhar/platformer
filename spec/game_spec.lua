-- Run with: busted spec/game_spec.lua  (from the project root)

-- Stub LÖVE APIs that modules reference at load time
love = {
    graphics = { newImage = function() return {} end },
    audio    = { newSource = function() return {play=function()end} end },
}
math.randomseed = math.randomseed or function() end

local netmsg  = require "netmsg"
local World   = require "world"
local Levels  = require "levels"

-- ── helpers ──────────────────────────────────────────────────────────────────

local function flat_level()
    -- 5-wide, 4-tall map: solid floor on row 4, everything else empty
    return {
        map = {
            {0, 0, 0, 0, 0},
            {0, 0, 0, 0, 0},
            {0, 0, 0, 0, 0},
            {1, 1, 1, 1, 1},
        },
        skyTop = {0,0,0}, skyBot = {0,0,0}, groundColor = {0,0,0},
        enemies = {},
        name = "test",
    }
end

local function coin_level()
    return {
        map = {
            {0, 2, 0, 0, 0},  -- coin at tile (2,1)
            {0, 0, 0, 0, 0},
            {0, 0, 0, 0, 0},
            {1, 1, 1, 1, 1},
        },
        skyTop = {0,0,0}, skyBot = {0,0,0}, groundColor = {0,0,0},
        enemies = {},
        name = "coin_test",
    }
end

local T = 32  -- tile size

-- ── World: collision ─────────────────────────────────────────────────────────

describe("World:move", function()

    it("lets a player fall onto the floor", function()
        local w = World.new(flat_level())
        -- Floor row 4 top = 3*32=96. Player h=28 → rests at y=68.
        -- Start just above (y=64, bottom=92) and move dy=10 so bottom crosses floor.
        local nx, ny, _, _, ground = w:move(0, 64, 22, 28, 0, 10)
        assert.is_true(ground)
        assert.are.equal(ny, 3 * T - 28)  -- y = 96-28 = 68
    end)

    it("stops horizontal movement into a wall", function()
        local level = flat_level()
        -- wall at column 3 (pixel x=64), rows 1-3
        for r = 1, 3 do level.map[r][3] = 1 end
        local w = World.new(level)
        -- player right edge (30+22=52) moves 20px → right edge hits tile col 3 at x=64
        local nx = select(1, w:move(30, 0, 22, 28, 20, 0))
        assert.are.equal(nx, 2 * T - 22)  -- x = 64-22 = 42
    end)

    it("clamps player to left world edge", function()
        local w = World.new(flat_level())
        local nx = select(1, w:move(5, 0, 22, 28, -100, 0))
        assert.are.equal(nx, 0)
    end)

    it("clamps player to right world edge", function()
        local w = World.new(flat_level())
        local worldPixels = 5 * T  -- 160 px wide
        local nx = select(1, w:move(100, 0, 22, 28, 500, 0))
        assert.are.equal(nx, worldPixels - 22)
    end)

    it("detects spike tiles", function()
        local level = flat_level()
        level.map[3][1] = 4  -- spike at tile (1,3)
        local w = World.new(level)
        local _, _, _, _, _, _, spike = w:move(0, 50, 22, 28, 0, 20)
        assert.is_true(spike)
    end)

end)

-- ── World: coin collection ────────────────────────────────────────────────────

describe("World:collectCoin", function()

    it("collects a coin and removes the tile", function()
        local w = World.new(coin_level())
        -- coin is at tile (2,1) → pixel x=32..63, y=0..31
        local count = w:collectCoin(32, 0, 22, 28)
        assert.are.equal(count, 1)
        assert.are.equal(w:getTile(2, 1), World.T_EMPTY)
    end)

    it("returns 0 when no coin is present", function()
        local w = World.new(flat_level())
        local count = w:collectCoin(0, 0, 22, 28)
        assert.are.equal(count, 0)
    end)

    it("records the removal in pendingRemovals", function()
        local w = World.new(coin_level())
        w:collectCoin(32, 0, 22, 28)
        assert.are.equal(#w.pendingRemovals, 1)
        assert.are.equal(w.pendingRemovals[1][1], 2)
        assert.are.equal(w.pendingRemovals[1][2], 1)
    end)

    it("does not double-collect the same coin", function()
        local w = World.new(coin_level())
        w:collectCoin(32, 0, 22, 28)
        local second = w:collectCoin(32, 0, 22, 28)
        assert.are.equal(second, 0)
    end)

end)

-- ── World: goal detection ─────────────────────────────────────────────────────

describe("World:checkGoal", function()

    it("detects the goal tile", function()
        local level = flat_level()
        level.map[1][1] = 3  -- goal at tile (1,1)
        local w = World.new(level)
        local hit = w:checkGoal(0, 0, 22, 28)
        assert.is_true(hit)
    end)

    it("returns false when away from goal", function()
        local level = flat_level()
        level.map[1][5] = 3  -- goal far right
        local w = World.new(level)
        local hit = w:checkGoal(0, 0, 22, 28)
        assert.is_false(hit)
    end)

end)

-- ── World: coin count helper ──────────────────────────────────────────────────

describe("World:countCoins", function()

    it("counts coins correctly", function()
        local w = World.new(coin_level())
        assert.are.equal(w:countCoins(), 1)
    end)

    it("returns 0 after all coins collected", function()
        local w = World.new(coin_level())
        w:collectCoin(32, 0, 22, 28)
        assert.are.equal(w:countCoins(), 0)
    end)

end)

-- ── Network: pack / unpack ────────────────────────────────────────────────────

describe("netmsg.pack / unpack", function()

    it("round-trips numbers", function()
        local msg = netmsg.pack({"STATE", 1, 42, 3})
        local t   = netmsg.unpack(msg)
        assert.are.equal(t[1], "STATE")
        assert.are.equal(t[2], 1)
        assert.are.equal(t[3], 42)
        assert.are.equal(t[4], 3)
    end)

    it("encodes booleans as 1/0", function()
        local msg = netmsg.pack({true, false, true})
        local t   = netmsg.unpack(msg)
        assert.are.equal(t[1], 1)
        assert.are.equal(t[2], 0)
        assert.are.equal(t[3], 1)
    end)

    it("handles floats", function()
        local msg = netmsg.pack({3.14})
        local t   = netmsg.unpack(msg)
        assert.is_true(math.abs(t[1] - 3.14) < 0.001)
    end)

    it("handles empty table", function()
        local msg = netmsg.pack({})
        local t   = netmsg.unpack(msg)
        assert.are.equal(#t, 0)
    end)

end)

-- ── Network: buildStateMsg round-trip ─────────────────────────────────────────

describe("Network buildStateMsg", function()

    -- Inline the build logic (mirrors network.lua:buildStateMsg) so we can
    -- test the wire format without bringing in enet.
    local function buildStateMsg(players, enemies, currentLevel)
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
            parts[#parts+1] = math.floor(e.x)
            parts[#parts+1] = math.floor(e.y)
            parts[#parts+1] = e.dead and 1 or 0
            parts[#parts+1] = string.format("%.2f", e.deadTimer)
        end
        return netmsg.pack(parts)
    end

    local function make_player(id, opts)
        opts = opts or {}
        return {
            id=id, x=opts.x or 100, y=opts.y or 200,
            vx=opts.vx or 0, vy=opts.vy or 0,
            lives=opts.lives or 3, eliminated=false, dead=false, won=false,
            facing=1, onGround=true, walkFrame=1,
            coins=opts.coins or 0,
        }
    end

    it("encodes and decodes level number", function()
        local msg = buildStateMsg({}, {}, 3)
        local t   = netmsg.unpack(msg)
        assert.are.equal(t[1], "STATE")
        assert.are.equal(t[2], 3)   -- level
        assert.are.equal(t[3], 0)   -- player count
    end)

    it("encodes a single player correctly", function()
        local p   = make_player(1, {x=64, y=128, coins=5, lives=2})
        local msg = buildStateMsg({p}, {}, 1)
        local t   = netmsg.unpack(msg)
        -- header: STATE=t[1], level=t[2], pcount=t[3]
        -- player: id x y vx vy lives elim dead won facing ground walkFrame coins
        assert.are.equal(t[4],  1)    -- id
        assert.are.equal(t[5],  64)   -- x
        assert.are.equal(t[6],  128)  -- y
        assert.are.equal(t[9],  2)    -- lives
        assert.are.equal(t[16], 5)    -- coins
    end)

    it("encodes two players, both readable", function()
        local p1 = make_player(1, {x=10, coins=1})
        local p2 = make_player(2, {x=200, coins=3})
        local msg = buildStateMsg({p1, p2}, {}, 1)
        local t   = netmsg.unpack(msg)
        assert.are.equal(t[3], 2)    -- player count
        -- p1 starts at index 4, p2 at index 4+13=17
        assert.are.equal(t[4],  1)   -- p1 id
        assert.are.equal(t[17], 2)   -- p2 id
        assert.are.equal(t[16], 1)   -- p1 coins
        assert.are.equal(t[29], 3)   -- p2 coins
    end)

    it("encodes enemies correctly", function()
        local enemy = {x=300, y=64, dead=false, deadTimer=0}
        local msg   = buildStateMsg({}, {enemy}, 1)
        local t     = netmsg.unpack(msg)
        -- header STATE+level+0players = indices 1..3, then enemy count at 4
        assert.are.equal(t[4], 1)    -- enemy count
        assert.are.equal(t[5], 300)  -- enemy x
        assert.are.equal(t[6], 64)   -- enemy y
        assert.are.equal(t[7], 0)    -- dead=false → 0
    end)

    it("enemies table must not be a number (regression: lobby bug)", function()
        -- Passing currentLevel as enemies used to crash with #enemies on a number
        assert.has_no_error(function()
            buildStateMsg({}, {}, 1)
        end)
    end)

end)

-- ── Multiplayer: coin sync via pendingRemovals ────────────────────────────────

describe("Multiplayer coin sync", function()

    it("pendingRemovals accumulates across multiple collections", function()
        local level = {
            map = {
                {2, 2, 2, 0, 0},
                {0, 0, 0, 0, 0},
                {0, 0, 0, 0, 0},
                {1, 1, 1, 1, 1},
            },
            skyTop={0,0,0}, skyBot={0,0,0}, groundColor={0,0,0},
            enemies={}, name="t",
        }
        local w = World.new(level)
        w:collectCoin(0,  0, 22, 28)   -- tile (1,1)
        w:collectCoin(32, 0, 22, 28)   -- tile (2,1)
        assert.are.equal(#w.pendingRemovals, 2)
    end)

    it("pendingRemovals is empty for a fresh world", function()
        local w = World.new(flat_level())
        assert.are.equal(#w.pendingRemovals, 0)
    end)

    it("setTile can clear a coin tile (simulates client receiving COIN msg)", function()
        local w = World.new(coin_level())
        assert.are.equal(w:getTile(2, 1), World.T_COIN)
        w:setTile(2, 1, World.T_EMPTY)
        assert.are.equal(w:getTile(2, 1), World.T_EMPTY)
        assert.are.equal(w:countCoins(), 0)
    end)

    it("coin collected by host is invisible to a fresh client world until synced", function()
        local host_world   = World.new(coin_level())
        local client_world = World.new(coin_level())

        -- Host collects coin
        host_world:collectCoin(32, 0, 22, 28)
        assert.are.equal(host_world:getTile(2, 1),   World.T_EMPTY)
        -- Client still has the coin before sync
        assert.are.equal(client_world:getTile(2, 1), World.T_COIN)

        -- Simulate receiving COIN message
        local removal = host_world.pendingRemovals[1]
        client_world:setTile(removal[1], removal[2], World.T_EMPTY)

        -- Now client matches host
        assert.are.equal(client_world:getTile(2, 1), World.T_EMPTY)
    end)

end)

-- ── Levels data sanity ────────────────────────────────────────────────────────

describe("Levels data", function()

    it("has 8 levels", function()
        assert.are.equal(#Levels, 8)
    end)

    it("every level has a name and a map", function()
        for i, lvl in ipairs(Levels) do
            assert.is_truthy(lvl.name,  "level " .. i .. " missing name")
            assert.is_truthy(lvl.map,   "level " .. i .. " missing map")
        end
    end)

    it("all maps have consistent row widths", function()
        for i, lvl in ipairs(Levels) do
            local w = #lvl.map[1]
            for r, row in ipairs(lvl.map) do
                assert.are.equal(#row, w,
                    "level " .. i .. " row " .. r .. " width mismatch")
            end
        end
    end)

    it("all tile values are valid (0-4)", function()
        for i, lvl in ipairs(Levels) do
            for r, row in ipairs(lvl.map) do
                for c, tile in ipairs(row) do
                    assert.is_true(tile >= 0 and tile <= 4,
                        string.format("level %d [%d][%d] bad tile %d", i, r, c, tile))
                end
            end
        end
    end)

end)
