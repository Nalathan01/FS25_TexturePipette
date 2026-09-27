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

local TP_MOD_DIRECTORY = g_currentModDirectory or ""

local TP_TREE_SCAN_RADIUS = 1.40

local tpExtractTreeNameFromHierarchy

local function tpLog(message)
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
        MapObjectFinder:tpEnsureSearchResultItemSlot(self)
        MapObjectFinder:tpInvalidateSearchIndex(self)
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

function MapObjectFinder:tpFindSearchScreenIndices(screen)
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
                        if type(tab) == "table" and tostring(tab.name or "") == "TP_SEARCH_TAB" then
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

function MapObjectFinder:tpIsSearchResultTabActive(screen)
    local categoryIndex, tabIndex = self:tpFindSearchScreenIndices(screen)
    return categoryIndex ~= nil
        and tabIndex ~= nil
        and screen ~= nil
        and tonumber(screen.currentCategory) == tonumber(categoryIndex)
        and tonumber(screen.currentTab) == tonumber(tabIndex)
end

function MapObjectFinder:tpEnsureSearchResultItemSlot(screen)
    if screen == nil
        or type(screen.categories) ~= "table"
        or type(screen.items) ~= "table" then
        return false
    end

    local categoryIndex, tabIndex = self:tpFindSearchScreenIndices(screen)
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

    local container = parentElement:getDescendantById("tpPipettePanelContainer") or parentElement.elements[after]
    local button = container:getDescendantById("tpPipetteActivateButton")
    local buttonText = container:getDescendantById("tpPipetteActivateText")
    local candidateText = container:getDescendantById("tpPipetteStatusText") or container:getDescendantById("tpPipetteCandidateText")
    local statusText = candidateText

    local searchContainer = parentElement:getDescendantById("tpSearchPanelContainer")
    local searchInput = parentElement:getDescendantById("tpSearchTextInput")
    local searchPlaceholder = parentElement:getDescendantById("tpSearchPlaceholderText")

    local subPos = screen.subCategorySelector.position
    local subSize = screen.subCategorySelector.size

    container:setPosition(subPos[1], subPos[2])
    container:setSize(subSize[1], 0.075)
    container:setVisible(false)
    container:updateAbsolutePosition()

    if button ~= nil then
        button.target = screen
    end

    if searchContainer ~= nil then
        searchContainer:setPosition(subPos[1], subPos[2])
        searchContainer:setSize(subSize[1], 0.075)
        searchContainer:setVisible(false)
        searchContainer:updateAbsolutePosition()
    end

    if searchInput ~= nil then
        searchInput.target = screen
    end

    state.container = container
    state.button = button
    state.buttonText = buttonText
    state.candidateText = candidateText
    state.statusText = statusText
    state.searchContainer = searchContainer
    state.searchInput = searchInput
    state.searchPlaceholder = searchPlaceholder
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
        screen.itemList:reloadData()
    end

    return true
end

local function tpNormalizeSearchText(text)
    if text == nil then
        return ""
    end

    return string.lower(tostring(text))
end

local function tpSearchWordScore(word, field)
    if word == "" or field == "" then
        return 0
    end

    if field == word then
        return 100
    end

    if string.sub(field, 1, string.len(word)) == word then
        return 50
    end

    local searchPattern = " " .. word
    if string.find(" " .. field .. " ", searchPattern .. " ", 1, true) ~= nil then
        return 30
    end

    if string.find(field, word, 1, true) ~= nil then
        return 10
    end

    return 0
end

local TP_SEARCH_CATEGORY_ALIASES = {
    ["stall"] = { "husbandry", "animal" },
    ["ställe"] = { "husbandry", "animal" },
    ["staelle"] = { "husbandry", "animal" },
    ["stalle"] = { "husbandry", "animal" },
    ["tier"] = { "husbandry", "animal" },
    ["tiere"] = { "husbandry", "animal" },
    ["barn"] = { "husbandry", "animal" },
    ["animal"] = { "husbandry", "animal" },
    ["animals"] = { "husbandry", "animal" },
    ["husbandry"] = { "husbandry", "animal" },
    ["étable"] = { "husbandry", "animal" },
    ["etable"] = { "husbandry", "animal" },
    ["animaux"] = { "husbandry", "animal" },
    ["élevage"] = { "husbandry", "animal" },
    ["elevage"] = { "husbandry", "animal" }
}

local function tpMatchesCategoryAlias(word, entry)
    local fragments = TP_SEARCH_CATEGORY_ALIASES[word]
    if fragments == nil or entry == nil then
        return false
    end

    for _, fragment in ipairs(fragments) do
        if (entry.categoryNameField ~= nil and string.find(entry.categoryNameField, fragment, 1, true) ~= nil)
            or (entry.tabNameField ~= nil and string.find(entry.tabNameField, fragment, 1, true) ~= nil) then
            return true
        end
    end

    return false
end

function MapObjectFinder:tpGetSearchState(screen)
    if screen == nil then
        return nil
    end

    if screen.tpSearchState == nil then
        screen.tpSearchState = {
            index = nil,
            lastQuery = nil
        }
    end

    return screen.tpSearchState
end

function MapObjectFinder:tpInvalidateSearchIndex(screen)
    local state = self:tpGetSearchState(screen)
    if state ~= nil then
        state.index = nil
        state.lastQuery = nil
    end
end

local TP_SEARCH_CONCEPT_ALIASES = {
    ["baum"] = "tree",
    ["bäume"] = "tree",
    ["baeume"] = "tree",
    ["baume"] = "tree",
    ["tree"] = "tree",
    ["trees"] = "tree",
    ["arbre"] = "tree",
    ["arbres"] = "tree"
}

local function tpIsTreeStoreItem(item)
    if type(item) ~= "table" or type(item.storeItem) ~= "table" then
        return false
    end

    local storeItem = item.storeItem
    if storeItem.treeType ~= nil or storeItem.treeSaplingType ~= nil then
        return true
    end

    if type(storeItem.brush) == "table" then
        local brush = storeItem.brush
        if brush.treeType ~= nil or brush.treeSaplingType ~= nil then
            return true
        end
    end

    return false
end

function MapObjectFinder:tpGetSearchItemDisplayName(item)
    if type(item) ~= "table" then
        return ""
    end

    local storeItem = type(item.storeItem) == "table" and item.storeItem or nil
    return tostring(
        item.title
        or item.name
        or (storeItem ~= nil and (storeItem.title or storeItem.name))
        or ""
    )
end

function MapObjectFinder:tpBuildSearchIndex(screen)
    local index = {}

    if screen == nil or type(screen.categories) ~= "table" or type(screen.items) ~= "table" then
        tpLog(string.format(
            "tpBuildSearchIndex: aborted early (screen=%s categories=%s items=%s)",
            tostring(screen ~= nil),
            tostring(screen ~= nil and type(screen.categories)),
            tostring(screen ~= nil and type(screen.items))
        ))
        return index
    end

    local scannedCategories = 0
    local scannedTabs = 0
    local emptyTabItemsSlots = 0

    for categoryIndex, category in ipairs(screen.categories) do
        local categoryName = type(category) == "table" and tostring(category.name or "") or ""
        if categoryName ~= "TP_PIPETTE_MENU" then
            scannedCategories = scannedCategories + 1
            local categoryTitle = type(category) == "table" and tostring(category.title or "") or ""
            local categoryTabsPresent = type(screen.items[categoryIndex]) == "table"
            local categoryTabs = categoryTabsPresent and screen.items[categoryIndex] or {}

            if not categoryTabsPresent then
                emptyTabItemsSlots = emptyTabItemsSlots + 1
            end

            for tabIndex, tabItems in pairs(categoryTabs) do
                if type(tabItems) == "table" then
                    scannedTabs = scannedTabs + 1
                    local tab = type(category) == "table" and type(category.tabs) == "table" and category.tabs[tabIndex] or nil
                    local tabTitle = type(tab) == "table" and tostring(tab.title or "") or ""
                    local tabName = type(tab) == "table" and tostring(tab.name or "") or ""

                    for _, item in ipairs(tabItems) do
                        if type(item) == "table" then
                            table.insert(index, {
                                item = item,
                                nameField = tpNormalizeSearchText(self:tpGetSearchItemDisplayName(item)),
                                categoryField = tpNormalizeSearchText(categoryTitle),
                                tabField = tpNormalizeSearchText(tabTitle),
                                categoryNameField = tpNormalizeSearchText(categoryName),
                                tabNameField = tpNormalizeSearchText(tabName),
                                conceptTags = tpIsTreeStoreItem(item) and { tree = true } or {}
                            })
                        end
                    end
                end
            end
        end
    end

    tpLog(string.format(
        "tpBuildSearchIndex: categories=%d tabs=%d emptyCategorySlots=%d indexedEntries=%d",
        scannedCategories, scannedTabs, emptyTabItemsSlots, #index
    ))

    return index
end

function MapObjectFinder:tpPerformSearch(screen, queryText)
    local state = self:tpGetSearchState(screen)
    if state == nil then
        return {}
    end

    if state.index == nil then
        state.index = self:tpBuildSearchIndex(screen)
    end

    local normalizedQuery = tpNormalizeSearchText(queryText)
    state.lastQuery = normalizedQuery

    if normalizedQuery == "" then
        tpLog("tpPerformSearch: empty query, no results")
        return {}
    end

    local words = {}
    for word in string.gmatch(normalizedQuery, "%S+") do
        table.insert(words, word)
    end

    if #words == 0 then
        tpLog(string.format("tpPerformSearch: query %q had no words after split", normalizedQuery))
        return {}
    end

    local scoredResults = {}

    for _, entry in ipairs(state.index) do
        local totalScore = 0
        local allWordsMatch = true

        for _, word in ipairs(words) do
            local bestScore = math.max(
                tpSearchWordScore(word, entry.nameField),
                tpSearchWordScore(word, entry.categoryField),
                tpSearchWordScore(word, entry.tabField)
            )

            local conceptTag = TP_SEARCH_CONCEPT_ALIASES[word]
            if conceptTag ~= nil and entry.conceptTags ~= nil and entry.conceptTags[conceptTag] == true then
                bestScore = math.max(bestScore, 60)
            end

            if tpMatchesCategoryAlias(word, entry) then
                bestScore = math.max(bestScore, 40)
            end

            if bestScore <= 0 then
                allWordsMatch = false
                break
            end

            totalScore = totalScore + bestScore
        end

        if allWordsMatch then
            table.insert(scoredResults, { item = entry.item, score = totalScore, name = entry.nameField })
        end
    end

    table.sort(scoredResults, function(a, b)
        if a.score == b.score then
            return a.name < b.name
        end
        return a.score > b.score
    end)

    local resultItems = {}
    for _, result in ipairs(scoredResults) do
        table.insert(resultItems, result.item)
    end

    tpLog(string.format(
        "tpPerformSearch: query=%q indexSize=%d matches=%d",
        normalizedQuery, #state.index, #resultItems
    ))

    return resultItems
end

function MapObjectFinder:tpApplySearchResults(screen, resultItems)
    local categoryIndex, tabIndex = self:tpFindSearchScreenIndices(screen)
    if categoryIndex == nil or tabIndex == nil or screen == nil or type(screen.items) ~= "table" then
        tpLog(string.format(
            "tpApplySearchResults: could not resolve search tab (categoryIndex=%s tabIndex=%s)",
            tostring(categoryIndex), tostring(tabIndex)
        ))
        return false
    end

    if type(screen.items[categoryIndex]) ~= "table" then
        screen.items[categoryIndex] = {}
    end

    screen.items[categoryIndex][tabIndex] = resultItems or {}

    local isActive = self:tpIsSearchResultTabActive(screen)
    local reloaded = false
    if isActive
        and screen.itemList ~= nil
        and screen.itemList.reloadData ~= nil then
        screen.itemList:reloadData()
        reloaded = true
    end

    tpLog(string.format(
        "tpApplySearchResults: catIdx=%s tabIdx=%s results=%d tabActive=%s reloaded=%s",
        tostring(categoryIndex), tostring(tabIndex), #(resultItems or {}), tostring(isActive), tostring(reloaded)
    ))

    return true
end

function MapObjectFinder:tpOnSearchTextChanged(screen, text)
    if screen == nil then
        return
    end

    local results = self:tpPerformSearch(screen, text)
    self:tpApplySearchResults(screen, results)

    local uiState = self:tpGetPipetteUiState(screen)
    if uiState ~= nil and uiState.searchPlaceholder ~= nil and uiState.searchPlaceholder.setVisible ~= nil then
        uiState.searchPlaceholder:setVisible(tostring(text or "") == "")
    end
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
    if state ~= nil and state.searchContainer ~= nil then
        state.searchContainer:setVisible(self:tpIsSearchResultTabActive(screen))
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
        local class = g_constructionBrushTypeManager:getClassObjectByTypeName("select")
        if class ~= nil and type(class.new) == "function" then
            local createdBrush = class.new(nil, screen.cursor)
            if createdBrush ~= nil then
                selectorBrush = createdBrush
                screen.selectorBrush = createdBrush
            end
        end
    end

    if selectorBrush ~= nil then
        screen:setBrush(selectorBrush, true)
        return true
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

function ConstructionScreen:onTpSearchTextChanged(element, text)
    if MapObjectFinder == nil then
        return
    end

    MapObjectFinder:tpOnSearchTextChanged(self, text)
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

local function tpAfterConstructionTabOrCategoryChanged(screen, ...)
    if MapObjectFinder == nil or screen == nil then
        return
    end

    if not MapObjectFinder:tpIsSearchResultTabActive(screen) then
        return
    end

    local uiState = MapObjectFinder:tpGetPipetteUiState(screen)

    local currentText = ""
    if uiState ~= nil and uiState.searchInput ~= nil and uiState.searchInput.getText ~= nil then
        local text = uiState.searchInput:getText()
        if text ~= nil then
            currentText = text
        end
    end

    MapObjectFinder:tpOnSearchTextChanged(screen, currentText)

    if uiState == nil or uiState.searchInput == nil then
        return
    end

    if uiState.searchInput.setFocus ~= nil then
        uiState.searchInput:setFocus()
    end
end

if ConstructionScreen ~= nil and ConstructionScreen.setCurrentCategory ~= nil then
    ConstructionScreen.setCurrentCategory = Utils.appendedFunction(ConstructionScreen.setCurrentCategory, tpAfterConstructionTabOrCategoryChanged)
end

if ConstructionScreen ~= nil and ConstructionScreen.setCurrentTab ~= nil then
    ConstructionScreen.setCurrentTab = Utils.appendedFunction(ConstructionScreen.setCurrentTab, tpAfterConstructionTabOrCategoryChanged)
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

    if button == 1 and isDown == true then
        tpLog("mouseClick armed=" .. tostring(self.isPipetteArmed) .. " screenOpen=" .. tostring(self:isConstructionScreenOpen()) .. " mouseX=" .. tostring(mouseX) .. " isLikelyWorldArea=" .. tostring(isLikelyWorldArea))
    end

    if self.isPipetteArmed
        and self:isConstructionScreenOpen()
        and button == 1
        and isDown == true then

        if not isLikelyWorldArea then
            tpLog("pipetteClick ignored, click was outside world area (mouseX=" .. tostring(mouseX) .. ")")
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

function MapObjectFinder:tpTrackManualPipetteSelection()
end

function MapObjectFinder:update(dt)
    self:tpInstallShowDialogSuppressionHook()
    self:tpClearExpiredObjectInfoDialogSuppression()
    self:updatePersistentArmedStatus()
    self:tpUpdatePipetteResultArea()
    self:tpRestorePipetteDecoratedNames()
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

    if getName ~= nil and entityExists(nodeId) then
        local name = getName(nodeId)
        if name ~= nil and tostring(name) ~= "" then
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
        if current == nil or current == 0 or visited[current] == true or not entityExists(current) then
            break
        end
        visited[current] = true
        local name = nil
        if type(getName) == "function" then
            local value = getName(current)
            if value ~= nil then
                name = tostring(value)
            end
        end
        if name ~= nil and name ~= "" then
            table.insert(parts, 1, name)
        end
        current = getParent(current)
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
    local treeName = tpExtractTreeNameFromHierarchy(hierarchy)

    self.tpResultItems = {}
    self:tpResetLayerMenuOutput()

    local statusLabel = treeName ~= nil and string.format("%s: %s", tpText("TP_label_treeDetected", "Tree detected"), treeName) or label
    self.tpPipettePanelStatusText = string.format(tpText("TP_msg_staticNotInBuildMenu", "No construction menu entry at this position. Static map object: %s"), statusLabel)
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

local function tpCollectAllStoreItemsSafe()
    local items = {}

    if g_storeManager == nil then
        return items
    end

    local result = nil
    if g_storeManager.getItems ~= nil then
        result = g_storeManager:getItems()
    end

    if type(result) == "table" then
        for _, item in ipairs(result) do
            table.insert(items, item)
        end
    end

    if #items == 0 and type(g_storeManager.items) == "table" then
        for _, item in ipairs(g_storeManager.items) do
            table.insert(items, item)
        end
    end

    return items
end

function MapObjectFinder:tpFindStoreItemByFilenameFallback(xmlFilename)
    local wanted = tpNormalizeComparableFilename(xmlFilename)
    if wanted == nil then
        return nil
    end

    for _, item in ipairs(tpCollectAllStoreItemsSafe()) do
        if type(item) == "table" then
            local itemFilename = tpNormalizeComparableFilename(
                item.xmlFilename or item.filename or item.configFileName
            )
            if itemFilename ~= nil and itemFilename == wanted then
                return item
            end
        end
    end

    return nil
end

function MapObjectFinder:tpResolveStoreItemFromPlaceableObject(object)
    if object == nil or g_storeManager == nil or g_storeManager.getItemByXMLFilename == nil then
        return nil, nil
    end

    local xmlFilename = object.configFileName or object.xmlFilename
    if xmlFilename == nil or tostring(xmlFilename) == "" then
        return nil, nil
    end

    local storeItem = g_storeManager:getItemByXMLFilename(xmlFilename)

    if storeItem ~= nil then
        return storeItem, xmlFilename
    end

    local fallbackItem = self:tpFindStoreItemByFilenameFallback(xmlFilename)
    if fallbackItem ~= nil then
        return fallbackItem, xmlFilename
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
        return nil
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

    overlapSphere(x, scanY, z, radius, "tpOnPlaceableNearbyShapeDetected", self, mask, false, false, true, false)

    local rawShapes = self.tpPlaceableNearbyShapes or {}
    self.tpPlaceableNearbyShapes = nil
    self.tpPlaceableNearbySeen = nil

    if #rawShapes == 0 then
        return results
    end

    local seenObjects = {}

    for _, shapeId in ipairs(rawShapes) do
        local currentNode = shapeId
        local visited = {}

        for _ = 1, 16 do
            if currentNode == nil or currentNode == 0 or visited[currentNode] == true or not entityExists(currentNode) then
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

            currentNode = getParent(currentNode)
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

    raycastClosest(
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
                local numericSubLayerId = tonumber(getTerrainLayerSubLayer(terrainRoot, overlayLayer, subIndex))
                if numericSubLayerId ~= nil and numericSubLayerId >= 0 then
                    local sampleCount = 0
                    local failCount = 0
                    local positiveCount = 0
                    local total = 0
                    local maxValue = 0
                    local centerValue = nil

                    for _, dx in ipairs(offsets) do
                        for _, dz in ipairs(offsets) do
                            local layerValue = getTerrainLayerAtWorldPos(
                                terrainRoot,
                                numericSubLayerId,
                                (tonumber(x) or 0) + dx,
                                tonumber(y) or 0,
                                (tonumber(z) or 0) + dz
                            )

                            if layerValue ~= nil then
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

    if screen.itemList.setSelectedIndex ~= nil then
        screen.itemList:setSelectedIndex(1)
    elseif screen.itemList.setSelectedItem ~= nil then
        screen.itemList:setSelectedItem(1)
    else
        screen.itemList.selectedIndex = 1
    end

    return true
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

    local function resolvePlaneId(foliage)
        if type(foliage) ~= "table" then
            return nil
        end

        local planeId = tonumber(foliage.terrainDataPlaneId)
        if planeId ~= nil and planeId > 0 and entityExists(planeId) then
            return planeId
        end

        local layerName = tostring(foliage.layerName or foliage.foliageLayerName or foliage.name or "")
        if layerName ~= "" and type(getTerrainDataPlaneByName) == "function" and g_currentMission ~= nil and g_currentMission.terrainRootNode ~= nil then
            local plane = tonumber(getTerrainDataPlaneByName(g_currentMission.terrainRootNode, layerName))
            if plane ~= nil and plane > 0 and entityExists(plane) then
                return plane
            end
        end

        return nil
    end

    local function sampleDensity(planeId, sampleX, sampleZ)
        if type(getDensityAtWorldPos) ~= "function" or planeId == nil or planeId <= 0 or not entityExists(planeId) then
            return nil
        end

        return tonumber(getDensityAtWorldPos(planeId, sampleX, y or 0, sampleZ))
    end

    local function sampleDensityFull(planeId, sampleX, sampleZ)
        if type(getDensityAtWorldPos) ~= "function" or planeId == nil or planeId <= 0 or not entityExists(planeId) then
            return nil, nil, nil
        end

        local density = tonumber(getDensityAtWorldPos(planeId, sampleX, y or 0, sampleZ))

        local state = nil
        if type(getDensityStatesAtWorldPos) == "function" then
            state = tonumber(getDensityStatesAtWorldPos(planeId, sampleX, y or 0, sampleZ))
        end

        local typeIndex = nil
        if type(getDensityTypeIndexAtWorldPos) == "function" then
            typeIndex = tonumber(getDensityTypeIndexAtWorldPos(planeId, sampleX, y or 0, sampleZ))
        end

        return density, state, typeIndex
    end

    local function resolvePlaneAndTypeByName(layerName)
        if layerName == nil or layerName == "" or type(getTerrainDataPlaneByName) ~= "function" or g_currentMission == nil or g_currentMission.terrainRootNode == nil then
            return nil, nil
        end

        local planeId, typeIndex = getTerrainDataPlaneByName(g_currentMission.terrainRootNode, layerName)
        planeId = tonumber(planeId)

        if planeId ~= nil and planeId > 0 and entityExists(planeId) then
            return planeId, tonumber(typeIndex)
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
        if byNamePlaneId ~= nil and byNamePlaneId > 0 then
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
            existingPaint = foliageSystem:getFoliagePaintByName(layerName)
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
                tpLog("mapOnlyVisualFoliageResultSuppressed layer=" .. tostring(unresolvedLayer.layerName or "") .. " reason=conservativeModMapCleanup")
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
                    imageName = string.gsub(imageName, "\\", "/")
                    imageName = string.match(imageName, "([^/]+)%.%w+$") or imageName
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

function MapObjectFinder:tpDrawDebugWorldLine(x1, y1, z1, x2, y2, z2, r, g, b)
    r = r or 0.15
    g = g or 1.0
    b = b or 0.15

    if DebugUtil ~= nil and type(DebugUtil.drawDebugLine) == "function" then
        DebugUtil.drawDebugLine(x1, y1, z1, x2, y2, z2, r, g, b)
        return true
    end

    if type(drawDebugLine) == "function" then
        drawDebugLine(x1, y1, z1, x2, y2, z2, r, g, b)
        return true
    end

    return false
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
        renderText(0.02, 0.78, 0.015, "Map-only Foliage: " .. tostring(marker.layer or "?") .. " states " .. tostring(marker.states or "?"))
    end
end

function MapObjectFinder:draw()
    self:tpDrawMapOnlyFoliageMarkerNow()
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

function MapObjectFinder:tpGetTreeDescFromSplitShape(splitShapeId)
    if splitShapeId == nil or splitShapeId == 0 or not entityExists(splitShapeId) then
        return nil, nil
    end

    if type(getSplitType) ~= "function" then
        return nil, nil
    end

    local splitType = getSplitType(splitShapeId)

    if splitType == nil then
        return nil, nil
    end

    if g_treePlantManager == nil or type(g_treePlantManager.getTreeTypeDescFromSplitType) ~= "function" then
        return nil, splitType
    end

    local desc = g_treePlantManager:getTreeTypeDescFromSplitType(splitType)

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
    overlapSphere(x, scanY, z, radius, "tpOnTreeProbeShapeDetected", self, CollisionFlag.TREE, false, false, true, false)

    local rawShapes = self.tpTreeProbeShapes or {}
    self.tpTreeProbeShapes = nil
    self.tpTreeProbeSeen = nil

    if #rawShapes == 0 then
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
                px, py, pz = getWorldTranslation(splitShapeId)
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
            end
        end
    end

    table.sort(results, function(a, b)
        return (tonumber(a.distanceSq) or 0) < (tonumber(b.distanceSq) or 0)
    end)

    return results
end

tpExtractTreeNameFromHierarchy = function(hierarchy)
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

function MapObjectFinder:tpFindTreeDisplayItemsForDescs(screen, treeDescs)
    local results = {}

    if type(treeDescs) ~= "table" then
        return results
    end

    for _, treeInfo in ipairs(treeDescs) do
        local desc = treeInfo ~= nil and treeInfo.desc or nil
        if type(desc) == "table" then
            local candidates = self:tpFindTreePlaceableCandidates(screen, treeInfo)

            if #candidates == 1 and (tonumber(candidates[1].descHits) or 0) > 0 then
                local item = candidates[1].item
                if type(item) == "table" then
                    local title = tostring(desc.title or desc.name or "Baum")
                    item.tpPipetteDebugSuffix = " [Baum erkannt]"
                    table.insert(results, item)

                end
            else
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

function MapObjectFinder:pickTextureAtCurrentMousePosition()
    local x, y, z = self:findMouseWorldPosition()
    tpLog("pickTextureAtCurrentMousePosition called, worldPos=" .. tostring(x) .. "," .. tostring(y) .. "," .. tostring(z))

    if x == nil then
        tpShowMessage(tpText("TP_msg_noPosition", "No target found."))
        return
    end

    local rawX, rawY, rawZ = x, y, z

    self.tpLastRawSampleX = rawX
    self.tpLastRawSampleY = rawY
    self.tpLastRawSampleZ = rawZ

    self.lastPipetteWorldX = x
    self.lastPipetteWorldY = y
    self.lastPipetteWorldZ = z

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
        local collectedTreeItems = self:tpCollectTreeDisplayItemsAtWorldPosition(screen, x, y, z)
        if type(collectedTreeItems) == "table" then
            treeResultItems = collectedTreeItems
        end
    end

    if #(objectResultItems or {}) == 0 and #(treeResultItems or {}) == 0 then
        if self:tpTryHandleStaticMapObjectHit(screen) then
            self.nextArmedStatusRefreshAt = 0
            return
        end
    end

    local visibleCandidates = self:tpCollectCurrentPaintTabCandidates() or {}
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

    for _, entry in ipairs(rankedMatches or {}) do
        local item = entry ~= nil and entry.sourceItem or nil
        if item ~= nil and usedFinalItems[item] ~= true then
            usedFinalItems[item] = true
            table.insert(finalResultItems, item)
        end
    end

    local cappedFinalResultItems = {}
    for index, item in ipairs(finalResultItems or {}) do
        if index > 10 then
            break
        end
        table.insert(cappedFinalResultItems, item)
    end
    finalResultItems = cappedFinalResultItems

    self:tpDecoratePipetteResultNames(finalResultItems)
    self.tpResultItems = finalResultItems

    if screen ~= nil then
        self:tpRefreshPipetteResultItems(screen)
        if #finalResultItems > 0 then
            self:tpTryPreselectFirstPipetteResult(screen)
        elseif screen.itemList ~= nil then
            if screen.itemList.setSelectedIndex ~= nil then
                screen.itemList:setSelectedIndex(0)
            else
                screen.itemList.selectedIndex = 0
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
