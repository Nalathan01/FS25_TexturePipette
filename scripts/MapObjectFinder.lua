MapObjectFinder = {}

MapObjectFinder.mouseX = 0.5
MapObjectFinder.mouseY = 0.5
MapObjectFinder.raycastHit = nil

MapObjectFinder.isPipetteArmed = false

MapObjectFinder.nextArmedStatusRefreshAt = 0
MapObjectFinder.armedStatusRefreshInterval = 1.75

MapObjectFinder.tpResultItems = {}
MapObjectFinder.tpConstructionCategoryRegistered = false
MapObjectFinder.tpLastTrackedManualSelectionKey = nil
MapObjectFinder.tpDecoratedPipetteItems = nil
MapObjectFinder.tpLastTrackedConstructionSelectionKey = nil
MapObjectFinder.tpLastConstructionSelectionSnapshot = nil

MapObjectFinder.lastPipetteWorldX = nil
MapObjectFinder.lastPipetteWorldY = nil
MapObjectFinder.lastPipetteWorldZ = nil
MapObjectFinder.tpDebugOverlayLines = {}
MapObjectFinder.tpDebugLastClickTime = 0

local TP_MOD_DIRECTORY = g_currentModDirectory or ""

local TP_DEBUG_LOG = false
local TP_HEAVY_DIAGNOSTICS = false
local TP_DEBUG_OVERLAY_ENABLED = false
local TP_FOLIAGE_TEST_SUPPRESS_GROUND_RESULTS = false
local TP_MAP_ONLY_FOLIAGE_RESULT_ITEMS = false
local TP_TREE_SCAN_RADIUS = 1.40


local tpIsDebugModeEnabled

local TP_DEBUG_SUMMARY_PREFIXES = {
    "treePick descs=",
    "treePick placeableProbe",
    "treePick placeableMatchAccepted",
    "treePick noSafePlaceableMatch",
    "treePick collectError=",
    "pipetteMixedResults",
    "foliageResultCandidates=",
    "foliageResultCandidate index=",
    "groundResultDisplaySuppressed=",
    "rankSummary",
    "treeDiag scanError=",
    "treeDiag scan center=",
    "treeDiag hit index=",
    "treeDiag moreHits=",
    "treeDiag descError",
    "treeDiag skipped",
    "treeDiagError=",
    "staticMapObjectHitSuppressed",
    "staticMapObjectHierarchy",
}

local function tpShouldPrintDebugSummary(message)
    for _, prefix in ipairs(TP_DEBUG_SUMMARY_PREFIXES) do
        if string.sub(message, 1, string.len(prefix)) == prefix then
            return true
        end
    end

    return false
end

local function tpLog(message)
end

tpIsDebugModeEnabled = function()
    return false
end


local function tpText(key, fallback)
    if g_i18n ~= nil and g_i18n.getText ~= nil then
        local text = g_i18n:getText(key)
        if text ~= nil and text ~= "" and text ~= key then
            return text
        end
    end

    return fallback
end

local function tpShowMessage(text)
    if text == nil or text == "" then
        return
    end

    if g_currentMission ~= nil and g_currentMission.hud ~= nil and g_currentMission.hud.showBlinkingWarning ~= nil then
        g_currentMission.hud:showBlinkingWarning(text, 2000)
        return
    end

    if g_currentMission ~= nil and g_currentMission.addExtraPrintText ~= nil then
        g_currentMission:addExtraPrintText(text)
        return
    end
end

local function tpValueIsWorldPosition(x, y, z)
    return type(x) == "number"
        and type(y) == "number"
        and type(z) == "number"
        and math.abs(x) < 100000
        and math.abs(y) < 100000
        and math.abs(z) < 100000
end


local function tpExtractFileBaseName(filename)
    local value = tostring(filename or "")
    if value == "" then
        return ""
    end

    value = string.gsub(value, "\\", "/")
    local base = string.match(value, "([^/]+)$") or value
    base = string.gsub(base, "%.[Dd][Dd][Ss]$", "")
    base = string.gsub(base, "%.[Pp][Nn][Gg]$", "")
    base = string.gsub(base, "%.[Jj][Pp][Gg]$", "")
    base = string.gsub(base, "%.[Xx][Mm][Ll]$", "")
    return base
end

function MapObjectFinder:tpRestorePipetteDecoratedNames()
    if type(self.tpDecoratedPipetteItems) ~= "table" then
        return
    end

    for _, item in ipairs(self.tpDecoratedPipetteItems) do
        if type(item) == "table" and item.tpPipetteOriginalDisplayName ~= nil then
            item.name = item.tpPipetteOriginalDisplayName
            item.tpPipetteConfirmLabel = nil
            item.tpPipetteDebugSuffix = nil
            item.tpPipetteOriginalDisplayName = nil
        end
    end

    self.tpDecoratedPipetteItems = nil
end

function MapObjectFinder:tpDecoratePipetteResultNames(items)
    self:tpRestorePipetteDecoratedNames()
    self.tpDecoratedPipetteItems = {}

    for _, item in ipairs(items or {}) do
        if type(item) == "table" then
            item.tpPipetteOriginalDisplayName = tostring(item.name or item.title or "?")
            if item.tpPipetteDebugSuffix ~= nil then
                item.name = item.tpPipetteOriginalDisplayName .. tostring(item.tpPipetteDebugSuffix)
            end
            table.insert(self.tpDecoratedPipetteItems, item)
        end
    end
end


function MapObjectFinder:tpFormatConstructionMenuDebugLabel(item, categoryIndex, tabIndex, itemIndex)
    if type(item) ~= "table" then
        return nil
    end

    local brushParts = {}
    if type(item.brushParameters) == "table" then
        for i, value in ipairs(item.brushParameters) do
            table.insert(brushParts, tostring(value))
        end
    elseif type(item.storeItem) == "table" and type(item.storeItem.brush) == "table" and type(item.storeItem.brush.parameters) == "table" then
        for i, value in ipairs(item.storeItem.brush.parameters) do
            table.insert(brushParts, tostring(value))
        end
    end

    local brushText = table.concat(brushParts, "|")
    local imageBase = tpExtractFileBaseName(item.imageFilename or (type(item.storeItem) == "table" and item.storeItem.imageFilename or "") or "")
    local xmlBase = tpExtractFileBaseName(item.xmlFilename or item.filename or item.configFileName or (type(item.storeItem) == "table" and item.storeItem.xmlFilename or "") or "")
    local overlay = tostring(item.terrainOverlayLayer or item.overlayLayer or item.terrainLayer or "")

    local details = {}
    if brushText ~= "" then
        table.insert(details, brushText)
    end
    if overlay ~= "" and overlay ~= brushText then
        table.insert(details, "ov=" .. overlay)
    end
    if imageBase ~= "" then
        table.insert(details, imageBase)
    end
    if xmlBase ~= "" and xmlBase ~= imageBase then
        table.insert(details, xmlBase)
    end

    if #details == 0 then
        return nil
    end

    return string.format("%s [C%s/T%s/I%s | %s]", tostring(item.tpPipetteMenuOriginalName or item.name or item.title or "?"), tostring(categoryIndex or "-"), tostring(tabIndex or "-"), tostring(itemIndex or "-"), table.concat(details, " | "))
end

function MapObjectFinder:tpExposeConstructionInternalNames(screen)
    screen = screen or self:tpResolveConstructionLogicScreen()
    if type(screen) ~= "table" or type(screen.items) ~= "table" then
        return
    end

    local changed = 0
    for categoryIndex, categoryItems in pairs(screen.items) do
        if type(categoryItems) == "table" then
            for tabIndex, tabItems in pairs(categoryItems) do
                if type(tabItems) == "table" then
                    for itemIndex, item in ipairs(tabItems) do
                        if type(item) == "table" then
                            local hasBrush = type(item.brushParameters) == "table" or (type(item.storeItem) == "table" and type(item.storeItem.brush) == "table")
                            if hasBrush then
                                if item.tpPipetteMenuOriginalName == nil then
                                    item.tpPipetteMenuOriginalName = tostring(item.name or item.title or "?")
                                    item.tpPipetteMenuOriginalTitle = item.title
                                end
                                local debugLabel = self:tpFormatConstructionMenuDebugLabel(item, categoryIndex, tabIndex, itemIndex)
                                if debugLabel ~= nil then
                                    if item.name ~= debugLabel then
                                        item.name = debugLabel
                                        item.title = debugLabel
                                        changed = changed + 1
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    if changed > 0 and self.tpLastInternalNameExposeLogCount ~= changed then
        self.tpLastInternalNameExposeLogCount = changed
        tpLog("constructionMenuInternalNamesVisible changed=" .. tostring(changed))
    end
end

function MapObjectFinder:loadMap()
    self.mouseX = 0.5
    self.mouseY = 0.5
    self.raycastHit = nil

    self.isPipetteArmed = false
    self.nextArmedStatusRefreshAt = 0

    self.tpResultItems = {}
    self.tpDecoratedPipetteItems = nil
    self.tpLastTrackedConstructionSelectionKey = nil
    self.tpLastConstructionSelectionSnapshot = nil
    self.tpConstructionCategoryRegistered = false
    self.tpShowDialogSuppressionHookInstalled = false
    self.tpSuppressNextObjectInfoDialog = false
    self.tpSuppressNextObjectInfoDialogUntil = 0

    self.lastPipetteWorldX = nil
    self.lastPipetteWorldY = nil
    self.lastPipetteWorldZ = nil
    self.tpDebugOverlayLines = {}
    self.tpDebugLastClickTime = 0
    self.tpFoliageStructureLogged = false
    self.tpConstructionStructureLogged = false
    self.tpFoliageFunctionAvailabilityLogged = false
    self.tpConstructionInteractionTraceInstalled = false

    self:tpRegisterConstructionCategory()
    self:tpInstallShowDialogSuppressionHook()
end


function MapObjectFinder:tpGetConstructionIconUVs()
    if GuiUtils ~= nil and GuiUtils.getUVs ~= nil then
        return GuiUtils.getUVs("0 0 1 1", {1, 1})
    end

    return {0, 0, 1, 1}
end

function MapObjectFinder:tpRegisterConstructionCategory()
    if MapObjectFinderMenu ~= nil then
        if not MapObjectFinderMenu:isEnabled("pipetteEnabled") then
            return false
        end
        return MapObjectFinderMenu:registerConstructionMenu()
    end

    if self.tpConstructionCategoryRegistered == true then
        return true
    end

    if g_storeManager == nil
        or g_storeManager.getConstructionCategoryByName == nil
        or g_storeManager.addConstructionCategory == nil
        or g_storeManager.addConstructionTab == nil then
        return false
    end

    local category = g_storeManager:getConstructionCategoryByName("TP_PIPETTE")
    if category == nil then
        g_storeManager:addConstructionCategory(
            "TP_PIPETTE",
            tpText("TP_category_pipette", "Pipette"),
            "data/icon_TexturePipette_category.dds",
            self:tpGetConstructionIconUVs(),
            TP_MOD_DIRECTORY,
            nil
        )
    end

    local tab = nil
    if g_storeManager.getConstructionTabByName ~= nil then
        tab = g_storeManager:getConstructionTabByName("TP_RESULTS", "TP_PIPETTE")
    end

    if tab == nil then
        g_storeManager:addConstructionTab(
            "TP_PIPETTE",
            "TP_RESULTS",
            tpText("TP_tab_results", "Found Objects"),
            nil,
            nil,
            TP_MOD_DIRECTORY,
            nil
        )
    end

    self.tpConstructionCategoryRegistered = true
    return true
end

function MapObjectFinder:tpEnsurePipetteResultItemSlot(screen)
    if screen == nil
        or type(screen.categories) ~= "table"
        or type(screen.items) ~= "table" then
        return false
    end

    local categoryIndex, tabIndex = self:tpFindPipetteScreenIndices(screen)
    if categoryIndex == nil or tabIndex == nil then
        return false
    end

    if type(screen.items[categoryIndex]) ~= "table" then
        screen.items[categoryIndex] = {}
    end

    if screen.items[categoryIndex][tabIndex] == nil then
        screen.items[categoryIndex][tabIndex] = {}
    end

    return true
end


local function tpPipetteAppendRebuildData(self)
    if MapObjectFinder ~= nil then
        MapObjectFinder:tpRegisterConstructionCategory()
        MapObjectFinder:tpEnsurePipetteResultItemSlot(self)
    end
end

ConstructionScreen.rebuildData = Utils.appendedFunction(
    ConstructionScreen.rebuildData,
    tpPipetteAppendRebuildData
)

function MapObjectFinder:tpFindPipetteScreenIndices(screen)
    if screen == nil or type(screen.categories) ~= "table" then
        return nil, nil
    end

    for categoryIndex, category in ipairs(screen.categories) do
        if type(category) == "table" then
            local categoryName = tostring(category.name or "")
            if categoryName == "TP_PIPETTE_MENU" then
                local tabs = category.tabs
                if type(tabs) == "table" then
                    for tabIndex, tab in ipairs(tabs) do
                        if type(tab) == "table" and tostring(tab.name or "") == "TP_PIPETTE_TAB" then
                            return categoryIndex, tabIndex
                        end
                    end
                end

                return nil, nil
            end
        end
    end

    return nil, nil
end

function MapObjectFinder:tpIsPipetteResultTabActive(screen)
    local categoryIndex, tabIndex = self:tpFindPipetteScreenIndices(screen)
    return categoryIndex ~= nil
        and tabIndex ~= nil
        and screen ~= nil
        and tonumber(screen.currentCategory) == tonumber(categoryIndex)
        and tonumber(screen.currentTab) == tonumber(tabIndex)
end

function MapObjectFinder:tpGetPipetteUiState(screen)
    if screen == nil then
        return nil
    end

    if screen.tpPipettePanel == nil then
        screen.tpPipettePanel = {
            created = false,
            createFailed = false,
            container = nil,
            button = nil,
            buttonText = nil,
            candidateText = nil,
            statusText = nil
        }
    end

    return screen.tpPipettePanel
end

function MapObjectFinder:tpUpdatePipettePanelVisuals(screen)
    local state = self:tpGetPipetteUiState(screen)
    if state == nil then
        return
    end

    if state.buttonText ~= nil and state.buttonText.setText ~= nil then
        state.buttonText:setText(
            self.isPipetteArmed
                and tpText("TP_button_active", "Pipette active")
                or tpText("TP_button_activate", "Activate pipette")
        )
    end
    local statusElement = state.statusText or state.candidateText
    if statusElement ~= nil and statusElement.setVisible ~= nil then
        local statusText = tostring(self.tpPipettePanelStatusText or "")
        if statusText ~= "" then
            if statusElement.setText ~= nil then
                statusElement:setText(statusText)
            end
            statusElement:setVisible(true)
        else
            statusElement:setVisible(false)
        end
    end
end

function MapObjectFinder:tpSetPipettePanelStatus(text)
    self.tpPipettePanelStatusText = tostring(text or "")
    self:tpUpdatePipettePanelVisuals(self:tpResolveConstructionLogicScreen())
end

function MapObjectFinder:tpClearPipettePanelStatus()
    self.tpPipettePanelStatusText = ""
    self:tpUpdatePipettePanelVisuals(self:tpResolveConstructionLogicScreen())
end

function MapObjectFinder:tpCreatePipettePanel(screen)
    local state = self:tpGetPipetteUiState(screen)
    if state == nil then
        return false
    end

    if state.created then
        return true
    end

    if state.createFailed then
        return false
    end

    if loadXMLFile == nil or g_gui == nil or g_gui.loadGuiRec == nil then
        state.createFailed = true
        return false
    end

    if screen.subCategorySelector == nil or screen.subCategorySelector.parent == nil then
        state.createFailed = true
        return false
    end

    local xmlPath = TP_MOD_DIRECTORY .. "data/pipetteResultPanel.xml"
    local xmlFile = loadXMLFile("tpPipetteResultPanel", xmlPath)

    if xmlFile == nil or xmlFile == 0 then
        state.createFailed = true
        return false
    end

    local parentElement = screen.subCategorySelector.parent
    local before = #parentElement.elements

    g_gui:loadProfileSet(xmlFile, "GUI.GUIProfiles", g_gui.presets)
    g_gui:loadGuiRec(xmlFile, "GUI", parentElement, screen)
    delete(xmlFile)

    local after = #parentElement.elements
    if after <= before then
        state.createFailed = true
        return false
    end

    local container = parentElement.elements[after]
    local button = container:getDescendantById("tpPipetteActivateButton")
    local buttonText = container:getDescendantById("tpPipetteActivateText")
    local candidateText = container:getDescendantById("tpPipetteStatusText") or container:getDescendantById("tpPipetteCandidateText")
    local statusText = candidateText

    local subPos = screen.subCategorySelector.position
    local subSize = screen.subCategorySelector.size

    container:setPosition(subPos[1], subPos[2])
    container:setSize(subSize[1], 0.075)
    container:setVisible(false)
    container:updateAbsolutePosition()

    if button ~= nil then
        button.target = screen
    end

    state.container = container
    state.button = button
    state.buttonText = buttonText
    state.candidateText = candidateText
    state.statusText = statusText
    state.created = true

    self:tpUpdatePipettePanelVisuals(screen)
    return true
end

function MapObjectFinder:tpRefreshPipetteResultItems(screen)
    local categoryIndex, tabIndex = self:tpFindPipetteScreenIndices(screen)
    if categoryIndex == nil or tabIndex == nil or screen == nil or type(screen.items) ~= "table" then
        return false
    end

    if type(screen.items[categoryIndex]) ~= "table" then
        screen.items[categoryIndex] = {}
    end

    screen.items[categoryIndex][tabIndex] = self.tpResultItems or {}

    if self:tpIsPipetteResultTabActive(screen)
        and screen.itemList ~= nil
        and screen.itemList.reloadData ~= nil then
        pcall(function()
            screen.itemList:reloadData()
        end)
    end

    return true
end

function MapObjectFinder:tpUpdatePipetteResultArea()
    if not self:isConstructionScreenOpen() then
        return
    end

    local screen = self:tpResolveConstructionLogicScreen()
    if screen == nil then
        return
    end

    self:tpEnsurePipetteResultItemSlot(screen)
    self:tpCreatePipettePanel(screen)
    self:tpRefreshPipetteResultItems(screen)

    local state = self:tpGetPipetteUiState(screen)
    if state ~= nil and state.container ~= nil then
        state.container:setVisible(self:tpIsPipetteResultTabActive(screen))
    end

    self:tpUpdatePipettePanelVisuals(screen)
end

function MapObjectFinder:tpSetConstructionSelectorBrush(screen)
    if screen == nil or type(screen.setBrush) ~= "function" then
        return false
    end

    local selectorBrush = screen.selectorBrush
    if selectorBrush == nil
        and g_constructionBrushTypeManager ~= nil
        and type(g_constructionBrushTypeManager.getClassObjectByTypeName) == "function"
        and screen.cursor ~= nil then
        local ok, class = pcall(function()
            return g_constructionBrushTypeManager:getClassObjectByTypeName("select")
        end)
        if ok and class ~= nil and type(class.new) == "function" then
            local createdOk, createdBrush = pcall(function()
                return class.new(nil, screen.cursor)
            end)
            if createdOk and createdBrush ~= nil then
                selectorBrush = createdBrush
                screen.selectorBrush = createdBrush
            end
        end
    end

    if selectorBrush ~= nil then
        local ok = pcall(function()
            screen:setBrush(selectorBrush, true)
        end)
        return ok == true
    end

    return false
end

function ConstructionScreen:onPtpPipetteActivateButtonClick()
    if MapObjectFinder == nil then
        return
    end

    local hasSelection = MapObjectFinder.lastPipetteWorldX ~= nil
    local wasArmed = MapObjectFinder.isPipetteArmed == true

    MapObjectFinder:tpSetConstructionSelectorBrush(self)

    if hasSelection then
        MapObjectFinder.isPipetteArmed = true
        MapObjectFinder.nextArmedStatusRefreshAt = 0
        MapObjectFinder:tpClearPipetteSelection(self, "buttonRearm")
        MapObjectFinder:tpUpdatePipettePanelVisuals(self)
        tpShowMessage(tpText("TP_msg_armed", "Pipette ready. Click target."))
        return
    end

    MapObjectFinder.isPipetteArmed = not wasArmed
    MapObjectFinder.nextArmedStatusRefreshAt = 0
    MapObjectFinder:tpUpdatePipettePanelVisuals(self)

    if MapObjectFinder.isPipetteArmed then
        MapObjectFinder:tpInstallShowDialogSuppressionHook()
        tpShowMessage(tpText("TP_msg_armed", "Pipette ready. Click target."))
    else
        tpShowMessage(tpText("TP_msg_cancelled", "Pipette off."))
    end
end


local function tpAfterConstructionScreenClose(screen, ...)
    if MapObjectFinder == nil then
        return
    end

    MapObjectFinder.isPipetteArmed = false
    MapObjectFinder.nextArmedStatusRefreshAt = 0
    MapObjectFinder:tpClearPipetteSelection(screen, "constructionScreenClose")
end

if ConstructionScreen ~= nil and ConstructionScreen.onClose ~= nil then
    ConstructionScreen.onClose = Utils.appendedFunction(ConstructionScreen.onClose, tpAfterConstructionScreenClose)
end


function MapObjectFinder:mouseEvent(posX, posY, isDown, isUp, button)
    if type(posX) == "number" then
        self.mouseX = posX
    end

    if type(posY) == "number" then
        self.mouseY = posY
    end

    local mouseX = tonumber(self.mouseX) or -1
    local isLikelyWorldArea = mouseX >= 0.30

    if self:isConstructionScreenOpen()
        and self.isPipetteArmed ~= true
        and button == 1
        and isDown == true
        and isLikelyWorldArea then
        self:tpTrackActiveConstructionSelection("worldClickMaybePaint", true)
    end

    if self.isPipetteArmed
        and self:isConstructionScreenOpen()
        and button == 1
        and isDown == true then

        if not isLikelyWorldArea then
            return
        end

        self:tpSetConstructionSelectorBrush(self:tpResolveConstructionLogicScreen())
        self:tpArmPipetteWorldClickDialogSuppression()
        self:pickTextureAtCurrentMousePosition()

        self.isPipetteArmed = false
        self.nextArmedStatusRefreshAt = 0
        self:tpUpdatePipettePanelVisuals(self:tpResolveConstructionLogicScreen())
    end
end

function MapObjectFinder:tpGetCurrentPipetteSelectedItem(screen)
    if screen == nil or screen.itemList == nil or not self:tpIsPipetteResultTabActive(screen) then
        return nil, nil
    end

    local categoryIndex, tabIndex = self:tpFindPipetteScreenIndices(screen)
    if categoryIndex == nil or tabIndex == nil or type(screen.items) ~= "table" then
        return nil, nil
    end

    local list = screen.items[categoryIndex] ~= nil and screen.items[categoryIndex][tabIndex] or nil
    if type(list) ~= "table" then
        return nil, nil
    end

    local selectedIndex = tonumber(screen.itemList.selectedIndex or screen.itemList.selectedItemIndex or screen.selectedIndex or 0)
    if selectedIndex == nil or selectedIndex <= 0 then
        return nil, nil
    end

    return list[selectedIndex], selectedIndex
end

function MapObjectFinder:tpGetCurrentConstructionSelectedItem(screen)
    if screen == nil or screen.itemList == nil or type(screen.items) ~= "table" then
        return nil, nil, nil, nil
    end

    local categoryIndex = tonumber(screen.currentCategory or screen.selectedCategoryIndex or 0)
    local tabIndex = tonumber(screen.currentTab or screen.selectedTabIndex or 0)
    local selectedIndex = tonumber(screen.itemList.selectedIndex or screen.itemList.selectedItemIndex or screen.selectedIndex or 0)

    if categoryIndex == nil or tabIndex == nil or selectedIndex == nil or categoryIndex <= 0 or tabIndex <= 0 or selectedIndex <= 0 then
        return nil, nil, nil, nil
    end

    local categoryItems = screen.items[categoryIndex]
    local list = type(categoryItems) == "table" and categoryItems[tabIndex] or nil
    if type(list) ~= "table" then
        return nil, nil, nil, nil
    end

    return list[selectedIndex], selectedIndex, categoryIndex, tabIndex
end

function MapObjectFinder:tpBuildConstructionItemConfirmLabel(item, itemIndex, categoryIndex, tabIndex)
    if type(item) ~= "table" then
        return "-"
    end

    local originalName = tostring(item.tpPipetteOriginalDisplayName or item.name or item.title or "?")
    local imageBase = tpExtractFileBaseName(item.imageFilename or "")
    local xmlBase = tpExtractFileBaseName(item.xmlFilename or item.filename or item.configFileName or "")
    local brushBase = ""

    if type(item.brushParameters) == "table" then
        brushBase = tostring(item.brushParameters[1] or "")
        brushBase = tpExtractFileBaseName(brushBase)
    end

    local idPart = imageBase ~= "" and imageBase or (xmlBase ~= "" and xmlBase or brushBase)
    if idPart == "" then
        idPart = "unknown"
    end

    return string.format("C%s T%s I%s | %s | %s", tostring(categoryIndex or "-"), tostring(tabIndex or "-"), tostring(itemIndex or "-"), originalName, idPart)
end

function MapObjectFinder:tpTrackActiveConstructionSelection(context, force)
    local screen = self:tpResolveConstructionLogicScreen()
    local item, index, categoryIndex, tabIndex = self:tpGetCurrentConstructionSelectedItem(screen)
    if type(item) ~= "table" then
        return nil
    end

    local label = self:tpBuildConstructionItemConfirmLabel(item, index, categoryIndex, tabIndex)
    local itemName = tostring(item.tpPipetteOriginalDisplayName or item.name or item.title or "-")
    local itemXml = tostring(item.xmlFilename or item.filename or item.configFileName or "")
    local itemImage = tostring(item.imageFilename or "")
    local brushParameter = ""
    local terrainOverlayLayer = tostring(item.terrainOverlayLayer or item.overlayLayer or item.terrainLayer or "")

    local brushParts = {}
    if type(item.brushParameters) == "table" then
        for _, value in ipairs(item.brushParameters) do
            table.insert(brushParts, tostring(value))
        end
    elseif type(item.storeItem) == "table" and type(item.storeItem.brush) == "table" and type(item.storeItem.brush.parameters) == "table" then
        for _, value in ipairs(item.storeItem.brush.parameters) do
            table.insert(brushParts, tostring(value))
        end
    end
    brushParameter = table.concat(brushParts, "|")

    local key = table.concat({
        tostring(categoryIndex or "-"),
        tostring(tabIndex or "-"),
        tostring(index or "-"),
        itemName,
        itemXml,
        itemImage,
        brushParameter,
        terrainOverlayLayer
    }, "|")

    self.tpLastConstructionSelectionSnapshot = {
        context = tostring(context or "selection"),
        label = label,
        name = itemName,
        xml = itemXml,
        image = itemImage,
        brushParameter = brushParameter,
        terrainOverlayLayer = terrainOverlayLayer,
        itemIndex = index,
        categoryIndex = categoryIndex,
        tabIndex = tabIndex
    }

    if item.tpMapOnlyFoliage == true and tpIsDebugModeEnabled() == true then
        local storeBrush = "<none>"
        if type(item.storeItem) == "table" and type(item.storeItem.brush) == "table" and type(item.storeItem.brush.parameters) == "table" then
            storeBrush = table.concat(item.storeItem.brush.parameters, "|")
        end

        local activeLayer = "<none>"
        local activePaintState = "<nil>"
        local activeFoliageState = "<nil>"
        local activePlane = "<nil>"
        if type(screen) == "table" and type(screen.brush) == "table" then
            if type(screen.brush.foliagePaint) == "table" then
                activeLayer = tostring(screen.brush.foliagePaint.layerName or "<none>")
                activePaintState = tostring(screen.brush.foliagePaint.state or "<nil>")
                activePlane = tostring(screen.brush.foliagePaint.terrainDataPlaneId or "<nil>")
            end
            activeFoliageState = tostring(screen.brush.foliageState or "<nil>")
        end

        local wantedLayer = tostring(item.tpMapOnlyFoliageLayer or "")
        local wantedState = tostring(item.tpMapOnlyFoliageState or "")
        local activeAccepted = (activeLayer == wantedLayer and activeFoliageState == wantedState)
        local selectionLogKey = table.concat({
            tostring(context or "selection"), wantedLayer, wantedState, tostring(brushParameter or ""),
            tostring(storeBrush), tostring(categoryIndex or "-"), tostring(tabIndex or "-"), tostring(index or "-"),
            activeLayer, activeFoliageState, activePaintState, activePlane
        }, "|")

        if force == true or self.tpLastMapFoliageSelectionLogKey ~= selectionLogKey then
            tpLog(string.format(
                "mapFoliageSelection context=%s layer=%s state=%s brush=%s storeBrush=%s activeLayer=%s activeFoliageState=%s activePaintState=%s activePlane=%s accepted=%s cat=%s tab=%s item=%s",
                tostring(context or "selection"),
                tostring(item.tpMapOnlyFoliageLayer or "<nil>"),
                tostring(item.tpMapOnlyFoliageState or "<nil>"),
                tostring(brushParameter or ""),
                tostring(storeBrush),
                tostring(activeLayer),
                tostring(activeFoliageState),
                tostring(activePaintState),
                tostring(activePlane),
                tostring(activeAccepted),
                tostring(categoryIndex or "-"),
                tostring(tabIndex or "-"),
                tostring(index or "-")
            ))
            self.tpLastMapFoliageSelectionLogKey = selectionLogKey

            if tostring(context or "") == "update" then
                if activeAccepted == true then
                    tpShowMessage("Karten-Foliage gewählt: Brush übernommen.")
                else
                    tpShowMessage("Karten-Foliage gewählt.")
                end
            end
        end

        self.tpLastMapFoliageItem = {
            context = tostring(context or "selection"),
            layer = tostring(item.tpMapOnlyFoliageLayer or ""),
            state = tostring(item.tpMapOnlyFoliageState or ""),
            brush = tostring(brushParameter or ""),
            storeBrush = tostring(storeBrush),
            activeLayer = tostring(activeLayer),
            activeFoliageState = tostring(activeFoliageState),
            activePaintState = tostring(activePaintState),
            activePlane = tostring(activePlane),
            activeAccepted = activeAccepted,
            label = label,
            name = itemName,
            categoryIndex = categoryIndex,
            tabIndex = tabIndex,
            itemIndex = index
        }
    end

    if tostring(context or "") == "worldClickMaybePaint" then
        self.tpLastPaintedConstructionSelectionSnapshot = self.tpLastConstructionSelectionSnapshot

        local brushLower = string.lower(tostring(brushParameter or ""))
        local imageBase = tpExtractFileBaseName(itemImage)
        local xmlBase = tpExtractFileBaseName(itemXml)
    end

    if force ~= true and key == self.tpLastTrackedConstructionSelectionKey then
        return self.tpLastConstructionSelectionSnapshot
    end

    self.tpLastTrackedConstructionSelectionKey = key

    return self.tpLastConstructionSelectionSnapshot
end


function MapObjectFinder:tpInstallConstructionInteractionTrace()
    if TP_HEAVY_DIAGNOSTICS ~= true then
        return
    end

    if self.tpConstructionInteractionTraceInstalled == true then
        return
    end

    local tpSelf = self

    local function valueToShortString(value)
        local valueType = type(value)
        if value == nil then
            return "<nil>"
        elseif valueType == "string" then
            return value
        elseif valueType == "number" or valueType == "boolean" then
            return tostring(value)
        elseif valueType == "table" then
            local keys = {}
            local count = 0
            for key, _ in pairs(value) do
                count = count + 1
                if count <= 12 then
                    table.insert(keys, tostring(key))
                end
            end
            table.sort(keys)

            local detailParts = {}
            for _, detailKey in ipairs({
                "layerName", "state", "id", "terrainDataPlaneId", "startStateChannel", "numStateChannels",
                "uniqueIndex", "name", "title", "price", "imageFilename", "xmlFilename", "filename"
            }) do
                local detailValue = value[detailKey]
                if detailValue ~= nil and type(detailValue) ~= "table" then
                    table.insert(detailParts, tostring(detailKey) .. "=" .. tostring(detailValue))
                end
            end

            if #detailParts > 0 then
                return "table:" .. tostring(value) .. " details={" .. table.concat(detailParts, ",") .. "} keys=" .. table.concat(keys, ",")
            end

            return "table:" .. tostring(value) .. " keys=" .. table.concat(keys, ",")
        end
        return tostring(value)
    end

    local function describeFoliagePaint(paint)
        if type(paint) ~= "table" then
            return tostring(paint)
        end

        local parts = {}
        for _, key in ipairs({
            "layerName", "state", "id", "terrainDataPlaneId", "startStateChannel", "numStateChannels"
        }) do
            table.insert(parts, tostring(key) .. "=" .. tostring(paint[key]))
        end

        return table.concat(parts, ",")
    end

    local function formatArgs(...)
        local parts = {}
        local count = select("#", ...)
        for index = 1, count do
            table.insert(parts, tostring(index) .. "=" .. valueToShortString(select(index, ...)))
        end
        return table.concat(parts, " ; ")
    end

    local function formatReturns(values)
        local parts = {}
        for index, value in ipairs(values or {}) do
            table.insert(parts, tostring(index) .. "=" .. valueToShortString(value))
        end
        if #parts == 0 then
            return "<none>"
        end
        return table.concat(parts, " ; ")
    end

    local function describeItem(item)
        if type(item) ~= "table" then
            return "<noItem>"
        end

        local brush = ""
        if type(item.brushParameters) == "table" then
            brush = table.concat(item.brushParameters, "|")
        end

        return string.format(
            "name=%s title=%s brush=%s image=%s xml=%s price=%s uniqueIndex=%s brushClass=%s",
            tostring(item.name or "<nil>"),
            tostring(item.title or "<nil>"),
            tostring(brush),
            tostring(item.imageFilename or "<nil>"),
            tostring(item.xmlFilename or item.filename or item.configFileName or "<nil>"),
            tostring(item.price or "<nil>"),
            tostring(item.uniqueIndex or "<nil>"),
            tostring(item.brushClass or "<nil>")
        )
    end

    local function traceScreenState(screen, context)
        if type(screen) ~= "table" then
            return
        end

        local item, index, categoryIndex, tabIndex = tpSelf:tpGetCurrentConstructionSelectedItem(screen)
        tpLog(string.format(
            "constructionInteractionScreen context=%s currentCategory=%s currentTab=%s selected=%s selectedIndex=%s itemIndex=%s itemCat=%s itemTab=%s item=%s",
            tostring(context),
            tostring(screen.currentCategory),
            tostring(screen.currentTab),
            tostring(screen.selected),
            tostring(screen.itemList ~= nil and screen.itemList.selectedIndex or "<nil>"),
            tostring(index),
            tostring(categoryIndex),
            tostring(tabIndex),
            describeItem(item)
        ))
    end

    local function traceBrushState(brush, context)
        if type(brush) ~= "table" then
            return
        end

        local parts = {}
        for key, value in pairs(brush) do
            local lower = string.lower(tostring(key))
            if string.find(lower, "foliage", 1, true) ~= nil
                or string.find(lower, "brush", 1, true) ~= nil
                or string.find(lower, "state", 1, true) ~= nil
                or string.find(lower, "type", 1, true) ~= nil
                or string.find(lower, "density", 1, true) ~= nil
                or string.find(lower, "layer", 1, true) ~= nil
                or string.find(lower, "parameter", 1, true) ~= nil
                or string.find(lower, "item", 1, true) ~= nil then
                table.insert(parts, tostring(key) .. "=" .. valueToShortString(value))
            end
        end
        table.sort(parts)
        tpLog("constructionInteractionBrush context=" .. tostring(context) .. " " .. table.concat(parts, " ; "))

        if type(brush.foliagePaint) == "table" then
            tpLog("constructionInteractionFoliagePaint context=" .. tostring(context) .. " " .. describeFoliagePaint(brush.foliagePaint))
        end

        if type(brush.storeItem) == "table" then
            tpLog("constructionInteractionStoreItem context=" .. tostring(context) .. " " .. describeItem(brush.storeItem))
            if type(brush.storeItem.brush) == "table" then
                local brushParts = {}
                for _, key in ipairs({"type", "category", "tab"}) do
                    if brush.storeItem.brush[key] ~= nil then
                        table.insert(brushParts, tostring(key) .. "=" .. tostring(brush.storeItem.brush[key]))
                    end
                end
                tpLog("constructionInteractionStoreItemBrush context=" .. tostring(context) .. " " .. table.concat(brushParts, ","))
                if type(brush.storeItem.brush.parameters) == "table" then
                    local parameterParts = {}
                    for i, value in ipairs(brush.storeItem.brush.parameters) do
                        table.insert(parameterParts, tostring(i) .. "=" .. tostring(value) .. "(" .. type(value) .. ")")
                    end
                    tpLog("constructionInteractionStoreItemBrushParameters context=" .. tostring(context) .. " values=" .. table.concat(parameterParts, " ; "))
                else
                    tpLog("constructionInteractionStoreItemBrushParameters context=" .. tostring(context) .. " type=" .. tostring(type(brush.storeItem.brush.parameters)) .. " value=" .. tostring(brush.storeItem.brush.parameters))
                end
            end
        end
    end

    local function wrapFunction(ownerLabel, ownerTable, fnName, traceKind)
        if type(ownerTable) ~= "table" then
            return
        end

        local original = ownerTable[fnName]
        if type(original) ~= "function" then
            return
        end

        local originalKey = "__tpOriginal_" .. tostring(fnName)
        if ownerTable[originalKey] ~= nil then
            return
        end

        ownerTable[originalKey] = original
        ownerTable[fnName] = function(...)
            tpLog("constructionInteractionCall before owner=" .. tostring(ownerLabel) .. " fn=" .. tostring(fnName) .. " args=" .. formatArgs(...))
            local firstArg = select(1, ...)
            if traceKind == "screen" then
                traceScreenState(firstArg, "before_" .. tostring(fnName))
            elseif traceKind == "brush" then
                traceBrushState(firstArg, "before_" .. tostring(fnName))
            end

            local results = {pcall(original, ...)}
            local ok = table.remove(results, 1)
            if ok ~= true then
                tpLog("constructionInteractionCall error owner=" .. tostring(ownerLabel) .. " fn=" .. tostring(fnName) .. " error=" .. tostring(results[1]))
                error(results[1])
            end

            if traceKind == "screen" then
                traceScreenState(firstArg, "after_" .. tostring(fnName))
            elseif traceKind == "brush" then
                traceBrushState(firstArg, "after_" .. tostring(fnName))
            end
            tpLog("constructionInteractionCall after owner=" .. tostring(ownerLabel) .. " fn=" .. tostring(fnName) .. " returns=" .. formatReturns(results))

            return unpack(results)
        end
        tpLog("constructionInteractionHooked owner=" .. tostring(ownerLabel) .. " fn=" .. tostring(fnName))
    end

    local foliageBrushClass = _G ~= nil and _G.ConstructionBrushFoliage or nil
    if type(foliageBrushClass) == "table" then
        for _, fnName in ipairs({"setParameters", "setFoliageType", "activate", "copyState", "onButtonPrimary", "performBrush", "update", "deactivate"}) do
            wrapFunction("ConstructionBrushFoliage", foliageBrushClass, fnName, "brush")
        end
    end

    local screen = self:tpResolveConstructionLogicScreen()
    if type(screen) == "table" then
        local mt = getmetatable(screen)
        if type(mt) == "table" then
            for _, fnName in ipairs({"onClickItem", "onListSelectionChanged", "setBrush", "setCurrentCategory", "setCurrentTab", "updateMenuState", "refreshDetails", "populateCellForItemInSection"}) do
                wrapFunction("ConstructionScreenMeta", mt, fnName, "screen")
            end
        end

        for _, fnName in ipairs({"onClickItem", "onListSelectionChanged", "setBrush", "setCurrentCategory", "setCurrentTab", "updateMenuState", "refreshDetails", "populateCellForItemInSection"}) do
            wrapFunction("ConstructionScreen", screen, fnName, "screen")
        end
    end

    self.tpConstructionInteractionTraceInstalled = true
    tpLog("constructionInteractionTraceInstalled=true")
end


function MapObjectFinder:tpTrackManualPipetteSelection()
end

function MapObjectFinder:update(dt)
    self:tpInstallShowDialogSuppressionHook()
    if TP_HEAVY_DIAGNOSTICS == true then
        self:tpInstallConstructionInteractionTrace()
    end
    self:tpClearExpiredObjectInfoDialogSuppression()
    self:updatePersistentArmedStatus()
    self:tpUpdatePipetteResultArea()
    if tpIsDebugModeEnabled() == true then
        self:tpExposeConstructionInternalNames()
    else
        self:tpRestorePipetteDecoratedNames()
    end
    self:tpTrackActiveConstructionSelection("update")
    self:tpTrackManualPipetteSelection()
end

function MapObjectFinder:updatePersistentArmedStatus()
    if not self.isPipetteArmed then
        return
    end

    if not self:isConstructionScreenOpen() then
        self.isPipetteArmed = false
        self.nextArmedStatusRefreshAt = 0
        return
    end

end

function MapObjectFinder:isConstructionScreenOpen()
    if g_gui == nil then
        return false
    end

    if g_gui.currentGuiName ~= nil and string.find(string.lower(tostring(g_gui.currentGuiName)), "construction", 1, true) ~= nil then
        return true
    end

    if g_gui.currentGui ~= nil then
        local className = tostring(g_gui.currentGui.className or g_gui.currentGui.name or "")
        if string.find(string.lower(className), "construction", 1, true) ~= nil then
            return true
        end
    end

    return false
end

function MapObjectFinder:tpResolveConstructionLogicScreen()
    local candidates = {}

    if g_gui ~= nil then
        table.insert(candidates, g_gui.currentGui)

        if type(g_gui.guis) == "table" then
            table.insert(candidates, g_gui.guis["ConstructionScreen"])
            table.insert(candidates, g_gui.guis["constructionScreen"])
        end

        if type(g_gui.frames) == "table" then
            table.insert(candidates, g_gui.frames["ConstructionScreen"])
            table.insert(candidates, g_gui.frames["constructionScreen"])
        end
    end

    if g_constructionScreen ~= nil then
        table.insert(candidates, g_constructionScreen)
    end

    local visited = {}
    local expanded = {}

    for _, object in ipairs(candidates) do
        if object ~= nil and not visited[object] then
            visited[object] = true
            table.insert(expanded, object)

            if type(object) == "table" then
                for _, childKey in ipairs({ "target", "controller", "screen", "logic" }) do
                    local child = object[childKey]
                    if child ~= nil and not visited[child] then
                        visited[child] = true
                        table.insert(expanded, child)
                    end
                end
            end
        end
    end

    local bestCandidate = nil
    local bestScore = -1

    for _, object in ipairs(expanded) do
        local score = 0

        if type(object) == "table" then
            if object.items ~= nil then score = score + 4 end
            if object.currentCategory ~= nil then score = score + 3 end
            if object.itemList ~= nil then score = score + 3 end
            if object.cursor ~= nil then score = score + 2 end
            if object.brush ~= nil then score = score + 2 end
            if object.menuBox ~= nil then score = score + 1 end
        end

        if score > bestScore then
            bestScore = score
            bestCandidate = object
        end
    end

    return bestCandidate, nil, bestScore
end


function MapObjectFinder:tpCollectCurrentPaintTabCandidates()
    local screen = self:tpResolveConstructionLogicScreen()
    if screen == nil or type(screen.items) ~= "table" then
        return {}
    end

    local results = {}
    local seen = {}

    for categoryIndex, categoryItems in pairs(screen.items) do
        if type(categoryItems) == "table" then
            for tabIndex, tabItems in pairs(categoryItems) do
                if type(tabItems) == "table" then
                    for itemIndex, item in ipairs(tabItems) do
                        if type(item) == "table"
                            and item.terrainOverlayLayer ~= nil
                            and type(item.brushParameters) == "table"
                            and type(item.brushParameters[1]) == "string"
                            and item.brushParameters[1] ~= "" then

                            local name = item.name ~= nil and tostring(item.name) or ""
                            local brushParameter = tostring(item.brushParameters[1])
                            local uniqueKey = table.concat({
                                tostring(name),
                                tostring(brushParameter),
                                tostring(item.terrainOverlayLayer)
                            }, "|")

                            if not seen[uniqueKey] then
                                seen[uniqueKey] = true
                                table.insert(results, {
                                    categoryIndex = categoryIndex,
                                    tabIndex = tabIndex,
                                    itemIndex = itemIndex,
                                    name = name,
                                    brushParameter = brushParameter,
                                    terrainOverlayLayer = item.terrainOverlayLayer,
                                    sourceItem = item
                                })
                            end
                        end
                    end
                end
            end
        end
    end

    return results
end

function MapObjectFinder:raycastClosestCallback(nodeId, x, y, z, distance, nx, ny, nz, subShapeIndex, shapeId, isLast)
    self.raycastHit = {
        nodeId = nodeId,
        x = x,
        y = y,
        z = z,
        distance = distance,
        nx = nx,
        ny = ny,
        nz = nz,
        subShapeIndex = subShapeIndex,
        shapeId = shapeId
    }

    return true
end

function MapObjectFinder:tpResolveNodeObjectFromRaycastHit()
    local hit = self.raycastHit
    local nodeId = hit ~= nil and hit.nodeId or nil

    if nodeId == nil or nodeId == 0 or g_currentMission == nil or g_currentMission.getNodeObject == nil then
        return nil, nil
    end

    local currentNode = nodeId
    local visited = {}

    for _ = 1, 16 do
        if currentNode == nil or currentNode == 0 or visited[currentNode] then
            break
        end

        visited[currentNode] = true

        local object = g_currentMission:getNodeObject(currentNode)
        if object ~= nil then
            return object, currentNode
        end

        if getParent == nil then
            break
        end

        currentNode = getParent(currentNode)
    end

    return nil, nil
end

function MapObjectFinder:tpIsRaycastHitTerrainRelated()
    local hit = self.raycastHit
    local nodeId = hit ~= nil and hit.nodeId or nil
    if nodeId == nil or nodeId == 0 then
        return true
    end

    local terrainRootNode = g_currentMission ~= nil and g_currentMission.terrainRootNode or nil
    if terrainRootNode ~= nil and nodeId == terrainRootNode then
        return true
    end

    local currentNode = nodeId
    local visited = {}
    for _ = 1, 16 do
        if currentNode == nil or currentNode == 0 or visited[currentNode] == true then
            break
        end
        visited[currentNode] = true
        if terrainRootNode ~= nil and currentNode == terrainRootNode then
            return true
        end
        if getParent == nil then
            break
        end
        currentNode = getParent(currentNode)
    end

    return false
end

function MapObjectFinder:tpGetRaycastHitNodeLabel()
    local hit = self.raycastHit
    local nodeId = hit ~= nil and hit.nodeId or nil
    if nodeId == nil or nodeId == 0 then
        return "object"
    end

    if getName ~= nil then
        local ok, name = pcall(getName, nodeId)
        if ok == true and name ~= nil and tostring(name) ~= "" then
            return tostring(name)
        end
    end

    return "object"
end

local function tpCleanPanelObjectLabel(value)
    local text = tostring(value or "")
    if text == "" then
        return tpText("TP_label_mapObject", "map object")
    end
    if string.find(text, "Missing '", 1, true) ~= nil then
        return tpText("TP_label_mapObject", "map object")
    end
    return text
end


function MapObjectFinder:tpBuildRaycastHitNodeHierarchyLabel()
    local nodeId = nil
    if type(self.raycastHit) == "table" then
        nodeId = self.raycastHit.node or self.raycastHit.nodeId or self.raycastHit.objectId
    end
    if nodeId == nil and self.lastRaycastHitNode ~= nil then
        nodeId = self.lastRaycastHitNode
    end
    if nodeId == nil or nodeId == 0 or type(getParent) ~= "function" then
        return nil
    end

    local parts = {}
    local current = nodeId
    local visited = {}
    for _ = 1, 12 do
        if current == nil or current == 0 or visited[current] == true then
            break
        end
        visited[current] = true
        local name = nil
        if type(getName) == "function" then
            local okName, value = pcall(function()
                return getName(current)
            end)
            if okName == true and value ~= nil then
                name = tostring(value)
            end
        end
        if name ~= nil and name ~= "" then
            table.insert(parts, 1, name)
        end
        local okParent, parent = pcall(function()
            return getParent(current)
        end)
        if okParent ~= true then
            break
        end
        current = parent
    end

    if #parts == 0 then
        return nil
    end
    return table.concat(parts, "/")
end

function MapObjectFinder:tpTryHandleStaticMapObjectHit(screen)
    if self:tpIsRaycastHitTerrainRelated() == true then
        return false
    end

    local object = self:tpResolveNodeObjectFromRaycastHit()
    if object ~= nil then
        return false
    end

    local label = tpCleanPanelObjectLabel(self:tpGetRaycastHitNodeLabel())
    local hierarchy = self:tpBuildRaycastHitNodeHierarchyLabel()
    local staticTreeItem = self:tpCreateStaticTreeDisplayItem(hierarchy)

    self.tpResultItems = {}
    self:tpResetLayerMenuOutput()

    if staticTreeItem ~= nil then
        self.tpResultItems = {staticTreeItem}
        self:tpDecoratePipetteResultNames(self.tpResultItems)
        self.tpPipettePanelStatusText = nil
        if screen ~= nil then
            self:tpRefreshPipetteResultItems(screen)
            self:tpUpdatePipettePanelVisuals(screen)
        end
        tpLog("staticTreeMapObjectRecognized node=" .. tostring(label) .. " path=" .. tostring(hierarchy))
        return true
    end

    self.tpPipettePanelStatusText = string.format(tpText("TP_msg_staticNotInBuildMenu", "No construction menu entry at this position. Static map object: %s"), label)
    if screen ~= nil then
        self:tpRefreshPipetteResultItems(screen)
        self:tpUpdatePipettePanelVisuals(screen)
    end
    tpLog("staticMapObjectHitSuppressed node=" .. tostring(label) .. " reason=noConstructionMenuObject")
    if hierarchy ~= nil then
        tpLog("staticMapObjectHierarchy path=" .. tostring(hierarchy))
    end
    return true
end

local function tpNormalizeComparableFilename(filename)
    if filename == nil then
        return nil
    end

    local value = tostring(filename)
    if value == "" then
        return nil
    end

    value = string.lower(value)
    value = string.gsub(value, "\\", "/")
    return value
end

function MapObjectFinder:tpGetDisplayItemStoreFilename(item)
    if type(item) ~= "table" then
        return nil
    end

    local filename = item.xmlFilename
        or item.filename
        or item.configFileName
        or (
            type(item.storeItem) == "table"
            and (
                item.storeItem.xmlFilename
                or item.storeItem.filename
                or item.storeItem.configFileName
            )
        )

    return tpNormalizeComparableFilename(filename)
end

function MapObjectFinder:tpFindConstructionDisplayItemForStoreItem(screen, storeItem, xmlFilename)
    if screen == nil or type(screen.items) ~= "table" then
        return nil, "screenItemsMissing"
    end

    local wantedFilename = tpNormalizeComparableFilename(xmlFilename)
    if wantedFilename == nil and type(storeItem) == "table" then
        wantedFilename = tpNormalizeComparableFilename(
            storeItem.xmlFilename or storeItem.filename or storeItem.configFileName
        )
    end

    for _, categoryItems in pairs(screen.items) do
        if type(categoryItems) == "table" then
            for _, tabItems in pairs(categoryItems) do
                if type(tabItems) == "table" then
                    for _, item in ipairs(tabItems) do
                        if type(item) == "table" then
                            if item == storeItem then
                                return item, "directItem"
                            end

                            if item.storeItem ~= nil and item.storeItem == storeItem then
                                return item, "storeItemReference"
                            end

                            local itemFilename = self:tpGetDisplayItemStoreFilename(item)
                            if wantedFilename ~= nil and itemFilename ~= nil and itemFilename == wantedFilename then
                                return item, "filenameMatch"
                            end
                        end
                    end
                end
            end
        end
    end

    return nil, "notFound"
end


function MapObjectFinder:tpResetLayerMenuOutput()
end


function MapObjectFinder:tpResolveStoreItemFromPlaceableObject(object)
    if object == nil or g_storeManager == nil or g_storeManager.getItemByXMLFilename == nil then
        return nil, nil
    end

    local xmlFilename = object.configFileName or object.xmlFilename
    if xmlFilename == nil or tostring(xmlFilename) == "" then
        return nil, nil
    end

    local ok, storeItem = pcall(function()
        return g_storeManager:getItemByXMLFilename(xmlFilename)
    end)

    if ok and storeItem ~= nil then
        return storeItem, xmlFilename
    end

    return nil, xmlFilename
end


function MapObjectFinder:tpCollectPlaceableDisplayItemFromObject(object, screen, sourceLabel)
    if object == nil then
        return nil
    end

    local storeItem, xmlFilename = self:tpResolveStoreItemFromPlaceableObject(object)
    if storeItem == nil then
        return nil
    end

    screen = screen or self:tpResolveConstructionLogicScreen()
    local displayItem, displayResolveMode = self:tpFindConstructionDisplayItemForStoreItem(screen, storeItem, xmlFilename)
    if displayItem == nil then
        if tpIsDebugModeEnabled() == true then
            local storeName = tostring(storeItem.name or storeItem.customEnvironment or storeItem.xmlFilename or xmlFilename or "Object")
            tpLog("placeablePick noDisplayItem name=" .. storeName .. " mode=" .. tostring(displayResolveMode) .. " source=" .. tostring(sourceLabel or "direct"))
        end
        return nil
    end

    if tpIsDebugModeEnabled() == true then
        local displayStoreItem = type(displayItem.storeItem) == "table" and displayItem.storeItem or storeItem
        local storeName = tostring(
            displayItem.name
            or (displayStoreItem ~= nil and displayStoreItem.name)
            or storeItem.name
            or storeItem.customEnvironment
            or storeItem.xmlFilename
            or "Object"
        )
        tpLog("placeablePick displayItemAccepted name=" .. storeName .. " mode=" .. tostring(displayResolveMode) .. " source=" .. tostring(sourceLabel or "direct"))
    end

    return displayItem
end

function MapObjectFinder.tpOnPlaceableNearbyShapeDetected(self, shapeId)
    if self == nil or shapeId == nil or shapeId == 0 then
        return
    end

    self.tpPlaceableNearbyShapes = self.tpPlaceableNearbyShapes or {}
    self.tpPlaceableNearbySeen = self.tpPlaceableNearbySeen or {}

    if self.tpPlaceableNearbySeen[shapeId] == true then
        return
    end

    self.tpPlaceableNearbySeen[shapeId] = true
    table.insert(self.tpPlaceableNearbyShapes, shapeId)
end

function MapObjectFinder:tpCollectPlaceableObjectsNearWorldPosition(x, y, z)
    local results = {}

    x = tonumber(x)
    y = tonumber(y)
    z = tonumber(z)

    if x == nil or y == nil or z == nil or type(overlapSphere) ~= "function" or g_currentMission == nil or type(g_currentMission.getNodeObject) ~= "function" then
        return results
    end

    self.tpPlaceableNearbyShapes = {}
    self.tpPlaceableNearbySeen = {}

    local radius = 0.75
    local scanY = y + 0.75
    local mask = 4294967295

    local okScan, scanError = pcall(function()
        overlapSphere(x, scanY, z, radius, "tpOnPlaceableNearbyShapeDetected", self, mask, false, false, true, false)
    end)

    local rawShapes = self.tpPlaceableNearbyShapes or {}
    self.tpPlaceableNearbyShapes = nil
    self.tpPlaceableNearbySeen = nil

    if tpIsDebugModeEnabled() == true then
        tpLog("placeableNearbyScan ok=" .. tostring(okScan) .. " hits=" .. tostring(#rawShapes) .. " radius=" .. tostring(radius) .. " error=" .. tostring(scanError))
    end

    if okScan ~= true or #rawShapes == 0 then
        return results
    end

    local seenObjects = {}

    for _, shapeId in ipairs(rawShapes) do
        local currentNode = shapeId
        local visited = {}

        for _ = 1, 16 do
            if currentNode == nil or currentNode == 0 or visited[currentNode] == true then
                break
            end
            visited[currentNode] = true

            local object = g_currentMission:getNodeObject(currentNode)
            if object ~= nil and seenObjects[object] ~= true then
                seenObjects[object] = true
                table.insert(results, {
                    object = object,
                    node = currentNode,
                    shape = shapeId
                })
                break
            end

            if type(getParent) ~= "function" then
                break
            end

            local okParent, parent = pcall(function()
                return getParent(currentNode)
            end)
            if okParent ~= true then
                break
            end
            currentNode = parent
        end
    end

    return results
end

function MapObjectFinder:tpCollectPlaceableDisplayItemsNearWorldPosition(x, y, z, screen, usedItems)
    local resultItems = {}
    local nearbyObjects = self:tpCollectPlaceableObjectsNearWorldPosition(x, y, z)
    usedItems = usedItems or {}

    for _, entry in ipairs(nearbyObjects or {}) do
        local item = self:tpCollectPlaceableDisplayItemFromObject(entry.object, screen, "nearby")
        if item ~= nil and usedItems[item] ~= true then
            usedItems[item] = true
            item.tpPipetteDebugSuffix = " [Objekt | Umkreis]"
            table.insert(resultItems, item)
            if #resultItems >= 1 then
                break
            end
        end
    end

    return resultItems
end

function MapObjectFinder:tpCollectPlaceableDisplayItemsAtCurrentRaycast(screen)
    screen = screen or self:tpResolveConstructionLogicScreen()

    local resultItems = {}
    local usedItems = {}

    local object, objectNodeId = self:tpResolveNodeObjectFromRaycastHit()
    local directItem = self:tpCollectPlaceableDisplayItemFromObject(object, screen, "direct")
    if directItem ~= nil then
        usedItems[directItem] = true
        directItem.tpPipetteDebugSuffix = " [Objekt | direkt]"
        table.insert(resultItems, directItem)
    end

    if self.lastPipetteWorldX ~= nil then
        local nearbyItems = self:tpCollectPlaceableDisplayItemsNearWorldPosition(
            self.lastPipetteWorldX,
            self.lastPipetteWorldY,
            self.lastPipetteWorldZ,
            screen,
            usedItems
        )

        for _, item in ipairs(nearbyItems or {}) do
            table.insert(resultItems, item)
        end
    end

    return resultItems
end

function MapObjectFinder:tpTryPickPlaceableAtCurrentRaycast()
    local object, objectNodeId = self:tpResolveNodeObjectFromRaycastHit()
    if object == nil then
        return false
    end

    local storeItem, xmlFilename = self:tpResolveStoreItemFromPlaceableObject(object)
    if storeItem == nil then
        return false
    end

    local screen = self:tpResolveConstructionLogicScreen()
    local displayItem, displayResolveMode = self:tpFindConstructionDisplayItemForStoreItem(screen, storeItem, xmlFilename)

    if displayItem == nil then
        local storeName = tostring(storeItem.name or storeItem.customEnvironment or storeItem.xmlFilename or "Object")
        self.tpResultItems = {}
        self:tpRefreshPipetteResultItems(screen)
        self:tpUpdatePipettePanelVisuals(screen)

        tpShowMessage(string.format(tpText("TP_msg_objectNotReady", "Not buildable: %s"), storeName))
        return true
    end

    self.tpResultItems = { displayItem }

    if screen ~= nil then
        self:tpRefreshPipetteResultItems(screen)
        self:tpUpdatePipettePanelVisuals(screen)
        self:tpTryPreselectFirstPipetteResult(screen)
    end

    local displayStoreItem = type(displayItem.storeItem) == "table" and displayItem.storeItem or storeItem
    local storeName = tostring(
        displayItem.name
        or (displayStoreItem ~= nil and displayStoreItem.name)
        or storeItem.name
        or storeItem.customEnvironment
        or storeItem.xmlFilename
        or "Object"
    )

    tpShowMessage(string.format(tpText("TP_msg_objectDetected", "Selected: %s"), storeName))

    return true
end


function MapObjectFinder:findMouseWorldPosition()
    if unProject == nil then
        return nil
    end

    if raycastClosest == nil then
        return nil
    end

    local sx = tonumber(self.mouseX) or 0.5
    local sy = tonumber(self.mouseY) or 0.5

    local nearX, nearY, nearZ = unProject(sx, sy, 0)
    local farX, farY, farZ = unProject(sx, sy, 1)

    if not tpValueIsWorldPosition(nearX, nearY, nearZ) or not tpValueIsWorldPosition(farX, farY, farZ) then
        return nil
    end

    local dx = farX - nearX
    local dy = farY - nearY
    local dz = farZ - nearZ
    local length = math.sqrt(dx * dx + dy * dy + dz * dz)

    if length <= 0.0001 then
        return nil
    end

    dx = dx / length
    dy = dy / length
    dz = dz / length

    self.raycastHit = nil

    local ok, numHits = pcall(function()
        return raycastClosest(
            nearX,
            nearY,
            nearZ,
            dx,
            dy,
            dz,
            10000,
            "raycastClosestCallback",
            self
        )
    end)

    if not ok then
        return nil
    end

    if self.raycastHit ~= nil then
        return self.raycastHit.x, self.raycastHit.y, self.raycastHit.z
    end

    return nil
end

function MapObjectFinder:getTerrainRoot()
    if g_currentMission ~= nil and g_currentMission.terrainRootNode ~= nil then
        return g_currentMission.terrainRootNode
    end

    return nil
end


function MapObjectFinder:tpRankCandidateMatchesBySubLayerCompetition(candidateMatches, sessionId)
    local x = self.lastPipetteWorldX
    local y = self.lastPipetteWorldY
    local z = self.lastPipetteWorldZ
    local terrainRoot = self:getTerrainRoot()

    local directEntries = {}
    local contextEntries = {}
    local surroundingEntries = {}
    local neutralEntries = {}
    local summaryDirectLabels = {}
    local summaryContextLabels = {}
    local summarySurroundingLabels = {}
    local scanned = 0
    local directPositive = 0
    local contextPositive = 0
    local surroundingPositive = 0
    local failed = 0

    if x == nil or y == nil or z == nil
        or terrainRoot == nil
        or type(getTerrainLayerAtWorldPos) ~= "function"
        or type(getTerrainLayerSubLayer) ~= "function" then

        return candidateMatches or {}, {
            scanned = 0,
            positive = 0,
            directPositive = 0,
            contextPositive = 0,
            surroundingPositive = 0,
            failed = 0,
            shown = #(candidateMatches or {}),
            favoriteName = nil,
            favoriteBrush = nil,
            messageMode = "fallback"
        }
    end
    local directOffsets = {
        -0.25, -0.125, 0.00, 0.125, 0.25
    }

    local contextOffsets = {
        -0.55, -0.35, 0.00, 0.35, 0.55
    }

    local surroundingOffsets = {
        -0.90, -0.70, 0.00, 0.70, 0.90
    }

    local function probeOverlay(overlayLayer, offsets)
        local candidatePositive = false
        local candidateFailed = false
        local candidateScore = 0
        local perCandidateSignals = {}

        if overlayLayer ~= nil then
            for subIndex = 0, 3 do
                local subOk, subLayerId = pcall(function()
                    return getTerrainLayerSubLayer(terrainRoot, overlayLayer, subIndex)
                end)

                local numericSubLayerId = subOk and tonumber(subLayerId) or nil
                if numericSubLayerId ~= nil and numericSubLayerId >= 0 then
                    local sampleCount = 0
                    local failCount = 0
                    local positiveCount = 0
                    local total = 0
                    local maxValue = 0
                    local centerValue = nil

                    for _, dx in ipairs(offsets) do
                        for _, dz in ipairs(offsets) do
                            local layerOk, layerValue = pcall(function()
                                return getTerrainLayerAtWorldPos(
                                    terrainRoot,
                                    numericSubLayerId,
                                    (tonumber(x) or 0) + dx,
                                    tonumber(y) or 0,
                                    (tonumber(z) or 0) + dz
                                )
                            end)

                            if layerOk then
                                sampleCount = sampleCount + 1
                                local numericLayerValue = tonumber(layerValue) or 0
                                total = total + numericLayerValue

                                if numericLayerValue > maxValue then
                                    maxValue = numericLayerValue
                                end
                                if numericLayerValue > 0 then
                                    positiveCount = positiveCount + 1
                                end
                                if dx == 0 and dz == 0 then
                                    centerValue = numericLayerValue
                                end
                            else
                                failCount = failCount + 1
                            end
                        end
                    end

                    if failCount > 0 then
                        candidateFailed = true
                    end

                    if positiveCount > 0 or total > 0 or (tonumber(centerValue) or 0) > 0 then
                        candidatePositive = true
                        candidateScore = candidateScore + total + positiveCount + ((tonumber(centerValue) or 0) * 10)

                        table.insert(perCandidateSignals, string.format(
                            "sub%s=id%s:center%s:sum%s:max%s:pos%s:samples%s:fail%s",
                            tostring(subIndex),
                            tostring(numericSubLayerId),
                            tostring(centerValue),
                            tostring(total),
                            tostring(maxValue),
                            tostring(positiveCount),
                            tostring(sampleCount),
                            tostring(failCount)
                        ))
                    end
                elseif subOk ~= true then
                    candidateFailed = true
                end
            end
        else
            candidateFailed = true
        end

        return candidatePositive, candidateFailed, candidateScore, perCandidateSignals
    end

    for _, entry in ipairs(candidateMatches or {}) do
        scanned = scanned + 1

        local item = entry ~= nil and entry.sourceItem or nil
        local candidate = entry ~= nil and entry.candidate or {}
        local candidateName = tostring(candidate.name or candidate.itemName or (item ~= nil and item.name) or "<nil>")
        local candidateBrush = tostring(candidate.brushParameter or (
            item ~= nil
            and type(item.brushParameters) == "table"
            and item.brushParameters[1]
        ) or "<nil>")
        local overlayLayer = item ~= nil and tonumber(item.terrainOverlayLayer) or nil

        local directHit, directFailed, directScore, directSignals = probeOverlay(overlayLayer, directOffsets)
        local contextHit, contextFailed, contextScore, contextSignals = probeOverlay(overlayLayer, contextOffsets)
        local surroundingHit, surroundingFailed, surroundingScore, surroundingSignals = probeOverlay(overlayLayer, surroundingOffsets)

        entry.tpDirectPositive = directHit
        entry.tpDirectScore = directScore
        entry.tpDirectSignals = directSignals
        entry.tpContextPositive = contextHit
        entry.tpContextScore = contextScore
        entry.tpContextSignals = contextSignals
        entry.tpSurroundingPositive = surroundingHit
        entry.tpSurroundingScore = surroundingScore
        entry.tpSurroundingSignals = surroundingSignals

        if directHit then
            directPositive = directPositive + 1
            table.insert(directEntries, entry)

            local directLabel = string.format(
                "candidate=%s/%s overlay=%s directScore=%s %s",
                tostring(candidateName),
                tostring(candidateBrush),
                tostring(overlayLayer),
                tostring(directScore),
                #directSignals > 0 and table.concat(directSignals, "|") or "<no-positive-direct-signal>"
            )
            table.insert(summaryDirectLabels, directLabel)
        elseif contextHit then
            contextPositive = contextPositive + 1
            table.insert(contextEntries, entry)

            local contextLabel = string.format(
                "candidate=%s/%s overlay=%s contextScore=%s %s",
                tostring(candidateName),
                tostring(candidateBrush),
                tostring(overlayLayer),
                tostring(contextScore),
                #contextSignals > 0 and table.concat(contextSignals, "|") or "<no-positive-context-signal>"
            )
            table.insert(summaryContextLabels, contextLabel)
        elseif surroundingHit then
            surroundingPositive = surroundingPositive + 1
            table.insert(surroundingEntries, entry)

            local surroundingLabel = string.format(
                "candidate=%s/%s overlay=%s surroundingScore=%s %s",
                tostring(candidateName),
                tostring(candidateBrush),
                tostring(overlayLayer),
                tostring(surroundingScore),
                #surroundingSignals > 0 and table.concat(surroundingSignals, "|") or "<no-positive-surrounding-signal>"
            )
            table.insert(summarySurroundingLabels, surroundingLabel)
        else
            table.insert(neutralEntries, entry)
        end

        if directFailed or contextFailed or surroundingFailed then
            failed = failed + 1
        end
    end

    local function sortByScoreAndName(entries, scoreKey)
        table.sort(entries, function(a, b)
            local aScore = tonumber(a[scoreKey]) or 0
            local bScore = tonumber(b[scoreKey]) or 0
            if aScore ~= bScore then
                return aScore > bScore
            end

            local aCandidate = a.candidate or {}
            local bCandidate = b.candidate or {}
            local aName = tostring(aCandidate.name or aCandidate.itemName or "")
            local bName = tostring(bCandidate.name or bCandidate.itemName or "")
            if aName == bName then
                return tostring(aCandidate.brushParameter or "") < tostring(bCandidate.brushParameter or "")
            end
            return aName < bName
        end)
    end

    sortByScoreAndName(directEntries, "tpDirectScore")
    sortByScoreAndName(contextEntries, "tpContextScore")
    sortByScoreAndName(surroundingEntries, "tpSurroundingScore")

    table.sort(neutralEntries, function(a, b)
        local aCandidate = a.candidate or {}
        local bCandidate = b.candidate or {}
        local aName = tostring(aCandidate.name or aCandidate.itemName or "")
        local bName = tostring(bCandidate.name or bCandidate.itemName or "")
        if aName == bName then
            return tostring(aCandidate.brushParameter or "") < tostring(bCandidate.brushParameter or "")
        end
        return aName < bName
    end)

    local ranked = {}
    local mode = "fallbackFullCatalog"

    if #directEntries > 0 then
        mode = "directPlusCloseContext"
        for _, entry in ipairs(directEntries) do
            table.insert(ranked, entry)
        end

        if #ranked < 4 then
            for _, entry in ipairs(contextEntries) do
                if #ranked >= 4 then
                    break
                end
                table.insert(ranked, entry)
            end
        end

        if #ranked < 4 then
            for _, entry in ipairs(surroundingEntries) do
                if #ranked >= 4 then
                    break
                end
                table.insert(ranked, entry)
            end
        end
    else
        if #contextEntries > 0 then
            mode = "contextOnlyLocal"
            for _, entry in ipairs(contextEntries) do
                if #ranked >= 4 then
                    break
                end
                table.insert(ranked, entry)
            end
        elseif #surroundingEntries > 0 then
            mode = "surroundingOnlyLocal"
            for _, entry in ipairs(surroundingEntries) do
                if #ranked >= 4 then
                    break
                end
                table.insert(ranked, entry)
            end
        else
            mode = "noLocalHit"
        end
    end

    if #ranked > 4 then
        local limitedRanked = {}
        for i = 1, 4 do
            table.insert(limitedRanked, ranked[i])
        end
        ranked = limitedRanked
    end

    local favoriteName = nil
    local favoriteBrush = nil
    if #directEntries > 0 then
        local favoriteCandidate = directEntries[1].candidate or {}
        favoriteName = tostring(favoriteCandidate.name or favoriteCandidate.itemName or "<nil>")
        favoriteBrush = tostring(favoriteCandidate.brushParameter or "<nil>")
    end

    local messageMode = "fallback"
    if #directEntries == 1 and #contextEntries == 0 and #surroundingEntries == 0 then
        messageMode = "unique"
    elseif #directEntries == 1 and #contextEntries > 0 and #surroundingEntries == 0 then
        messageMode = "directWithContext"
    elseif #directEntries == 1 and #contextEntries == 0 and #surroundingEntries > 0 then
        messageMode = "directWithSurrounding"
    elseif #directEntries == 1 and #contextEntries > 0 and #surroundingEntries > 0 then
        messageMode = "directWithContextAndSurrounding"
    elseif #directEntries > 1 and #contextEntries == 0 and #surroundingEntries == 0 then
        messageMode = "multiple"
    elseif #directEntries > 1 and #contextEntries > 0 and #surroundingEntries == 0 then
        messageMode = "multipleWithContext"
    elseif #directEntries > 1 and #contextEntries == 0 and #surroundingEntries > 0 then
        messageMode = "multipleWithSurrounding"
    elseif #directEntries > 1 and #contextEntries > 0 and #surroundingEntries > 0 then
        messageMode = "multipleWithContextAndSurrounding"
    elseif #directEntries == 0 and #contextEntries > 0 and #surroundingEntries == 0 then
        messageMode = "contextOnly"
    elseif #directEntries == 0 and #contextEntries > 0 and #surroundingEntries > 0 then
        messageMode = "contextWithSurrounding"
    elseif #directEntries == 0 and #contextEntries == 0 and #surroundingEntries > 0 then
        messageMode = "surroundingOnly"
    end

    tpLog(string.format(
        "rankSummary scanned=%s direct=%s context=%s surrounding=%s failed=%s shown=%s mode=%s pos=%.3f,%.3f,%.3f",
        tostring(scanned),
        tostring(directPositive),
        tostring(contextPositive),
        tostring(surroundingPositive),
        tostring(failed),
        tostring(#ranked),
        tostring(mode),
        tonumber(x) or 0,
        tonumber(y) or 0,
        tonumber(z) or 0
    ))

    for index, entry in ipairs(ranked or {}) do
        local candidate = entry.candidate or {}
        tpLog(string.format(
            "rankedCandidate index=%s name=%s brush=%s overlay=%s direct=%s/%s context=%s/%s surrounding=%s/%s",
            tostring(index),
            tostring(candidate.name or candidate.itemName or "<nil>"),
            tostring(candidate.brushParameter or "<nil>"),
            tostring(candidate.terrainOverlayLayer or candidate.overlayLayer or candidate.terrainLayer or "<nil>"),
            tostring(entry.tpDirectPositive),
            tostring(entry.tpDirectScore),
            tostring(entry.tpContextPositive),
            tostring(entry.tpContextScore),
            tostring(entry.tpSurroundingPositive),
            tostring(entry.tpSurroundingScore)
        ))
    end

    if #ranked == 0 and #neutralEntries > 0 then
        local maxNeutral = math.min(#neutralEntries, 8)
        for index = 1, maxNeutral do
            local entry = neutralEntries[index] or {}
            local candidate = entry.candidate or {}
            tpLog(string.format(
                "neutralCandidate index=%s name=%s brush=%s overlay=%s",
                tostring(index),
                tostring(candidate.name or candidate.itemName or "<nil>"),
                tostring(candidate.brushParameter or "<nil>"),
                tostring(candidate.terrainOverlayLayer or candidate.overlayLayer or candidate.terrainLayer or "<nil>")
            ))
        end
    end

    return ranked, {
        scanned = scanned,
        positive = directPositive,
        directPositive = directPositive,
        contextPositive = contextPositive,
        surroundingPositive = surroundingPositive,
        failed = failed,
        shown = #ranked,
        favoriteName = favoriteName,
        favoriteBrush = favoriteBrush,
        messageMode = messageMode
    }
end

function MapObjectFinder:tpTryPreselectFirstPipetteResult(screen)
    if screen == nil or screen.itemList == nil then
        return false
    end

    local ok = false

    if screen.itemList.setSelectedIndex ~= nil then
        ok = pcall(function()
            screen.itemList:setSelectedIndex(1)
        end)
    elseif screen.itemList.setSelectedItem ~= nil then
        ok = pcall(function()
            screen.itemList:setSelectedItem(1)
        end)
    else
        ok = pcall(function()
            screen.itemList.selectedIndex = 1
        end)
    end

    return ok == true
end

function MapObjectFinder:tpStoreResultMatchesForResultTab(mergedMatches)
    self:tpRestorePipetteDecoratedNames()
    local resultItems = {}

    for _, entry in ipairs(mergedMatches or {}) do
        if entry.sourceItem ~= nil then
            table.insert(resultItems, entry.sourceItem)
        end
    end

    self.tpResultItems = resultItems

    local screen = self:tpResolveConstructionLogicScreen()
    if screen ~= nil then
        self:tpRefreshPipetteResultItems(screen)
        self:tpUpdatePipettePanelVisuals(screen)
    end

    return #resultItems
end


function MapObjectFinder:tpClearPipetteSelection(screen, reason)
    self:tpRestorePipetteDecoratedNames()
    self.tpResultItems = {}
    self:tpResetLayerMenuOutput()
    self.tpPipettePanelStatusText = ""
    self.tpLastTrackedManualSelectionKey = nil
    self.lastPipetteWorldX = nil
    self.lastPipetteWorldY = nil
    self.lastPipetteWorldZ = nil

    screen = screen or self:tpResolveConstructionLogicScreen()
    if screen ~= nil then
        self:tpRefreshPipetteResultItems(screen)
        self:tpUpdatePipettePanelVisuals(screen)
    end

end


function MapObjectFinder:tpFormatDebugValue(value)
    local valueType = type(value)
    if valueType == "nil" then
        return "<nil>"
    elseif valueType == "number" or valueType == "boolean" then
        return tostring(value)
    elseif valueType == "string" then
        if string.len(value) > 120 then
            return string.sub(value, 1, 120) .. "..."
        end
        return value
    elseif valueType == "table" then
        local label = tostring(value)
        local name = rawget(value, "name") or rawget(value, "title") or rawget(value, "typeName") or rawget(value, "layerName")
        if name ~= nil then
            label = label .. ":" .. tostring(name)
        end
        return label
    end

    return valueType
end

function MapObjectFinder:tpLogTableKeys(label, data, maxKeys)
    if type(data) ~= "table" then
        tpLog(tostring(label) .. " type=" .. tostring(type(data)) .. " value=" .. tostring(data))
        return
    end

    local keys = {}
    for key, value in pairs(data) do
        table.insert(keys, tostring(key) .. "=" .. self:tpFormatDebugValue(value))
        if #keys >= (maxKeys or 30) then
            break
        end
    end

    table.sort(keys)
    tpLog(tostring(label) .. " keys=" .. table.concat(keys, " ; "))
end

function MapObjectFinder:tpLogCandidateDeep(label, item, maxKeys)
    label = tostring(label or "candidate")
    maxKeys = maxKeys or 80

    if type(item) ~= "table" then
        tpLog(label .. " type=" .. tostring(type(item)) .. " value=" .. tostring(item))
        return
    end

    self:tpLogTableKeys(label .. ".item", item, maxKeys)

    if type(item.brushParameters) == "table" then
        local parts = {}
        for i, value in ipairs(item.brushParameters) do
            table.insert(parts, tostring(i) .. "=" .. tostring(value) .. "(" .. type(value) .. ")")
        end
        tpLog(label .. ".brushParameters values=" .. table.concat(parts, " ; "))
        self:tpLogTableKeys(label .. ".brushParametersKeys", item.brushParameters, maxKeys)
    else
        tpLog(label .. ".brushParameters type=" .. tostring(type(item.brushParameters)) .. " value=" .. tostring(item.brushParameters))
    end

    local nestedKeys = {"displayItem", "storeItem", "brushClass", "category", "tab", "typeDesc"}
    for _, key in ipairs(nestedKeys) do
        if type(item[key]) == "table" then
            self:tpLogTableKeys(label .. "." .. key, item[key], maxKeys)
        elseif item[key] ~= nil then
            tpLog(label .. "." .. key .. " type=" .. tostring(type(item[key])) .. " value=" .. tostring(item[key]))
        end
    end

    if type(item.storeItem) == "table" and type(item.storeItem.brush) == "table" then
        self:tpLogTableKeys(label .. ".storeItem.brush", item.storeItem.brush, maxKeys)
        if type(item.storeItem.brush.parameters) == "table" then
            local parameterParts = {}
            for i, value in ipairs(item.storeItem.brush.parameters) do
                table.insert(parameterParts, tostring(i) .. "=" .. tostring(value) .. "(" .. type(value) .. ")")
            end
            tpLog(label .. ".storeItem.brush.parameters values=" .. table.concat(parameterParts, " ; "))
            self:tpLogTableKeys(label .. ".storeItem.brush.parametersKeys", item.storeItem.brush.parameters, maxKeys)
        else
            tpLog(label .. ".storeItem.brush.parameters type=" .. tostring(type(item.storeItem.brush.parameters)) .. " value=" .. tostring(item.storeItem.brush.parameters))
        end
    end
end


function MapObjectFinder:tpLogFoliageFunctionAvailabilityOnce()
    if self.tpFoliageFunctionAvailabilityLogged == true then
        return
    end
    self.tpFoliageFunctionAvailabilityLogged = true

    local names = {
        "getDensityAtWorldPos",
        "getDensityMapAtWorldPos",
        "getDensityMapHeightAtWorldPos",
        "getDensityMapValueAtWorldPos",
        "getFoliageDensityAtWorldPos",
        "getFoliageTypeAtWorldPos",
        "getTerrainSystem",
        "getDensityMapData",
        "getTerrainDetailByName",
        "getTerrainDataPlaneByName",
        "getTerrainLayerAtWorldPos",
        "getTerrainLayerSubLayer"
    }

    local parts = {}
    for _, name in ipairs(names) do
        table.insert(parts, name .. "=" .. tostring(type(_G[name])))
    end

    tpLog("foliageFunctionAvailability " .. table.concat(parts, " "))
end

function MapObjectFinder:tpLogConstructionStructureOnce(screen)
    if self.tpConstructionStructureLogged == true then
        return
    end
    self.tpConstructionStructureLogged = true

    screen = screen or self:tpResolveConstructionLogicScreen()
    if screen == nil or type(screen.items) ~= "table" then
        tpLog("constructionStructure missing")
        return
    end

    local total = 0
    for categoryIndex, categoryItems in pairs(screen.items) do
        if type(categoryItems) == "table" then
            for tabIndex, tabItems in pairs(categoryItems) do
                if type(tabItems) == "table" then
                    tpLog(string.format("constructionTab category=%s tab=%s items=%s", tostring(categoryIndex), tostring(tabIndex), tostring(#tabItems)))
                    for itemIndex, item in ipairs(tabItems) do
                        if type(item) == "table" then
                            total = total + 1
                            local brushParameter = ""
                            if type(item.brushParameters) == "table" then
                                brushParameter = table.concat(item.brushParameters, "|")
                            end
                            tpLog(string.format(
                                "constructionItem category=%s tab=%s item=%s name=%s title=%s brush=%s overlay=%s terrainLayer=%s image=%s xml=%s",
                                tostring(categoryIndex),
                                tostring(tabIndex),
                                tostring(itemIndex),
                                tostring(item.name or "<nil>"),
                                tostring(item.title or "<nil>"),
                                tostring(brushParameter),
                                tostring(item.terrainOverlayLayer or item.overlayLayer or "<nil>"),
                                tostring(item.terrainLayer or "<nil>"),
                                tostring(item.imageFilename or "<nil>"),
                                tostring(item.xmlFilename or item.filename or item.configFileName or "<nil>")
                            ))
                            if total <= 100 then
                                self:tpLogTableKeys(string.format("constructionItemKeys category=%s tab=%s item=%s", tostring(categoryIndex), tostring(tabIndex), tostring(itemIndex)), item, 24)
                            end
                        end
                    end
                end
            end
        end
    end

    tpLog("constructionStructure totalItems=" .. tostring(total))
end


function MapObjectFinder:tpFunctionSourceLabel(fn)
    if type(fn) ~= "function" or debug == nil or type(debug.getinfo) ~= "function" then
        return "<no-debug-info>"
    end
    local ok, info = pcall(function()
        return debug.getinfo(fn, "Sln")
    end)
    if ok ~= true or type(info) ~= "table" then
        return "<debug-error>"
    end
    return tostring(info.short_src or info.source or "?") .. ":" .. tostring(info.linedefined or "?")
end

function MapObjectFinder:tpCollectKeys(object, maxKeys)
    local keys = {}
    if type(object) == "table" then
        for key, _ in pairs(object) do
            table.insert(keys, tostring(key))
            if #keys >= (maxKeys or 80) then
                break
            end
        end
    end
    table.sort(keys)
    return table.concat(keys, ",")
end

function MapObjectFinder:tpLogRuntimeObject(label, object, maxKeys)
    tpLog(label .. " type=" .. tostring(type(object)) .. " value=" .. tostring(object))
    if type(object) == "table" then
        tpLog(label .. ".keys=" .. self:tpCollectKeys(object, maxKeys or 80))
        local mt = getmetatable(object)
        if mt ~= nil then
            tpLog(label .. ".metatable=" .. tostring(mt) .. " mtKeys=" .. self:tpCollectKeys(mt, maxKeys or 80))
            if type(mt.__index) == "table" then
                tpLog(label .. ".metatable.__indexKeys=" .. self:tpCollectKeys(mt.__index, maxKeys or 120))
            end
        end
    end
end

function MapObjectFinder:tpLogConstructionBrushRuntime(screen, context)
    tpLog("constructionBrushRuntimeStart context=" .. tostring(context or "?"))
    screen = screen or self:tpResolveConstructionLogicScreen()
    self:tpLogRuntimeObject("constructionScreenRuntime", screen, 120)

    local globals = {}
    for key, value in pairs(_G or {}) do
        local name = tostring(key)
        local lower = string.lower(name)
        if string.find(lower, "construction", 1, true) ~= nil
            and (string.find(lower, "brush", 1, true) ~= nil or string.find(lower, "foliage", 1, true) ~= nil or string.find(lower, "tree", 1, true) ~= nil) then
            table.insert(globals, name .. "=" .. tostring(type(value)))
        end
    end
    table.sort(globals)
    tpLog("constructionBrushGlobals " .. table.concat(globals, " ; "))

    local globalNames = {
        "ConstructionBrush",
        "ConstructionBrushPaint",
        "ConstructionBrushFoliage",
        "ConstructionBrushTree",
        "ConstructionBrushPlaceable",
        "ConstructionBrushTerrain"
    }
    for _, name in ipairs(globalNames) do
        local object = _G[name]
        if object ~= nil then
            self:tpLogRuntimeObject("constructionBrushClass." .. name, object, 160)
            if type(object) == "table" then
                for key, value in pairs(object) do
                    if type(value) == "function" then
                        tpLog("constructionBrushClassFunction class=" .. name .. " fn=" .. tostring(key) .. " source=" .. self:tpFunctionSourceLabel(value))
                    end
                end
            end
        end
    end

    if screen ~= nil then
        self:tpLogRuntimeObject("constructionScreen.brush", screen.brush, 160)
        self:tpLogRuntimeObject("constructionScreen.cursor", screen.cursor, 80)
        self:tpLogRuntimeObject("constructionScreen.itemList", screen.itemList, 80)
    end
    tpLog("constructionBrushRuntimeEnd context=" .. tostring(context or "?"))
end

function MapObjectFinder:tpLogFoliageMenuItemInternals(screen, context)
    tpLog("foliageMenuItemInternalsStart context=" .. tostring(context or "?"))
    screen = screen or self:tpResolveConstructionLogicScreen()
    if screen == nil or type(screen.items) ~= "table" then
        tpLog("foliageMenuItemInternals missingScreen")
        return
    end

    local count = 0
    for categoryIndex, categoryItems in pairs(screen.items) do
        if type(categoryItems) == "table" then
            for tabIndex, tabItems in pairs(categoryItems) do
                if type(tabItems) == "table" then
                    for itemIndex, item in ipairs(tabItems) do
                        local brushText = ""
                        if type(item) == "table" and type(item.brushParameters) == "table" then
                            brushText = table.concat(item.brushParameters, "|")
                        end
                        local lower = string.lower(brushText .. " " .. tostring(item and item.name or "") .. " " .. tostring(item and item.title or ""))
                        if type(item) == "table" and (string.find(lower, "bush", 1, true) or string.find(lower, "deco", 1, true) or string.find(lower, "foliage", 1, true) or string.find(lower, "meadow", 1, true)) then
                            count = count + 1
                            tpLog(string.format("foliageMenuInternal index=%s cat=%s tab=%s item=%s name=%s brush=%s terrainOverlay=%s terrainLayer=%s class=%s image=%s xml=%s",
                                tostring(count), tostring(categoryIndex), tostring(tabIndex), tostring(itemIndex), tostring(item.name or item.title or "<nil>"), tostring(brushText), tostring(item.terrainOverlayLayer or item.overlayLayer or "<nil>"), tostring(item.terrainLayer or "<nil>"), tostring(item.className or item.typeName or "<nil>"), tostring(item.imageFilename or "<nil>"), tostring(item.xmlFilename or item.filename or item.configFileName or "<nil>")
                            ))
                            self:tpLogRuntimeObject("foliageMenuInternal.item." .. tostring(count), item, 120)
                            if type(item.brushParameters) == "table" then
                                self:tpLogRuntimeObject("foliageMenuInternal.item." .. tostring(count) .. ".brushParameters", item.brushParameters, 40)
                            end
                            if type(item.storeItem) == "table" then
                                self:tpLogRuntimeObject("foliageMenuInternal.item." .. tostring(count) .. ".storeItem", item.storeItem, 120)
                                tpLog(string.format("foliageMenuStoreItemData index=%s name=%s brush=%s uniqueIndex=%s price=%s image=%s xml=%s rawXml=%s category=%s tab=%s species=%s shopHeight=%s",
                                    tostring(count),
                                    tostring(item.storeItem.name or item.name or item.title or "<nil>"),
                                    tostring(brushText),
                                    tostring(item.uniqueIndex or item.storeItem.uniqueIndex or "<nil>"),
                                    tostring(item.price or item.storeItem.price or "<nil>"),
                                    tostring(item.storeItem.imageFilename or item.imageFilename or "<nil>"),
                                    tostring(item.storeItem.xmlFilename or "<nil>"),
                                    tostring(item.storeItem.rawXMLFilename or "<nil>"),
                                    tostring(item.storeItem.categoryName or "<nil>"),
                                    tostring(type(item.storeItem.brush) == "table" and item.storeItem.brush.tab or "<nil>"),
                                    tostring(item.storeItem.species or "<nil>"),
                                    tostring(item.storeItem.shopHeight or "<nil>")
                                ))
                                if type(item.storeItem.brush) == "table" then
                                    self:tpLogRuntimeObject("foliageMenuInternal.item." .. tostring(count) .. ".storeItem.brush", item.storeItem.brush, 120)
                                    local params = item.storeItem.brush.parameters
                                    if type(params) == "table" then
                                        local paramParts = {}
                                        for paramIndex, paramValue in ipairs(params) do
                                            table.insert(paramParts, tostring(paramIndex) .. "=" .. tostring(paramValue) .. "(" .. type(paramValue) .. ")")
                                        end
                                        tpLog("foliageMenuStoreItemBrushParameters index=" .. tostring(count) .. " values=" .. table.concat(paramParts, ";"))
                                    else
                                        tpLog("foliageMenuStoreItemBrushParameters index=" .. tostring(count) .. " type=" .. tostring(type(params)) .. " value=" .. tostring(params))
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end
    tpLog("foliageMenuItemInternalsEnd count=" .. tostring(count))
end

function MapObjectFinder:tpExtractNibbleStatesFromDensity(rawValue)
    local states = {}
    local seen = {}
    local value = tonumber(rawValue)

    if value == nil or value <= 0 then
        return states
    end

    for shift = 0, 12, 4 do
        local divisor = 2 ^ shift
        local state = math.floor(value / divisor) % 16
        if state > 0 and seen[state] ~= true then
            seen[state] = true
            table.insert(states, state)
        end
    end

    table.sort(states)
    return states
end

function MapObjectFinder:tpCollectFoliageMenuCandidatesAtCurrentPick(screen)
    local x = self.lastPipetteWorldX
    local y = self.lastPipetteWorldY
    local z = self.lastPipetteWorldZ
    local foliageSystem = g_currentMission ~= nil and g_currentMission.foliageSystem or nil

    if x == nil or z == nil or type(foliageSystem) ~= "table" or screen == nil or type(screen.items) ~= "table" then
        return {}
    end

    local foliageItems = {}
    for categoryIndex, categoryItems in pairs(screen.items) do
        if type(categoryItems) == "table" then
            for tabIndex, tabItems in pairs(categoryItems) do
                if type(tabItems) == "table" then
                    for itemIndex, item in ipairs(tabItems) do
                        if type(item) == "table" and type(item.brushParameters) == "table" then
                            local brush = ""
                            local layerName = nil
                            local stateText = nil

                            if item.brushParameters[2] ~= nil then
                                layerName = tostring(item.brushParameters[1] or "")
                                stateText = tostring(item.brushParameters[2] or "")
                                brush = layerName .. "|" .. stateText
                            else
                                brush = tostring(item.brushParameters[1] or "")
                                layerName, stateText = string.match(brush, "^([^|]+)|([^|]+)$")
                            end

                            local state = tonumber(stateText)
                            if layerName ~= nil and layerName ~= "" and state ~= nil then
                                table.insert(foliageItems, {
                                    categoryIndex = categoryIndex,
                                    tabIndex = tabIndex,
                                    itemIndex = itemIndex,
                                    item = item,
                                    layerName = layerName,
                                    state = state,
                                    brush = brush,
                                    name = item.name or item.title or ""
                                })
                            end
                        end
                    end
                end
            end
        end
    end

    if TP_HEAVY_DIAGNOSTICS == true then
        tpLog("visualFoliageMappingProbeActive=true")

    local function tpSafeString(value)
        if value == nil then
            return "<nil>"
        end
        return tostring(value)
    end

    local function tpItemImage(item)
        if type(item) ~= "table" then
            return "<nil>"
        end
        return tpSafeString(item.imageFilename or item.image or item.iconFilename or item.storeImageFilename or item.filename or item.xmlFilename)
    end

    local loggedMenuCount = 0
    for _, candidate in ipairs(foliageItems) do
        local item = candidate.item
        local brushParams = ""
        if type(item) == "table" and type(item.brushParameters) == "table" then
            brushParams = table.concat(item.brushParameters, "|")
        end
        tpLog(string.format(
            "visualFoliageMenuCandidate index=%s order=%s/%s/%s name=%s layer=%s state=%s brush=%s brushParams=%s image=%s xml=%s filename=%s",
            tostring(loggedMenuCount + 1),
            tostring(candidate.categoryIndex or "<nil>"),
            tostring(candidate.tabIndex or "<nil>"),
            tostring(candidate.itemIndex or "<nil>"),
            tostring(candidate.name or "<nil>"),
            tostring(candidate.layerName or "<nil>"),
            tostring(candidate.state or "<nil>"),
            tostring(candidate.brush or "<nil>"),
            tostring(brushParams),
            tpSafeString(type(item) == "table" and item.imageFilename or nil),
            tpSafeString(type(item) == "table" and item.xmlFilename or nil),
            tpSafeString(type(item) == "table" and item.filename or nil)
        ))
        if type(item) == "table" and (string.find(string.lower(tostring(candidate.layerName or "")), "bush", 1, true) ~= nil or loggedMenuCount < 6) then
            self:tpLogTableKeys("visualFoliageMenuCandidateKeys order=" .. tostring(candidate.categoryIndex) .. "/" .. tostring(candidate.tabIndex) .. "/" .. tostring(candidate.itemIndex), item, 40)
            if type(item.storeItem) == "table" and type(item.storeItem.brush) == "table" then
                self:tpLogTableKeys("visualFoliageMenuCandidateStoreBrush order=" .. tostring(candidate.categoryIndex) .. "/" .. tostring(candidate.tabIndex) .. "/" .. tostring(candidate.itemIndex), item.storeItem.brush, 40)
                if type(item.storeItem.brush.parameters) == "table" then
                    local parameterParts = {}
                    for i, value in ipairs(item.storeItem.brush.parameters) do
                        table.insert(parameterParts, tostring(i) .. "=" .. tostring(value) .. "(" .. type(value) .. ")")
                    end
                    tpLog("visualFoliageMenuCandidateStoreBrushParameters order=" .. tostring(candidate.categoryIndex) .. "/" .. tostring(candidate.tabIndex) .. "/" .. tostring(candidate.itemIndex) .. " values=" .. table.concat(parameterParts, " ; "))
                end
            end
        end
        loggedMenuCount = loggedMenuCount + 1
        if loggedMenuCount >= 80 then
            break
        end
    end

    self:tpLogTableKeys("visualFoliageSystemKeys", foliageSystem, 60)

    local function logFoliageArray(label, array, maxItems)
        if type(array) ~= "table" then
            tpLog(label .. " type=" .. tostring(type(array)))
            return
        end
        local count = 0
        for index, entry in pairs(array) do
            count = count + 1
            local layerName = ""
            if type(entry) == "table" then
                layerName = tostring(entry.layerName or entry.foliageLayerName or entry.name or entry.xmlFilename or "")
            end
            tpLog(string.format(
                "%s index=%s layer=%s name=%s id=%s state=%s dataPlane=%s startChannel=%s numChannels=%s type=%s xml=%s filename=%s",
                label,
                tostring(index),
                tostring(layerName),
                tpSafeString(type(entry) == "table" and entry.name or nil),
                tpSafeString(type(entry) == "table" and entry.id or nil),
                tpSafeString(type(entry) == "table" and entry.state or nil),
                tpSafeString(type(entry) == "table" and entry.terrainDataPlaneId or nil),
                tpSafeString(type(entry) == "table" and entry.startStateChannel or entry.startChannel or nil),
                tpSafeString(type(entry) == "table" and entry.numStateChannels or entry.numChannels or nil),
                tpSafeString(type(entry) == "table" and entry.typeIndex or nil),
                tpSafeString(type(entry) == "table" and entry.xmlFilename or nil),
                tpSafeString(type(entry) == "table" and entry.filename or nil)
            ))
            if type(entry) == "table" then
                self:tpLogTableKeys(label .. "Keys index=" .. tostring(index), entry, 50)
            end
            if count >= (maxItems or 40) then
                break
            end
        end
        tpLog(label .. "CountLogged=" .. tostring(count))
    end

    logFoliageArray("visualPaintableFoliage", foliageSystem.paintableFoliages, 30)
    logFoliageArray("visualDecoFoliage", foliageSystem.decoFoliages, 60)
    logFoliageArray("visualDecoFoliageMapping", foliageSystem.decoFoliageMappings, 80)

    local transformLayerSeen = {}
    local function logTransformForLayer(layerName, source)
        layerName = tostring(layerName or "")
        if layerName == "" or transformLayerSeen[layerName] == true then
            return
        end
        transformLayerSeen[layerName] = true
        local groupId = nil
        if type(getFoliageTransformGroupIdByFoliageName) == "function" then
            local ok, value = pcall(function()
                return getFoliageTransformGroupIdByFoliageName(g_currentMission.terrainRootNode, layerName)
            end)
            if ok == true then
                groupId = value
            else
                groupId = "error:" .. tostring(value)
            end
        else
            groupId = "functionMissing"
        end
        local planeId = nil
        local typeIndex = nil
        if type(getTerrainDataPlaneByName) == "function" and g_currentMission ~= nil and g_currentMission.terrainRootNode ~= nil then
            local okPlane, planeValue, typeValue = pcall(function()
                return getTerrainDataPlaneByName(g_currentMission.terrainRootNode, layerName)
            end)
            if okPlane == true then
                planeId = tonumber(planeValue)
                typeIndex = tonumber(typeValue)
            end
        end

        local associatedGroupId = nil
        if planeId ~= nil and tonumber(planeId) ~= nil and tonumber(planeId) > 0 and type(getDataPlaneAssociatedTransformGroup) == "function" then
            local okAssoc, assocValue = pcall(function()
                return getDataPlaneAssociatedTransformGroup(planeId)
            end)
            if okAssoc == true then
                associatedGroupId = assocValue
            else
                associatedGroupId = "error:" .. tostring(assocValue)
            end
        elseif planeId ~= nil and tonumber(planeId) ~= nil and tonumber(planeId) <= 0 then
            associatedGroupId = "skippedInvalidPlane"
        end

        tpLog("visualFoliageTransformGroup source=" .. tostring(source or "?") .. " layer=" .. tostring(layerName) .. " groupId=" .. tostring(groupId) .. " planeId=" .. tostring(planeId) .. " typeIndex=" .. tostring(typeIndex) .. " associatedGroupId=" .. tostring(associatedGroupId))
    end

    for _, candidate in ipairs(foliageItems) do
        logTransformForLayer(candidate.layerName, "menu")
    end

    local function tpNodeName(nodeId)
        if nodeId == nil or tonumber(nodeId) == nil or tonumber(nodeId) <= 0 then
            return "<nil>"
        end
        if type(getName) ~= "function" then
            return "<getNameMissing>"
        end
        local ok, value = pcall(function()
            return getName(nodeId)
        end)
        if ok == true then
            return tostring(value)
        end
        return "error:" .. tostring(value)
    end

    local function tpChildCount(nodeId)
        if nodeId == nil or tonumber(nodeId) == nil or tonumber(nodeId) <= 0 then
            return 0
        end
        if type(getNumOfChildren) ~= "function" then
            return 0
        end
        local ok, value = pcall(function()
            return getNumOfChildren(nodeId)
        end)
        if ok == true and tonumber(value) ~= nil then
            return tonumber(value)
        end
        return 0
    end

    local function tpChildAt(nodeId, index)
        if nodeId == nil or tonumber(nodeId) == nil or tonumber(nodeId) <= 0 then
            return nil
        end
        if type(getChildAt) ~= "function" then
            return nil
        end
        local ok, value = pcall(function()
            return getChildAt(nodeId, index)
        end)
        if ok == true and tonumber(value) ~= nil then
            return tonumber(value)
        end
        return nil
    end

    local function tpLogNodeTree(rootNode, label, maxDepth, maxChildren)
        if rootNode == nil or tonumber(rootNode) == nil or tonumber(rootNode) <= 0 then
            tpLog("visualFoliageNodeTree label=" .. tostring(label) .. " root=" .. tostring(rootNode) .. " skipped=true")
            return
        end

        local visited = {}
        local function walk(nodeId, depth, path)
            if nodeId == nil or visited[nodeId] == true or depth > maxDepth then
                return
            end
            visited[nodeId] = true
            local count = tpChildCount(nodeId)
            tpLog("visualFoliageNodeTree label=" .. tostring(label) .. " depth=" .. tostring(depth) .. " path=" .. tostring(path) .. " node=" .. tostring(nodeId) .. " name=" .. tpNodeName(nodeId) .. " children=" .. tostring(count))
            local limit = math.min(count, maxChildren)
            for childIndex = 0, limit - 1 do
                local child = tpChildAt(nodeId, childIndex)
                if child ~= nil then
                    walk(child, depth + 1, tostring(path) .. "/" .. tostring(childIndex))
                end
            end
            if count > limit then
                tpLog("visualFoliageNodeTree label=" .. tostring(label) .. " depth=" .. tostring(depth) .. " path=" .. tostring(path) .. " childrenOmitted=" .. tostring(count - limit))
            end
        end
        walk(rootNode, 0, "root")
    end

    local function tpLogFoliageGroupHierarchy(layerName, label)
        if type(getFoliageTransformGroupIdByFoliageName) ~= "function" then
            tpLog("visualFoliageGroupHierarchy layer=" .. tostring(layerName) .. " label=" .. tostring(label) .. " skipped=getFoliageTransformGroupIdByFoliageNameMissing")
            return
        end
        local ok, groupId = pcall(function()
            return getFoliageTransformGroupIdByFoliageName(g_currentMission.terrainRootNode, layerName)
        end)
        if ok ~= true then
            tpLog("visualFoliageGroupHierarchy layer=" .. tostring(layerName) .. " label=" .. tostring(label) .. " error=" .. tostring(groupId))
            return
        end
        tpLog("visualFoliageGroupHierarchy layer=" .. tostring(layerName) .. " label=" .. tostring(label) .. " groupId=" .. tostring(groupId) .. " groupName=" .. tpNodeName(groupId) .. " childCount=" .. tostring(tpChildCount(groupId)))
        tpLogNodeTree(groupId, tostring(label) .. ":" .. tostring(layerName), 3, 24)
    end

    tpLogFoliageGroupHierarchy("decoBush", "activeVisualBushLayer")
    tpLogFoliageGroupHierarchy("decoBushUS", "menuBushLayer")
    if type(foliageSystem.paintableFoliages) == "table" then
        for _, entry in pairs(foliageSystem.paintableFoliages) do
            if type(entry) == "table" then
                logTransformForLayer(entry.layerName or entry.foliageLayerName or entry.name, "paintable")
            end
        end
    end
    if type(foliageSystem.decoFoliages) == "table" then
        for _, entry in pairs(foliageSystem.decoFoliages) do
            if type(entry) == "table" then
                logTransformForLayer(entry.layerName or entry.foliageLayerName or entry.name, "deco")
            end
        end
    end
    end

    local function resolvePlaneId(foliage)
        if type(foliage) ~= "table" then
            return nil
        end

        local planeId = tonumber(foliage.terrainDataPlaneId)
        if planeId ~= nil then
            return planeId
        end

        local layerName = tostring(foliage.layerName or foliage.foliageLayerName or foliage.name or "")
        if layerName ~= "" and type(getTerrainDataPlaneByName) == "function" and g_currentMission ~= nil and g_currentMission.terrainRootNode ~= nil then
            local okPlane, plane = pcall(function()
                return getTerrainDataPlaneByName(g_currentMission.terrainRootNode, layerName)
            end)
            if okPlane == true and tonumber(plane) ~= nil then
                return tonumber(plane)
            end
        end

        return nil
    end

    local function sampleDensity(planeId, sampleX, sampleZ)
        if type(getDensityAtWorldPos) ~= "function" or planeId == nil then
            return nil
        end

        local okDensity, density = pcall(function()
            return getDensityAtWorldPos(planeId, sampleX, y or 0, sampleZ)
        end)

        if okDensity == true then
            return tonumber(density)
        end

        return nil
    end

    local function sampleDensityFull(planeId, sampleX, sampleZ)
        if type(getDensityAtWorldPos) ~= "function" or planeId == nil then
            return nil, nil, nil
        end

        local density = nil
        local okDensity, densityValue = pcall(function()
            return getDensityAtWorldPos(planeId, sampleX, y or 0, sampleZ)
        end)
        if okDensity == true then
            density = tonumber(densityValue)
        end

        local state = nil
        if type(getDensityStatesAtWorldPos) == "function" then
            local okState, stateValue = pcall(function()
                return getDensityStatesAtWorldPos(planeId, sampleX, y or 0, sampleZ)
            end)
            if okState == true then
                state = tonumber(stateValue)
            end
        end

        local typeIndex = nil
        if type(getDensityTypeIndexAtWorldPos) == "function" then
            local okType, typeValue = pcall(function()
                return getDensityTypeIndexAtWorldPos(planeId, sampleX, y or 0, sampleZ)
            end)
            if okType == true then
                typeIndex = tonumber(typeValue)
            end
        end

        return density, state, typeIndex
    end

    local function resolvePlaneAndTypeByName(layerName)
        if layerName == nil or layerName == "" or type(getTerrainDataPlaneByName) ~= "function" or g_currentMission == nil or g_currentMission.terrainRootNode == nil then
            return nil, nil
        end

        local okPlane, planeId, typeIndex = pcall(function()
            return getTerrainDataPlaneByName(g_currentMission.terrainRootNode, layerName)
        end)

        if okPlane == true then
            return tonumber(planeId), tonumber(typeIndex)
        end

        return nil, nil
    end

    local layers = {}
    local function addLayer(foliage, source)
        if type(foliage) ~= "table" then
            return
        end

        local layerName = tostring(foliage.layerName or foliage.foliageLayerName or foliage.name or "")
        if layerName == "" then
            return
        end

        local planeId = resolvePlaneId(foliage)
        local byNamePlaneId, byNameTypeIndex = resolvePlaneAndTypeByName(layerName)
        if byNamePlaneId ~= nil then
            planeId = byNamePlaneId
        end
        if planeId == nil then
            return
        end

        layers[layerName] = layers[layerName] or { layerName = layerName, planeId = planeId, typeIndex = byNameTypeIndex, source = source, values = {}, states = {}, stateSet = {}, stateScore = {}, sampleLabels = {}, positiveSamples = 0, weightedScore = 0, primaryState = nil, primaryDensity = nil, typeMatchedSamples = 0, typeRejectedSamples = 0 }
    end

    if type(foliageSystem.paintableFoliages) == "table" then
        for _, foliage in ipairs(foliageSystem.paintableFoliages) do
            addLayer(foliage, "paintable")
        end
    end

    if type(foliageSystem.decoFoliages) == "table" then
        for _, foliage in ipairs(foliageSystem.decoFoliages) do
            addLayer(foliage, "deco")
        end
    end

    local offsets = {
        { label = "CENTER", dx = 0.00, dz = 0.00, weight = 18 }
    }

    local rawX = tonumber(self.tpLastRawSampleX)
    local rawZ = tonumber(self.tpLastRawSampleZ)
    if rawX ~= nil and rawZ ~= nil then
        local baseDx = rawX - x
        local baseDz = rawZ - z
        local function addRaw(label, dx, dz, weight)
            table.insert(offsets, { label = label, dx = baseDx + dx, dz = baseDz + dz, weight = weight })
        end

        addRaw("RAW", 0.00, 0.00, 10)

        local near = 0.10
        addRaw("RAW_N1", 0.00, -near, 7)
        addRaw("RAW_S1", 0.00,  near, 7)
        addRaw("RAW_E1",  near, 0.00, 7)
        addRaw("RAW_W1", -near, 0.00, 7)
        addRaw("RAW_NE1", near, -near, 5)
        addRaw("RAW_NW1", -near, -near, 5)
        addRaw("RAW_SE1", near, near, 5)
        addRaw("RAW_SW1", -near, near, 5)

        local mid = 0.24
        addRaw("RAW_N2", 0.00, -mid, 4)
        addRaw("RAW_S2", 0.00,  mid, 4)
        addRaw("RAW_E2",  mid, 0.00, 4)
        addRaw("RAW_W2", -mid, 0.00, 4)
        addRaw("RAW_NE2", mid, -mid, 3)
        addRaw("RAW_NW2", -mid, -mid, 3)
        addRaw("RAW_SE2", mid, mid, 3)
        addRaw("RAW_SW2", -mid, mid, 3)

        local wide = 0.38
        addRaw("RAW_N3", 0.00, -wide, 2)
        addRaw("RAW_S3", 0.00,  wide, 2)
        addRaw("RAW_E3",  wide, 0.00, 2)
        addRaw("RAW_W3", -wide, 0.00, 2)

        local scan1 = 0.55
        addRaw("SCAN_N1", 0.00, -scan1, 2)
        addRaw("SCAN_S1", 0.00,  scan1, 2)
        addRaw("SCAN_E1",  scan1, 0.00, 2)
        addRaw("SCAN_W1", -scan1, 0.00, 2)
        addRaw("SCAN_NE1", scan1, -scan1, 1)
        addRaw("SCAN_NW1", -scan1, -scan1, 1)
        addRaw("SCAN_SE1", scan1, scan1, 1)
        addRaw("SCAN_SW1", -scan1, scan1, 1)

        local scan2 = 0.85
        addRaw("SCAN_N2", 0.00, -scan2, 1)
        addRaw("SCAN_S2", 0.00,  scan2, 1)
        addRaw("SCAN_E2",  scan2, 0.00, 1)
        addRaw("SCAN_W2", -scan2, 0.00, 1)

        local scan3 = 1.15
        addRaw("SCAN_N3", 0.00, -scan3, 1)
        addRaw("SCAN_S3", 0.00,  scan3, 1)
        addRaw("SCAN_E3",  scan3, 0.00, 1)
        addRaw("SCAN_W3", -scan3, 0.00, 1)
        addRaw("SCAN_NE3", scan3, -scan3, 1)
        addRaw("SCAN_NW3", -scan3, -scan3, 1)
        addRaw("SCAN_SE3", scan3, scan3, 1)
        addRaw("SCAN_SW3", -scan3, scan3, 1)

        local scan4 = 1.45
        addRaw("SCAN_N4", 0.00, -scan4, 1)
        addRaw("SCAN_S4", 0.00,  scan4, 1)
        addRaw("SCAN_E4",  scan4, 0.00, 1)
        addRaw("SCAN_W4", -scan4, 0.00, 1)
    end

    local gridSignatureOffsets = {
        { label = "C", dx = 0.00, dz = 0.00 },
        { label = "N", dx = 0.00, dz = -0.50 },
        { label = "S", dx = 0.00, dz = 0.50 },
        { label = "E", dx = 0.50, dz = 0.00 },
        { label = "W", dx = -0.50, dz = 0.00 }
    }

    for _, layer in pairs(layers) do
        local signatureParts = {}
        layer.gridValues = {}
        for _, gridOffset in ipairs(gridSignatureOffsets) do
            local gridDensity = sampleDensity(layer.planeId, x + gridOffset.dx, z + gridOffset.dz)
            layer.gridValues[gridOffset.label] = tonumber(gridDensity or 0) or 0
            table.insert(signatureParts, tostring(gridOffset.label) .. "=" .. tostring(layer.gridValues[gridOffset.label]))
        end
        layer.gridSignature = table.concat(signatureParts, ";")
        tpLog(string.format(
            "foliageGridSignature layer=%s signature=%s",
            tostring(layer.layerName),
            tostring(layer.gridSignature or "<nil>")
        ))

        for offsetIndex, offset in ipairs(offsets) do
            local sampleX = x + offset.dx
            local sampleZ = z + offset.dz
            local density, sampleState, sampleType = sampleDensityFull(layer.planeId, sampleX, sampleZ)
            if tostring(offset.label or "") == "RAW" then
                layer.rawDensity = density
                layer.rawState = sampleState
                layer.rawType = sampleType
            elseif offsetIndex == 1 then
                layer.centerDensity = density
                layer.centerState = sampleState
                layer.centerType = sampleType
            end

            if density ~= nil and density > 0 then
                local typeIndex = tonumber(layer.typeIndex)
                local sampleTypeNum = tonumber(sampleType)
                local typeKnown = sampleTypeNum ~= nil and sampleTypeNum > 0
                local typeOk = true
                if typeIndex ~= nil and typeIndex >= 0 and typeKnown == true and sampleTypeNum ~= typeIndex then
                    typeOk = false
                end

                if typeOk == true then
                    if typeKnown == true and typeIndex ~= nil and typeIndex >= 0 and sampleTypeNum == typeIndex then
                        layer.typeMatchedSamples = (tonumber(layer.typeMatchedSamples) or 0) + 1
                    else
                        layer.typeUncheckedSamples = (tonumber(layer.typeUncheckedSamples) or 0) + 1
                    end
                    table.insert(layer.values, density)
                    layer.positiveSamples = (tonumber(layer.positiveSamples) or 0) + 1
                    layer.weightedScore = (tonumber(layer.weightedScore) or 0) + (tonumber(offset.weight) or 1)
                    table.insert(layer.sampleLabels, tostring(offset.label or offsetIndex) .. "=" .. tostring(density) .. "/state=" .. tostring(sampleState or "nil") .. "/type=" .. tostring(sampleType or "nil") .. "/typeMode=" .. (typeKnown and "checked" or "unchecked"))

                    if offsetIndex == 1 then
                        layer.primaryDensity = density
                    end

                    if sampleState ~= nil and sampleState > 0 then
                        layer.stateSet[sampleState] = true
                        layer.stateScore[sampleState] = (tonumber(layer.stateScore[sampleState]) or 0) + (tonumber(offset.weight) or 1)
                    else
                        local states = self:tpExtractNibbleStatesFromDensity(density)
                        for _, state in ipairs(states) do
                            layer.stateSet[state] = true
                            layer.stateScore[state] = (tonumber(layer.stateScore[state]) or 0) + (tonumber(offset.weight) or 1)
                        end
                    end
                else
                    layer.typeRejectedSamples = (tonumber(layer.typeRejectedSamples) or 0) + 1
                    table.insert(layer.sampleLabels, tostring(offset.label or offsetIndex) .. "=rejected:" .. tostring(density) .. "/state=" .. tostring(sampleState or "nil") .. "/type=" .. tostring(sampleType or "nil") .. "/expected=" .. tostring(typeIndex or "nil"))
                end
            end
        end

        local bestState = nil
        local bestScore = -1
        for state, score in pairs(layer.stateScore or {}) do
            local stateNum = tonumber(state)
            local scoreNum = tonumber(score) or 0
            if stateNum ~= nil and (scoreNum > bestScore or (scoreNum == bestScore and (bestState == nil or stateNum < bestState))) then
                bestState = stateNum
                bestScore = scoreNum
            end
        end
        layer.primaryState = bestState
        layer.primaryStateScore = bestScore
        layer.dominantStateSet = {}
        local dominantThreshold = math.max(1, (tonumber(bestScore) or 0) * 0.72)
        for state, score in pairs(layer.stateScore or {}) do
            if (tonumber(score) or 0) >= dominantThreshold then
                layer.dominantStateSet[tonumber(state)] = true
            end
        end

        local stateTexts = {}
        for state in pairs(layer.stateSet) do
            table.insert(stateTexts, tostring(state))
        end
        table.sort(stateTexts)
        tpLog(string.format(
            "foliageDecodedLayer layer=%s plane=%s typeIndex=%s values=%s states=%s primaryDensity=%s primaryState=%s primaryStateScore=%s positiveSamples=%s weightedScore=%s typeMatched=%s typeUnchecked=%s typeRejected=%s raw=%s/%s/%s center=%s/%s/%s samples=%s",
            tostring(layer.layerName),
            tostring(layer.planeId),
            tostring(layer.typeIndex or "<nil>"),
            table.concat(layer.values, ","),
            table.concat(stateTexts, ","),
            tostring(layer.primaryDensity or "<nil>"),
            tostring(layer.primaryState or "<nil>"),
            tostring(layer.primaryStateScore or "<nil>"),
            tostring(layer.positiveSamples or 0),
            tostring(layer.weightedScore or 0),
            tostring(layer.typeMatchedSamples or 0),
            tostring(layer.typeUncheckedSamples or 0),
            tostring(layer.typeRejectedSamples or 0),
            tostring(layer.rawDensity or "<nil>"),
            tostring(layer.rawState or "<nil>"),
            tostring(layer.rawType or "<nil>"),
            tostring(layer.centerDensity or "<nil>"),
            tostring(layer.centerState or "<nil>"),
            tostring(layer.centerType or "<nil>"),
            table.concat(layer.sampleLabels or {}, ";")
        ))
        local dominantTexts = {}
        for state in pairs(layer.dominantStateSet or {}) do
            table.insert(dominantTexts, tostring(state))
        end
        table.sort(dominantTexts)
        tpLog("foliageDominantStates layer=" .. tostring(layer.layerName) .. " states=" .. table.concat(dominantTexts, ",") .. " threshold=72%")
    end

    local grassMatches = {}
    local bushMatches = {}
    local allBushMenuCandidates = {}
    local allFoliageMenuCandidates = {}
    local otherMatches = {}
    local seen = {}

    local hasAnyBushDensity = false
    for layerName, layer in pairs(layers) do
        if string.find(string.lower(tostring(layerName or "")), "bush", 1, true) ~= nil and type(layer.values) == "table" and #layer.values > 0 then
            hasAnyBushDensity = true
            break
        end
    end

    if hasAnyBushDensity == true then
        local seenAllBush = {}
        local seenAllFoliage = {}
        for _, candidate in ipairs(foliageItems) do
            local keyAll = tostring(candidate.brush or "") .. "|" .. tostring(candidate.name or "")
            if seenAllFoliage[keyAll] ~= true then
                seenAllFoliage[keyAll] = true
                table.insert(allFoliageMenuCandidates, {
                    sourceItem = candidate.item,
                    layerName = candidate.layerName,
                    state = candidate.state,
                    brush = candidate.brush,
                    name = candidate.name,
                    categoryIndex = candidate.categoryIndex,
                    tabIndex = candidate.tabIndex,
                    itemIndex = candidate.itemIndex,
                    reviewAll = true,
                    reviewBroad = true
                })
            end

            if string.find(string.lower(tostring(candidate.layerName or "")), "bush", 1, true) ~= nil then
                local key = tostring(candidate.brush or "") .. "|" .. tostring(candidate.name or "")
                if seenAllBush[key] ~= true then
                    seenAllBush[key] = true
                    table.insert(allBushMenuCandidates, {
                        sourceItem = candidate.item,
                        layerName = candidate.layerName,
                        state = candidate.state,
                        brush = candidate.brush,
                        name = candidate.name,
                        categoryIndex = candidate.categoryIndex,
                        tabIndex = candidate.tabIndex,
                        itemIndex = candidate.itemIndex,
                        reviewAll = true
                    })
                end
            end
        end
    end

    for _, candidate in ipairs(foliageItems) do
        local layer = layers[candidate.layerName]
        local stateAllowed = layer ~= nil and layer.stateSet[candidate.state] == true
        if stateAllowed == true and layer.dominantStateSet ~= nil then
            stateAllowed = layer.dominantStateSet[candidate.state] == true
        end
        if layer ~= nil and stateAllowed == true then
            local key = candidate.brush .. "|" .. tostring(candidate.name)
            if seen[key] ~= true then
                seen[key] = true
                local match = {
                    sourceItem = candidate.item,
                    layerName = candidate.layerName,
                    state = candidate.state,
                    brush = candidate.brush,
                    name = candidate.name,
                    categoryIndex = candidate.categoryIndex,
                    tabIndex = candidate.tabIndex,
                    itemIndex = candidate.itemIndex,
                    stateScore = layer.stateScore ~= nil and tonumber(layer.stateScore[candidate.state]) or 0,
                    layerScore = tonumber(layer.weightedScore) or 0,
                    positiveSamples = tonumber(layer.positiveSamples) or 0
                }

                if candidate.layerName == "decoFoliage" or candidate.layerName == "meadow" then
                    table.insert(grassMatches, match)
                elseif string.find(string.lower(candidate.layerName), "bush", 1, true) ~= nil then
                    table.insert(bushMatches, match)
                else
                    table.insert(otherMatches, match)
                end
            end
        end
    end

    local exactMatchByLayer = {}
    local function markExactMatches(list)
        for _, match in ipairs(list or {}) do
            if match ~= nil and match.layerName ~= nil then
                exactMatchByLayer[tostring(match.layerName)] = true
            end
        end
    end
    markExactMatches(grassMatches)
    markExactMatches(bushMatches)
    markExactMatches(otherMatches)

    local function isBushLikeLayerName(layerName)
        local lowerName = string.lower(tostring(layerName or ""))
        return string.find(lowerName, "bush", 1, true) ~= nil
    end

    local positiveLayers = {}
    for layerName, layer in pairs(layers) do
        local positiveSamples = tonumber(layer.positiveSamples) or 0
        local weightedScore = tonumber(layer.weightedScore) or 0
        local typeMatched = tonumber(layer.typeMatchedSamples) or 0
        local typeUnchecked = tonumber(layer.typeUncheckedSamples) or 0
        local isUncheckedBushFootprint = isBushLikeLayerName(layerName) == true and typeMatched == 0 and typeUnchecked > 0 and weightedScore >= 4
        if positiveSamples > 0 and weightedScore >= 2 and (typeMatched > 0 or (typeUnchecked > 0 and exactMatchByLayer[tostring(layerName)] == true) or isUncheckedBushFootprint == true) then
            table.insert(positiveLayers, {
                layerName = tostring(layerName),
                weightedScore = weightedScore,
                positiveSamples = positiveSamples,
                typeMatched = typeMatched,
                typeUnchecked = typeUnchecked,
                uncheckedBushFootprint = isUncheckedBushFootprint
            })
        end
    end
    table.sort(positiveLayers, function(a, b)
        if tonumber(a.weightedScore or 0) ~= tonumber(b.weightedScore or 0) then
            return tonumber(a.weightedScore or 0) > tonumber(b.weightedScore or 0)
        end
        return tostring(a.layerName or "") < tostring(b.layerName or "")
    end)

    local layerReviewMatches = {}
    local layerReviewSeen = {}
    local unresolvedVisualLayers = {}

    local function tpDetectedStatesFromLayer(layer)
        local detected = {}
        local seenStates = {}

        local function addState(value)
            local state = tonumber(value)
            if state ~= nil and state > 0 and seenStates[state] ~= true then
                seenStates[state] = true
                table.insert(detected, state)
            end
        end

        if type(layer) == "table" and type(layer.stateScore) == "table" then
            for state, score in pairs(layer.stateScore) do
                if tonumber(score or 0) ~= nil and tonumber(score or 0) > 0 then
                    addState(state)
                end
            end
        end

        if #detected == 0 and type(layer) == "table" and type(layer.states) == "table" then
            for key, value in pairs(layer.states) do
                if value == true or (tonumber(value or 0) ~= nil and tonumber(value or 0) > 0) then
                    addState(key)
                    addState(value)
                end
            end
        end

        table.sort(detected, function(a, b)
            return tonumber(a or 0) < tonumber(b or 0)
        end)

        return detected
    end

    local function tpJoinNumbers(values, separator)
        if type(values) ~= "table" then
            return ""
        end

        local texts = {}
        for _, value in ipairs(values) do
            table.insert(texts, tostring(value))
        end

        return table.concat(texts, tostring(separator or ","))
    end

    local function addUnresolvedVisualLayer(layerName, reason)
        local layer = layers[layerName]
        if layer == nil then
            return
        end
        local key = tostring(layerName or "")
        if key ~= "" and unresolvedVisualLayers[key] == nil then
            unresolvedVisualLayers[key] = {
                layerName = key,
                reason = tostring(reason or "unknown"),
                weightedScore = tonumber(layer.weightedScore or 0) or 0,
                positiveSamples = tonumber(layer.positiveSamples or 0) or 0,
                states = tpJoinNumbers(tpDetectedStatesFromLayer(layer), ",")
            }
            tpLog("unmappedVisualFoliageLayer layer=" .. key .. " reason=" .. tostring(reason or "unknown") .. " positiveSamples=" .. tostring(layer.positiveSamples or 0) .. " weightedScore=" .. tostring(layer.weightedScore or 0) .. " states=" .. tostring(unresolvedVisualLayers[key].states))
        end
    end
    local function addLayerReviewCandidates(layerName)
        local layer = layers[layerName]
        if layer == nil then
            return
        end

        local added = 0
        for _, candidate in ipairs(foliageItems) do
            if tostring(candidate.layerName or "") == tostring(layerName or "") then
                local key = tostring(candidate.brush or "") .. "|" .. tostring(candidate.name or "")
                if seen[key] ~= true and layerReviewSeen[key] ~= true then
                    layerReviewSeen[key] = true
                    table.insert(layerReviewMatches, {
                        sourceItem = candidate.item,
                        layerName = candidate.layerName,
                        state = candidate.state,
                        brush = candidate.brush,
                        name = candidate.name,
                        categoryIndex = candidate.categoryIndex,
                        tabIndex = candidate.tabIndex,
                        itemIndex = candidate.itemIndex,
                        stateScore = layer.stateScore ~= nil and tonumber(layer.stateScore[candidate.state]) or 0,
                        layerScore = tonumber(layer.weightedScore) or 0,
                        positiveSamples = tonumber(layer.positiveSamples) or 0,
                        reviewBroad = true,
                        ambiguousFoliage = true,
                        layerReview = true
                    })
                    added = added + 1
                end
            end
        end

        if added == 0 and isBushLikeLayerName(layerName) == true and tonumber(layer.positiveSamples or 0) > 0 then
            addUnresolvedVisualLayer(layerName, "no_exact_menu_layer_match")
        end
    end

    for _, positiveLayer in ipairs(positiveLayers) do
        if positiveLayer ~= nil and exactMatchByLayer[tostring(positiveLayer.layerName or "")] ~= true then
            addLayerReviewCandidates(positiveLayer.layerName)
        end
    end

    local positiveLayerNames = {}
    for _, positiveLayer in ipairs(positiveLayers) do
        table.insert(positiveLayerNames, tostring(positiveLayer.layerName) .. ":" .. tostring(positiveLayer.positiveSamples) .. "/" .. tostring(positiveLayer.weightedScore))
    end
    local unresolvedVisualLayerCount = 0
    local unresolvedVisualBushCount = 0
    local unresolvedVisualTexts = {}
    for _, unresolvedLayer in pairs(unresolvedVisualLayers) do
        unresolvedVisualLayerCount = unresolvedVisualLayerCount + 1
        if isBushLikeLayerName(unresolvedLayer.layerName) == true then
            unresolvedVisualBushCount = unresolvedVisualBushCount + 1
        end
        table.insert(unresolvedVisualTexts, tostring(unresolvedLayer.layerName) .. ":" .. tostring(unresolvedLayer.positiveSamples) .. "/" .. tostring(unresolvedLayer.weightedScore) .. "/states=" .. tostring(unresolvedLayer.states))
    end
    tpLog("foliagePositiveLayerSummary count=" .. tostring(#positiveLayers) .. " layers=" .. table.concat(positiveLayerNames, ",") .. " exactLayers=" .. tostring((#grassMatches) + (#bushMatches) + (#otherMatches)) .. " reviewCandidates=" .. tostring(#layerReviewMatches) .. " unresolvedVisualLayers=" .. tostring(unresolvedVisualLayerCount) .. " unresolvedVisualBushLayers=" .. tostring(unresolvedVisualBushCount) .. " unresolved=" .. table.concat(unresolvedVisualTexts, ","))

    if unresolvedVisualBushCount > 0 then
        for _, unresolvedLayer in pairs(unresolvedVisualLayers) do
            if unresolvedLayer ~= nil and isBushLikeLayerName(unresolvedLayer.layerName) == true then
                local loggedBridgeCandidates = 0
                for _, candidate in ipairs(foliageItems) do
                    if candidate ~= nil and isBushLikeLayerName(candidate.layerName) == true then
                        loggedBridgeCandidates = loggedBridgeCandidates + 1
                        tpLog("unresolvedVisualBushBridgeCandidate visualLayer=" .. tostring(unresolvedLayer.layerName or "<nil>") .. " visualStates=" .. tostring(unresolvedLayer.states or "<nil>") .. " visualScore=" .. tostring(unresolvedLayer.weightedScore or 0) .. " menuLayer=" .. tostring(candidate.layerName or "<nil>") .. " menuState=" .. tostring(candidate.state or "<nil>") .. " menuName=" .. tostring(candidate.name or "<nil>") .. " sameLayer=" .. tostring(tostring(unresolvedLayer.layerName or "") == tostring(candidate.layerName or "")) .. " accepted=false")
                    end
                    if loggedBridgeCandidates >= 12 then
                        break
                    end
                end
                if loggedBridgeCandidates == 0 then
                    tpLog("unresolvedVisualBushBridgeCandidate visualLayer=" .. tostring(unresolvedLayer.layerName or "<nil>") .. " visualStates=" .. tostring(unresolvedLayer.states or "<nil>") .. " visualScore=" .. tostring(unresolvedLayer.weightedScore or 0) .. " menuLayer=<none> accepted=false")
                end
            end
        end
    end


    local decoGrassMatches = {}
    for _, match in ipairs(grassMatches) do
        if match ~= nil and tostring(match.layerName) == "decoFoliage" then
            local state = tonumber(match.state or 0)
            if state == 9 or state == 10 then
                table.insert(decoGrassMatches, match)
            end
        end
    end

    local strictBushMatches = {}
    for _, match in ipairs(bushMatches) do
        local layer = layers[match.layerName]
        local primaryState = layer ~= nil and tonumber(layer.primaryState) or nil
        if primaryState ~= nil and tonumber(match.state) == primaryState then
            table.insert(strictBushMatches, match)
        end
    end

    local function tpShallowCloneTable(source)
        local clone = {}
        if type(source) == "table" then
            for key, value in pairs(source) do
                if key ~= "tpPipetteOriginalDisplayName" and key ~= "tpPipetteDebugSuffix" and key ~= "tpPipetteConfirmLabel" then
                    if type(value) == "table" and key == "brushParameters" then
                        local copied = {}
                        for i, v in ipairs(value) do
                            copied[i] = v
                        end
                        clone[key] = copied
                    else
                        clone[key] = value
                    end
                end
            end
        end
        return clone
    end

    local function tpMapOnlyCloneTable(source, depth)
        depth = tonumber(depth) or 0
        if type(source) ~= "table" or depth > 3 then
            return source
        end
        local clone = {}
        for key, value in pairs(source) do
            if key ~= "tpPipetteOriginalDisplayName" and key ~= "tpPipetteDebugSuffix" and key ~= "tpPipetteConfirmLabel" then
                if type(value) == "table" then
                    clone[key] = tpMapOnlyCloneTable(value, depth + 1)
                else
                    clone[key] = value
                end
            end
        end
        return clone
    end

    local function tpFindMapFoliageTemplateItem()
        local fallback = nil
        for _, candidate in ipairs(foliageItems or {}) do
            if candidate ~= nil and type(candidate.item) == "table" then
                fallback = fallback or candidate.item
                if tostring(candidate.layerName or "") == "decoFoliage" then
                    return candidate.item, "decoFoliage"
                end
                if string.find(string.lower(tostring(candidate.layerName or "")), "bush", 1, true) ~= nil then
                    return candidate.item, tostring(candidate.layerName or "bush")
                end
            end
        end
        return fallback, fallback ~= nil and "fallback" or "none"
    end

    local function tpFindRuntimeFoliageDefinition(layerName)
        local foliageSystem = g_currentMission ~= nil and g_currentMission.foliageSystem or nil
        if type(foliageSystem) ~= "table" then
            return nil, "noFoliageSystem"
        end

        local function findInList(list, sourceName)
            if type(list) ~= "table" then
                return nil
            end
            for _, foliage in ipairs(list) do
                if type(foliage) == "table" then
                    local currentLayer = tostring(foliage.layerName or foliage.name or "")
                    if currentLayer == layerName then
                        return foliage, sourceName
                    end
                end
            end
            return nil
        end

        local foliage, source = findInList(foliageSystem.paintableFoliages, "paintableFoliages")
        if foliage ~= nil then
            return foliage, source
        end
        foliage, source = findInList(foliageSystem.decoFoliages, "decoFoliages")
        if foliage ~= nil then
            return foliage, source
        end

        return nil, "notFound"
    end

    local function tpEnsureMapFoliagePaintable(layerName)
        layerName = tostring(layerName or "")
        if layerName == "" then
            return false, "emptyLayer"
        end

        local foliageSystem = g_currentMission ~= nil and g_currentMission.foliageSystem or nil
        if type(foliageSystem) ~= "table" then
            tpLog("mapFoliagePaintableEnsure layer=" .. layerName .. " result=false reason=noFoliageSystem")
            return false, "noFoliageSystem"
        end

        local existingPaint = nil
        if type(foliageSystem.getFoliagePaintByName) == "function" then
            local ok, result = pcall(foliageSystem.getFoliagePaintByName, foliageSystem, layerName)
            if ok == true then
                existingPaint = result
            end
        end
        if existingPaint ~= nil then
            tpLog("mapFoliagePaintableEnsure layer=" .. layerName .. " result=true action=alreadyPaintable")
            return true, "alreadyPaintable"
        end

        if type(foliageSystem.paintableFoliages) ~= "table" then
            foliageSystem.paintableFoliages = {}
        end

        local sourceFoliage, sourceName = tpFindRuntimeFoliageDefinition(layerName)
        if type(sourceFoliage) ~= "table" then
            tpLog("mapFoliagePaintableEnsure layer=" .. layerName .. " result=false reason=noRuntimeDefinition source=" .. tostring(sourceName))
            return false, "noRuntimeDefinition"
        end

        local startStateChannel = tonumber(sourceFoliage.startStateChannel or sourceFoliage.startChannel or sourceFoliage.state)
        local numStateChannels = tonumber(sourceFoliage.numStateChannels or sourceFoliage.numChannels or sourceFoliage.numDensityMapChannels)
        if startStateChannel == nil or numStateChannels == nil then
            tpLog("mapFoliagePaintableEnsure layer=" .. layerName .. " result=false reason=missingStateChannels source=" .. tostring(sourceName) .. " start=" .. tostring(sourceFoliage.startStateChannel or sourceFoliage.startChannel or sourceFoliage.state) .. " num=" .. tostring(sourceFoliage.numStateChannels or sourceFoliage.numChannels or sourceFoliage.numDensityMapChannels))
            return false, "missingStateChannels"
        end

        local newPaint = {
            id = #foliageSystem.paintableFoliages + 1,
            layerName = layerName,
            startStateChannel = startStateChannel,
            numStateChannels = numStateChannels,
            state = startStateChannel
        }
        table.insert(foliageSystem.paintableFoliages, newPaint)

        local afterPaint = nil
        if type(foliageSystem.getFoliagePaintByName) == "function" then
            local ok, result = pcall(foliageSystem.getFoliagePaintByName, foliageSystem, layerName)
            if ok == true then
                afterPaint = result
            end
        end

        tpLog("mapFoliagePaintableEnsure layer=" .. layerName .. " result=true action=added source=" .. tostring(sourceName) .. " startStateChannel=" .. tostring(startStateChannel) .. " numStateChannels=" .. tostring(numStateChannels) .. " getAfter=" .. tostring(afterPaint ~= nil))
        return true, "added"
    end

    local function tpBuildMapOnlyFoliageItem(unresolvedLayer, state)
        local layerName = tostring(unresolvedLayer ~= nil and unresolvedLayer.layerName or "")
        local numericState = tonumber(state)
        if layerName == "" or numericState == nil or numericState <= 0 then
            return nil
        end

        local ensuredPaintable, ensureReason = tpEnsureMapFoliagePaintable(layerName)
        if ensuredPaintable ~= true then
            tpLog("mapFoliageItemSkipped layer=" .. layerName .. " state=" .. tostring(state) .. " reason=paintableEnsureFailed detail=" .. tostring(ensureReason))
            return nil
        end

        local template, templateLayer = tpFindMapFoliageTemplateItem()
        if type(template) ~= "table" then
            tpLog("mapFoliageItemSkipped layer=" .. layerName .. " state=" .. tostring(state) .. " reason=noTemplateItem")
            return nil
        end

        local item = tpMapOnlyCloneTable(template, 0)
        item.name = "Karten-Foliage: " .. layerName .. " | " .. tostring(numericState)
        item.title = item.name
        item.price = 0
        item.dailyUpkeep = 0
        item.brushParameters = { layerName, tostring(numericState) }
        item.tpMapOnlyFoliage = true
        item.tpMapOnlyFoliageLayer = layerName
        item.tpMapOnlyFoliageState = tostring(numericState)
        item.tpMapOnlyFoliageSourceStates = tostring(unresolvedLayer.states or "")
        item.tpPipetteDebugSuffix = " [Karten-Foliage]"

        if type(item.storeItem) == "table" then
            item.storeItem.name = item.name
            item.storeItem.price = 0
            if type(item.storeItem.brush) == "table" then
                item.storeItem.brush.parameters = { layerName, tostring(numericState) }
            end
        end
        return item
    end

    local function buildUnresolvedVisualBushReviewMatches()
        local reviewMatches = {}

        local function logUnsupportedVisualLayer(unresolvedLayer)
            if unresolvedLayer == nil then
                return
            end
            local visualLayerName = tostring(unresolvedLayer.layerName or "")
            if visualLayerName == "" then
                return
            end

            local exactMenuItems = 0
            local sameLayerStates = {}
            local menuBushLayers = {}
            local seenMenuBushLayers = {}
            for _, candidate in ipairs(allBushMenuCandidates or {}) do
                if candidate ~= nil then
                    local candidateLayer = tostring(candidate.layerName or "")
                    if candidateLayer ~= "" and seenMenuBushLayers[candidateLayer] ~= true then
                        seenMenuBushLayers[candidateLayer] = true
                        table.insert(menuBushLayers, candidateLayer)
                    end
                    if candidateLayer == visualLayerName then
                        exactMenuItems = exactMenuItems + 1
                        table.insert(sameLayerStates, tostring(candidate.state or "<nil>"))
                    end
                end
            end

            local exactFoliageItems = 0
            for _, candidate in ipairs(foliageItems or {}) do
                if candidate ~= nil and tostring(candidate.layerName or "") == visualLayerName then
                    exactFoliageItems = exactFoliageItems + 1
                end
            end

            local decision = "map_only_visual_foliage_not_directly_paintable"
            tpLog("visibleBushSupportCheck visualLayer=" .. visualLayerName .. " visualStates=" .. tostring(unresolvedLayer.states or "<nil>") .. " visualScore=" .. tostring(unresolvedLayer.weightedScore or 0) .. " exactMenuItems=" .. tostring(exactMenuItems) .. " exactFoliageItems=" .. tostring(exactFoliageItems) .. " sameLayerStates=" .. table.concat(sameLayerStates, ",") .. " availableBushMenuLayers=" .. table.concat(menuBushLayers, ",") .. " decision=" .. decision)
            tpLog("mapOnlyVisualFoliageFound layer=" .. visualLayerName .. " states=" .. tostring(unresolvedLayer.states or "<nil>") .. " score=" .. tostring(unresolvedLayer.weightedScore or 0) .. " menuLayerMatch=false paintableByConstruction=false nextStep=inspect_map_foliage_definition")
            self.tpMapOnlyFoliageMarker = {
                x = self.lastPipetteWorldX,
                y = self.lastPipetteWorldY,
                z = self.lastPipetteWorldZ,
                layer = visualLayerName,
                states = tostring(unresolvedLayer.states or "?"),
                score = tonumber(unresolvedLayer.weightedScore or 0),
                expiresAt = (getTimeSec ~= nil and getTimeSec() or 0) + 20
            }
            tpLog("mapOnlyVisualMarkerCreated layer=" .. visualLayerName .. " states=" .. tostring(unresolvedLayer.states or "<nil>") .. " duration=20")

            tpLog("visibleBushSyntheticSuppressed visualLayer=" .. visualLayerName .. " reason=density_state_is_not_brush_parameter_and_no_exact_construction_menu_layer")
            tpShowMessage(string.format(tpText("TP_msg_mapOnlyFoliage", "Map foliage found: %s"), tostring(visualLayerName or "?")))
        end

        local function addMapOnlyFoliageItems(unresolvedLayer)
            if unresolvedLayer == nil then
                return
            end
            local states = {}
            local seenStates = {}
            for stateText in string.gmatch(tostring(unresolvedLayer.states or ""), "[^,]+") do
                local state = tonumber(stateText)
                if state ~= nil and state > 0 and seenStates[state] ~= true then
                    seenStates[state] = true
                    table.insert(states, state)
                end
            end
            table.sort(states)
            if #states == 0 then
                local fallbackState = tonumber(unresolvedLayer.primaryState or 0)
                if fallbackState ~= nil and fallbackState > 0 then
                    table.insert(states, fallbackState)
                end
            end
            if #states > 2 then
                local limited = { states[1], states[2] }
                states = limited
            end

            for _, state in ipairs(states) do
                local item = tpBuildMapOnlyFoliageItem(unresolvedLayer, state)
                if item ~= nil then
                    table.insert(reviewMatches, {
                        sourceItem = item,
                        layerName = tostring(unresolvedLayer.layerName or ""),
                        state = tonumber(state),
                        brush = tostring(unresolvedLayer.layerName or "") .. "|" .. tostring(state),
                        name = tostring(item.name or "Karten-Foliage"),
                        layerScore = tonumber(unresolvedLayer.weightedScore or 0) or 0,
                        positiveSamples = tonumber(unresolvedLayer.positiveSamples or 0) or 0,
                        mapOnlyFoliage = true
                    })
                end
            end
        end

        for _, unresolvedLayer in pairs(unresolvedVisualLayers or {}) do
            if unresolvedLayer ~= nil and isBushLikeLayerName(unresolvedLayer.layerName) == true then
                logUnsupportedVisualLayer(unresolvedLayer)
                if TP_MAP_ONLY_FOLIAGE_RESULT_ITEMS == true then
                    addMapOnlyFoliageItems(unresolvedLayer)
                else
                    tpLog("mapOnlyVisualFoliageResultSuppressed layer=" .. tostring(unresolvedLayer.layerName or "") .. " reason=conservativeModMapCleanup")
                end
            end
        end

        return reviewMatches
    end

    local unresolvedVisualBushReviewMatches = {}
    if unresolvedVisualBushCount > 0 then
        unresolvedVisualBushReviewMatches = buildUnresolvedVisualBushReviewMatches()
    end
    tpLog("nearbyVisibleFootprintScanActive=true searchRing=0.55/0.85 weights=2/1 unresolvedVisualBushReviewCandidates=" .. tostring(#unresolvedVisualBushReviewMatches))

    local bushStateOneMatches = {}
    for _, match in ipairs(bushMatches) do
        if tonumber(match.state or 0) == 1 then
            table.insert(bushStateOneMatches, match)
        end
    end

    local selected = {}
    local exactMatchCount = (#grassMatches) + (#bushMatches) + (#otherMatches)
    local mixedLayerReviewMode = (#positiveLayers > 1 and (exactMatchCount > 1 or #layerReviewMatches > 0)) or (exactMatchCount == 0 and #layerReviewMatches > 0)
    if unresolvedVisualBushCount > 0 and exactMatchCount == 0 and #layerReviewMatches == 0 then
        selected = unresolvedVisualBushReviewMatches
        self.tpLastFoliageRecognitionFallback = (#selected == 0)
        tpLog("foliageSelectionMode=unmappedVisualBushOnlyMapFoliageProbe unresolvedVisualBushLayers=" .. tostring(unresolvedVisualBushCount) .. " exact=" .. tostring(exactMatchCount) .. " selected=" .. tostring(#selected) .. " mapFoliageTestItems=" .. tostring(#unresolvedVisualBushReviewMatches) .. " review=" .. tostring(#layerReviewMatches))
    elseif unresolvedVisualBushCount > 0 then
        local selectedSeen = {}
        local function addSelected(list)
            for _, match in ipairs(list or {}) do
                if match ~= nil then
                    local key = tostring(match.brush or "") .. "|" .. tostring(match.name or "")
                    if selectedSeen[key] ~= true then
                        selectedSeen[key] = true
                        table.insert(selected, match)
                    end
                end
            end
        end
        addSelected(grassMatches)
        addSelected(bushMatches)
        addSelected(otherMatches)
        addSelected(unresolvedVisualBushReviewMatches)
        self.tpLastFoliageRecognitionFallback = false
        tpLog("foliageSelectionMode=unmappedVisualBushSupportedOnly unresolvedVisualBushLayers=" .. tostring(unresolvedVisualBushCount) .. " exact=" .. tostring(exactMatchCount) .. " selected=" .. tostring(#selected) .. " mapFoliageTestItems=" .. tostring(#unresolvedVisualBushReviewMatches) .. " reviewSuppressed=" .. tostring(#layerReviewMatches))
    elseif mixedLayerReviewMode == true then
        local selectedSeen = {}
        local function addSelected(list)
            for _, match in ipairs(list or {}) do
                if match ~= nil then
                    local key = tostring(match.brush or "") .. "|" .. tostring(match.name or "")
                    if selectedSeen[key] ~= true then
                        selectedSeen[key] = true
                        if match.layerReview == true then
                            match.ambiguousFoliage = true
                        end
                        table.insert(selected, match)
                    end
                end
            end
        end
        addSelected(grassMatches)
        addSelected(bushMatches)
        addSelected(otherMatches)
        addSelected(layerReviewMatches)
        tpLog("foliageSelectionMode=mixedFoliageMultiLayerExactAndReview uncheckedBushReviewActive=true positiveLayers=" .. tostring(#positiveLayers) .. " exact=" .. tostring(exactMatchCount) .. " review=" .. tostring(#layerReviewMatches))
    elseif #decoGrassMatches > 0 then
        selected = decoGrassMatches
        tpLog("foliageSelectionMode=strictDecoGrassState")
    elseif #allBushMenuCandidates > 0 then
        selected = allBushMenuCandidates

        local primaryBushDensity = nil
        local primaryBushState = nil
        for layerName, layer in pairs(layers) do
            if string.find(string.lower(tostring(layerName or "")), "bush", 1, true) ~= nil and layer.primaryDensity ~= nil then
                primaryBushDensity = tonumber(layer.primaryDensity)
                primaryBushState = tonumber(layer.primaryState)
                break
            end
        end

        local trustedBushState = nil

        if trustedBushState ~= nil then
            local trusted = {}
            for _, match in ipairs(allBushMenuCandidates) do
                if tonumber(match.state or -1) == trustedBushState then
                    table.insert(trusted, match)
                end
            end

            if #trusted > 0 then
                selected = trusted
                tpLog("foliageSelectionMode=bushTrustedState density=" .. tostring(primaryBushDensity) .. " rawState=" .. tostring(primaryBushState) .. " trustedState=" .. tostring(trustedBushState))
            else
                selected = {}
                tpLog("foliageSelectionMode=bushTrustedStateMissing density=" .. tostring(primaryBushDensity) .. " rawState=" .. tostring(primaryBushState) .. " trustedState=" .. tostring(trustedBushState))
            end
        else
            local ambiguousFoliage = {}
            local ambiguousSeen = {}

            local grassGridSignatures = {}
            for _, match in ipairs(grassMatches or {}) do
                local layer = layers[match.layerName]
                if layer ~= nil and layer.gridSignature ~= nil then
                    grassGridSignatures[tostring(layer.gridSignature)] = true
                end
            end

            local suppressedBySharedGrid = 0
            local function shouldKeepAmbiguous(match)
                if match == nil then
                    return false
                end
                local layerName = tostring(match.layerName or "")
                if #grassMatches > 0 and string.find(string.lower(layerName), "bush", 1, true) ~= nil then
                    local layer = layers[layerName]
                    if layer ~= nil and layer.gridSignature ~= nil and grassGridSignatures[tostring(layer.gridSignature)] == true then
                        suppressedBySharedGrid = suppressedBySharedGrid + 1
                        return false
                    end
                end
                return true
            end

            local function addAmbiguous(list)
                for _, match in ipairs(list or {}) do
                    if shouldKeepAmbiguous(match) == true then
                        local key = tostring(match.brush or "") .. "|" .. tostring(match.name or "")
                        if ambiguousSeen[key] ~= true then
                            ambiguousSeen[key] = true
                            match.ambiguousFoliage = true
                            table.insert(ambiguousFoliage, match)
                        end
                    end
                end
            end

            addAmbiguous(grassMatches)
            addAmbiguous(otherMatches)
            addAmbiguous(bushMatches)

            local hasBushAmbiguity = #bushMatches > 0 and suppressedBySharedGrid > 0
            local hasGrassAmbiguity = #grassMatches > 0
            if hasBushAmbiguity == true and hasGrassAmbiguity == true then
                self.tpLastFoliageRecognitionFallback = false
                selected = {}
                for _, match in ipairs(bushMatches or {}) do
                    if match ~= nil then
                        match.ambiguousFoliage = true
                        table.insert(selected, match)
                    end
                end
                tpLog("foliageSelectionMode=sharedSignatureBushCandidatePriority density=" .. tostring(primaryBushDensity) .. " rawState=" .. tostring(primaryBushState) .. " grassMatches=" .. tostring(#grassMatches) .. " bushMatches=" .. tostring(#bushMatches) .. " selected=" .. tostring(#selected) .. " suppressedSharedGrid=" .. tostring(suppressedBySharedGrid))
            else
                self.tpLastFoliageRecognitionFallback = false
                selected = ambiguousFoliage
                tpLog("foliageSelectionMode=ambiguousFoliageOnlyGridFiltered density=" .. tostring(primaryBushDensity) .. " rawState=" .. tostring(primaryBushState) .. " candidates=" .. tostring(#selected) .. " suppressedSharedGrid=" .. tostring(suppressedBySharedGrid))
            end
        end
    elseif #bushMatches > 0 then
        selected = bushMatches
        tpLog("foliageSelectionMode=bushStateReviewAllDetectedStates")
    elseif #grassMatches > 0 then
        selected = grassMatches
        tpLog("foliageSelectionMode=grassFallback")
    else
        selected = otherMatches
        tpLog("foliageSelectionMode=otherFallback")
    end


    local function tpAddStrongVisibleLayerCandidates()
        local selectedSeen = {}
        for _, match in ipairs(selected or {}) do
            if match ~= nil then
                selectedSeen[tostring(match.brush or "") .. "|" .. tostring(match.name or "")] = true
            end
        end

        local bestLayerScore = 0
        for _, positiveLayer in ipairs(positiveLayers or {}) do
            bestLayerScore = math.max(bestLayerScore, tonumber(positiveLayer.weightedScore or 0) or 0)
        end
        if bestLayerScore <= 0 then
            return 0
        end

        local added = 0
        local maxAdditional = 3
        local minScore = math.max(4, bestLayerScore * 0.25)

        for _, positiveLayer in ipairs(positiveLayers or {}) do
            if added >= maxAdditional then
                break
            end

            local layerName = tostring(positiveLayer.layerName or "")
            local layer = layers[layerName]
            local layerScore = tonumber(positiveLayer.weightedScore or 0) or 0
            if layer ~= nil and layerScore >= minScore then
                local perLayerAdded = 0
                local layerCandidates = {}
                for _, candidate in ipairs(foliageItems or {}) do
                    if tostring(candidate.layerName or "") == layerName then
                        local state = tonumber(candidate.state)
                        local stateScore = layer.stateScore ~= nil and tonumber(layer.stateScore[state] or 0) or 0
                        local isDominant = layer.dominantStateSet ~= nil and layer.dominantStateSet[state] == true
                        local isPrimary = tonumber(layer.primaryState or -1) == state
                        if state ~= nil and (isDominant == true or isPrimary == true or stateScore >= math.max(1, (tonumber(layer.primaryStateScore or 0) or 0) * 0.55)) then
                            table.insert(layerCandidates, {
                                sourceItem = candidate.item,
                                layerName = candidate.layerName,
                                state = candidate.state,
                                brush = candidate.brush,
                                name = candidate.name,
                                categoryIndex = candidate.categoryIndex,
                                tabIndex = candidate.tabIndex,
                                itemIndex = candidate.itemIndex,
                                stateScore = stateScore,
                                layerScore = layerScore,
                                positiveSamples = tonumber(layer.positiveSamples) or 0,
                                balancedSupplement = true
                            })
                        end
                    end
                end

                table.sort(layerCandidates, function(a, b)
                    local as = tonumber(a.stateScore or 0) or 0
                    local bs = tonumber(b.stateScore or 0) or 0
                    if as ~= bs then return as > bs end
                    return tonumber(a.state or 0) < tonumber(b.state or 0)
                end)

                for _, match in ipairs(layerCandidates) do
                    if added >= maxAdditional or perLayerAdded >= 2 then
                        break
                    end
                    local key = tostring(match.brush or "") .. "|" .. tostring(match.name or "")
                    if selectedSeen[key] ~= true then
                        selectedSeen[key] = true
                        table.insert(selected, match)
                        added = added + 1
                        perLayerAdded = perLayerAdded + 1
                    end
                end
            end
        end

        if added > 0 then
            tpLog("balancedFoliageSupplement added=" .. tostring(added) .. " bestLayerScore=" .. tostring(bestLayerScore) .. " minScore=" .. tostring(minScore))
        end
        return added
    end

    tpAddStrongVisibleLayerCandidates()


    tpLog("foliagePrimaryPriorityActive=true selected=" .. tostring(#selected))
    if mixedLayerReviewMode == true then
        tpLog("mixedFoliageScoreSortActive=true centerCellPriorityActive=true selected=" .. tostring(#selected))
    end

    table.sort(selected, function(a, b)
        if mixedLayerReviewMode == true and a ~= nil and b ~= nil then
            local aLayerScore = tonumber(a.layerScore or 0) or 0
            local bLayerScore = tonumber(b.layerScore or 0) or 0
            if aLayerScore ~= bLayerScore then
                return aLayerScore > bLayerScore
            end
            local aStateScore = tonumber(a.stateScore or 0) or 0
            local bStateScore = tonumber(b.stateScore or 0) or 0
            if aStateScore ~= bStateScore then
                return aStateScore > bStateScore
            end
            local aSamples = tonumber(a.positiveSamples or 0) or 0
            local bSamples = tonumber(b.positiveSamples or 0) or 0
            if aSamples ~= bSamples then
                return aSamples > bSamples
            end
            local ac = tonumber(a.categoryIndex or 9999) or 9999
            local bc = tonumber(b.categoryIndex or 9999) or 9999
            if ac ~= bc then return ac < bc end
            local at = tonumber(a.tabIndex or 9999) or 9999
            local bt = tonumber(b.tabIndex or 9999) or 9999
            if at ~= bt then return at < bt end
            local ai = tonumber(a.itemIndex or 9999) or 9999
            local bi = tonumber(b.itemIndex or 9999) or 9999
            return ai < bi
        end

        if a ~= nil and b ~= nil and (a.ambiguousFoliage == true or b.ambiguousFoliage == true) then
            local aLayerScore = tonumber(a.layerScore or 0) or 0
            local bLayerScore = tonumber(b.layerScore or 0) or 0
            if aLayerScore ~= bLayerScore then
                return aLayerScore > bLayerScore
            end
            local aStateScore = tonumber(a.stateScore or 0) or 0
            local bStateScore = tonumber(b.stateScore or 0) or 0
            if aStateScore ~= bStateScore then
                return aStateScore > bStateScore
            end

            if tostring(a.layerName) == tostring(b.layerName) then
                local layer = layers[a.layerName]
                local primaryState = layer ~= nil and tonumber(layer.primaryState) or nil
                if primaryState ~= nil then
                    local aPrimary = tonumber(a.state or -1) == primaryState
                    local bPrimary = tonumber(b.state or -1) == primaryState
                    if aPrimary ~= bPrimary then
                        return aPrimary == true
                    end
                end
            end

            local ac = tonumber(a.categoryIndex or 9999) or 9999
            local bc = tonumber(b.categoryIndex or 9999) or 9999
            if ac ~= bc then return ac < bc end
            local at = tonumber(a.tabIndex or 9999) or 9999
            local bt = tonumber(b.tabIndex or 9999) or 9999
            if at ~= bt then return at < bt end
            local ai = tonumber(a.itemIndex or 9999) or 9999
            local bi = tonumber(b.itemIndex or 9999) or 9999
            return ai < bi
        end

        if tostring(a.layerName) == tostring(b.layerName) then
            local aLayer = layers[a.layerName]
            local bLayer = layers[b.layerName]
            local aPrimary = aLayer ~= nil and tonumber(aLayer.primaryState) == tonumber(a.state or -1)
            local bPrimary = bLayer ~= nil and tonumber(bLayer.primaryState) == tonumber(b.state or -1)
            if aPrimary ~= bPrimary then
                return aPrimary == true
            end
            return tonumber(a.state or 0) < tonumber(b.state or 0)
        end
        return tostring(a.layerName) < tostring(b.layerName)
    end)

    if #selected > 0 then
        local limited = {}
        local perLayer = {}
        for _, match in ipairs(selected) do
            local layerName = tostring(match ~= nil and match.layerName or "")
            perLayer[layerName] = tonumber(perLayer[layerName] or 0) or 0
            if perLayer[layerName] < 3 and #limited < 8 then
                table.insert(limited, match)
                perLayer[layerName] = perLayer[layerName] + 1
            end
        end
        if #limited ~= #selected then
            tpLog("balancedFoliageDisplayLimit before=" .. tostring(#selected) .. " after=" .. tostring(#limited) .. " maxTotal=8 maxPerLayer=3")
        end
        selected = limited
    end


    for _, match in ipairs(selected) do
        if match ~= nil and match.sourceItem ~= nil then
            if match.mapOnlyFoliage == true then
                match.sourceItem.tpPipetteDebugSuffix = ""
            elseif match.ambiguousFoliage == true then
                local imageName = ""
                if match.sourceItem ~= nil and match.sourceItem.imageFilename ~= nil then
                    imageName = tostring(match.sourceItem.imageFilename)
                    imageName = string.match(imageName, "([^/\]+)%.%w+$") or imageName
                    imageName = " | " .. imageName
                end
                match.sourceItem.tpPipetteDebugSuffix = " [Foliage | " .. tostring(match.layerName or "?") .. " | State " .. tostring(match.state or "?") .. imageName .. "]"
            elseif string.find(string.lower(tostring(match.layerName or "")), "bush", 1, true) ~= nil then
                local layer = layers[match.layerName]
                local isPrimary = layer ~= nil and tonumber(layer.primaryState) == tonumber(match.state or -1)
                local imageName = ""
                if match.sourceItem ~= nil and match.sourceItem.imageFilename ~= nil then
                    imageName = tostring(match.sourceItem.imageFilename)
                    imageName = string.match(imageName, "([^/\\]+)%.%w+$") or imageName
                    imageName = " | " .. imageName
                end
                if isPrimary then
                    match.sourceItem.tpPipetteDebugSuffix = " [State " .. tostring(match.state or "?") .. " | direkt" .. imageName .. "]"
                else
                    match.sourceItem.tpPipetteDebugSuffix = " [State " .. tostring(match.state or "?") .. imageName .. "]"
                end
            elseif match.reviewBroad == true then
                match.sourceItem.tpPipetteDebugSuffix = " [" .. tostring(match.layerName or "?") .. " | State " .. tostring(match.state or "?") .. "]"
            else
                match.sourceItem.tpPipetteDebugSuffix = nil
            end
        end
    end

    local filteredSelected = {}
    local suppressedUnsafeFallback = 0
    for _, match in ipairs(selected or {}) do
        local layerName = string.lower(tostring(match ~= nil and match.layerName or ""))
        local matchName = string.lower(tostring(match ~= nil and match.name or ""))
        local imageName = string.lower(tostring(match ~= nil and match.sourceItem ~= nil and match.sourceItem.imageFilename or ""))
        local isCommonFallback = string.find(matchName, "common02", 1, true) ~= nil or string.find(imageName, "common02", 1, true) ~= nil
        local isBushLayer = string.find(layerName, "bush", 1, true) ~= nil
        if isBushLayer == true and isCommonFallback == true then
            suppressedUnsafeFallback = suppressedUnsafeFallback + 1
            tpLog("foliageUnsafeFallbackSuppressed layer=" .. tostring(match.layerName or "") .. " name=" .. tostring(match.name or "") .. " reason=common02StaticObjectFalsePositive")
        else
            table.insert(filteredSelected, match)
        end
    end
    if suppressedUnsafeFallback > 0 then
        selected = filteredSelected
        self.tpLastFoliageRecognitionFallback = (#selected == 0)
        tpLog("foliageUnsafeFallbackSuppressedCount=" .. tostring(suppressedUnsafeFallback) .. " remaining=" .. tostring(#selected))
    end

    tpLog("foliageResultCandidates=" .. tostring(#selected))
    for index, match in ipairs(selected) do
        if index > 12 then
            break
        end
        tpLog(string.format(
            "foliageResultCandidate index=%s name=%s brush=%s layer=%s state=%s order=%s/%s/%s image=%s",
            tostring(index),
            tostring(match.name or "<nil>"),
            tostring(match.brush or "<nil>"),
            tostring(match.layerName or "<nil>"),
            tostring(match.state or "<nil>"),
            tostring(match.categoryIndex or "<nil>"),
            tostring(match.tabIndex or "<nil>"),
            tostring(match.itemIndex or "<nil>"),
            tostring(match.sourceItem ~= nil and match.sourceItem.imageFilename or "<nil>")
        ))
        if match.syntheticVisualBush == true or string.find(string.lower(tostring(match.name or "")), "busch", 1, true) ~= nil then
            self:tpLogCandidateDeep("selectedFoliageCandidateDeep index=" .. tostring(index), match.sourceItem, 80)
            if match.templateSourceItem ~= nil then
                self:tpLogCandidateDeep("selectedFoliageCandidateTemplateDeep index=" .. tostring(index), match.templateSourceItem, 80)
            end
        end
    end

    return selected
end


function MapObjectFinder:tpFormatTraceValue(value)
    if value == nil then
        return "<nil>"
    end

    local valueType = type(value)
    if valueType == "number" or valueType == "boolean" or valueType == "string" then
        return tostring(value)
    end

    return valueType
end

function MapObjectFinder:tpSafeCallTrace(functionName, ...)
    local fn = _G[functionName]
    if type(fn) ~= "function" then
        return false, "functionMissing"
    end

    local args = {...}
    local results = {pcall(function()
        return fn(unpack(args))
    end)}

    local ok = table.remove(results, 1)
    if ok ~= true then
        return false, tostring(results[1])
    end

    local parts = {}
    for i, value in ipairs(results) do
        table.insert(parts, self:tpFormatTraceValue(value))
    end

    if #parts == 0 then
        return true, "<noReturn>"
    end

    return true, table.concat(parts, ",")
end

function MapObjectFinder:tpBuildFoliageTraceMenuMap(screen)
    local map = {}
    local treeItems = {}

    screen = screen or self:tpResolveConstructionLogicScreen()
    if screen == nil or type(screen.items) ~= "table" then
        return map, treeItems
    end

    local function addMenuEntry(layerName, state, item, categoryIndex, tabIndex, itemIndex)
        layerName = tostring(layerName or "")
        state = tonumber(state)
        if layerName == "" or state == nil then
            return
        end

        map[layerName] = map[layerName] or {}
        map[layerName][state] = map[layerName][state] or {}
        table.insert(map[layerName][state], {
            item = item,
            categoryIndex = categoryIndex,
            tabIndex = tabIndex,
            itemIndex = itemIndex
        })
    end

    for categoryIndex, categoryItems in pairs(screen.items) do
        if type(categoryItems) == "table" then
            for tabIndex, tabItems in pairs(categoryItems) do
                if type(tabItems) == "table" then
                    for itemIndex, item in ipairs(tabItems) do
                        if type(item) == "table" then
                            local itemName = tostring(item.name or item.title or "")
                            local lowerName = string.lower(itemName)
                            local image = tostring(item.imageFilename or "")
                            local lowerImage = string.lower(image)
                            local brushText = ""

                            if type(item.brushParameters) == "table" then
                                if item.brushParameters[2] ~= nil then
                                    local layerName = tostring(item.brushParameters[1] or "")
                                    local stateText = tostring(item.brushParameters[2] or "")
                                    brushText = layerName .. "|" .. stateText
                                    addMenuEntry(layerName, tonumber(stateText), item, categoryIndex, tabIndex, itemIndex)
                                else
                                    brushText = tostring(item.brushParameters[1] or "")
                                    local layerName, stateText = string.match(brushText, "^([^|]+)|([^|]+)$")
                                    addMenuEntry(layerName, tonumber(stateText), item, categoryIndex, tabIndex, itemIndex)
                                end
                            end

                            if string.find(lowerName, "tree", 1, true) ~= nil or string.find(lowerName, "baum", 1, true) ~= nil or string.find(lowerImage, "tree", 1, true) ~= nil or string.find(lowerImage, "baum", 1, true) ~= nil then
                                table.insert(treeItems, {
                                    categoryIndex = categoryIndex,
                                    tabIndex = tabIndex,
                                    itemIndex = itemIndex,
                                    name = itemName,
                                    image = image,
                                    brush = brushText,
                                    xml = tostring(item.xmlFilename or item.filename or item.configFileName or "")
                                })
                            end
                        end
                    end
                end
            end
        end
    end

    return map, treeItems
end

function MapObjectFinder:tpCollectTraceSamples(planeId, rawX, rawY, rawZ, gridX, gridZ)
    local samples = {}
    local offsets = {
        {name="raw", x=rawX, z=rawZ},
        {name="grid", x=gridX, z=gridZ},
        {name="rawN", x=rawX, z=rawZ + 0.15},
        {name="rawS", x=rawX, z=rawZ - 0.15},
        {name="rawE", x=rawX + 0.15, z=rawZ},
        {name="rawW", x=rawX - 0.15, z=rawZ}
    }

    for _, sample in ipairs(offsets) do
        local densityOk, density = self:tpSafeCallTrace("getDensityAtWorldPos", planeId, sample.x, rawY or 0, sample.z)
        local statesOk, states = self:tpSafeCallTrace("getDensityStatesAtWorldPos", planeId, sample.x, rawY or 0, sample.z)
        local typeOk, typeIndex = self:tpSafeCallTrace("getDensityTypeIndexAtWorldPos", planeId, sample.x, rawY or 0, sample.z)
        table.insert(samples, string.format(
            "%s[d=%s:%s states=%s:%s type=%s:%s]",
            tostring(sample.name),
            tostring(densityOk), tostring(density),
            tostring(statesOk), tostring(states),
            tostring(typeOk), tostring(typeIndex)
        ))
    end

    return table.concat(samples, " ")
end

function MapObjectFinder:tpLogOfficialFoliageTraceAtCurrentPick(screen)
    local gridX = self.lastPipetteWorldX
    local gridY = self.lastPipetteWorldY
    local gridZ = self.lastPipetteWorldZ
    local rawX = self.tpLastRawSampleX or gridX
    local rawY = self.tpLastRawSampleY or gridY
    local rawZ = self.tpLastRawSampleZ or gridZ
    local foliageSystem = g_currentMission ~= nil and g_currentMission.foliageSystem or nil
    local terrainRootNode = g_currentMission ~= nil and g_currentMission.terrainRootNode or nil

    if gridX == nil or gridZ == nil or rawX == nil or rawZ == nil then
        tpLog("officialFoliageTrace missingWorldPosition")
        return
    end

    tpLog(string.format(
        "officialFoliageTraceStart world=%.3f,%.3f,%.3f raw=%.3f,%.3f,%.3f terrainRoot=%s",
        tonumber(gridX) or 0,
        tonumber(gridY) or 0,
        tonumber(gridZ) or 0,
        tonumber(rawX) or 0,
        tonumber(rawY) or 0,
        tonumber(rawZ) or 0,
        tostring(terrainRootNode)
    ))

    if terrainRootNode ~= nil then
        local terrainSizeOk, terrainSize = self:tpSafeCallTrace("getTerrainSize", terrainRootNode)
        tpLog("officialTerrainInfo getTerrainSize=" .. tostring(terrainSizeOk) .. ":" .. tostring(terrainSize))
    end

    if type(foliageSystem) ~= "table" then
        tpLog("officialFoliageTrace missingFoliageSystem")
        return
    end

    local menuMap, treeItems = self:tpBuildFoliageTraceMenuMap(screen)

    local function menuStateSummary(layerName)
        local states = {}
        if type(menuMap[layerName]) == "table" then
            for state, entries in pairs(menuMap[layerName]) do
                table.insert(states, tostring(state) .. "(" .. tostring(#entries) .. ")")
            end
            table.sort(states)
        end
        if #states == 0 then
            return "<none>"
        end
        return table.concat(states, ",")
    end

    local function logFoliageTrace(sourceName, index, foliage)
        if type(foliage) ~= "table" then
            return
        end

        local layerName = tostring(foliage.layerName or foliage.foliageLayerName or foliage.name or "")
        if layerName == "" then
            layerName = "<empty>"
        end

        local fieldPlane = tonumber(foliage.terrainDataPlaneId)
        local byNameOk, byName = false, "notCalled"
        local foliageTgOk, foliageTg = false, "notCalled"
        local detailByNameOk, detailByName = false, "notCalled"

        if terrainRootNode ~= nil and layerName ~= "<empty>" then
            byNameOk, byName = self:tpSafeCallTrace("getTerrainDataPlaneByName", terrainRootNode, layerName)
            foliageTgOk, foliageTg = self:tpSafeCallTrace("getFoliageTransformGroupIdByFoliageName", terrainRootNode, layerName)
            detailByNameOk, detailByName = self:tpSafeCallTrace("getTerrainDetailByName", terrainRootNode, layerName)
        end

        local planeId = fieldPlane
        if planeId == nil then
            planeId = tonumber(string.match(tostring(byName), "^([^,]+)"))
        end

        local densityMapSizeOk, densityMapSize = false, "missingPlane"
        local associatedTgOk, associatedTg = false, "missingPlane"
        local detailNameOk, detailName = false, "missingPlane"
        local detailChannelsOk, detailChannels = false, "missingPlane"
        local detailTypeOk, detailType = false, "missingPlane"
        local samples = "missingPlane"
        local officialTypeMatch = "missingPlane"

        if planeId ~= nil then
            densityMapSizeOk, densityMapSize = self:tpSafeCallTrace("getDensityMapSize", planeId)
            associatedTgOk, associatedTg = self:tpSafeCallTrace("getDataPlaneAssociatedTransformGroup", planeId)
            detailNameOk, detailName = self:tpSafeCallTrace("getTerrainDetailName", planeId)
            detailChannelsOk, detailChannels = self:tpSafeCallTrace("getTerrainDetailNumChannels", planeId)
            detailTypeOk, detailType = self:tpSafeCallTrace("getTerrainDetailTypeIndex", planeId)
            samples = self:tpCollectTraceSamples(planeId, rawX, rawY, rawZ, gridX, gridZ)
            local byNameText = tostring(byName or "")
            local byNameType = tonumber(string.match(byNameText, "^[^,]+,([^,]+)"))
            local detailTypeNum = tonumber(tostring(detailType or ""))
            local sampleTypeOk, sampleType = self:tpSafeCallTrace("getDensityTypeIndexAtWorldPos", planeId, rawX, rawY or 0, rawZ)
            local sampleTypeNum = tonumber(tostring(sampleType or ""))
            officialTypeMatch = "byNameType=" .. tostring(byNameType or "<nil>") .. " detailType=" .. tostring(detailTypeNum or "<nil>") .. " rawType=" .. tostring(sampleTypeNum or "<nil>") .. " rawTypeOk=" .. tostring(sampleTypeOk) .. " matchByName=" .. tostring(byNameType ~= nil and sampleTypeNum ~= nil and byNameType == sampleTypeNum) .. " matchDetail=" .. tostring(detailTypeNum ~= nil and sampleTypeNum ~= nil and detailTypeNum == sampleTypeNum)
        end

        local startChannel = tonumber(foliage.startStateChannel or foliage.startChannel or foliage.stateChannel or 0) or 0
        local numChannels = tonumber(foliage.numStateChannels or foliage.numChannels or foliage.stateChannels or 0) or 0

        tpLog(string.format(
            "officialFoliageTrace source=%s index=%s layer=%s name=%s fieldPlane=%s byName=%s:%s detailByName=%s:%s foliageTg=%s:%s associatedTg=%s:%s densityMapSize=%s:%s detailName=%s:%s detailChannels=%s:%s detailType=%s:%s startChannel=%s numStateChannels=%s menuStates=%s typeMatch=%s samples=%s",
            tostring(sourceName),
            tostring(index),
            tostring(layerName),
            tostring(foliage.name or foliage.typeName or foliage.fillTypeName or "<nil>"),
            tostring(fieldPlane),
            tostring(byNameOk), tostring(byName),
            tostring(detailByNameOk), tostring(detailByName),
            tostring(foliageTgOk), tostring(foliageTg),
            tostring(associatedTgOk), tostring(associatedTg),
            tostring(densityMapSizeOk), tostring(densityMapSize),
            tostring(detailNameOk), tostring(detailName),
            tostring(detailChannelsOk), tostring(detailChannels),
            tostring(detailTypeOk), tostring(detailType),
            tostring(startChannel),
            tostring(numChannels),
            menuStateSummary(layerName),
            tostring(officialTypeMatch),
            tostring(samples)
        ))
    end

    if type(foliageSystem.paintableFoliages) == "table" then
        for index, foliage in ipairs(foliageSystem.paintableFoliages) do
            logFoliageTrace("paintableFoliages", index, foliage)
        end
    end

    if type(foliageSystem.decoFoliages) == "table" then
        for index, foliage in ipairs(foliageSystem.decoFoliages) do
            logFoliageTrace("decoFoliages", index, foliage)
        end
    end

    if type(foliageSystem.decoFoliageMappings) == "table" then
        local printed = 0
        for key, mapping in pairs(foliageSystem.decoFoliageMappings) do
            printed = printed + 1
            if printed > 60 then
                break
            end

            local mappedLayer = "<nil>"
            local mappedState = "<nil>"
            local mappedName = "<nil>"
            if type(mapping) == "table" then
                mappedLayer = tostring(mapping.layerName or mapping.foliageLayerName or mapping.name or mapping.typeName or "<nil>")
                mappedState = tostring(mapping.state or mapping.value or mapping.densityValue or mapping.growthState or "<nil>")
                mappedName = tostring(mapping.name or mapping.typeName or mapping.fillTypeName or "<nil>")
            else
                mappedName = tostring(mapping)
            end

            tpLog(string.format(
                "officialFoliageMapping key=%s mappedName=%s mappedLayer=%s mappedState=%s valueType=%s",
                tostring(key),
                tostring(mappedName),
                tostring(mappedLayer),
                tostring(mappedState),
                tostring(type(mapping))
            ))
        end
    end

    tpLog("officialTreeTrace separateHandlingRequired=true menuTreeCandidates=" .. tostring(#treeItems))
    for index, tree in ipairs(treeItems) do
        if index > 25 then
            break
        end
        tpLog(string.format(
            "officialTreeMenuCandidate index=%s name=%s brush=%s order=%s/%s/%s image=%s xml=%s",
            tostring(index),
            tostring(tree.name),
            tostring(tree.brush),
            tostring(tree.categoryIndex),
            tostring(tree.tabIndex),
            tostring(tree.itemIndex),
            tostring(tree.image),
            tostring(tree.xml)
        ))
    end

    tpLog("officialFoliageTraceEnd")
end

function MapObjectFinder:tpProbeFoliageAtCurrentPick()
    local x = self.lastPipetteWorldX
    local y = self.lastPipetteWorldY
    local z = self.lastPipetteWorldZ
    local foliageSystem = g_currentMission ~= nil and g_currentMission.foliageSystem or nil

    if x == nil or z == nil or type(foliageSystem) ~= "table" then
        return
    end

    local function sampleDensity(planeId, sampleX, sampleZ)
        if type(getDensityAtWorldPos) ~= "function" or planeId == nil then
            return false, nil
        end

        return pcall(function()
            return getDensityAtWorldPos(planeId, sampleX, y or 0, sampleZ)
        end)
    end

    local function resolvePlaneId(foliage)
        if type(foliage) ~= "table" then
            return nil, "noFoliageTable"
        end

        local planeId = tonumber(foliage.terrainDataPlaneId)
        if planeId ~= nil then
            return planeId, "terrainDataPlaneId"
        end

        local layerName = tostring(foliage.layerName or foliage.foliageLayerName or foliage.name or "")
        if layerName ~= "" and type(getTerrainDataPlaneByName) == "function" and g_currentMission ~= nil and g_currentMission.terrainRootNode ~= nil then
            local okPlane, plane = pcall(function()
                return getTerrainDataPlaneByName(g_currentMission.terrainRootNode, layerName)
            end)
            if okPlane == true and tonumber(plane) ~= nil then
                return tonumber(plane), "getTerrainDataPlaneByName"
            end
        end

        return nil, "missingPlaneId"
    end

    local function logPlaneSamples(prefix, index, foliage)
        local layerName = tostring(foliage.layerName or foliage.foliageLayerName or foliage.name or "")
        local planeId, planeSource = resolvePlaneId(foliage)
        local startChannel = tonumber(foliage.startStateChannel or foliage.startChannel or 0) or 0
        local numChannels = tonumber(foliage.numStateChannels or foliage.numChannels or 4) or 4

        local samples = {}
        local offsets = {
            {name = "center", dx = 0.00, dz = 0.00},
            {name = "north", dx = 0.00, dz = 0.25},
            {name = "south", dx = 0.00, dz = -0.25},
            {name = "east", dx = 0.25, dz = 0.00},
            {name = "west", dx = -0.25, dz = 0.00}
        }

        for _, offset in ipairs(offsets) do
            local okDensity, density = sampleDensity(planeId, x + offset.dx, z + offset.dz)
            table.insert(samples, string.format(
                "%s=%s:%s",
                tostring(offset.name),
                tostring(okDensity),
                tostring(density)
            ))
        end

        tpLog(string.format(
            "foliagePlaneProbe type=%s index=%s layer=%s plane=%s source=%s startChannel=%s numChannels=%s world=%.3f,%.3f,%.3f %s",
            tostring(prefix),
            tostring(index),
            tostring(layerName),
            tostring(planeId),
            tostring(planeSource),
            tostring(startChannel),
            tostring(numChannels),
            tonumber(x) or 0,
            tonumber(y) or 0,
            tonumber(z) or 0,
            table.concat(samples, " ")
        ))
    end

    if type(foliageSystem.paintableFoliages) == "table" then
        for index, foliage in ipairs(foliageSystem.paintableFoliages) do
            if index > 12 then
                break
            end

            self:tpLogTableKeys("paintableFoliageKeys index=" .. tostring(index), foliage, 32)
            logPlaneSamples("paintable", index, foliage)
        end
    end

    if type(foliageSystem.decoFoliages) == "table" then
        for index, foliage in ipairs(foliageSystem.decoFoliages) do
            if index > 12 then
                break
            end

            self:tpLogTableKeys("decoFoliageKeys index=" .. tostring(index), foliage, 32)
            logPlaneSamples("deco", index, foliage)
        end
    end

    if type(foliageSystem.decoFoliageMappings) == "table" then
        local printed = 0
        for key, mapping in pairs(foliageSystem.decoFoliageMappings) do
            printed = printed + 1
            if printed > 20 then
                break
            end
            self:tpLogTableKeys("decoFoliageMappingKeys key=" .. tostring(key), mapping, 32)
        end
    end
end

function MapObjectFinder:tpLogFoliageStructureOnce()
    if self.tpFoliageStructureLogged == true then
        return
    end

    self.tpFoliageStructureLogged = true

    local foliageSystem = g_currentMission ~= nil and g_currentMission.foliageSystem or nil
    if type(foliageSystem) ~= "table" then
        tpLog("foliageStructure missing")
        return
    end

    local paintableCount = type(foliageSystem.paintableFoliages) == "table" and #foliageSystem.paintableFoliages or 0
    local decoCount = type(foliageSystem.decoFoliages) == "table" and #foliageSystem.decoFoliages or 0
    local mappingCount = 0
    if type(foliageSystem.decoFoliageMappings) == "table" then
        for _ in pairs(foliageSystem.decoFoliageMappings) do
            mappingCount = mappingCount + 1
        end
    end

    tpLog(string.format("foliageStructure paintable=%s deco=%s mappings=%s", tostring(paintableCount), tostring(decoCount), tostring(mappingCount)))

    if type(foliageSystem.paintableFoliages) == "table" then
        for index, foliage in ipairs(foliageSystem.paintableFoliages) do
            if index > 12 then
                break
            end
            tpLog(string.format(
                "paintableFoliage index=%s name=%s layer=%s id=%s value=%s state=%s",
                tostring(index),
                tostring(foliage.name or foliage.typeName or foliage.fillTypeName or "<nil>"),
                tostring(foliage.layerName or foliage.foliageLayerName or "<nil>"),
                tostring(foliage.id or foliage.typeIndex or foliage.foliageId or "<nil>"),
                tostring(foliage.value or foliage.densityValue or "<nil>"),
                tostring(foliage.state or foliage.growthState or foliage.growthStateI or "<nil>")
            ))
        end
    end

    if type(foliageSystem.decoFoliages) == "table" then
        for index, foliage in ipairs(foliageSystem.decoFoliages) do
            if index > 12 then
                break
            end
            tpLog(string.format(
                "decoFoliage index=%s name=%s layer=%s id=%s value=%s state=%s",
                tostring(index),
                tostring(foliage.name or foliage.typeName or foliage.fillTypeName or "<nil>"),
                tostring(foliage.layerName or foliage.foliageLayerName or "<nil>"),
                tostring(foliage.id or foliage.typeIndex or foliage.foliageId or "<nil>"),
                tostring(foliage.value or foliage.densityValue or "<nil>"),
                tostring(foliage.state or foliage.growthState or foliage.growthStateI or "<nil>")
            ))
        end
    end

    if type(foliageSystem.decoFoliageMappings) == "table" then
        local printed = 0
        for key, mapping in pairs(foliageSystem.decoFoliageMappings) do
            printed = printed + 1
            if printed > 16 then
                break
            end
            tpLog(string.format(
                "decoFoliageMapping key=%s type=%s value=%s name=%s layer=%s",
                tostring(key),
                tostring(type(mapping)),
                tostring(mapping),
                type(mapping) == "table" and tostring(mapping.name or mapping.typeName or "<nil>") or "<nil>",
                type(mapping) == "table" and tostring(mapping.layerName or mapping.foliageLayerName or "<nil>") or "<nil>"
            ))
        end
    end
end

function MapObjectFinder:tpBuildFoliageDebugOverlayForWorld(x, y, z)
    if tpIsDebugModeEnabled() ~= true then
        return
    end

    local lines = {}
    table.insert(lines, "Terrain Texture And Object Picker Debug")
    table.insert(lines, string.format("Click world: %.3f / %.3f / %.3f", tonumber(x) or 0, tonumber(y) or 0, tonumber(z) or 0))

    local foliageSystem = g_currentMission ~= nil and g_currentMission.foliageSystem or nil
    if type(foliageSystem) ~= "table" then
        table.insert(lines, "No foliageSystem available")
        self.tpDebugOverlayLines = lines
        self.tpDebugLastClickTime = getTimeSec ~= nil and getTimeSec() or 0
        return
    end

    local function resolvePlaneId(foliage)
        if type(foliage) ~= "table" then
            return nil
        end

        local planeId = tonumber(foliage.terrainDataPlaneId)
        if planeId ~= nil then
            return planeId
        end

        local layerName = tostring(foliage.layerName or foliage.foliageLayerName or foliage.name or "")
        if layerName ~= "" and type(getTerrainDataPlaneByName) == "function" and g_currentMission ~= nil and g_currentMission.terrainRootNode ~= nil then
            local okPlane, plane = pcall(function()
                return getTerrainDataPlaneByName(g_currentMission.terrainRootNode, layerName)
            end)
            if okPlane == true and tonumber(plane) ~= nil then
                return tonumber(plane)
            end
        end

        return nil
    end

    local function sampleDensity(planeId, sx, sz)
        if type(getDensityAtWorldPos) ~= "function" or planeId == nil then
            return nil
        end

        local ok, density = pcall(function()
            return getDensityAtWorldPos(planeId, sx, y or 0, sz)
        end)

        if ok == true then
            return tonumber(density)
        end

        return nil
    end

    local layers = {}
    local function addLayer(foliage, source)
        if type(foliage) ~= "table" then
            return
        end

        local layerName = tostring(foliage.layerName or foliage.foliageLayerName or foliage.name or "")
        if layerName == "" or layers[layerName] ~= nil then
            return
        end

        local planeId = resolvePlaneId(foliage)
        if planeId ~= nil then
            table.insert(layers, { name = layerName, planeId = planeId, source = tostring(source or "?") })
            layers[layerName] = true
        end
    end

    if type(foliageSystem.paintableFoliages) == "table" then
        for _, foliage in ipairs(foliageSystem.paintableFoliages) do
            addLayer(foliage, "paintable")
        end
    end

    if type(foliageSystem.decoFoliages) == "table" then
        for _, foliage in ipairs(foliageSystem.decoFoliages) do
            addLayer(foliage, "deco")
        end
    end

    local offset = 0.50
    for _, layer in ipairs(layers) do
        if #lines >= 10 then
            break
        end

        local center = sampleDensity(layer.planeId, x, z) or 0
        local north = sampleDensity(layer.planeId, x, z - offset) or 0
        local south = sampleDensity(layer.planeId, x, z + offset) or 0
        local east = sampleDensity(layer.planeId, x + offset, z) or 0
        local west = sampleDensity(layer.planeId, x - offset, z) or 0
        if center ~= 0 or north ~= 0 or south ~= 0 or east ~= 0 or west ~= 0 then
            table.insert(lines, string.format("%s: C=%s N=%s S=%s E=%s W=%s", tostring(layer.name), tostring(center), tostring(north), tostring(south), tostring(east), tostring(west)))
        end
    end

    if #lines <= 2 then
        table.insert(lines, "No non-zero foliage density at sampled points")
    end

    self.tpDebugOverlayLines = lines
    self.tpDebugLastClickTime = getTimeSec ~= nil and getTimeSec() or 0

    for _, line in ipairs(lines) do
        tpLog("debugOverlay " .. tostring(line))
    end
end

function MapObjectFinder:tpDrawDebugWorldLine(x1, y1, z1, x2, y2, z2, r, g, b)
    r = r or 0.15
    g = g or 1.0
    b = b or 0.15

    if DebugUtil ~= nil and type(DebugUtil.drawDebugLine) == "function" then
        local ok = pcall(function()
            DebugUtil.drawDebugLine(x1, y1, z1, x2, y2, z2, r, g, b)
        end)
        if ok == true then
            return true
        end
    end

    if type(drawDebugLine) == "function" then
        local ok = pcall(function()
            drawDebugLine(x1, y1, z1, x2, y2, z2, r, g, b)
        end)
        if ok == true then
            return true
        end
    end

    if DebugUtil ~= nil and type(DebugUtil.drawDebugPoint) == "function" then
        local ok = pcall(function()
            DebugUtil.drawDebugPoint(x1, y1, z1, 0.05, r, g, b)
            DebugUtil.drawDebugPoint(x2, y2, z2, 0.05, r, g, b)
        end)
        if ok == true then
            return true
        end
    end

    return false
end

function MapObjectFinder:tpResolveDebugFoliagePlane()
    local foliageSystem = g_currentMission ~= nil and g_currentMission.foliageSystem or nil
    if type(foliageSystem) ~= "table" then
        return nil, nil
    end

    local function resolvePlaneId(foliage)
        if type(foliage) ~= "table" then
            return nil
        end

        local planeId = tonumber(foliage.terrainDataPlaneId)
        if planeId ~= nil then
            return planeId
        end

        local layerName = tostring(foliage.layerName or foliage.foliageLayerName or foliage.name or "")
        if layerName ~= "" and type(getTerrainDataPlaneByName) == "function" and g_currentMission ~= nil and g_currentMission.terrainRootNode ~= nil then
            local okPlane, plane = pcall(function()
                return getTerrainDataPlaneByName(g_currentMission.terrainRootNode, layerName)
            end)
            if okPlane == true and tonumber(plane) ~= nil then
                return tonumber(plane)
            end
        end

        return nil
    end

    local bestPlane = nil
    local bestName = nil

    local function tryList(list)
        if type(list) ~= "table" then
            return
        end
        for _, foliage in ipairs(list) do
            local layerName = tostring(foliage.layerName or foliage.foliageLayerName or foliage.name or "")
            local planeId = resolvePlaneId(foliage)
            if planeId ~= nil then
                bestPlane = planeId
                bestName = layerName ~= "" and layerName or tostring(planeId)
                return
            end
        end
    end

    tryList(foliageSystem.decoFoliages)
    if bestPlane == nil then
        tryList(foliageSystem.paintableFoliages)
    end

    return bestPlane, bestName
end

function MapObjectFinder:tpSampleDebugDensity(planeId, x, y, z)
    if type(getDensityAtWorldPos) ~= "function" or planeId == nil then
        return nil
    end

    local ok, density = pcall(function()
        return getDensityAtWorldPos(planeId, x, y or 0, z)
    end)

    if ok == true then
        return tonumber(density)
    end

    return nil
end

function MapObjectFinder:tpFindDebugRasterBoundary(planeId, x, y, z, dx, dz, maxDistance, stepSize)
    local centerValue = self:tpSampleDebugDensity(planeId, x, y, z)
    if centerValue == nil then
        return nil
    end

    maxDistance = maxDistance or 2.0
    stepSize = stepSize or 0.025

    local lastSame = 0
    local firstDifferent = nil
    local distance = stepSize
    while distance <= maxDistance do
        local value = self:tpSampleDebugDensity(planeId, x + (dx * distance), y, z + (dz * distance))
        if value == nil then
            break
        end
        if value ~= centerValue then
            firstDifferent = distance
            break
        end
        lastSame = distance
        distance = distance + stepSize
    end

    if firstDifferent == nil then
        return nil
    end

    local low = lastSame
    local high = firstDifferent
    for _ = 1, 8 do
        local mid = (low + high) * 0.5
        local value = self:tpSampleDebugDensity(planeId, x + (dx * mid), y, z + (dz * mid))
        if value == centerValue then
            low = mid
        else
            high = mid
        end
    end

    return high
end

function MapObjectFinder:tpBuildAlignedDebugGridPosition(x, y, z)
    local planeId, layerName = self:tpResolveDebugFoliagePlane()
    if planeId == nil then
        return nil
    end

    local cellSize = 0.50
    local terrainRootNode = g_currentMission ~= nil and g_currentMission.terrainRootNode or nil
    if terrainRootNode ~= nil and type(getTerrainSize) == "function" and type(getDensityMapSize) == "function" then
        local okTerrain, terrainSize = pcall(function()
            return getTerrainSize(terrainRootNode)
        end)
        local okDensity, densitySize = pcall(function()
            return getDensityMapSize(planeId)
        end)
        terrainSize = tonumber(terrainSize)
        densitySize = tonumber(densitySize)
        if okTerrain == true and okDensity == true and terrainSize ~= nil and densitySize ~= nil and terrainSize > 0 and densitySize > 0 then
            local calculated = terrainSize / densitySize
            if calculated > 0.05 and calculated < 5 then
                cellSize = calculated
            end
        end
    end

    return {
        centerX = math.floor((tonumber(x) or 0) / cellSize + 0.5) * cellSize,
        centerZ = math.floor((tonumber(z) or 0) / cellSize + 0.5) * cellSize,
        cellX = cellSize,
        cellZ = cellSize,
        layerName = layerName or "?",
        aligned = true,
        boundaryMode = "officialCell",
        measuredEast = nil,
        measuredWest = nil,
        measuredNorth = nil,
        measuredSouth = nil
    }
end

function MapObjectFinder:tpDrawPersistentDebugGrid()
    local x, y, z = self:findMouseWorldPosition()
    if x == nil then
        x = self.lastPipetteWorldX
        y = self.lastPipetteWorldY
        z = self.lastPipetteWorldZ
    end

    if x == nil or y == nil or z == nil then
        return false
    end

    local grid = self:tpBuildAlignedDebugGridPosition(x, y, z)
    if grid == nil then
        return false
    end

    local centerX = grid.centerX
    local centerZ = grid.centerZ
    local cellX = grid.cellX
    local cellZ = grid.cellZ
    local drawY = (tonumber(y) or 0) + 0.09
    local anyLine = false
    local recognitionFallbackActive = false
    if self.tpLastFoliageRecognitionFallback == true then
        local now = getTimeSec ~= nil and getTimeSec() or 0
        recognitionFallbackActive = self.tpLastFoliageRecognitionFallbackUntil == nil or now <= self.tpLastFoliageRecognitionFallbackUntil
    end

    for i = -2, 2 do
        local xLine = centerX + ((i - 0.5) * cellX)
        local zLine = centerZ + ((i - 0.5) * cellZ)
        local major = (i == 0 or i == 1)
        local r = recognitionFallbackActive and 1.0 or (major and 1.0 or 0.45)
        local g = recognitionFallbackActive and 0.05 or (major and 0.15 or 1.0)
        local b = recognitionFallbackActive and 0.05 or (major and 0.05 or 0.25)

        anyLine = self:tpDrawDebugWorldLine(centerX - (1.5 * cellX), drawY, zLine, centerX + (1.5 * cellX), drawY, zLine, r, g, b) or anyLine
        anyLine = self:tpDrawDebugWorldLine(xLine, drawY, centerZ - (1.5 * cellZ), xLine, drawY, centerZ + (1.5 * cellZ), r, g, b) or anyLine
    end

    local left = centerX - (0.5 * cellX)
    local right = centerX + (0.5 * cellX)
    local top = centerZ - (0.5 * cellZ)
    local bottom = centerZ + (0.5 * cellZ)
    local br = (recognitionFallbackActive == true) and 1.0 or (grid.aligned and 0.05 or 1.0)
    local bg = (recognitionFallbackActive == true) and 0.05 or (grid.aligned and 1.0 or 0.65)
    local bb = (recognitionFallbackActive == true) and 0.05 or (grid.aligned and 0.05 or 0.0)
    anyLine = self:tpDrawDebugWorldLine(left, drawY + 0.015, top, right, drawY + 0.015, top, br, bg, bb) or anyLine
    anyLine = self:tpDrawDebugWorldLine(right, drawY + 0.015, top, right, drawY + 0.015, bottom, br, bg, bb) or anyLine
    anyLine = self:tpDrawDebugWorldLine(right, drawY + 0.015, bottom, left, drawY + 0.015, bottom, br, bg, bb) or anyLine
    anyLine = self:tpDrawDebugWorldLine(left, drawY + 0.015, bottom, left, drawY + 0.015, top, br, bg, bb) or anyLine

    local cross = math.min(cellX, cellZ) * 0.18
    anyLine = self:tpDrawDebugWorldLine((tonumber(x) or centerX) - cross, drawY + 0.03, tonumber(z) or centerZ, (tonumber(x) or centerX) + cross, drawY + 0.03, tonumber(z) or centerZ, 1.0, 1.0, 1.0) or anyLine
    anyLine = self:tpDrawDebugWorldLine(tonumber(x) or centerX, drawY + 0.03, (tonumber(z) or centerZ) - cross, tonumber(x) or centerX, drawY + 0.03, (tonumber(z) or centerZ) + cross, 1.0, 1.0, 1.0) or anyLine

    if anyLine == true then
        local modeText = grid.boundaryMode == "officialCell" and "LS25-Zellgröße offiziell" or (grid.aligned and "LS25-Grenze gemessen" or "Fallback-Grenze sichtbar")
        if recognitionFallbackActive == true then
            modeText = "Fallback: keine sichere Foliage-Erkennung"
        end
        self.tpDebugOverlayLines = {
            "Terrain Texture And Object Picker Debug",
            "3x3 Grid: " .. modeText,
            "Sampling: offizielle Zellgröße + Rohpunkt",
            "Layer: " .. tostring(grid.layerName or "?"),
            string.format("Cell: %.3f x %.3f", tonumber(cellX) or 0, tonumber(cellZ) or 0),
            string.format("Center: %.3f / %.3f", tonumber(centerX) or 0, tonumber(centerZ) or 0),
            string.format("Mouse: %.3f / %.3f", tonumber(x) or 0, tonumber(z) or 0)
        }
    end

    return anyLine
end

function MapObjectFinder:tpDrawDebugOverlayNow(source)
    if tpIsDebugModeEnabled() ~= true then
        return
    end

    local gridDrawn = false
    local okGrid, resultGrid = pcall(function()
        return self:tpDrawPersistentDebugGrid()
    end)
    if okGrid == true and resultGrid == true then
        gridDrawn = true
    end

    if renderText == nil then
        return
    end

    local lines = self.tpDebugOverlayLines
    if type(lines) ~= "table" or #lines == 0 then
        lines = { "Terrain Texture And Object Picker Debug aktiv", "3x3 LS25-Raster-Grid aktiv.", "Pipette nutzen, um Werte zu loggen." }
    end

    local y = 0.94
    for index, line in ipairs(lines) do
        if index > 9 then
            break
        end
        pcall(function()
            renderText(0.02, y - ((index - 1) * 0.018), 0.014, tostring(line))
        end)
    end

    pcall(function()
        renderText(0.02, 0.76, 0.014, gridDrawn and "Debug-Grid: sichtbar (" .. tostring(source or "world") .. ")" or "Debug-Grid: keine 3D-Line-Funktion verfügbar")
    end)
end


function MapObjectFinder:tpDrawMapOnlyFoliageMarkerNow()
    if type(self.tpMapOnlyFoliageMarker) ~= "table" then
        return
    end

    local marker = self.tpMapOnlyFoliageMarker
    local now = getTimeSec ~= nil and getTimeSec() or 0
    if tonumber(marker.expiresAt or 0) < now then
        self.tpMapOnlyFoliageMarker = nil
        return
    end

    local x = tonumber(marker.x)
    local y = tonumber(marker.y)
    local z = tonumber(marker.z)
    if x == nil or y == nil or z == nil then
        return
    end

    local height = 1.8
    local radius = 0.65
    local topY = y + height
    local midY = y + 0.15

    self:tpDrawDebugWorldLine(x - radius, midY, z, x + radius, midY, z, 1.0, 0.65, 0.05)
    self:tpDrawDebugWorldLine(x, midY, z - radius, x, midY, z + radius, 1.0, 0.65, 0.05)
    self:tpDrawDebugWorldLine(x, y, z, x, topY, z, 1.0, 0.25, 0.05)
    self:tpDrawDebugWorldLine(x - radius, topY, z - radius, x + radius, topY, z + radius, 1.0, 0.25, 0.05)
    self:tpDrawDebugWorldLine(x - radius, topY, z + radius, x + radius, topY, z - radius, 1.0, 0.25, 0.05)

    if renderText ~= nil then
        pcall(function()
            renderText(0.02, 0.78, 0.015, "Map-only Foliage: " .. tostring(marker.layer or "?") .. " states " .. tostring(marker.states or "?"))
        end)
    end
end


function MapObjectFinder:draw()
    self:tpDrawMapOnlyFoliageMarkerNow()
end

local function tpAfterConstructionScreenDraw(screen, ...)
    if TP_DEBUG_OVERLAY_ENABLED == true and MapObjectFinder ~= nil and MapObjectFinder.tpDrawDebugOverlayNow ~= nil then
        MapObjectFinder:tpDrawDebugOverlayNow("construction")
    end
end

if TP_DEBUG_OVERLAY_ENABLED == true and ConstructionScreen ~= nil and ConstructionScreen.draw ~= nil then
    ConstructionScreen.draw = Utils.appendedFunction(ConstructionScreen.draw, tpAfterConstructionScreenDraw)
end


function MapObjectFinder.tpOnTreeProbeShapeDetected(self, splitShapeId)
    if self == nil or splitShapeId == nil or splitShapeId == 0 then
        return
    end

    self.tpTreeProbeShapes = self.tpTreeProbeShapes or {}
    self.tpTreeProbeSeen = self.tpTreeProbeSeen or {}

    if self.tpTreeProbeSeen[splitShapeId] == true then
        return
    end
    self.tpTreeProbeSeen[splitShapeId] = true

    table.insert(self.tpTreeProbeShapes, splitShapeId)
end

function MapObjectFinder:tpSafeCall(label, fn)
    if type(fn) ~= "function" then
        return nil, "noFunction"
    end

    local ok, result = pcall(fn)
    if ok == true then
        return result, nil
    end

    return nil, tostring(result or label or "error")
end


local function tpNormalizeTreeComparable(value)
    if value == nil then
        return nil
    end

    local text = string.lower(tostring(value or ""))
    text = string.gsub(text, "ä", "ae")
    text = string.gsub(text, "ö", "oe")
    text = string.gsub(text, "ü", "ue")
    text = string.gsub(text, "ß", "ss")
    text = string.gsub(text, "[^a-z0-9]+", "")

    if text == "" then
        return nil
    end

    return text
end

local function tpTreeTextMatches(haystack, needle)
    haystack = tpNormalizeTreeComparable(haystack)
    needle = tpNormalizeTreeComparable(needle)

    if haystack == nil or needle == nil or string.len(haystack) < 4 or string.len(needle) < 4 then
        return false
    end

    return haystack == needle
end

function MapObjectFinder:tpGetTreeDescFromSplitShape(splitShapeId)
    if splitShapeId == nil or splitShapeId == 0 then
        return nil, nil
    end

    if type(getSplitType) ~= "function" then
        return nil, nil
    end

    local splitType = self:tpSafeCall("getSplitType", function()
        return getSplitType(splitShapeId)
    end)

    if splitType == nil then
        return nil, nil
    end

    if g_treePlantManager == nil or type(g_treePlantManager.getTreeTypeDescFromSplitType) ~= "function" then
        return nil, splitType
    end

    local okDesc, desc = pcall(function()
        return g_treePlantManager:getTreeTypeDescFromSplitType(splitType)
    end)

    if okDesc ~= true then
        return nil, splitType
    end

    return desc, splitType
end

function MapObjectFinder:tpCollectTreeDescsAtWorldPosition(x, y, z)
    x = tonumber(x)
    y = tonumber(y)
    z = tonumber(z)

    if x == nil or y == nil or z == nil then
        return {}
    end

    if type(overlapSphere) ~= "function" or CollisionFlag == nil or CollisionFlag.TREE == nil then
        return {}
    end

    self.tpTreeProbeShapes = {}
    self.tpTreeProbeSeen = {}

    local radius = TP_TREE_SCAN_RADIUS
    local scanY = y + 0.75
    local okScan = pcall(function()
        overlapSphere(x, scanY, z, radius, "tpOnTreeProbeShapeDetected", self, CollisionFlag.TREE, false, false, true, false)
    end)

    local rawShapes = self.tpTreeProbeShapes or {}
    self.tpTreeProbeShapes = nil
    self.tpTreeProbeSeen = nil

    if okScan ~= true or #rawShapes == 0 then
        return {}
    end

    local results = {}
    local seenSplitType = {}

    for _, splitShapeId in ipairs(rawShapes) do
        local desc, splitType = self:tpGetTreeDescFromSplitShape(splitShapeId)
        if desc ~= nil and splitType ~= nil and seenSplitType[splitType] ~= true then
            seenSplitType[splitType] = true

            local px, py, pz = nil, nil, nil
            if type(getWorldTranslation) == "function" then
                local okPos, rx, ry, rz = pcall(function()
                    return getWorldTranslation(splitShapeId)
                end)
                if okPos == true then
                    px, py, pz = rx, ry, rz
                end
            end

            local dx = (tonumber(px) or x) - x
            local dy = (tonumber(py) or y) - y
            local dz = (tonumber(pz) or z) - z
            local distanceSq = dx * dx + dy * dy + dz * dz

            if distanceSq <= (radius * radius) then
                table.insert(results, {
                    splitShapeId = splitShapeId,
                    splitType = splitType,
                    desc = desc,
                    distanceSq = distanceSq
                })
            elseif tpIsDebugModeEnabled() == true then
                tpLog("treePick skippedByDistance splitType=" .. tostring(splitType) .. " distanceSq=" .. tostring(distanceSq) .. " radius=" .. tostring(radius))
            end
        end
    end

    table.sort(results, function(a, b)
        return (tonumber(a.distanceSq) or 0) < (tonumber(b.distanceSq) or 0)
    end)

    return results
end

function MapObjectFinder:tpTreeItemTextMatchesDesc(item, desc)
    if type(item) ~= "table" or type(desc) ~= "table" then
        return false
    end

    local storeItem = type(item.storeItem) == "table" and item.storeItem or nil
    local brush = storeItem ~= nil and type(storeItem.brush) == "table" and storeItem.brush or nil

    local descName = desc.name
    local descTitle = desc.title
    local descIndex = desc.index

    local fields = {
        item.name,
        item.title,
        item.xmlFilename,
        item.filename,
        item.configFileName,
        item.imageFilename,
        storeItem ~= nil and storeItem.name or nil,
        storeItem ~= nil and storeItem.title or nil,
        storeItem ~= nil and storeItem.xmlFilename or nil,
        storeItem ~= nil and storeItem.filename or nil,
        storeItem ~= nil and storeItem.configFileName or nil,
        storeItem ~= nil and storeItem.imageFilename or nil,
        storeItem ~= nil and storeItem.species or nil,
        storeItem ~= nil and storeItem.customEnvironment or nil,
        brush ~= nil and brush.type or nil,
        brush ~= nil and brush.category or nil,
        brush ~= nil and brush.tab or nil
    }

    if type(item.brushParameters) == "table" then
        for _, value in ipairs(item.brushParameters) do
            table.insert(fields, value)
        end
    end

    if brush ~= nil and type(brush.parameters) == "table" then
        for _, value in ipairs(brush.parameters) do
            table.insert(fields, value)
        end
    end

    for _, field in ipairs(fields) do
        if tpTreeTextMatches(field, descName) == true or tpTreeTextMatches(field, descTitle) == true then
            return true
        end
    end


    return false
end

function MapObjectFinder:tpCreateTreeProbeDisplayItem(treeInfo)
    local desc = type(treeInfo) == "table" and treeInfo.desc or nil
    if type(desc) ~= "table" then
        return nil
    end

    local title = tostring(desc.title or desc.name or "Tree")
    local name = tostring(desc.name or desc.title or "TREE")
    local splitType = tostring(type(treeInfo) == "table" and (treeInfo.splitType or "?") or "?")
    local label = string.format("%s: %s", tpText("TP_label_treeDetected", "Tree detected"), title)
    local iconPath = nil

    if self.modDirectory ~= nil then
        iconPath = tostring(self.modDirectory) .. "icon_TexturePipette.dds"
    elseif g_currentModDirectory ~= nil then
        iconPath = tostring(g_currentModDirectory) .. "icon_TexturePipette.dds"
    end

    return {
        name = label,
        title = label,
        price = 0,
        imageFilename = iconPath,
        tpTreeProbeOnly = true,
        storeItem = {
            name = label,
            title = label,
            price = 0,
            imageFilename = iconPath,
            xmlFilename = "",
            customEnvironment = "MapObjectFinderTreeProbe",
            brush = {
                type = "select",
                parameters = {}
            }
        }
    }
end

local function tpExtractTreeNameFromHierarchy(hierarchy)
    if hierarchy == nil then
        return nil
    end

    local text = tostring(hierarchy)
    local value = string.match(text, "/trees/([^/]+)/")
    if value == nil or value == "" then
        return nil
    end

    value = string.gsub(value, "_", " ")
    value = string.gsub(value, "([a-z])([A-Z])", "%1 %2")
    value = string.gsub(value, "stage(%d+)", "stage %1")
    value = string.gsub(value, "Stage(%d+)", "Stage %1")
    return value
end

function MapObjectFinder:tpCreateStaticTreeDisplayItem(hierarchy)
    local treeName = tpExtractTreeNameFromHierarchy(hierarchy)
    if treeName == nil then
        return nil
    end

    local label = string.format("%s: %s", tpText("TP_label_treeDetected", "Tree detected"), treeName)
    local iconPath = nil

    if self.modDirectory ~= nil then
        iconPath = tostring(self.modDirectory) .. "icon_TexturePipette.dds"
    elseif g_currentModDirectory ~= nil then
        iconPath = tostring(g_currentModDirectory) .. "icon_TexturePipette.dds"
    end

    return {
        name = label,
        title = label,
        price = 0,
        imageFilename = iconPath,
        tpTreeProbeOnly = true,
        storeItem = {
            name = label,
            title = label,
            price = 0,
            imageFilename = iconPath,
            xmlFilename = "",
            customEnvironment = "MapObjectFinderStaticTree",
            brush = {
                type = "select",
                parameters = {}
            }
        }
    }
end

local function tpTreeTextHasTreeMarker(value)
    if value == nil then
        return false
    end

    local text = string.lower(tostring(value or ""))
    if string.find(text, "treesapling", 1, true) ~= nil
        or string.find(text, "sapling", 1, true) ~= nil
        or string.find(text, "treeplant", 1, true) ~= nil
        or string.find(text, "treetype", 1, true) ~= nil
        or string.find(text, "baum", 1, true) ~= nil then
        return true
    end

    if string.find(text, "tree", 1, true) ~= nil and string.find(text, "street", 1, true) == nil then
        return true
    end

    return false
end

local function tpTreeCollectComparableEvidence(root, desc, treeInfo)
    local evidence = {tree = {}, desc = {}, numeric = {}}
    local descName = tpNormalizeTreeComparable(desc ~= nil and desc.name or nil)
    local descTitle = tpNormalizeTreeComparable(desc ~= nil and desc.title or nil)
    local descIndex = tonumber(desc ~= nil and desc.index or nil)
    local splitType = tonumber(treeInfo ~= nil and treeInfo.splitType or nil)

    local function add(list, text)
        if #list < 8 then
            table.insert(list, tostring(text))
        end
    end

    local function inspectValue(path, value)
        local valueType = type(value)
        if valueType ~= "string" and valueType ~= "number" and valueType ~= "boolean" then
            return
        end

        local text = tostring(value)
        local normalized = tpNormalizeTreeComparable(text)

        if tpTreeTextHasTreeMarker(path) or tpTreeTextHasTreeMarker(text) then
            add(evidence.tree, tostring(path) .. "=" .. text)
        end

        if normalized ~= nil and (normalized == descName or normalized == descTitle) then
            add(evidence.desc, tostring(path) .. "=" .. text)
        end

        local numeric = tonumber(text)
        if numeric ~= nil and (numeric == descIndex or numeric == splitType) then
            local pathText = string.lower(tostring(path or ""))
            if string.find(pathText, "treesapling", 1, true) ~= nil
                or string.find(pathText, "treetype", 1, true) ~= nil
                or string.find(pathText, "splittype", 1, true) ~= nil then
                add(evidence.numeric, tostring(path) .. "=" .. text)
            end
        end
    end

    local function inspectTable(prefix, tbl)
        if type(tbl) ~= "table" then
            return
        end

        local scalarKeys = {
            "name", "title", "xmlFilename", "filename", "configFileName", "imageFilename",
            "species", "customEnvironment", "category", "tab", "type", "treeType",
            "treeSaplingType", "splitType", "index", "id", "brandName", "categoryName"
        }

        for _, key in ipairs(scalarKeys) do
            inspectValue(prefix .. "." .. key, tbl[key])
        end

        if type(tbl.brushParameters) == "table" then
            for i, value in ipairs(tbl.brushParameters) do
                inspectValue(prefix .. ".brushParameters[" .. tostring(i) .. "]", value)
            end
        end

        if type(tbl.parameters) == "table" then
            for i, value in ipairs(tbl.parameters) do
                inspectValue(prefix .. ".parameters[" .. tostring(i) .. "]", value)
            end
        end
    end

    if type(root) ~= "table" then
        return evidence
    end

    inspectTable("item", root)

    if type(root.storeItem) == "table" then
        inspectTable("item.storeItem", root.storeItem)
        if type(root.storeItem.brush) == "table" then
            inspectTable("item.storeItem.brush", root.storeItem.brush)
        end
    end

    if type(root.brush) == "table" then
        inspectTable("item.brush", root.brush)
    end

    return evidence
end


function MapObjectFinder:tpFindTreePlaceableCandidates(screen, treeInfo)
    local candidates = {}
    local desc = treeInfo ~= nil and treeInfo.desc or nil
    if screen == nil or type(screen.items) ~= "table" or type(desc) ~= "table" then
        return candidates
    end

    for categoryIndex, categoryItems in pairs(screen.items) do
        if type(categoryItems) == "table" then
            for tabIndex, tabItems in pairs(categoryItems) do
                if type(tabItems) == "table" then
                    for itemIndex, item in ipairs(tabItems) do
                        if type(item) == "table" then
                            local evidence = tpTreeCollectComparableEvidence(item, desc, treeInfo)
                            local descHits = #evidence.desc
                            local treeHits = #evidence.tree
                            local numericHits = #evidence.numeric

                            if treeHits > 0 and descHits > 0 then
                                table.insert(candidates, {
                                    item = item,
                                    categoryIndex = categoryIndex,
                                    tabIndex = tabIndex,
                                    itemIndex = itemIndex,
                                    descHits = descHits,
                                    treeHits = treeHits,
                                    numericHits = numericHits,
                                    descEvidence = table.concat(evidence.desc, " ; "),
                                    treeEvidence = table.concat(evidence.tree, " ; "),
                                    numericEvidence = table.concat(evidence.numeric, " ; ")
                                })
                            end
                        end
                    end
                end
            end
        end
    end

    table.sort(candidates, function(a, b)
        local aScore = (tonumber(a.descHits) or 0) * 100 + (tonumber(a.treeHits) or 0)
        local bScore = (tonumber(b.descHits) or 0) * 100 + (tonumber(b.treeHits) or 0)
        if aScore == bScore then
            return tostring((a.item or {}).name or "") < tostring((b.item or {}).name or "")
        end
        return aScore > bScore
    end)

    return candidates
end

function MapObjectFinder:tpFindTreeCatalogueCandidates(screen, treeInfo)
    local candidates = {}
    local desc = treeInfo ~= nil and treeInfo.desc or nil
    if screen == nil or type(screen.items) ~= "table" or type(desc) ~= "table" then
        return candidates
    end

    for categoryIndex, categoryItems in pairs(screen.items) do
        if type(categoryItems) == "table" then
            for tabIndex, tabItems in pairs(categoryItems) do
                if type(tabItems) == "table" then
                    for itemIndex, item in ipairs(tabItems) do
                        if type(item) == "table" then
                            local evidence = tpTreeCollectComparableEvidence(item, desc, treeInfo)
                            local descHits = #evidence.desc
                            local treeHits = #evidence.tree

                            if treeHits > 0 then
                                table.insert(candidates, {
                                    item = item,
                                    categoryIndex = categoryIndex,
                                    tabIndex = tabIndex,
                                    itemIndex = itemIndex,
                                    descHits = descHits,
                                    treeHits = treeHits,
                                    descEvidence = table.concat(evidence.desc, " ; "),
                                    treeEvidence = table.concat(evidence.tree, " ; ")
                                })
                            end
                        end
                    end
                end
            end
        end
    end

    table.sort(candidates, function(a, b)
        local aScore = (tonumber(a.descHits) or 0) * 100 + (tonumber(a.treeHits) or 0)
        local bScore = (tonumber(b.descHits) or 0) * 100 + (tonumber(b.treeHits) or 0)
        if aScore == bScore then
            return tostring((a.item or {}).name or "") < tostring((b.item or {}).name or "")
        end
        return aScore > bScore
    end)

    return candidates
end


function MapObjectFinder:tpFindTreeDisplayItemsForDescs(screen, treeDescs)
    local results = {}

    if type(treeDescs) ~= "table" then
        return results
    end

    for _, treeInfo in ipairs(treeDescs) do
        local desc = treeInfo ~= nil and treeInfo.desc or nil
        if type(desc) == "table" then
            local candidates = self:tpFindTreePlaceableCandidates(screen, treeInfo)

            if tpIsDebugModeEnabled() == true then
                tpLog(string.format(
                    "treePick placeableProbe descName=%s descTitle=%s splitType=%s exactCandidates=%s mode=exactOnly",
                    tostring(desc.name),
                    tostring(desc.title),
                    tostring(treeInfo.splitType),
                    tostring(#candidates)
                ))
            end

            if #candidates == 1 and (tonumber(candidates[1].descHits) or 0) > 0 then
                local item = candidates[1].item
                if type(item) == "table" then
                    local title = tostring(desc.title or desc.name or "Baum")
                    item.tpPipetteDebugSuffix = " [Baum erkannt]"
                    table.insert(results, item)

                    if tpIsDebugModeEnabled() == true then
                        tpLog(string.format(
                            "treePick placeableMatchAccepted descName=%s descTitle=%s splitType=%s cat=%s tab=%s item=%s",
                            tostring(desc.name),
                            tostring(desc.title),
                            tostring(treeInfo.splitType),
                            tostring(candidates[1].categoryIndex),
                            tostring(candidates[1].tabIndex),
                            tostring(candidates[1].itemIndex)
                        ))
                    end
                end
            else
                local probeItem = self:tpCreateTreeProbeDisplayItem(treeInfo)
                if probeItem ~= nil then
                    table.insert(results, probeItem)
                end

                if tpIsDebugModeEnabled() == true then
                    tpLog(string.format(
                        "treePick noSafePlaceableMatch descName=%s descTitle=%s splitType=%s exactCandidates=%s mode=probeOnly",
                        tostring(desc.name),
                        tostring(desc.title),
                        tostring(treeInfo.splitType),
                        tostring(#candidates)
                    ))
                end
            end
        end
    end

    return results
end

function MapObjectFinder:tpCollectTreeDisplayItemsAtWorldPosition(screen, x, y, z)
    local treeDescs = self:tpCollectTreeDescsAtWorldPosition(x, y, z)
    if #treeDescs == 0 then
        return {}
    end

    if tpIsDebugModeEnabled() == true then
        tpLog("treePick descs=" .. tostring(#treeDescs))
    end

    local treeItems = self:tpFindTreeDisplayItemsForDescs(screen, treeDescs)
    local capped = {}
    for index, item in ipairs(treeItems or {}) do
        if index > 4 then
            break
        end
        table.insert(capped, item)
    end

    return capped
end

function MapObjectFinder:tpTryPickTreeAtWorldPosition(screen, x, y, z)
    local capped = self:tpCollectTreeDisplayItemsAtWorldPosition(screen, x, y, z)
    if #capped == 0 then
        return false
    end

    self:tpDecoratePipetteResultNames(capped)
    self.tpResultItems = capped

    if screen ~= nil then
        self:tpRefreshPipetteResultItems(screen)
        self:tpUpdatePipettePanelVisuals(screen)
        if type(capped[1]) == "table" and capped[1].tpTreeProbeOnly ~= true then
            self:tpTryPreselectFirstPipetteResult(screen)
        end
    end

    local firstItem = capped[1]
    local firstStoreItem = type(firstItem) == "table" and type(firstItem.storeItem) == "table" and firstItem.storeItem or nil
    local displayName = tostring(
        (type(firstItem) == "table" and (firstItem.tpPipetteMenuOriginalName or firstItem.name or firstItem.title))
        or (firstStoreItem ~= nil and firstStoreItem.name)
        or "Tree"
    )
    if type(firstItem) == "table" and firstItem.tpTreeProbeOnly == true then
        tpShowMessage(displayName)
    else
        tpShowMessage(string.format(tpText("TP_msg_objectDetected", "Selected: %s"), displayName))
    end

    return true
end

function MapObjectFinder:tpLogTreeProbesAtWorldPosition(x, y, z)
    if tpIsDebugModeEnabled() ~= true then
        return
    end

    x = tonumber(x)
    y = tonumber(y)
    z = tonumber(z)

    if x == nil or y == nil or z == nil then
        tpLog("treeDiag skipped reason=noWorldPosition")
        return
    end

    if type(overlapSphere) ~= "function" then
        tpLog("treeDiag skipped reason=noOverlapSphere")
        return
    end

    if CollisionFlag == nil or CollisionFlag.TREE == nil then
        tpLog("treeDiag skipped reason=noCollisionFlagTree")
        return
    end

    self.tpTreeProbeShapes = {}
    self.tpTreeProbeSeen = {}

    local radius = 2.0
    local scanY = y + 1.0
    local okScan, scanError = pcall(function()
        overlapSphere(x, scanY, z, radius, "tpOnTreeProbeShapeDetected", self, CollisionFlag.TREE, false, false, true, false)
    end)

    if okScan ~= true then
        tpLog("treeDiag scanError=" .. tostring(scanError))
        self.tpTreeProbeShapes = nil
        self.tpTreeProbeSeen = nil
        return
    end

    local shapes = self.tpTreeProbeShapes or {}
    tpLog(string.format("treeDiag scan center=%.3f,%.3f,%.3f radius=%.2f hits=%s", x, scanY, z, radius, tostring(#shapes)))

    for index, splitShapeId in ipairs(shapes) do
        if index > 12 then
            tpLog("treeDiag moreHits=" .. tostring(#shapes - 12))
            break
        end

        local exists = true
        if type(entityExists) == "function" then
            exists = entityExists(splitShapeId) == true
        end

        local hasSplitClass = false
        if exists == true and type(getHasClassId) == "function" and ClassIds ~= nil and ClassIds.MESH_SPLIT_SHAPE ~= nil then
            local okClass, value = pcall(function()
                return getHasClassId(splitShapeId, ClassIds.MESH_SPLIT_SHAPE)
            end)
            hasSplitClass = okClass == true and value == true
        end

        local splitType = nil
        if exists == true and type(getSplitType) == "function" then
            splitType = self:tpSafeCall("getSplitType", function()
                return getSplitType(splitShapeId)
            end)
        end

        local isSplit = nil
        if exists == true and type(getIsSplitShapeSplit) == "function" then
            isSplit = self:tpSafeCall("getIsSplitShapeSplit", function()
                return getIsSplitShapeSplit(splitShapeId)
            end)
        end

        local rigidBodyType = nil
        if exists == true and type(getRigidBodyType) == "function" then
            rigidBodyType = self:tpSafeCall("getRigidBodyType", function()
                return getRigidBodyType(splitShapeId)
            end)
        end

        local nodeName = nil
        if exists == true and type(getName) == "function" then
            nodeName = self:tpSafeCall("getName", function()
                return getName(splitShapeId)
            end)
        end

        local px, py, pz = nil, nil, nil
        if exists == true and type(getWorldTranslation) == "function" then
            local okPos, rx, ry, rz = pcall(function()
                return getWorldTranslation(splitShapeId)
            end)
            if okPos == true then
                px, py, pz = rx, ry, rz
            end
        end

        local desc = nil
        if g_treePlantManager ~= nil and type(g_treePlantManager.getTreeTypeDescFromSplitType) == "function" and splitType ~= nil then
            local okDesc, value = pcall(function()
                return g_treePlantManager:getTreeTypeDescFromSplitType(splitType)
            end)
            if okDesc == true then
                desc = value
            else
                tpLog("treeDiag descError splitType=" .. tostring(splitType) .. " error=" .. tostring(value))
            end
        end

        if desc ~= nil then
            tpLog(string.format(
                "treeDiag hit index=%s node=%s exists=%s splitClass=%s splitType=%s rigidBody=%s isSplit=%s pos=%.3f,%.3f,%.3f descIndex=%s descName=%s descTitle=%s xml=%s i3d=%s",
                tostring(index),
                tostring(nodeName),
                tostring(exists),
                tostring(hasSplitClass),
                tostring(splitType),
                tostring(rigidBodyType),
                tostring(isSplit),
                tonumber(px) or 0,
                tonumber(py) or 0,
                tonumber(pz) or 0,
                tostring(desc.index),
                tostring(desc.name),
                tostring(desc.title),
                tostring(desc.xmlFilename),
                tostring(desc.i3dFilename)
            ))
        else
            tpLog(string.format(
                "treeDiag hit index=%s node=%s exists=%s splitClass=%s splitType=%s rigidBody=%s isSplit=%s pos=%.3f,%.3f,%.3f desc=nil",
                tostring(index),
                tostring(nodeName),
                tostring(exists),
                tostring(hasSplitClass),
                tostring(splitType),
                tostring(rigidBodyType),
                tostring(isSplit),
                tonumber(px) or 0,
                tonumber(py) or 0,
                tonumber(pz) or 0
            ))
        end
    end

    self.tpTreeProbeShapes = nil
    self.tpTreeProbeSeen = nil
end


function MapObjectFinder:pickTextureAtCurrentMousePosition()
    local x, y, z = self:findMouseWorldPosition()

    if x == nil then
        tpShowMessage(tpText("TP_msg_noPosition", "No target found."))
        return
    end

    local rawX, rawY, rawZ = x, y, z

    if tpIsDebugModeEnabled() == true and type(self.tpBuildAlignedDebugGridPosition) == "function" then
        local okGrid, grid = pcall(function()
            return self:tpBuildAlignedDebugGridPosition(rawX, rawY, rawZ)
        end)

        if okGrid == true and type(grid) == "table" and tonumber(grid.centerX) ~= nil and tonumber(grid.centerZ) ~= nil then
            x = tonumber(grid.centerX)
            z = tonumber(grid.centerZ)
            self.tpLastSamplingGrid = grid
            self.tpLastRawSampleX = rawX
            self.tpLastRawSampleY = rawY
            self.tpLastRawSampleZ = rawZ
        else
            self.tpLastSamplingGrid = nil
            self.tpLastRawSampleX = rawX
            self.tpLastRawSampleY = rawY
            self.tpLastRawSampleZ = rawZ
        end
    else
        self.tpLastSamplingGrid = nil
        self.tpLastRawSampleX = rawX
        self.tpLastRawSampleY = rawY
        self.tpLastRawSampleZ = rawZ
    end

    self.lastPipetteWorldX = x
    self.lastPipetteWorldY = y
    self.lastPipetteWorldZ = z

    self:tpBuildFoliageDebugOverlayForWorld(x, y, z)

    if tpIsDebugModeEnabled() == true then
        local okTreeDiag, treeDiagError = pcall(function()
            self:tpLogTreeProbesAtWorldPosition(x, y, z)
        end)
        if okTreeDiag ~= true then
            tpLog("treeDiagError=" .. tostring(treeDiagError))
        end
    end
   if type(self.tpLastMapFoliagePaintAttempt) == "table" then
        local snap = self.tpLastMapFoliagePaintAttempt
        tpLog(string.format(
            "mapFoliageLastPaintBeforePick layer=%s state=%s brush=%s name=%s note=compareCurrentScanWithPaintAttempt",
            tostring(snap.layer or ""),
            tostring(snap.state or ""),
            tostring(snap.brush or ""),
            tostring(snap.name or "")
        ))
    end
    if self.tpLastSamplingGrid ~= nil then
        local grid = self.tpLastSamplingGrid
        tpLog(string.format("pickGridSample mode=%s layer=%s cell=%.3fx%.3f center=%.3f,%.3f raw=%.3f,%.3f", tostring(grid.boundaryMode or "?"), tostring(grid.layerName or "?"), tonumber(grid.cellX) or 0, tonumber(grid.cellZ) or 0, tonumber(grid.centerX) or 0, tonumber(grid.centerZ) or 0, tonumber(rawX) or 0, tonumber(rawZ) or 0))
    end
    if TP_HEAVY_DIAGNOSTICS == true then
        self:tpLogFoliageStructureOnce()
        self:tpLogFoliageFunctionAvailabilityOnce()
        local okFoliageProbe, foliageProbeError = pcall(function()
            self:tpProbeFoliageAtCurrentPick()
        end)
        if okFoliageProbe ~= true then
            tpLog("foliageProbeError=" .. tostring(foliageProbeError))
        end

        local okOfficialTrace, officialTraceError = pcall(function()
            self:tpLogOfficialFoliageTraceAtCurrentPick()
        end)
        if okOfficialTrace ~= true then
            tpLog("officialFoliageTraceError=" .. tostring(officialTraceError))
        end
    end

    self.tpResultItems = {}
    self:tpResetLayerMenuOutput()
    self.tpLastTrackedManualSelectionKey = nil

    local screen = self:tpResolveConstructionLogicScreen()
    if screen ~= nil then
        self:tpRefreshPipetteResultItems(screen)
        self:tpUpdatePipettePanelVisuals(screen)
    end

    local objectResultItems = self:tpCollectPlaceableDisplayItemsAtCurrentRaycast(screen) or {}

    local treeResultItems = {}
    if screen ~= nil then
        local okTreeItems, collectedTreeItems = pcall(function()
            return self:tpCollectTreeDisplayItemsAtWorldPosition(screen, x, y, z)
        end)
        if okTreeItems == true and type(collectedTreeItems) == "table" then
            treeResultItems = collectedTreeItems
        elseif okTreeItems ~= true then
            tpLog("treePick collectError=" .. tostring(collectedTreeItems))
        end
    end

    if #(objectResultItems or {}) == 0 and #(treeResultItems or {}) == 0 then
        if self:tpTryHandleStaticMapObjectHit(screen) then
            self.nextArmedStatusRefreshAt = 0
            return
        end
    end

    if TP_HEAVY_DIAGNOSTICS == true then
        self:tpLogConstructionStructureOnce(screen)
        self:tpLogConstructionBrushRuntime(screen, "afterPickBeforeCandidates")
        self:tpLogFoliageMenuItemInternals(screen, "afterPickBeforeCandidates")
    end

    local visibleCandidates = self:tpCollectCurrentPaintTabCandidates() or {}
    if TP_HEAVY_DIAGNOSTICS == true then
        tpLog("visiblePaintCandidates=" .. tostring(#visibleCandidates))
        for index, candidate in ipairs(visibleCandidates) do
            if index > 80 then
                break
            end
            tpLog(string.format(
                "visibleCandidate index=%s name=%s brush=%s overlay=%s cat=%s tab=%s item=%s",
                tostring(index),
                tostring(candidate.name or candidate.itemName or "<nil>"),
                tostring(candidate.brushParameter or "<nil>"),
                tostring(candidate.terrainOverlayLayer or candidate.overlayLayer or candidate.terrainLayer or "<nil>"),
                tostring(candidate.categoryIndex or "<nil>"),
                tostring(candidate.tabIndex or "<nil>"),
                tostring(candidate.itemIndex or "<nil>")
            ))
        end
    end
    local resultMatches = {}
    local seen = {}

    for _, candidate in ipairs(visibleCandidates) do
        local sourceItem = candidate ~= nil and candidate.sourceItem or nil
        local uniqueKey = candidate ~= nil and table.concat({
            tostring(candidate.name or candidate.itemName or "<nil>"),
            tostring(candidate.brushParameter or "<nil>"),
            tostring(candidate.terrainOverlayLayer or candidate.overlayLayer or candidate.terrainLayer or "<nil>")
        }, "|") or nil

        if sourceItem ~= nil and uniqueKey ~= nil and seen[uniqueKey] ~= true then
            seen[uniqueKey] = true
            table.insert(resultMatches, {
                candidate = candidate,
                sourceItem = sourceItem,
                uniqueKey = uniqueKey,
                source = "pipetteResult"
            })
        end
    end

    table.sort(resultMatches, function(a, b)
        local aCandidate = a.candidate or {}
        local bCandidate = b.candidate or {}
        local aName = tostring(aCandidate.name or aCandidate.itemName or "")
        local bName = tostring(bCandidate.name or bCandidate.itemName or "")
        if aName == bName then
            return tostring(aCandidate.brushParameter or "") < tostring(bCandidate.brushParameter or "")
        end
        return aName < bName
    end)

    local rankedMatches, previewSummary = self:tpRankCandidateMatchesBySubLayerCompetition(resultMatches)

    screen = screen or self:tpResolveConstructionLogicScreen()
    local layerMenuItems = {}
    local foliageMenuMatches = self:tpCollectFoliageMenuCandidatesAtCurrentPick(screen)
    for _, match in ipairs(foliageMenuMatches or {}) do
        if match ~= nil and match.sourceItem ~= nil then
            table.insert(layerMenuItems, match.sourceItem)
        end
    end

    local finalResultItems = {}
    local usedFinalItems = {}

    for _, item in ipairs(objectResultItems or {}) do
        if item ~= nil and usedFinalItems[item] ~= true then
            usedFinalItems[item] = true
            table.insert(finalResultItems, item)
        end
    end

    for _, item in ipairs(treeResultItems or {}) do
        if item ~= nil and usedFinalItems[item] ~= true then
            usedFinalItems[item] = true
            table.insert(finalResultItems, item)
        end
    end

    for _, item in ipairs(layerMenuItems or {}) do
        if item ~= nil and usedFinalItems[item] ~= true then
            usedFinalItems[item] = true
            table.insert(finalResultItems, item)
        end
    end

    if TP_FOLIAGE_TEST_SUPPRESS_GROUND_RESULTS ~= true then
        for _, entry in ipairs(rankedMatches or {}) do
            local item = entry ~= nil and entry.sourceItem or nil
            if item ~= nil and usedFinalItems[item] ~= true then
                usedFinalItems[item] = true
                table.insert(finalResultItems, item)
            end
        end
    else
        tpLog("groundResultDisplaySuppressed=true rankedGroundMatches=" .. tostring(#(rankedMatches or {})))
    end


    local cappedFinalResultItems = {}
    for index, item in ipairs(finalResultItems or {}) do
        if index > 10 then
            break
        end
        table.insert(cappedFinalResultItems, item)
    end
    finalResultItems = cappedFinalResultItems

    if tpIsDebugModeEnabled() == true then
        tpLog("pipetteMixedResults objectItems=" .. tostring(#(objectResultItems or {})) .. " treeItems=" .. tostring(#(treeResultItems or {})) .. " foliageItems=" .. tostring(#(layerMenuItems or {})) .. " groundItems=" .. tostring(#(rankedMatches or {})) .. " finalItems=" .. tostring(#(finalResultItems or {})))
    end

    self:tpDecoratePipetteResultNames(finalResultItems)
    self.tpResultItems = finalResultItems

    if screen ~= nil then
        self:tpRefreshPipetteResultItems(screen)
        if #finalResultItems > 0 then
            self:tpTryPreselectFirstPipetteResult(screen)
            if TP_HEAVY_DIAGNOSTICS == true then
                self:tpLogConstructionBrushRuntime(screen, "afterPipetteResultPreselect")
            end
        elseif screen.itemList ~= nil then
            if screen.itemList.setSelectedIndex ~= nil then
                pcall(function()
                    screen.itemList:setSelectedIndex(0)
                end)
            else
                pcall(function()
                    screen.itemList.selectedIndex = 0
                end)
            end
        end
        self:tpUpdatePipettePanelVisuals(screen)
    end

    if #finalResultItems == 0 and self.tpLastFoliageRecognitionFallback == true then
        tpLog("redFallbackGridActive=true reason=noSafeFoliageResult")
        self.tpPipettePanelStatusText = tpText("TP_msg_noBuildMenuEntryHere", "No selectable construction menu entry found at this position.")
        if screen ~= nil then
            self:tpUpdatePipettePanelVisuals(screen)
        end
    end


    self.nextArmedStatusRefreshAt = 0
end


local function tpTryGetGuiShowDialogSource()
    if g_gui == nil then
        return nil, nil
    end

    if type(g_gui.showDialog) == "function" then
        return g_gui, "g_gui"
    end

    local mt = getmetatable(g_gui)
    if type(mt) == "table" and type(mt.showDialog) == "function" then
        return mt, "g_gui.metatable"
    end

    if type(mt) == "table" and type(mt.__index) == "table" and type(mt.__index.showDialog) == "function" then
        return mt.__index, "g_gui.metatable.__index"
    end

    return nil, nil
end

function MapObjectFinder:tpArmPipetteWorldClickDialogSuppression()
    self.tpSuppressNextObjectInfoDialog = true
    local now = getTimeSec ~= nil and getTimeSec() or 0
    self.tpSuppressNextObjectInfoDialogUntil = now + 0.75
end

function MapObjectFinder:tpInstallShowDialogSuppressionHook()
    if self.tpShowDialogSuppressionHookInstalled == true then
        return true
    end

    local source, label = tpTryGetGuiShowDialogSource()
    if source == nil then
        return false
    end

    local originalShowDialog = source.showDialog
    source.showDialog = function(gui, ...)
        if MapObjectFinder ~= nil and MapObjectFinder.tpSuppressNextObjectInfoDialog == true then
            local now = getTimeSec ~= nil and getTimeSec() or 0
            local untilTime = tonumber(MapObjectFinder.tpSuppressNextObjectInfoDialogUntil) or 0

            if now <= untilTime then
                MapObjectFinder.tpSuppressNextObjectInfoDialog = false
                MapObjectFinder.tpSuppressNextObjectInfoDialogUntil = 0
                return
            end

            MapObjectFinder.tpSuppressNextObjectInfoDialog = false
            MapObjectFinder.tpSuppressNextObjectInfoDialogUntil = 0
        end

        return originalShowDialog(gui, ...)
    end

    self.tpShowDialogSuppressionHookInstalled = true
    return true
end

function MapObjectFinder:tpClearExpiredObjectInfoDialogSuppression()
    if self.tpSuppressNextObjectInfoDialog ~= true then
        return
    end

    local now = getTimeSec ~= nil and getTimeSec() or 0
    local untilTime = tonumber(self.tpSuppressNextObjectInfoDialogUntil) or 0
    if now > untilTime then
        self.tpSuppressNextObjectInfoDialog = false
        self.tpSuppressNextObjectInfoDialogUntil = 0
    end
end


addModEventListener(MapObjectFinder)
