--[[
    Under perFrame.ragdolls a dying rig is re-keyed to its body at once and
    holds its pose, and the frame's end starts its ragdoll up to the cap a
    frame: those that waited from frames before first, in the order they
    came, then the new ones nearest first, until every one has started; a
    rig released while it waits goes back to the pool unragdolled
--]]

--!strict
local roblox: any = require("@lune/roblox") -- Its typedefs leave out implementProperty and implementMethod

local Environment = require("../../Environment")

local RIGS: string = "src/Client/Rigs/init.luau"
local RIG: string = "tests/Fixtures/Rigs/Rig.luau"
local STATE: string = "src/Step/State.luau"
local ANIMATE: string = "ReplicatedStorage.Packages.Tread.Client.Rigs.Animate" -- Where the pool requires it

local CAP: number = 1
local DISTANCES: { number } = { 30, 10, 20, 5, 1 } -- Studs from the eye each slot's rig was last drawn at, by slot
local BODY: number = 10 -- A slot's body is this many slots on
local HELD: number = 0 -- The track speed a dying rig holds its pose at

return function (): (boolean, string | nil)
	-- Lune's RunService has no PreSimulation and its Workspace no BulkMoveTo, which a drawn rig needs. Lune takes one
	-- registration of each a run, so a case that ran first may have made it; with no collision groups a ragdoll warns
	-- and carries on
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

	-- Lune loads no animation, so a stand-in for Animate writes down each rig's last speed
	local speeds: { [any]: number } = {}
	local Animate: { [string]: any } = {
		check = function (_: any) end,
		places = function (_: any, _: any): { any }
			return {}
		end,
		load = function (rig: Model, _: any, _: any, _: any, _: (string, string) -> ()): any
			return { rig = rig, tracks = {} }
		end,
		speed = function (animated: any, speed: number)
			speeds[animated.rig] = speed
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
	settings.perFrame = { ragdolls = CAP }
	local rigs: any = Rigs.new(settings, Rig.drawDistance, Rig.collision())

	-- Every rig drawn once at its distance
	local models: { any } = {}
	for slot: number, distance: number in DISTANCES do
		models[slot] = rigs:checkout(slot, {})

		local state = State.new()
		state.mode = "Ground"
		state.position = vector.create(slot * 10, 0, 0)
		rigs:pose(slot, state, distance, 0)
	end
	rigs:frame()

	-- The slots whose rigs have ragdolled, in slot order
	local function ragdolled(): string
		local list: { number } = {}
		for slot: number, model: any in models do
			if model:FindFirstChildWhichIsA("BallSocketConstraint", true) then
				table.insert(list, slot)
			end
		end

		return table.concat(list, ",")
	end

	-- 1) Three deaths: each rig is its body's at once, holding its pose, and none ragdolls before the frame's end
	for slot: number = 1, 3 do
		rigs:ragdoll(slot, slot + BODY, nil)
	end

	if ragdolled() ~= "" then
		return false, `Deaths past the cap ragdolled slots {ragdolled()} at once`
	end

	for slot: number = 1, 3 do
		if speeds[models[slot]] ~= HELD then
			return false, `Slot {slot}'s dying rig played on at {speeds[models[slot]]} while its ragdoll waited`
		elseif pcall(rigs.pose, rigs, slot, State.new(), 1, 0) then
			return false, `Slot {slot} still had a rig once its rig died`
		end
	end

	if pcall(rigs.ragdoll, rigs, 1 + BODY, 1 + BODY, nil) or pcall(rigs.lie, rigs, 1 + BODY, 1 + BODY) then
		return false, "A dying rig whose ragdoll waits was ragdolled or laid down again"
	end

	-- 2) The frame's end starts the nearest, and a nearer death after it waits behind the two that waited
	rigs:frame()
	if ragdolled() ~= "2" then
		return false, `The first frame's end ragdolled slots {ragdolled()}, not the nearest, 2`
	end

	rigs:ragdoll(4, 4 + BODY, nil)

	local sequence: { string } = {}
	for _ = 1, 3 do
		rigs:frame()
		table.insert(sequence, ragdolled())
	end

	local wanted: string = "2,3 then 1,2,3 then 1,2,3,4"
	if table.concat(sequence, " then ") ~= wanted then
		return false, `The next frames' ends ragdolled {table.concat(sequence, " then ")}, not {wanted}`
	end

	-- 3) A rig released while its ragdoll waits goes back to the pool unragdolled
	rigs:ragdoll(5, 5 + BODY, nil)
	rigs:release(5 + BODY)
	rigs:frame()

	if models[5]:FindFirstChildWhichIsA("BallSocketConstraint", true) then
		return false, "A rig released while its ragdoll waited was ragdolled"
	elseif rigs:checkout(5, {}) ~= models[5] then
		return false, "A rig released while its ragdoll waited didn't go back to the pool"
	end

	rigs:destroy()

	return true, nil
end
