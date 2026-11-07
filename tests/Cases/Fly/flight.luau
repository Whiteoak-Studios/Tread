--[[
    While on, the owner's predicted body moves along the look at the fly
    speed with no gravity in place of Tread's step, and off puts Tread's own
    step back in the table, after which the body falls again
--]]

--!strict
local Handle = require("../../Fixtures/Client/Handle")
local Kit = require("../../Fixtures/Exploits/Kit")

local OWN: number = 9
local TICK: number = 100
local PITCH: number = math.pi / 8 -- A pitch the command's wire steps hold exactly
local TICKS: number = 4 -- Ticks of flight measured
local CLOSE: number = 1e-3

return function (): (boolean, string | nil)
	local rig: any = Handle.new({ start = false })

	-- Full forward, looking up
	rig.client.sample = function (command: any)
		command.forward = 1
		command.pitch = PITCH
		command.fields.slot = 0
		command.fields.shots = {}
	end

	rig.start()
	rig.handshake()
	rig.own(OWN, 1)
	rig.owner(rig.body(vector.create(0, 50, 0), 0, TICK))
	rig.frames(2)

	local mounted: Kit.Mounted = Kit.mount(rig)
	local Step: any = rig.globals.require(rig.tread.Step)
	local own: any = Step.advance
	local delta: number = 1 / rig.shared.rates.simulation
	local speed: number = mounted.require(mounted.config).exploits.flySpeed

	local switch: (on: boolean) -> () =
		mounted.require(mounted.exploits.Fly).start({ client = rig.handle, shared = rig.shared })

	switch(true)
	if Step.advance == own then
		return false, "Switching the fly on left Tread's own step in the table"
	end

	-- The body is drawn a tick behind its newest, so two frames in it is a tick into the flight
	rig.frames(2)
	local from: vector = rig.Predict.state().position
	rig.frames(TICKS)
	local to: vector = rig.Predict.state().position

	local look: vector = vector.create(0, math.sin(PITCH), -math.cos(PITCH))
	local expected: vector = from + look * speed * delta * TICKS
	if vector.magnitude(to - expected) > CLOSE then
		return false, `{TICKS} ticks of flight from {from} ended at {to}, not {expected}`
	end

	switch(false)
	if Step.advance ~= own then
		return false, "Switching the fly off didn't put Tread's own step back"
	end

	-- Tread's step runs again, and gravity takes the climb's speed down tick by tick
	rig.frames(2)
	local rising: number = rig.Predict.state().velocity.y
	rig.frames(1)
	local slower: number = rig.Predict.state().velocity.y
	if not (slower < rising) then
		return false, `With the fly off the body's upward speed went from {rising} to {slower}, with no gravity`
	end

	return true, nil
end
