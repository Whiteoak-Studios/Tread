--[[
    A frozen rig holds its pose: the freeze sets its tracks' speed to 0 and
    drops the switch it had waiting, and from then on setSpeed and the
    layer leave it alone, while a drawn rig beside it takes each of them
--]]

--!strict
local roblox: any = require("@lune/roblox") -- Its typedefs leave out implementProperty and implementMethod

local Environment = require("../../Environment")

local RIGS: string = "src/Client/Rigs/init.luau"
local RIG: string = "tests/Fixtures/Rigs/Rig.luau"
local STATE: string = "src/Step/State.luau"
local ANIMATE: string = "ReplicatedStorage.Packages.Tread.Client.Rigs.Animate" -- Where the pool requires it

local FROZEN: number = 4
local LIVE: number = 5 -- Drawn beside it and never frozen
local DISTANCE: number = 10 -- Studs from the eye, inside every detail range
local CAP: number = 2 -- Track switches a frame, enough for both rigs' at once
local HELD: number = 0 -- The track speed a frozen rig holds its pose at
local SLOW: number = 0.5 -- A pool speed set once the rig is frozen

-- What Animate's stand-in was asked for one rig
type Asked = { speeds: { number }, layers: number, granted: number }

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

	-- Lune loads no animation, so a stand-in for Animate writes down each rig's speeds, layers and granted switches
	local asked: { [any]: Asked } = {}
	local switching: boolean = false -- Whether each pose keeps its track playing while it waits to switch
	local function nothing(_: any) end
	local Animate: { [string]: any } = {
		check = nothing,
		places = function (_: any, _: any): { any }
			return {}
		end,
		load = function (rig: Model, _: any): any
			asked[rig] = { speeds = {}, layers = 0, granted = 0 }
			return { rig = rig, tracks = {}, granted = false, wanted = false }
		end,
		speed = function (animated: any, speed: number)
			table.insert(asked[animated.rig].speeds, speed)
		end,
		pose = function (animated: any, _: any, _: boolean, _: number?)
			if animated.granted then
				asked[animated.rig].granted += 1
			end

			animated.granted = false
			animated.wanted = switching
		end,
		layer = function (animated: any)
			asked[animated.rig].layers += 1
		end,
		stop = nothing,
		detail = nothing,
		aim = nothing,
		plant = nothing,
		watch = nothing,
		release = nothing,
		markers = function (_: any): { string }
			return {}
		end,
	}

	local Rigs = Environment.load(RIGS, { [ANIMATE] = Animate })
	local Rig = Environment.load(RIG)
	local State = Environment.load(STATE)

	local settings: any = Rig.settings({})
	settings.perFrame = { switches = CAP }
	local rigs: any = Rigs.new(settings, Rig.drawDistance, Rig.collision())

	local frozen: any = rigs:checkout(FROZEN, {})
	local live: any = rigs:checkout(LIVE, {})

	local state = State.new()
	state.mode = "Ground"

	rigs:pose(FROZEN, state, DISTANCE, 0)
	rigs:pose(LIVE, state, DISTANCE, 0)
	rigs:frame()

	-- 1) Both rigs wait to switch track, and the one frozen before the frame's end drops its switch
	switching = true
	rigs:pose(FROZEN, state, DISTANCE, 0)
	rigs:pose(LIVE, state, DISTANCE, 0)
	switching = false

	if rigs:freeze(FROZEN) ~= true then
		return false, "Rigs.freeze refused a drawn rig"
	end

	rigs:frame()
	if asked[live].granted ~= 1 then
		return false, `The frame's end granted the drawn rig's switch {asked[live].granted} times, not once`
	elseif asked[frozen].granted ~= 0 then
		return false, "The frame's end played the switch a rig had waiting when it froze"
	end

	-- 2) The freeze holds its tracks, as a dying rig's are held
	local speeds: { number } = asked[frozen].speeds
	if #speeds ~= 1 or speeds[1] ~= HELD then
		return false, `The freeze set the rig's tracks' speed {#speeds} times, to {speeds[1]}, not once to {HELD}`
	elseif #asked[live].speeds ~= 0 then
		return false, "A freeze reached another rig's tracks"
	end

	-- 3) The pool's speed reaches every drawn rig but the frozen one
	rigs:setSpeed(SLOW)
	if asked[live].speeds[1] ~= SLOW then
		return false, `setSpeed({SLOW}) left the drawn rig at {asked[live].speeds[1]}`
	elseif #speeds ~= 1 then
		return false, `setSpeed({SLOW}) set a frozen rig's tracks to {speeds[#speeds]}`
	end

	-- 4) The layer is written on every drawn rig but the frozen one, which shows its tracks' own pose
	rigs:_layer()
	if asked[live].layers ~= 1 then
		return false, `One simulation step wrote the drawn rig's layer {asked[live].layers} times, not once`
	elseif asked[frozen].layers ~= 0 then
		return false, "A simulation step wrote a frozen rig's layer"
	end

	-- 5) A rig already frozen answers true again and is held no second time
	if rigs:freeze(FROZEN) ~= true then
		return false, "Rigs.freeze answered false for a rig already frozen"
	elseif #speeds ~= 1 or #rigs._frozen ~= 1 then
		return false, "A second freeze of a frozen rig held it again"
	end

	rigs:destroy()

	return true, nil
end
