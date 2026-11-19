--[[
    A body in a crouch slide plays the slide's track whatever its posture,
    speed or sprint, and the animations check still asks only for the
    states every game plays, since only a game with a slide gives one
--]]

--!strict
local roblox: any = require("@lune/roblox") -- Its typedefs leave out the datatypes

local Environment = require("../../Environment")

local ANIMATE: string = "src/Client/Rigs/Animate.luau"
local STATE: string = "src/Step/State.luau"
local EXAMPLE: string = "tests/Fixtures/Config/Example.luau"

return function (): (boolean, string | nil)
	local Animate: any = Environment.load(ANIMATE)
	local State: any = Environment.load(STATE)
	local Example: any = Environment.load(EXAMPLE)

	for _, velocity: vector in { vector.zero, vector.create(0, 0, -18) } do
		for _, sprint: boolean in { false, true } do
			local state: any = State.new()
			state.mode = "Slide"
			state.posture = "Crouch"
			state.velocity = velocity
			state.sprint = sprint

			local chosen: string = Animate.choose(state)
			if chosen ~= "slide" then
				return false, `A slide at {velocity}, sprint {sprint}, picked {chosen}, not slide`
			end
		end
	end

	-- The example plays no slide, and the check passes it; a map with one missing state still fails
	local animations: any = Example.client().animations
	local passed: boolean, failure: any = pcall(Animate.check, animations)
	if not passed then
		return false, `The animations check refused a map with no slide: {failure}`
	end

	animations.crawl = nil
	animations.slide = roblox.Instance.new("Animation")
	local refused: boolean = pcall(Animate.check, animations)
	if refused then
		return false, "The animations check passed a map missing crawl because it gave a slide"
	end

	return true, nil
end
