--[[
    A remote rider is drawn at its place in its platform's space on the
    platform's copy as each frame placed it, so its pose, its distance from
    the eye and the body the owner's prediction blocks against all ride the
    moving copy; a rider on a platform this client never registered isn't
    drawn and blocks nothing
--]]

--!strict
local roblox: any = require("@lune/roblox") -- Its typedefs leave out the datatypes

local Environment = require("../../Environment")
local Handle = require("../../Fixtures/Client/Handle")

local RIDERS: string = "tests/Fixtures/Step/RiderParity.luau"

local RIDER: number = 3
local STRANDED: number = 4 -- Rides a platform the client never registered
local GENERATION: number = 1
local LIFT: number = 6
local UNKNOWN: number = 50
local SERVER_TICK: number = 1000
local RELAY_TICK: number = 400 -- The first relay block's tick
local BLOCKS: number = 6 -- Relay blocks sent, a tick apart, past the render delay
local RISE: number = 0.25 -- Studs the lift rises a simulation tick
local LOCAL: vector = vector.create(1.5, 0.03125, -2) -- The riders' place in their platforms' space, on the record's grid
local FRAMES: number = 3

return function (): (boolean, string | nil)
	local Riders: any = Environment.load(RIDERS)
	local rig: any = Handle.new()
	local handle: any = rig.handle
	local pool: any = rig.pool
	local world: any = handle._world
	local need: any = rig.globals.require
	local Config: any = need(rig.tread.Config)
	local ClientPlatforms: any = need(rig.tread.Client.Platforms)
	local Platforms: any = need(rig.tread.Step.Platforms)

	-- A lift that rises every tick, so each frame's copy stands somewhere new
	handle:addPlatform(Riders.lift(LIFT, roblox.Vector3.new(30, 60, -10), 0, RISE))

	rig.send("Shared", Config.hash(rig.shared), SERVER_TICK)
	rig.slots({
		{ slot = RIDER, generation = GENERATION, rig = "A" },
		{ slot = STRANDED, generation = GENERATION, rig = "A" },
	})

	-- Both standing still in their platforms' space, a block a tick
	for index: number = 0, BLOCKS - 1 do
		local reveals: { any }? = nil
		if index == 0 then
			reveals = {
				{ slot = RIDER, generation = GENERATION, kind = "Player" },
				{ slot = STRANDED, generation = GENERATION, kind = "Player" },
			}
		end

		rig.relay({
			tick = RELAY_TICK + index,
			reveals = reveals,
			records = {
				{ slot = RIDER, generation = GENERATION, position = LOCAL, platform = LIFT },
				{ slot = STRANDED, generation = GENERATION, position = LOCAL, platform = UNKNOWN },
			},
		})
	end

	local before: vector? = nil
	for frame: number = 1, FRAMES do
		local posed: number = #pool.of("pose")
		rig.frames(1)

		local copy: vector? = ClientPlatforms.position(LIFT)
		local expected: vector? = Platforms.at(world, LIFT, handle._ticks)
		if copy == nil or copy ~= expected then
			return false, `On frame {frame} the lift's copy stood at {copy}, not where its path puts it, {expected}`
		end

		local poses: { any } = pool.of("pose")
		local drawn: { any } = {}
		for index: number = posed + 1, #poses do
			table.insert(drawn, poses[index])
		end

		local wanted: vector = LOCAL + copy
		local pose: any = drawn[1]
		if #drawn ~= 1 or pose.slot ~= RIDER then
			return false, `Frame {frame} posed {#drawn} rigs, where the rider alone has a platform drawn`
		elseif pose.position ~= wanted then
			return false, `On frame {frame} the rider was drawn at {pose.position}, not on the lift's copy at {wanted}`
		elseif math.abs(pose.distance - vector.magnitude(wanted)) > 1e-4 then
			return false, `On frame {frame} the rider's distance was {pose.distance}, not its place's from the eye`
		end

		local bodies: { any } = handle._bodies
		if #bodies ~= 1 or bodies[1].position ~= wanted then
			return false, `On frame {frame} the owner blocks against {#bodies} bodies, not the rider on the copy alone`
		end

		-- The lift rose under it since the frame before, and the rider with it
		if before and wanted.y <= before.y then
			return false, `On frame {frame} the rider stood at {wanted.y} studs up, no higher than {before.y} before`
		end

		before = wanted
	end

	return true, nil
end
