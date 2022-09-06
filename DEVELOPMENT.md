# Long-term fertility map

PL
długoterminowa poprawa żyzności (long-term fertility improvement)
budowanie warstwy czarnoziemu (ang. humus) przez resztki pożniwne (przyśpieszane przez gnojówkę) i obornik, który robi za rezerwuar składników odżywczych
erozja czarnoziemu przez deszcz i suszę (humidity map)
aktualizowanie zawartości 4x w roku

range:  <-0.2 ; 0.1> nonlinear



PF_ValueMap = FS22_precisionFarming.ValueMap

BiomassMap = {
    MAP_NUM_CHANNELS = 3
}

BiomassMap_mt = Class(BiomassMap, PF_ValueMap)

function BiomassMap.new(pfModule, customMt)
    local self = PF_ValueMap.new(pfModule, customMt or BiomassMap_mt)

    return self
end



    --[[
    BIT MAPPING
    [D:1] lvl-up due to liquid manure/digestate
    [M:1] lvl-up due to manure
    [L:1] lvl-up due to green biomass (harvest leftovers)

    [R2:5] crop that was growing two harvests ago
    [R1:5] crop that was growing before current crop
    [F:1] fallow bit
    [H:1] harvest bit
    ]]--

    -- TODO: * cropRotation:getSoilConditionYieldMultiplier()
    -- TODO: read BiomassMap for level!

---Calculate the yield multiplier based on the soil condition
-- TODO: move to BiomassMap
function CropRotation:getSoilConditionYieldMultiplier(v)
    --[[
    F(v) = v^3/500 - v^2/50 - v/125 + 1.15

    F(perfect) = 1.15
    F(good_2) = 1.125
    F(good_1) = 1.07
    F(ok_2) = 1.0
    F(ok_1) = 0.93
    F(bad_3) = 0.86
    F(bad_2) = 0.815
    F(bad_1) = 0.8
    --]]
    return 0.002 * v ^ 3 - 0.02 * v ^ 2 - 0.008 * v + 1.15
end
