CropRotationSettings = {
    MOD_NAME = g_currentModName
}

local CropRotationSettings_mt = Class(CropRotationSettings)

function CropRotationSettings:new(cropRotation, customMt)
    local self = setmetatable({}, customMt or CropRotationSettings_mt)

    self.cropRotation = cropRotation
    self.elementsCreated = false
    self.settingsHeadline = 'Nailed to death' -- g_i18n:getText("ui_header")
    self.settings = {}

    return self
end

function CropRotationSettings:addSetting(name, title, description, callback, callbackTarget, default, isCheckbox, optionTexts)
    log(string.format('CropRotationSettings:addSetting(): name: %s, title: %s, description: %s, default: %s, checkbox: %s', 
        tostring(name), tostring(title), tostring(description), tostring(default), tostring(isCheckbox)))
    local setting = {
        name = name,
        title = title,
        description = description
    }

    if default ~= nil then
        setting.state = default
    elseif isCheckbox then
        setting.state = false
    else
        setting.state = 0
    end

    setting.callback = callback
    setting.callbackTarget = callbackTarget
    setting.isCheckbox = isCheckbox
    setting.optionTexts = optionTexts
    setting.element = nil

    table.insert(self.settings, setting)
    self:loadSettings()
    self:onSettingChanged(setting)
end

function CropRotationSettings:onSettingChanged(setting)
    if setting.callback ~= nil and setting.callbackTarget == nil then
        setting.callback(setting.state)
    elseif setting.callback ~= nil and setting.callbackTarget ~= nil then
        setting.callback(setting.callbackTarget, setting.state)
    end

    self:saveSettings()
end

function CropRotationSettings:saveSettings()
    if g_savegameXML ~= nil then
        for i = 1, #self.settings do
            local setting = self.settings[i]

            if setting.isCheckbox then
                setXMLBool(g_savegameXML, string.format("gameSettings.cropRotation.settings.%s#state", setting.name), setting.state)
            else
                setXMLInt(g_savegameXML, string.format("gameSettings.cropRotation.settings.%s#state", setting.name), setting.state)
            end
        end
    end

    g_gameSettings:saveToXMLFile(g_savegameXML)
end

function CropRotationSettings:loadSettings()
    if g_savegameXML ~= nil then
        for i = 1, #self.settings do
            local setting = self.settings[i]

            if setting.isCheckbox then
                setting.state = Utils.getNoNil(getXMLBool(g_savegameXML, string.format("gameSettings.cropRotation.settings.%s#state", setting.name)), setting.state)
            else
                setting.state = Utils.getNoNil(getXMLInt(g_savegameXML, string.format("gameSettings.cropRotation.settings.%s#state", setting.name)), setting.state)
            end
        end
    end
end

function CropRotationSettings:onClickCheckbox(state, checkboxElement)
    for i = 1, #self.settings do
        local setting = self.settings[i]

        if setting.element == checkboxElement then
            setting.state = state == CheckedOptionElement.STATE_CHECKED

            self:onSettingChanged(setting)
        end
    end
end

function CropRotationSettings:onClickMultiOption(state, optionElement)
    for i = 1, #self.settings do
        local setting = self.settings[i]

        if setting.element == optionElement then
            setting.state = state

            self:onSettingChanged(setting)
        end
    end
end

function CropRotationSettings:overwriteGameFunctions(crModule)
    crModule:overwriteGameFunction(InGameMenuGeneralSettingsFrame, "onFrameOpen", function (superFunc, frame, element)
        superFunc(frame, element)

        -- general algorithm, probably not needed for CR (only global disable switch is needed I guess...)
        if not self.elementsCreated then
            for i = 1, #frame.boxLayout.elements do
                local elem = frame.boxLayout.elements[i]

                if elem:isa(TextElement) then
                    local header = elem:clone(frame.boxLayout)

                    header:setText(self.settingsHeadline)
                    header:reloadFocusHandling(true)

                    break
                end
            end

            for i = 1, #self.settings do
                local setting = self.settings[i]

                if setting.isCheckbox then
                    setting.element = frame.checkUseEasyArmControl:clone(frame.boxLayout)

                    function setting.element.onClickCallback(_, ...)
                        self:onClickCheckbox(...)
                    end

                    setting.element:reloadFocusHandling(true)
                    setting.element:setIsChecked(setting.state)
                else
                    setting.element = frame.multiRealBeaconLightBrightness:clone(frame.boxLayout)

                    setting.element:setTexts(setting.optionTexts)

                    function setting.element.onClickCallback(_, ...)
                        self:onClickMultiOption(...)
                    end

                    setting.element:reloadFocusHandling(true)
                    setting.element:setState(setting.state)
                end

                setting.element.elements[4]:setText(setting.title)
                setting.element.elements[6]:setText(setting.description)
            end

            frame.boxLayout:invalidateLayout()

            self.elementsCreated = true
        end
    end)
    -- crModule:overwriteGameFunction(InGameMenuGameSettingsFrame, "onFrameOpen", function (superFunc, frame, element)
           -- alter specific check, PF-specific, not sure if CR needs one
    --     if frame.checkLimeRequired ~= nil then
    --         frame.checkLimeRequired:setVisible(false)
    --         frame.checkLimeRequired.parent:invalidateLayout()
    --     end

    --     superFunc(frame, element)
    -- end)
end
