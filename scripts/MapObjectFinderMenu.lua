MapObjectFinderMenu = {}
MapObjectFinderMenu.modDirectory = g_currentModDirectory or ""
MapObjectFinderMenu.pipetteCategoryName = "TP_PIPETTE_MENU"
MapObjectFinderMenu.pipetteTabName = "TP_PIPETTE_TAB"
MapObjectFinderMenu.settings = {
    pipetteEnabled = true,
    freePaintEnabled = true,
}
MapObjectFinderMenu.controls = {}
MapObjectFinderMenu.settingsUiInitialized = false
MapObjectFinderMenu.settingsLoaded = false
MapObjectFinderMenu.settingsPath = nil
MapObjectFinderMenu.constructionMenuRegistered = false


local function tpMenuText(key, fallback)
    if g_i18n ~= nil and g_i18n.getText ~= nil then
        local text = g_i18n:getText(key)
        if text ~= nil and text ~= "" and text ~= key then
            return text
        end
    end
    return fallback
end

function MapObjectFinderMenu:getSettingsPath()
    if self.settingsPath == nil then
        self.settingsPath = getUserProfileAppPath() .. "modSettings/FS25_TexturePipette.xml"
    end
    return self.settingsPath
end

function MapObjectFinderMenu:loadSettings()
    if self.settingsLoaded then
        return
    end

    self.settingsLoaded = true
    local path = self:getSettingsPath()

    if fileExists ~= nil and not fileExists(path) then
        return
    end

    local xmlFile = loadXMLFile("MapObjectFinderSettings", path)
    if xmlFile == nil or xmlFile == 0 then
        return
    end

    for key, defaultValue in pairs(self.settings) do
        local value = getXMLBool(xmlFile, "texturePipette.settings#" .. key)
        if value ~= nil then
            self.settings[key] = value
        else
            self.settings[key] = defaultValue
        end
    end

    delete(xmlFile)
end

function MapObjectFinderMenu:saveSettings()
    local path = self:getSettingsPath()
    local dir = string.match(path, "^(.*)[/\\][^/\\]+$")
    if dir ~= nil and createFolder ~= nil then
        createFolder(dir)
    end

    local xmlFile = createXMLFile("MapObjectFinderSettings", path, "texturePipette")
    if xmlFile == nil or xmlFile == 0 then
        return
    end

    for key, value in pairs(self.settings) do
        setXMLBool(xmlFile, "texturePipette.settings#" .. key, value == true)
    end

    saveXMLFile(xmlFile)
    delete(xmlFile)
end

function MapObjectFinderMenu:isEnabled(key)
    self:loadSettings()
    return self.settings[key] == true
end

function MapObjectFinderMenu:setEnabled(key, value)
    self:loadSettings()
    if self.settings[key] == nil then
        return
    end

    self.settings[key] = value == true
    self:saveSettings()

    self:registerConstructionMenu()
    self:refreshConstructionScreen()
end

function MapObjectFinderMenu:toggle(key)
    self:setEnabled(key, not self:isEnabled(key))
end

function MapObjectFinderMenu:getConstructionIconUVs()
    if GuiUtils ~= nil and GuiUtils.getUVs ~= nil then
        return GuiUtils.getUVs("0 0 1 1", {1, 1})
    end
    return {0, 0, 1, 1}
end

function MapObjectFinderMenu:registerConstructionMenu()
    if g_storeManager == nil
        or g_storeManager.getConstructionCategoryByName == nil
        or g_storeManager.addConstructionCategory == nil
        or g_storeManager.addConstructionTab == nil then
        return false
    end

    self:loadSettings()

    local pipetteEnabled = self:isEnabled("pipetteEnabled")
    if not pipetteEnabled then
        return false
    end

    if pipetteEnabled then
        local pipetteCategory = g_storeManager:getConstructionCategoryByName(self.pipetteCategoryName)
        if pipetteCategory == nil then
            g_storeManager:addConstructionCategory(
                self.pipetteCategoryName,
                tpMenuText("TP_tab_pipette", "Pipette"),
                "data/icon_TexturePipette_category.dds",
                self:getConstructionIconUVs(),
                self.modDirectory,
                nil
            )
        end

        local pipetteTab = nil
        if g_storeManager.getConstructionTabByName ~= nil then
            pipetteTab = g_storeManager:getConstructionTabByName(self.pipetteTabName, self.pipetteCategoryName)
        end
        if pipetteTab == nil then
            g_storeManager:addConstructionTab(
                self.pipetteCategoryName,
                self.pipetteTabName,
                tpMenuText("TP_tab_pipette", "Pipette"),
                nil,
                nil,
                self.modDirectory,
                nil
            )
        end
    end


    self.constructionMenuRegistered = true
    return true
end

function MapObjectFinderMenu:getTabIndex(screen, tabName)
    if screen == nil or type(screen.categories) ~= "table" then
        return nil, nil
    end

    local targetCategoryName = nil
    if tostring(tabName) == tostring(self.pipetteTabName) then
        targetCategoryName = self.pipetteCategoryName
    end

    if targetCategoryName == nil then
        return nil, nil
    end

    for categoryIndex, category in ipairs(screen.categories) do
        if type(category) == "table" and tostring(category.name or "") == tostring(targetCategoryName) then
            for tabIndex, tab in ipairs(category.tabs or {}) do
                if type(tab) == "table" and tostring(tab.name or "") == tostring(tabName) then
                    return categoryIndex, tabIndex
                end
            end
            return categoryIndex, nil
        end
    end

    return nil, nil
end

local function tpAppendConstructionRebuild(screen)
    if MapObjectFinderMenu ~= nil then
        MapObjectFinderMenu:registerConstructionMenu()
    end
end
ConstructionScreen.rebuildData = Utils.appendedFunction(ConstructionScreen.rebuildData, tpAppendConstructionRebuild)

function MapObjectFinderMenu:refreshConstructionScreen()
    local screen = nil
    if MapObjectFinder ~= nil and MapObjectFinder.tpResolveConstructionLogicScreen ~= nil then
        screen = MapObjectFinder:tpResolveConstructionLogicScreen()
    elseif g_constructionScreen ~= nil then
        screen = g_constructionScreen
    end

    if screen ~= nil and screen.rebuildData ~= nil then
        local ok, err = pcall(function()
            screen:rebuildData()
        end)

        if ok then
            local pipetteCategoryIndex, pipetteTabIndex = self:getTabIndex(screen, self.pipetteTabName)
        else
        end
    end
end

function MapObjectFinderMenu:getConstructionScreen()
    if MapObjectFinder ~= nil and MapObjectFinder.tpResolveConstructionLogicScreen ~= nil then
        return MapObjectFinder:tpResolveConstructionLogicScreen()
    end
    return g_constructionScreen
end

function MapObjectFinderMenu:isPaintBrushActive()
    local screen = self:getConstructionScreen()
    local brush = screen ~= nil and screen.brush or nil
    if brush == nil or ConstructionBrushPaint == nil then
        return false
    end

    if brush.isa ~= nil then
        local ok, result = pcall(function()
            return brush:isa(ConstructionBrushPaint)
        end)
        if ok then
            return result == true
        end
    end

    return getmetatable(brush) == ConstructionBrushPaint
end

function MapObjectFinderMenu:onLandscapingGetCost(landscaping, superFunc, displacedVolumeOrArea, ...)
    if self:isEnabled("freePaintEnabled") and self:isPaintBrushActive() then
        return 0
    end
    return superFunc(landscaping, displacedVolumeOrArea, ...)
end

if Landscaping ~= nil and Landscaping.getCost ~= nil then
    Landscaping.getCost = Utils.overwrittenFunction(Landscaping.getCost, function(landscaping, superFunc, displacedVolumeOrArea, ...)
        return MapObjectFinderMenu:onLandscapingGetCost(landscaping, superFunc, displacedVolumeOrArea, ...)
    end)
end


function MapObjectFinderMenu:onSettingsUiChanged(control)
    self:saveSettings()
end

function MapObjectFinderMenu:injectUiSettings()
    if self.settingsUiInitialized then
        return true
    end

    if g_gui == nil or g_gui.screenControllers == nil or InGameMenu == nil then
        return false
    end

    local inGameMenuController = g_gui.screenControllers[InGameMenu]
    local settingsPage = inGameMenuController ~= nil and inGameMenuController.pageSettings or nil
    if settingsPage == nil or settingsPage.generalSettingsLayout == nil then
        return false
    end

    self.controls = {}

    local controlProperties = {
        { name = "pipetteEnabled", autoBind = true },
        { name = "freePaintEnabled", autoBind = true }
    }

    MapObjectFinderUIHelper.createControlsDynamically(settingsPage, "TP_settings_title", self, controlProperties, "TP_")
    MapObjectFinderUIHelper.setupAutoBindControls(self, self.settings, MapObjectFinderMenu.onSettingsUiChanged)

    if self.populateAutoBindControls ~= nil then
        self:populateAutoBindControls()
    end

    self.settingsUiInitialized = true
    return true
end

BaseMission.loadMapFinished = Utils.appendedFunction(BaseMission.loadMapFinished, function(...)
    MapObjectFinderMenu:loadSettings()
    MapObjectFinderMenu:injectUiSettings()
end)

function MapObjectFinderMenu:loadMap()
    self:loadSettings()
    self:registerConstructionMenu()
end

function MapObjectFinderMenu:update(dt)
end

function MapObjectFinderMenu:deleteMap()
    self.constructionMenuRegistered = false
    self.settingsUiInitialized = false
    self.controls = {}
end

addModEventListener(MapObjectFinderMenu)
