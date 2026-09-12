-- Exercise the shipped dependency order and the real category registration path.
local GAM = { UI = {}, L = { SETTINGS_NAME = "Gold Advisor Midnight Dev" },
    RuntimeName = function(name) return name .. "Dev" end,
    Log = { Warn = function() end } }
local Loader = assert(loadfile("../tests/TestLoader.lua"))()
local modules = {
    ["UI/WindowManager.lua"] = true,
    ["UI/MainWindowCommon.lua"] = true,
    ["Settings.lua"] = true,
}
for line in io.lines("GoldAdvisorMidnightDev.toc") do
    local path = line:gsub("\\", "/"):gsub("\r", "")
    if modules[path] then
        if path == "Settings.lua" then
            Loader.LoadModuleWithFixture(path, "../tests/fixtures/SettingsStartup.lua",
                "GoldAdvisorMidnightDev", GAM)
        else
            assert(loadfile(path))("GoldAdvisorMidnightDev", GAM)
        end
    end
end
assert(GAM.TestSettingsCommon() == GAM.UI.MainWindowCommon
    and GAM.TestSettingsCommon() ~= nil,
    "Settings captured a missing appearance module in the shipped TOC order")

local frames, canvas, registered, attempts = {}, nil, nil, 0
local function noop() end
function CreateFrame(_, name)
    local frame = { scripts = {}, Hide = noop, SetPoint = noop, SetSize = noop,
        SetText = noop }
    function frame:CreateFontString() return { SetPoint = noop, SetText = noop } end
    function frame:SetScript(event, callback) self.scripts[event] = callback end
    frames[#frames + 1] = frame
    return frame
end
UIParent = {}
-- Settings can become available after this addon file was evaluated.
assert(not GAM.TestRegisterSettingsCategory(), "unavailable API must not count as registration")
Settings = {
    RegisterCanvasLayoutCategory = function(panel, name)
        canvas = panel
        assert(name == GAM.L.SETTINGS_NAME)
        return { GetID = function() return 123 end }
    end,
    RegisterAddOnCategory = function(category)
        attempts = attempts + 1
        if attempts == 1 then error("registration failed") end
        registered = category
    end,
}
assert(not GAM.TestRegisterSettingsCategory(), "failed registration must be reported")
assert(GAM.TestRegisterSettingsCategory(), "failed registration must be retryable")
assert(registered and registered:GetID() == 123)
assert(#frames == 2, "retry must reuse the category panel and its button")
assert(GAM.TestRegisterSettingsCategory() and attempts == 2,
    "successful registration must not be duplicated")
local opens = 0
GAM.Settings.ShowStandalone = function() opens = opens + 1 end
canvas.scripts.OnShow()
frames[2].scripts.OnClick()
assert(opens == 2, "category selection and button must open settings")
print("PASS: settings dependencies, registration failure/retry, and category entry points")
