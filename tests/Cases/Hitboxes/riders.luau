--[[
    A remote rider's hitboxes stand on its platform's copy as each frame
    placed it, where Tread draws its rig, and a rider on a platform this
    client never registered, which Tread leaves undrawn, has none shown
--]]

--!strict
local roblox: any = require("@lune/roblox") -- Its typedefs leave out the datatypes

local Environment = require("../../Environment")
local Handle = require("../../Fixtures/Client/Handle")
local Kit = require("../../Fixtures/Exploits/Kit")

local RIDERS: string = "tests/Fixtures/Step/RiderParity.luau"
local DRAWN: string = "Hitboxes" -- The Workspace folder the hitboxes draw in

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
local CLOSE: number = 1e-3

return function (): (boolean, string | nil)
	local Riders: any = Environment.load(RIDERS)
	local rig: any = Handle.new()
	local handle: any = rig.handle
	local mounted: Kit.Mounted = Kit.mount(rig)
	local workspace: any = rig.globals.game:GetService("Workspace")
	local Config: any = rig.globals.require(rig.tread.Config)
	local height: number = rig.shared.step.standing

	local switch: (on: boolean) -> () =
		mounted.require(mounted.exploits.Hitboxes).start({ client = handle, shared = rig.shared })

	-- A lift that rises every tick, so each frame's copy stands somewhere new
	handle:addPlatform(Riders.lift(LIFT, roblox.Vector3.new(30, 60, -10), 0, RISE))

	rig.send("Shared", Config.hash(rig.shared), SERVER_TICK)
	rig.slots({
		{ slot = RIDER, generation = GENERATION, rig = "A" },
		{ slot = STRANDED, generation = GENERATION, rig = "A" },
	})

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

	switch(true)

	for frame: number = 1, FRAMES do
		rig.frames(1)

		local poses: { any } = rig.pool.of("pose")
		local feet: vector = poses[#poses].position
		local drawn: any = workspace:FindFirstChild(DRAWN)
		local rider: any = drawn and drawn:FindFirstChild(`{RIDER}`)
		local stranded: any = drawn and drawn:FindFirstChild(`{STRANDED}`)

		if poses[#poses].slot ~= RIDER then
			return false, `Frame {frame} posed slot {poses[#poses].slot} last, not the rider`
		elseif not rider or not rider.Hull.Visible then
			return false, `On frame {frame} the rider's hull wasn't drawn`
		elseif
			(rider.Hull.CFrame.Position - roblox.Vector3.new(feet.x, feet.y + height / 2, feet.z)).Magnitude > CLOSE
		then
			return false,
				`On frame {frame} the rider's hull sat at {rider.Hull.CFrame.Position}, off its rig's feet at {feet}`
		elseif stranded and stranded.Hull.Visible then
			return false, `On frame {frame} the rider on an unregistered platform had its hull shown`
		end
	end

	switch(false)

	return true, nil
end
