lu = require('luaunit')

function test_empty()
    lu.assertAlmostEquals(1.0, 1.05, 0.1)
end

os.exit(lu.LuaUnit.run())


