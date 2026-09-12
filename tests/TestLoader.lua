-- Test-only loader that appends fixture code to a runtime module's Lua chunk.
-- This preserves access to private locals without shipping regression fixtures.

local Loader = {}

local function ReadAll(path)
    local handle, err = io.open(path, "rb")
    assert(handle, err)
    local source = handle:read("*a")
    handle:close()
    return source
end

function Loader.LoadModuleWithFixture(modulePath, fixturePath, addonName, addonTable)
    local source = ReadAll(modulePath)
        .. "\n-- appended test-only fixture\n"
        .. ReadAll(fixturePath)
    local compile = loadstring or load
    local chunk, err = compile(source, "@" .. modulePath .. "+" .. fixturePath)
    assert(chunk, err)
    return chunk(addonName, addonTable)
end

return Loader
