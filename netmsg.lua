-- Serialization helpers shared by network.lua and tests
local M = {}

function M.pack(t)
    local parts = {}
    for _, v in ipairs(t) do
        parts[#parts+1] = type(v) == "boolean" and (v and "1" or "0") or tostring(v)
    end
    return table.concat(parts, "|")
end

function M.unpack(s)
    if s == "" then return {} end
    local t = {}
    for v in (s.."|"):gmatch("([^|]*)|") do
        local n = tonumber(v)
        t[#t+1] = n ~= nil and n or v
    end
    return t
end

return M
