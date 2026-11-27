--[[
    A frozen rig released goes back to the pool thawed, out of every later
    frame's move, and is drawn like any other for its next slot. One that
    dies leaves the frozen rigs too, so no frame's end moves a ragdoll
--]]

--!strict
local roblox: any = require("@lune/roblox") -- Its typedefs leave out implementProperty and implementMethod

local Environment = require("../../Environment")

local RIGS: string = "src/Client/Rigs/init.luau"
local RIG: string = "tests/Fixtures/Rigs/Rig.luau"
local STATE: string = "src/Step/State.luau"
local ANIMATE: string = "ReplicatedStorage.Packages.Tread.Client.Rigs.Animate" -- Where the pool requires it

local RELEASED: number = 4 -- Frozen, then released
local DIES: number = 5 -- Frozen, then ragdolled
local NEXT: number = 6 -- The slot the released rig comes back out for
local BODY: number = 15 -- The slot the dying rig is keyed to
local DISTANCE: number = 4 -- Studs from the eye
local MOVED: vector = vector.create(40, 0, 12) -- Where the rig is posed for its next slot
local SLOW: number = 0.5 -- A pool speed set once the rig is out again
local TOLERANCE: number = 1e-4 -- Studs, a tenth of the nudge a frozen rig's root would move by

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
	local function nothing(_: any) end
	local Animate: { [string]: any } = {
		check = nothing,
		places = function (_: any, _: any): { any }
			return {}
		end,
		load = function (rig: Model, _: any): any
			return { rig = rig, tracks = {} }
		end,
		speed = function (animated: any, speed: number)
			speeds[animated.rig] = speed
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
	local rigs: any = Rigs.new(Rig.settings(calls), Rig.drawDistance, Rig.collision())

	local state = State.new()
	state.mode = "Ground"

	local released: any = rigs:checkout(RELEASED, {})
	local dies: any = rigs:checkout(DIES, {})
	rigs:pose(RELEASED, state, DISTANCE, 0)
	rigs:pose(DIES, state, DISTANCE, 0)
	rigs:frame()

	if not rigs:freeze(RELEASED) or not rigs:freeze(DIES) or #rigs._frozen ~= 2 then
		return false, "The pool didn't freeze its two drawn rigs"
	end

	-- 1) The release takes the rig off the frozen rigs and out of Workspace, undressed
	local entry: any = rigs._slots[RELEASED]
	rigs:release(RELEASED)

	local last: any = calls[#calls]
	if entry.frozen or #rigs._frozen ~= 1 or rigs._frozen[1] ~= rigs._slots[DIES] then
		return false, "A frozen rig released stayed among the frozen rigs"
	elseif released.Parent ~= nil then
		return false, "A frozen rig released stayed in Workspace"
	elseif last.hook ~= "undress" or last.rig ~= released then
		return false, "A frozen rig released went back to the pool dressed"
	end

	-- The frame's end still nudges the rig left frozen, and never the one released
	local stood: any = released.PrimaryPart.CFrame.Position
	local other: any = dies.PrimaryPart.CFrame.Position
	rigs:frame()
	if (released.PrimaryPart.CFrame.Position - stood).Magnitude > TOLERANCE then
		return false, "The frame's end moved the root of a frozen rig released to the pool"
	elseif (dies.PrimaryPart.CFrame.Position - other).Magnitude < TOLERANCE then
		return false, "The frame's end left the root of the rig still frozen unmoved"
	end

	-- 2) Out again for another slot, it is drawn, moved and given the pool's speed like any other
	local position: any = roblox.Vector3.new(MOVED.x, MOVED.y + released.PrimaryPart.CFrame.Position.Y, MOVED.z)
	local moved = State.new()
	moved.mode = "Ground"
	moved.position = MOVED

	if rigs:checkout(NEXT, {}) ~= released then
		return false, "A frozen rig released didn't go back to the pool"
	end

	rigs:pose(NEXT, moved, DISTANCE, 0)
	rigs:frame()
	rigs:setSpeed(SLOW)

	if released.Parent == nil or (released.PrimaryPart.CFrame.Position - position).Magnitude > TOLERANCE then
		return false, `The rig's next slot drew it at {released.PrimaryPart.CFrame.Position}, not at {position}`
	elseif speeds[released] ~= SLOW then
		return false, `setSpeed({SLOW}) left the rig's tracks at {speeds[released]} in its next slot`
	end

	-- 3) A frozen rig that dies is its body's, off the frozen rigs, and no frame's end moves its root again
	rigs:ragdoll(DIES, BODY, nil)
	if rigs._slots[BODY].frozen or #rigs._frozen ~= 0 then
		return false, "A frozen rig that died stayed among the frozen rigs"
	end

	other = dies.PrimaryPart.CFrame.Position
	rigs:frame()
	if (dies.PrimaryPart.CFrame.Position - other).Magnitude > TOLERANCE then
		return false, "The frame's end moved a ragdoll's root"
	end

	rigs:destroy()

	return true, nil
end
