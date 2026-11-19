--[[
    No footstep entry goes for a culled enemy walking crouched, for one
    walking past the walk's earshot, or for an enemy the viewer is sent,
    while one sprinting at that distance is heard to the sprint's
--]]

--!strict
local Environment = require("../../Environment")

local HARNESS: string = "tests/Fixtures/Relay/Harness.luau"
local STRIDE: number = 0.5
local TICKS: number = 30
local LINE: number = 1 -- How near its own line of Z a step must fall to be one enemy's

-- Each enemy walks along its own line of Z, so an entry, which names no player, is told apart by where it fell
local CROUCHED: number = 10
local FAR: number = 45 -- Past the example's 40-stud walking range
local SPRINTER: number = -45 -- Inside its 60-stud sprinting range
local SEEN: number = -10 -- Not culled, so the viewer is sent it

return function (): (boolean, string | nil)
	local Harness: any = Environment.load(HARNESS)
	local harness: any = Harness.new()
	local client: any = harness:viewer("Viewer")

	local lines: { [number]: number } = {}
	for _, z: number in { CROUCHED, FAR, SPRINTER, SEEN } do
		lines[harness:spawn("Player", vector.create(0, 0, z))] = z
	end

	for slot: number, z: number in lines do
		harness:hide(client, slot, z ~= SEEN)
		harness.states[slot].posture = z == CROUCHED and "Crouch" or "Stand"
		harness.states[slot].sprint = z == SPRINTER
	end

	harness:run()

	local heard: { [number]: number } = { [CROUCHED] = 0, [FAR] = 0, [SPRINTER] = 0, [SEEN] = 0 }
	for _ = 1, TICKS do
		for slot: number in lines do
			harness.states[slot].position += vector.create(STRIDE, 0, 0)
		end

		harness:run()

		for _, step: any in client.seen.footsteps do
			for _, z: number in lines do
				if math.abs(step.at.z - z) < LINE then
					heard[z] += 1
				end
			end
		end
	end

	if heard[CROUCHED] ~= 0 then
		return false, `The crouched enemy made {heard[CROUCHED]} footstep entries`
	elseif heard[FAR] ~= 0 then
		return false, `The enemy walking past the walking range made {heard[FAR]} footstep entries`
	elseif heard[SEEN] ~= 0 then
		return false, `The enemy the viewer is sent made {heard[SEEN]} footstep entries`
	elseif heard[SPRINTER] == 0 then
		return false, "The enemy sprinting inside the sprinting range made no footstep entry"
	end

	return true, nil
end
