--[[
    A frozen rig's first pose thaws it at the pool's speed, and the frame's
    end moves it to its new place, never out of Workspace. It loads no
    track and takes no draw grant, and once thawed only a pose moves it
--]]

--!strict
local roblox: any = require("@lune/roblox") -- Its typedefs leave out the datatypes, implementProperty and implementMethod

local Environment = require("../../Environment")

local RIGS: string = "src/Client/Rigs/init.luau"
local RIG: string = "tests/Fixtures/Rigs/Rig.luau"
local STATE: string = "src/Step/State.luau"
local ANIMATE: string = "ReplicatedStorage.Packages.Tread.Client.Rigs.Animate" -- Where the pool requires it

local FROZEN: number = 4
local WAITING: number = 5 -- First drawn in the frame the frozen rig thaws
local CAP: number = 1 -- Draws into the Workspace a frame
local DISTANCE: number = 10 -- Studs from the eye, the frozen rig the nearer of the two
local FARTHER: number = 20
local STOOD: vector = vector.create(10, 2, -5) -- Where the rig froze
local REVEALED: vector = vector.create(160, 2, 90) -- Where its first pose after puts it, 177.6 studs on
local HELD: number = 0 -- The track speed a frozen rig holds its pose at
local SLOW: number = 0.5 -- The pool's speed, set before the freeze
local NUDGE: number = 0.001 -- Studs a frozen rig's root stands above its place on alternate frames
local TOLERANCE: number = 1e-4 -- Studs, since a CFrame holds 32-bit floats

-- What Animate's stand-in was asked for one rig
type Asked = { loads: number, speeds: { number }, passed: { number } }

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

	-- Lune loads no animation, so a stand-in for Animate writes down each rig's loads, the speeds its tracks are set
	-- and the speed each pose passes
	local asked: { [any]: Asked } = {}
	local function nothing(_: any) end
	local Animate: { [string]: any } = {
		check = nothing,
		places = function (_: any, _: any): { any }
			return {}
		end,
		load = function (rig: Model, _: any): any
			asked[rig] = asked[rig] or { loads = 0, speeds = {}, passed = {} }
			asked[rig].loads += 1
			return { rig = rig, tracks = {} }
		end,
		speed = function (animated: any, speed: number)
			table.insert(asked[animated.rig].speeds, speed)
		end,
		pose = function (animated: any, _: any, _: boolean, speed: number?)
			table.insert(asked[animated.rig].passed, speed or 1)
		end,
		stop = nothing,
		detail = nothing,
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

	local settings: any = Rig.settings({})
	settings.perFrame = { draws = CAP }
	local rigs: any = Rigs.new(settings, Rig.drawDistance, Rig.collision())
	local model: any = rigs:checkout(FROZEN, {})

	local state = State.new()
	state.mode = "Ground"
	state.position = STOOD

	-- The frame's end grants its first draw, the pool is slowed, and it freezes where that draw put it
	rigs:pose(FROZEN, state, DISTANCE, 0)
	rigs:frame()
	rigs:setSpeed(SLOW)

	local height: number = model.PrimaryPart.CFrame.Position.Y - STOOD.y
	local stood: any = roblox.Vector3.new(STOOD.x, STOOD.y + height, STOOD.z)
	local revealed: any = roblox.Vector3.new(REVEALED.x, REVEALED.y + height, REVEALED.z)

	if not rigs:freeze(FROZEN) then
		return false, "Rigs.freeze refused a drawn rig"
	end
	rigs:frame()

	local holder: any = model.Parent
	local speeds: { number } = asked[model].speeds
	if speeds[#speeds] ~= HELD or holder == nil then
		return false, `A frozen rig's tracks ran at {speeds[#speeds]}, or it left Workspace`
	end

	-- 1) Its first pose, in a frame whose one draw grant another rig asks for, thaws it at the pool's speed
	local waiting: any = rigs:checkout(WAITING, {})
	local held: number = #speeds
	state.position = REVEALED
	rigs:pose(FROZEN, state, DISTANCE, 0)
	rigs:pose(WAITING, state, FARTHER, 0)

	local passed: { number } = asked[model].passed
	if rigs._slots[FROZEN].frozen or #rigs._frozen ~= 0 then
		return false, "A frozen rig's first pose left it frozen"
	elseif #speeds ~= held + 1 or speeds[#speeds] ~= SLOW then
		return false, `The thaw set the rig's tracks' speed to {speeds[#speeds]}, not once to the pool's {SLOW}`
	elseif passed[#passed] ~= SLOW then
		return false, `The thawing pose passed a speed of {passed[#passed]}, not the pool's {SLOW}`
	elseif model.Parent ~= holder then
		return false, "The thawing pose took the rig out of Workspace"
	elseif (model.PrimaryPart.CFrame.Position - stood).Magnitude > NUDGE + TOLERANCE then
		return false, "The thawing pose moved the rig's root before the frame's end"
	end

	-- 2) The frame's end moves it there in its one move, and draws the waiting rig with the grant it never took
	rigs:frame()
	local stands: any = model.PrimaryPart.CFrame.Position
	if (stands - revealed).Magnitude > TOLERANCE then
		return false, `The thaw's frame left the rig at {stands}, not at its new place {revealed}`
	elseif model.Parent ~= holder then
		return false, "The thaw's frame took the rig out of Workspace"
	elseif waiting.Parent == nil then
		return false, "The thaw took the frame's draw grant, so the rig waiting for it wasn't drawn"
	elseif asked[model].loads ~= 1 then
		return false, `The rig's tracks were loaded {asked[model].loads} times, where a thaw loads none`
	end

	-- 3) Thawed, it is moved only when posed: a frame with no pose leaves its root where it stands
	rigs:frame()
	if (model.PrimaryPart.CFrame.Position - stands).Magnitude > TOLERANCE then
		return false, "A frame with no pose moved a thawed rig's root, as if it were still frozen"
	end

	rigs:destroy()

	return true, nil
end
