local verbose = false


local crops = {}
local matrix = {}

-- setup crop rotation data
local function test_setup()
    crops = {
        [1] = { returnPeriod = 2 }, -- BARLEY
        [2] = { returnPeriod = 3 }, -- SOYBEAN
        [3] = { returnPeriod = 3 }, -- CANOLA
        [4] = { returnPeriod = 3 }, -- POTATO
        [5] = { returnPeriod = 1 }, -- MAIZE
        [6] = { returnPeriod = 1 }, -- GRASS
        [7] = { returnPeriod = 2 }, -- WHEAT
        [8] = { returnPeriod = 2 }, -- OAT
        [9] = { returnPeriod = 2 } -- WEIRDOCROP (RP2, GOOD)
    }

    matrix = {
        [1] = {[2] = 2, [3] = 2, [4] = 2},
        [2] = {},
        [3] = {[1] = 2, [2] = 2, [4] = 0, [8] = 2},
        [4] = {[2] = 2, [3] = 0, [4] = 0},
        [5] = {[2] = 2, [3] = 0},
        [6] = {[6] = 2},
        [7] = {[2] = 2, [3] = 2, [7] = 0, [8] = 1},
        [8] = {[2] = 2, [3] = 2},
        [9] = {[9] = 2}
    }
end

-- mock crop rotation
local function getRotationForecropValue(past, current)
    if past == 0 then
        return 2
    end

    return matrix[current][past] or 1
end

local function getRotationForecropMultiplier(prevIndex, lastIndex, currentIndex)
    local prevValue = getRotationForecropValue(prevIndex, currentIndex)
    local lastValue = getRotationForecropValue(lastIndex, currentIndex)

    local prevFactor = -0.025 * prevValue ^ 2 + 0.125 * prevValue -- <0.0 ; 0.15>
    local lastFactor = -0.05 * lastValue ^ 2 + 0.25 * lastValue -- <0.0 ; 0.30>

    return prevFactor + lastFactor + 0.7 -- <0.7 ; 1.15>
end

local function getRotationReturnPeriodMultiplier(prevIndex, lastIndex, currentIndex)
    local returnPeriod = crops[currentIndex].returnPeriod

    if returnPeriod == 2 then
        -- monoculture
        if prevIndex == lastIndex and lastIndex == currentIndex then
            return 0.9
        -- same as last
        elseif lastIndex == currentIndex then
            return 0.95
        end
    elseif returnPeriod == 3 then
        -- monoculture
        if prevIndex == lastIndex and lastIndex == currentIndex then
            return 0.85
        -- same as last
        elseif lastIndex == currentIndex then
            return 0.9
        -- 1 year gap
        elseif prevIndex == currentIndex and lastIndex ~= currentIndex then
            return 0.95
        end
    end

    return 1.0
end

local function getRotationYieldMultiplier(prevIndex, lastIndex, currentIndex)
    local returnPeriod = getRotationReturnPeriodMultiplier(prevIndex, lastIndex, currentIndex)
    local forecrops = getRotationForecropMultiplier(prevIndex, lastIndex, currentIndex)

    return returnPeriod * forecrops
end

-- test framework
function match(expected, actual)
    if #expected == #actual and table.concat(expected) == table.concat(actual) then
        return true
    else
        print(string.format("expected table(%i) = {%s} is not equal to actual table(%i) = {%s}",
                            #expected, table.concat(expected, ", "),
                            #actual, table.concat(actual, ", ")))
        return false
    end
end

-- input: list of crop indices: {1, 2, 3} NOTE: indices must be consecutive natural numbers
-- output: list of multipliers: {1.15, 1.1, 1.0}
function planner(input)
    if #input < 1 then return {} end

    result = {}
    for pos, current in pairs(input) do
        if current ~= 0 then
            lastPos = 1 + math.mod(pos - 1 - 1 + #input, #input)
            prevPos = 1 + math.mod(pos - 2 - 1 + #input, #input)

            last = input[lastPos]
            prev = input[prevPos]

            local mult = getRotationYieldMultiplier(prev, last, current)
            table.insert(result, mult)

            if verbose then
                print(string.format("pos: %i => mult: %f curr: %i last: %i prev: %i", pos, mult, current, last, prev))
            end
        else -- degenerated
            table.insert(result, 0)
        end
    end

    return result
end

-- the tests
function test_plannerDegenerated_empty()
    assert(match({}, planner({})))
end

local function test_plannerDegenerated_zeroes()
    assert(match({0}, planner({0})))
    assert(match({1.05, 0, 1.1}, planner({5, 0, 5})))
end

function test_plannerMonoculture1x()
    assert(match({0.85}, planner({2}))) -- canola(RP3) monoculture
    assert(match({0.90}, planner({1}))) -- barley(RP2) monoculture
    assert(match({1.00}, planner({5}))) -- maize(RP1) monoculture

    assert(match({0.595}, planner({4}))) -- potato(RP3, BAD) -- worst case
    assert(match({0.63}, planner({7}))) -- wheat(RP2, BAD)
    assert(match({1.035}, planner({9}))) -- weirdocrop(RP2, GOOD)
    assert(match({1.15}, planner({6}))) -- grass(RP1, GOOD) -- best case
end

function test_plannerMonoculture2x()
    assert(match({0.85, 0.85}, planner({2, 2}))) -- canola(RP3) monoculture
    assert(match({0.90, 0.90}, planner({1, 1}))) -- barley(RP2) monoculture
    assert(match({1.0, 1.0}, planner({5, 5}))) -- maize(RP1) monoculture

    assert(match({0.595, 0.595}, planner({4, 4}))) -- potato(RP3, BAD) -- worst case
    assert(match({0.63, 0.63}, planner({7, 7}))) -- wheat(RP2, BAD)
    assert(match({1.035, 1.035}, planner({9, 9}))) -- weirdocrop(RP2, GOOD)
    assert(match({1.15, 1.15}, planner({6, 6}))) -- grass(RP1, GOOD) -- best case
end

function test_plannerMonoculture3x()
    assert(match({0.85, 0.85, 0.85}, planner({2, 2, 2}))) -- canola(RP3) monoculture
    assert(match({0.90, 0.90, 0.90}, planner({1, 1, 1}))) -- barley(RP2) monoculture
    assert(match({1.0, 1.0, 1.0}, planner({5, 5, 5}))) -- maize(RP1) monoculture

    assert(match({0.595, 0.595, 0.595}, planner({4, 4, 4}))) -- potato(RP3, BAD) -- worst case
    assert(match({0.63, 0.63, 0.63}, planner({7, 7, 7}))) -- wheat(RP2, BAD)
    assert(match({1.035, 1.035, 1.035}, planner({9, 9, 9}))) -- weirdocrop(RP2, GOOD)
    assert(match({1.15, 1.15, 1.15}, planner({6, 6, 6}))) -- grass(RP1, GOOD) -- best case
end

function test_plannerCereals2x()
    assert(match({1.0, 1.0}, planner({1, 8}))) -- BARLEY/OAT => 1.0
end

function test_plannerCereals3x()
    assert(match({1.0, 1.0, 1.0}, planner({1, 7, 8}))) -- BARLEY/WHEAT/OAT => 1.0
end

function test_plannerPerfect3x()
    crops = { -- all crops have return period of 3 years
        [1] = { returnPeriod = 3 },
        [2] = { returnPeriod = 3 },
        [3] = { returnPeriod = 3 }
    }
    matrix = { -- matrix of perfect forecrops
        [1] = {[2] = 2, [3] = 2},
        [2] = {[1] = 2, [3] = 2},
        [3] = {[1] = 2, [2] = 2}
    }
    assert(match({1.15, 1.15, 1.15}, planner({1, 2, 3})))
end

function test_plannerFallow6x()
    old_ = getRotationForecropValue
    getRotationForecropValue = function (past, current)
        if past == 0 then return 2 end
        return matrix[current][past] or 1
    end

    assert(match({0, 0, 1.15, 0, 0, 1.15}, planner({0, 0, 1, 0, 0, 1})))

    getRotationForecropValue = old_
end

local function run_planner_unittests()
    local test_functions = {
        test_plannerDegenerated_empty,
        test_plannerDegenerated_zeroes,
        test_plannerMonoculture1x,
        test_plannerMonoculture2x,
        test_plannerMonoculture3x,
        test_plannerCereals2x,
        test_plannerCereals3x,
        test_plannerPerfect3x,
        test_plannerFallow6x
    }

    for i, test_func in pairs(test_functions) do
        test_setup()
        test_func()
    end
end

run_planner_unittests()

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
    assert(match(x, skip(x)))
end

function test_skip_last()
    x = {1, 2, 3, -1}
    assert(match({1, 2, 3}, skip(x)))
end

function test_skip_first()
    x = {-1, 1, 2, 3}
    assert(match({1, 2, 3}, skip(x)))
end

function test_skip_mid()
    x = { 1, -1, 2, 3}
    assert(match({1, 2, 3}, skip(x)))
end

function test_skip_mult()
    x = { 1, -1, -1, 2, -1, -1, 3}
    assert(match({1, 2, 3}, skip(x)))
end

local function run_skipper_unittests()
    local test_functions = {
        test_skip_noop,
        test_skip_last,
        test_skip_first,
        test_skip_mid,
        test_skip_mult
    }

    for i, test_func in pairs(test_functions) do
        test_func()
    end
end

run_skipper_unittests()

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
    assert(match(result, unskip(orig, input)))
end

function test_unskip_last()
    orig = {1, 2, 3, -1}
    input = {1.15, 1.1, 1.0}
    result = {"1.15", "1.10", "1.00", "-"}
    assert(match(result, unskip(orig, input)))
end

function test_unskip_endings()
    orig = {-1, 1, 2, 3, -1}
    input = {1.15, 1.1, 1.0}
    result = {"-", "1.15", "1.10", "1.00", "-"}
    assert(match(result, unskip(orig, input)))
end

function test_unskip_middle()
    orig = {-1, 1, -1, 2, 3, -1}
    input = {1.15, 1.1, 1.0}
    result = {"-", "1.15", "-", "1.10", "1.00", "-"}
    assert(match(result, unskip(orig, input)))
end

local function run_unskipper_unittests()
    local test_functions = {
        test_unskip_noop,
        test_unskip_last,
        test_unskip_endings,
        test_unskip_middle
    }

    for i, test_func in pairs(test_functions) do
        test_func()
    end
end

run_unskipper_unittests()
