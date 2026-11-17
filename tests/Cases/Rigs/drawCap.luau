--[[
    Under perFrame.draws a rig's draw into the Workspace waits for the
    frame's end, which draws up to the cap a frame, those that waited from
    frames before first and then the nearest, each placed where its pose
    put it, until all are drawn; a rig back from past the draw distance
    waits as a first draw, and a rig released while it waits is never drawn
--]]

--!strict
local roblox: any = require("@lune/roblox") -- Its typedefs leave out the datatypes, implementProperty and implementMethod

local Environment = require("../../Environment")

local RIGS: string = "src/Client/Rigs/init.luau"
local RIG: string = "tests/Fixtures/Rigs/Rig.luau"
local STATE: string = "src/Step/State.luau"
local ANIMATE: string = "ReplicatedStorage.Packages.Tread.Client.Rigs.Animate" -- Where the pool requires it

local CAP: number = 2
local SLOTS: { number } = { 1, 2, 3, 4, 5 }
local DISTANCES: { [number]: number } = { 50, 10, 40, 20, 30 } -- Studs from the eye, by slot, none in slot order
local LATE: number = 6 -- A slot checked out once the others wait, nearer than all of them
local LATE_DISTANCE: number = 5
local GONE: number = 7 -- A slot released while it waits
local FAR: number = 2000 -- Studs, past the fixture's draw distance
local TOLERANCE: number = 1e-4 -- Studs, since a CFrame holds 32-bit floats

return function (): (boolean, string | nil)
	-- Lune's RunService has no PreSimulation and its Workspace no BulkMoveTo, which a drawn rig needs. Lune takes one
	-- registration of each a run, so a case that ran first may have made it
	pcall(roblox.implementProperty, "RunService", "PreSimulation", function (_: any): any
		return {
			Connect = function (_: any, _: () -> ()): any
				return { Disconnect = function (_: any) end }
			end,
		}
	end)
	pcall(roblox.implementMethod, "Workspace", "BulkMoveTo", function (_: any, parts: { any }, cframes: { any }, _: any)
		for index: number, part: any in parts do
			part.CFrame = cframes[index]
		end
	end)

	-- Lune loads no animation, so Animate's stand-in plays nothing
	local Animate: { [string]: any } = {
		check = function (_: any) end,
		places = function (_: any, _: any): { any }
			return {}
		end,
		load = function (rig: Model, _: any, _: any, _: any, _: (string, string) -> ()): any
			return { rig = rig, tracks = {} }
		end,
		stop = function (_: any) end,
		detail = function (_: any, _: boolean) end,
		pose = function (_: any, _: any, _: boolean, _: number?) end,
		aim = function (_: any, _: number, _: number, _: number, _: number, _: number) end,
		plant = function (_: any, _: any, _: number, _: number, _: any, _: boolean, _: boolean) end,
		layer = function (_: any) end,
		watch = function (_: any, _: string, _: { string }) end,
		release = function (_: any) end,
		markers = function (_: any): { string }
			return {}
		end,
	}

	local Rigs = Environment.load(RIGS, { [ANIMATE] = Animate })
	local Rig = Environment.load(RIG)
	local State = Environment.load(STATE)

	local settings: any = Rig.settings({})
	settings.perFrame = { draws = CAP }
	local rigs: any = Rigs.new(settings, Rig.drawDistance, Rig.collision())

	local models: { [number]: any } = {}
	local states: { [number]: any } = {}
	local distances: { [number]: number } = table.clone(DISTANCES)
	local function take(slot: number, distance: number)
		models[slot] = rigs:checkout(slot, {})
		distances[slot] = distance

		local state = State.new()
		state.mode = "Ground"
		state.position = vector.create(slot * 10, 0, -slot)
		states[slot] = state
	end

	for _, slot: number in SLOTS do
		take(slot, DISTANCES[slot])
	end

	-- The slots drawn into the Workspace, in slot order
	local function drawn(): string
		local list: { number } = {}
		for slot: number = 1, LATE do
			local model: any = models[slot]
			if model and model.Parent ~= nil then
				table.insert(list, slot)
			end
		end

		return table.concat(list, ",")
	end

	-- Every slot checked out posed in slot order, then the frame's end
	local function frame()
		for slot: number = 1, LATE do
			if models[slot] then
				rigs:pose(slot, states[slot], distances[slot], 0)
			end
		end

		rigs:frame()
	end

	-- 1) The poses put no rig into the Workspace, and the frame's end draws the two nearest where they stand
	for _, slot: number in SLOTS do
		rigs:pose(slot, states[slot], distances[slot], 0)
	end

	if drawn() ~= "" then
		return false, `Poses past the cap drew slots {drawn()} at once`
	end

	rigs:frame()
	if drawn() ~= "2,4" then
		return false, `The frame's end drew slots {drawn()}, not the two nearest, 2 and 4`
	end

	local stands: any = models[2].PrimaryPart.CFrame.Position
	if
		math.abs(stands.X - states[2].position.x) > TOLERANCE
		or math.abs(stands.Z - states[2].position.z) > TOLERANCE
	then
		return false, `Slot 2 was drawn at {stands}, not where its pose put it`
	end

	-- 2) A rig nearer than every one waiting comes in: those that waited go first, in the order they came
	take(LATE, LATE_DISTANCE)
	frame()
	if drawn() ~= "2,3,4,5" then
		return false, `The second frame's end left slots {drawn()} drawn, not the waiting 5 and 3 beside 2 and 4`
	end

	frame()
	if drawn() ~= "1,2,3,4,5,6" then
		return false, `The third frame's end left slots {drawn()} drawn, not every slot`
	end

	-- 3) A rig back from past the draw distance waits for the frame's end as a first draw
	rigs:pose(2, states[2], FAR, 0)
	if models[2].Parent ~= nil then
		return false, "A rig posed past the draw distance stayed in the Workspace"
	end

	rigs:pose(2, states[2], distances[2], 0)
	if models[2].Parent ~= nil then
		return false, "A rig back from past the draw distance was drawn past the cap at once"
	end

	rigs:frame()
	if models[2].Parent == nil then
		return false, "The frame's end left a rig back from past the draw distance undrawn"
	end

	-- 4) A rig released while it waits is never drawn, and goes back to the pool out of the Workspace
	local gone: any = rigs:checkout(GONE, {})
	rigs:pose(GONE, states[1], distances[1], 0)
	rigs:release(GONE)
	rigs:frame()
	if gone.Parent ~= nil then
		return false, "A rig released while it waited was drawn"
	elseif rigs:checkout(GONE, {}) ~= gone then
		return false, "A rig released while it waited didn't go back to the pool"
	end

	rigs:destroy()

	return true, nil
end
