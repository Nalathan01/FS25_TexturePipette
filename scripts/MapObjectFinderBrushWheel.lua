MapObjectFinderBrushWheel = {}

local TP_BW_SIZE_WORDS = { "superbig", "medium", "small", "short", "tall", "big" }

local function tpBwFamilyKey(item)
    local storeItem = type(item) == "table" and item.storeItem or nil
    local filename = type(storeItem) == "table" and (storeItem.xmlFilename or storeItem.rawXMLFilename) or nil
    if filename == nil then
        return nil
    end

    local base = string.lower(tostring(filename)):gsub("\\", "/")
    base = base:match("([^/]+)$") or base
    base = base:gsub("%.xml$", "")
    base = base:gsub("%d+$", "")
    local hasSizeWord = false
    for _, sizeWord in ipairs(TP_BW_SIZE_WORDS) do
        local stripped = base:gsub("_?" .. sizeWord .. "$", "")
        if stripped ~= base then
            base = stripped
            hasSizeWord = true
            break
        end
    end
    base = base:gsub("_+$", "")
    if not hasSizeWord or base == "" then
        return nil
    end
    return base
end

local function tpBwFoliageParams(item)
    local params = type(item) == "table" and item.brushParameters or nil
    if type(params) ~= "table" then
        return nil, nil
    end
    return tostring(params[1] or ""), tonumber(params[2])
end

function MapObjectFinderBrushWheel.applyBushStep(screen, inputValue)
    local item, _, currentCategory, currentTab = MapObjectFinder:tpGetCurrentConstructionSelectedItem(screen)
    local layer, state = tpBwFoliageParams(item)
    local family = tpBwFamilyKey(item)
    if layer == nil or layer == "" or state == nil or family == nil or type(screen.items) ~= "table" then
        return false
    end

    local bestState = nil
    local candidates = {}
    for categoryIndex, categoryItems in pairs(screen.items) do
        if type(categoryItems) == "table" then
            for tabIndex, tabItems in pairs(categoryItems) do
                if type(tabItems) == "table" then
                    for itemIndex, candidate in ipairs(tabItems) do
                        local candidateLayer, candidateState = tpBwFoliageParams(candidate)
                        if candidateLayer == layer and candidateState ~= nil and tpBwFamilyKey(candidate) == family then
                            local isNext = (inputValue > 0 and candidateState > state) or (inputValue < 0 and candidateState < state)
                            if isNext and (bestState == nil or (inputValue > 0 and candidateState < bestState) or (inputValue < 0 and candidateState > bestState)) then
                                bestState = candidateState
                                candidates = {}
                            end
                            if isNext and candidateState == bestState then
                                table.insert(candidates, { categoryIndex = categoryIndex, tabIndex = tabIndex, itemIndex = itemIndex })
                            end
                        end
                    end
                end
            end
        end
    end

    if bestState == nil or #candidates == 0 then
        return true
    end

    local target = candidates[1]
    for _, candidate in ipairs(candidates) do
        if candidate.categoryIndex == currentCategory and candidate.tabIndex == currentTab then
            target = candidate
            break
        end
    end

    if target.categoryIndex ~= currentCategory or target.tabIndex ~= currentTab then
        screen:setCurrentCategory(target.categoryIndex, target.tabIndex)
    end
    screen.itemList:setSelectedIndex(target.itemIndex)

    return true
end

function MapObjectFinderBrushWheel.isTreeStageAtLimit(brush, inputValue)
    local stage = tonumber(brush.treeStage)
    if stage == nil or g_treePlantManager == nil then
        return false
    end

    local desc = g_treePlantManager:getTreeTypeDescFromName(brush.treeType)
    local maxStage = type(desc) == "table" and type(desc.stages) == "table" and #desc.stages or nil
    if maxStage == nil then
        return false
    end

    return (inputValue > 0 and stage >= maxStage) or (inputValue < 0 and stage <= 1)
end

function MapObjectFinderBrushWheel.applyWheel(inputValue)
    if MapObjectFinder == nil or MapObjectFinder:isConstructionScreenOpen() ~= true then
        return false
    end

    local screen = MapObjectFinder:tpResolveConstructionLogicScreen()
    if screen == nil then
        return false
    end

    local brush = screen.brush
    if type(brush) ~= "table" then
        return false
    end

    if brush.foliageState ~= nil and MapObjectFinderBrushWheel.applyBushStep(screen, inputValue) then
        return true
    end

    if brush.treeStage ~= nil and MapObjectFinderBrushWheel.isTreeStageAtLimit(brush, inputValue) then
        return true
    end

    if brush.supportsPrimaryAxis == true and type(screen.onAxisPrimary) == "function" then
        local step = inputValue > 0 and 1 or -1
        screen:onAxisPrimary(InputAction.AXIS_CONSTRUCTION_ACTION_PRIMARY, step, nil, false)
        return true
    end

    return false
end

GuiTopDownCamera.onZoom = Utils.overwrittenFunction(GuiTopDownCamera.onZoom, function(camera, superFunc, actionName, inputValue, callbackState, isAnalog, isMouse)
    if isMouse == true and inputValue ~= nil and inputValue ~= 0 and Input.isKeyPressed(Input.KEY_lshift) then
        if MapObjectFinderBrushWheel.applyWheel(inputValue) then
            return
        end
    end

    return superFunc(camera, actionName, inputValue, callbackState, isAnalog, isMouse)
end)
