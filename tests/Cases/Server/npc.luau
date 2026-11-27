--[[
    An NPC built over the floor falls, lands through onLanded with its handle,
    speed, material and apex, stands, and is found by npcsNear and getAll;
    its getState is the public State, its command moves it, an idle one
    takes no step, and destroyed it is found by neither and refuses calls
--]]

--!strict
local roblox: any = require("@lune/roblox")

local Rig = require("../../Fixtures/Server/Rig")

local DROP: number = 6 -- Studs above the floor it is built at, past the landing airtime
local FALL_TICKS: number = 20
local WALK_TICKS: number = 5
local RANGE: number = 3

return function (): (boolean, string | nil)
	local rig: Rig.Rig = Rig.new()
	local server: any = rig:start()
	local floor: number = rig.floor
	local npc: any = server:createNpc(roblox.CFrame.new(-10, floor + DROP, 0))

	local landings: { { target: any, speed: number, material: any, apex: number } } = {}
	server:onLanded(function (target: any, speed: number, material: any, apex: number)
		table.insert(landings, { target = target, speed = speed, material = material, apex = apex })
	end)

	rig:tick(FALL_TICKS)

	local landing = landings[1]
	if #landings ~= 1 or landing.target ~= npc or not (landing.speed > 0) then
		return false, `The NPC's fall gave {#landings} landings, not one with its handle and a speed`
	elseif landing.material ~= roblox.Enum.Material.Plastic or math.abs(landing.apex - (floor + DROP)) > 0.01 then
		return false, `The landing reported {landing.material} at an apex of {landing.apex}`
	end

	local state: any = npc:getState()
	if typeof(state.root) ~= "Vector3" or not state.grounded or state.mode ~= "Ground" then
		return false, `The landed NPC reads {state.root}, grounded {state.grounded}, in {state.mode}`
	end

	local near: { any } = server:npcsNear(state.root, RANGE)
	if #near ~= 1 or near[1] ~= npc or server:getAll()[1] ~= npc then
		return false, `npcsNear found {#near} NPCs at the NPC, and getAll did not give it`
	end

	-- A command forward along -Z walks it that way
	local before: number = state.root.Z
	npc:command({
		number = 0,
		forward = 1,
		right = 0,
		jump = false,
		crouch = false,
		sprint = false,
		aim = false,
		pressed = { jump = false, crouch = false, sprint = false, aim = false },
		yaw = 0,
		pitch = 0,
		lean = 0,
		headYaw = 0,
		headPitch = 0,
		fields = { slot = 0, shots = {} },
	})
	rig:tick(WALK_TICKS)

	local walked: number = npc:getState().root.Z
	if not (walked < before) then
		return false, `A command forward moved the NPC from Z {before} to {walked}`
	end

	npc:setAwake(false)
	rig:tick(WALK_TICKS)
	if npc:getState().root.Z ~= walked then
		return false, "An idle NPC still stepped"
	end

	npc:destroy()

	if #server:npcsNear(state.root, RANGE * 10) ~= 0 or #server:getAll() ~= 0 then
		return false, "A destroyed NPC was still found"
	elseif pcall(npc.getState, npc) or pcall(npc.destroy, npc) then
		return false, "A destroyed NPC took a call"
	end

	return true, nil
end
