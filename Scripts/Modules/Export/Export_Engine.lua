--[[
@version 1.19
@noindex
DM Ambiance Creator - Export Engine Module
Handles export orchestration, region creation, and export execution.
Migrated from Export_Core.lua (performExport, parseRegionPattern, shallowCopy).
v1.2: Added instanceCount to PreviewEntry, optimized pool size calculation, fixed trackType default.
v1.3: Story 2.1 - Added validateMaxPoolItems() call before resolvePool(), empty pool handling.
v1.4: Code review fixes - math.randomseed moved here (once per export), validateMaxPoolItems uses containerInfo, empty pool warning.
v1.5: Story 3.1 - Added loopDuration to PreviewEntry, updated estimateDuration for loop mode.
      Code review fix: estimateDuration now uses Settings.resolveLoopMode for consistency.
v1.6: Story 3.2 - Integrated Export_Loop for zero-crossing loop processing (split/swap).
v1.7: Code review fixes - Region bounds now include loop-created items, totalItemsExported counts split items.
v1.8: Story 4.1 - Sequential container placement for batch export. Each container starts after
      previous container ends, preventing overlap. Uses globalParams.spacing for container spacing.
v1.9: Code review fixes - containerSpacing from global params, Loop module warning in loop mode.
v1.10: Bug fix - Reposition loop container items after split/swap to prevent overlap with previous container.
v1.11: Bug fix - Read actual item bounds from REAPER after loop processing for accurate spacing and regions.
v1.12: Bug fix - Calculate actual endPosition for ALL containers (not just loops) to ensure consistent spacing.
v1.13: Story 4.1 fix - Apply crossfades to overlapping items after placement using Utils.applyCrossfadesToTrack.
v1.14: Story 4.3 - Per-container error isolation with pcall, structured ExportResults with per-container status.
       Empty pool now recorded as warning (not just console), missing source files detected and reported.
v1.15: Code review fixes - Log warning when ValidatePtr fails, log all warnings (not just first),
       remove redundant success check condition.
v1.16 (2026-02-07): Story 5.3 - Capture effectiveInterval from placeContainerItems() and pass to Loop.processLoop()
       for consistent overlap after split/swap in seamless loops.
v1.18: Added config history save on successful export (Export_ConfigHistory integration).
v1.17 (2026-02-08): Story 5.6 Code Review v2 R2 - Skip processLoop() when multi-channel sync applied
       Captures syncApplied flag from placeContainerItems() 4th return value.
       When multi-channel preserve loop sync has already trimmed items to bounds,
       processLoop() would do a destructive second split/swap, inflating the region.
v1.19: Bug fix - Region creation now uses global createRegions setting instead of per-container params.
       Fixes bug where containers with overrides (typically loop containers) had createRegions=false
       frozen from override creation time, preventing region creation even when enabled globally.
--]]

local M = {}
local globals = {}
local Settings = nil
local Placement = nil
local Loop = nil
local ConfigHistory = nil

function M.initModule(g)
    if not g then
        error("Export_Engine.initModule: globals parameter is required")
    end
    globals = g
end

function M.setDependencies(settings, placement, loop, configHistory)
    Settings = settings
    Placement = placement
    Loop = loop
    ConfigHistory = configHistory
end

-- Find the index of the last child track within a folder
-- Only searches up to maxIdx (exclusive)
local function findFolderLastChildIdx(parentIdx, maxIdx)
    local parentTrack = reaper.GetTrack(0, parentIdx)
    local depth = reaper.GetMediaTrackInfo_Value(parentTrack, "I_FOLDERDEPTH")
    if depth ~= 1 then return parentIdx end

    local folderDepth = 1
    local lastChildIdx = parentIdx
    local k = parentIdx + 1
    while k < maxIdx and folderDepth > 0 do
        local track = reaper.GetTrack(0, k)
        local d = reaper.GetMediaTrackInfo_Value(track, "I_FOLDERDEPTH")
        folderDepth = folderDepth + d
        lastChildIdx = k
        k = k + 1
    end
    return lastChildIdx
end

-- Relocate tracks into a parent track by GUID, adjusting folder depths
local function relocateTracksIntoParent(parentGUID, firstNewIdx, lastNewIdx)
    local parentTrack, parentIdx = nil, nil
    for i = 0, firstNewIdx - 1 do
        local track = reaper.GetTrack(0, i)
        if reaper.GetTrackGUID(track) == parentGUID then
            parentTrack = track
            parentIdx = i
            break
        end
    end
    if not parentTrack then return end

    local isFolder = reaper.GetMediaTrackInfo_Value(parentTrack, "I_FOLDERDEPTH") == 1
    local closingDepthToTransfer = -1
    local insertBeforeIdx

    if isFolder then
        local lastChildIdx = findFolderLastChildIdx(parentIdx, firstNewIdx)
        if lastChildIdx > parentIdx then
            local lastChild = reaper.GetTrack(0, lastChildIdx)
            closingDepthToTransfer = reaper.GetMediaTrackInfo_Value(lastChild, "I_FOLDERDEPTH")
            reaper.SetMediaTrackInfo_Value(lastChild, "I_FOLDERDEPTH", 0)
            insertBeforeIdx = lastChildIdx + 1
        else
            insertBeforeIdx = parentIdx + 1
        end
    else
        reaper.SetMediaTrackInfo_Value(parentTrack, "I_FOLDERDEPTH", 1)
        insertBeforeIdx = parentIdx + 1
    end

    local trackCount = reaper.CountTracks(0)
    for i = 0, trackCount - 1 do
        reaper.SetTrackSelected(reaper.GetTrack(0, i), false)
    end
    for i = firstNewIdx, lastNewIdx do
        reaper.SetTrackSelected(reaper.GetTrack(0, i), true)
    end

    reaper.ReorderSelectedTracks(insertBeforeIdx, 0)

    local numNew = lastNewIdx - firstNewIdx + 1
    local lastMovedIdx = insertBeforeIdx + numNew - 1
    local lastMovedTrack = reaper.GetTrack(0, lastMovedIdx)
    local currentDepth = reaper.GetMediaTrackInfo_Value(lastMovedTrack, "I_FOLDERDEPTH")
    reaper.SetMediaTrackInfo_Value(lastMovedTrack, "I_FOLDERDEPTH", currentDepth + closingDepthToTransfer)

    for i = 0, reaper.CountTracks(0) - 1 do
        reaper.SetTrackSelected(reaper.GetTrack(0, i), false)
    end
end

-- Helper: Create an ExportResult object for a single container
-- @param containerKey string: Unique container identifier
-- @param containerName string: Display name for UI
-- @param status string: "success" | "error" | "warning"
-- @param itemsExported number: Count of items placed
-- @param errors table: Array of error messages
-- @param warnings table: Array of warning messages
-- @return table: ExportResult object
local function createExportResult(containerKey, containerName, status, itemsExported, errors, warnings)
    return {
        containerKey = containerKey,
        containerName = containerName,
        status = status,
        itemsExported = itemsExported or 0,
        errors = errors or {},
        warnings = warnings or {}
    }
end

-- Helper: Create an ExportResults aggregate object
-- @return table: ExportResults structure
local function createExportResults()
    return {
        results = {},              -- Array of ExportResult objects
        totalItemsExported = 0,    -- Total items across all containers
        totalSuccess = 0,          -- Count of successful containers
        totalErrors = 0,           -- Count of containers with errors
        totalWarnings = 0          -- Count of containers with warnings (but still succeeded)
    }
end

-- Helper: Add a result to ExportResults and update totals
-- @param exportResults table: ExportResults aggregate object
-- @param result table: ExportResult object to add
local function addExportResult(exportResults, result)
    table.insert(exportResults.results, result)
    exportResults.totalItemsExported = exportResults.totalItemsExported + result.itemsExported

    if result.status == "error" then
        exportResults.totalErrors = exportResults.totalErrors + 1
    elseif result.status == "warning" then
        exportResults.totalWarnings = exportResults.totalWarnings + 1
        exportResults.totalSuccess = exportResults.totalSuccess + 1  -- Warnings still count as success
    elseif result.status == "success" then
        exportResults.totalSuccess = exportResults.totalSuccess + 1
    end
end

-- Helper: Parse region name pattern and replace tags
-- @param pattern string: The pattern string with tags (e.g., "sfx_$container")
-- @param containerInfo table: Container information with container, group
-- @param containerIndex number: 1-based index of container in export list
-- @return string: The parsed region name
local function parseRegionPattern(pattern, containerInfo, containerIndex)
    local result = pattern
    result = result:gsub("%$container", containerInfo.container.name or "Container")
    result = result:gsub("%$group", containerInfo.group.name or "Group")
    result = result:gsub("%$index", tostring(containerIndex))
    return result
end

-- Process a single container for export (isolated function for pcall wrapping)
-- @param containerInfo table: Container info from collectAllContainers
-- @param params table: Effective params for this container
-- @param currentExportPosition number: Start position for this container
-- @param containerExportIndex number: 1-based index in export list (for region naming)
-- @return table: Result object with { itemsExported, endPosition, warnings, loopNewItems }
local function processContainerExport(containerInfo, params, currentExportPosition, containerExportIndex)
    local warnings = {}

    -- Get track structure first (delegates to Generation engine)
    -- Computed once and passed through to avoid redundant analysis
    local trackStructure = Placement.resolveTrackStructure(containerInfo)

    -- Get target tracks for this container (may create hierarchy based on trackStructure)
    local targetTracks = Placement.resolveTargetTracks(containerInfo, trackStructure, params)
    if #targetTracks == 0 then
        error("No target tracks available for container")
    end

    -- Validate and clamp maxPoolItems to actual pool size (AC #3, #4)
    local validatedMax = Settings.validateMaxPoolItems(containerInfo, params.maxPoolItems)

    -- Get pool of PoolEntry objects (item + area pre-resolved)
    local pool = Placement.resolvePool(containerInfo, validatedMax)

    -- Handle empty pool: return as warning, not error
    if #pool == 0 then
        return {
            itemsExported = 0,
            endPosition = currentExportPosition,
            warnings = { "Empty container skipped" },
            loopNewItems = {},
            isEmpty = true
        }
    end

    -- Place items on tracks using Placement module
    -- Story 5.3: Capture effectiveInterval for loop processing
    -- R2: Capture syncApplied flag to skip processLoop when multi-channel sync was applied
    local placedItems, endPosition, effectiveInterval, syncApplied = Placement.placeContainerItems(
        pool,
        targetTracks,
        trackStructure,
        params,
        containerInfo,
        currentExportPosition
    )

    -- Process loop if in loop mode (Story 3.2: zero-crossing split/swap)
    local isLoopMode = Settings.resolveLoopMode(containerInfo.container, params)
    local loopNewItems = {}

    -- Warn if loop mode enabled but Loop module not available
    if isLoopMode and not Loop then
        table.insert(warnings, "Loop mode enabled but Export_Loop module not loaded. Loop processing skipped.")
    end

    -- R2: Skip processLoop when multi-channel sync was applied (sync already handles trim-to-bounds)
    if isLoopMode and Loop and #placedItems > 1 and not syncApplied then
        -- Code Review M1: Pass targetDuration for AC#8 validation
        -- Story 5.3: Pass effectiveInterval for consistent overlap in split/swap
        local targetDuration = params.loopDuration or 30
        local loopResult = Loop.processLoop(placedItems, targetTracks, targetDuration, effectiveInterval)
        if loopResult.warnings then
            for _, warn in ipairs(loopResult.warnings) do
                table.insert(warnings, warn)
            end
        end
        if loopResult.errors then
            for _, err in ipairs(loopResult.errors) do
                -- Loop errors are treated as warnings since export still succeeded
                table.insert(warnings, "Loop processing: " .. err)
            end
        end
        -- Capture new items created by split/swap for region bounds calculation
        if loopResult.newItems then
            loopNewItems = loopResult.newItems
        end

        -- Reposition all items if loop processing moved items before container start
        if #loopNewItems > 0 then
            local minPosition = currentExportPosition
            for _, newItem in ipairs(loopNewItems) do
                if newItem.position < minPosition then
                    minPosition = newItem.position
                end
            end

            if minPosition < currentExportPosition then
                local shiftAmount = currentExportPosition - minPosition

                for _, placed in ipairs(placedItems) do
                    if reaper.ValidatePtr(placed.item, "MediaItem*") then
                        local currentPos = reaper.GetMediaItemInfo_Value(placed.item, "D_POSITION")
                        reaper.SetMediaItemPosition(placed.item, currentPos + shiftAmount, false)
                        placed.position = placed.position + shiftAmount
                    end
                end

                for _, newItem in ipairs(loopNewItems) do
                    if reaper.ValidatePtr(newItem.item, "MediaItem*") then
                        local currentPos = reaper.GetMediaItemInfo_Value(newItem.item, "D_POSITION")
                        reaper.SetMediaItemPosition(newItem.item, currentPos + shiftAmount, false)
                        newItem.position = newItem.position + shiftAmount
                    end
                end

                endPosition = endPosition + shiftAmount
            end
        end
    end

    -- Calculate actual endPosition for ALL containers
    -- Story 4.3 fix: Log warning if items become invalid during processing
    if #placedItems > 0 then
        local actualEndPosition = currentExportPosition
        local invalidItemCount = 0
        for _, placed in ipairs(placedItems) do
            if reaper.ValidatePtr(placed.item, "MediaItem*") then
                local itemPos = reaper.GetMediaItemInfo_Value(placed.item, "D_POSITION")
                local itemLen = reaper.GetMediaItemInfo_Value(placed.item, "D_LENGTH")
                local itemEnd = itemPos + itemLen
                if itemEnd > actualEndPosition then
                    actualEndPosition = itemEnd
                end
                placed.position = itemPos
                placed.length = itemLen
            else
                invalidItemCount = invalidItemCount + 1
            end
        end
        for _, newItem in ipairs(loopNewItems) do
            if reaper.ValidatePtr(newItem.item, "MediaItem*") then
                local itemPos = reaper.GetMediaItemInfo_Value(newItem.item, "D_POSITION")
                local itemLen = reaper.GetMediaItemInfo_Value(newItem.item, "D_LENGTH")
                local itemEnd = itemPos + itemLen
                if itemEnd > actualEndPosition then
                    actualEndPosition = itemEnd
                end
                newItem.position = itemPos
                newItem.length = itemLen
            else
                invalidItemCount = invalidItemCount + 1
            end
        end
        if invalidItemCount > 0 then
            table.insert(warnings, string.format("%d item(s) became invalid during processing", invalidItemCount))
        end
        endPosition = actualEndPosition
    end

    -- Apply crossfades to overlapping items on each target track
    if globals.Utils and globals.Utils.applyCrossfadesToTrack then
        for _, track in ipairs(targetTracks) do
            globals.Utils.applyCrossfadesToTrack(track)
        end
    end

    -- Create region for this container if enabled
    -- Always use GLOBAL createRegions setting (not per-container override)
    -- because region creation is a project-level concern.
    -- Fix: overrides created before enabling createRegions globally would have
    -- createRegions=false frozen from creation time, preventing region creation.
    local globalParams = Settings.getGlobalParams()
    if globalParams.createRegions and #placedItems > 0 then
        local regionStartPos = nil
        local regionEndPos = nil

        for _, placed in ipairs(placedItems) do
            local itemEnd = placed.position + placed.length
            if regionStartPos == nil or placed.position < regionStartPos then
                regionStartPos = placed.position
            end
            if regionEndPos == nil or itemEnd > regionEndPos then
                regionEndPos = itemEnd
            end
        end

        for _, newItem in ipairs(loopNewItems) do
            local itemEnd = newItem.position + newItem.length
            if regionStartPos == nil or newItem.position < regionStartPos then
                regionStartPos = newItem.position
            end
            if regionEndPos == nil or itemEnd > regionEndPos then
                regionEndPos = itemEnd
            end
        end

        if regionStartPos and regionEndPos then
            local regionName = parseRegionPattern(params.regionPattern, containerInfo, containerExportIndex)
            reaper.AddProjectMarker2(0, true, regionStartPos, regionEndPos, regionName, -1, 0)
        end
    end

    local totalItems = #placedItems + #loopNewItems

    return {
        itemsExported = totalItems,
        endPosition = endPosition,
        warnings = warnings,
        loopNewItems = loopNewItems,
        isEmpty = false
    }
end

-- Main export function - exports Areas from containers using Generation Engine
-- Delegates to Export_Placement for item placement with correct multichannel support
-- Story 4.3: Returns structured ExportResults with per-container status
-- @return boolean: true if any containers exported successfully
-- @return string: Summary message
-- @return table: ExportResults structure with per-container details
function M.performExport()
    local containers = Settings.collectAllContainers()
    local enabledContainers = {}

    -- Filter enabled containers
    for _, c in ipairs(containers) do
        if Settings.isContainerEnabled(c.key) then
            table.insert(enabledContainers, c)
        end
    end

    if #enabledContainers == 0 then
        reaper.ShowMessageBox("No containers are enabled for export.", "Export", 0)
        local emptyResults = createExportResults()
        return false, "No containers enabled", emptyResults
    end

    -- Capture selected parent track before export modifies anything
    local parentTrackGUID = nil
    if reaper.CountSelectedTracks(0) >= 1 then
        local selectedTrack = reaper.GetSelectedTrack(0, 0)
        if selectedTrack then
            parentTrackGUID = reaper.GetTrackGUID(selectedTrack)
        end
    end

    reaper.Undo_BeginBlock()
    reaper.PreventUIRefresh(1)

    -- Record track count before export for post-export relocation
    local firstNewTrackIdx = reaper.GetNumTracks()

    -- Seed random ONCE at export start for consistent randomness across all containers
    math.randomseed(os.time())

    -- Initialize structured export results
    local exportResults = createExportResults()
    local containerExportIndex = 0

    -- Track cumulative position for sequential container placement
    local currentExportPosition = reaper.GetCursorPosition()
    local globalParams = Settings.getGlobalParams()
    local containerSpacing = globalParams.spacing or 1.0

    for _, containerInfo in ipairs(enabledContainers) do
        containerExportIndex = containerExportIndex + 1
        local params = Settings.getEffectiveParams(containerInfo.key)
        local containerName = containerInfo.container.name or "Unknown"
        local containerKey = containerInfo.key

        -- Use pcall to isolate container errors (Story 4.3: AC #1)
        local ok, result = pcall(
            processContainerExport,
            containerInfo,
            params,
            currentExportPosition,
            containerExportIndex
        )

        if not ok then
            -- pcall failed: result contains error message
            local errorMsg = tostring(result)
            local exportResult = createExportResult(
                containerKey,
                containerName,
                "error",
                0,
                { errorMsg },
                {}
            )
            addExportResult(exportResults, exportResult)
            reaper.ShowConsoleMsg("[Export] Error in container '" .. containerName .. "': " .. errorMsg .. "\n")
        elseif result.isEmpty then
            -- Empty container: treated as warning
            local exportResult = createExportResult(
                containerKey,
                containerName,
                "warning",
                0,
                {},
                result.warnings
            )
            addExportResult(exportResults, exportResult)
            -- Story 4.3 fix: Log all warnings, not just the first one
            for _, warn in ipairs(result.warnings) do
                reaper.ShowConsoleMsg("[Export] Warning: Container '" .. containerName .. "' - " .. warn .. "\n")
            end
        elseif #result.warnings > 0 then
            -- Success with warnings
            local exportResult = createExportResult(
                containerKey,
                containerName,
                "warning",
                result.itemsExported,
                {},
                result.warnings
            )
            addExportResult(exportResults, exportResult)
            -- Update position for next container
            if result.itemsExported > 0 and result.endPosition then
                currentExportPosition = result.endPosition + containerSpacing
            end
        else
            -- Full success
            local exportResult = createExportResult(
                containerKey,
                containerName,
                "success",
                result.itemsExported,
                {},
                {}
            )
            addExportResult(exportResults, exportResult)
            -- Update position for next container
            if result.itemsExported > 0 and result.endPosition then
                currentExportPosition = result.endPosition + containerSpacing
            end
        end
    end

    -- Wrap exported tracks in preset parent and/or selected track
    local lastNewTrackIdx = reaper.GetNumTracks() - 1
    if lastNewTrackIdx >= firstNewTrackIdx then
        -- Wrap in preset parent track if a preset is loaded
        local presetName = globals.currentPresetName
        if presetName and presetName ~= "" then
            reaper.InsertTrackAtIndex(firstNewTrackIdx, true)
            local presetParent = reaper.GetTrack(0, firstNewTrackIdx)
            reaper.GetSetMediaTrackInfo_String(presetParent, "P_NAME", presetName, true)
            reaper.SetMediaTrackInfo_Value(presetParent, "I_FOLDERDEPTH", 1)

            local newLastIdx = reaper.GetNumTracks() - 1
            local lastTrack = reaper.GetTrack(0, newLastIdx)
            local depth = reaper.GetMediaTrackInfo_Value(lastTrack, "I_FOLDERDEPTH")
            reaper.SetMediaTrackInfo_Value(lastTrack, "I_FOLDERDEPTH", depth - 1)
        end

        -- Relocate into selected parent track if applicable
        if parentTrackGUID then
            lastNewTrackIdx = reaper.GetNumTracks() - 1
            if lastNewTrackIdx >= firstNewTrackIdx then
                relocateTracksIntoParent(parentTrackGUID, firstNewTrackIdx, lastNewTrackIdx)
            end
        end
    end

    reaper.PreventUIRefresh(-1)
    reaper.UpdateArrange()
    reaper.Undo_EndBlock("Export Ambiance Areas", -1)

    -- Build summary message
    local message = string.format(
        "Exported %d items (%d success, %d warnings, %d errors)",
        exportResults.totalItemsExported,
        exportResults.totalSuccess,
        exportResults.totalWarnings,
        exportResults.totalErrors
    )

    -- Show message box with appropriate title based on results
    if exportResults.totalErrors > 0 then
        reaper.ShowMessageBox(message, "Export Complete (with errors)", 0)
    elseif exportResults.totalWarnings > 0 then
        reaper.ShowMessageBox(message, "Export Complete (with warnings)", 0)
    else
        -- Full success - show simple success message
        local successMessage = string.format("Exported %d items", exportResults.totalItemsExported)
        reaper.ShowMessageBox(successMessage, "Export Complete", 0)
    end

    -- Return success if at least one container succeeded
    -- Note: totalSuccess already includes containers with warnings (see addExportResult)
    local overallSuccess = exportResults.totalSuccess > 0

    -- Save export config to history after successful export
    if overallSuccess and ConfigHistory then
        local savedGlobal = {}
        for k, v in pairs(globalParams) do savedGlobal[k] = v end

        local savedOverrides = {}
        for _, containerInfo in ipairs(enabledContainers) do
            local override = Settings.getContainerOverride(containerInfo.key)
            if override and override.enabled then
                savedOverrides[containerInfo.key] = {
                    enabled = true,
                    params = {}
                }
                for k, v in pairs(override.params) do
                    savedOverrides[containerInfo.key].params[k] = v
                end
            end
        end

        local savedEnabled = {}
        for _, containerInfo in ipairs(containers) do
            savedEnabled[containerInfo.key] = Settings.isContainerEnabled(containerInfo.key)
        end

        ConfigHistory.saveConfig(savedGlobal, savedOverrides, savedEnabled)
    end

    return overallSuccess, message, exportResults
end

-- Generate preview of export showing per-container summary
-- @return table: Array of PreviewEntry objects
function M.generatePreview()
    local previewEntries = {}

    local containers = Settings.collectAllContainers()

    for _, containerInfo in ipairs(containers) do
        if not Settings.isContainerEnabled(containerInfo.key) then
            goto nextContainer
        end

        local params = Settings.getEffectiveParams(containerInfo.key)
        local container = containerInfo.container

        -- Get total pool size (use optimized version since we have containerInfo)
        local poolTotal = Settings.calculatePoolSizeFromInfo
            and Settings.calculatePoolSizeFromInfo(containerInfo)
            or Settings.getPoolSize(containerInfo.key)

        -- Calculate poolSelected based on maxPoolItems
        local poolSelected
        if params.maxPoolItems > 0 and params.maxPoolItems < poolTotal then
            poolSelected = params.maxPoolItems
        else
            poolSelected = poolTotal
        end

        -- Resolve loop mode
        local loopModeResolved = Settings.resolveLoopMode(container, params)
        local loopModeAuto = (params.loopMode == "auto" and loopModeResolved)

        -- Resolve track structure (may error if Generation not available)
        -- Default to mono for single track (consistent with trackCount=1)
        local trackCount = 1
        local trackType = "mono"
        if Placement and globals.Generation then
            local ok, trackStructure = pcall(Placement.resolveTrackStructure, containerInfo)
            if ok and trackStructure then
                trackCount = trackStructure.numTracks or 1
                trackType = trackStructure.trackType or "stereo"
            end
        end

        -- Estimate duration
        local estimatedDuration = M.estimateDuration(poolSelected, params, container)

        -- Build PreviewEntry (includes instanceCount per Architecture 3.4)
        table.insert(previewEntries, {
            name = containerInfo.displayName,
            poolTotal = poolTotal,
            poolSelected = poolSelected,
            loopMode = loopModeResolved,
            loopModeAuto = loopModeAuto,
            loopDuration = loopModeResolved and (params.loopDuration or 30) or nil,
            trackCount = trackCount,
            trackType = trackType,
            estimatedDuration = estimatedDuration,
            instanceCount = params.instanceAmount or 1,
        })

        ::nextContainer::
    end

    return previewEntries
end

-- Estimate total duration of export for a container
-- @param poolSize number: Number of items/areas that will be exported
-- @param params table: Export params with instanceAmount, spacing
-- @param container table: Container object with items for avg length calculation
-- @return number: Estimated duration in seconds
function M.estimateDuration(poolSize, params, container)
    if poolSize == 0 then return 0 end

    -- Calculate average item length from container items or use default
    local avgItemLength = 5.0  -- Default: 5 seconds
    if container and container.items and #container.items > 0 then
        local totalLength = 0
        local itemCount = 0
        for _, item in ipairs(container.items) do
            if item.length and item.length > 0 then
                totalLength = totalLength + item.length
                itemCount = itemCount + 1
            end
        end
        if itemCount > 0 then
            avgItemLength = totalLength / itemCount
        end
    end

    -- Calculate total items: poolSize * instanceAmount
    local totalItems = poolSize * (params.instanceAmount or 1)

    -- Calculate duration: (totalItems * avgItemLength) + ((totalItems - 1) * spacing)
    local spacing = params.spacing or 0
    local duration = (totalItems * avgItemLength)
    if totalItems > 1 then
        duration = duration + ((totalItems - 1) * spacing)
    end

    -- If loop mode is enabled, return loopDuration as the estimated duration
    -- Use resolveLoopMode for consistency with actual export behavior
    local isLoopMode = Settings and Settings.resolveLoopMode
        and Settings.resolveLoopMode(container, params)
        or false
    if isLoopMode then
        -- For loop mode, loopDuration defines the target duration
        if params.loopDuration and params.loopDuration > 0 then
            return params.loopDuration
        end
    end

    return duration
end

return M
