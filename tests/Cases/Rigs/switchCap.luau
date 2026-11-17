--[[
    Under perFrame.switches a pose past the cap keeps its track playing, and
    the frame's end plays the waiting switches up to the cap a frame: those
    that waited from frames before first, in the order they came, then the
    new ones nearest first, until all of them have played; a first track
    plays at once
--]]

--!strict
local roblox: any = require("@lune/roblox") -- Its typedefs leave out implementProperty and implementMethod

local Environment = require("../../Environment")

local ANIMATE: string = "src/Client/Rigs/Animate.luau"
local ANIMATE_PATH: string = "ReplicatedStorage.Packages.Tread.Client.Rigs.Animate" -- Where the pool requires it
local RIGS: string = "src/Client/Rigs/init.luau"
local RIG: string = "tests/Fixtures/Rigs/Rig.luau"
local STATE: string = "src/Step/State.luau"

local CAP: number = 2
local SLOTS: { number } = { 1, 2, 3, 4, 5 }
local DISTANCES: { number } = { 50, 10, 40, 20, 30 } -- Studs from the eye, by slot, none in the pose order's order
local AHEAD: vector = vector.create(0, 0, -10) -- A walk
local SPRINT_SLOT: number = 2 -- The nearest, which sprints once it walks
local CLIP: string = "rbxassetid://0" -- Every stand-in track's AnimationId, which no clip answers

-- One Play the pool asked of a track: the slot whose rig it is and the state it plays
type Played = { slot: number, state: string }

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

	local Real = Environment.load(ANIMATE)
	local State = Environment.load(STATE)
	local Rig = Environment.load(RIG)

	-- Lune loads no animation, so the real Animate runs over stand-in tracks that write down each Play
	local played: { Played } = {}
	local slotOf: { [any]: number } = {} -- Each rig's slot, by its model

	local function track(rig: Model, state: string): any
		local fake: any = { IsPlaying = false, Looped = true }

		fake.Play = function (self: any)
			self.IsPlaying = true
			table.insert(played, { slot = slotOf[rig], state = state })
		end

		fake.Stop = function (self: any, _: number?)
			self.IsPlaying = false
		end

		fake.AdjustSpeed = function (_: any, _: number) end

		return fake
	end

	local Animate: { [string]: any } = table.clone(Real)
	Animate.markers = function (_: any): { string }
		return {}
	end

	-- What the real load gives, its Animator and tracks stand-ins
	Animate.load = function (rig: Model, joints: any, animations: any, places: any, fire: any): any
		local tracks: { [string]: any } = {}
		for state: string in animations do
			tracks[state] = track(rig, state)
		end

		local animated: any = {
			animator = { PreferLodEnabled = false, EvaluationThrottled = false },
			tracks = tracks,
			playing = nil,
			waits = false,
			granted = false,
			wanted = false,
			speed = 1,
			rate = 1,
			still = false,
			land = tracks.land,
			lands = nil,
			waist = joints.Waist,
			neck = joints.Neck,
			root = joints.Root,
			pitch = 0,
			yaw = 0,
			lean = 0,
			tilt = roblox.CFrame.identity,
			tilted = false,
			headYaw = 0,
			headPitch = 0,
			turn = roblox.CFrame.identity,
			turned = false,
			detailed = false,
			planted = false,
			legs = Real.legs(joints, places),
			connections = {},
			watched = {},
			fire = fire,
		}

		return animated
	end

	local Rigs = Environment.load(RIGS, { [ANIMATE_PATH] = Animate })
	local settings: any = Rig.settings({})
	settings.perFrame = { switches = CAP }

	-- Lune's Animation has no AnimationId until one is set, and the pool reads each track's to read its markers
	for _, animation: any in settings.animations do
		animation.AnimationId = CLIP
	end
	local rigs: any = Rigs.new(settings, Rig.drawDistance, Rig.collision())

	local states: { any } = {}
	for _, slot: number in SLOTS do
		slotOf[rigs:checkout(slot, {})] = slot

		local state = State.new()
		state.mode = "Ground"
		state.grounded = true
		state.position = vector.create(slot * 10, 0, 0)
		states[slot] = state
	end

	-- Every slot posed in slot order, then the frame's end, giving what that frame played
	local function frame(): { Played }
		table.clear(played)
		for _, slot: number in SLOTS do
			rigs:pose(slot, states[slot], DISTANCES[slot], 0)
		end

		local posed: number = #played
		rigs:frame()

		return table.move(played, posed + 1, #played, 1, {})
	end

	local function names(list: { Played }): string
		local parts: { string } = {}
		for _, play: Played in list do
			table.insert(parts, `{play.slot} {play.state}`)
		end

		return table.concat(parts, ", ")
	end

	-- 1) Each rig's first track plays at its first draw, whatever the cap
	table.clear(played)
	frame()
	if #played ~= #SLOTS then
		return false, `The first draws played {#played} tracks, not one for each of the {#SLOTS} rigs`
	end

	-- 2) Every rig turns to a walk: none switches inside its pose, and the frame's end plays the two nearest
	for _, slot: number in SLOTS do
		states[slot].velocity = AHEAD
	end

	table.clear(played)
	for _, slot: number in SLOTS do
		rigs:pose(slot, states[slot], DISTANCES[slot], 0)
	end

	if #played ~= 0 then
		return false, `Poses past the cap switched {names(played)} at once`
	end

	local idle: any = rigs._slots[1].animated.tracks.idle
	if not idle.IsPlaying then
		return false, "A rig whose switch waits stopped the track it was playing"
	end

	rigs:frame()
	if names(played) ~= "2 walk, 4 walk" then
		return false, `The frame's end first played {names(played)}, not the two nearest walks, 2 then 4`
	end

	-- 3) The nearest turns to a sprint: the three that waited go first, in the order they came, and it waits behind
	states[SPRINT_SLOT].sprint = true
	local third: string = names(frame())
	if third ~= "5 walk, 3 walk" then
		return false, `The second frame's end played {third}, not the walks that waited, 5 then 3`
	end

	local fourth: string = names(frame())
	if fourth ~= "1 walk, 2 sprint" then
		return false, `The third frame's end played {fourth}, not the last walk that waited and then the sprint`
	end

	-- 4) Every switch has played, so the next frame plays nothing
	local fifth: { Played } = frame()
	if #fifth ~= 0 then
		return false, `With every switch played, the next frame's end played {names(fifth)}`
	end

	rigs:destroy()

	return true, nil
end
