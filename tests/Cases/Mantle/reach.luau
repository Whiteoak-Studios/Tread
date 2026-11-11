--[[
    The mantle's forward search reaches the game's mantle reach past the
    hull's front: a face 1.2 studs past it is found at a reach of 1.39 and
    not at 1.0, and a sliding body finds it as one on the ground does
--]]

--!strict
local Environment = require("../../Environment")

local SLIDES: string = "tests/Fixtures/Step/Slides.luau"
local MANTLE: string = "src/Step/Mantle.luau"
local GAP: number = 1.2 -- Studs from the hull's front to the shelf's face
local REACH: number = 1.39 -- The hull's radius, Frontier Zero's reach
local SHORT: number = 1 -- A reach short of the gap

return function (): (boolean, string | nil)
	local Slides: any = Environment.load(SLIDES)
	local Mantle: any = Environment.load(MANTLE)
	local shelf: any = Slides.shelf
	local face: number = shelf.center.z + shelf.size.z / 2

	-- A body on the floor looking along -Z at the shelf's face, the gap from its hull's front
	local function facing(mode: string): any
		local radius: number = Slides.settings().radius
		local state: any = Slides.state(vector.create(shelf.center.x, Slides.resting, face + radius + GAP), true)
		state.mode = mode
		if mode == "Slide" then
			state.posture = "Crouch"
		end

		return state
	end

	local reaching: any = Slides.world(Slides.settings())
	reaching.settings.mantleReach = REACH
	local short: any = Slides.world(Slides.settings())
	short.settings.mantleReach = SHORT

	for _, mode: string in { "Ground", "Slide" } do
		local found: string? = Mantle.find(facing(mode), reaching)
		if found == nil then
			return false, `In {mode}, a reach of {REACH} found no mantle at a face {GAP} studs past the hull`
		elseif Mantle.find(facing(mode), short) ~= nil then
			return false, `In {mode}, a reach of {SHORT} found a mantle at a face {GAP} studs past the hull`
		end
	end

	-- A press finds it too, and a sliding body ends crouched, as any crouched body's mantle does
	local state: any = facing("Slide")
	local order: any = Slides.command()
	order.forward = 1
	order.crouch = true
	order.jump, order.pressed.jump = true, true
	Slides.advance(state, reaching, order, 1)

	return Slides.verdict(
		Slides.is("the mode after the press", state.mode, "Mantle")
			or Slides.is("the posture after the press", state.posture, "Crouch")
	)
end
