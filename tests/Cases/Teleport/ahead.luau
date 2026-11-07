--[[
    Switching the teleport on moves the owner's predicted body the kit's
    distance along the look before its next step, once, with Tread's own
    step back after; off undoes nothing, and forgets a move still waiting
--]]

--!strict
local Handle = require("../../Fixtures/Client/Handle")
local Kit = require("../../Fixtures/Exploits/Kit")

local OWN: number = 9
local TICK: number = 100
local CLOSE: number = 1e-3

return function (): (boolean, string | nil)
	local rig: any = Handle.new()
	rig.handshake()
	rig.own(OWN, 1)
	rig.owner(rig.body(vector.create(0, 50, 0), 0, TICK))
	rig.frames(2)

	local mounted: Kit.Mounted = Kit.mount(rig)
	local Step: any = rig.globals.require(rig.tread.Step)
	local own: any = Step.advance
	local distance: number = mounted.require(mounted.config).exploits.teleport

	local switch: (on: boolean) -> () =
		mounted.require(mounted.exploits.Teleport).start({ client = rig.handle, shared = rig.shared })

	-- The look is level along -Z and the body only falls, so the move shows alone along Z
	local from: vector = rig.Predict.state().position
	switch(true)
	rig.frames(2)
	local to: vector = rig.Predict.state().position
	if math.abs(to.z - (from.z - distance)) > CLOSE or math.abs(to.x - from.x) > CLOSE then
		return false, `The teleport moved the body from {from} to {to}, not {distance} studs along -Z`
	elseif Step.advance ~= own then
		return false, "Once the body had moved, Tread's own step wasn't back in the table"
	end

	rig.frames(2)
	local later: vector = rig.Predict.state().position
	if math.abs(later.z - to.z) > CLOSE then
		return false, `The teleport moved the body again, to {later}`
	end

	switch(false)
	rig.frames(2)
	if math.abs(rig.Predict.state().position.z - to.z) > CLOSE then
		return false, "Switching the teleport off moved the body"
	end

	-- On and off before the body steps again leaves no move behind
	switch(true)
	switch(false)
	if Step.advance ~= own then
		return false, "A move forgotten by the switch off left the step hooked"
	end

	rig.frames(2)
	if math.abs(rig.Predict.state().position.z - to.z) > CLOSE then
		return false, "A move the switch off forgot still moved the body"
	end

	return true, nil
end
