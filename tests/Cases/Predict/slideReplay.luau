--[[
    A crouch slide the owner's client predicts matches the server's own
    step bit for bit: with every tolerance at 0, the server's state for each
    command of a sprint, its slide and its end raises no correction
--]]

--!strict
local Environment = require("../../Environment")
local Harness = require("../../Fixtures/Predict/Harness")

local SLIDES: string = "tests/Fixtures/Step/Slides.luau"
local SPRINT_TICKS: number = 4 -- Samples of the sprint before crouch is pressed
local TICKS: number = 60 -- Frames run, past the slide's 41 ticks and the walk after it
local LAG: number = 2 -- Commands the server's state trails the newest by
local DEPTH: number = 2 -- The queue depth each OwnerState gives, inside the band

local EXACT: { [string]: number } = { Ground = 0, Air = 0, Swim = 0, Ladder = 0, Rider = 0, Mantle = 0 }

return function (): (boolean, string | nil)
	local Slides: any = Environment.load(SLIDES)
	local rig: any = Harness.new({
		step = Slides.settings(),
		parts = Slides.parts,
		spawn = vector.create(0, Slides.floor, 100),
		tolerances = EXACT,
	})

	-- A sprint ahead along -Z, then crouch held with sprint let go, the game's fields at rest
	rig.input = function (command: any, sample: number)
		command.forward = 1
		command.sprint = sample <= SPRINT_TICKS
		command.crouch = sample > SPRINT_TICKS
		command.fields.slot = 0
		command.fields.shots = {}
	end

	rig.spawn()

	local slid: number = 0
	for frame: number = 1, TICKS do
		rig.frames(1)

		local through: number = frame - LAG
		if through >= 1 then
			local server: any = rig.twin(through)
			if server.mode == "Slide" then
				slid += 1
			end

			rig.Predict.receive(rig.owner(server, DEPTH))
			if #rig.corrections > 0 then
				return false, `The server's state for command {through}, in {server.mode}, raised a correction`
			end
		end
	end

	if slid == 0 then
		return false, "The server's step never slid, so this case proves nothing"
	end

	return true, nil
end
