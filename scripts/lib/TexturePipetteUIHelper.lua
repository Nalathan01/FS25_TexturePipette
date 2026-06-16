TexturePipetteUIHelper = {}

function TexturePipetteUIHelper.createSection(generalSettingsPage, i18nTitleId)
	local sectionTitle = nil
	for _, elem in ipairs(generalSettingsPage.generalSettingsLayout.elements) do
		if elem.name == "sectionHeader" then
			sectionTitle = elem:clone(generalSettingsPage.generalSettingsLayout)
			sectionTitle:setText(g_i18n:getText(i18nTitleId))
			break
		end
	end
	if sectionTitle then
		sectionTitle.focusId = FocusManager:serveAutoFocusId()
		table.insert(generalSettingsPage.controlsList, sectionTitle)
	end
	return sectionTitle
end

function TexturePipetteUIHelper.updateFocusIds(element)
	if not element then
		return
	end
	element.focusId = FocusManager:serveAutoFocusId()
	for _, child in pairs(element.elements) do
		TexturePipetteUIHelper.updateFocusIds(child)
	end
end

local function createElement(generalSettingsPage, template, id, i18nTextId, target, callbackFunc)
	local elementBox = template:clone(generalSettingsPage.generalSettingsLayout)
	TexturePipetteUIHelper.updateFocusIds(elementBox)

	elementBox.id = id .. "Box"
	local elementOption = elementBox.elements[1]
	elementOption.target = target
	elementOption:setCallback("onClickCallback", callbackFunc)
	target.name = generalSettingsPage.name
	elementOption.id = id
	elementOption:setDisabled(false)
	local textElement = elementBox.elements[2]
	textElement:setText(g_i18n:getText(i18nTextId .. "_short"))
	local toolTip = elementOption.elements[1]
	toolTip:setText(g_i18n:getText(i18nTextId .. "_long"))

	table.insert(generalSettingsPage.controlsList, elementBox)
	return elementBox
end


function TexturePipetteUIHelper.createBoolElement(generalSettingsPage, id, i18nTextId, target, callbackFunc)
	return createElement(generalSettingsPage, generalSettingsPage.checkWoodHarvesterAutoCutBox, id, i18nTextId, target, callbackFunc)
end

function TexturePipetteUIHelper.createChoiceElement(generalSettingsPage, id, i18nTextId, i18nValueMap, target, callbackFunc, nillable)
	local choiceElementBox = createElement(generalSettingsPage, generalSettingsPage.multiVolumeVoiceBox, id, i18nTextId, target, callbackFunc)

	local choiceElement = choiceElementBox.elements[1]
	local texts = {}

	if nillable then
		table.insert(texts, "-")
	end
	for _, valueEntry in pairs(i18nValueMap) do
		local value
		if type(valueEntry) == "number" then
			value = tostring(valueEntry)
		elseif type(valueEntry) == "string" then
			value = g_i18n:getText(valueEntry)
			choiceElementBox.hasStrings = true
		else
			value = g_i18n:getText(valueEntry.i18nTextId)
			choiceElementBox.hasStrings = true
		end
		table.insert(texts, value)
	end
	choiceElement:setTexts(texts)

	return choiceElementBox
end

function TexturePipetteUIHelper.createRangeElement(generalSettingsPage, id, i18nTextId, minValue, maxValue, step, unit, target, callbackFunc, nillable)
	local rangeElementBox = createElement(generalSettingsPage, generalSettingsPage.multiVolumeVoiceBox, id, i18nTextId, target, callbackFunc)

	local rangeElement = rangeElementBox.elements[1]
	local texts = {}

	if nillable then
		table.insert(texts, "-")
	end

	local digits = 0
	local tmpStep = step
	while tmpStep < 1 do
		digits = digits + 1
		tmpStep = tmpStep * 10
	end
	local formatTemplate = (".%df"):format(digits)
	for i = minValue, maxValue, step do
		local text = ("%" .. formatTemplate):format(i)
		if unit then
			text = ("%s %s"):format(text, unit)
		end
		table.insert(texts, text)
	end
	rangeElement:setTexts(texts)

	return rangeElementBox
end

function TexturePipetteUIHelper.createControlsDynamically(settingsPage, sectionTitle, owningTable, controlProperties, prefix)
	owningTable.sectionTitle = TexturePipetteUIHelper.createSection(settingsPage, sectionTitle)
	owningTable.controls[1] = owningTable.sectionTitle

	for _, controlProps in ipairs(controlProperties) do
		local uiControl
		local id = prefix .. controlProps.name
		local callback = "on_" .. controlProps.name .. "_changed"
		if controlProps.min ~= nil then
			uiControl = TexturePipetteUIHelper.createRangeElement(
			settingsPage, id, id, 
			controlProps.min, controlProps.max, controlProps.step, controlProps.unit,
			owningTable, callback, controlProps.nillable)

			uiControl.min = controlProps.min
			uiControl.max = controlProps.max
			uiControl.step = controlProps.step
			uiControl.nillable = controlProps.nillable

		elseif controlProps.values ~= nil then
			uiControl = TexturePipetteUIHelper.createChoiceElement(settingsPage, id, id, controlProps.values, owningTable, callback, controlProps.nillable)
			uiControl.values = controlProps.values -- for mapping values later on, if necessary
			uiControl.nillable = controlProps.nillable
		else
			uiControl = TexturePipetteUIHelper.createBoolElement(settingsPage, id, id, owningTable, callback)
		end

		uiControl.autoBind = controlProps.autoBind
		uiControl.name = controlProps.name
		uiControl.subTable = controlProps.subTable
		uiControl.propName = controlProps.propName
		table.insert(owningTable.controls, uiControl)
		owningTable[controlProps.name] = uiControl -- allow accessing the control by its name

		TexturePipetteUIHelper.registerFocusControls(owningTable.controls)
		settingsPage.generalSettingsLayout:invalidateLayout()
	end
end


function TexturePipetteUIHelper.registerFocusControls(controls)
	FocusManager.setGui = Utils.appendedFunction(FocusManager.setGui, function(_, gui)
		for _, control in ipairs(controls) do
			if not control.focusId or not FocusManager.currentFocusData.idToElementMapping[control.focusId] then
				if not FocusManager:loadElementFromCustomValues(control, nil, nil, false, false) then
					Logging.warning("Failed loading focus element for %s. Keyboard/controller menu navigation might be bugged.", control.id or control.name)
				end
			end
		end
		local settingsPage = g_gui.screenControllers[InGameMenu].pageSettings
		settingsPage.generalSettingsLayout:invalidateLayout()
	end)
end

function TexturePipetteUIHelper.setupAutoBindControls(owningTable, targetTable, updateFunc)
	owningTable.populateAutoBindControls = function()
		for _, control in ipairs(owningTable.controls) do
			if control.autoBind then
				local value = TexturePipetteUIHelper.getAutoBoundValueFromTable(control, targetTable)
				TexturePipetteUIHelper.setControlValue(control, value)
			end
		end
	end
	InGameMenuSettingsFrame.onFrameOpen = Utils.appendedFunction(InGameMenuSettingsFrame.onFrameOpen, owningTable.populateAutoBindControls)
	for _, control in ipairs(owningTable.controls) do
		if control.autoBind then
			local callbackName = "on_autoBind_" .. control.name .. "_changed"
			owningTable[callbackName] = function(self, newState)
				local newValue = TexturePipetteUIHelper.getControlValue(control, newState)
				TexturePipetteUIHelper.setAutoBoundValueInTable(control, newValue, targetTable)
				if updateFunc then
					updateFunc(owningTable, control)
				end
			end
			control.elements[1]:setCallback("onClickCallback", callbackName)
		end
	end
end

function TexturePipetteUIHelper.getAutoBoundValueFromTable(control, targetTable)
	if control.subTable == nil then
		return targetTable[control.propName or control.name]
	else
		return targetTable[control.subTable][control.propName or control.name]
	end
end

function TexturePipetteUIHelper.setAutoBoundValueInTable(control, value, targetTable)
	if control.subTable == nil then
		targetTable[control.propName or control.name or "ERROR"] = value
	else
		targetTable[control.subTable][control.propName or control.name] = value
	end
end

function TexturePipetteUIHelper.setRangeValue(control, value)
	local valueIndex
	if control.nillable and value == nil then
		valueIndex = 1
	else
		valueIndex = math.floor(((value - control.min) / control.step + 1) + 0.5) -- floor(x+0.5) = round(x)
		if control.nillable then
			valueIndex = valueIndex + 1
		end
	end
	control.elements[1]:setState(valueIndex)
end

function TexturePipetteUIHelper.getRangeValue(control, controlState)
	if control.nillable and controlState == 1 then
		return nil
	else
		local offset = 1
		if control.nillable then
			offset = 2
		end
		return control.min + control.step * (controlState - offset)
	end
end

function TexturePipetteUIHelper.setChoiceValue(control, value)
	if control.hasStrings then
		control.elements[1]:setState(value)
	else
		for index, val in control.values do
			if val == value then
				control.elements[1]:setState(index)
			end
		end
	end
end

function TexturePipetteUIHelper.getChoiceValue(control, controlState)
	if control.hasStrings then
		return controlState
	else
		return control.values[controlState]
	end
end

function TexturePipetteUIHelper.setBoolValue(control, value)
	control.elements[1]:setState(value and BinaryOptionElement.STATE_RIGHT or BinaryOptionElement.STATE_LEFT)
end

function TexturePipetteUIHelper.getBoolValue(controlState)
	return controlState == 2
end

function TexturePipetteUIHelper.setControlValue(control, value)
	if control.min ~= nil then
		TexturePipetteUIHelper.setRangeValue(control, value)
	elseif control.values ~= nil then
		TexturePipetteUIHelper.setChoiceValue(control, value)
	else
		TexturePipetteUIHelper.setBoolValue(control, value)
	end
end

function TexturePipetteUIHelper.getControlValue(control, controlState)
	if control.min ~= nil then
		return TexturePipetteUIHelper.getRangeValue(control, controlState)
	elseif control.values ~= nil then
		return TexturePipetteUIHelper.getChoiceValue(control, controlState)
	else
		return TexturePipetteUIHelper.getBoolValue(controlState)
	end
end

BinaryOptionElement.update = Utils.appendedFunction(BinaryOptionElement.update, function(element, _)
	if element.sliderState < 0 then
		element.sliderState = 0
		element.sliderElement:setPosition(0)
	end
end)
