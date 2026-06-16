TexturePipetteGroundTextures = {}

local function tpGroundLayerLooksPaintable(layerName)
    if type(layerName) ~= "string" or layerName == "" then
        return false
    end

    return true
end

local function tpGroundTextureTitle(layerName)
    local words = {}

    for word in string.gmatch(layerName, "[^_]+") do
        local first = string.sub(word, 1, 1)
        local rest = string.sub(word, 2)
        table.insert(words, first .. string.lower(rest))
    end

    return table.concat(words, " ")
end

function TexturePipetteGroundTextures:appendAvailableTerrainLayers(manager, terrain)
    if manager == nil
        or type(manager.groundTypeMappings) ~= "table"
        or terrain == nil
        or getTerrainNumOfLayers == nil
        or getTerrainLayerName == nil then
        return
    end

    local numLayers = getTerrainNumOfLayers(terrain)
    if type(numLayers) ~= "number" or numLayers <= 0 then
        return
    end

    for layerIndex = 0, numLayers - 1 do
        local layerName = getTerrainLayerName(terrain, layerIndex)

        if tpGroundLayerLooksPaintable(layerName)
            and manager.groundTypeMappings[layerName] == nil then
            manager.groundTypeMappings[layerName] = {
                typeName = layerName,
                layerName = layerName,
                title = tpGroundTextureTitle(layerName)
            }
        end
    end
end

local function tpAppendGroundTextureMappings(manager, terrain)
    TexturePipetteGroundTextures:appendAvailableTerrainLayers(manager, terrain)
end

GroundTypeManager.initTerrain = Utils.appendedFunction(
    GroundTypeManager.initTerrain,
    tpAppendGroundTextureMappings
)
