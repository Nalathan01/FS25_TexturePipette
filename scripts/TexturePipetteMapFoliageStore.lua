TexturePipetteMapFoliageStore = TexturePipetteMapFoliageStore or {}

local TP_MF_MOD_NAME = g_currentModName or "FS25_TexturePipette"
local TP_MF_MOD_DIR = g_currentModDirectory or ""

local function tpMfDebugModeEnabled()
    if TexturePipetteMenu ~= nil and TexturePipetteMenu.isEnabled ~= nil then
        local ok, enabled = pcall(function()
            return TexturePipetteMenu:isEnabled("debugModeEnabled")
        end)
        return ok == true and enabled == true
    end
    return false
end

local function tpMfLog(message)
    message = tostring(message or "")
    local isError = string.find(message, "Error", 1, true) ~= nil or string.find(message, "error", 1, true) ~= nil
    if isError == true or tpMfDebugModeEnabled() == true then
        print(string.format("[TexturePipetteMapFoliage] %s", message))
    end
end

local function tpMfSafeFilename(value)
    value = tostring(value or "foliage")
    value = value:gsub("[^%w_%-]+", "_")
    value = value:gsub("_+", "_")
    value = value:gsub("^_+", "")
    value = value:gsub("_+$", "")
    if value == "" then
        value = "foliage"
    end
    return value
end

local function tpMfTitleCase(value)
    value = tostring(value or "")
    value = value:gsub("[_%-%s]+", " ")
    value = value:gsub("(%a)([%w_']*)", function(a, b)
        return string.upper(a) .. string.lower(b or "")
    end)
    return value
end

local function tpMfGetSettingsDirectory(missionInfo)
    local mapId = "unknownMap"
    if missionInfo ~= nil and missionInfo.mapId ~= nil then
        mapId = tostring(missionInfo.mapId)
    end

    local dir = g_modSettingsDirectory .. TP_MF_MOD_NAME .. "/mapFoliageMenu/" .. mapId .. "/"
    if not folderExists(g_modSettingsDirectory .. TP_MF_MOD_NAME .. "/") then
        createFolder(g_modSettingsDirectory .. TP_MF_MOD_NAME .. "/")
    end
    if not folderExists(g_modSettingsDirectory .. TP_MF_MOD_NAME .. "/mapFoliageMenu/") then
        createFolder(g_modSettingsDirectory .. TP_MF_MOD_NAME .. "/mapFoliageMenu/")
    end
    if not folderExists(dir) then
        createFolder(dir)
    end
    return dir
end

local function tpMfBuildExistingBrushMap()
    local storeMap = {}
    if g_storeManager ~= nil and type(g_storeManager.items) == "table" then
        for _, storeItem in ipairs(g_storeManager.items) do
            if type(storeItem) == "table"
                and type(storeItem.brush) == "table"
                and tostring(storeItem.brush.type or "") == "foliage"
                and type(storeItem.brush.parameters) == "table" then

                local layerName = tostring(storeItem.brush.parameters[1] or storeItem.brush.parameters[0] or "")
                local state = tonumber(storeItem.brush.parameters[2] or storeItem.brush.parameters[1])
                if layerName ~= "" and state ~= nil then
                    storeMap[layerName .. "|" .. tostring(state)] = true
                end
            end
        end
    end
    return storeMap
end

local function tpMfRegisterPaintableFromCache(foliageSystem, settingsDirectory)
    if type(foliageSystem) ~= "table" then
        return 0
    end

    local paintableFile = XMLFile.loadIfExists("tpMapFoliagePaintables", settingsDirectory .. "paintableFoliages.xml")
    if paintableFile == nil then
        return 0
    end

    if type(foliageSystem.paintableFoliages) ~= "table" then
        foliageSystem.paintableFoliages = {}
    end

    local registered = 0
    paintableFile:iterate("paintableFoliages.paintableFoliage", function(_, key)
        local layerName = paintableFile:getString(key .. "#layerName")
        local startStateChannel = paintableFile:getInt(key .. "#startStateChannel")
        local numStateChannels = paintableFile:getInt(key .. "#numStateChannels")

        if layerName ~= nil and layerName ~= "" and startStateChannel ~= nil and numStateChannels ~= nil then
            local exists = nil
            if type(foliageSystem.getFoliagePaintByName) == "function" then
                local ok, result = pcall(foliageSystem.getFoliagePaintByName, foliageSystem, layerName)
                if ok == true then
                    exists = result
                end
            end

            if exists == nil then
                table.insert(foliageSystem.paintableFoliages, {
                    id = #foliageSystem.paintableFoliages + 1,
                    layerName = layerName,
                    startStateChannel = startStateChannel,
                    numStateChannels = numStateChannels,
                    state = startStateChannel
                })
                registered = registered + 1
            end
        end
    end)

    paintableFile:delete()
    return registered
end

local function tpMfToStoreName(layerName, stateIndex, stateName)
    local niceState = tostring(stateName or "")
    niceState = niceState:gsub("_", " ")
    niceState = niceState:gsub("%s*%b[]", "")
    niceState = niceState:gsub("%s+", " ")
    niceState = niceState:gsub("^%s+", "")
    niceState = niceState:gsub("%s+$", "")

    if niceState == "" or niceState == "invisible" then
        niceState = tostring(layerName or "Foliage") .. " " .. tostring(stateIndex)
    else
        niceState = niceState:gsub("%f[%a].", string.upper):gsub("(%w)(%u)", "%1 %2")
    end

    return niceState
end

local function tpMfCreateMenuXml(settingsDirectory, baseDirectory, layerName, stateIndex, stateName, storeI3dFile, imageFile, price)
    local safeLayer = tpMfSafeFilename(layerName)
    local safeState = tpMfSafeFilename(stateName ~= nil and stateName ~= "" and stateName or tostring(stateIndex))
    local xmlName = string.format("paintable_%s_%03d_%s.xml", safeLayer, tonumber(stateIndex) or 0, safeState)
    local xmlPath = settingsDirectory .. xmlName

    local displayName = tpMfToStoreName(layerName, stateIndex, stateName)

    local xml = XMLFile.create("tpMapFoliageStoreItem", "", "placeable", Placeable.xmlSchema)
    xml:setValue("placeable#type", "bush")
    xml:setValue("placeable.storeData.name", displayName)
    xml:setValue("placeable.storeData.species", "PLACEABLE")
    xml:setValue("placeable.storeData.brand", "NONE")
    xml:setValue("placeable.storeData.category", "placeableMisc")
    xml:setValue("placeable.storeData.functions.function(0)", "$l10n_function_foliage")
    xml:setValue("placeable.storeData.image", imageFile or (TP_MF_MOD_DIR .. "data/icon_TexturePipette_category.dds"))
    xml:setValue("placeable.storeData.price", price or 25)
    xml:setValue("placeable.storeData.brush.type", "foliage")
    xml:setValue("placeable.storeData.brush.category", "landscaping")
    xml:setValue("placeable.storeData.brush.tab", "plants")
    xml:setValue("placeable.storeData.brush.parameters.parameter(0)", tostring(layerName))
    xml:setValue("placeable.storeData.brush.parameters.parameter(1)", tostring(stateIndex))

    if storeI3dFile ~= nil and storeI3dFile ~= "" then
        local baseFile = tostring(storeI3dFile)
        if baseFile:startsWith("data/") then
            baseFile = baseFile:gsub("^data/", "$data/")
        end
        xml:setValue("placeable.base.filename", baseFile)
    end

    xml:saveTo(xmlPath)
    xml:delete()
    return xmlPath, displayName
end

local function tpMfGenerateFromMapXml(foliageSystem, xmlFile, missionInfo, baseDirectory)
    if xmlFile == nil or baseDirectory == nil then
        tpMfLog("mapFoliageMenuGenerate skipped reason=missingXmlOrBase")
        return nil
    end

    local settingsDirectory = tpMfGetSettingsDirectory(missionInfo)
    if settingsDirectory == nil or not folderExists(settingsDirectory) then
        tpMfLog("mapFoliageMenuGenerate skipped reason=settingsDirectoryFailed")
        return nil
    end

    local mapFilename = getXMLString(xmlFile, "map.filename")
    if mapFilename == nil or mapFilename == "" then
        tpMfLog("mapFoliageMenuGenerate skipped reason=missingMapFilename")
        return settingsDirectory
    end

    mapFilename = Utils.getFilename(mapFilename, baseDirectory)
    local mapFile = XMLFile.loadIfExists("tpMapFoliageMapI3D", mapFilename)
    if mapFile == nil then
        tpMfLog("mapFoliageMenuGenerate skipped reason=mapFileLoadFailed file=" .. tostring(mapFilename))
        return settingsDirectory
    end

    deleteFolder(settingsDirectory)
    createFolder(settingsDirectory)

    local filesMap = {}
    mapFile:iterate("i3D.Files.File", function(_, key)
        local fileId = mapFile:getInt(key .. "#fileId")
        local filename = mapFile:getString(key .. "#filename")
        if fileId ~= nil and filename ~= nil and filename:contains("%.xml$") then
            filesMap[fileId] = filename
        end
    end)

    local existingBrushes = tpMfBuildExistingBrushMap()
    local paintableFile = XMLFile.create("tpMapFoliagePaintables", settingsDirectory .. "paintableFoliages.xml", "paintableFoliages")

    local created = 0
    local skippedExisting = 0
    local skippedFruit = 0
    local skippedInvisible = 0
    local layerCount = 0
    local paintableIndex = 0

    local i3dContainer = nil
    local cameraBaseNode = nil
    local camera = nil
    local light = nil
    local canRenderIcons = false

    if g_dedicatedServer == nil then
        i3dContainer = createTransformGroup("TexturePipetteMapFoliageIconContainer")
        link(getRootNode(), i3dContainer)
        setTranslation(i3dContainer, -100, -100, -100)

        local okCamera = pcall(function()
            cameraBaseNode = createTransformGroup("TexturePipetteStoreIconCameraBase")
            camera = createCamera("TexturePipetteStoreIconCamera", math.rad(60), 0.1, 1000)
            link(cameraBaseNode, camera)
            link(i3dContainer, cameraBaseNode)
            setRotation(cameraBaseNode, math.rad(-15), math.rad(45), 0)

            if g_cameraManager ~= nil and g_cameraManager.addCamera ~= nil and g_cameraManager.setActiveCamera ~= nil then
                g_cameraManager:addCamera(camera, nil, false)
                g_cameraManager:setActiveCamera(camera)
                canRenderIcons = true
            end

            light = createLightSource("TexturePipetteStoreIconLight", LightType.DIRECTIONAL, 0.75, 0.75, 0.75, 100)
            setLightShadowMap(light, true, 512)
            link(i3dContainer, light)
            setRotation(light, math.rad(-95), math.rad(70), math.rad(-5))
        end)

        if okCamera ~= true then
            canRenderIcons = false
            if light ~= nil then delete(light); light = nil end
            if camera ~= nil then delete(camera); camera = nil end
            if cameraBaseNode ~= nil then delete(cameraBaseNode); cameraBaseNode = nil end
        end
    end

    mapFile:iterate("i3D.Scene.TerrainTransformGroup.Layers.FoliageSystem.FoliageMultiLayer", function(_, layerGroupKey)
        mapFile:iterate(layerGroupKey .. ".FoliageType", function(_, foliageTypeKey)
            local layerName = mapFile:getString(foliageTypeKey .. "#name")
            local foliageXmlId = mapFile:getInt(foliageTypeKey .. "#foliageXmlId")
            local foliageXml = foliageXmlId ~= nil and filesMap[foliageXmlId] or nil
            if layerName == nil or layerName == "" or foliageXml == nil then
                return
            end

            foliageXml = Utils.getFilename(foliageXml, Utils.getDirectory(mapFilename))
            local foliageFile = XMLFile.loadIfExists("tpMapFoliageDefinition", foliageXml, FruitTypeDesc.xmlSchema)
            if foliageFile == nil then
                tpMfLog("mapFoliageLayerSkipped layer=" .. tostring(layerName) .. " reason=foliageXmlLoadFailed file=" .. tostring(foliageXml))
                return
            end

            if foliageFile:hasProperty("foliageType.fruitType") then
                skippedFruit = skippedFruit + 1
                foliageFile:delete()
                return
            end

            local firstStateName = foliageFile:getValue("foliageType.foliageLayer(0).foliageState(0)#name")
            if tostring(firstStateName or "") == "invisible" then
                skippedInvisible = skippedInvisible + 1
                foliageFile:delete()
                return
            end

            local storeI3dFile = foliageFile:getValue("foliageType.foliageLayer(0)#shapeSource")
            if storeI3dFile ~= nil and storeI3dFile ~= "" then
                storeI3dFile = Utils.getFilename(storeI3dFile, Utils.getDirectory(foliageXml))
            else
                storeI3dFile = nil
            end

            local i3dNode = nil
            if storeI3dFile ~= nil then
                local ok, result = pcall(loadI3DFile, storeI3dFile, false, false, false)
                if ok == true and result ~= nil and result ~= 0 then
                    i3dNode = result
                end
            end

            local stateCreated = 0
            foliageFile:iterate("foliageType.foliageLayer(0).foliageState", function(stateIndex, stateKey)
                local stateNumber = tonumber(stateIndex)
                if stateNumber == nil then
                    return
                end

                local brushKey = tostring(layerName) .. "|" .. tostring(stateNumber)
                if existingBrushes[brushKey] == true then
                    skippedExisting = skippedExisting + 1
                    return
                end

                local stateName = foliageFile:getString(stateKey .. "#name")
                local baseFilename = (tostring(layerName) .. " " .. tostring(stateName or stateNumber)):gsub("%f[%a].", string.upper):gsub("[%s-_]+", ""):gsub("^.", string.lower)
                baseFilename = tpMfSafeFilename(baseFilename .. "_" .. tostring(stateNumber))
                local storeIcon = "store_" .. baseFilename .. ".dxt"
                local imageFile = storeIcon
                local renderNodePath = foliageFile:getString(stateKey .. ".foliageShape(0).foliageLod(0)#blockShape", ""):gsub(">", "|")

                local objectNode = nil
                local posX, posY, posZ, radius = 0, 0, 0, 1
                local price = 25

                if i3dNode ~= nil then
                    local sourceNode = I3DUtil.indexToObject(i3dNode, renderNodePath) or i3dNode
                    if sourceNode ~= nil and sourceNode ~= 0 then
                        objectNode = clone(sourceNode, false, false, false)
                        if objectNode ~= nil and objectNode ~= 0 then
                            posX, posY, posZ, radius = getShapeBoundingSphere(objectNode)
                            radius = (radius or 1) * math.max(getScale(objectNode))
                            price = math.clamp(math.floor((radius or 1) * 2) * 25, 10, 100)
                        end
                    end
                end

                if canRenderIcons == true and objectNode ~= nil and objectNode ~= 0 then
                    link(i3dContainer, objectNode)
                    setTranslation(cameraBaseNode, posX, posY + radius * 0.1, posZ)
                    setTranslation(camera, 0, 0, radius * 2)

                    local okRender, rendered = pcall(function()
                        return renderScreenshot(settingsDirectory .. storeIcon, 512, 512, 1, "raw_alpha", 2, 0, 0, 0, 0, 0, 15, false)
                    end)

                    if okRender == true and rendered == true then
                        imageFile = storeIcon
                    else
                        imageFile = TP_MF_MOD_DIR .. "data/icon_TexturePipette_category.dds"
                    end
                else
                    imageFile = TP_MF_MOD_DIR .. "data/icon_TexturePipette_category.dds"
                end

                if objectNode ~= nil and objectNode ~= 0 then
                    delete(objectNode)
                end

                local xmlPath = tpMfCreateMenuXml(settingsDirectory, baseDirectory, layerName, stateNumber, stateName, storeI3dFile, imageFile, price)
                if xmlPath ~= nil then
                    existingBrushes[brushKey] = true
                    created = created + 1
                    stateCreated = stateCreated + 1
                end
            end)

            if i3dNode ~= nil and i3dNode ~= 0 then
                delete(i3dNode)
            end

            if stateCreated > 0 then
                local paintableKey = string.format("paintableFoliages.paintableFoliage(%d)", paintableIndex)
                paintableFile:setString(paintableKey .. "#layerName", layerName)
                paintableFile:setInt(paintableKey .. "#startStateChannel", foliageFile:getValue("foliageType.foliageLayer(0)#densityMapChannelOffset", 0))
                paintableFile:setInt(paintableKey .. "#numStateChannels", foliageFile:getValue("foliageType.foliageLayer(0)#numDensityMapChannels", 0))
                paintableIndex = paintableIndex + 1
                layerCount = layerCount + 1
                tpMfLog("mapFoliageLayerMenuCreated layer=" .. tostring(layerName) .. " states=" .. tostring(stateCreated))
            end

            foliageFile:delete()
        end)
    end)

    if light ~= nil then
        delete(light)
    end
    if camera ~= nil then
        if g_cameraManager ~= nil then
            if g_cameraManager.setActiveCamera ~= nil and g_cameraManager.defaultCameraNode ~= nil then
                pcall(function()
                    g_cameraManager:setActiveCamera(g_cameraManager.defaultCameraNode)
                end)
            end
            if g_cameraManager.removeCamera ~= nil then
                pcall(function()
                    g_cameraManager:removeCamera(camera)
                end)
            end
        end
        delete(camera)
    end
    if cameraBaseNode ~= nil then
        delete(cameraBaseNode)
    end
    if i3dContainer ~= nil then
        delete(i3dContainer)
    end

    paintableFile:save()
    paintableFile:delete()
    mapFile:delete()

    local registered = tpMfRegisterPaintableFromCache(foliageSystem, settingsDirectory)

    local modInfo = g_modManager ~= nil and g_modManager:getModByName(TP_MF_MOD_NAME) or nil
    local loaded = 0
    if g_storeManager ~= nil and g_storeManager.loadItem ~= nil and Files ~= nil and Files.getFilesRecursive ~= nil then
        local storeFiles = Files.getFilesRecursive(settingsDirectory)
        for _, item in pairs(storeFiles or {}) do
            if item ~= nil and item.isDirectory ~= true and tostring(item.filename or ""):contains("^paintable_.+%.xml$") then
                local ok = pcall(function()
                    g_storeManager:loadItem(item.filename, settingsDirectory, TP_MF_MOD_NAME, true, false, modInfo ~= nil and modInfo.title or "Texture Pipette")
                end)
                if ok == true then
                    loaded = loaded + 1
                end
            end
        end
    end

    return settingsDirectory
end

if FoliageSystem ~= nil and FoliageSystem.loadMapData ~= nil then
    FoliageSystem.loadMapData = Utils.appendedFunction(FoliageSystem.loadMapData, function(self, xmlFile, missionInfo, baseDirectory)
        local ok, err = pcall(function()
            tpMfGenerateFromMapXml(self, xmlFile, missionInfo, baseDirectory)
        end)
        if ok ~= true then
            tpMfLog("mapFoliageMenuError " .. tostring(err))
        end
    end)
end
