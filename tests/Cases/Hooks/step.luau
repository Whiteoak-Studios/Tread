--[[
    A body move waiting when the step is replaced lands before the
    replacement runs, once, and Tread's own step is back in the table only
    once nothing replaces it or waits to move the body
--]]

--!strict
local Handle = require("../../Fixtures/Client/Handle")
local Kit = require("../../Fixtures/Exploits/Kit")

local OWN: number = 9
local TICK: number = 100
local BY: vector = vector.create(3, 0, 0) -- The body's move

return function (): (boolean, string | nil)
	local rig: any = Handle.new()
	rig.handshake()
	rig.own(OWN, 1)
	rig.owner(rig.body(vector.create(0, 50, 0), 0, TICK))
	rig.frames(2)

	local mounted: Kit.Mounted = Kit.mount(rig)
	local Hooks: any = mounted.require(mounted.exploits.Hooks)
	local Step: any = rig.globals.require(rig.tread.Step)
	local own: any = Step.advance
	local seen: { vector } = {} -- Where each replaced step found the body

	-- A step that holds the body where it finds it
	Hooks.replace(function (state: any, _: any, _: any): (number, number?)
		table.insert(seen, state.position)

		return 0, nil
	end)

	local from: vector = rig.Predict.state().position
	Hooks.nudge(BY)
	rig.frames(3)

	if #seen ~= 3 then
		return false, `The replacement ran {#seen} times over 3 ticks`
	elseif seen[1] ~= seen[3] or math.abs(seen[1].x - (from.x + BY.x)) > 1e-6 then
		-- The body falls only along Y, so the move shows alone along X
		return false, `The replacement found the body at {seen[1]} then {seen[3]}, not moved once by {BY} from {from}`
	elseif Step.advance == own then
		return false, "Tread's own step came back while the replacement was still set"
	end

	Hooks.replace(nil)
	if Step.advance ~= own then
		return false, "With nothing replacing it or waiting, Tread's own step wasn't back"
	end

	Hooks.nudge(BY)
	Hooks.nudge(nil)
	if Step.advance ~= own then
		return false, "A forgotten move left the step hooked"
	end

	return true, nil
end
