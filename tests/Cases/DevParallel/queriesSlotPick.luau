--[[
    The probe's slot pick: only parts with CanCollide and CanQuery on, each
    once, in the same order twice from one seed, and an error naming both
    numbers when fewer parts qualify than the slots asked for
--]]

--!strict
local roblox: any = require("@lune/roblox") -- Its typedefs leave out the datatypes

local Harness = require("../../Fixtures/DevServer/Harness")

local SEED: number = 362436069
local QUALIFYING: number = 5 -- Of the 8 parts below, those with both flags on
local FEW: number = 3

-- Each part's CanCollide and CanQuery
local FLAGS: { { boolean } } = {
	{ true, true },
	{ false, true },
	{ true, false },
	{ true, true },
	{ true, true },
	{ false, false },
	{ true, true },
	{ true, true },
}

-- The picks' problem: a part with a flag off, one picked twice, or one of the wrong count
local function check(picked: { any }, count: number): string?
	if #picked ~= count then
		return `{count} slots gave {#picked} parts`
	end

	local seen: { [any]: boolean } = {}
	for _, part: any in picked do
		if not part.CanCollide or not part.CanQuery then
			return `{part.Name} was picked with CanCollide {part.CanCollide} and CanQuery {part.CanQuery}`
		elseif seen[part] then
			return `{part.Name} was picked twice`
		end

		seen[part] = true
	end

	return nil
end

return function (): (boolean, string | nil)
	local loaded: any = Harness.load()
	local Queries: any = loaded.require(loaded.game:GetService("ServerScriptService").Server.Parallel.Queries)

	local parts: { any } = {}
	for index: number, flags: { boolean } in FLAGS do
		local part: any = roblox.Instance.new("Part")
		part.Name = `Part{index}`
		part.CanCollide = flags[1]
		part.CanQuery = flags[2]
		table.insert(parts, part)
	end

	-- 1) Every qualifying part once, and only those, in the same order from the same seed
	local all: { any } = Queries.slots(parts, QUALIFYING, SEED)
	local problem: string? = check(all, QUALIFYING)
	if problem then
		return false, problem
	end

	local again: { any } = Queries.slots(parts, QUALIFYING, SEED)
	for index: number, part: any in all do
		if again[index] ~= part then
			return false, `A second pick from the same seed put {again[index].Name} at {index}, not {part.Name}`
		end
	end

	-- 2) A smaller pick keeps to the qualifying parts as well
	problem = check(Queries.slots(parts, FEW, SEED), FEW)
	if problem then
		return false, problem
	end

	-- 3) One slot past the qualifying parts is refused, naming both numbers
	local picked: boolean, refusal: any = pcall(Queries.slots, parts, QUALIFYING + 1, SEED)
	if picked then
		return false, `{QUALIFYING + 1} slots were picked from {QUALIFYING} qualifying parts`
	end

	local said: string = tostring(refusal)
	if not said:find("6 slots", 1, true) or not said:find("5 of 8 parts", 1, true) then
		return false, `The refusal of 6 slots from 5 qualifying parts of 8 said "{said}"`
	end

	return true, nil
end
