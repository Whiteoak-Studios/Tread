--[[
    A roaming bot walks forward toward one seeded goal of its area after
    another, its path the same for the same seed and another for another,
    gives up on a goal it cannot reach, and an idle one sends inputs at rest
--]]

--!strict
local roblox: any = require("@lune/roblox") -- Its typedefs leave out the datatypes

local Harness = require("../../Fixtures/DevBot/Harness")

local SIZE: number = 100 -- The area's width and depth
local SPEED: number = 10 -- Studs a second the walker covers
local RATE: number = 20 -- Ticks a second
local TICKS: number = 2000
local ARRIVE: number = 4 -- The bot harness's config's arrival distance, which a goal is changed within
local SEED: number = 3
local OTHER_SEED: number = 4
local STUCK_TICKS: number = 1200 -- Ticks a walker held in place runs, past several of the longest goals' patience

-- Walks a roaming bot's commands from the area's center, moving the walker along its look, and gives each tick's yaw
local function walk(harness: Harness.Loaded, seed: number, held: boolean): ({ number }, number, any)
	local area: any = { center = roblox.Vector3.new(0, 0, 0), size = roblox.Vector2.new(SIZE, SIZE) }
	local gait: any = { speed = SPEED, rate = RATE, sprint = true, crouch = false, long = false }
	local steer: any = harness.Programs.roam(area, harness.Seeded.new(seed), gait)
	local Command: any =
		harness.loaded.require(harness.loaded.game:GetService("ReplicatedStorage").Packages.Tread.Codec.Command)

	local position: vector = vector.zero
	local yaws: { number } = {}
	local farthest: number = 0
	local command: any = Command.new()
	local ticks: number = held and STUCK_TICKS or TICKS

	for tick: number = 1, ticks do
		steer(command, tick, position)
		table.insert(yaws, command.yaw)

		-- The step's yaw 0 looks along -Z, a quarter turn along -X
		if not held then
			local step: number = SPEED / RATE * command.forward
			position += vector.create(-math.sin(command.yaw) * step, 0, -math.cos(command.yaw) * step)
		end

		farthest = math.max(farthest, math.abs(position.x), math.abs(position.z))
	end

	return yaws, farthest, command
end

-- How many times a list of yaws changes from one tick to the next by more than a hair
local function turns(yaws: { number }): number
	local count: number = 0
	for index: number = 2, #yaws do
		if math.abs(yaws[index] - yaws[index - 1]) > 1e-9 then
			count += 1
		end
	end

	return count
end

return function (): (boolean, string | nil)
	local harness: Harness.Loaded = Harness.load()

	local yaws: { number }, farthest: number, command: any = walk(harness, SEED, false)
	local again: { number } = walk(harness, SEED, false)
	local other: { number } = walk(harness, OTHER_SEED, false)

	if farthest > SIZE / 2 + ARRIVE then
		return false, `A walker roaming a {SIZE}-stud area got {farthest} studs from its center`
	elseif command.forward ~= 1 or command.sprint ~= true or command.crouch ~= false or command.right ~= 0 then
		return false, "A roaming bot did not walk straight ahead at its gait"
	elseif table.concat(again, ",") ~= table.concat(yaws, ",") then
		return false, "The same seed walked another path"
	elseif table.concat(other, ",") == table.concat(yaws, ",") then
		return false, "Another seed walked the same path"
	elseif turns(yaws) < 3 then
		return false, `A walker reached only {turns(yaws)} goals over {TICKS} ticks`
	end

	-- Held in place, a walker gives up on each goal once its patience runs out and turns to the next
	local stuck: { number } = walk(harness, SEED, true)
	if turns(stuck) < 2 then
		return false, `A walker held in place for {STUCK_TICKS} ticks turned {turns(stuck)} times`
	end

	-- A long move's cheat sends a raw diagonal
	local area: any = { center = roblox.Vector3.new(0, 0, 0), size = roblox.Vector2.new(SIZE, SIZE) }
	local long: any = { speed = SPEED, rate = RATE, sprint = false, crouch = true, long = true }
	local diagonal: any = command
	harness.Programs.roam(area, harness.Seeded.new(SEED), long)(diagonal, 1, vector.zero)
	if diagonal.right ~= 1 or diagonal.forward ~= 1 or diagonal.crouch ~= true then
		return false, "A long move did not send forward and right at once, crouched as its gait says"
	end

	-- An idle bot leaves every input as it is
	local before: number = diagonal.yaw
	harness.Programs.idle()(diagonal, 1, vector.zero)
	if diagonal.yaw ~= before then
		return false, "An idle bot changed its command"
	end

	if pcall(harness.Programs.roam, area, harness.Seeded.new(SEED), { speed = 0, rate = RATE }) then
		return false, "Programs.roam took a gait that never moves"
	end

	return true, nil
end
