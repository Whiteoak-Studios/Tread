--[[
    The own slot's pose draws the first-person copy firstPerson.back studs
    behind the world rig along its facing, at any facing and as the setting
    changes, the world rig unshifted, and a back of 0 where the rig stands
--]]

--!strict
local roblox: any = require("@lune/roblox") -- Its typedefs leave out the datatypes, implementProperty and implementMethod

local Environment = require("../../Environment")

local RIGS: string = "src/Client/Rigs/init.luau"
local RIG: string = "tests/Fixtures/Rigs/Rig.luau"
local STATE: string = "src/Step/State.luau"
local ANIMATE: string = "ReplicatedStorage.Packages.Tread.Client.Rigs.Animate" -- Where the pool requires it

local OWN: number = 9
local OTHER: number = 3
local DISTANCE: number = 4 -- Studs from the eye to the world rig's feet
local TOLERANCE: number = 1e-4 -- Studs, since a CFrame holds 32-bit floats
local TUNED: number = 2.5 -- Studs, the back a game tunes the setting to while the copy is drawn

-- Radians: along both axes, and along neither
local FACINGS: { number } = { 0, math.pi / 2, 2.3 }

-- Where a rig's root stands, the given studs behind it along its facing
local function behind(rig: any, back: number): any
	local root: any = rig.PrimaryPart.CFrame
	return root.Position - root.LookVector * back
end

local function apart(a: any, b: any): number
	return (a - b).Magnitude
end

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
	local function nothing(...: any) end
	local Animate: { [string]: any } = {
		check = nothing,
		places = function (_: any, _: any): { any }
			return {}
		end,
		load = function (rig: Model, ...: any): any
			return { rig = rig, tracks = {} }
		end,
		stop = nothing,
		detail = nothing,
		pose = nothing,
		aim = nothing,
		plant = nothing,
		layer = nothing,
		watch = nothing,
		release = nothing,
		markers = function (_: any): { string }
			return {}
		end,
	}

	local Rigs = Environment.load(RIGS, { [ANIMATE] = Animate })
	local Rig = Environment.load(RIG)
	local State = Environment.load(STATE)

	local calls: { any } = {}
	local settings: any = Rig.settings(calls)
	local rigs = Rigs.new(settings, Rig.drawDistance, Rig.collision())

	local world: any = rigs:checkout(OWN, {}, true)
	local copy: any = calls[2].rig
	local other: any = rigs:checkout(OTHER, {})

	local state = State.new()
	state.position = vector.create(10, 2, -5)
	state.mode = "Ground"

	for _, facing: number in FACINGS do
		state.facing = facing
		rigs:pose(OWN, state, DISTANCE, 0)
		rigs:pose(OTHER, state, DISTANCE, 0)

		local placed: any = world.PrimaryPart.CFrame
		local drawn: any = copy.PrimaryPart.CFrame
		local stands: any = roblox.Vector3.new(state.position.x, placed.Position.Y, state.position.z)

		-- The world rig stands where any other rig posed from the state does
		if placed ~= other.PrimaryPart.CFrame or apart(placed.Position, stands) > TOLERANCE then
			return false, `At a facing of {facing}, the world rig stands at {placed.Position}, not at the state`
		elseif apart(drawn.Position, behind(world, Rig.back)) > TOLERANCE then
			return false, `At a facing of {facing}, the copy stands at {drawn.Position}, not {Rig.back} studs behind`
		elseif drawn.Position.Y ~= placed.Position.Y or apart(drawn.LookVector, placed.LookVector) > TOLERANCE then
			return false, `At a facing of {facing}, the copy's height or facing differs from the world rig's`
		end
	end

	-- A game tuning the setting moves the copy at its next move
	settings.firstPerson.back = TUNED
	state.position = vector.create(12, 2, -5)
	rigs:pose(OWN, state, DISTANCE, 0)
	local tuned: any = copy.PrimaryPart.CFrame.Position
	if apart(tuned, behind(world, TUNED)) > TOLERANCE then
		return false, `Once tuned, the copy stands at {tuned}, not {TUNED} studs behind`
	end

	rigs:destroy()

	-- A back of 0 draws the copy where its world rig stands
	local stillCalls: { any } = {}
	local stillSettings: any = Rig.settings(stillCalls)
	stillSettings.firstPerson = { back = 0 }
	local stillRigs = Rigs.new(stillSettings, Rig.drawDistance, Rig.collision())

	local stillWorld: any = stillRigs:checkout(OWN, {}, true)
	local stillCopy: any = stillCalls[2].rig
	stillRigs:pose(OWN, state, DISTANCE, 0)
	local stood: any = stillCopy.PrimaryPart.CFrame
	if stood ~= stillWorld.PrimaryPart.CFrame then
		return false, `With a back of 0, the copy stands at {stood.Position}, not at its world rig`
	end

	stillRigs:destroy()

	return true, nil
end
