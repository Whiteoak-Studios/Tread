--[[
    A frozen rig's first pose past the draw distance thaws it and takes it
    out of Workspace as any pose past it does: off the frozen rigs, its
    tracks' speed restored, its last place kept, and drawn again on return
--]]

--!strict
local roblox: any = require("@lune/roblox") -- Its typedefs leave out implementProperty and implementMethod

local Environment = require("../../Environment")

local RIGS: string = "src/Client/Rigs/init.luau"
local RIG: string = "tests/Fixtures/Rigs/Rig.luau"
local STATE: string = "src/Step/State.luau"
local ANIMATE: string = "ReplicatedStorage.Packages.Tread.Client.Rigs.Animate" -- Where the pool requires it

local SLOT: number = 4
local EMPTY: number = 9 -- A slot with no rig
local NEAR: number = 4 -- Studs from the eye
local FAR: number = 5000 -- Past the fixture's draw distance
local STOOD: vector = vector.create(10, 2, -5) -- Where the rig froze
local AWAY: vector = vector.create(60, 2, 40) -- Where its poses after the freeze put it
local HELD: number = 0 -- The track speed a frozen rig holds its pose at
local SLOW: number = 0.5 -- The pool's speed, set before the freeze
local TOLERANCE: number = 1e-4 -- Studs, a tenth of the nudge a frozen rig's root would move by

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

	-- Lune loads no animation, so a stand-in for Animate writes down the speeds the rig's tracks are set and its stops
	local speeds: { number } = {}
	local stops: number = 0
	local function nothing(_: any) end
	local Animate: { [string]: any } = {
		check = nothing,
		places = function (_: any, _: any): { any }
			return {}
		end,
		load = function (rig: Model, _: any): any
			return { rig = rig, tracks = {} }
		end,
		speed = function (_: any, speed: number)
			table.insert(speeds, speed)
		end,
		stop = function (_: any)
			stops += 1
		end,
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

	local rigs: any = Rigs.new(Rig.settings({}), Rig.drawDistance, Rig.collision())
	local model: any = rigs:checkout(SLOT, {})

	local state = State.new()
	state.mode = "Ground"
	state.position = STOOD

	if rigs:placeOf(SLOT) ~= nil then
		return false, `A rig no pose has placed stands at {rigs:placeOf(SLOT)}`
	elseif pcall(rigs.placeOf, rigs, EMPTY) then
		return false, "Rigs.placeOf took a slot with no rig"
	end

	-- Drawn where it stands, the pool slowed, then frozen there
	rigs:pose(SLOT, state, NEAR, 0)
	rigs:frame()
	rigs:setSpeed(SLOW)

	if rigs:placeOf(SLOT) ~= STOOD then
		return false, `The pool has the rig standing at {rigs:placeOf(SLOT)}, not where its pose put it, {STOOD}`
	elseif not rigs:freeze(SLOT) or speeds[#speeds] ~= HELD then
		return false, "The pool didn't freeze its drawn rig with its tracks held"
	end
	rigs:frame()

	-- 1) Its first pose comes from past the draw distance: thawed, at the pool's speed, and out of Workspace
	local held: number = #speeds
	local halted: number = stops
	state.position = AWAY
	rigs:pose(SLOT, state, FAR, 0)

	if rigs._slots[SLOT].frozen or #rigs._frozen ~= 0 then
		return false, "A frozen rig's first pose, past the draw distance, left it frozen"
	elseif #speeds ~= held + 1 or speeds[#speeds] ~= SLOW then
		return false, `That pose set the rig's tracks' speed to {speeds[#speeds]}, not once to the pool's {SLOW}`
	elseif model.Parent ~= nil or stops ~= halted + 1 then
		return false, "A thawing pose past the draw distance left the rig in Workspace, or its tracks playing"
	elseif rigs:placeOf(SLOT) ~= STOOD then
		return false, `A pose past the draw distance moved the place the pool has the rig at to {rigs:placeOf(SLOT)}`
	end

	-- No frame's end moves its root now, and out of Workspace it can't be frozen
	local stood: any = model.PrimaryPart.CFrame.Position
	rigs:frame()
	if (model.PrimaryPart.CFrame.Position - stood).Magnitude > TOLERANCE then
		return false, "The frame's end moved the root of a rig thawed out of Workspace"
	elseif rigs:freeze(SLOT) ~= false then
		return false, "Rigs.freeze froze a rig thawed out of Workspace"
	end

	-- 2) Back inside the draw distance it is drawn and placed like any other
	rigs:pose(SLOT, state, NEAR, 0)
	rigs:frame()

	local stands: any = model.PrimaryPart.CFrame.Position
	if model.Parent == nil then
		return false, "A thawed rig back inside the draw distance wasn't drawn"
	elseif math.abs(stands.X - AWAY.x) > TOLERANCE or math.abs(stands.Z - AWAY.z) > TOLERANCE then
		return false, `Back inside the draw distance the rig was drawn at {stands}, not at {AWAY}`
	elseif rigs:placeOf(SLOT) ~= AWAY then
		return false, `The pool has the rig standing at {rigs:placeOf(SLOT)}, not where its pose put it, {AWAY}`
	end

	rigs:destroy()

	return true, nil
end
