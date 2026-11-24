--[[
    The kit's hooked step hands Tread's own the exact argument it was
    given: asked on a command that is no tenth, a body inside a part is
    freed through the hook, and left out it stays
--]]

--!strict
local Handle = require("../../Fixtures/Client/Handle")
local Kit = require("../../Fixtures/Exploits/Kit")

local SPOT_X: number = -20 -- Where the body stands, clear of every fixture part
local SPOT_Z: number = -10
local POST_SIZE: vector = vector.create(1, 8, 1) -- Narrower than the hull and taller, so only the exact check finds it
local ASKED: number = 13 -- A command that is no tenth

-- A command with no input, its presses all off
local function newCommand(number: number): any
	return {
		number = number,
		forward = 0,
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
		fields = {},
	}
end

return function (): (boolean, string | nil)
	local rig: any = Handle.new()
	local mounted: Kit.Mounted = Kit.mount(rig)
	local Hooks: any = mounted.require(mounted.exploits.Hooks)
	local Step: any = rig.globals.require(rig.tread.Step)
	local Math: any = rig.globals.require(rig.tread.Step.Math)
	local Constants: any = rig.globals.require(rig.tread.Constants)
	local own: any = Step.advance

	local fixtures: any = rig.globals.game:GetService("ServerScriptService").Fixtures.Step
	local Scene: any = rig.globals.require(fixtures.Scene)
	local Casts: any = rig.globals.require(fixtures.Collision)
	local Geometry: any = rig.globals.require(fixtures.Geometry)

	local parts: { any } = table.clone(Geometry.parts)
	table.insert(parts, {
		name = "Post",
		center = vector.create(SPOT_X, Geometry.floor + POST_SIZE.y / 2, SPOT_Z),
		size = POST_SIZE,
		tilt = 0,
	})

	-- Feet on the quantum, so the still body's rounding never moves it and only the exact check can free it
	local spot: vector = vector.create(SPOT_X, Math.quantize(Geometry.floor + Constants.SKIN), SPOT_Z)
	local world: any = Scene.world(Casts(parts))
	world.tick = ASKED

	-- A move of nothing waiting hooks the step, and the next step through the table runs the hook
	for _, asked: boolean in { false, true } do
		local state: any = Scene.state(spot, true)
		Hooks.nudge(vector.zero)
		if Step.advance == own then
			return false, "A move waiting left Tread's own step in the table"
		end

		if asked then
			Step.advance(state, newCommand(ASKED), world, true)
		else
			Step.advance(state, newCommand(ASKED), world)
		end

		if Step.advance ~= own then
			return false, "Once the waiting move had run, Tread's own step wasn't back in the table"
		elseif asked and state.position == spot then
			return false, `Asked through the hook on command {ASKED}, the body was still inside the part`
		elseif not asked and state.position ~= spot then
			return false, `Left out through the hook on command {ASKED}, the body left the part for {state.position}`
		end
	end

	return true, nil
end
