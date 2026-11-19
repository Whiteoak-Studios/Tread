--[[
    A rig's head offset reaches its layer at each pose within lod.full and
    not beyond, the first-person copy takes none, and a rig back from the
    pool holds none from the slot it was last drawn for
--]]

--!strict
local roblox: any = require("@lune/roblox") -- Its typedefs leave out implementProperty and implementMethod

local Environment = require("../../Environment")

local RIGS: string = "src/Client/Rigs/init.luau"
local RIG: string = "tests/Fixtures/Rigs/Rig.luau"
local STATE: string = "src/Step/State.luau"
local ANIMATE: string = "ReplicatedStorage.Packages.Tread.Client.Rigs.Animate" -- Where the pool requires it

local OWN: number = 9
local OTHER: number = 3
local NEXT: number = 4 -- The slot the other's rig goes to once back in the pool
local PITCH: number = 0.4 -- Radians
local HEAD_YAW: number = 0.6
local HEAD_PITCH: number = -0.3

-- What the layer was last handed for one rig
type Aimed = { pitch: number, headYaw: number?, headPitch: number? }

-- One distance a rig is posed at, and whether its head turns there
type Reach = { name: string, distance: number, turns: boolean }

return function (): (boolean, string | nil)
	-- Lune's RunService has no PreSimulation and its Workspace no BulkMoveTo, which a drawn rig needs. Lune refuses
	-- a second registration, and another case's stands in the same way, so whichever comes first serves
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

	-- Lune loads no animation, so a stand-in for Animate writes down what each drawn rig's layer is handed
	local aimed: { [any]: Aimed } = {}
	local Animate: { [string]: any } = {
		check = function (_: any) end,
		places = function (_: any, _: any): { any }
			return {}
		end,
		load = function (rig: Model, _: any, _: any, _: any, _: any): any
			return { rig = rig, tracks = {} }
		end,
		detail = function (_: any, _: boolean) end,
		pose = function (_: any, _: any, _: boolean) end,
		aim = function (animated: any, pitch: number, _: number, _: number?, headYaw: number?, headPitch: number?)
			aimed[animated.rig] = { pitch = pitch, headYaw = headYaw, headPitch = headPitch }
		end,
		plant = function (...: any) end,
		layer = function (_: any) end,
		stop = function (_: any) end,
		watch = function (...: any) end,
		markers = function (_: any): { string }
			return {}
		end,
		release = function (_: any) end,
	}

	local Rigs = Environment.load(RIGS, { [ANIMATE] = Animate })
	local Rig = Environment.load(RIG)
	local State = Environment.load(STATE)

	-- Whether a rig's layer took a head offset, and why not
	local function turned(rig: any, headYaw: number, headPitch: number): string?
		local got: Aimed? = aimed[rig]
		if got == nil then
			return "its layer was handed nothing"
		elseif got.headYaw ~= headYaw or got.headPitch ~= headPitch then
			return `its layer took a head offset of {got.headYaw} and {got.headPitch}, not {headYaw} and {headPitch}`
		end

		return nil
	end

	local calls: { any } = {}
	local rigs = Rigs.new(Rig.settings(calls), Rig.drawDistance, Rig.collision())

	local world: any = rigs:checkout(OWN, {}, true)
	local copy: any = calls[2].rig
	local other: any = rigs:checkout(OTHER, {})

	local state = State.new()
	state.position = vector.create(10, 0, -5)
	state.mode = "Ground"

	local lod: any = Rig.lod
	local reaches: { Reach } = {
		{ name = "inside lod.full", distance = lod.full / 2, turns = true },
		{ name = "past lod.full, inside lod.aim", distance = (lod.full + lod.aim) / 2, turns = false },
		{ name = "past lod.aim", distance = (lod.aim + Rig.drawDistance) / 2, turns = false },
	}

	-- 1) Another character's head offset, at each distance
	rigs:turn(OTHER, HEAD_YAW, HEAD_PITCH)
	for _, reach: Reach in reaches do
		rigs:pose(OTHER, state, reach.distance, PITCH)

		local headYaw: number, headPitch: number = 0, 0
		if reach.turns then
			headYaw, headPitch = HEAD_YAW, HEAD_PITCH
		end

		local problem: string? = turned(other, headYaw, headPitch)
		if problem then
			return false, `Posed {reach.name}, {problem}`
		end
	end

	-- 2) The local player's world rig turns its head for other viewers, and its copy keeps it level
	rigs:turn(OWN, HEAD_YAW, HEAD_PITCH)
	rigs:pose(OWN, state, lod.full / 2, PITCH)

	local problem: string? = turned(world, HEAD_YAW, HEAD_PITCH)
	if problem then
		return false, `The local player's world rig: {problem}`
	end

	problem = turned(copy, 0, 0)
	if problem then
		return false, `The first-person copy: {problem}`
	end

	-- 3) Back from the pool for another slot, the rig holds no head offset from the last
	rigs:release(OTHER)
	local reused: any = rigs:checkout(NEXT, {})
	if reused ~= other then
		return false, "The released rig wasn't the one the next checkout took"
	end

	rigs:pose(NEXT, state, lod.full / 2, PITCH)
	problem = turned(reused, 0, 0)
	if problem then
		return false, `A rig back from the pool: {problem}`
	end

	rigs:destroy()

	return true, nil
end
