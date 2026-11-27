--[[
    A culled enemy's jump makes one footstep entry where it left the ground
    and its landing one where it came down, each on the ground it stood on,
    and a teleport's leap makes none
--]]

--!strict
local roblox: any = require("@lune/roblox") -- Its typedefs leave out the datatypes

local Environment = require("../../Environment")

local Material: any = roblox.Enum.Material

local HARNESS: string = "tests/Fixtures/Relay/Harness.luau"
local QUANTUM: number = 1 / 64
local TAKEOFF: vector = vector.create(12, 0, 3)
local AIRBORNE: vector = vector.create(12.5, 1.25, 3)
local LANDING: vector = vector.create(14, 0, 3)

return function (): (boolean, string | nil)
	local Harness: any = Environment.load(HARNESS)
	local harness: any = Harness.new()
	local client: any = harness:viewer("Viewer")
	local slot: number = harness:spawn("Player", TAKEOFF)
	local state: any = harness.states[slot]

	harness:hide(client, slot, true)
	state.groundMaterial = Material.Wood
	harness:run()

	state.jumps = 1
	state.grounded = false
	state.mode = "Air"
	state.groundMaterial = Material.Air
	state.position = AIRBORNE
	harness:run()

	local steps: { any } = client.seen.footsteps
	if #steps ~= 1 or steps[1].kind ~= "Jump" then
		return false, `The jump made {#steps} entries, not one Jump`
	elseif vector.magnitude(steps[1].at - TAKEOFF) > QUANTUM or steps[1].material ~= Material.Wood then
		return false, `The jump's entry is at {steps[1].at} on {steps[1].material}, not where it left the wood`
	end

	state.lands = 1
	state.grounded = true
	state.mode = "Ground"
	state.groundMaterial = Material.Sand
	state.position = LANDING
	harness:run()

	steps = client.seen.footsteps
	if #steps ~= 1 or steps[1].kind ~= "Land" then
		return false, `The landing made {#steps} entries, not one Land`
	elseif vector.magnitude(steps[1].at - LANDING) > QUANTUM or steps[1].material ~= Material.Sand then
		return false, `The landing's entry is at {steps[1].at} on {steps[1].material}, not where it came down`
	end

	-- A teleport moves it far along the ground under a new epoch, and covers no ground on the way
	state.epoch = 1
	state.position = LANDING + vector.create(30, 0, 0)
	harness:run()

	if #client.seen.footsteps ~= 0 then
		return false, `The teleport made {#client.seen.footsteps} footstep entries`
	end

	return true, nil
end
