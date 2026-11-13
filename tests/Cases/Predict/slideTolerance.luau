--[[
    A sliding body's correction tolerance is the ground's: a server's state
    in a slide 2 quanta off raises no correction with the ground's at 2 and
    the mantle's at 0, and one 3 quanta off raises one
--]]

--!strict
local Environment = require("../../Environment")
local Harness = require("../../Fixtures/Predict/Harness")

local SLIDES: string = "tests/Fixtures/Step/Slides.luau"
local QUANTUM: number = 1 / 512
local SPRINT_TICKS: number = 4
local SLIDE_TICKS: number = 4 -- Commands into the slide the off state is for
local DEPTH: number = 2

local TOLERANCES: { [string]: number } = { Ground = 2, Air = 0, Swim = 0, Ladder = 0, Rider = 0, Mantle = 0 }

-- How many corrections a server's sliding state some quanta off raises
local function corrections(Slides: any, quanta: number): (number, string)
	local rig: any = Harness.new({
		step = Slides.settings(),
		parts = Slides.parts,
		spawn = vector.create(0, Slides.floor, 100),
		tolerances = TOLERANCES,
	})

	rig.input = function (command: any, sample: number)
		command.forward = 1
		command.sprint = sample <= SPRINT_TICKS
		command.crouch = sample > SPRINT_TICKS
		command.fields.slot = 0
		command.fields.shots = {}
	end

	rig.spawn()
	rig.frames(SPRINT_TICKS + SLIDE_TICKS + 2)

	local server: any = rig.twin(SPRINT_TICKS + SLIDE_TICKS)
	server.position += vector.create(quanta * QUANTUM, 0, 0)
	rig.Predict.receive(rig.owner(server, DEPTH))

	return #rig.corrections, server.mode
end

return function (): (boolean, string | nil)
	local Slides: any = Environment.load(SLIDES)

	local inside: number, mode: string = corrections(Slides, 2)
	if mode ~= "Slide" then
		return false, `The server's state was in {mode}, not a slide, so this case proves nothing`
	elseif inside ~= 0 then
		return false, `A sliding state 2 quanta off raised {inside} corrections, past the ground's tolerance of 2`
	end

	local past: number = corrections(Slides, 3)
	if past ~= 1 then
		return false, `A sliding state 3 quanta off raised {past} corrections, not 1`
	end

	return true, nil
end
