--[[
    A seeded generator gives the same numbers for the same seed and others
    for another, keeps each draw inside its bounds, takes a seed that lands
    on 0 as 1, and refuses a seed that is not whole
--]]

--!strict
local Harness = require("../../Fixtures/DevBot/Harness")

local DRAWS: number = 1000
local SEED: number = 11
local OTHER_SEED: number = 12
local MODULUS: number = 2 ^ 31 - 1 -- The generator's prime, which a seed lands on 0 inside at
local LOW: number = -3
local HIGH: number = 3

local function draws(Seeded: any, seed: number): { number }
	local seeded: any = Seeded.new(seed)
	local values: { number } = {}

	for _ = 1, DRAWS do
		table.insert(values, seeded:next())
	end

	return values
end

return function (): (boolean, string | nil)
	local Seeded: any = Harness.load().Seeded

	local values: { number } = draws(Seeded, SEED)
	if table.concat(draws(Seeded, SEED), ",") ~= table.concat(values, ",") then
		return false, "The same seed drew other numbers"
	elseif table.concat(draws(Seeded, OTHER_SEED), ",") == table.concat(values, ",") then
		return false, "Another seed drew the same numbers"
	elseif table.concat(draws(Seeded, 0), ",") ~= table.concat(draws(Seeded, 1), ",") then
		return false, "A seed of 0 did not draw as 1 does"
	elseif table.concat(draws(Seeded, MODULUS), ",") ~= table.concat(draws(Seeded, 1), ",") then
		return false, "A seed on the modulus did not draw as 1 does"
	end

	local seeded: any = Seeded.new(SEED)
	local lowest: number, highest: number = math.huge, -math.huge
	local seen: { [number]: boolean } = {}

	for _ = 1, DRAWS do
		local value: number = seeded:next()
		local number: number = seeded:number(LOW, HIGH)
		local whole: number = seeded:integer(LOW, HIGH)

		if not (value >= 0 and value < 1) or not (number >= LOW and number < HIGH) then
			return false, `A draw of {value} or {number} fell outside its bounds`
		elseif whole % 1 ~= 0 or whole < LOW or whole > HIGH then
			return false, `A whole draw of {whole} fell outside {LOW} to {HIGH}`
		end

		lowest = math.min(lowest, whole)
		highest = math.max(highest, whole)
		seen[whole] = true
	end

	if lowest ~= LOW or highest ~= HIGH then
		return false, `{DRAWS} whole draws ran from {lowest} to {highest}, not both bounds`
	elseif pcall(Seeded.new, 1.5) or pcall(Seeded.new, "1") then
		return false, "Seeded.new took a seed that is not a whole number"
	end

	return true, nil
end
