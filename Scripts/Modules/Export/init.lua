--[[
@version 1.3
@noindex
DM Ambiance Creator - Export Module Aggregator
v1.2: Story 3.2 - Added Export_Loop module for zero-crossing loop processing.
v1.3: Added Export_ConfigHistory module for ExtState-based export config persistence.
--]]

local Export = {}
local globals = {}

-- Get the module path for loading sub-modules
local info = debug.getinfo(1, "S")
local modulePath = info.source:match[[^@?(.*[\/])[^\/]-$]]

-- Load sub-modules
local Export_Settings = dofile(modulePath .. "Export_Settings.lua")
local Export_Engine = dofile(modulePath .. "Export_Engine.lua")
local Export_Placement = dofile(modulePath .. "Export_Placement.lua")
local Export_Loop = dofile(modulePath .. "Export_Loop.lua")
local Export_UI = dofile(modulePath .. "Export_UI.lua")
local Export_ConfigHistory = dofile(modulePath .. "Export_ConfigHistory.lua")

function Export.initModule(g)
    if not g then
        error("Export.initModule: globals parameter is required")
    end
    globals = g

    -- Initialize sub-modules
    Export_Settings.initModule(g)
    Export_Engine.initModule(g)
    Export_Placement.initModule(g)
    Export_Loop.initModule(g)
    Export_UI.initModule(g)
    Export_ConfigHistory.initModule(g)

    -- Wire dependencies
    Export_Engine.setDependencies(Export_Settings, Export_Placement, Export_Loop, Export_ConfigHistory)
    Export_Placement.setDependencies(Export_Settings, Export_Loop)
    Export_Loop.setDependencies(Export_Settings)
    Export_UI.setDependencies(Export_Settings, Export_Engine, Export_ConfigHistory)
end

-- Re-export main functions
Export.openModal = function()
    return Export_UI.openModal()
end

Export.renderModal = function()
    return Export_UI.renderModal()
end

Export.performExport = function()
    return Export_Engine.performExport()
end

Export.resetSettings = function()
    return Export_Settings.resetSettings()
end

-- Provide access to sub-modules for advanced usage
function Export.getSubModules()
    return {
        Settings = Export_Settings,
        Engine = Export_Engine,
        Placement = Export_Placement,
        Loop = Export_Loop,
        UI = Export_UI
    }
end

return Export
