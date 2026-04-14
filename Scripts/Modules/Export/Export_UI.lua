--[[
@version 1.9
@noindex
DM Ambiance Creator - Export UI Module
Handles the Export modal window rendering with multi-selection and new widgets.
v1.2: Fixed BeginChild/EndChild bug, added visual distinction for override values.
v1.3: Code review fixes - added error display, all 11 override params, constants extraction, nil checks, caching.
v1.4: Story 3.1 - Added loopDuration and loopInterval UI controls for loop mode configuration.
v1.5: Story 4.3 - Added per-container export results display with success/error/warning indicators.
      Replaced lastExportError with lastExportResults for structured result display.
v1.6: Code review fixes - Clearer success count labels (OK vs with warnings), consistent terminology
      across summary displays.
v1.7: Story 4.4 - Added "(auto: uses container intervals)" indicator when loopInterval=0 in global,
      single override, and batch override sections.
v1.8: Story 5.2 - Added Multichannel Export Mode selector (Flatten/Preserve) in global, override,
      and batch sections. Hidden for stereo-only containers (AC #10).
v1.9: Added Export Config History dropdown with auto-recall and ExtState persistence.
--]]

local Export_UI = {}
local globals = {}
local Export_Settings = nil
local Export_Engine = nil

-- UI State
local shouldOpenModal = false
local lastClickedKey = nil  -- For Shift+Click range selection
local lastExportResults = nil  -- Store structured export results for display (Story 4.3)
local ConfigHistory = nil
local selectedConfigIndex = 0  -- 0 = most recent (auto), maps to ComboBox index

-- Module-level constants (avoid duplication)
local LOOP_MODE_OPTIONS = "Auto\0On\0Off\0"
local LOOP_MODE_VALUE_TO_INDEX = { ["auto"] = 0, ["on"] = 1, ["off"] = 2 }
local LOOP_MODE_INDEX_TO_VALUE = { [0] = "auto", [1] = "on", [2] = "off" }
local OVERRIDE_LABEL_WIDTH = 100
local MAX_POOL_UI_LIMIT = 999
-- Story 5.2: Multichannel Export Mode UI constants
local MULTICHANNEL_MODE_OPTIONS = "Flatten\0Preserve\0"
local MULTICHANNEL_MODE_VALUE_TO_INDEX = { ["flatten"] = 0, ["preserve"] = 1 }
local MULTICHANNEL_MODE_INDEX_TO_VALUE = { [0] = "flatten", [1] = "preserve" }

function Export_UI.initModule(g)
    if not g then
        error("Export_UI.initModule: globals parameter is required")
    end
    globals = g
end

function Export_UI.setDependencies(settings, engine, configHistory)
    Export_Settings = settings
    Export_Engine = engine
    ConfigHistory = configHistory
end

-- Open the export modal
function Export_UI.openModal()
    -- Reset and initialize settings
    Export_Settings.resetSettings()
    Export_Settings.initializeEnabledContainers()
    lastClickedKey = nil
    lastExportResults = nil  -- Clear any previous results (Story 4.3)

    -- Auto-recall most recent config
    if ConfigHistory then
        local latestConfig = ConfigHistory.getLatestConfig()
        if latestConfig then
            Export_Settings.applyConfig(latestConfig)
            selectedConfigIndex = 0
        end
    end

    shouldOpenModal = true
end

-- Render the export modal (call every frame from UI_Preset)
function Export_UI.renderModal()
    local ctx = globals.ctx
    local imgui = globals.imgui

    if not ctx or not imgui then return end

    -- Open popup when requested
    if shouldOpenModal then
        imgui.OpenPopup(ctx, "Export Items")
        shouldOpenModal = false
    end

    -- Set modal size (increased for Preview section)
    imgui.SetNextWindowSize(ctx, 750, 620, imgui.Cond_FirstUseEver)

    local popupOpen, popupVisible = imgui.BeginPopupModal(ctx, "Export Items", true, imgui.WindowFlags_NoCollapse)

    if popupVisible then
        local windowWidth, windowHeight = imgui.GetWindowSize(ctx)
        local leftPanelWidth = 260
        local rightPanelWidth = windowWidth - leftPanelWidth - 30
        local contentHeight = windowHeight - 130  -- Leave room for export method + buttons

        -- Get global params (needed in multiple sections)
        local globalParams = Export_Settings.getGlobalParams()
        local Constants = globals.Constants
        local EXPORT = Constants and Constants.EXPORT or {}

        -- Cache containers list (called once per frame, used in multiple places)
        local containers = Export_Settings.collectAllContainers()

        -- Left Panel: Container List with Checkboxes and Multi-Selection
        if imgui.BeginChild(ctx, "ContainerList", leftPanelWidth, contentHeight, imgui.ChildFlags_Border) then
            imgui.TextColored(ctx, 0xFFAA00FF, "Containers")
            imgui.SameLine(ctx)
            imgui.TextDisabled(ctx, "(Ctrl/Shift+Click)")
            imgui.Separator(ctx)
            imgui.Spacing(ctx)

            if #containers == 0 then
                imgui.TextDisabled(ctx, "No containers found")
            else
                for _, c in ipairs(containers) do
                    local enabled = Export_Settings.isContainerEnabled(c.key)
                    local isSelected = Export_Settings.isContainerSelected(c.key)

                    -- Checkbox for enable/disable export
                    local changedEnable, newEnabled = imgui.Checkbox(ctx, "##enable_" .. c.key, enabled)
                    if changedEnable then
                        Export_Settings.setContainerEnabled(c.key, newEnabled)
                    end

                    imgui.SameLine(ctx)

                    -- Selectable for container name (multi-selection)
                    local flags = 0
                    if imgui.Selectable(ctx, c.displayName .. "##sel_" .. c.key, isSelected, flags) then
                        local ctrl = imgui.IsKeyDown(ctx, imgui.Mod_Ctrl)
                        local shift = imgui.IsKeyDown(ctx, imgui.Mod_Shift)

                        if shift and lastClickedKey then
                            -- Shift+Click: Range selection
                            Export_Settings.selectContainerRange(lastClickedKey, c.key)
                        elseif ctrl then
                            -- Ctrl+Click: Toggle selection
                            Export_Settings.toggleContainerSelected(c.key)
                        else
                            -- Normal click: Single selection
                            Export_Settings.clearContainerSelection()
                            Export_Settings.setContainerSelected(c.key, true)
                        end
                        lastClickedKey = c.key
                    end
                end
            end
            imgui.EndChild(ctx)  -- ContainerList - inside if block
        end

        imgui.SameLine(ctx)

        -- Right Panel: Parameters
        if imgui.BeginChild(ctx, "Parameters", rightPanelWidth, contentHeight, imgui.ChildFlags_Border) then
            -- Export Config History Dropdown
            if ConfigHistory and ConfigHistory.getConfigCount() > 0 then
                imgui.TextColored(ctx, 0xFFAA00FF, "Export Config")
                imgui.SameLine(ctx, 120)
                imgui.PushItemWidth(ctx, rightPanelWidth - 130)

                local configs = ConfigHistory.getConfigList()
                local comboItems = {}
                for _, cfg in ipairs(configs) do
                    table.insert(comboItems, cfg.presetName .. " | " .. cfg.timestamp)
                end
                local comboStr = table.concat(comboItems, "\0") .. "\0"

                local changedConfig, newConfigIdx = imgui.Combo(ctx, "##ExportConfigHistory",
                    selectedConfigIndex, comboStr)
                if changedConfig then
                    selectedConfigIndex = newConfigIdx
                    local config = ConfigHistory.getConfig(newConfigIdx + 1)  -- 1-based
                    if config then
                        Export_Settings.applyConfig(config)
                    end
                end

                imgui.PopItemWidth(ctx)
                imgui.Spacing(ctx)
                imgui.Separator(ctx)
                imgui.Spacing(ctx)
            end

            -- Global Parameters Section
            imgui.TextColored(ctx, 0xFFAA00FF, "Global Export Parameters")
            imgui.Separator(ctx)
            imgui.Spacing(ctx)

            -- Instance Amount (DragInt)
            imgui.Text(ctx, "Instance Amount:")
            imgui.SameLine(ctx, 150)
            imgui.PushItemWidth(ctx, 120)
            local minInstances = EXPORT.INSTANCE_MIN or 1
            local maxInstances = EXPORT.INSTANCE_MAX or 100
            local changedAmount, newAmount = imgui.DragInt(ctx, "##InstanceAmount",
                globalParams.instanceAmount, 0.1, minInstances, maxInstances)
            if changedAmount then
                Export_Settings.setGlobalParam("instanceAmount", newAmount)
            end
            imgui.PopItemWidth(ctx)

            -- Spacing (DragDouble)
            imgui.Text(ctx, "Spacing (seconds):")
            imgui.SameLine(ctx, 150)
            imgui.PushItemWidth(ctx, 120)
            local minSpacing = EXPORT.SPACING_MIN or 0
            local maxSpacing = EXPORT.SPACING_MAX or 60
            local changedSpacing, newSpacing = imgui.DragDouble(ctx, "##Spacing",
                globalParams.spacing, 0.01, minSpacing, maxSpacing, "%.2f")
            if changedSpacing then
                Export_Settings.setGlobalParam("spacing", newSpacing)
            end
            imgui.PopItemWidth(ctx)

            -- Max Pool Items (DragInt)
            imgui.Text(ctx, "Max Pool Items:")
            imgui.SameLine(ctx, 150)
            imgui.PushItemWidth(ctx, 120)
            local changedMaxPool, newMaxPool = imgui.DragInt(ctx, "##MaxPoolItems",
                globalParams.maxPoolItems, 0.1, 0, MAX_POOL_UI_LIMIT)
            if changedMaxPool then
                Export_Settings.setGlobalParam("maxPoolItems", newMaxPool)
            end
            imgui.PopItemWidth(ctx)

            -- Display pool info: "All (X)" when 0, or "X / Y available" when > 0
            imgui.SameLine(ctx)
            local totalPool = 0
            local selectedKeys = Export_Settings.getSelectedContainerKeys()
            if #selectedKeys == 1 then
                totalPool = Export_Settings.getPoolSize(selectedKeys[1])
            elseif #selectedKeys == 0 then
                -- Show total from all enabled containers (use cached containers)
                for _, c in ipairs(containers) do
                    if Export_Settings.isContainerEnabled(c.key) then
                        totalPool = totalPool + Export_Settings.getPoolSize(c.key)
                    end
                end
            end
            if totalPool > 0 then
                local poolText
                if globalParams.maxPoolItems == 0 or globalParams.maxPoolItems >= totalPool then
                    poolText = string.format("All (%d)", totalPool)
                else
                    poolText = string.format("%d / %d available", globalParams.maxPoolItems, totalPool)
                end
                imgui.TextDisabled(ctx, poolText)
            end

            -- Loop Mode (Combo)
            imgui.Text(ctx, "Loop Mode:")
            imgui.SameLine(ctx, 150)
            imgui.PushItemWidth(ctx, 120)
            local currentLoopIndex = LOOP_MODE_VALUE_TO_INDEX[globalParams.loopMode] or 0
            local changedLoopMode, newLoopIndex = imgui.Combo(ctx, "##LoopMode",
                currentLoopIndex, LOOP_MODE_OPTIONS)
            if changedLoopMode then
                local newLoopValue = LOOP_MODE_INDEX_TO_VALUE[newLoopIndex] or "auto"
                Export_Settings.setGlobalParam("loopMode", newLoopValue)
            end
            imgui.PopItemWidth(ctx)

            -- Loop Duration & Interval (only visible when loopMode != "off")
            if globalParams.loopMode ~= "off" then
                imgui.Text(ctx, "Loop Duration (s):")
                imgui.SameLine(ctx, 150)
                imgui.PushItemWidth(ctx, 120)
                local loopDurMin = EXPORT.LOOP_DURATION_MIN or 5
                local loopDurMax = EXPORT.LOOP_DURATION_MAX or 300
                local changedLoopDur, newLoopDur = imgui.DragInt(ctx, "##LoopDuration",
                    globalParams.loopDuration or 30, 1, loopDurMin, loopDurMax)
                if changedLoopDur then
                    Export_Settings.setGlobalParam("loopDuration", newLoopDur)
                end
                imgui.PopItemWidth(ctx)

                imgui.Text(ctx, "Loop Interval (s):")
                imgui.SameLine(ctx, 150)
                imgui.PushItemWidth(ctx, 120)
                local loopIntMin = EXPORT.LOOP_INTERVAL_MIN or -10
                local loopIntMax = EXPORT.LOOP_INTERVAL_MAX or 10
                local changedLoopInt, newLoopInt = imgui.DragDouble(ctx, "##LoopInterval",
                    globalParams.loopInterval or 0, 0.1, loopIntMin, loopIntMax, "%.1f")
                if changedLoopInt then
                    Export_Settings.setGlobalParam("loopInterval", newLoopInt)
                end
                imgui.PopItemWidth(ctx)
                -- Auto-mode indicator: show when loopInterval is 0
                if (globalParams.loopInterval or 0) == 0 then
                    imgui.SameLine(ctx)
                    imgui.TextDisabled(ctx, "(auto: uses container intervals)")
                    if imgui.IsItemHovered(ctx) then
                        imgui.SetTooltip(ctx, "When set to 0, each container uses its own triggerRate\nfor overlap timing instead of a global value.")
                    end
                end
            end

            -- Story 5.2: Multichannel Export Mode (AC #9, #10)
            -- Only show when at least one enabled container has channelMode != DEFAULT (0)
            local hasMultichannelContainer = false
            for _, c in ipairs(containers) do
                if Export_Settings.isContainerEnabled(c.key) then
                    local channelMode = c.container.channelMode or 0
                    if channelMode ~= 0 then
                        hasMultichannelContainer = true
                        break
                    end
                end
            end

            if hasMultichannelContainer then
                imgui.Text(ctx, "Multichannel Mode:")
                imgui.SameLine(ctx, 150)
                imgui.PushItemWidth(ctx, 120)
                local currentMchIdx = MULTICHANNEL_MODE_VALUE_TO_INDEX[globalParams.multichannelExportMode or "flatten"] or 0
                local changedMch, newMchIdx = imgui.Combo(ctx, "##MultichannelMode",
                    currentMchIdx, MULTICHANNEL_MODE_OPTIONS)
                if changedMch then
                    local newMchValue = MULTICHANNEL_MODE_INDEX_TO_VALUE[newMchIdx] or "flatten"
                    Export_Settings.setGlobalParam("multichannelExportMode", newMchValue)
                end
                imgui.PopItemWidth(ctx)
            end

            imgui.Spacing(ctx)

            -- Align to whole seconds
            local changedAlign, newAlign = imgui.Checkbox(ctx, "Align to whole seconds",
                globalParams.alignToSeconds)
            if changedAlign then
                Export_Settings.setGlobalParam("alignToSeconds", newAlign)
            end

            imgui.Spacing(ctx)
            imgui.Separator(ctx)
            imgui.Spacing(ctx)

            -- Preserve checkboxes
            imgui.Text(ctx, "Preserve Properties:")
            imgui.Spacing(ctx)

            local changed1, newPan = imgui.Checkbox(ctx, "Preserve Pan", globalParams.preservePan)
            if changed1 then Export_Settings.setGlobalParam("preservePan", newPan) end

            local changed2, newVol = imgui.Checkbox(ctx, "Preserve Volume", globalParams.preserveVolume)
            if changed2 then Export_Settings.setGlobalParam("preserveVolume", newVol) end

            local changed3, newPitch = imgui.Checkbox(ctx, "Preserve Pitch/Stretch", globalParams.preservePitch)
            if changed3 then Export_Settings.setGlobalParam("preservePitch", newPitch) end

            imgui.Spacing(ctx)
            imgui.Separator(ctx)
            imgui.Spacing(ctx)

            -- Region Creation Section
            imgui.Text(ctx, "Region Creation:")
            imgui.Spacing(ctx)

            local changedCreateRegions, newCreateRegions = imgui.Checkbox(ctx,
                "Create regions for exported items", globalParams.createRegions)
            if changedCreateRegions then
                Export_Settings.setGlobalParam("createRegions", newCreateRegions)
            end

            if globalParams.createRegions then
                imgui.Indent(ctx, 15)
                imgui.Text(ctx, "Pattern:")
                imgui.SameLine(ctx, 80)
                imgui.PushItemWidth(ctx, 200)
                local changedPattern, newPattern = imgui.InputText(ctx, "##RegionPattern",
                    globalParams.regionPattern, imgui.InputTextFlags_None)
                if changedPattern then
                    Export_Settings.setGlobalParam("regionPattern", newPattern)
                end
                imgui.PopItemWidth(ctx)
                imgui.TextDisabled(ctx, "Tags: $container, $group, $index")
                imgui.Unindent(ctx, 15)
            end

            imgui.Spacing(ctx)

            -- Container Override Section
            imgui.Separator(ctx)
            imgui.Spacing(ctx)
            imgui.TextColored(ctx, 0x00AAFFFF, "Container Override")
            imgui.Spacing(ctx)

            local selectedCount = Export_Settings.getSelectedContainerCount()

            if selectedCount == 0 then
                imgui.TextDisabled(ctx, "Select container(s) to set overrides")
            elseif selectedCount == 1 then
                -- Single selection: show container name
                local selectedKeys = Export_Settings.getSelectedContainerKeys()
                local selectedKey = selectedKeys[1]

                -- Find container display name (use cached containers)
                local selectedName = ""
                for _, c in ipairs(containers) do
                    if c.key == selectedKey then
                        selectedName = c.displayName
                        break
                    end
                end

                imgui.Text(ctx, "Selected: " .. selectedName)
                imgui.Spacing(ctx)

                -- Get or create override
                local override = Export_Settings.getContainerOverride(selectedKey)
                -- Find selected containerInfo for multichannel check
                local selectedContainerInfo = nil
                for _, c in ipairs(containers) do
                    if c.key == selectedKey then
                        selectedContainerInfo = c
                        break
                    end
                end

                if not override then
                    override = {
                        enabled = false,
                        params = {
                            instanceAmount = globalParams.instanceAmount,
                            spacing = globalParams.spacing,
                            alignToSeconds = globalParams.alignToSeconds,
                            exportMethod = globalParams.exportMethod,
                            preservePan = globalParams.preservePan,
                            preserveVolume = globalParams.preserveVolume,
                            preservePitch = globalParams.preservePitch,
                            createRegions = globalParams.createRegions,
                            regionPattern = globalParams.regionPattern,
                            maxPoolItems = globalParams.maxPoolItems,
                            loopMode = globalParams.loopMode,
                            loopDuration = globalParams.loopDuration,
                            loopInterval = globalParams.loopInterval,
                            multichannelExportMode = globalParams.multichannelExportMode,
                        }
                    }
                end

                local changedOverride, enableOverride = imgui.Checkbox(ctx, "Enable Override##container", override.enabled)
                if changedOverride then
                    override.enabled = enableOverride
                    Export_Settings.setContainerOverride(selectedKey, override)
                end

                if override.enabled then
                    -- Code Review M2: Reduce parameter count from 6 to 4 using context table
                    local renderContext = {
                        EXPORT = EXPORT,
                        containerInfo = selectedContainerInfo,
                        globalParams = globalParams
                    }
                    Export_UI.renderOverrideParams(ctx, imgui, selectedKey, override, renderContext)
                else
                    imgui.TextDisabled(ctx, "Using global parameters")
                end
            else
                -- Multi-selection
                imgui.TextColored(ctx, 0xFFAA00FF, string.format("%d containers selected", selectedCount))
                imgui.Text(ctx, "Changes apply to all selected")
                imgui.Spacing(ctx)

                -- Check if all selected have overrides enabled
                local allOverridesEnabled = true
                local selectedKeys = Export_Settings.getSelectedContainerKeys()
                for _, key in ipairs(selectedKeys) do
                    local override = Export_Settings.getContainerOverride(key)
                    if not override or not override.enabled then
                        allOverridesEnabled = false
                        break
                    end
                end

                -- Enable override checkbox for all selected
                local changedBatchOverride, enableBatchOverride = imgui.Checkbox(ctx,
                    "Enable Override for all##batch", allOverridesEnabled)
                if changedBatchOverride then
                    for _, key in ipairs(selectedKeys) do
                        local override = Export_Settings.getContainerOverride(key)
                        if not override then
                            override = {
                                enabled = enableBatchOverride,
                                params = {
                                    instanceAmount = globalParams.instanceAmount,
                                    spacing = globalParams.spacing,
                                    alignToSeconds = globalParams.alignToSeconds,
                                    exportMethod = globalParams.exportMethod,
                                    preservePan = globalParams.preservePan,
                                    preserveVolume = globalParams.preserveVolume,
                                    preservePitch = globalParams.preservePitch,
                                    createRegions = globalParams.createRegions,
                                    regionPattern = globalParams.regionPattern,
                                    maxPoolItems = globalParams.maxPoolItems,
                                    loopMode = globalParams.loopMode,
                                    loopDuration = globalParams.loopDuration,
                                    loopInterval = globalParams.loopInterval,
                                    multichannelExportMode = globalParams.multichannelExportMode,
                                }
                            }
                        else
                            override.enabled = enableBatchOverride
                        end
                        Export_Settings.setContainerOverride(key, override)
                    end
                end

                if allOverridesEnabled then
                    imgui.Spacing(ctx)
                    imgui.TextDisabled(ctx, "Editing applies to all selected:")
                    imgui.Spacing(ctx)

                    -- Get first selected container's override as reference
                    local refOverride = Export_Settings.getContainerOverride(selectedKeys[1])
                    if refOverride then
                        -- Code Review M2: Reduce parameter count from 6 to 4 using context table
                        local renderContext = {
                            EXPORT = EXPORT,
                            containers = containers,
                            globalParams = globalParams
                        }
                        Export_UI.renderBatchOverrideParams(ctx, imgui, selectedKeys, refOverride, renderContext)
                    end
                end
            end

            -- Preview Section
            imgui.Spacing(ctx)
            imgui.Separator(ctx)
            imgui.Spacing(ctx)
            imgui.TextColored(ctx, 0x00AAFFFF, "Preview")
            imgui.Spacing(ctx)

            if imgui.BeginChild(ctx, "PreviewList", -1, 120, imgui.ChildFlags_Border) then
                -- Defensive nil-check for Export_Engine
                local previewEntries = Export_Engine and Export_Engine.generatePreview
                    and Export_Engine.generatePreview() or {}

                if #previewEntries == 0 then
                    imgui.TextDisabled(ctx, "No enabled containers")
                else
                    for _, entry in ipairs(previewEntries) do
                        -- Defensive nil checks for entry fields
                        if not entry or not entry.name then
                            imgui.TextDisabled(ctx, "(invalid entry)")
                        else
                            -- Format pool display: "6/12" or "8/8"
                            local poolSelected = entry.poolSelected or 0
                            local poolTotal = entry.poolTotal or 0
                            local poolDisplay = string.format("%d/%d", poolSelected, poolTotal)

                            -- Format loop indicator: checkmark or X, with "(auto)" suffix and duration
                            local loopIndicator
                            if entry.loopMode then
                                loopIndicator = "Loop \226\156\147"  -- ✓
                                if entry.loopModeAuto then
                                    loopIndicator = loopIndicator .. " (auto)"
                                end
                                -- Add loop duration if available
                                if entry.loopDuration then
                                    loopIndicator = loopIndicator .. " " .. entry.loopDuration .. "s"
                                end
                            else
                                loopIndicator = "Loop \226\156\151"  -- ✗
                            end

                            -- Format track info: "1trk" for mono, "2trk" for stereo
                            local trackCount = entry.trackCount or 1
                            local trackInfo = string.format("%dtrk", trackCount)

                            -- Format duration: "~12s" rounded to nearest second
                            local estimatedDuration = entry.estimatedDuration or 0
                            local durationDisplay = string.format("~%ds", math.floor(estimatedDuration + 0.5))

                            -- Render row with proper spacing
                            -- Name (truncated if needed)
                            local displayName = entry.name
                            if #displayName > 20 then
                                displayName = displayName:sub(1, 17) .. "..."
                            end
                            imgui.Text(ctx, displayName)
                            imgui.SameLine(ctx, 160)
                            imgui.TextDisabled(ctx, poolDisplay)
                            imgui.SameLine(ctx, 200)
                            if entry.loopMode then
                                imgui.TextColored(ctx, 0x88FF88FF, loopIndicator)
                            else
                                imgui.TextDisabled(ctx, loopIndicator)
                            end
                            imgui.SameLine(ctx, 300)
                            imgui.TextDisabled(ctx, trackInfo)
                            imgui.SameLine(ctx, 340)
                            imgui.TextDisabled(ctx, durationDisplay)
                        end
                    end
                end
                imgui.EndChild(ctx)  -- PreviewList - inside if block
            end

            -- Story 4.3: Export Results Section (shows after export with errors/warnings)
            if lastExportResults and #lastExportResults.results > 0 then
                local hasIssues = lastExportResults.totalErrors > 0 or lastExportResults.totalWarnings > 0
                if hasIssues then
                    imgui.Spacing(ctx)
                    imgui.Separator(ctx)
                    imgui.Spacing(ctx)

                    -- Header with color based on severity
                    if lastExportResults.totalErrors > 0 then
                        imgui.TextColored(ctx, 0xFF4444FF, "Export Results (with errors)")
                    else
                        imgui.TextColored(ctx, 0xFFAA00FF, "Export Results (with warnings)")
                    end
                    imgui.Spacing(ctx)

                    -- Scrollable results list
                    if imgui.BeginChild(ctx, "ExportResults", -1, 100, imgui.ChildFlags_Border) then
                        for _, result in ipairs(lastExportResults.results) do
                            local containerName = result.containerName or "Unknown"
                            if #containerName > 25 then
                                containerName = containerName:sub(1, 22) .. "..."
                            end

                            -- Status indicator and container name
                            if result.status == "success" then
                                -- Green checkmark for success
                                imgui.TextColored(ctx, 0x88FF88FF, "\226\156\147")  -- ✓
                                imgui.SameLine(ctx)
                                imgui.Text(ctx, containerName)
                                imgui.SameLine(ctx, 200)
                                imgui.TextDisabled(ctx, string.format("(%d items)", result.itemsExported))
                            elseif result.status == "warning" then
                                -- Yellow warning for warnings
                                imgui.TextColored(ctx, 0xFFAA00FF, "!")
                                imgui.SameLine(ctx)
                                imgui.Text(ctx, containerName)
                                imgui.SameLine(ctx, 200)
                                imgui.TextDisabled(ctx, string.format("(%d items)", result.itemsExported))
                                -- Show warning details
                                for _, warn in ipairs(result.warnings or {}) do
                                    imgui.Indent(ctx, 20)
                                    imgui.TextColored(ctx, 0xFFAA00FF, "\226\148\148 " .. warn)
                                    imgui.Unindent(ctx, 20)
                                end
                            elseif result.status == "error" then
                                -- Red X for errors
                                imgui.TextColored(ctx, 0xFF4444FF, "\226\156\151")  -- ✗
                                imgui.SameLine(ctx)
                                imgui.TextColored(ctx, 0xFF6666FF, containerName)
                                -- Show error details
                                for _, err in ipairs(result.errors or {}) do
                                    imgui.Indent(ctx, 20)
                                    imgui.TextColored(ctx, 0xFF4444FF, "\226\148\148 " .. err)
                                    imgui.Unindent(ctx, 20)
                                end
                            end
                        end
                        imgui.EndChild(ctx)  -- ExportResults
                    end

                    -- Summary line (pure success = totalSuccess - totalWarnings since warnings count as success)
                    local pureSuccess = lastExportResults.totalSuccess - lastExportResults.totalWarnings
                    imgui.TextDisabled(ctx, string.format(
                        "Summary: %d items (%d OK, %d with warnings, %d failed)",
                        lastExportResults.totalItemsExported,
                        pureSuccess,
                        lastExportResults.totalWarnings,
                        lastExportResults.totalErrors
                    ))
                end
            end
            imgui.EndChild(ctx)  -- Parameters - inside if block
        end

        -- Export Method Section (between panels and buttons)
        imgui.Separator(ctx)
        imgui.Spacing(ctx)

        imgui.Text(ctx, "Export Method:")
        imgui.SameLine(ctx)
        imgui.PushItemWidth(ctx, 200)
        local methods = "Current Track\0New Track\0"
        local changedMethod, newMethod = imgui.Combo(ctx, "##ExportMethod",
            globalParams.exportMethod, methods)
        if changedMethod then
            Export_Settings.setGlobalParam("exportMethod", newMethod)
        end
        imgui.PopItemWidth(ctx)

        imgui.SameLine(ctx)

        -- Show enabled count (use cached containers)
        local enabledCount = Export_Settings.getEnabledContainerCount()
        local totalCount = #containers
        imgui.Text(ctx, string.format("| Enabled: %d/%d", enabledCount, totalCount))

        imgui.Spacing(ctx)
        imgui.Separator(ctx)
        imgui.Spacing(ctx)

        -- Footer buttons
        local buttonWidth = 120
        local buttonSpacing = 10
        local totalButtonWidth = buttonWidth * 2 + buttonSpacing
        local startX = (windowWidth - totalButtonWidth) / 2

        imgui.SetCursorPosX(ctx, startX)

        -- Export button
        imgui.PushStyleColor(ctx, imgui.Col_Button, 0x0088AAFF)
        imgui.PushStyleColor(ctx, imgui.Col_ButtonHovered, 0x00AACCFF)
        imgui.PushStyleColor(ctx, imgui.Col_ButtonActive, 0x006688FF)
        if imgui.Button(ctx, "Export", buttonWidth, 30) then
            local success, message, exportResults = Export_Engine.performExport()
            lastExportResults = exportResults
            -- Reset config dropdown to latest (new config was just saved at index 0)
            if success then
                selectedConfigIndex = 0
            end
            -- Only close on full success (no errors or warnings)
            if success and exportResults and exportResults.totalErrors == 0 and exportResults.totalWarnings == 0 then
                imgui.CloseCurrentPopup(ctx)
            end
            -- Results will be displayed below if there were any issues
        end
        imgui.PopStyleColor(ctx, 3)

        -- Show compact export results summary (Story 4.3)
        -- Note: Detailed results section (above) shows full breakdown when issues exist
        if lastExportResults and (lastExportResults.totalErrors > 0 or lastExportResults.totalWarnings > 0) then
            imgui.SameLine(ctx)
            local pureSuccess = lastExportResults.totalSuccess - lastExportResults.totalWarnings
            if lastExportResults.totalErrors > 0 then
                imgui.TextColored(ctx, 0xFF4444FF, string.format(
                    "%d items (%d OK, %d warn, %d failed)",
                    lastExportResults.totalItemsExported,
                    pureSuccess,
                    lastExportResults.totalWarnings,
                    lastExportResults.totalErrors
                ))
            else
                imgui.TextColored(ctx, 0xFFAA00FF, string.format(
                    "%d items (%d OK, %d with warnings)",
                    lastExportResults.totalItemsExported,
                    pureSuccess,
                    lastExportResults.totalWarnings
                ))
            end
        end

        imgui.SameLine(ctx)

        -- Cancel button
        if imgui.Button(ctx, "Cancel", buttonWidth, 30) then
            imgui.CloseCurrentPopup(ctx)
        end

        imgui.EndPopup(ctx)
    end
end

-- Render override parameters for single selection
-- Visual distinction: orange text with * suffix for values that differ from global
-- Code Review M2: Reduced from 6 to 5 parameters using context table
-- @param renderContext table: { EXPORT, containerInfo, globalParams }
function Export_UI.renderOverrideParams(ctx, imgui, containerKey, override, renderContext)
    imgui.Indent(ctx, 15)
    imgui.Spacing(ctx)

    local EXPORT = renderContext.EXPORT
    local containerInfo = renderContext.containerInfo
    local globalParams = renderContext.globalParams
    local MODIFIED_COLOR = 0xFFAA00FF  -- Orange

    -- Story 5.2: Multichannel Export Mode override (only for multichannel containers)
    local isMultichannel = containerInfo and containerInfo.container
        and (containerInfo.container.channelMode or 0) ~= 0
    if isMultichannel then
        local mchDiff = (override.params.multichannelExportMode or "flatten") ~= (globalParams.multichannelExportMode or "flatten")
        if mchDiff then
            imgui.TextColored(ctx, MODIFIED_COLOR, "MCh Mode: *")
        else
            imgui.Text(ctx, "MCh Mode:")
        end
        imgui.SameLine(ctx, OVERRIDE_LABEL_WIDTH)
        imgui.PushItemWidth(ctx, 100)
        local currentMchIdx = MULTICHANNEL_MODE_VALUE_TO_INDEX[override.params.multichannelExportMode or "flatten"] or 0
        local changedMchOvr, newMchOvrIdx = imgui.Combo(ctx, "##OverrideMultichannelMode",
            currentMchIdx, MULTICHANNEL_MODE_OPTIONS)
        if changedMchOvr then
            override.params.multichannelExportMode = MULTICHANNEL_MODE_INDEX_TO_VALUE[newMchOvrIdx] or "flatten"
            Export_Settings.setContainerOverride(containerKey, override)
        end
        imgui.PopItemWidth(ctx)
    end

    -- Override Instance Amount
    local instDiff = override.params.instanceAmount ~= globalParams.instanceAmount
    if instDiff then
        imgui.TextColored(ctx, MODIFIED_COLOR, "Instances: *")
    else
        imgui.Text(ctx, "Instances:")
    end
    imgui.SameLine(ctx, OVERRIDE_LABEL_WIDTH)
    imgui.PushItemWidth(ctx, 100)
    local changedAmt, newAmt = imgui.DragInt(ctx, "##OverrideAmount",
        override.params.instanceAmount, 0.1,
        EXPORT.INSTANCE_MIN or 1, EXPORT.INSTANCE_MAX or 100)
    if changedAmt then
        override.params.instanceAmount = newAmt
        Export_Settings.setContainerOverride(containerKey, override)
    end
    imgui.PopItemWidth(ctx)

    -- Override Spacing
    local spcDiff = override.params.spacing ~= globalParams.spacing
    if spcDiff then
        imgui.TextColored(ctx, MODIFIED_COLOR, "Spacing: *")
    else
        imgui.Text(ctx, "Spacing:")
    end
    imgui.SameLine(ctx, OVERRIDE_LABEL_WIDTH)
    imgui.PushItemWidth(ctx, 100)
    local changedSpc, newSpc = imgui.DragDouble(ctx, "##OverrideSpacing",
        override.params.spacing, 0.01,
        EXPORT.SPACING_MIN or 0, EXPORT.SPACING_MAX or 60, "%.2f")
    if changedSpc then
        override.params.spacing = newSpc
        Export_Settings.setContainerOverride(containerKey, override)
    end
    imgui.PopItemWidth(ctx)

    -- Override Max Pool Items
    local poolDiff = (override.params.maxPoolItems or 0) ~= (globalParams.maxPoolItems or 0)
    if poolDiff then
        imgui.TextColored(ctx, MODIFIED_COLOR, "Max Pool: *")
    else
        imgui.Text(ctx, "Max Pool:")
    end
    imgui.SameLine(ctx, OVERRIDE_LABEL_WIDTH)
    imgui.PushItemWidth(ctx, 100)
    local changedMaxPoolOvr, newMaxPoolOvr = imgui.DragInt(ctx, "##OverrideMaxPool",
        override.params.maxPoolItems or 0, 0.1, 0, MAX_POOL_UI_LIMIT)
    if changedMaxPoolOvr then
        override.params.maxPoolItems = newMaxPoolOvr
        Export_Settings.setContainerOverride(containerKey, override)
    end
    imgui.PopItemWidth(ctx)

    -- Override Loop Mode
    local loopDiff = (override.params.loopMode or "auto") ~= (globalParams.loopMode or "auto")
    if loopDiff then
        imgui.TextColored(ctx, MODIFIED_COLOR, "Loop Mode: *")
    else
        imgui.Text(ctx, "Loop Mode:")
    end
    imgui.SameLine(ctx, OVERRIDE_LABEL_WIDTH)
    imgui.PushItemWidth(ctx, 100)
    local currentLoopIdx = LOOP_MODE_VALUE_TO_INDEX[override.params.loopMode or "auto"] or 0
    local changedLoopOvr, newLoopIdx = imgui.Combo(ctx, "##OverrideLoopMode",
        currentLoopIdx, LOOP_MODE_OPTIONS)
    if changedLoopOvr then
        override.params.loopMode = LOOP_MODE_INDEX_TO_VALUE[newLoopIdx] or "auto"
        Export_Settings.setContainerOverride(containerKey, override)
    end
    imgui.PopItemWidth(ctx)

    -- Override Loop Duration (only visible when loopMode != "off")
    if (override.params.loopMode or "auto") ~= "off" then
        local loopDurDiff = (override.params.loopDuration or 30) ~= (globalParams.loopDuration or 30)
        if loopDurDiff then
            imgui.TextColored(ctx, MODIFIED_COLOR, "Loop Dur: *")
        else
            imgui.Text(ctx, "Loop Dur:")
        end
        imgui.SameLine(ctx, OVERRIDE_LABEL_WIDTH)
        imgui.PushItemWidth(ctx, 100)
        local loopDurMin = EXPORT.LOOP_DURATION_MIN or 5
        local loopDurMax = EXPORT.LOOP_DURATION_MAX or 300
        local changedLoopDurOvr, newLoopDurOvr = imgui.DragInt(ctx, "##OverrideLoopDuration",
            override.params.loopDuration or 30, 1, loopDurMin, loopDurMax)
        if changedLoopDurOvr then
            override.params.loopDuration = newLoopDurOvr
            Export_Settings.setContainerOverride(containerKey, override)
        end
        imgui.PopItemWidth(ctx)

        -- Override Loop Interval
        local loopIntDiff = (override.params.loopInterval or 0) ~= (globalParams.loopInterval or 0)
        if loopIntDiff then
            imgui.TextColored(ctx, MODIFIED_COLOR, "Loop Int: *")
        else
            imgui.Text(ctx, "Loop Int:")
        end
        imgui.SameLine(ctx, OVERRIDE_LABEL_WIDTH)
        imgui.PushItemWidth(ctx, 100)
        local loopIntMin = EXPORT.LOOP_INTERVAL_MIN or -10
        local loopIntMax = EXPORT.LOOP_INTERVAL_MAX or 10
        local changedLoopIntOvr, newLoopIntOvr = imgui.DragDouble(ctx, "##OverrideLoopInterval",
            override.params.loopInterval or 0, 0.1, loopIntMin, loopIntMax, "%.1f")
        if changedLoopIntOvr then
            override.params.loopInterval = newLoopIntOvr
            Export_Settings.setContainerOverride(containerKey, override)
        end
        imgui.PopItemWidth(ctx)
        -- Auto-mode indicator: show when loopInterval is 0
        if (override.params.loopInterval or 0) == 0 then
            imgui.SameLine(ctx)
            imgui.TextDisabled(ctx, "(auto: uses container intervals)")
            if imgui.IsItemHovered(ctx) then
                imgui.SetTooltip(ctx, "When set to 0, each container uses its own triggerRate\nfor overlap timing instead of a global value.")
            end
        end
    end

    -- Override Align to seconds
    local alignDiff = override.params.alignToSeconds ~= globalParams.alignToSeconds
    local changedAlignOvr, newAlignOvr = imgui.Checkbox(ctx,
        alignDiff and "Align to seconds *##override" or "Align to seconds##override",
        override.params.alignToSeconds)
    if changedAlignOvr then
        override.params.alignToSeconds = newAlignOvr
        Export_Settings.setContainerOverride(containerKey, override)
    end

    imgui.Spacing(ctx)

    -- Override Preserve checkboxes
    local panDiff = override.params.preservePan ~= globalParams.preservePan
    local c1, p1 = imgui.Checkbox(ctx,
        panDiff and "Preserve Pan *##override" or "Preserve Pan##override",
        override.params.preservePan)
    if c1 then
        override.params.preservePan = p1
        Export_Settings.setContainerOverride(containerKey, override)
    end

    local volDiff = override.params.preserveVolume ~= globalParams.preserveVolume
    local c2, p2 = imgui.Checkbox(ctx,
        volDiff and "Preserve Volume *##override" or "Preserve Volume##override",
        override.params.preserveVolume)
    if c2 then
        override.params.preserveVolume = p2
        Export_Settings.setContainerOverride(containerKey, override)
    end

    local pitchDiff = override.params.preservePitch ~= globalParams.preservePitch
    local c3, p3 = imgui.Checkbox(ctx,
        pitchDiff and "Preserve Pitch *##override" or "Preserve Pitch##override",
        override.params.preservePitch)
    if c3 then
        override.params.preservePitch = p3
        Export_Settings.setContainerOverride(containerKey, override)
    end

    imgui.Spacing(ctx)
    imgui.Separator(ctx)
    imgui.Spacing(ctx)

    -- Override Export Method
    local methodDiff = (override.params.exportMethod or 0) ~= (globalParams.exportMethod or 0)
    if methodDiff then
        imgui.TextColored(ctx, MODIFIED_COLOR, "Export To: *")
    else
        imgui.Text(ctx, "Export To:")
    end
    imgui.SameLine(ctx, OVERRIDE_LABEL_WIDTH)
    imgui.PushItemWidth(ctx, 120)
    local methods = "Current Track\0New Track\0"
    local changedMethodOvr, newMethodOvr = imgui.Combo(ctx, "##OverrideMethod",
        override.params.exportMethod or 0, methods)
    if changedMethodOvr then
        override.params.exportMethod = newMethodOvr
        Export_Settings.setContainerOverride(containerKey, override)
    end
    imgui.PopItemWidth(ctx)

    -- Override Create Regions
    local regionsDiff = override.params.createRegions ~= globalParams.createRegions
    local changedRegionsOvr, newRegionsOvr = imgui.Checkbox(ctx,
        regionsDiff and "Create Regions *##override" or "Create Regions##override",
        override.params.createRegions or false)
    if changedRegionsOvr then
        override.params.createRegions = newRegionsOvr
        Export_Settings.setContainerOverride(containerKey, override)
    end

    -- Override Region Pattern (only show if createRegions is enabled)
    if override.params.createRegions then
        local patternDiff = (override.params.regionPattern or "") ~= (globalParams.regionPattern or "")
        if patternDiff then
            imgui.TextColored(ctx, MODIFIED_COLOR, "Pattern: *")
        else
            imgui.Text(ctx, "Pattern:")
        end
        imgui.SameLine(ctx, OVERRIDE_LABEL_WIDTH)
        imgui.PushItemWidth(ctx, 150)
        local changedPatternOvr, newPatternOvr = imgui.InputText(ctx, "##OverridePattern",
            override.params.regionPattern or "$container", imgui.InputTextFlags_None)
        if changedPatternOvr then
            override.params.regionPattern = newPatternOvr
            Export_Settings.setContainerOverride(containerKey, override)
        end
        imgui.PopItemWidth(ctx)
    end

    imgui.Unindent(ctx, 15)
end

-- Render override parameters for multi-selection (batch editing)
-- Visual distinction: orange text with * suffix for values that differ from global
-- Code Review M2: Reduced from 6 to 5 parameters using context table
-- @param renderContext table: { EXPORT, containers, globalParams }
function Export_UI.renderBatchOverrideParams(ctx, imgui, selectedKeys, refOverride, renderContext)
    imgui.Indent(ctx, 15)

    local EXPORT = renderContext.EXPORT
    local containers = renderContext.containers
    local globalParams = renderContext.globalParams
    local MODIFIED_COLOR = 0xFFAA00FF  -- Orange

    -- Story 5.2: Check if any selected container is multichannel
    local hasMultichannelSelected = false
    if containers then
        for _, key in ipairs(selectedKeys) do
            for _, c in ipairs(containers) do
                if c.key == key and (c.container.channelMode or 0) ~= 0 then
                    hasMultichannelSelected = true
                    break
                end
            end
            if hasMultichannelSelected then break end
        end
    end

    if hasMultichannelSelected then
        local mchDiff = (refOverride.params.multichannelExportMode or "flatten") ~= (globalParams.multichannelExportMode or "flatten")
        if mchDiff then
            imgui.TextColored(ctx, MODIFIED_COLOR, "MCh Mode: *")
        else
            imgui.Text(ctx, "MCh Mode:")
        end
        imgui.SameLine(ctx, OVERRIDE_LABEL_WIDTH)
        imgui.PushItemWidth(ctx, 100)
        local currentMchIdxBatch = MULTICHANNEL_MODE_VALUE_TO_INDEX[refOverride.params.multichannelExportMode or "flatten"] or 0
        local changedMchBatch, newMchIdxBatch = imgui.Combo(ctx, "##BatchMultichannelMode",
            currentMchIdxBatch, MULTICHANNEL_MODE_OPTIONS)
        if changedMchBatch then
            Export_Settings.applyParamToSelected("multichannelExportMode", MULTICHANNEL_MODE_INDEX_TO_VALUE[newMchIdxBatch] or "flatten")
        end
        imgui.PopItemWidth(ctx)
    end

    -- Batch Instance Amount
    local instDiff = refOverride.params.instanceAmount ~= globalParams.instanceAmount
    if instDiff then
        imgui.TextColored(ctx, MODIFIED_COLOR, "Instances: *")
    else
        imgui.Text(ctx, "Instances:")
    end
    imgui.SameLine(ctx, OVERRIDE_LABEL_WIDTH)
    imgui.PushItemWidth(ctx, 100)
    local changedAmt, newAmt = imgui.DragInt(ctx, "##BatchAmount",
        refOverride.params.instanceAmount, 0.1,
        EXPORT.INSTANCE_MIN or 1, EXPORT.INSTANCE_MAX or 100)
    if changedAmt then
        Export_Settings.applyParamToSelected("instanceAmount", newAmt)
    end
    imgui.PopItemWidth(ctx)

    -- Batch Spacing
    local spcDiff = refOverride.params.spacing ~= globalParams.spacing
    if spcDiff then
        imgui.TextColored(ctx, MODIFIED_COLOR, "Spacing: *")
    else
        imgui.Text(ctx, "Spacing:")
    end
    imgui.SameLine(ctx, OVERRIDE_LABEL_WIDTH)
    imgui.PushItemWidth(ctx, 100)
    local changedSpc, newSpc = imgui.DragDouble(ctx, "##BatchSpacing",
        refOverride.params.spacing, 0.01,
        EXPORT.SPACING_MIN or 0, EXPORT.SPACING_MAX or 60, "%.2f")
    if changedSpc then
        Export_Settings.applyParamToSelected("spacing", newSpc)
    end
    imgui.PopItemWidth(ctx)

    -- Batch Max Pool Items
    local poolDiff = (refOverride.params.maxPoolItems or 0) ~= (globalParams.maxPoolItems or 0)
    if poolDiff then
        imgui.TextColored(ctx, MODIFIED_COLOR, "Max Pool: *")
    else
        imgui.Text(ctx, "Max Pool:")
    end
    imgui.SameLine(ctx, OVERRIDE_LABEL_WIDTH)
    imgui.PushItemWidth(ctx, 100)
    local changedMaxPoolBatch, newMaxPoolBatch = imgui.DragInt(ctx, "##BatchMaxPool",
        refOverride.params.maxPoolItems or 0, 0.1, 0, MAX_POOL_UI_LIMIT)
    if changedMaxPoolBatch then
        Export_Settings.applyParamToSelected("maxPoolItems", newMaxPoolBatch)
    end
    imgui.PopItemWidth(ctx)

    -- Batch Loop Mode
    local loopDiff = (refOverride.params.loopMode or "auto") ~= (globalParams.loopMode or "auto")
    if loopDiff then
        imgui.TextColored(ctx, MODIFIED_COLOR, "Loop Mode: *")
    else
        imgui.Text(ctx, "Loop Mode:")
    end
    imgui.SameLine(ctx, OVERRIDE_LABEL_WIDTH)
    imgui.PushItemWidth(ctx, 100)
    local currentLoopIdxBatch = LOOP_MODE_VALUE_TO_INDEX[refOverride.params.loopMode or "auto"] or 0
    local changedLoopBatch, newLoopIdxBatch = imgui.Combo(ctx, "##BatchLoopMode",
        currentLoopIdxBatch, LOOP_MODE_OPTIONS)
    if changedLoopBatch then
        Export_Settings.applyParamToSelected("loopMode", LOOP_MODE_INDEX_TO_VALUE[newLoopIdxBatch] or "auto")
    end
    imgui.PopItemWidth(ctx)

    -- Batch Loop Duration (only visible when loopMode != "off")
    if (refOverride.params.loopMode or "auto") ~= "off" then
        local loopDurDiff = (refOverride.params.loopDuration or 30) ~= (globalParams.loopDuration or 30)
        if loopDurDiff then
            imgui.TextColored(ctx, MODIFIED_COLOR, "Loop Dur: *")
        else
            imgui.Text(ctx, "Loop Dur:")
        end
        imgui.SameLine(ctx, OVERRIDE_LABEL_WIDTH)
        imgui.PushItemWidth(ctx, 100)
        local loopDurMin = EXPORT.LOOP_DURATION_MIN or 5
        local loopDurMax = EXPORT.LOOP_DURATION_MAX or 300
        local changedLoopDurBatch, newLoopDurBatch = imgui.DragInt(ctx, "##BatchLoopDuration",
            refOverride.params.loopDuration or 30, 1, loopDurMin, loopDurMax)
        if changedLoopDurBatch then
            Export_Settings.applyParamToSelected("loopDuration", newLoopDurBatch)
        end
        imgui.PopItemWidth(ctx)

        -- Batch Loop Interval
        local loopIntDiff = (refOverride.params.loopInterval or 0) ~= (globalParams.loopInterval or 0)
        if loopIntDiff then
            imgui.TextColored(ctx, MODIFIED_COLOR, "Loop Int: *")
        else
            imgui.Text(ctx, "Loop Int:")
        end
        imgui.SameLine(ctx, OVERRIDE_LABEL_WIDTH)
        imgui.PushItemWidth(ctx, 100)
        local loopIntMin = EXPORT.LOOP_INTERVAL_MIN or -10
        local loopIntMax = EXPORT.LOOP_INTERVAL_MAX or 10
        local changedLoopIntBatch, newLoopIntBatch = imgui.DragDouble(ctx, "##BatchLoopInterval",
            refOverride.params.loopInterval or 0, 0.1, loopIntMin, loopIntMax, "%.1f")
        if changedLoopIntBatch then
            Export_Settings.applyParamToSelected("loopInterval", newLoopIntBatch)
        end
        imgui.PopItemWidth(ctx)
        -- Auto-mode indicator: show when loopInterval is 0
        if (refOverride.params.loopInterval or 0) == 0 then
            imgui.SameLine(ctx)
            imgui.TextDisabled(ctx, "(auto: uses container intervals)")
            if imgui.IsItemHovered(ctx) then
                imgui.SetTooltip(ctx, "When set to 0, each container uses its own triggerRate\nfor overlap timing instead of a global value.")
            end
        end
    end

    -- Batch Align to seconds
    local alignDiff = refOverride.params.alignToSeconds ~= globalParams.alignToSeconds
    local changedAlignBatch, newAlignBatch = imgui.Checkbox(ctx,
        alignDiff and "Align to seconds *##batch" or "Align to seconds##batch",
        refOverride.params.alignToSeconds)
    if changedAlignBatch then
        Export_Settings.applyParamToSelected("alignToSeconds", newAlignBatch)
    end

    imgui.Spacing(ctx)

    -- Batch Preserve checkboxes
    local panDiff = refOverride.params.preservePan ~= globalParams.preservePan
    local c1, p1 = imgui.Checkbox(ctx,
        panDiff and "Preserve Pan *##batch" or "Preserve Pan##batch",
        refOverride.params.preservePan)
    if c1 then
        Export_Settings.applyParamToSelected("preservePan", p1)
    end

    local volDiff = refOverride.params.preserveVolume ~= globalParams.preserveVolume
    local c2, p2 = imgui.Checkbox(ctx,
        volDiff and "Preserve Volume *##batch" or "Preserve Volume##batch",
        refOverride.params.preserveVolume)
    if c2 then
        Export_Settings.applyParamToSelected("preserveVolume", p2)
    end

    local pitchDiff = refOverride.params.preservePitch ~= globalParams.preservePitch
    local c3, p3 = imgui.Checkbox(ctx,
        pitchDiff and "Preserve Pitch *##batch" or "Preserve Pitch##batch",
        refOverride.params.preservePitch)
    if c3 then
        Export_Settings.applyParamToSelected("preservePitch", p3)
    end

    imgui.Spacing(ctx)
    imgui.Separator(ctx)
    imgui.Spacing(ctx)

    -- Batch Export Method
    local methodDiff = (refOverride.params.exportMethod or 0) ~= (globalParams.exportMethod or 0)
    if methodDiff then
        imgui.TextColored(ctx, MODIFIED_COLOR, "Export To: *")
    else
        imgui.Text(ctx, "Export To:")
    end
    imgui.SameLine(ctx, OVERRIDE_LABEL_WIDTH)
    imgui.PushItemWidth(ctx, 120)
    local methods = "Current Track\0New Track\0"
    local changedMethodBatch, newMethodBatch = imgui.Combo(ctx, "##BatchMethod",
        refOverride.params.exportMethod or 0, methods)
    if changedMethodBatch then
        Export_Settings.applyParamToSelected("exportMethod", newMethodBatch)
    end
    imgui.PopItemWidth(ctx)

    -- Batch Create Regions
    local regionsDiff = refOverride.params.createRegions ~= globalParams.createRegions
    local changedRegionsBatch, newRegionsBatch = imgui.Checkbox(ctx,
        regionsDiff and "Create Regions *##batch" or "Create Regions##batch",
        refOverride.params.createRegions or false)
    if changedRegionsBatch then
        Export_Settings.applyParamToSelected("createRegions", newRegionsBatch)
    end

    -- Batch Region Pattern (only show if createRegions is enabled in reference)
    if refOverride.params.createRegions then
        local patternDiff = (refOverride.params.regionPattern or "") ~= (globalParams.regionPattern or "")
        if patternDiff then
            imgui.TextColored(ctx, MODIFIED_COLOR, "Pattern: *")
        else
            imgui.Text(ctx, "Pattern:")
        end
        imgui.SameLine(ctx, OVERRIDE_LABEL_WIDTH)
        imgui.PushItemWidth(ctx, 150)
        local changedPatternBatch, newPatternBatch = imgui.InputText(ctx, "##BatchPattern",
            refOverride.params.regionPattern or "$container", imgui.InputTextFlags_None)
        if changedPatternBatch then
            Export_Settings.applyParamToSelected("regionPattern", newPatternBatch)
        end
        imgui.PopItemWidth(ctx)
    end

    imgui.Unindent(ctx, 15)
end

return Export_UI
