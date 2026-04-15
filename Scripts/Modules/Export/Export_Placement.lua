--[[
@version 1.21
@noindex
DM Ambiance Creator - Export Placement Module
Handles track resolution, item placement helpers, and export track management.
Migrated from Export_Core.lua (makeItemKey, createExportTrack, findTrackByName, getChildTracks, getTargetTracks).
v1.2: Story 2.1 - Full resolvePool() implementation with PoolEntry format and Fisher-Yates shuffle.
      placeContainerItems() updated to use PoolEntry objects directly.
v1.3: Story 3.1 - Added loop mode support with loopInterval and loopDuration in placeContainerItems.
      Code review fix: Use LOOP_MAX_ITERATIONS constant, added loop overshoot documentation.
v1.4: Story 4.1 - Added startPosition parameter and endPosition return for sequential container placement.
      Enables batch export without overlap between containers.
v1.5: Code review fixes - startPosition validation, improved return value documentation.
v1.6: Story 4.1 fix - In autoloop mode, use container.triggerRate for overlap instead of export loopInterval.
v1.7: Story 4.3 - Added missing source file detection with reaper.file_exists() check.
      Throws error with file path if source file is missing for pcall isolation in Export_Engine.
v1.8: Code review fixes - Nil filePath now throws error instead of silent skip, error() uses level 0
      for cleaner UI display without file:line prefix.
v1.9: Story 4.4 - Fixed effectiveInterval logic to properly support auto-mode semantics.
      loopInterval=0 means auto-mode (use container.triggerRate), non-zero overrides all containers.
v1.10: Story 5.1 - Export now creates proper track hierarchy (folder + channel tracks) for multichannel
       containers. Uses Generation_TrackManagement.createMultiChannelTracks() for consistency.
       Handles GUID fallback when tracks don't exist. Stores GUIDs after track creation.
v1.11: Code review fixes - Removed dead needsTrackHierarchy(), suppressed Generation view/state
       side effects during export, eliminated redundant analysis via trackStructure passthrough,
       consistent "Export -" naming for multichannel folders, defensive checks for Generation API.
v1.12: Story 5.2 - Multichannel export mode: Flatten restricts to first child track,
       Preserve distributes via Round-Robin/Random/All Tracks matching Generation engine.
v1.13 (2026-02-07): Story 5.3 - placeContainerItems() now returns effectiveInterval as third return value.
       Enables Export_Loop to maintain consistent overlap after split/swap for seamless loops.
v1.14 (2026-02-07): Story 5.6 - Fix Multi-Channel Preserve Loop - Synchronize Track Timestamps
       - Added syncMultiChannelLoopTracks() to align start/end timestamps across all tracks
       - Overfill phase: fills tracks to 110% (or based on abs(effectiveInterval)) for repositioning
       - Timestamp detection: finds earliest start and latest end across all tracks
       - Item shifting: aligns all tracks to synchronized start position
       - Split & swap: uses zero-crossing from Story 3.2 to split excess items and move to beginning
       - Integration: auto-detects multi-channel preserve loop mode and applies sync
       - Ensures seamless loop export for all channels in surround configurations
v1.15 (2026-02-07): Story 5.6 CODE REVIEW FIXES - Critical bugs in sync algorithm
       - CRITICAL FIX #1: Added track extension logic for tracks ending before targetEnd
         Previously only split tracks that exceeded targetEnd, leaving short tracks misaligned
         Now duplicates items from track beginning to fill gap when track ends early
       - CRITICAL FIX #2: Improved overfill calculation based on max item length in pool
         Previously used fixed 5-10% overfill, insufficient for variable item lengths
         Now calculates overfill as max(10%, maxItemLength/targetDuration) to guarantee all tracks overshoot
       - HIGH FIX #3: Removed early exit for single-item tracks (#trackItems < 2)
         Now handles single-item tracks correctly with shift and extension/split logic
       - MEDIUM FIX: Added comprehensive debug logging (enabled via globals.debugExport)
         Logs overfill calculation, sync bounds detection, per-track operations for troubleshooting
       - Fixes misalignment bug where multi-channel tracks don't start/end at same timestamps
v1.16 (2026-02-08): Story 5.6 CODE REVIEW v2 FIXES - Philosophy change: trim replaces split/swap
       - R1 CRITICAL: Fixed split/wrap positioning in syncMultiChannelLoopTracks
         Old splitAndSwap placed rightPart at (firstItemPos - rightPartLen - interval) → different starts
         Fix: split at zero-crossing near targetEnd, move rightPart to EXACTLY targetStart
         All tracks start at same position AND loop seamlessly (split item wraps at zero-crossing)
       - R2 CRITICAL: placeContainerItems() now returns 4th value (syncApplied flag)
         Allows Export_Engine to skip processLoop() when multi-channel sync already applied
       - R3 CRITICAL: Fixed extension phase self-referencing trackItems
         Captured originalTrackItemCount before extension loop to prevent infinite growth of wrap condition
       - R5 MEDIUM: Fixed trackEnd calculation after extension phase
         Now uses actual last item end position instead of next placement position (currentExtendPos)
       - Deleted items cleaned up from placedItems array before return
v1.17 (2026-02-08): Story 5.6 BUG FIX - Export_Loop dependency was never wired
       - ROOT CAUSE: globals.Export_Loop was nil because init.lua never passed Export_Loop
         to Export_Placement.setDependencies(). The split/wrap code always fell to trim fallback.
       - FIX: Added Export_Loop as module-level dependency via setDependencies(settings, loop)
       - Updated init.lua to pass Export_Loop: setDependencies(Export_Settings, Export_Loop)
       - syncMultiChannelLoopTracks() now uses module-level Loop variable instead of globals.Export_Loop
v1.18 (2026-02-08): Story 5.6 FIX - Trim first items after rightPart wrap
       - PROBLEM: rightPart placed at targetStart overlapped fully with existing first items
         Standard splitAndSwap places rightPart BEFORE firstItem (at firstItemPos - rightPartLen - interval)
         but multi-channel sync places at targetStart (same position as firstItem) → full superposition
       - FIX: After wrapping rightPart(s), trim existing first item from the left so that
         overlap matches effectiveInterval. Formula: requiredFirstItemStart = targetStart + rightPartLen + effectiveInterval
       - Handles edge case: if rightPartLen + effectiveInterval >= firstItem.length, delete item entirely
v1.19 (2026-02-08): Story 5.5 - Fix export interval inheritance for Round-Robin/Random
       - INVESTIGATION: Per-track independent positioning was implemented and tested but
         REVERTED — Generation engine itself uses shared position counter for round-robin,
         creating a staggered pattern. Export must match this behavior, not fix it independently.
       - PROBLEM: Export used raw container.triggerRate/intervalMode without inheritance
         When container.overrideParent=false, generation inherits from group but export
         used the container's default values (10.0s), causing interval mismatch
       - FIX: Added inheritance resolution matching Structures.getEffectiveContainerParams()
         Now uses group.triggerRate/intervalMode when container doesn't override
       - Added documentation comment on placeItemsStandardMode explaining shared position design
v1.20: Bug fix - resolvePool() now reads item.areas (source of truth) first, falls back to
       globals.waveformAreas (UI cache). Previously only checked globals.waveformAreas which is
       ephemeral and only populated when the user views the waveform in the UI, causing export
       to ignore areas and use the full item instead.
v1.21: Reverted v1.21-draft global params override for loop settings. Loop mode settings
       (loopMode, loopDuration, loopInterval) correctly use effective params (per-container
       override or global) so users can set loopMode per container via overrides.
--]]

local M = {}
local globals = {}
local Settings = nil
local Loop = nil

function M.initModule(g)
    if not g then
        error("Export_Placement.initModule: globals parameter is required")
    end
    globals = g
end

function M.setDependencies(settings, loop)
    Settings = settings
    Loop = loop
end

-- Helper: Make item key for waveformAreas lookup
function M.makeItemKey(path, containerIndex, itemIndex)
    if globals.Structures and globals.Structures.makeItemKey then
        return globals.Structures.makeItemKey(path, containerIndex, itemIndex)
    end
    -- Fallback (replicate Structures logic with comma)
    local pathStr = table.concat(path, ",")
    return pathStr .. "::" .. containerIndex .. "::" .. itemIndex
end

-- Helper: Create a new track for export (simple flat track)
-- Used only for stereo containers that don't need hierarchy
function M.createExportTrack(containerInfo, channelIndex)
    local trackCount = reaper.CountTracks(0)
    reaper.InsertTrackAtIndex(trackCount, false)
    local newTrack = reaper.GetTrack(0, trackCount)

    local trackName = containerInfo.container.name
    if channelIndex then
        local label = ""
        local mode = containerInfo.container.channelMode or 0
        local config = globals.Constants and globals.Constants.CHANNEL_CONFIGS[mode]
        if config and config.labels then
            label = " (" .. (config.labels[channelIndex] or channelIndex) .. ")"
        else
            label = " (Ch " .. channelIndex .. ")"
        end
        trackName = trackName .. label
    end
    reaper.GetSetMediaTrackInfo_String(newTrack, "P_NAME", trackName, true)

    return newTrack
end

-- Helper: Create track hierarchy for multichannel containers
-- Uses Generation engine's createMultiChannelTracks for consistency with generation
-- @param containerInfo table: Container info from collectAllContainers
-- @param trackStructure table: Pre-computed track structure from resolveTrackStructure
-- @return table: Array of channel tracks (or single track for stereo)
function M.createExportTrackHierarchy(containerInfo, trackStructure)
    local container = containerInfo.container

    -- Check if Generation module is available (all required sub-functions)
    if not globals.Generation
       or not globals.Generation.createMultiChannelTracks
       or not globals.Generation.analyzeContainerItems
       or not globals.Generation.determineTrackStructure then
        -- Fallback to simple track creation
        local track = M.createExportTrack(containerInfo)
        return {track}
    end

    -- For single track (stereo with stereo items), create simple track
    if trackStructure.numTracks == 1 then
        local track = M.createExportTrack(containerInfo)
        -- Set channel count to match requirements
        local requiredChannels = trackStructure.trackChannels or 2
        if requiredChannels % 2 == 1 then
            requiredChannels = requiredChannels + 1
        end
        reaper.SetMediaTrackInfo_Value(track, "I_NCHAN", requiredChannels)

        -- Store GUID for future exports
        container.trackGUID = reaper.GetTrackGUID(track)
        container.channelTrackGUIDs = nil

        return {track}
    end

    -- Create folder track for multichannel container
    local trackCount = reaper.CountTracks(0)
    reaper.InsertTrackAtIndex(trackCount, false)
    local folderTrack = reaper.GetTrack(0, trackCount)

    -- Name the folder track
    reaper.GetSetMediaTrackInfo_String(folderTrack, "P_NAME",
        (container.name or "Container"), true)

    -- Suppress Generation-specific side effects during export:
    -- 1. View zoom commands (inappropriate during export)
    -- 2. Container state mutation (previousChannelMode tracking)
    local savedPreviousChannelMode = container.previousChannelMode
    globals.suppressViewRefresh = true

    -- Use Generation's createMultiChannelTracks to create the hierarchy
    -- This handles all the complexity: track structure analysis, routing, folder depth
    local channelTracks = globals.Generation.createMultiChannelTracks(folderTrack, container, false)

    globals.suppressViewRefresh = nil
    container.previousChannelMode = savedPreviousChannelMode

    -- GUIDs are already stored by createMultiChannelTracks via storeTrackGUIDs

    return channelTracks
end

-- Helper: Find track by name (fallback when GUID unavailable)
function M.findTrackByName(groupName, containerName)
    local trackCount = reaper.CountTracks(0)
    for i = 0, trackCount - 1 do
        local track = reaper.GetTrack(0, i)
        local _, trackName = reaper.GetTrackName(track)
        -- Match "ContainerName" or "GroupName - ContainerName"
        if trackName == containerName or
           trackName == (groupName .. " - " .. containerName) then
            return track
        end
    end
    return nil
end

-- Helper: Get child tracks of a folder track
function M.getChildTracks(folderTrack)
    local children = {}
    if not folderTrack then return children end

    local folderIdx = reaper.GetMediaTrackInfo_Value(folderTrack, "IP_TRACKNUMBER") - 1
    local trackCount = reaper.CountTracks(0)
    local depth = 1

    for i = folderIdx + 1, trackCount - 1 do
        local track = reaper.GetTrack(0, i)
        local trackDepth = reaper.GetMediaTrackInfo_Value(track, "I_FOLDERDEPTH")

        -- Stop when we exit the folder (depth goes back to same level or higher)
        if depth <= 0 then break end

        local parent = reaper.GetParentTrack(track)
        if parent == folderTrack then
            table.insert(children, track)
        end

        depth = depth + trackDepth
    end

    return children
end

-- Helper: Get target tracks for export (handles multi-channel)
-- Story 5.1: Creates proper track hierarchy using Generation engine for consistency
-- @param containerInfo table: Container info from collectAllContainers
-- @param trackStructure table: Pre-computed track structure from resolveTrackStructure
-- @param params table: Export params with exportMethod
-- @return table: Array of target tracks
function M.resolveTargetTracks(containerInfo, trackStructure, params)
    local tracks = {}
    local container = containerInfo.container
    local groupName = containerInfo.group and containerInfo.group.name or ""
    local containerName = container.name or ""

    if params.exportMethod == 1 then  -- New Track
        -- Story 5.1: Use track hierarchy creation for proper multichannel support
        -- This delegates to Generation engine for consistent track structure
        tracks = M.createExportTrackHierarchy(containerInfo, trackStructure)

    else  -- Current Track (exportMethod == 0)
        local foundValidTracks = false

        -- Strategy 1: Try channelTrackGUIDs for multi-channel
        if container.channelTrackGUIDs and #container.channelTrackGUIDs > 0 then
            local allTracksFound = true
            local guidTracks = {}

            for _, guid in ipairs(container.channelTrackGUIDs) do
                local track = reaper.BR_GetMediaTrackByGUID(0, guid)
                if track then
                    table.insert(guidTracks, track)
                else
                    -- At least one GUID points to non-existent track
                    allTracksFound = false
                    break
                end
            end

            if allTracksFound and #guidTracks > 0 then
                tracks = guidTracks
                foundValidTracks = true
            end
            -- Story 5.1 AC#3: If GUIDs point to non-existent tracks, fall through to create hierarchy
        end

        -- Strategy 2: Try trackGUID for single track or folder
        if not foundValidTracks and container.trackGUID then
            local track = reaper.BR_GetMediaTrackByGUID(0, container.trackGUID)
            if track then
                -- Check if it's a folder track with children
                local folderDepth = reaper.GetMediaTrackInfo_Value(track, "I_FOLDERDEPTH")
                if folderDepth == 1 then
                    -- It's a folder, get child tracks
                    tracks = M.getChildTracks(track)
                    if #tracks > 0 then
                        foundValidTracks = true
                    end
                end

                -- If no children found or it's not a folder, use the track itself
                if #tracks == 0 then
                    table.insert(tracks, track)
                    foundValidTracks = true
                end
            end
            -- Story 5.1 AC#3: If trackGUID points to non-existent track, fall through
        end

        -- Strategy 3: Fallback to name search
        if not foundValidTracks then
            local track = M.findTrackByName(groupName, containerName)
            if track then
                -- Check if it's a folder track with children
                local folderDepth = reaper.GetMediaTrackInfo_Value(track, "I_FOLDERDEPTH")
                if folderDepth == 1 then
                    -- It's a folder, get child tracks
                    tracks = M.getChildTracks(track)
                    if #tracks > 0 then
                        foundValidTracks = true
                    end
                end

                -- If no children found or it's not a folder, use the track itself
                if #tracks == 0 then
                    table.insert(tracks, track)
                    foundValidTracks = true
                end
            end
        end

        -- Strategy 4: Ultimate fallback - create proper track hierarchy
        -- Story 5.1 AC#3: Creates hierarchy instead of simple flat tracks
        if not foundValidTracks then
            tracks = M.createExportTrackHierarchy(containerInfo, trackStructure)
        end
    end

    return tracks
end

-- Fisher-Yates shuffle (in-place, returns same array)
-- @param arr table: Array to shuffle
-- @return table: The same array, shuffled in place
function M.shuffleArray(arr)
    local n = #arr
    for i = n, 2, -1 do
        local j = math.random(1, i)
        arr[i], arr[j] = arr[j], arr[i]
    end
    return arr
end

-- Resolve pool subset for export with random selection
-- Returns array of PoolEntry objects: { item, area, itemIdx, itemKey }
-- @param containerInfo table: Container info from collectAllContainers
-- @param maxPoolItems number: Maximum items to return (0 = all)
-- @return table: Array of PoolEntry objects
function M.resolvePool(containerInfo, maxPoolItems)
    -- Defensive nil-check for containerInfo
    if not containerInfo or not containerInfo.container then
        return {}
    end

    local allEntries = {}

    -- Iterate all items in container
    for itemIdx, item in ipairs(containerInfo.container.items or {}) do
        local itemKey = M.makeItemKey(containerInfo.path, containerInfo.containerIndex, itemIdx)

        -- Use item.areas (source of truth) first, fall back to globals.waveformAreas (UI cache)
        local areas = item.areas
        if not areas or #areas == 0 then
            areas = globals.waveformAreas and globals.waveformAreas[itemKey]
        end

        if areas and #areas > 0 then
            -- Create entry for each waveform area
            for _, area in ipairs(areas) do
                table.insert(allEntries, {
                    item = item,
                    area = area,
                    itemIdx = itemIdx,
                    itemKey = itemKey
                })
            end
        else
            -- No waveform areas: treat full item as single area
            table.insert(allEntries, {
                item = item,
                area = {
                    startPos = 0,
                    endPos = item.length or 10,
                    name = item.name or "Full"
                },
                itemIdx = itemIdx,
                itemKey = itemKey
            })
        end
    end

    -- Return all entries if maxPoolItems is 0 or >= total entries
    if maxPoolItems == 0 or maxPoolItems >= #allEntries then
        return allEntries
    end

    -- Random subset selection using Fisher-Yates shuffle
    -- NOTE: math.randomseed() is called once in Export_Engine.performExport()
    local shuffled = M.shuffleArray(allEntries)
    local subset = {}
    for i = 1, maxPoolItems do
        subset[i] = shuffled[i]
    end
    return subset
end

-- Build ItemData object for placeSingleItem
-- @param item table: Source item from container
-- @param area table: Area within the item (startPos, endPos, name)
-- @return table: ItemData object compatible with Generation.placeSingleItem
function M.buildItemData(item, area)
    return {
        filePath = item.filePath,
        name = area.name or item.name or "Exported",
        startOffset = area.startPos,
        length = area.endPos - area.startPos,
        originalPitch = item.originalPitch or 0,
        originalVolume = item.originalVolume or 1.0,
        originalPan = item.originalPan or 0,
        gainDB = item.gainDB or 0.0,
        numChannels = item.numChannels or 2
    }
end

-- Build genParams object for placeSingleItem
-- Copies container settings but overrides randomization based on preserve flags
-- @param params table: Effective params from Settings.getEffectiveParams
-- @param containerInfo table: Container info with container and group
-- @return table: genParams object compatible with Generation.placeSingleItem
function M.buildGenParams(params, containerInfo)
    local container = containerInfo.container
    local genParams = {}

    -- Copy all container properties
    for k, v in pairs(container) do
        genParams[k] = v
    end

    -- Override randomization flags based on preserve settings
    -- If preserve is TRUE, we allow the container's randomization
    -- If preserve is FALSE, we force randomization to FALSE (flatten)
    genParams.randomizePitch = container.randomizePitch and params.preservePitch
    genParams.randomizeVolume = container.randomizeVolume and params.preserveVolume
    genParams.randomizePan = container.randomizePan and params.preservePan

    -- When preserve is FALSE, also flatten the base values to neutral defaults
    -- This prevents baked-in randomization from imported items from leaking through
    -- (e.g., items imported from timeline may have non-neutral originalVolume/Pitch/Pan)
    genParams.flattenPitch = not params.preservePitch
    genParams.flattenVolume = not params.preserveVolume
    genParams.flattenPan = not params.preservePan

    return genParams
end

-- Calculate timeline position for item placement
-- Handles alignToSeconds rounding
-- @param currentPos number: Current timeline position in seconds
-- @param params table: Export params with alignToSeconds flag
-- @return number: Calculated position (potentially aligned to next whole second)
function M.calculatePosition(currentPos, params)
    if params.alignToSeconds then
        return math.ceil(currentPos)
    end
    return currentPos
end

-- Resolve track structure by delegating to Generation engine
-- This ensures export uses the same channel mapping logic as generation
-- @param containerInfo table: Container info from collectAllContainers
-- @return table: trackStructure object from Generation_Modes.determineTrackStructure()
function M.resolveTrackStructure(containerInfo)
    if not globals.Generation then
        error("Export_Placement.resolveTrackStructure: globals.Generation not initialized. Ensure Generation module is loaded before Export.")
    end

    local container = containerInfo.container

    -- Analyze items for channel structure
    local itemsAnalysis = globals.Generation.analyzeContainerItems(container)

    -- Determine track structure based on container mode and item analysis
    local trackStructure = globals.Generation.determineTrackStructure(container, itemsAnalysis)

    return trackStructure
end

-- Place a single pool entry at specified position on given tracks
-- Replaces closure to eliminate upvalue mutation (Code Review H2)
-- @param poolEntry table: PoolEntry object { item, area, itemIdx, itemKey }
-- @param placementTracks table: Tracks to place on
-- @param placementIndices table: Real track indices for channel extraction
-- @param currentPos number: Timeline position in seconds
-- @param params table: Export params with alignToSeconds
-- @param genParams table: Generation params for placeSingleItem
-- @param effectiveTrackStructure table: Track structure with channel selection mode
-- @param effectiveInterval number: Interval between items
-- @param placedItems table: Output array to append PlacedItem records
-- @return number: New position after placement (or currentPos if nothing placed)
local function placeSinglePoolEntry(poolEntry, placementTracks, placementIndices, currentPos, params, genParams, effectiveTrackStructure, effectiveInterval, placedItems)
    -- Story 4.3 fix: Nil filePath should throw error, not silently skip
    if not poolEntry.item.filePath then
        error("Item has no file path configured")
    end

    -- Story 4.3: Check if source file exists before attempting placement
    local filePath = poolEntry.item.filePath
    if not reaper.file_exists(filePath) then
        error("Missing source file: " .. filePath, 0)
    end

    local itemData = M.buildItemData(poolEntry.item, poolEntry.area)
    -- Story 5.4: Don't align to seconds in loop mode with overlap (negative interval)
    local itemPos
    if effectiveInterval < 0 then
        itemPos = currentPos  -- Preserve precise positioning for overlaps
    else
        itemPos = M.calculatePosition(currentPos, params)
    end
    local actualLen = 0
    local anyItemCreated = false

    for tIdx, track in ipairs(placementTracks) do
        local realTrackIdx = placementIndices and placementIndices[tIdx] or tIdx

        local newItem, length = globals.Generation.placeSingleItem(
            track,
            itemData,
            itemPos,
            genParams,
            effectiveTrackStructure,
            realTrackIdx,
            effectiveTrackStructure.channelSelectionMode,
            true -- ignoreBounds
        )

        if newItem then
            anyItemCreated = true
            actualLen = math.max(actualLen, length)
            table.insert(placedItems, {
                item = newItem,
                track = track,
                position = itemPos,
                length = length,
                trackIdx = realTrackIdx
            })
        end
    end

    if anyItemCreated then
        -- Advance position by item length plus interval
        local newPos = itemPos + actualLen + effectiveInterval
        -- Clamp to prevent negative progress (overlap cannot exceed item length)
        if newPos <= currentPos then
            newPos = currentPos + 0.001
        end
        -- Optionally align after interval
        if params.alignToSeconds and effectiveInterval > 0 then
            newPos = math.ceil(newPos)
        end
        return newPos
    end

    return currentPos
end

-- Resolve distribution target tracks for Round-Robin or Random modes
-- Replaces closure to eliminate shared upvalue (Code Review H2)
-- @param distributionMode number: 0 = Round-Robin, 1 = Random
-- @param distributionCounter number: Current counter for Round-Robin (passed by reference via return)
-- @param effectiveTargetTracks table: Array of tracks to distribute across
-- @param effectiveTrackStructure table: Track structure with trackIndices
-- @return table: Single-element array with target track
-- @return table: Single-element array with real track index
-- @return number: Updated distribution counter (for Round-Robin)
local function getDistributionTargetTracks(distributionMode, distributionCounter, effectiveTargetTracks, effectiveTrackStructure)
    local targetIdx
    local newCounter = distributionCounter

    if distributionMode == 0 then
        -- Round-Robin: cycle through tracks sequentially
        newCounter = newCounter + 1
        targetIdx = ((newCounter - 1) % #effectiveTargetTracks) + 1
    else
        -- Random: pick random track per pool entry
        targetIdx = math.random(1, #effectiveTargetTracks)
    end

    local track = effectiveTargetTracks[targetIdx]
    local realIdx = effectiveTrackStructure.trackIndices
        and effectiveTrackStructure.trackIndices[targetIdx] or targetIdx

    return {track}, {realIdx}, newCounter
end

-- Place items in All Tracks mode (distributionMode == 2)
-- Each track gets independent sequence from shuffled pool
-- Code Review H1: Extracted to reduce placeContainerItems complexity
-- Story 5.6: Added optional overfillDuration parameter for multi-channel sync
-- @param overfillDuration number|nil: Optional overfill duration (uses targetDuration if nil)
-- @return table: placedItems array
-- @return number: Final position (furthest across all tracks)
local function placeItemsAllTracksMode(pool, effectiveTargetTracks, effectiveTrackStructure, startPos, params, genParams, effectiveInterval, isLoopMode, targetDuration, placedItems, overfillDuration)
    local Constants = globals.Constants
    local EXPORT = Constants and Constants.EXPORT or {}
    local furthestPos = startPos

    for tIdx, track in ipairs(effectiveTargetTracks) do
        local realIdx = effectiveTrackStructure.trackIndices
            and effectiveTrackStructure.trackIndices[tIdx] or tIdx
        local trackPos = startPos
        local trackTracks = {track}
        local trackIndices = {realIdx}

        -- Shuffle independent copy of pool for this track
        local trackPool = {}
        for i, entry in ipairs(pool) do trackPool[i] = entry end
        M.shuffleArray(trackPool)

        if isLoopMode then
            -- Loop mode: cycle through shuffled pool until fillDuration
            -- Story 5.6: Use overfill duration if provided (for multi-channel sync)
            local fillDuration = overfillDuration or targetDuration
            local poolIndex = 1
            local itemsPlaced = 0
            local maxIter = EXPORT.LOOP_MAX_ITERATIONS or 10000

            while (trackPos - startPos) < fillDuration and itemsPlaced < maxIter do
                local poolEntry = trackPool[poolIndex]
                if not poolEntry then break end

                for instance = 1, params.instanceAmount do
                    if (trackPos - startPos) >= fillDuration then break end
                    trackPos = placeSinglePoolEntry(poolEntry, trackTracks, trackIndices, trackPos, params, genParams, effectiveTrackStructure, effectiveInterval, placedItems)
                    itemsPlaced = itemsPlaced + 1
                end

                poolIndex = poolIndex + 1
                if poolIndex > #trackPool then
                    poolIndex = 1
                end
            end
        else
            -- Standard mode: iterate once through shuffled pool per track
            for _, poolEntry in ipairs(trackPool) do
                for instance = 1, params.instanceAmount do
                    trackPos = placeSinglePoolEntry(poolEntry, trackTracks, trackIndices, trackPos, params, genParams, effectiveTrackStructure, effectiveInterval, placedItems)
                end
            end
        end

        -- Track furthest position across all tracks
        if trackPos > furthestPos then
            furthestPos = trackPos
        end
    end

    return placedItems, furthestPos
end

-- Place items in Loop mode (non-All Tracks)
-- Cycles through pool until targetDuration reached
-- Code Review H1: Extracted to reduce placeContainerItems complexity
-- Story 5.6: Added optional overfillDuration parameter for multi-channel sync
-- @param overfillDuration number|nil: Optional overfill duration (uses targetDuration if nil)
-- @return table: placedItems array
-- @return number: Final position
local function placeItemsLoopMode(pool, effectiveTargetTracks, effectiveTrackStructure, startPos, params, genParams, effectiveInterval, targetDuration, preserveDistribution, distributionMode, distributionCounter, placedItems, overfillDuration)
    local Constants = globals.Constants
    local EXPORT = Constants and Constants.EXPORT or {}
    local currentPos = startPos
    local poolIndex = 1
    local itemsPlaced = 0
    local maxIterations = EXPORT.LOOP_MAX_ITERATIONS or 10000

    -- Story 5.6: Use overfill duration if provided (for multi-channel sync), otherwise use target duration
    local fillDuration = overfillDuration or targetDuration

    while (currentPos - startPos) < fillDuration and itemsPlaced < maxIterations do
        local poolEntry = pool[poolIndex]
        if not poolEntry then break end

        -- Place for each instance requested
        -- Code Review M3: Advance distribution counter PER INSTANCE (not per pool entry)
        for instance = 1, params.instanceAmount do
            if (currentPos - startPos) >= fillDuration then break end

            -- Resolve distribution target for Preserve Round-Robin/Random
            local distTracks, distIndices
            if preserveDistribution then
                distTracks, distIndices, distributionCounter = getDistributionTargetTracks(distributionMode, distributionCounter, effectiveTargetTracks, effectiveTrackStructure)
            else
                distTracks = effectiveTargetTracks
                distIndices = effectiveTrackStructure.trackIndices
            end

            currentPos = placeSinglePoolEntry(poolEntry, distTracks, distIndices, currentPos, params, genParams, effectiveTrackStructure, effectiveInterval, placedItems)
            itemsPlaced = itemsPlaced + 1
        end

        -- Cycle through pool
        poolIndex = poolIndex + 1
        if poolIndex > #pool then
            poolIndex = 1
        end
    end

    return placedItems, currentPos
end

-- Place items in Standard mode (non-loop, non-All Tracks)
-- Single pass through pool with optional distribution
-- Code Review H1: Extracted to reduce placeContainerItems complexity
-- Code Review M3: Distribution counter now advances per instance (matching Generation engine)
-- Story 5.5: Uses shared position counter matching Generation engine's round-robin behavior.
--   Generation advances position globally across all tracks, creating a staggered pattern
--   where each track's items are spaced by N*(itemLen+interval) where N=number of tracks.
-- @return table: placedItems array
-- @return number: Final position
local function placeItemsStandardMode(pool, effectiveTargetTracks, effectiveTrackStructure, startPos, params, genParams, effectiveInterval, preserveDistribution, distributionMode, distributionCounter, placedItems)
    local currentPos = startPos

    for _, poolEntry in ipairs(pool) do
        -- Place for each instance requested
        -- Code Review M3: Advance distribution counter PER INSTANCE (not per pool entry)
        for instance = 1, params.instanceAmount do
            -- Resolve distribution target for Preserve Round-Robin/Random
            local distTracks, distIndices
            if preserveDistribution then
                distTracks, distIndices, distributionCounter = getDistributionTargetTracks(distributionMode, distributionCounter, effectiveTargetTracks, effectiveTrackStructure)
            else
                distTracks = effectiveTargetTracks
                distIndices = effectiveTrackStructure.trackIndices
            end

            currentPos = placeSinglePoolEntry(poolEntry, distTracks, distIndices, currentPos, params, genParams, effectiveTrackStructure, effectiveInterval, placedItems)
        end
    end

    return placedItems, currentPos
end

-- Synchronize multi-channel loop track timestamps (Story 5.6)
-- Ensures all tracks start and end at the same timestamps for seamless loop export
-- @param placedItems table: Array of PlacedItem records {item, track, position, length, trackIdx}
-- @param effectiveTargetTracks table: Array of tracks that were filled
-- @param targetDuration number: Original target duration (before overfill)
-- @param effectiveInterval number: Interval between items (negative for overlap)
-- @return table: Updated placedItems with new items from split/swap
function M.syncMultiChannelLoopTracks(placedItems, effectiveTargetTracks, targetDuration, effectiveInterval)
    -- Code Review Fix (Medium #2): Add debug logging
    local debugSync = globals.debugExport or false
    if debugSync then
        reaper.ShowConsoleMsg("[Export Sync] ========== Multi-Channel Loop Sync ==========\n")
        reaper.ShowConsoleMsg(string.format("  Target Duration: %.2fs\n", targetDuration))
        reaper.ShowConsoleMsg(string.format("  Effective Interval: %.2fs\n", effectiveInterval))
        reaper.ShowConsoleMsg(string.format("  Total Tracks: %d\n", #effectiveTargetTracks))
        reaper.ShowConsoleMsg(string.format("  Total Items (pre-sync): %d\n", #placedItems))
    end

    -- Task 2: Detect timestamp bounds
    local earliestStart = math.huge
    local latestEnd = -math.huge

    -- Group items by track for independent processing
    local itemsByTrack = {}
    for _, placed in ipairs(placedItems) do
        local trackIdx = placed.trackIdx
        if not itemsByTrack[trackIdx] then
            itemsByTrack[trackIdx] = {}
        end
        table.insert(itemsByTrack[trackIdx], placed)
    end

    -- Find earliest start and latest end across all tracks
    for trackIdx, trackItems in pairs(itemsByTrack) do
        if #trackItems > 0 then
            -- Sort by position to find first and last
            table.sort(trackItems, function(a, b) return a.position < b.position end)
            local firstItem = trackItems[1]
            local lastItem = trackItems[#trackItems]

            earliestStart = math.min(earliestStart, firstItem.position)
            latestEnd = math.max(latestEnd, lastItem.position + lastItem.length)
        end
    end

    -- Define target bounds
    local targetStart = earliestStart
    local targetEnd = targetStart + targetDuration

    if debugSync then
        reaper.ShowConsoleMsg(string.format("  Detected Bounds: [%.2fs → %.2fs] (span: %.2fs)\n",
            earliestStart, latestEnd, latestEnd - earliestStart))
        reaper.ShowConsoleMsg(string.format("  Target Bounds: [%.2fs → %.2fs]\n",
            targetStart, targetEnd))
    end

    -- Task 3 & 4: Synchronize each track (shift + split/swap + extend)
    for trackIdx, trackItems in pairs(itemsByTrack) do
        -- Code Review Fix (High #3): Only skip empty tracks, handle single-item tracks
        if #trackItems == 0 then
            goto nextTrack
        end

        -- Sort items by position
        table.sort(trackItems, function(a, b) return a.position < b.position end)

        -- Task 3: Calculate shift amount to align all tracks to targetStart
        local currentStart = trackItems[1].position
        local shiftAmount = targetStart - currentStart

        -- Apply shift to all items on this track
        if math.abs(shiftAmount) > 0.001 then  -- Only shift if meaningful
            for _, placed in ipairs(trackItems) do
                local newPos = placed.position + shiftAmount
                reaper.SetMediaItemInfo_Value(placed.item, "D_POSITION", newPos)
                placed.position = newPos  -- Update record
            end
        end

        -- Code Review Fix (Critical #1): Check if track ends before targetEnd and extend if needed
        local lastItem = trackItems[#trackItems]
        local trackEnd = lastItem.position + lastItem.length

        if trackEnd < targetEnd - 0.001 then
            -- Track is SHORT - need to extend it by duplicating items from the beginning
            local gap = targetEnd - trackEnd
            local currentExtendPos = trackEnd + effectiveInterval  -- Start after last item with proper interval
            local extendPoolIdx = 1
            local maxExtendIter = 1000  -- Safety limit to prevent infinite loop

            local originalTrackItemCount = #trackItems  -- R3 fix: capture count before extension
            while currentExtendPos < targetEnd and extendPoolIdx <= originalTrackItemCount and maxExtendIter > 0 do
                local sourceItem = trackItems[extendPoolIdx]
                maxExtendIter = maxExtendIter - 1

                -- Calculate how much of this item we need
                local remainingGap = targetEnd - currentExtendPos
                local sourceLength = sourceItem.length
                local useLength = math.min(sourceLength, remainingGap + math.abs(effectiveInterval))

                -- Duplicate the media item
                local newItem = reaper.AddMediaItemToTrack(sourceItem.track)
                reaper.SetMediaItemInfo_Value(newItem, "D_POSITION", currentExtendPos)
                reaper.SetMediaItemInfo_Value(newItem, "D_LENGTH", useLength)

                -- Copy properties from source item
                local sourceTake = reaper.GetActiveTake(sourceItem.item)
                if sourceTake then
                    local newTake = reaper.AddTakeToMediaItem(newItem)
                    local sourceSource = reaper.GetMediaItemTake_Source(sourceTake)
                    if sourceSource then
                        reaper.SetMediaItemTake_Source(newTake, sourceSource)

                        -- Copy take properties
                        local startOffset = reaper.GetMediaItemTakeInfo_Value(sourceTake, "D_STARTOFFS")
                        reaper.SetMediaItemTakeInfo_Value(newTake, "D_STARTOFFS", startOffset)
                        reaper.SetMediaItemTakeInfo_Value(newTake, "D_PITCH",
                            reaper.GetMediaItemTakeInfo_Value(sourceTake, "D_PITCH"))
                        reaper.SetMediaItemTakeInfo_Value(newTake, "D_VOL",
                            reaper.GetMediaItemTakeInfo_Value(sourceTake, "D_VOL"))
                        reaper.SetMediaItemTakeInfo_Value(newTake, "D_PAN",
                            reaper.GetMediaItemTakeInfo_Value(sourceTake, "D_PAN"))
                    end
                end

                -- Add to placedItems for region bounds
                table.insert(placedItems, {
                    item = newItem,
                    track = sourceItem.track,
                    position = currentExtendPos,
                    length = useLength,
                    trackIdx = trackIdx
                })

                -- Add to trackItems for potential split/swap processing
                table.insert(trackItems, {
                    item = newItem,
                    track = sourceItem.track,
                    position = currentExtendPos,
                    length = useLength,
                    trackIdx = trackIdx
                })

                -- Advance position
                currentExtendPos = currentExtendPos + useLength + effectiveInterval
                extendPoolIdx = extendPoolIdx + 1

                -- Wrap around to beginning of pool if we run out
                if extendPoolIdx > originalTrackItemCount then
                    extendPoolIdx = 1
                end

                -- If we've filled the gap and possibly exceeded, prepare for split
                if currentExtendPos >= targetEnd then
                    break
                end
            end

            -- Update trackEnd for next phase (R5 fix: use actual last item end, not next position)
            trackEnd = trackItems[#trackItems].position + trackItems[#trackItems].length
        end

        -- Task 4: Split at targetEnd and wrap excess to targetStart for seamless loop
        -- Place rightPart at EXACTLY targetStart so all tracks start at the same position.
        -- Then trim existing first items to maintain correct overlap with the wrapped rightPart.
        local trimCount = 0
        local maxRightPartLen = 0  -- Track longest rightPart for first-item trimming
        for _, placed in ipairs(trackItems) do
            local itemEnd = placed.position + placed.length

            if placed.position >= targetEnd - 0.001 then
                -- Item starts at or past targetEnd: delete entirely
                reaper.DeleteTrackMediaItem(placed.track, placed.item)
                placed.deleted = true
                trimCount = trimCount + 1
            elseif itemEnd > targetEnd + 0.001 then
                -- Item crosses targetEnd: split at zero-crossing, wrap right part to targetStart
                if Loop and Loop.findNearestZeroCrossing then
                    local zeroCrossingTime = Loop.findNearestZeroCrossing(placed.item, targetEnd)
                    local rightPart = reaper.SplitMediaItem(placed.item, zeroCrossingTime)
                    if rightPart then
                        reaper.SetMediaItemPosition(rightPart, targetStart, false)

                        local rightPartLen = reaper.GetMediaItemInfo_Value(rightPart, "D_LENGTH")
                        table.insert(placedItems, {
                            item = rightPart,
                            track = placed.track,
                            position = targetStart,
                            length = rightPartLen,
                            trackIdx = trackIdx
                        })
                        if rightPartLen > maxRightPartLen then
                            maxRightPartLen = rightPartLen
                        end
                    end
                else
                    -- Fallback: trim length directly (no loop wrap, but at least aligned)
                    reaper.SetMediaItemInfo_Value(placed.item, "D_LENGTH", targetEnd - placed.position)
                end
                -- Update left part record with actual length after split
                placed.length = reaper.GetMediaItemInfo_Value(placed.item, "D_LENGTH")
                trimCount = trimCount + 1
            end
        end

        -- Task 4b: Trim existing first items to account for wrapped rightPart
        -- In standard splitAndSwap: rightPartPos = firstItemPos - rightPartLen - effectiveInterval
        -- In multi-channel sync: rightPartPos = targetStart (fixed for track alignment)
        -- Therefore first item must start at: targetStart + rightPartLen + effectiveInterval
        -- to maintain correct overlap (abs(effectiveInterval)) with the wrapped rightPart.
        if maxRightPartLen > 0 then
            local requiredFirstItemStart = targetStart + maxRightPartLen + effectiveInterval

            if debugSync then
                reaper.ShowConsoleMsg(string.format("  Track %d: rightPartLen=%.2fs, requiredFirstItemStart=%.2fs (trim=%.2fs)\n",
                    trackIdx, maxRightPartLen, requiredFirstItemStart, maxRightPartLen + effectiveInterval))
            end

            if requiredFirstItemStart > targetStart + 0.001 then
                for _, placed in ipairs(trackItems) do
                    if not placed.deleted then
                        local itemEnd = placed.position + placed.length

                        if itemEnd <= requiredFirstItemStart + 0.001 then
                            -- Item ends before required start: completely covered by rightPart, delete
                            reaper.DeleteTrackMediaItem(placed.track, placed.item)
                            placed.deleted = true
                        elseif placed.position < requiredFirstItemStart - 0.001 then
                            -- Item starts before required start: trim from left
                            local trimFromLeft = requiredFirstItemStart - placed.position
                            local take = reaper.GetActiveTake(placed.item)
                            if take then
                                local currentOffset = reaper.GetMediaItemTakeInfo_Value(take, "D_STARTOFFS")
                                reaper.SetMediaItemTakeInfo_Value(take, "D_STARTOFFS", currentOffset + trimFromLeft)
                            end
                            reaper.SetMediaItemInfo_Value(placed.item, "D_POSITION", requiredFirstItemStart)
                            reaper.SetMediaItemInfo_Value(placed.item, "D_LENGTH", placed.length - trimFromLeft)
                            placed.position = requiredFirstItemStart
                            placed.length = placed.length - trimFromLeft
                            break  -- Remaining items are properly spaced
                        else
                            break  -- Item already past required start, no trimming needed
                        end
                    end
                end
            end
        end

        -- Debug logging for each track
        if debugSync then
            -- Count remaining (non-deleted) items on this track
            local remainingCount = 0
            local finalTrackEnd = targetStart
            for _, placed in ipairs(trackItems) do
                if not placed.deleted then
                    remainingCount = remainingCount + 1
                    local itemEnd = placed.position + placed.length
                    if itemEnd > finalTrackEnd then finalTrackEnd = itemEnd end
                end
            end
            reaper.ShowConsoleMsg(string.format("  Track %d: %d items (-%d trimmed), shift=%.3fs, extended=%s, finalEnd=%.2fs\n",
                trackIdx, remainingCount, trimCount, shiftAmount,
                (trackEnd ~= lastItem.position + lastItem.length) and "YES" or "NO",
                finalTrackEnd))
        end

        ::nextTrack::
    end

    -- R1: Remove deleted items from placedItems (trim-to-bounds cleanup)
    local cleanedItems = {}
    for _, placed in ipairs(placedItems) do
        if not placed.deleted then
            table.insert(cleanedItems, placed)
        end
    end

    if debugSync then
        reaper.ShowConsoleMsg(string.format("[Export Sync] ========== Sync Complete (Total Items: %d) ==========\n", #cleanedItems))
    end

    return cleanedItems
end

-- Place container items on target tracks with correct multichannel channel distribution
-- CRITICAL: Uses real track indices from trackStructure for correct channel extraction
-- In loop mode: uses loopInterval instead of spacing, continues until loopDuration reached
--
-- ARCHITECTURE NOTE: This function is called ONCE per container by Export_Engine.performExport().
-- This design enables Story 4.4's AC5 (batch export with loopInterval=0): each container's
-- effectiveInterval is calculated independently based on its own triggerRate when in auto-mode.
-- Do NOT refactor Export_Engine to batch multiple containers in a single call without updating
-- the effectiveInterval logic accordingly.
--
-- Code Review H1: Refactored from 281 lines to ~60 lines by extracting helpers
--
-- @param pool table: Array of PoolEntry objects from resolvePool { item, area, itemIdx, itemKey }
-- @param targetTracks table: Array of REAPER tracks from resolveTargetTracks
-- @param trackStructure table: Track structure from resolveTrackStructure
-- @param params table: Effective export params
-- @param containerInfo table: Container info with path, container, group
-- @param startPosition number|nil: Optional start position in seconds (defaults to cursor if nil).
--        If provided, must be >= 0. Used by Export_Engine for sequential container placement.
-- @return table: Array of PlacedItem records {item, track, position, length, trackIdx}
-- @return number: End position (in seconds) after all items placed. Used by Export_Engine to
--        calculate next container's start position for sequential batch export.
-- @return number: effectiveInterval used for item spacing (negative for overlap). Used by
--        Export_Loop for maintaining consistent overlap after split/swap (Story 5.3).
function M.placeContainerItems(pool, targetTracks, trackStructure, params, containerInfo, startPosition)
    local placedItems = {}
    local startPos = startPosition or reaper.GetCursorPosition()
    if startPos < 0 then
        startPos = 0
    end

    local genParams = M.buildGenParams(params, containerInfo)
    local container = containerInfo.container
    local Constants = globals.Constants
    local EXPORT = Constants and Constants.EXPORT or {}

    -- Story 5.2: Multichannel export mode handling
    local multichannelMode = params.multichannelExportMode
        or EXPORT.MULTICHANNEL_EXPORT_MODE_DEFAULT or "flatten"
    local isFlattenMode = (multichannelMode == (EXPORT.MULTICHANNEL_EXPORT_MODE_FLATTEN or "flatten"))
    local isPreserveMode = (multichannelMode == (EXPORT.MULTICHANNEL_EXPORT_MODE_PRESERVE or "preserve"))

    -- Code Review L2: Defensive guard for invalid mode
    if not isFlattenMode and not isPreserveMode then
        error(string.format("Invalid multichannelExportMode: %s (must be 'flatten' or 'preserve')", tostring(multichannelMode)), 0)
    end

    -- Apply flatten mode: restrict to first track, disable channel extraction
    local effectiveTargetTracks = targetTracks
    local effectiveTrackStructure = trackStructure
    if isFlattenMode and #targetTracks > 1 then
        effectiveTargetTracks = {targetTracks[1]}
        effectiveTrackStructure = {}
        for k, v in pairs(trackStructure) do
            effectiveTrackStructure[k] = v
        end
        effectiveTrackStructure.channelSelectionMode = "none"
        effectiveTrackStructure.needsChannelSelection = false
        if trackStructure.trackIndices then
            effectiveTrackStructure.trackIndices = {trackStructure.trackIndices[1]}
        end
    end

    -- Story 5.5: Resolve effective trigger settings with inheritance
    -- Generation uses Structures.getEffectiveContainerParams() which inherits from group
    -- when container.overrideParent is false. Export must match this behavior.
    local effectiveTriggerRate = container.triggerRate
    local effectiveIntervalMode = container.intervalMode
    if not container.overrideParent and containerInfo.group then
        effectiveTriggerRate = containerInfo.group.triggerRate
        effectiveIntervalMode = containerInfo.group.intervalMode
    end
    effectiveIntervalMode = effectiveIntervalMode or Constants.TRIGGER_MODES.ABSOLUTE

    -- Resolve loop mode and effective interval
    -- Uses effective params (per-container override or global) so user can set loopMode per container
    local isLoopMode = Settings and Settings.resolveLoopMode(container, params) or false
    local effectiveInterval
    if isLoopMode then
        if (params.loopInterval or 0) ~= 0 then
            effectiveInterval = params.loopInterval
        elseif effectiveTriggerRate and effectiveTriggerRate < 0 then
            effectiveInterval = effectiveTriggerRate
        else
            effectiveInterval = 0
        end
    else
        -- Standard mode: respect container interval
        -- Story 5.4: Use effective triggerRate if defined (ABSOLUTE mode only)
        if effectiveTriggerRate
            and effectiveTriggerRate > 0
            and effectiveIntervalMode == Constants.TRIGGER_MODES.ABSOLUTE then
            -- Use effective interval (inherited from group if container doesn't override)
            effectiveInterval = effectiveTriggerRate
        else
            -- Fallback to global spacing for:
            -- - No triggerRate defined
            -- - triggerRate is 0
            -- - Non-ABSOLUTE modes (RELATIVE, COVERAGE, CHUNK)
            effectiveInterval = params.spacing or 0
        end
    end
    local targetDuration = isLoopMode and (params.loopDuration or 30) or math.huge

    -- Story 5.2: Determine distribution mode and flags
    local preserveDistribution = false
    local distributionCounter = 0
    local distributionMode = container.itemDistributionMode or 0
    local isAllTracksMode = false

    if isPreserveMode and #effectiveTargetTracks > 1 then
        if effectiveTrackStructure.useSmartRouting then
            preserveDistribution = false
        elseif effectiveTrackStructure.useDistribution then
            if distributionMode == 2 then
                isAllTracksMode = true
            else
                preserveDistribution = true
            end
        end
    end

    -- Story 5.6: Detect multi-channel preserve loop mode and calculate overfill
    local isMultiChannelPreserveLoop = isPreserveMode
        and #effectiveTargetTracks > 1
        and isLoopMode
    local overfillDuration = nil

    if isMultiChannelPreserveLoop then
        -- Code Review Fix (Critical #2): Calculate overfill based on max item length
        -- This ensures ALL tracks overshoot targetEnd, preventing short track misalignment

        -- Calculate maximum item length in pool
        local maxItemLength = 0
        for _, poolEntry in ipairs(pool) do
            local itemLen = poolEntry.area.endPos - poolEntry.area.startPos
            if itemLen > maxItemLength then
                maxItemLength = itemLen
            end
        end

        -- Task 1: Calculate overfill factor based on interval AND max item length
        -- Formula: overfillFactor = 1.0 + max(interval_factor, item_length_factor)
        -- This guarantees all tracks overshoot by at least the shortest item in the pool
        local overfillFactor = 1.0
        local intervalFactor = math.abs(effectiveInterval) / targetDuration
        local itemLengthFactor = maxItemLength / targetDuration

        if effectiveInterval < 0 then
            -- Overlap mode: use larger of interval or item length, minimum 5%
            overfillFactor = 1.0 + math.max(0.05, intervalFactor, itemLengthFactor)
        else
            -- Non-overlap mode: use item length factor, minimum 10%
            overfillFactor = 1.0 + math.max(0.10, itemLengthFactor)
        end

        overfillDuration = targetDuration * overfillFactor

        -- Code Review Fix (Medium #2): Debug logging for overfill calculation
        if globals.debugExport then
            reaper.ShowConsoleMsg("[Export Overfill] Multi-Channel Preserve Loop Detected\n")
            reaper.ShowConsoleMsg(string.format("  Max Item Length: %.2fs\n", maxItemLength))
            reaper.ShowConsoleMsg(string.format("  Interval Factor: %.2f%%\n", intervalFactor * 100))
            reaper.ShowConsoleMsg(string.format("  Item Length Factor: %.2f%%\n", itemLengthFactor * 100))
            reaper.ShowConsoleMsg(string.format("  Overfill Factor: %.2f%% (%.2fx)\n", (overfillFactor - 1.0) * 100, overfillFactor))
            reaper.ShowConsoleMsg(string.format("  Target Duration: %.2fs → Overfill Duration: %.2fs\n", targetDuration, overfillDuration))
        end
    end

    -- Route to appropriate placement strategy (with overfill support)
    local finalPos
    if isAllTracksMode then
        placedItems, finalPos = placeItemsAllTracksMode(pool, effectiveTargetTracks, effectiveTrackStructure, startPos, params, genParams, effectiveInterval, isLoopMode, targetDuration, placedItems, overfillDuration)
    elseif isLoopMode then
        placedItems, finalPos = placeItemsLoopMode(pool, effectiveTargetTracks, effectiveTrackStructure, startPos, params, genParams, effectiveInterval, targetDuration, preserveDistribution, distributionMode, distributionCounter, placedItems, overfillDuration)
    else
        placedItems, finalPos = placeItemsStandardMode(pool, effectiveTargetTracks, effectiveTrackStructure, startPos, params, genParams, effectiveInterval, preserveDistribution, distributionMode, distributionCounter, placedItems)
    end

    -- Story 5.6: Synchronize multi-channel loop tracks (Tasks 2-4)
    if isMultiChannelPreserveLoop and #placedItems > 0 then
        placedItems = M.syncMultiChannelLoopTracks(placedItems, effectiveTargetTracks, targetDuration, effectiveInterval)
    end

    -- R2: Return sync flag so Export_Engine can skip processLoop() when sync was applied
    return placedItems, finalPos, effectiveInterval, isMultiChannelPreserveLoop
end

return M
