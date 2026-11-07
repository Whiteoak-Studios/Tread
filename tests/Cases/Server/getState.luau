--[[
    character:getState gives the public State on Vector3, the same table
    with the same values on every read within a tick, refilled in place by
    the next tick's step, with the cleared eye and its look along the facing
--]]

--!strict
local roblox: any = require("@lune/roblox")

local Rig = require("../../Fixtures/Server/Rig")

local TOLERANCE: number = 1e-3 -- Studs, inside a float32's step at the fixture's height
local EYE_QUANTUM: number = 1 / 32 -- The grid the eased eye height sits on

return function (): (boolean, string | nil)
	local rig: Rig.Rig = Rig.new()
	local server: any = rig:start()
	local character: any = server:create(rig.mock:addBot("Bot"), rig:at(0, 0))

	rig:tick(1)

	local first: any = character:getState()
	local root: any = first.root
	local again: any = character:getState()

	if again ~= first or again.root ~= root then
		return false, "Two reads within one tick gave different tables or values"
	elseif typeof(root) ~= "Vector3" or typeof(first.standingBox.cframe) ~= "CFrame" then
		return false, `The public state holds a {typeof(root)} root and a {typeof(first.standingBox.cframe)} box`
	end

	-- Built looking along -Z, so the look at a level pitch with no head offset runs along -Z
	local look: any = first.look
	if math.abs(look.Z + 1) > TOLERANCE or math.abs(look.X) > TOLERANCE or math.abs(look.Y) > TOLERANCE then
		return false, `The look of a character built facing -Z reads {look}`
	end

	-- No ceiling or wall near, so the cleared eye is the standing eye height over the feet, on OwnerState's grid
	local eye: any = first.eye
	local height: number = math.round(rig.shared.step.eyeStanding / EYE_QUANTUM) * EYE_QUANTUM
	if math.abs(eye.Y - (root.Y + height)) > TOLERANCE or eye.X ~= root.X or eye.Z ~= root.Z then
		return false, `The eye sits at {eye}, not {height} studs over the feet at {root}`
	end

	-- Still falling from the rig's lift, so the next step moves it
	rig:tick(1)

	local next: any = character:getState()
	if next ~= first then
		return false, "The next tick's read gave a new table"
	elseif next.root == root then
		return false, "The next tick's read gave the last tick's root"
	elseif next.root.Y >= root.Y then
		return false, `A falling character's root went from {root} to {next.root}`
	elseif
		next.hullCenter ~= roblox.Vector3.new(next.root.X, next.root.Y + rig.shared.step.standing / 2, next.root.Z)
	then
		return false, `The hull center {next.hullCenter} sits off the standing hull over {next.root}`
	end

	return true, nil
end
