-- GoldCraft Advisor - Codec.lua
-- Varint, ZigZag, and Base64 encoding utilities for compact SavedVariables storage

local _, GCA = ...
GCA.Codec = {}
local Codec = GCA.Codec

-- ================= Varint Encoding (Unsigned) =================
-- Protocol Buffer style varint encoding
-- 7 bits per byte, MSB = continuation flag

function Codec:EncodeVarint(value)
    if not value or value < 0 then
        value = 0
    end

    local bytes = {}
    while value >= 128 do
        bytes[#bytes + 1] = bit.bor(bit.band(value, 0x7F), 0x80)
        value = bit.rshift(value, 7)
    end
    bytes[#bytes + 1] = value
    return bytes
end

function Codec:DecodeVarint(data, pos)
    pos = pos or 1
    local value = 0
    local shift = 0

    repeat
        if pos > #data then
            return nil, pos
        end
        local byte = data[pos]
        value = value + bit.lshift(bit.band(byte, 0x7F), shift)
        shift = shift + 7
        pos = pos + 1
    until bit.band(byte, 0x80) == 0

    return value, pos
end

-- ================= ZigZag Encoding (Signed to Unsigned) =================
-- Converts signed integers to unsigned for efficient varint encoding

function Codec:EncodeZigZag(value)
    if value >= 0 then
        return value * 2
    else
        return (-value) * 2 - 1
    end
end

function Codec:DecodeZigZag(encoded)
    if bit.band(encoded, 1) == 0 then
        return encoded / 2
    else
        return -(encoded + 1) / 2
    end
end

-- ================= Base64 Encoding =================
-- For SavedVariables-safe string storage

local B64_CHARS = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local B64_DECODE = {}
for i = 1, 64 do
    B64_DECODE[B64_CHARS:sub(i, i)] = i - 1
end

function Codec:ToBase64(bytes)
    if not bytes or #bytes == 0 then
        return ""
    end

    local result = {}
    local padding = (3 - (#bytes % 3)) % 3

    -- Process in groups of 3 bytes
    for i = 1, #bytes, 3 do
        local b1 = bytes[i] or 0
        local b2 = bytes[i + 1] or 0
        local b3 = bytes[i + 2] or 0

        local n = bit.bor(
            bit.lshift(b1, 16),
            bit.lshift(b2, 8),
            b3
        )

        result[#result + 1] = B64_CHARS:sub(bit.band(bit.rshift(n, 18), 0x3F) + 1, bit.band(bit.rshift(n, 18), 0x3F) + 1)
        result[#result + 1] = B64_CHARS:sub(bit.band(bit.rshift(n, 12), 0x3F) + 1, bit.band(bit.rshift(n, 12), 0x3F) + 1)
        result[#result + 1] = B64_CHARS:sub(bit.band(bit.rshift(n, 6), 0x3F) + 1, bit.band(bit.rshift(n, 6), 0x3F) + 1)
        result[#result + 1] = B64_CHARS:sub(bit.band(n, 0x3F) + 1, bit.band(n, 0x3F) + 1)
    end

    -- Replace trailing characters with padding
    for i = 1, padding do
        result[#result - i + 1] = "="
    end

    return table.concat(result)
end

function Codec:FromBase64(str)
    if not str or str == "" then
        return {}
    end

    -- Remove padding and whitespace
    str = str:gsub("%s", ""):gsub("=+$", "")

    local bytes = {}
    local buffer = 0
    local bits = 0

    for i = 1, #str do
        local char = str:sub(i, i)
        local value = B64_DECODE[char]
        if value then
            buffer = bit.bor(bit.lshift(buffer, 6), value)
            bits = bits + 6

            while bits >= 8 do
                bits = bits - 8
                bytes[#bytes + 1] = bit.band(bit.rshift(buffer, bits), 0xFF)
            end
        end
    end

    return bytes
end

-- ================= Scan Result Packing =================

-- Header format: "GCA1:<version>:<codec>:<payload>"
local HEADER_PREFIX = "GCA1"
local CODEC_VERSION = 1
local CODEC_TYPE = "V64"  -- Varint + Base64

function Codec:PackScanResult(itemID, price, rank, timestamp)
    local bytes = {}

    -- Encode itemID (varint)
    for _, v in ipairs(self:EncodeVarint(itemID or 0)) do
        bytes[#bytes + 1] = v
    end

    -- Encode price in copper (varint)
    for _, v in ipairs(self:EncodeVarint(price or 0)) do
        bytes[#bytes + 1] = v
    end

    -- Encode rank (single byte, 1-3)
    bytes[#bytes + 1] = rank or 0

    -- Encode timestamp (varint, delta from epoch base)
    local baseTimestamp = 1700000000  -- ~2023
    local delta = (timestamp or time()) - baseTimestamp
    for _, v in ipairs(self:EncodeVarint(delta)) do
        bytes[#bytes + 1] = v
    end

    -- Convert to Base64
    local payload = self:ToBase64(bytes)

    -- Return with header
    return string.format("%s:%d:%s:%s", HEADER_PREFIX, CODEC_VERSION, CODEC_TYPE, payload)
end

function Codec:UnpackScanResult(encoded)
    if not encoded or encoded == "" then
        return nil
    end

    -- Parse header
    local prefix, version, codecType, payload = encoded:match("^(%w+):(%d+):(%w+):(.+)$")

    if prefix ~= HEADER_PREFIX then
        return nil, "Invalid header"
    end

    version = tonumber(version)
    if version > CODEC_VERSION then
        return nil, "Version too new"
    end

    -- Decode Base64 payload
    local bytes = self:FromBase64(payload)
    if #bytes == 0 then
        return nil, "Empty payload"
    end

    local pos = 1
    local result = {}

    -- Decode itemID
    result.itemID, pos = self:DecodeVarint(bytes, pos)
    if not result.itemID then
        return nil, "Failed to decode itemID"
    end

    -- Decode price
    result.price, pos = self:DecodeVarint(bytes, pos)
    if not result.price then
        return nil, "Failed to decode price"
    end

    -- Decode rank
    result.rank = bytes[pos]
    pos = pos + 1

    -- Decode timestamp
    local delta
    delta, pos = self:DecodeVarint(bytes, pos)
    if delta then
        result.timestamp = 1700000000 + delta
    end

    return result
end

-- ================= Batch Encoding =================

function Codec:PackPriceData(prices)
    -- prices = { [itemID] = { [rank] = { price = copper, timestamp = epoch } } }
    local encoded = {}

    for itemID, ranks in pairs(prices) do
        for rank, data in pairs(ranks) do
            if data.price and data.price > 0 then
                local packed = self:PackScanResult(itemID, data.price, rank, data.timestamp)
                encoded[#encoded + 1] = packed
            end
        end
    end

    return encoded
end

function Codec:UnpackPriceData(encodedList)
    local prices = {}

    for _, encoded in ipairs(encodedList) do
        local result = self:UnpackScanResult(encoded)
        if result and result.itemID and result.price then
            prices[result.itemID] = prices[result.itemID] or {}
            prices[result.itemID][result.rank or 1] = {
                price = result.price,
                timestamp = result.timestamp
            }
        end
    end

    return prices
end

-- ================= Validation =================

function Codec:Validate()
    print("|cff00ff00[GCA Codec]|r Running validation tests...")

    local tests = {
        { itemID = 219947, price = 1234567, rank = 2, ts = 1700000000 },
        { itemID = 210803, price = 500, rank = 3, ts = 1700000001 },
        { itemID = 123456, price = 9999999, rank = 1, ts = 1750000000 },
        { itemID = 1, price = 1, rank = 1, ts = 1700000000 },
        { itemID = 999999, price = 99999999, rank = 3, ts = 1800000000 },
    }

    local passed = 0
    local failed = 0

    for i, test in ipairs(tests) do
        local packed = self:PackScanResult(test.itemID, test.price, test.rank, test.ts)
        local unpacked = self:UnpackScanResult(packed)

        if unpacked and
           unpacked.itemID == test.itemID and
           unpacked.price == test.price and
           unpacked.rank == test.rank and
           unpacked.timestamp == test.ts then
            passed = passed + 1
        else
            failed = failed + 1
            print(string.format("  Test %d FAILED:", i))
            print(string.format("    Expected: itemID=%d price=%d rank=%d ts=%d",
                test.itemID, test.price, test.rank, test.ts))
            if unpacked then
                print(string.format("    Got:      itemID=%d price=%d rank=%d ts=%d",
                    unpacked.itemID or 0, unpacked.price or 0, unpacked.rank or 0, unpacked.timestamp or 0))
            else
                print("    Got: nil")
            end
        end
    end

    -- Test varint edge cases
    local varintTests = { 0, 1, 127, 128, 255, 256, 16383, 16384, 2097151, 2097152 }
    for _, v in ipairs(varintTests) do
        local encoded = self:EncodeVarint(v)
        local decoded = self:DecodeVarint(encoded, 1)
        if decoded ~= v then
            failed = failed + 1
            print(string.format("  Varint test FAILED: %d -> %d", v, decoded or -1))
        else
            passed = passed + 1
        end
    end

    -- Test ZigZag
    local zigzagTests = { 0, 1, -1, 2, -2, 127, -128, 255, -256 }
    for _, v in ipairs(zigzagTests) do
        local encoded = self:EncodeZigZag(v)
        local decoded = self:DecodeZigZag(encoded)
        if decoded ~= v then
            failed = failed + 1
            print(string.format("  ZigZag test FAILED: %d -> %d", v, decoded or -1))
        else
            passed = passed + 1
        end
    end

    if failed == 0 then
        print(string.format("|cff00ff00[GCA Codec]|r All %d tests PASSED!", passed))
    else
        print(string.format("|cffff0000[GCA Codec]|r %d tests passed, %d FAILED", passed, failed))
    end

    return failed == 0
end
