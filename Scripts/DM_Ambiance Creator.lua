--[[
@description DM_Ambiance Creator
@version 0.17.13-beta
@about
    The Ambiance Creator is a tool that makes it easy to create soundscapes by randomly placing audio elements on the REAPER timeline according to user parameters.
@author Anthony Deneyer
@provides
    [nomain] Modules/*.lua
    [nomain] Modules/Audio/Generation/*.lua
    [nomain] Modules/Audio/Waveform/*.lua
    [nomain] Modules/Routing/*.lua
    [nomain] Modules/Utils/*.lua
    [nomain] Modules/UI/*.lua
    [nomain] Modules/Export/*.lua
    Icons/*.png
@changelog
  # Version 0.17.12-beta - Export Region Fix

  ## Bug Fixes
  * Fix: Regions not created for containers with per-container overrides (loop containers)
    - Override params froze createRegions=false from creation time, ignoring later global enable
    - Region creation now always uses the global createRegions setting

  # Version 0.17.9-beta - Noise Types (Ridged, Worley, Sine)

  ## New Features
  + Noise: Add Noise Type selector with 4 curve shapes
    - Perlin: Smooth organic curves (wind, rain, nature)
    - Ridged: Sharp peaks with calm valleys (thunder, bursts)
    - Worley: Cluster patterns with gaps (swarms, sporadic activity)
    - Sine: Perfectly periodic wave (rhythmic pulses, breathing)
  + Noise: Preview and generation both support all noise types

  # Version 0.17.8-beta - Noise Mode Resolution & Fixes

  ## New Features
  + Noise: Decouple resolution from frequency — new Resolution slider (1-100 samples/sec)
  + Noise: Add Placement Anchor option (Start→Start / End→Start) for overlap control
  + Noise: Hide Resolution slider in Accumulation mode (resolution-independent)
  + Noise: Normalize preview Y-axis so peaks reach top only at 100% density

  ## Bug Fixes
  * Fix: noiseAlgorithm not inherited from group to containers (preview/generation mismatch)
  * Fix: Curve formula mismatch between preview and generation algorithm
  * Fix: PROBABILITY density scaling with resolution (more items at higher resolution)
  * Fix: Replace Perlin decision noise with deterministic hash for uniform distribution
  * Fix: Preview average item length computed from actual items instead of hardcoded
  * Fix: noiseFrequency fallback default matching Constants

  ## Technical Changes
  + Add migration logic for pre-refactor presets (frequency scaling)
  + Remove /10.0 divisor from Noise module (compensated by adjusted default)

  # Version 0.17.7-beta - Keep Existing Tracks Fix & Generation Improvements

  ## New Features
  + Generation: Nest generated tracks inside selected parent track
  + Generation: Apply preset nesting to generated track hierarchy
  + MCP Remote execution support for Claude Code integration

  ## Bug Fixes
  * Fix: "Keep existing tracks" now preserves content outside time selection
    - Previously, regenerating at a new position would erase all existing items
    - Now only items within the current time selection are replaced
  * Fix: Renamed option to "Keep existing tracks and content" for clarity
  * Fix: Remove "Export - " prefix from export track names

  # Version 0.17.6-beta - Export Multichannel & Bug Fixes

  ## New Features
  + Export: Multichannel export mode selection (Flatten / Preserve)
    - Flatten: merge all channels to single track
    - Preserve: maintain Round-Robin/Random/All Tracks distribution
  + Export: Proper track hierarchy creation for multichannel containers
  + Export: Per-container error isolation with detailed reporting
  + Export: Loop interval auto-mode UI with container triggerRate support
  + Export: Zero-crossing loop processing for seamless loops
  + Export: Multi-channel preserve loop timestamp synchronization

  ## Bug Fixes
  * Fix: Suppress Generation view/state side effects during export
  * Fix: Multichannel export code review - refactor distribution logic
  * Fix: All Tracks mode now respects container interval setting
  * Fix: Multi-channel preserve loop sync with proper overlap handling
  * Fix: Export triggerRate inheritance for overrideParent=false containers

  # Version 0.16.1-beta - Export Region Creation

  ## New Features
  + Export: Add option to create REAPER regions during export
    - One region per container, spanning all exported items
    - Customizable region name pattern with tag system
    - Supported tags: $container, $group, $index
    - Example: "sfx_$container" → "sfx_Rain Drops"

  # Version 0.16.0-beta - Export Feature

  ## New Features
  + Export modal: Export generated items to timeline with custom settings
    - Control instance count and spacing
    - Choose to export on current track or new track
    - Preserve or reset pan, volume, and pitch settings
    - Multi-container selection support
--]]

-- Check if ReaImGui is available; display an error and exit if not
if not reaper.ImGui_CreateContext then
    reaper.MB("This script requires ReaImGui. Please install the extension via ReaPack.", "Error", 0)
    return
end

-- Proper initialization of ReaImGui as recommended by the developer
package.path = reaper.ImGui_GetBuiltinPath() .. '/?.lua'
local imgui = require 'imgui' '0.9.3'

-- Define the path for custom modules (relative to the script location)
local script_path = debug.getinfo(1, "S").source:match[[^@?(.*[\/])[^\/]-$]]
-- Add modules path so sub-modules can find each other
package.path = script_path .. "Modules/?.lua;" .. package.path

-- Import all project modules using dofile for better performance
local Constants = dofile(script_path .. "Modules/DM_Ambiance_Constants.lua")
local Utils = dofile(script_path .. "Modules/Utils/init.lua")
local Structures = dofile(script_path .. "Modules/DM_Ambiance_Structures.lua")
local Items = dofile(script_path .. "Modules/DM_Ambiance_Items.lua")
local Presets = dofile(script_path .. "Modules/DM_Ambiance_Presets.lua")
local Generation = dofile(script_path .. "Modules/Audio/Generation/init.lua")
local UI = dofile(script_path .. "Modules/DM_Ambiance_UI.lua")
local LinkedSliders = dofile(script_path .. "Modules/DM_Ambiance_UI_LinkedSliders.lua")
local Settings = dofile(script_path .. "Modules/DM_AmbianceCreator_Settings.lua")
local RoutingValidator = dofile(script_path .. "Modules/DM_Ambiance_RoutingValidator.lua")
local Waveform = dofile(script_path .. "Modules/Audio/Waveform/init.lua")
local History = dofile(script_path .. "Modules/DM_Ambiance_History.lua")
local UndoWrappers = dofile(script_path .. "Modules/DM_Ambiance_UndoWrappers.lua")
local UI_UndoHistory = dofile(script_path .. "Modules/DM_Ambiance_UI_UndoHistory.lua")
local Noise = dofile(script_path .. "Modules/DM_Ambiance_Noise.lua")
local SliderEnhanced = dofile(script_path .. "Modules/DM_Ambiance_UI_SliderEnhanced.lua")
local Knob = dofile(script_path .. "Modules/DM_Ambiance_UI_Knob.lua")
local FadeWidget = dofile(script_path .. "Modules/DM_Ambiance_UI_FadeWidget.lua")
local EuclideanUI = dofile(script_path .. "Modules/DM_Ambiance_UI_Euclidean.lua")
local RegenManager = dofile(script_path .. "Modules/DM_Ambiance_RegenManager.lua")
local Export = dofile(script_path .. "Modules/Export/init.lua")

-- New modular UI components
local UI_Core = dofile(script_path .. "Modules/DM_Ambiance_UI_Core.lua")
local UI_MainWindow = dofile(script_path .. "Modules/DM_Ambiance_UI_MainWindow.lua")
local UI_LeftPanel = dofile(script_path .. "Modules/DM_Ambiance_UI_LeftPanel.lua")
local UI_RightPanel = dofile(script_path .. "Modules/DM_Ambiance_UI_RightPanel.lua")
local UI_TriggerSection = dofile(script_path .. "Modules/DM_Ambiance_UI_TriggerSection.lua")
local UI_FadeSection = dofile(script_path .. "Modules/DM_Ambiance_UI_FadeSection.lua")
local UI_EuclideanSection = dofile(script_path .. "Modules/DM_Ambiance_UI_EuclideanSection.lua")
local UI_NoisePreview = dofile(script_path .. "Modules/DM_Ambiance_UI_NoisePreview.lua")
local UI_Folder = dofile(script_path .. "Modules/DM_Ambiance_UI_Folder.lua")
local UI_VolumeControls = dofile(script_path .. "Modules/DM_Ambiance_UI_VolumeControls.lua")

-- MCP Remote execution support (optional - allows Claude Code to control this script)
local MCPRemote
do
    local remotePath = reaper.GetResourcePath() .. "/Scripts/reaper-dev-mcp-remote.lua"
    local f = io.open(remotePath, "r")
    if f then
        f:close()
        MCPRemote = dofile(remotePath)
    end
end

-- Global state shared across modules and UI
local globals = {
    version = "0.17.10-beta",         -- Script version (sync with @version header)
    items = {},                       -- Stores all items (folders and groups at top-level) - PATH-BASED SYSTEM
    timeSelectionValid = false,       -- Indicates if a valid time selection exists in the project
    startTime = 0,                    -- Start time of the current time selection
    endTime = 0,                      -- End time of the current time selection
    timeSelectionLength = 0,          -- Length of the time selection
    currentPresetName = "",           -- Name of the currently loaded global preset
    presetsPath = "",                 -- Path to the presets directory

    -- Path-based selection system
    selectedPath = nil,               -- Path to the currently selected item (folder or group)
    selectedType = nil,               -- Type of selected item: "folder", "group", or nil
    selectedContainerIndex = nil,     -- Index of selected container within the group (if any)

    -- Multi-selection system
    selectedContainers = {},          -- Table of selected container keys for multi-selection
    inMultiSelectMode = false,        -- Flag indicating if multi-selection mode is active
    shiftAnchorPath = nil,            -- Path anchor for Shift+Click range selection
    shiftAnchorContainerIndex = nil,  -- Container index anchor for Shift+Click range selection

    selectedGroupPresetIndex = {},    -- Stores selected group preset indices for each group
    selectedContainerPresetIndex = {},-- Stores selected container preset indices for each container
    currentSaveGroupIndex = nil,      -- Index of the group currently being saved as a preset
    currentSaveContainerGroup = nil,  -- Index of the group for the container being saved
    currentSaveContainerIndex = nil,  -- Index of the container being saved as a preset
    newGroupPresetName = "",          -- Input field for new group preset name
    newContainerPresetName = "",      -- Input field for new container preset name
    newPresetName = "",               -- Input field for new global preset name
    selectedPresetIndex = -1,         -- Index of the currently selected global preset
    activePopups = {},                -- Table tracking active popup windows
    showMediaDirWarning = false,      -- Flag to display a warning if the media directory is not configured
    mediaWarningShown = false,        -- Prevents showing the media warning multiple times
    keepExistingTracks = true,        -- Default behavior for generation (changed from overrideExistingTracks)
    containerExpandedStates = {},     -- Stores expanded/collapsed states for container item lists to prevent auto-collapse
    
    -- Pending operations to avoid ImGui conflicts
    pendingGroupMove = nil,           -- Pending group reorder operation
    pendingContainerMove = nil,       -- Pending container move operation
    pendingContainerReorder = nil,    -- Pending container reorder within same group
    pendingContainerMultiMove = nil,  -- Pending multi-container move operation
    
    -- Drag and drop state
    draggedItem = nil,                -- Currently dragged item info

    -- UI window states
    showUndoHistoryWindow = false,    -- Flag to show/hide Undo History window
}

-- Main loop function for the GUI; called repeatedly via reaper.defer
local function loop()
    UI.PushStyle()

    -- Show the media directory warning popup ONLY if required
    if globals.showMediaDirWarning then
        Utils.showDirectoryWarningPopup()
    end

    -- Show routing validation modals
    RoutingValidator.renderModal()
    RoutingValidator.renderChannelOrderModal()

    -- Update waveform playback position if playing
    if globals.Waveform and globals.Waveform.updatePlaybackPosition then
        globals.Waveform.updatePlaybackPosition()
    end

    -- Process debounced gate detection requests
    if globals.Waveform and globals.Waveform.processGateDetectionDebounce then
        globals.Waveform.processGateDetectionDebounce()
    end

    -- Check for objects that need regeneration and regenerate them
    RegenManager.checkAndRegenerate()

    -- Render the main window; returns 'open' (true if window is open)
    local open = UI.ShowMainWindow(true)

    -- Show Undo History window if flagged
    if globals.showUndoHistoryWindow then
        globals.showUndoHistoryWindow = UI_UndoHistory.showWindow()
    end

    UI.PopStyle()

    -- Poll MCP Remote for incoming commands
    if MCPRemote then MCPRemote.poll() end

    -- Continue the loop if the window is still open
    if open then
        reaper.defer(loop)
    else
        -- Save settings on exit
        if globals.Settings and globals.Settings.saveSettings then
            globals.Settings.saveSettings()
        end

        -- Cleanup waveform resources on exit
        if globals.Waveform and globals.Waveform.cleanup then
            globals.Waveform.cleanup()
        end
    end
end

-- Script entry point when run directly (not as a module)
if select(2, reaper.get_action_context()) == debug.getinfo(1, 'S').source:sub(2) then
    -- Expose variables and modules globally for debugging and live tweaking
    _G.globals = globals
    _G.Constants = Constants
    _G.Utils = Utils
    _G.Structures = Structures
    _G.Items = Items
    _G.Presets = Presets
    _G.Generation = Generation
    _G.UI = UI
    _G.Settings = Settings
    _G.RoutingValidator = RoutingValidator
    _G.Waveform = Waveform
    _G.History = History
    _G.Noise = Noise
    _G.SliderEnhanced = SliderEnhanced
    _G.Knob = Knob
    _G.FadeWidget = FadeWidget
    _G.EuclideanUI = EuclideanUI
    _G.Export = Export
    _G.imgui = imgui

    -- Seed the random number generator for consistent randomization
    math.randomseed(os.time())

    -- Create the ImGui context for the application window
    local ctx = imgui.CreateContext('Ambiance Creator')
    globals.ctx = ctx
    globals.imgui = imgui

    -- Initialize fonts with default scale (will be updated when settings load)
    globals.scaledFont = nil
    globals.currentScale = 1.0

    -- Share module references through the globals table for cross-module access
    globals.Constants = Constants
    globals.Utils = Utils
    globals.Structures = Structures
    globals.Items = Items
    globals.Presets = Presets
    globals.Generation = Generation
    globals.UI = UI
    globals.Settings = Settings
    globals.RoutingValidator = RoutingValidator
    globals.Waveform = Waveform
    globals.History = History
    globals.UndoWrappers = UndoWrappers
    globals.UI_UndoHistory = UI_UndoHistory
    globals.Noise = Noise
    globals.LinkedSliders = LinkedSliders
    globals.SliderEnhanced = SliderEnhanced
    globals.Knob = Knob
    globals.FadeWidget = FadeWidget
    globals.EuclideanUI = EuclideanUI
    globals.RegenManager = RegenManager
    globals.Export = Export

    -- New modular UI components
    globals.UI_Core = UI_Core
    globals.UI_MainWindow = UI_MainWindow
    globals.UI_LeftPanel = UI_LeftPanel
    globals.UI_RightPanel = UI_RightPanel
    globals.UI_TriggerSection = UI_TriggerSection
    globals.UI_FadeSection = UI_FadeSection
    globals.UI_EuclideanSection = UI_EuclideanSection
    globals.UI_NoisePreview = UI_NoisePreview
    globals.UI_Folder = UI_Folder
    globals.UI_VolumeControls = UI_VolumeControls

    -- Initialize all modules with the shared globals table
    Utils.initModule(globals)
    Structures.initModule(globals)
    Items.initModule(globals)
    Presets.initModule(globals)
    Generation.initModule(globals)
    UI.initModule(globals)
    LinkedSliders.initModule(globals)
    Settings.initModule(globals)
    RoutingValidator.initModule(globals)
    Waveform.initModule(globals)
    History.initModule(globals)
    UndoWrappers.initModule(globals)
    UI_UndoHistory.initModule(globals)
    Noise.initModule(globals)
    SliderEnhanced.initModule(globals)
    Knob.initModule(globals)
    FadeWidget.initModule(globals)
    EuclideanUI.initModule(globals)
    RegenManager.initModule(globals)
    Export.initModule(globals)

    -- Initialize new modular UI components
    UI_Core.initModule(globals)
    UI_MainWindow.initModule(globals)
    UI_LeftPanel.initModule(globals)
    UI_RightPanel.initModule(globals)
    UI_TriggerSection.initModule(globals)
    UI_FadeSection.initModule(globals)
    UI_EuclideanSection.initModule(globals)
    UI_NoisePreview.initModule(globals)
    UI_Folder.initModule(globals)
    UI_VolumeControls.initModule(globals)

    -- Initialize MCP Remote execution (allows Claude Code to control this script)
    if MCPRemote then
        MCPRemote.init("ambiance-creator", _G, {
            name = "DM Ambiance Creator",
            description = "Soundscape generator - load presets, generate ambiances, manage groups/containers"
        })
    end

    -- Migrate old groups structure to new items structure (for old presets)
    -- Presets.lua may load data into globals.groups temporarily, which we migrate to globals.items
    if not globals.groups then
        globals.groups = {}
    end

    -- Initialize backward compatibility for container volumes
    Utils.initializeContainerVolumes()

    -- DON'T capture initial state - let the first change create the first snapshot
    -- This prevents duplicate states in the undo stack

    -- Start the main UI loop
    reaper.defer(loop)
end