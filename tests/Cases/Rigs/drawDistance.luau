--[[
    The pool draws to the distance setDrawDistance gives: a rig drawn at 300
    studs leaves Workspace on its next pose once the distance is 250, comes
    back inside it, and the call refuses what is no distance above 0
--]]

--!strict
local roblox: any = require("@lune/roblox") -- Its typedefs leave out implementProperty and implementMethod

local Environment = require("../../Environment")

local RIGS: string = "src/Client/Rigs/init.luau"
local RIG: string = "tests/Fixtures/Rigs/Rig.luau"
local STATE: string = "src/Step/State.luau"
local ANIMATE: string = "ReplicatedStorage.Packages.Tread.Client.Rigs.Animate" -- Where the pool requires it

local SLOT: number = 2
local SHORTER: number = 250
local BETWEEN: number = 300 -- Inside the fixture's draw distance, past the shorter one
local INSIDE: number = 200

local REFUSED: { any } = { 0, -250, 0 / 0, "250" }

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

	local rigs = Rigs.new(Rig.settings({}), Rig.drawDistance, Rig.collision())
	local state = State.new()
	state.mode = "Ground"

	for _, value: any in REFUSED do
		if pcall(rigs.setDrawDistance, rigs, value) then
			return false, `setDrawDistance took {value}`
		end
	end

	local rig: any = rigs:checkout(SLOT, {})
	rigs:pose(SLOT, state, BETWEEN, 0)
	if rig.Parent == nil then
		return false, `A rig posed at {BETWEEN} studs, inside the draw distance, was not drawn`
	end

	rigs:setDrawDistance(SHORTER)
	rigs:pose(SLOT, state, BETWEEN, 0)
	if rig.Parent ~= nil then
		return false, `A rig posed at {BETWEEN} studs stayed drawn past a draw distance of {SHORTER}`
	end

	rigs:pose(SLOT, state, INSIDE, 0)
	if rig.Parent == nil then
		return false, `A rig posed at {INSIDE} studs was not drawn inside a draw distance of {SHORTER}`
	end

	rigs:release(SLOT)
	rigs:destroy()

	return true, nil
end
