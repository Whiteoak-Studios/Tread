--[[
    A kick adds to a drawn rig's aim within lod.aim, a second adds to one
    still easing, and both are gone once their durations pass, while the
    local player's own rig and a rig not yet drawn take none
--]]

--!strict
local roblox: any = require("@lune/roblox") -- Its typedefs leave out implementProperty and implementMethod
local task = require("@lune/task")

local Environment = require("../../Environment")

local RIGS: string = "src/Client/Rigs/init.luau"
local RIG: string = "tests/Fixtures/Rigs/Rig.luau"
local STATE: string = "src/Step/State.luau"
local MATH: string = "src/Step/Math.luau"
local ANIMATE: string = "ReplicatedStorage.Packages.Tread.Client.Rigs.Animate" -- Where the pool requires it

local OWN: number = 9
local OTHER: number = 3
local UNDRAWN: number = 5 -- Checked out, never posed, so out of Workspace
local PITCH: number = 0.25 -- The aim pitch every pose hands, radians
local KICK_PITCH: number = 0.3 -- The first kick, radians, and its seconds
local KICK_YAW: number = 0.2
local KICK_DURATION: number = 0.2
local SECOND_PITCH: number = 0.1 -- The second, landing while the first eases
local SECOND_YAW: number = 0.05
local SECOND_DURATION: number = 0.1
local WAIT_LIMIT: number = 5 -- Seconds past the kicks' end the wait for it may take
local ROUNDING: number = 1e-12 -- Radians a sum of lerps may sit past its bounds

-- What the layer was last handed for one rig
type Aimed = { pitch: number, yaw: number? }

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

	-- Lune loads no animation, so a stand-in for Animate writes down the aim each drawn rig's layer is handed
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
		aim = function (animated: any, pitch: number, _: number, yaw: number?)
			aimed[animated.rig] = { pitch = pitch, yaw = yaw }
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
	local Math = Environment.load(MATH)

	local calls: { any } = {}
	local rigs = Rigs.new(Rig.settings(calls), Rig.drawDistance, Rig.collision())

	local own: any = rigs:checkout(OWN, {}, true)
	local copy: any = calls[2].rig
	local other: any = rigs:checkout(OTHER, {})
	local undrawn: any = rigs:checkout(UNDRAWN, {})

	local state = State.new()
	state.position = vector.create(10, 0, -5)
	state.mode = "Ground"

	local lod: any = Rig.lod
	local near: number = lod.full / 2
	local far: number = (lod.aim + Rig.drawDistance) / 2 -- Drawn, past lod.aim

	-- Whether a rig's layer took a pitch and a yaw inside their bounds, and why not
	local function within(rig: any, low: number, high: number, lowYaw: number, highYaw: number): string?
		local got: Aimed? = aimed[rig]
		if got == nil then
			return "its layer was handed nothing"
		end

		local yaw: number = got.yaw or 0
		if got.pitch < low - ROUNDING or got.pitch > high + ROUNDING then
			return `its layer took a pitch of {got.pitch}, outside {low} to {high}`
		elseif yaw < lowYaw - ROUNDING or yaw > highYaw + ROUNDING then
			return `its layer took a yaw of {got.yaw}, outside {lowYaw} to {highYaw}`
		end

		return nil
	end

	rigs:pose(OTHER, state, near, PITCH)
	rigs:pose(OWN, state, near, PITCH)

	-- 1) A kick on a drawn rig joins its aim at once, eased out by no more than the time since it landed
	local kicked: number = os.clock()
	rigs:kick(OTHER, KICK_PITCH, KICK_YAW, KICK_DURATION)
	rigs:pose(OTHER, state, near, PITCH)
	local share: number = (os.clock() - kicked) / KICK_DURATION

	local low: number = PITCH + Math.lerp(KICK_PITCH, 0, share)
	local problem: string? = within(other, low, PITCH + KICK_PITCH, Math.lerp(KICK_YAW, 0, share), KICK_YAW)
	if problem then
		return false, `Posed after a kick, {problem}`
	end

	-- 2) A second kick adds to the first, still easing
	local again: number = os.clock()
	rigs:kick(OTHER, SECOND_PITCH, SECOND_YAW, SECOND_DURATION)
	rigs:pose(OTHER, state, near, PITCH)
	local now: number = os.clock()
	local first: number = (now - kicked) / KICK_DURATION
	local second: number = (now - again) / SECOND_DURATION

	low = PITCH + Math.lerp(KICK_PITCH, 0, first) + Math.lerp(SECOND_PITCH, 0, second)
	local lowYaw: number = Math.lerp(KICK_YAW, 0, first) + Math.lerp(SECOND_YAW, 0, second)
	local high: number = PITCH + KICK_PITCH + SECOND_PITCH
	problem = within(other, low, high, lowYaw, KICK_YAW + SECOND_YAW)
	if problem then
		return false, `Posed after a second kick, {problem}`
	end

	-- 3) Past lod.aim the aim is level, kicks and all
	rigs:pose(OTHER, state, far, PITCH)
	problem = within(other, 0, 0, 0, 0)
	if problem then
		return false, `Posed past lod.aim while kicked, {problem}`
	end

	-- 4) The local player's own rig and a rig out of Workspace take no kick
	rigs:kick(OWN, KICK_PITCH, KICK_YAW, KICK_DURATION)
	rigs:kick(UNDRAWN, KICK_PITCH, KICK_YAW, KICK_DURATION)
	rigs:pose(OWN, state, near, PITCH)
	rigs:pose(UNDRAWN, state, near, PITCH)

	local checks: { [string]: any } = {
		["The local player's world rig"] = { rig = own, pitch = PITCH },
		["The first-person copy"] = { rig = copy, pitch = 0 },
		["A rig kicked out of Workspace"] = { rig = undrawn, pitch = PITCH },
	}

	for name: string, check: any in checks do
		problem = within(check.rig, check.pitch, check.pitch, 0, 0)
		if problem then
			return false, `{name}, kicked: {problem}`
		end
	end

	-- 5) Once both durations pass, the aim is the pose's alone
	local ends: number = math.max(kicked + KICK_DURATION, again + SECOND_DURATION)
	local deadline: number = ends + WAIT_LIMIT
	while os.clock() <= ends do
		if os.clock() > deadline then
			return false, `The wait for the kicks to end passed its {WAIT_LIMIT} s`
		end

		task.wait()
	end

	rigs:pose(OTHER, state, near, PITCH)
	local done: Aimed? = aimed[other]
	if done == nil or done.pitch ~= PITCH or done.yaw ~= 0 then
		return false, "Once both kicks' durations passed, the aim still carried a kick"
	end

	rigs:destroy()

	return true, nil
end
