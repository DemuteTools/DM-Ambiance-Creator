--[[
@version 1.0
@noindex
DM Ambiance Creator - Generation Item Placement Module
Core item placement logic for timeline generation.
--]]

local Generation_ItemPlacement = {}
local globals = {}

-- Dependencies (set by aggregator)
local Generation_TrackManagement = nil
local Generation_MultiChannel = nil

function Generation_ItemPlacement.initModule(g)
    globals = g
end

function Generation_ItemPlacement.setDependencies(trackMgmt, multiChannel)
    Generation_TrackManagement = trackMgmt
    Generation_MultiChannel = multiChannel
end

-- Clear only items that overlap with the current time selection from a track
-- Used when keepExistingTracks is true to preserve content outside the selection
local function clearItemsInTimeSelection(track)
    local itemsToDelete = {}
    local itemCount = reaper.CountTrackMediaItems(track)
    for i = 0, itemCount - 1 do
        local item = reaper.GetTrackMediaItem(track, i)
        local pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
        local len = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
        local itemEnd = pos + len
        -- Delete items that overlap with the time selection
        if pos < globals.endTime and itemEnd > globals.startTime then
            table.insert(itemsToDelete, item)
        end
    end
    -- Delete in reverse order to avoid index issues
    for i = #itemsToDelete, 1, -1 do
        reaper.DeleteTrackMediaItem(track, itemsToDelete[i])
    end
end

-- ═══════════════════════════════════════════════════════════════════════════════
-- CORE ITEM PLACEMENT FUNCTION
-- ═══════════════════════════════════════════════════════════════════════════════

--- Place a single item instance on a specific track
--- @param targetTrack userdata: REAPER track to place item on
--- @param itemData table: Item data (filePath, startOffset, length, etc.)
--- @param position number: Timeline position in seconds
--- @param effectiveParams table: Container parameters
--- @param trackStructure table: Track structure information
--- @param trackIdx number: Real track index for channel extraction
--- @param channelSelectionMode string: Channel selection mode
--- @param ignoreBounds boolean|nil: If true, ignore timeline bounds (globals.endTime) - useful for export
--- @return userdata|nil: The created media item or nil if failed
--- @return number: The actual length of the placed item
function Generation_ItemPlacement.placeSingleItem(targetTrack, itemData, position, effectiveParams, trackStructure, trackIdx, channelSelectionMode, ignoreBounds)
    if not targetTrack or not itemData then return nil, 0 end

    -- Create and configure the new item on current track
    local newItem = reaper.AddMediaItemToTrack(targetTrack)
    local newTake = reaper.AddTakeToMediaItem(newItem)

    -- Configure the item
    local PCM_source = reaper.PCM_Source_CreateFromFile(itemData.filePath)
    if not PCM_source then
        reaper.DeleteTrackMediaItem(targetTrack, newItem)
        return nil, 0
    end

    reaper.SetMediaItemTake_Source(newTake, PCM_source)
    reaper.SetMediaItemTakeInfo_Value(newTake, "D_STARTOFFS", itemData.startOffset)

    -- Apply channel selection if needed (use real track index for correct channel extraction)
    local needsChannelSelection = trackStructure and trackStructure.needsChannelSelection
    if needsChannelSelection then
        local itemChannels = itemData.numChannels or 2
        Generation_MultiChannel.applyChannelSelection(newItem, effectiveParams, itemChannels, channelSelectionMode, trackStructure, trackIdx)
    end

    -- Trim item so it never exceeds the selection end (unless explicitly ignored)
    -- For export, ignoreBounds allows placing items beyond the time selection
    local maxLen = itemData.length
    if not ignoreBounds and globals.endTime and globals.endTime > 0 then
        maxLen = globals.endTime - position
    end
    local actualLen = math.min(itemData.length, maxLen)

    -- Pre-calculate pitch and adjust length if using STRETCH mode
    local randomPitch = nil
    local playrate = nil
    if effectiveParams.pitchMode == globals.Constants.PITCH_MODES.STRETCH then
        local basePitch = effectiveParams.flattenPitch and 0 or itemData.originalPitch
        if effectiveParams.randomizePitch then
            randomPitch = basePitch + globals.Utils.randomInRange(effectiveParams.pitchRange.min, effectiveParams.pitchRange.max)
        else
            randomPitch = basePitch
        end
        playrate = globals.Utils.semitonesToPlayrate(randomPitch)

        -- Adjust length for playrate (slower playrate = longer item)
        actualLen = actualLen / playrate
        -- Re-clamp to timeline bounds if needed
        if not ignoreBounds and globals.endTime and globals.endTime > 0 then
             local boundMaxLen = globals.endTime - position
             actualLen = math.min(actualLen, boundMaxLen)
        end
    end

    reaper.SetMediaItemInfo_Value(newItem, "D_POSITION", position)
    reaper.GetSetMediaItemTakeInfo_String(newTake, "P_NAME", itemData.name, true)

    -- Apply randomization (pitch, volume, pan)
    -- Pass pre-calculated pitch/playrate to avoid generating different random values
    -- (the length was already adjusted using these values above)
    Generation_ItemPlacement.applyRandomization(newItem, newTake, effectiveParams, itemData, trackStructure, randomPitch, playrate)

    -- Set D_LENGTH with adjusted value (after playrate adjustment if STRETCH mode)
    reaper.SetMediaItemInfo_Value(newItem, "D_LENGTH", actualLen)

    -- Apply fades if enabled
    if effectiveParams.fadeInEnabled or effectiveParams.fadeOutEnabled then
        Generation_ItemPlacement.applyFades(newItem, effectiveParams, actualLen)
    end
    
    return newItem, actualLen
end

--- Main function to place items on the timeline for a container
--- Handles all interval modes, multi-channel routing, and randomization
--- @param group table: Parent group containing the container
--- @param container table: Container configuration with items and parameters
--- @param containerGroup userdata: REAPER track to place items on
--- @param xfadeshape number: Crossfade shape from REAPER preferences
function Generation_ItemPlacement.placeItemsForContainer(group, container, containerGroup, xfadeshape)
    -- Get effective parameters considering inheritance from parent group
    local effectiveParams = globals.Structures.getEffectiveContainerParams(group, container)

    -- Find group and container indices for area functionality
    local groupIndex = nil
    local containerIndex = nil
    for gi, g in ipairs(globals.groups) do
        for ci, c in ipairs(g.containers) do
            if c == container then
                groupIndex = gi
                containerIndex = ci
                break
            end
        end
        if groupIndex then break end
    end

    -- Analyze items and determine track structure
    local itemsAnalysis = Generation_MultiChannel.analyzeContainerItems(container)
    local trackStructure = globals.Generation.determineTrackStructure(container, itemsAnalysis)

    local hasChildTracks = reaper.GetMediaTrackInfo_Value(containerGroup, "I_FOLDERDEPTH") == 1
    local isLastInGroup = (containerIndex == #group.containers)
    local channelTracks = {}

    -- Get existing track structure
    local existingTracks = Generation_TrackManagement.getExistingChannelTracks(containerGroup)
    local numExistingTracks = #existingTracks

    -- Check if structure needs to be recreated
    local needsRecreate = false

    if trackStructure.numTracks == 1 and hasChildTracks then
        -- Need single track but have children
        needsRecreate = true
    elseif trackStructure.numTracks > 1 and not hasChildTracks then
        -- Need multiple tracks but don't have children
        needsRecreate = true
    elseif trackStructure.numTracks > 1 and numExistingTracks ~= trackStructure.numTracks then
        -- Wrong number of child tracks
        needsRecreate = true
    end

    if needsRecreate then
        -- Clear existing structure
        if hasChildTracks then
            Generation_TrackManagement.deleteContainerChildTracks(containerGroup)
        else
            -- Clear items from single track
            while reaper.CountTrackMediaItems(containerGroup) > 0 do
                local item = reaper.GetTrackMediaItem(containerGroup, 0)
                reaper.DeleteTrackMediaItem(containerGroup, item)
            end
        end

        -- Create new structure
        channelTracks = Generation_TrackManagement.createMultiChannelTracks(containerGroup, container, isLastInGroup)
    else
        -- Structure is correct, just clear items
        if globals.keepExistingTracks then
            -- Only clear items within the current time selection, preserving content outside
            if hasChildTracks then
                for _, track in ipairs(existingTracks) do
                    clearItemsInTimeSelection(track)
                end
            else
                clearItemsInTimeSelection(containerGroup)
            end
        else
            if hasChildTracks then
                Generation_TrackManagement.clearChannelTracks(existingTracks)
            else
                while reaper.CountTrackMediaItems(containerGroup) > 0 do
                    local item = reaper.GetTrackMediaItem(containerGroup, 0)
                    reaper.DeleteTrackMediaItem(containerGroup, item)
                end
            end
        end
        channelTracks = existingTracks

        -- CRITICAL FIX: Update channel count even when not recreating tracks
        -- This handles cases like perfect-match-passthrough where trackStructure changes
        -- but the physical track structure remains the same (1 track, no children)
        if trackStructure.numTracks == 1 and not hasChildTracks then
            -- Single track case: update I_NCHAN based on trackStructure
            local requiredChannels = trackStructure.trackChannels
            if requiredChannels and requiredChannels > 0 then
                -- Round up to even number
                if requiredChannels % 2 == 1 then
                    requiredChannels = requiredChannels + 1
                end
                reaper.SetMediaTrackInfo_Value(containerGroup, "I_NCHAN", requiredChannels)
            end
        end

        -- Store/update GUIDs
        if trackStructure.numTracks > 1 then
            Generation_TrackManagement.storeTrackGUIDs(container, containerGroup, channelTracks)
        else
            container.trackGUID = Generation_TrackManagement.getTrackGUID(containerGroup)
        end
    end

    local skippedItems = 0
    local minRequiredLength = 0
    local containerName = container.name or "Unnamed Container"

    if effectiveParams.items and #effectiveParams.items > 0 then
        -- Calculate interval based on the selected mode
        local interval = effectiveParams.triggerRate -- Default (Absolute mode)

        if effectiveParams.intervalMode == 1 then
            -- Relative mode: Interval is a percentage of time selection length
            interval = (globals.timeSelectionLength * effectiveParams.triggerRate) / 100
        elseif effectiveParams.intervalMode == 2 then
            -- Coverage mode: Interval will be calculated dynamically per item
            -- Formula: interval = itemLength × (100 / coverage%)
            -- This ensures the coverage percentage represents the actual audio duration
            -- Examples:
            --   50% coverage → item + equal silence → interval = itemLength × 2
            --   100% coverage → no silence → interval = itemLength × 1
            --   25% coverage → item + 3× silence → interval = itemLength × 4
            interval = 0 -- Will be calculated per item in the loop
        elseif effectiveParams.intervalMode == 3 then
            -- Chunk mode: Generate chunks with sound periods followed by silence periods
            -- For multi-channel (including stereo with mono split), generate on each track
            if #channelTracks > 1 then
                for _, channelTrack in ipairs(channelTracks) do
                    Generation_ItemPlacement.placeItemsChunkMode(effectiveParams, channelTrack)
                    globals.Utils.applyCrossfadesToTrack(channelTrack)
                end
                return
            else
                Generation_ItemPlacement.placeItemsChunkMode(effectiveParams, containerGroup)
                globals.Utils.applyCrossfadesToTrack(containerGroup)
                return
            end
        elseif effectiveParams.intervalMode == 4 then
            -- Noise mode: Place items based on Perlin noise probability
            -- For multi-channel (including stereo with mono split), generate on each track
            if #channelTracks > 1 then
                for _, channelTrack in ipairs(channelTracks) do
                    globals.Generation.placeItemsNoiseMode(effectiveParams, channelTrack, channelTracks, container, trackStructure, xfadeshape)
                    globals.Utils.applyCrossfadesToTrack(channelTrack)
                end
                return
            else
                globals.Generation.placeItemsNoiseMode(effectiveParams, containerGroup, channelTracks, container, trackStructure, xfadeshape)
                globals.Utils.applyCrossfadesToTrack(containerGroup)
                return
            end
        elseif effectiveParams.intervalMode == 5 then
            -- Euclidean Rhythm mode
            -- For multi-channel (including stereo with mono split), generate on each track
            if #channelTracks > 1 then
                for _, channelTrack in ipairs(channelTracks) do
                    globals.Generation.placeItemsEuclideanMode(effectiveParams, channelTrack, channelTracks, container, trackStructure, xfadeshape)
                    globals.Utils.applyCrossfadesToTrack(channelTrack)
                end
                return
            else
                globals.Generation.placeItemsEuclideanMode(effectiveParams, containerGroup, channelTracks, container, trackStructure, xfadeshape)
                globals.Utils.applyCrossfadesToTrack(containerGroup)
                return
            end
        end

        -- Analyze items and determine track structure for placement logic
        local itemsAnalysis = Generation_MultiChannel.analyzeContainerItems(container)
        local trackStructure = globals.Generation.determineTrackStructure(container, itemsAnalysis)

        -- SPECIAL CASE: Independent generation for "All Tracks" mode
        -- Must be checked BEFORE entering the main loop
        local distributionMode = container.itemDistributionMode or 0
        if trackStructure.useDistribution and distributionMode == 2 then
            -- All Tracks mode - generate independently for each track
            local needsChannelSelection = trackStructure.needsChannelSelection
            local channelSelectionMode = trackStructure.channelSelectionMode or container.channelSelectionMode or "none"

            for trackIdx, targetTrack in ipairs(channelTracks) do
                Generation_ItemPlacement.generateIndependentTrack(targetTrack, trackIdx, container, effectiveParams, channelTracks, trackStructure, needsChannelSelection, channelSelectionMode)
                globals.Utils.applyCrossfadesToTrack(targetTrack)
            end

            -- Exit completely - independent generation is done
            return
        end

        -- Reset for generation
        local lastItemRef = nil
        local isFirstItem = true
        local lastItemEnd = globals.startTime
        local theoreticalPosition = globals.startTime  -- Track theoretical position for coverage drift

        while lastItemEnd < globals.endTime do
            -- Select a random item from the container
            local randomItemIndex = math.random(1, #effectiveParams.items)
            local originalItemData = effectiveParams.items[randomItemIndex]

            -- Select area if available, or use full item
            local itemData = globals.Utils.selectRandomAreaOrFullItem(originalItemData)

            -- Determine which tracks to place this item on
            local targetTracks = {channelTracks[1]} -- Default
            local itemChannels = itemData.numChannels or 2
            local needsChannelSelection = trackStructure.needsChannelSelection
            -- Use the mode from trackStructure if it was overridden by auto-optimization
            local channelSelectionMode = trackStructure.channelSelectionMode or container.channelSelectionMode or "none"

            -- Check for custom routing matrix first
            local useCustomRouting = false
            if container.customItemRouting and container.customItemRouting[randomItemIndex] then
                local customRouting = container.customItemRouting[randomItemIndex]
                if customRouting.routingMatrix and not customRouting.isAutoRouting then
                    -- Use custom routing: place item on specified tracks
                    useCustomRouting = true
                    targetTracks = {}
                    local uniqueTracks = {}
                    for srcCh, destCh in pairs(customRouting.routingMatrix) do
                        if destCh > 0 and channelTracks[destCh] and not uniqueTracks[destCh] then
                            table.insert(targetTracks, channelTracks[destCh])
                            uniqueTracks[destCh] = true
                        end
                    end
                    if #targetTracks == 0 then
                        targetTracks = {channelTracks[1]}
                    end
                end
            end

            -- If no custom routing, use automatic distribution
            local distributionMode = container.itemDistributionMode or 0

            -- Track indices for channel extraction (maps position in targetTracks to real track index)
            local targetTrackIndices = {}

            if not useCustomRouting then
                if trackStructure.numTracks == 1 then
                    -- Single track: place item there
                    targetTracks = {channelTracks[1]}
                    targetTrackIndices = {1}
                elseif trackStructure.useSmartRouting then
                    -- Smart routing: place on all tracks (each will extract different channel)
                    targetTracks = channelTracks
                    for i = 1, #channelTracks do
                        targetTrackIndices[i] = i
                    end
                elseif trackStructure.useDistribution then
                    -- Mono items or items that need distribution: distribute across tracks

                    if distributionMode == 0 then
                        -- Round-robin
                        if not container.distributionCounter then
                            container.distributionCounter = 0
                        end
                        container.distributionCounter = container.distributionCounter + 1
                        local targetChannel = ((container.distributionCounter - 1) % #channelTracks) + 1
                        targetTracks = {channelTracks[targetChannel]}
                        targetTrackIndices = {targetChannel}  -- Store real track index!
                    elseif distributionMode == 1 then
                        -- Random
                        local targetChannel = math.random(1, #channelTracks)
                        targetTracks = {channelTracks[targetChannel]}
                        targetTrackIndices = {targetChannel}  -- Store real track index!
                    -- distributionMode == 2 (All tracks) is handled BEFORE the main loop
                    end
                else
                    -- All other cases: use all tracks or first track
                    targetTracks = channelTracks
                    for i = 1, #channelTracks do
                        targetTrackIndices[i] = i
                    end
                end
            else
                -- Custom routing: build indices from channelTracks positions
                for i, track in ipairs(targetTracks) do
                    for j, chTrack in ipairs(channelTracks) do
                        if track == chTrack then
                            targetTrackIndices[i] = j
                            break
                        end
                    end
                end
            end

            -- Vérification pour les intervalles négatifs
            if interval < 0 then
                local requiredLength = math.abs(interval)
                if itemData.length < requiredLength then
                    -- Item trop court, on le skip
                    skippedItems = skippedItems + 1
                    if minRequiredLength == 0 or requiredLength > minRequiredLength then
                        minRequiredLength = requiredLength
                    end

                    -- Avancer légèrement pour éviter une boucle infinie
                    lastItemEnd = lastItemEnd + 0.1
                    goto continue_loop -- Skip cet item et passer au suivant
                end
            end

            local position
            local maxDrift
            local drift

            -- Coverage mode: calculate interval based on current item length BEFORE placement
            if effectiveParams.intervalMode == 2 then
                local coveragePercent = effectiveParams.triggerRate
                if coveragePercent > 0 then
                    interval = itemData.length * (100 / coveragePercent)
                else
                    interval = globals.timeSelectionLength -- Fallback for 0% coverage
                end
            end

            -- Placement spécial pour le premier item
            -- Coverage mode: check interval > 0 OR intervalMode == 2
            if isFirstItem and (interval > 0 or effectiveParams.intervalMode == 2) then
                -- Coverage mode: place first item at startTime with optional drift
                if effectiveParams.intervalMode == 2 then
                    position = globals.startTime
                    -- Apply drift if triggerDrift > 0
                    if effectiveParams.triggerDrift > 0 and interval > 0 then
                        -- Calculate drift range based on interval
                        -- At 100% drift, item can move ±100% of the interval (full interval range)
                        local drift = globals.Utils.applyDirectionalVariation(interval, effectiveParams.triggerDrift, effectiveParams.triggerDriftDirection)
                        position = position + drift
                        -- Clamp to startTime (can't go before timeline start)
                        if position < globals.startTime then
                            position = globals.startTime
                        end
                    end
                else
                    -- Other modes: place randomly between startTime and startTime+interval
                    position = globals.startTime + math.random() * interval
                end
                -- Don't set isFirstItem = false yet - let it be set after lastItemEnd is updated
            else
                -- Calcul standard de position pour les items suivants
                if effectiveParams.intervalMode == 0 and interval < 0 then
                    -- Negative spacing creates overlap with the last item
                    drift = globals.Utils.applyDirectionalVariation(math.abs(interval), effectiveParams.triggerDrift, effectiveParams.triggerDriftDirection)
                    position = lastItemEnd + interval + drift
                elseif effectiveParams.intervalMode == 2 then
                    -- Coverage mode: drift moves items around theoretical position, but prevents overlap
                    -- Start from theoretical position (advances by interval regardless of drift)
                    local idealPosition = theoreticalPosition

                    if effectiveParams.triggerDrift > 0 and interval > 0 then
                        -- At 100% drift, item can move ±100% of the interval (full interval range)
                        local drift = globals.Utils.applyDirectionalVariation(interval, effectiveParams.triggerDrift, effectiveParams.triggerDriftDirection)
                        idealPosition = idealPosition + drift
                    end

                    -- COLLISION DETECTION: Items cannot overlap with the ACTUAL previous item
                    -- If drift would cause overlap, push item to touch previous item (creating chunks)
                    if idealPosition < lastItemEnd then
                        position = lastItemEnd  -- Push against previous item (no gap)
                    else
                        position = idealPosition  -- Use drifted position
                    end
                else
                    -- Regular spacing from the end of the last item (ABSOLUTE and RELATIVE modes)
                    drift = globals.Utils.applyDirectionalVariation(interval, effectiveParams.triggerDrift, effectiveParams.triggerDriftDirection)
                    position = lastItemEnd + interval + drift
                end

                -- Ensure no item starts before time selection
                if position < globals.startTime then
                    position = globals.startTime
                end
            end

            -- Stop if the item would start beyond the end of the time selection
            if position >= globals.endTime then
                break
            end

            -- Place the item on all target tracks determined by channel routing
            for i, targetTrack in ipairs(targetTracks) do
                -- Get the real track index for channel extraction
                local realTrackIdx = targetTrackIndices[i] or i

                -- Create and configure the new item on current track
                local newItem = reaper.AddMediaItemToTrack(targetTrack)
                local newTake = reaper.AddTakeToMediaItem(newItem)

                -- Configure the item
                local PCM_source = reaper.PCM_Source_CreateFromFile(itemData.filePath)
                reaper.SetMediaItemTake_Source(newTake, PCM_source)
                reaper.SetMediaItemTakeInfo_Value(newTake, "D_STARTOFFS", itemData.startOffset)

                -- Apply channel selection if needed (use real track index for correct channel extraction)
                if needsChannelSelection then
                    Generation_MultiChannel.applyChannelSelection(newItem, container, itemChannels, channelSelectionMode, trackStructure, realTrackIdx)
                end

                -- Trim item so it never exceeds the selection end
                local maxLen = globals.endTime - position
                local actualLen = math.min(itemData.length, maxLen)

                -- Pre-calculate pitch and adjust length if using STRETCH mode
                -- This must happen BEFORE coverage calculation to use adjusted length
                local randomPitch = nil
                local playrate = nil
                if effectiveParams.pitchMode == globals.Constants.PITCH_MODES.STRETCH then
                    if effectiveParams.randomizePitch then
                        randomPitch = itemData.originalPitch + globals.Utils.randomInRange(effectiveParams.pitchRange.min, effectiveParams.pitchRange.max)
                    else
                        randomPitch = itemData.originalPitch
                    end
                    playrate = globals.Utils.semitonesToPlayrate(randomPitch)

                    -- Adjust length for playrate (slower playrate = longer item)
                    actualLen = actualLen / playrate
                    actualLen = math.min(actualLen, maxLen)  -- Re-clamp to timeline bounds
                end

                -- Coverage mode: calculate interval based on ACTUAL item length (after trimming and playrate adjustment)
                -- This ensures accurate coverage even when items are trimmed at timeline end or stretched
                if effectiveParams.intervalMode == 2 and i == 1 then
                    local coveragePercent = effectiveParams.triggerRate
                    if coveragePercent > 0 then
                        interval = actualLen * (100 / coveragePercent)
                    else
                        interval = globals.timeSelectionLength -- Fallback for 0% coverage
                    end
                end

                reaper.SetMediaItemInfo_Value(newItem, "D_POSITION", position)
                reaper.GetSetMediaItemTakeInfo_String(newTake, "P_NAME", itemData.name, true)

                -- Apply randomizations using effective parameters
                if effectiveParams.randomizePitch then
                    if effectiveParams.pitchMode == globals.Constants.PITCH_MODES.STRETCH then
                        -- Use time stretch (D_PLAYRATE) - already calculated above
                        reaper.SetMediaItemTakeInfo_Value(newTake, "D_PLAYRATE", playrate)
                        reaper.SetMediaItemTakeInfo_Value(newTake, "B_PPITCH", 0)  -- Disable preserve pitch for stretch mode
                    else
                        -- Use standard pitch shift (D_PITCH)
                        local pitchValue = itemData.originalPitch + globals.Utils.randomInRange(effectiveParams.pitchRange.min, effectiveParams.pitchRange.max)
                        reaper.SetMediaItemTakeInfo_Value(newTake, "D_PITCH", pitchValue)
                    end
                else
                    if effectiveParams.pitchMode == globals.Constants.PITCH_MODES.STRETCH then
                        -- Use time stretch (D_PLAYRATE) - already calculated above
                        reaper.SetMediaItemTakeInfo_Value(newTake, "D_PLAYRATE", playrate)
                        reaper.SetMediaItemTakeInfo_Value(newTake, "B_PPITCH", 0)  -- Disable preserve pitch for stretch mode
                    else
                        reaper.SetMediaItemTakeInfo_Value(newTake, "D_PITCH", itemData.originalPitch)
                    end
                end

                -- Set D_LENGTH with adjusted value (after playrate adjustment if STRETCH mode)
                reaper.SetMediaItemInfo_Value(newItem, "D_LENGTH", actualLen)

                -- Apply gain from item settings
                local gainDB = itemData.gainDB or 0.0
                local gainScale = 10 ^ (gainDB / 20)  -- Convert dB to linear

                if effectiveParams.randomizeVolume then
                    local randomVolume = itemData.originalVolume * gainScale * 10^(globals.Utils.randomInRange(effectiveParams.volumeRange.min, effectiveParams.volumeRange.max) / 20)
                    reaper.SetMediaItemTakeInfo_Value(newTake, "D_VOL", randomVolume)
                else
                    reaper.SetMediaItemTakeInfo_Value(newTake, "D_VOL", itemData.originalVolume * gainScale)
                end

                -- Apply pan randomization for stereo items
                -- Enable for: stereo containers, OR stereo items on stereo tracks
                local canUsePan = false
                if not effectiveParams.channelMode or effectiveParams.channelMode == 0 then
                    -- Stereo container
                    canUsePan = true
                elseif trackStructure.trackType == "stereo" and trackStructure.trackChannels == 2 then
                    -- Stereo items on stereo tracks in multichannel
                    canUsePan = true
                end

                if effectiveParams.randomizePan and canUsePan then
                    local randomPan = itemData.originalPan - globals.Utils.randomInRange(effectiveParams.panRange.min, effectiveParams.panRange.max) / 100
                    randomPan = math.max(-1, math.min(1, randomPan))
                    -- Use envelope instead of directly modifying the property
                    globals.Items.createTakePanEnvelope(newTake, randomPan)
                end

                -- Apply fade in if enabled
                if effectiveParams.fadeInEnabled then
                    local fadeInDuration = effectiveParams.fadeInDuration or 0.1
                    -- Convert percentage to seconds if using percentage mode
                    if effectiveParams.fadeInUsePercentage then
                        fadeInDuration = (fadeInDuration / 100) * actualLen
                    end
                    -- Ensure fade doesn't exceed item length
                    fadeInDuration = math.min(fadeInDuration, actualLen)

                    reaper.SetMediaItemInfo_Value(newItem, "D_FADEINLEN", fadeInDuration)
                    reaper.SetMediaItemInfo_Value(newItem, "C_FADEINSHAPE", effectiveParams.fadeInShape or 0)
                    reaper.SetMediaItemInfo_Value(newItem, "D_FADEINDIR", effectiveParams.fadeInCurve or 0.0)
                end

                -- Apply fade out if enabled
                if effectiveParams.fadeOutEnabled then
                    local fadeOutDuration = effectiveParams.fadeOutDuration or 0.1
                    -- Convert percentage to seconds if using percentage mode
                    if effectiveParams.fadeOutUsePercentage then
                        fadeOutDuration = (fadeOutDuration / 100) * actualLen
                    end
                    -- Ensure fade doesn't exceed item length
                    fadeOutDuration = math.min(fadeOutDuration, actualLen)

                    reaper.SetMediaItemInfo_Value(newItem, "D_FADEOUTLEN", fadeOutDuration)
                    reaper.SetMediaItemInfo_Value(newItem, "C_FADEOUTSHAPE", effectiveParams.fadeOutShape or 0)
                    reaper.SetMediaItemInfo_Value(newItem, "D_FADEOUTDIR", effectiveParams.fadeOutCurve or 0.0)
                end

                -- Update global references for next iteration (only from first track)
                -- Used for loop control and position calculation
                if i == 1 then
                    -- Coverage mode with drift:
                    -- - lastItemEnd = actual end of placed item (for collision detection)
                    -- - theoreticalPosition = ideal next position (advances by interval, ignores drift)
                    if effectiveParams.intervalMode == 2 then
                        lastItemEnd = position + actualLen  -- Actual end of this item
                        theoreticalPosition = theoreticalPosition + interval  -- Advance by interval for next item's drift base
                    else
                        -- Other modes: standard behavior
                        lastItemEnd = position + actualLen
                    end
                    lastItemRef = newItem
                    -- Mark first item as placed after lastItemEnd is updated
                    if isFirstItem then
                        isFirstItem = false
                    end
                end
            end  -- End of for loop for target tracks

            ::continue_loop::
        end  -- End of while loop

        -- Apply crossfades to all overlapping items on each track
        -- Using REAPER's built-in action 41059 for unified crossfade handling
        if #channelTracks > 0 then
            for _, track in ipairs(channelTracks) do
                globals.Utils.applyCrossfadesToTrack(track)
            end
        else
            globals.Utils.applyCrossfadesToTrack(containerGroup)
        end

        -- Message d'erreur pour les items skippés
        if skippedItems > 0 then
            local message = string.format(
                "Warning: %d item(s) were skipped in container '%s'\n" ..
                "Reason: Item length insufficient for negative interval of %.2f seconds\n" ..
                "Minimum required item length: %.2f seconds",
                skippedItems,
                containerName,
                math.abs(interval),
                minRequiredLength
            )

            -- reaper.ShowConsoleMsg(message .. "\n")
        end
    end

    -- Create crossfades with existing items if they exist
    if globals.crossfadeItems and globals.crossfadeItems[containerGroup] then
        local crossfadeData = globals.crossfadeItems[containerGroup]

        -- Create crossfades with items at the start of the time selection
        for _, startItem in ipairs(crossfadeData.startItems) do
            local startItemEnd = reaper.GetMediaItemInfo_Value(startItem, "D_POSITION") +
                                reaper.GetMediaItemInfo_Value(startItem, "D_LENGTH")

            -- Find new items that overlap with this start item
            local containerItemCount = reaper.GetTrackNumMediaItems(containerGroup)
            for i = 0, containerItemCount - 1 do
                local newItem = reaper.GetTrackMediaItem(containerGroup, i)
                local newItemStart = reaper.GetMediaItemInfo_Value(newItem, "D_POSITION")

                -- Check if the new item overlaps with the start item
                if newItemStart < startItemEnd and newItemStart >= globals.startTime then
                    globals.Utils.createCrossfade(startItem, newItem, xfadeshape)
                    break -- One crossfade per start item is enough
                end
            end
        end

        -- Create crossfades with items at the end of the time selection
        for _, endItem in ipairs(crossfadeData.endItems) do
            local endItemStart = reaper.GetMediaItemInfo_Value(endItem, "D_POSITION")

            -- Find new items that overlap with this end item
            local containerItemCount = reaper.GetTrackNumMediaItems(containerGroup)
            for i = containerItemCount - 1, 0, -1 do -- Start from the end
                local newItem = reaper.GetTrackMediaItem(containerGroup, i)
                local newItemStart = reaper.GetMediaItemInfo_Value(newItem, "D_POSITION")
                local newItemEnd = newItemStart + reaper.GetMediaItemInfo_Value(newItem, "D_LENGTH")

                -- Check if the new item overlaps with the end item
                if newItemEnd > endItemStart and newItemEnd <= globals.endTime then
                    globals.Utils.createCrossfade(newItem, endItem, xfadeshape)
                    break -- One crossfade per end item is enough
                end
            end
        end

        -- Clean up the crossfade data after use
        globals.crossfadeItems[containerGroup] = nil
    end

end

-- ═══════════════════════════════════════════════════════════════════════════════
-- CHUNK MODE GENERATION
-- ═══════════════════════════════════════════════════════════════════════════════

--- Place items using Chunk Mode
--- Creates structured patterns of sound chunks separated by silence periods
--- @param effectiveParams table: Container parameters with chunk settings
--- @param containerGroup userdata: REAPER track to place items on
function Generation_ItemPlacement.placeItemsChunkMode(effectiveParams, containerGroup)
    if not effectiveParams.items or #effectiveParams.items == 0 then
        return
    end

    local chunkDuration = effectiveParams.chunkDuration
    local silenceDuration = effectiveParams.chunkSilence
    local chunkDurationVariation = effectiveParams.chunkDurationVariation / 100 -- Convert to ratio
    local chunkSilenceVariation = effectiveParams.chunkSilenceVariation / 100 -- Convert to ratio

    local lastItemRef = nil
    local currentTime = globals.startTime

    -- Process chunks until we reach the end of the time selection
    while currentTime < globals.endTime do
        -- Calculate actual chunk duration with variation (corrected formula)
        local actualChunkDuration = chunkDuration
        if chunkDurationVariation > 0 then
            local variation = globals.Utils.applyDirectionalVariation(1.0, effectiveParams.chunkDurationVariation, effectiveParams.chunkDurationVarDirection)
            actualChunkDuration = chunkDuration * (1 + variation)
            actualChunkDuration = math.max(0.1, actualChunkDuration)
        end

        -- Calculate actual silence duration with variation (separate control)
        local actualSilenceDuration = silenceDuration
        if chunkSilenceVariation > 0 then
            local variation = globals.Utils.applyDirectionalVariation(1.0, effectiveParams.chunkSilenceVariation, effectiveParams.chunkSilenceVarDirection)
            actualSilenceDuration = silenceDuration * (1 + variation)
            actualSilenceDuration = math.max(0, actualSilenceDuration)
        end

        local chunkEnd = math.min(currentTime + actualChunkDuration, globals.endTime)

        -- Generate items within this chunk period
        if chunkEnd > currentTime then
            lastItemRef = Generation_ItemPlacement.generateItemsInTimeRange(effectiveParams, containerGroup, currentTime, chunkEnd, lastItemRef)
        end

        -- Progress using the actual durations that were calculated
        currentTime = currentTime + actualChunkDuration + actualSilenceDuration

        -- Break if we've gone beyond the time selection
        if currentTime >= globals.endTime then
            break
        end
    end
end

-- ═══════════════════════════════════════════════════════════════════════════════
-- HELPER FUNCTIONS
-- ═══════════════════════════════════════════════════════════════════════════════

--- Helper function to generate items within a specific time range for chunk mode
--- @param effectiveParams table: Container parameters
--- @param containerGroup userdata: REAPER track to place items on
--- @param rangeStart number: Start time of the chunk
--- @param rangeEnd number: End time of the chunk
--- @param lastItemRef userdata: Reference to last placed item
--- @return userdata: Reference to last placed item
function Generation_ItemPlacement.generateItemsInTimeRange(effectiveParams, containerGroup, rangeStart, rangeEnd, lastItemRef)
    local rangeLength = rangeEnd - rangeStart
    if rangeLength <= 0 then
        return lastItemRef
    end

    -- Use the trigger rate as interval within chunks
    local interval = effectiveParams.triggerRate
    local currentTime = rangeStart
    local isFirstItem = true
    local itemCount = 0
    local maxItemsPerChunk = 1000 -- Protection contre boucle infinie

    while currentTime < rangeEnd and itemCount < maxItemsPerChunk do
        itemCount = itemCount + 1
        -- Select a random item from the container
        local randomItemIndex = math.random(1, #effectiveParams.items)
        local originalItemData = effectiveParams.items[randomItemIndex]

        -- Select area if available, or use full item
        local itemData = globals.Utils.selectRandomAreaOrFullItem(originalItemData)

        -- Vérification pour les intervalles négatifs (overlap)
        if interval < 0 then
            local requiredLength = math.abs(interval)
            if itemData.length < requiredLength then
                -- Item trop court pour supporter l'overlap, skip et avancer minimalement
                currentTime = currentTime + 0.1
                goto continue_loop
            end
        end

        local position
        local maxDrift
        local drift

        -- Placement pour le premier item
        if isFirstItem then
            if interval > 0 then
                -- Placer directement entre rangeStart et rangeStart+interval
                local maxStartOffset = math.min(interval, rangeLength)
                position = rangeStart + math.random() * maxStartOffset
            else
                -- Pour intervalle négatif, placer le premier item au début du chunk
                position = rangeStart
            end
            isFirstItem = false
        else
            -- Calcul standard de position pour les items suivants (même logique que mode Absolute)
            drift = globals.Utils.applyDirectionalVariation(math.abs(interval), effectiveParams.triggerDrift, effectiveParams.triggerDriftDirection)
            position = currentTime + interval + drift

            -- Ensure position stays within chunk bounds
            position = math.max(rangeStart, math.min(position, rangeEnd))
        end

        -- Stop if position would exceed chunk end
        if position >= rangeEnd then
            break
        end

        -- Calculate item length, ensuring it doesn't exceed chunk boundary
        local maxLength = rangeEnd - position
        local actualLength = math.min(itemData.length, maxLength)

        -- Pre-calculate pitch and adjust length if using STRETCH mode
        local randomPitch = nil
        local playrate = nil
        if effectiveParams.pitchMode == globals.Constants.PITCH_MODES.STRETCH then
            if effectiveParams.randomizePitch then
                randomPitch = itemData.originalPitch + globals.Utils.randomInRange(effectiveParams.pitchRange.min, effectiveParams.pitchRange.max)
            else
                randomPitch = itemData.originalPitch
            end
            playrate = globals.Utils.semitonesToPlayrate(randomPitch)

            -- Adjust length for playrate (slower playrate = longer item)
            actualLength = actualLength / playrate
            actualLength = math.min(actualLength, maxLength)  -- Re-clamp to chunk bounds
        end

        if actualLength <= 0 then
            break
        end

        -- Create and configure the new item
        local newItem = reaper.AddMediaItemToTrack(containerGroup)
        local newTake = reaper.AddTakeToMediaItem(newItem)

        -- Configure the item
        local PCM_source = reaper.PCM_Source_CreateFromFile(itemData.filePath)
        reaper.SetMediaItemTake_Source(newTake, PCM_source)
        reaper.SetMediaItemTakeInfo_Value(newTake, "D_STARTOFFS", itemData.startOffset)

        reaper.SetMediaItemInfo_Value(newItem, "D_POSITION", position)
        reaper.GetSetMediaItemTakeInfo_String(newTake, "P_NAME", itemData.name, true)

        -- Apply randomizations using effective parameters
        if effectiveParams.randomizePitch then
            if effectiveParams.pitchMode == globals.Constants.PITCH_MODES.STRETCH then
                -- Use time stretch (D_PLAYRATE) - already calculated above
                reaper.SetMediaItemTakeInfo_Value(newTake, "D_PLAYRATE", playrate)
                reaper.SetMediaItemTakeInfo_Value(newTake, "B_PPITCH", 0)  -- Disable preserve pitch for stretch mode
            else
                -- Use standard pitch shift (D_PITCH)
                local pitchValue = itemData.originalPitch + globals.Utils.randomInRange(effectiveParams.pitchRange.min, effectiveParams.pitchRange.max)
                reaper.SetMediaItemTakeInfo_Value(newTake, "D_PITCH", pitchValue)
            end
        else
            if effectiveParams.pitchMode == globals.Constants.PITCH_MODES.STRETCH then
                -- Use time stretch (D_PLAYRATE) - already calculated above
                reaper.SetMediaItemTakeInfo_Value(newTake, "D_PLAYRATE", playrate)
                reaper.SetMediaItemTakeInfo_Value(newTake, "B_PPITCH", 0)  -- Disable preserve pitch for stretch mode
            else
                reaper.SetMediaItemTakeInfo_Value(newTake, "D_PITCH", itemData.originalPitch)
            end
        end

        -- Set D_LENGTH with adjusted value (after playrate adjustment if STRETCH mode)
        reaper.SetMediaItemInfo_Value(newItem, "D_LENGTH", actualLength)

        -- Apply gain from item settings
        local gainDB = itemData.gainDB or 0.0
        local gainScale = 10 ^ (gainDB / 20)  -- Convert dB to linear

        if effectiveParams.randomizeVolume then
            local randomVolume = itemData.originalVolume * gainScale * 10^(globals.Utils.randomInRange(effectiveParams.volumeRange.min, effectiveParams.volumeRange.max) / 20)
            reaper.SetMediaItemTakeInfo_Value(newTake, "D_VOL", randomVolume)
        else
            reaper.SetMediaItemTakeInfo_Value(newTake, "D_VOL", itemData.originalVolume * gainScale)
        end

        -- Apply pan randomization only for stereo containers (channelMode = 0 or nil)
        if effectiveParams.randomizePan and (not effectiveParams.channelMode or effectiveParams.channelMode == 0) then
            local randomPan = itemData.originalPan - globals.Utils.randomInRange(effectiveParams.panRange.min, effectiveParams.panRange.max) / 100
            randomPan = math.max(-1, math.min(1, randomPan))
            -- Use envelope instead of directly modifying the property
            globals.Items.createTakePanEnvelope(newTake, randomPan)
        end

        -- Apply fade in if enabled
        if effectiveParams.fadeInEnabled then
            local fadeInDuration = effectiveParams.fadeInDuration or 0.1
            -- Convert percentage to seconds if using percentage mode
            if effectiveParams.fadeInUsePercentage then
                fadeInDuration = (fadeInDuration / 100) * actualLength
            end
            -- Ensure fade doesn't exceed item length
            fadeInDuration = math.min(fadeInDuration, actualLength)

            reaper.SetMediaItemInfo_Value(newItem, "D_FADEINLEN", fadeInDuration)
            reaper.SetMediaItemInfo_Value(newItem, "C_FADEINSHAPE", effectiveParams.fadeInShape or 0)
            reaper.SetMediaItemInfo_Value(newItem, "D_FADEINDIR", effectiveParams.fadeInCurve or 0.0)
        end

        -- Apply fade out if enabled
        if effectiveParams.fadeOutEnabled then
            local fadeOutDuration = effectiveParams.fadeOutDuration or 0.1
            -- Convert percentage to seconds if using percentage mode
            if effectiveParams.fadeOutUsePercentage then
                fadeOutDuration = (fadeOutDuration / 100) * actualLength
            end
            -- Ensure fade doesn't exceed item length
            fadeOutDuration = math.min(fadeOutDuration, actualLength)

            reaper.SetMediaItemInfo_Value(newItem, "D_FADEOUTLEN", fadeOutDuration)
            reaper.SetMediaItemInfo_Value(newItem, "C_FADEOUTSHAPE", effectiveParams.fadeOutShape or 0)
            reaper.SetMediaItemInfo_Value(newItem, "D_FADEOUTDIR", effectiveParams.fadeOutCurve or 0.0)
        end

        lastItemRef = newItem

        -- Calculer la prochaine position (fin de l'item actuel)
        -- L'interval sera appliqué au prochain calcul de position
        currentTime = position + actualLength

        ::continue_loop::
    end

    return lastItemRef
end

-- ═══════════════════════════════════════════════════════════════════════════════
-- RANDOMIZATION AND FADE HELPERS
-- ═══════════════════════════════════════════════════════════════════════════════

--- Apply randomization (pitch, volume, pan) to an item
--- @param newItem userdata: REAPER media item
--- @param newTake userdata: REAPER media take
--- @param effectiveParams table: Container parameters
--- @param itemData table: Item data with original values
--- @param trackStructure table: Track structure information
--- @param preCalcPitch number|nil: Pre-calculated pitch value (to avoid double-random when length was already adjusted)
--- @param preCalcPlayrate number|nil: Pre-calculated playrate (to avoid double-random when length was already adjusted)
function Generation_ItemPlacement.applyRandomization(newItem, newTake, effectiveParams, itemData, trackStructure, preCalcPitch, preCalcPlayrate)
    -- Resolve base values: use neutral defaults when flatten flags are set (export preserve=false)
    -- This prevents baked-in randomization from imported items from leaking through
    local basePitch = effectiveParams.flattenPitch and 0 or itemData.originalPitch
    local baseVolume = effectiveParams.flattenVolume and 1.0 or itemData.originalVolume
    local basePan = effectiveParams.flattenPan and 0.0 or itemData.originalPan

    -- Apply pitch randomization
    if effectiveParams.randomizePitch then
        local randomPitch = preCalcPitch or (basePitch + globals.Utils.randomInRange(effectiveParams.pitchRange.min, effectiveParams.pitchRange.max))

        if effectiveParams.pitchMode == globals.Constants.PITCH_MODES.STRETCH then
            -- Use time stretch (D_PLAYRATE)
            local playrate = preCalcPlayrate or globals.Utils.semitonesToPlayrate(randomPitch)
            reaper.SetMediaItemTakeInfo_Value(newTake, "D_PLAYRATE", playrate)
            reaper.SetMediaItemTakeInfo_Value(newTake, "B_PPITCH", 0)  -- Disable preserve pitch for stretch mode
        else
            -- Use standard pitch shift (D_PITCH)
            reaper.SetMediaItemTakeInfo_Value(newTake, "D_PITCH", randomPitch)
        end
    else
        if effectiveParams.pitchMode == globals.Constants.PITCH_MODES.STRETCH then
            local playrate = preCalcPlayrate or globals.Utils.semitonesToPlayrate(basePitch)
            reaper.SetMediaItemTakeInfo_Value(newTake, "D_PLAYRATE", playrate)
            reaper.SetMediaItemTakeInfo_Value(newTake, "B_PPITCH", 0)  -- Disable preserve pitch for stretch mode
        else
            reaper.SetMediaItemTakeInfo_Value(newTake, "D_PITCH", basePitch)
        end
    end

    -- Apply gain from item settings
    local gainDB = itemData.gainDB or 0.0
    local gainScale = 10 ^ (gainDB / 20)  -- Convert dB to linear

    -- Apply volume randomization
    if effectiveParams.randomizeVolume then
        local randomVolume = baseVolume * gainScale * 10^(globals.Utils.randomInRange(effectiveParams.volumeRange.min, effectiveParams.volumeRange.max) / 20)
        reaper.SetMediaItemTakeInfo_Value(newTake, "D_VOL", randomVolume)
    else
        reaper.SetMediaItemTakeInfo_Value(newTake, "D_VOL", baseVolume * gainScale)
    end

    -- Apply pan randomization (only for stereo contexts)
    local canUsePan = false
    if not effectiveParams.channelMode or effectiveParams.channelMode == 0 then
        -- Stereo container
        canUsePan = true
    elseif trackStructure and trackStructure.trackType == "stereo" and trackStructure.trackChannels == 2 then
        -- Stereo items on stereo tracks in multichannel
        canUsePan = true
    end

    if effectiveParams.randomizePan and canUsePan then
        local randomPan = basePan - globals.Utils.randomInRange(effectiveParams.panRange.min, effectiveParams.panRange.max) / 100
        randomPan = math.max(-1, math.min(1, randomPan))
        -- Use envelope instead of directly modifying the property
        globals.Items.createTakePanEnvelope(newTake, randomPan)
    end
end

--- Apply fade in/out to an item
--- @param newItem userdata: REAPER media item
--- @param effectiveParams table: Container parameters with fade settings
--- @param actualLen number: Item length in seconds
function Generation_ItemPlacement.applyFades(newItem, effectiveParams, actualLen)
    -- Apply fade in if enabled
    if effectiveParams.fadeInEnabled then
        local fadeInDuration = effectiveParams.fadeInDuration or 0.1
        -- Convert percentage to seconds if using percentage mode
        if effectiveParams.fadeInUsePercentage then
            fadeInDuration = (fadeInDuration / 100) * actualLen
        end
        -- Ensure fade doesn't exceed item length
        fadeInDuration = math.min(fadeInDuration, actualLen)

        reaper.SetMediaItemInfo_Value(newItem, "D_FADEINLEN", fadeInDuration)
        reaper.SetMediaItemInfo_Value(newItem, "C_FADEINSHAPE", effectiveParams.fadeInShape or 0)
        reaper.SetMediaItemInfo_Value(newItem, "D_FADEINDIR", effectiveParams.fadeInCurve or 0.0)
    end

    -- Apply fade out if enabled
    if effectiveParams.fadeOutEnabled then
        local fadeOutDuration = effectiveParams.fadeOutDuration or 0.1
        -- Convert percentage to seconds if using percentage mode
        if effectiveParams.fadeOutUsePercentage then
            fadeOutDuration = (fadeOutDuration / 100) * actualLen
        end
        -- Ensure fade doesn't exceed item length
        fadeOutDuration = math.min(fadeOutDuration, actualLen)

        reaper.SetMediaItemInfo_Value(newItem, "D_FADEOUTLEN", fadeOutDuration)
        reaper.SetMediaItemInfo_Value(newItem, "C_FADEOUTSHAPE", effectiveParams.fadeOutShape or 0)
        reaper.SetMediaItemInfo_Value(newItem, "D_FADEOUTDIR", effectiveParams.fadeOutCurve or 0.0)
    end
end

--- Calculate interval based on the selected mode
--- @param effectiveParams table: Container parameters
--- @return number: Calculated interval in seconds
function Generation_ItemPlacement.calculateInterval(effectiveParams)
    local interval = effectiveParams.triggerRate -- Default (Absolute mode)

    if effectiveParams.intervalMode == 1 then
        -- Relative mode: Interval is a percentage of time selection length
        interval = (globals.timeSelectionLength * effectiveParams.triggerRate) / 100
    elseif effectiveParams.intervalMode == 2 then
        -- Coverage mode: Calculate interval based on average item length and desired coverage
        local totalItemLength = 0
        local itemCount = #effectiveParams.items

        if itemCount > 0 then
            for _, item in ipairs(effectiveParams.items) do
                totalItemLength = totalItemLength + item.length
            end

            local averageItemLength = totalItemLength / itemCount
            local desiredCoverage = effectiveParams.triggerRate / 100 -- Convert percentage to ratio
            local totalNumberOfItems = (globals.timeSelectionLength * desiredCoverage) / averageItemLength

            if totalNumberOfItems > 0 then
                interval = globals.timeSelectionLength / totalNumberOfItems
            else
                interval = globals.timeSelectionLength -- Fallback
            end
        end
    end

    return interval
end

-- ═══════════════════════════════════════════════════════════════════════════════
-- INDEPENDENT TRACK GENERATION (for "All Tracks" distribution mode)
-- ═══════════════════════════════════════════════════════════════════════════════

--- Generate items independently for a single track in "All Tracks" mode
--- Each track gets its own timeline with independent intervals, drift, and randomization
--- @param targetTrack userdata: REAPER track to generate on
--- @param trackIdx number: Track index (1-based)
--- @param container table: Container configuration
--- @param effectiveParams table: Container parameters
--- @param channelTracks table: Array of all channel tracks
--- @param trackStructure table: Track structure information
--- @param needsChannelSelection boolean: Whether channel selection is needed
--- @param channelSelectionMode string: Channel selection mode
function Generation_ItemPlacement.generateIndependentTrack(targetTrack, trackIdx, container, effectiveParams, channelTracks, trackStructure, needsChannelSelection, channelSelectionMode)
    if not container.items or #container.items == 0 then
        return
    end

    local interval = Generation_ItemPlacement.calculateInterval(effectiveParams)
    local lastItemEnd = globals.startTime
    local isFirstItem = true
    local itemCount = 0
    local maxItems = 10000  -- Safety limit to prevent infinite loops

    -- Independent generation loop for this track
    while lastItemEnd < globals.endTime and itemCount < maxItems do
        itemCount = itemCount + 1
        -- Select a random item from the container
        local randomItemIndex = math.random(1, #effectiveParams.items)
        local originalItemData = effectiveParams.items[randomItemIndex]

        -- Select area if available, or use full item
        local itemData = globals.Utils.selectRandomAreaOrFullItem(originalItemData)
        local itemChannels = itemData.numChannels or 2

        -- Vérification pour les intervalles négatifs
        if interval < 0 then
            local requiredLength = math.abs(interval)
            if itemData.length < requiredLength then
                -- Item trop court, avancer légèrement
                lastItemEnd = lastItemEnd + 0.1
                goto continue_independent_loop
            end
        end

        local position
        local maxDrift
        local drift

        -- Placement spécial pour le premier item avec intervalle > 0
        if isFirstItem and interval > 0 then
            -- Placer directement entre startTime et startTime+interval
            position = globals.startTime + math.random() * interval
            isFirstItem = false
        else
            -- Calcul standard de position pour les items suivants
            if effectiveParams.intervalMode == 0 and interval < 0 then
                -- Negative spacing creates overlap with the last item
                drift = globals.Utils.applyDirectionalVariation(math.abs(interval), effectiveParams.triggerDrift, effectiveParams.triggerDriftDirection)
                position = lastItemEnd + interval + drift
            else
                -- Regular spacing from the end of the last item
                drift = globals.Utils.applyDirectionalVariation(interval, effectiveParams.triggerDrift, effectiveParams.triggerDriftDirection)
                position = lastItemEnd + interval + drift
            end

            -- Ensure no item starts before time selection
            if position < globals.startTime then
                position = globals.startTime
            end
        end

        -- Stop if the item would start beyond the end of the time selection
        if position >= globals.endTime then
            break
        end

        -- Create and configure the new item on this track
        local newItem = reaper.AddMediaItemToTrack(targetTrack)
        local newTake = reaper.AddTakeToMediaItem(newItem)

        -- Configure the item
        local PCM_source = reaper.PCM_Source_CreateFromFile(itemData.filePath)
        reaper.SetMediaItemTake_Source(newTake, PCM_source)
        reaper.SetMediaItemTakeInfo_Value(newTake, "D_STARTOFFS", itemData.startOffset)

        -- Apply channel selection if needed
        if needsChannelSelection then
            Generation_MultiChannel.applyChannelSelection(newItem, container, itemChannels, channelSelectionMode, trackStructure, trackIdx)
        end

        -- Trim item so it never exceeds the selection end
        local maxLen = globals.endTime - position
        local actualLen = math.min(itemData.length, maxLen)

        -- Pre-calculate pitch and adjust length if using STRETCH mode
        local randomPitch = nil
        local playrate = nil
        if effectiveParams.pitchMode == globals.Constants.PITCH_MODES.STRETCH then
            local basePitch = effectiveParams.flattenPitch and 0 or itemData.originalPitch
            if effectiveParams.randomizePitch then
                randomPitch = basePitch + globals.Utils.randomInRange(effectiveParams.pitchRange.min, effectiveParams.pitchRange.max)
            else
                randomPitch = basePitch
            end
            playrate = globals.Utils.semitonesToPlayrate(randomPitch)

            -- Adjust length for playrate (slower playrate = longer item)
            actualLen = actualLen / playrate
            actualLen = math.min(actualLen, maxLen)  -- Re-clamp to timeline bounds
        end

        reaper.SetMediaItemInfo_Value(newItem, "D_POSITION", position)
        reaper.GetSetMediaItemTakeInfo_String(newTake, "P_NAME", itemData.name, true)

        -- Apply randomization (pitch, volume, pan)
        -- Pass pre-calculated pitch/playrate to avoid generating different random values
        Generation_ItemPlacement.applyRandomization(newItem, newTake, effectiveParams, itemData, trackStructure, randomPitch, playrate)

        -- Set D_LENGTH with adjusted value (after playrate adjustment if STRETCH mode)
        reaper.SetMediaItemInfo_Value(newItem, "D_LENGTH", actualLen)

        -- Apply fades if enabled
        if effectiveParams.fadeInEnabled or effectiveParams.fadeOutEnabled then
            Generation_ItemPlacement.applyFades(newItem, effectiveParams, actualLen)
        end

        -- Update end time for next item
        lastItemEnd = position + actualLen

        -- Safety: ensure minimum progression to prevent infinite loops
        if actualLen <= 0 then
            lastItemEnd = lastItemEnd + 0.01
        end

        -- Recalculate interval for next iteration
        interval = Generation_ItemPlacement.calculateInterval(effectiveParams)

        ::continue_independent_loop::
    end

    -- Debug warning if we hit the safety limit
    if itemCount >= maxItems then
        reaper.ShowConsoleMsg("WARNING: Independent track generation hit safety limit of " .. maxItems .. " items\n")
    end
end

return Generation_ItemPlacement
