--[[
    A pose of the local player's own slot draws its first-person copy behind
    its world rig, at full detail, with the same lean and no aim
    pitch, while the world rig keeps the pitch; the copy raises no marker,
    and another slot's pose draws no copy
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
local PITCH: number = 0.4 -- Radians, the owner's aim
local LEAN: number = 12 -- Degrees
local DISTANCE: number = 4 -- Studs from the eye to the world rig's feet
local TOLERANCE: number = 1e-4 -- Studs, since a CFrame holds 32-bit floats

type Drawn = { pitch: number?, lean: number?, aims: number, full: boolean?, fire: ((string, string) -> ())? }

return function (): (boolean, string | nil)
	-- Lune's RunService has no PreSimulation and its Workspace no BulkMoveTo, which a drawn rig needs
	roblox.implementProperty("RunService", "PreSimulation", function (_: any): any
		return {
			Connect = function (_: any, _: () -> ()): any
				return { Disconnect = function (_: any) end }
			end,
		}
	end)
	roblox.implementMethod("Workspace", "BulkMoveTo", function (_: any, parts: { any }, cframes: { any }, _: any)
		for index: number, part: any in parts do
			part.CFrame = cframes[index]
		end
	end)

	-- Lune loads no animation, so a stand-in for Animate writes down what each drawn rig is given
	local drawn: { [any]: Drawn } = {}
	local function of(animated: any): Drawn
		drawn[animated.rig] = drawn[animated.rig] or { aims = 0 }
		return drawn[animated.rig]
	end

	local Animate: { [string]: any } = {
		check = function (_: any) end,
		places = function (_: any, _: any): { any }
			return {}
		end,
		load = function (rig: Model, _: any, _: any, _: any, fire: (string, string) -> ()): any
			local animated: any = { rig = rig, tracks = {} }
			of(animated).fire = fire
			return animated
		end,
		detail = function (animated: any, full: boolean)
			of(animated).full = full
		end,
		pose = function (_: any, _: any, _: boolean) end,
		aim = function (animated: any, pitch: number, lean: number)
			local rig: Drawn = of(animated)
			rig.pitch = pitch
			rig.lean = lean
			rig.aims += 1
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

	local calls: { any } = {}
	local rigs = Rigs.new(Rig.settings(calls), Rig.drawDistance, Rig.collision())

	local world: any = rigs:checkout(OWN, {}, true)
	local copy: any = calls[2].rig
	local other: any = rigs:checkout(OTHER, {})

	local markers: { any } = {}
	rigs:onMarker(function (slot: number, marker: string, _: string)
		table.insert(markers, { slot = slot, marker = marker })
	end)

	local state = State.new()
	state.position = vector.create(10, 0, -5)
	state.facing = 1
	state.lean = LEAN
	state.mode = "Ground"

	rigs:pose(OWN, state, DISTANCE, PITCH)

	local worldDrawn: Drawn? = drawn[world]
	local copyDrawn: Drawn? = drawn[copy]
	local placed: any = world.PrimaryPart.CFrame
	local behind: any = placed.Position - placed.LookVector * Rig.back -- The fixture's back studs along its facing
	if not worldDrawn or not copyDrawn then
		return false, `A pose of the own slot drew the world rig {worldDrawn ~= nil} and the copy {copyDrawn ~= nil}`
	elseif worldDrawn.pitch ~= PITCH or worldDrawn.lean ~= LEAN then
		return false, `The world rig took a pitch of {worldDrawn.pitch} and a lean of {worldDrawn.lean}`
	elseif copyDrawn.pitch ~= 0 or copyDrawn.lean ~= LEAN then
		return false, `The copy took a pitch of {copyDrawn.pitch} and a lean of {copyDrawn.lean}, not 0 and {LEAN}`
	elseif copyDrawn.full ~= true then
		return false, "The copy wasn't drawn at full detail"
	elseif world.Parent == nil or copy.Parent ~= world.Parent then
		return false, "The copy wasn't drawn into Workspace beside the world rig"
	elseif (copy.PrimaryPart.CFrame.Position - behind).Magnitude > TOLERANCE then
		return false, `The copy stands at {copy.PrimaryPart.CFrame.Position}, not {Rig.back} studs behind the world rig`
	elseif (copy.PrimaryPart.CFrame.LookVector - placed.LookVector).Magnitude > TOLERANCE then
		return false, "The copy faces another way than the world rig"
	end

	-- The world rig's markers are the local player's, and the copy's reach nobody
	local copyFire = copyDrawn.fire :: (string, string) -> ()
	local worldFire = worldDrawn.fire :: (string, string) -> ()
	copyFire("Step", "Left")
	worldFire("Step", "Right")
	if #markers ~= 1 or markers[1].slot ~= OWN then
		return false, `The two rigs' markers raised {#markers} callbacks, not the world rig's alone`
	end

	-- Another slot's pose draws its own rig and leaves the copy alone
	local aims: number = copyDrawn.aims
	rigs:pose(OTHER, state, DISTANCE, PITCH)
	if drawn[other] == nil or drawn[other].pitch ~= PITCH then
		return false, "Another slot's pose didn't draw its rig with its pitch"
	elseif copyDrawn.aims ~= aims then
		return false, "Another slot's pose drew the copy"
	end

	rigs:destroy()

	return true, nil
end
