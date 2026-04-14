--[[
@version 1.0
@noindex
DM Ambiance Creator - Export Config History Module
Persists export configurations to REAPER ExtState with automatic deduplication.
Provides history browsing and recall for the Export modal.
--]]

local M = {}
local globals = {}

local EXTSTATE_SECTION = "DM_Ambiance_Export"
local EXTSTATE_KEY = "configHistory"
local MAX_HISTORY = 20

-- In-memory cache of config history (loaded once on init)
local configHistory = {}  -- Array of config entries, sorted newest first

-- Helper: Serialize a table into a Lua string (same pattern as Presets module)
local function serializeTable(val, name, depth)
    depth = depth or 0
    local indent = string.rep("  ", depth)
    local result = ""

    if name then result = indent .. name .. " = " end

    if type(val) == "table" then
        result = result .. "{\n"
        for k, v in pairs(val) do
            local key
            if type(k) == "number" then
                key = "[" .. k .. "]"
            elseif type(k) == "string" then
                if k:match("^[%a_][%w_]*$") then
                    key = k
                else
                    key = "[" .. string.format("%q", k) .. "]"
                end
            else
                key = "[" .. tostring(k) .. "]"
            end
            result = result .. serializeTable(v, key, depth + 1) .. ",\n"
        end
        result = result .. indent .. "}"
    elseif type(val) == "number" then
        result = result .. tostring(val)
    elseif type(val) == "string" then
        result = result .. string.format("%q", val)
    elseif type(val) == "boolean" then
        result = result .. (val and "true" or "false")
    else
        result = result .. "nil"
    end

    return result
end

-- Helper: Deserialize history string from ExtState
-- Uses sandboxed load() with empty environment to prevent code execution
local function deserializeHistory(str)
    if not str or str == "" then return {} end
    local fn, err = load("return " .. str, "config", "t", {})
    if not fn then
        reaper.ShowConsoleMsg("[Export ConfigHistory] Deserialize error: " .. tostring(err) .. "\n")
        return {}
    end
    local ok, result = pcall(fn)
    if not ok or type(result) ~= "table" then
        reaper.ShowConsoleMsg("[Export ConfigHistory] Invalid history data\n")
        return {}
    end
    return result
end

-- Helper: Deep compare two tables (recursive)
local function deepCompare(a, b)
    if type(a) ~= type(b) then return false end
    if type(a) ~= "table" then return a == b end

    -- Check all keys in a exist in b with same values
    for k, v in pairs(a) do
        if not deepCompare(v, b[k]) then return false end
    end
    -- Check b doesn't have extra keys
    for k in pairs(b) do
        if a[k] == nil then return false end
    end
    return true
end

-- Helper: Persist configHistory to REAPER ExtState
local function persistToExtState()
    local serialized = serializeTable(configHistory, nil, 0)
    reaper.SetExtState(EXTSTATE_SECTION, EXTSTATE_KEY, serialized, true)
end

-- Helper: Load configHistory from REAPER ExtState
local function loadFromExtState()
    if reaper.HasExtState(EXTSTATE_SECTION, EXTSTATE_KEY) then
        local str = reaper.GetExtState(EXTSTATE_SECTION, EXTSTATE_KEY)
        configHistory = deserializeHistory(str)
        -- Validate entries
        local valid = {}
        for _, entry in ipairs(configHistory) do
            if type(entry) == "table" and entry.presetName and entry.timestamp and entry.globalParams then
                table.insert(valid, entry)
            end
        end
        configHistory = valid
    else
        configHistory = {}
    end
end

function M.initModule(g)
    if not g then
        error("Export_ConfigHistory.initModule: globals parameter is required")
    end
    globals = g
    loadFromExtState()
end

-- Save a config to history after successful export
-- Deduplicates: if same presetName has identical globalParams+containerOverrides, update timestamp only
function M.saveConfig(globalParams, containerOverrides, enabledContainers)
    if not globalParams then return end

    -- Determine preset name
    local presetName = globals.currentPresetName
    if not presetName or presetName == "" then
        presetName = "Export"
    end

    local timestamp = os.date("%Y-%m-%d %H:%M")

    -- Check deduplication: scan all entries for identical params (any preset name)
    for i, entry in ipairs(configHistory) do
        if entry.presetName == presetName then
            local sameGlobal = deepCompare(globalParams, entry.globalParams)
            local sameOverrides = deepCompare(containerOverrides or {}, entry.containerOverrides or {})
            if sameGlobal and sameOverrides then
                -- Duplicate: update timestamp and move to top
                entry.timestamp = timestamp
                entry.enabledContainers = enabledContainers or {}
                table.remove(configHistory, i)
                table.insert(configHistory, 1, entry)
                persistToExtState()
                return
            end
        end
    end

    -- New entry
    local newEntry = {
        presetName = presetName,
        timestamp = timestamp,
        globalParams = globalParams,
        containerOverrides = containerOverrides or {},
        enabledContainers = enabledContainers or {},
    }

    table.insert(configHistory, 1, newEntry)

    -- Trim to MAX_HISTORY
    while #configHistory > MAX_HISTORY do
        table.remove(configHistory)
    end

    persistToExtState()
end

-- Get the full config history list (sorted newest first)
function M.getConfigList()
    return configHistory
end

-- Get a specific config entry by index (1-based)
function M.getConfig(index)
    return configHistory[index]
end

-- Get the most recent config entry
function M.getLatestConfig()
    return configHistory[1]
end

-- Get the number of config entries
function M.getConfigCount()
    return #configHistory
end

return M
