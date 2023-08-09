lu = require('luaunit')

-- SKIP --

function skip(input)
    result = {}
    for i, v in pairs(input) do
        if v ~= -1 then
            table.insert(result, v)
        end
    end
    return result
end

function test_skip_noop()
    x = {1, 2, 3}
    lu.assertEquals(x, skip(x))
end

function test_skip_last()
    x = {1, 2, 3, -1}
    lu.assertEquals({1, 2, 3}, skip(x))
end

function test_skip_first()
    x = {-1, 1, 2, 3}
    lu.assertEquals({1, 2, 3}, skip(x))
end

function test_skip_mid()
    x = { 1, -1, 2, 3}
    lu.assertEquals({1, 2, 3}, skip(x))
end

function test_skip_mult()
    x = { 1, -1, -1, 2, -1, -1, 3}
    lu.assertEquals({1, 2, 3}, skip(x))
end

-- UNSKIP --

function unskip(orig, input)
    local j = 1
    local result = {}
    for k,v in pairs(orig) do
        if v ~= -1 then
            table.insert(result, string.format("%.2f", input[j]))
            j = 1 + j
        else
            table.insert(result, "-")
        end
    end
    return result
end

function test_unskip_noop()
    orig = {1, 2, 3}
    input = {1.15, 1.1, 1.0}
    result = {"1.15", "1.10", "1.00"}

    lu.assertEquals(result, unskip(orig, input))
end

function test_unskip_last()
    orig = {1, 2, 3, -1}
    input = {1.15, 1.1, 1.0}
    result = {"1.15", "1.10", "1.00", "-"}
    lu.assertEquals(result, unskip(orig, input))
end

function test_unskip_endings()
    orig = {-1, 1, 2, 3, -1}
    input = {1.15, 1.1, 1.0}
    result = {"-", "1.15", "1.10", "1.00", "-"}
    lu.assertEquals(result, unskip(orig, input))
end

function test_unskip_middle()
    orig = {-1, 1, -1, 2, 3, -1}
    input = {1.15, 1.1, 1.0}
    result = {"-", "1.15", "-", "1.10", "1.00", "-"}
    lu.assertEquals(result, unskip(orig, input))
end

os.exit(lu.LuaUnit.run())

