--[[
    The sampler's box: a standing walker, a crouched one and a swimmer each
    give the box settle builds, the hull's width by its height centered half
    that height above the feet, read back as Queries reads its boxes
--]]

--!strict
local Harness = require("../../Fixtures/DevServer/Harness")
local Kit = require("../../Fixtures/Exploits/Kit")

local SETTLES: string = "dev/Server/Parallel/Settles.luau"
local CAP: number = 8
local FIRST_TICK: number = 10

-- The step block's keys the box reads, each a value a binary float holds exactly, so every box sums exactly
local SETTINGS: { [string]: number } = { radius = 1.25, standing = 5, crouched = 3 }

-- Each body's posture and mode, its feet before and after its step, and the box worked out by hand from them
type Body = {
	label: string,
	posture: string,
	mode: string,
	from: vector,
	to: vector,
	center: vector,
	size: vector,
}

local BODIES: { Body } = {
	{
		label = "a standing walker",
		posture = "Stand",
		mode = "Ground",
		from = vector.create(12, 3, -40),
		to = vector.create(12.5, 3, -40),
		center = vector.create(12.5, 5.5, -40), -- Half the standing 5 above the feet
		size = vector.create(2.5, 5, 2.5),
	},
	{
		label = "a crouched walker",
		posture = "Crouch",
		mode = "Ground",
		from = vector.create(-30, 7, 64),
		to = vector.create(-30, 7, 64.25),
		center = vector.create(-30, 8.5, 64.25), -- Half the crouched 3 above the feet
		size = vector.create(2.5, 3, 2.5),
	},
	{
		label = "a standing swimmer",
		posture = "Stand",
		mode = "Swim",
		from = vector.create(5, -8, 5),
		to = vector.create(5.5, -8.25, 5),
		center = vector.create(5.5, -6.75, 5), -- A swimmer's hull is crouched whatever its posture
		size = vector.create(2.5, 3, 2.5),
	},
}

return function (): (boolean, string | nil)
	local loaded: Harness.Loaded = Harness.load()
	local dataModel: any = loaded.game
	local server: any = dataModel:GetService("ServerScriptService").Server
	local packages: any = dataModel:GetService("ReplicatedStorage").Packages
	local State: any = loaded.require(packages.Tread.Step.State)
	local Queries: any = loaded.require(server.Parallel.Queries)

	-- Characters and the bot harness's runs stand in empty, since the case hands each read its state
	local results: { [any]: any } = { [packages.Tread.Server.Characters] = {}, [server.Bots.Run] = {} }
	local Settles: any =
		Kit.loader(dataModel, { [server.Parallel.Settles] = SETTLES }, results, loaded.require)(server.Parallel.Settles)

	-- 1) Each body seeded where it stood, then read on the next tick where its step left it
	local sampler: any = Settles.new("Case", CAP, SETTINGS)
	for index: number, body: Body in BODIES do
		local state: any = State.new()
		state.posture = body.posture
		state.mode = body.mode
		state.position = body.from
		state.tick = FIRST_TICK
		Settles.read(sampler, index, state)

		state.position = body.to
		state.tick = FIRST_TICK + 1
		Settles.read(sampler, index, state)
	end

	local recording: any = Settles.recording(sampler)
	local bytes: number = #BODIES * Queries.BOX_WIDTH * Queries.VALUE_BYTES
	if recording.recorded ~= #BODIES or buffer.len(recording.boxes) ~= bytes then
		return false, `{#BODIES} moved walkers recorded {recording.recorded} boxes in {buffer.len(recording.boxes)} B`
	end

	-- 2) Each box, read back as Queries reads a box, is the one settle hands the exact check
	local boxes: { { center: vector, size: vector } } = {}
	Queries.overlaps(recording.boxes, function (center: vector, size: vector): boolean
		table.insert(boxes, { center = center, size = size })

		return false
	end)

	for index: number, body: Body in BODIES do
		local box: { center: vector, size: vector }? = boxes[index]
		if not box then
			return false, `Queries read {#boxes} boxes, none for {body.label}`
		elseif box.center ~= body.center or box.size ~= body.size then
			return false, `{body.label} gave a box at {box.center} of {box.size}, not at {body.center} of {body.size}`
		end
	end

	return true, nil
end
