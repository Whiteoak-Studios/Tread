--[[
    Under an NPC budget of 0 a walking NPC waits on alternate ticks from the
    first: on each tick it waits it stays put and the history still holds its
    sample for that tick where it stands, and it steps on the next
--]]

--!strict
local Rig = require("../../Fixtures/Server/Rig")

local TICKS: number = 8
local TOLERANCE: number = 1 / 32 -- Studs, the history's height step
local AT: { number } = { 2, 0 } -- Its x and z, clear of the fixture's obstacles, walking along -Z

return function (): (boolean, string | nil)
	local rig: Rig.Rig = Rig.new(function (_: any, settings: any)
		settings.npcs.budget = 0
	end)

	local server: any = rig:start()
	local Npcs: any = rig:require(rig.tread.Server.Npcs)
	local Tick: any = rig:require(rig.tread.Server.Tick)

	local npc: any = server:createNpc(rig:at(AT[1], AT[2]))
	npc:command({
		forward = 1,
		right = 0,
		jump = false,
		crouch = false,
		sprint = false,
		aim = false,
		yaw = 0,
		pitch = 0,
		lean = 0,
		headYaw = 0,
		headPitch = 0,
		fields = { slot = 0, shots = {} },
	})

	local before: any = npc:getState().root
	for count: number = 1, TICKS do
		local waited: number = Npcs.waited()
		rig:tick(1)

		local tick: number = Tick.counts()
		local root: any = npc:getState().root
		local waits: boolean = count % 2 == 1
		local sample: any = server:sampleAt(npc, tick)

		if Npcs.waited() - waited ~= (waits and 1 or 0) then
			return false, `Tick {tick} made the NPC wait {Npcs.waited() - waited} times, waiting {waits}`
		elseif waits and root ~= before then
			return false, `The NPC moved from {before} to {root} on tick {tick}, which it waited`
		elseif not waits and not ((root - before).Magnitude > TOLERANCE) then
			return false, `The NPC stayed at {root} on tick {tick}, the one after its wait`
		elseif sample == nil then
			return false, `The history held no sample of the NPC for tick {tick}, waiting {waits}`
		elseif (sample.position - root).Magnitude > TOLERANCE then
			return false, `Tick {tick}'s sample stands at {sample.position}, where the NPC stands at {root}`
		end

		before = root
	end

	return true, nil
end
