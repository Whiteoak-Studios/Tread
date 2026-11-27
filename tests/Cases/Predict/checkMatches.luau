--[[
    Each command's check is the server's own hash of its state after it,
    tick by tick through a sprint, a crouch slide, a jump, a crouch and a
    rule-state field the game's rules set, at another queue depth than ours
--]]

--!strict
local Environment = require("../../Environment")
local Harness = require("../../Fixtures/Predict/Harness")

local SLIDES: string = "tests/Fixtures/Step/Slides.luau"
local TICKS: number = 90 -- Frames run, a command each
local SERVER_DEPTH: number = 3 -- The queue the server writes, which the client's prediction never holds
local SINCE_MOST: number = 15 -- The most the fixture game's 4-bit sinceJump holds

-- Sprint, then crouch through a slide and its end, stand, jump, walk on, and last crouch standing still
local function input(command: any, sample: number)
	command.forward = sample <= 75 and 1 or 0
	command.sprint = sample <= 4
	command.crouch = (sample >= 5 and sample <= 50) or (sample >= 76 and sample <= 85)
	command.jump = sample == 56
	command.fields.slot = 0
	command.fields.shots = {}
end

-- The game's rules: sinceJump counts the ticks since the last jump press, up to what its field holds
local function rules(step: any, _: any): number
	local block: any = step.block
	block.sinceJump = step.pressed.jump and 0 or math.min(block.sinceJump + 1, SINCE_MOST)

	return math.huge
end

return function (): (boolean, string | nil)
	local Slides: any = Environment.load(SLIDES)
	local rig: any = Harness.new({
		step = Slides.settings(),
		parts = Slides.parts,
		spawn = vector.create(0, Slides.floor, 100),
		rules = rules,
	})

	rig.input = input
	rig.spawn()

	local hashes: { [number]: number } = {}
	local slid: boolean, jumped: boolean, crouched: boolean, reset: boolean = false, false, false, false
	local since: number = 0

	for number: number = 1, TICKS do
		rig.frames(1)

		local server: any = rig.twin(number)
		slid = slid or server.mode == "Slide"
		jumped = jumped or server.mode == "Air"
		crouched = crouched or (server.mode == "Ground" and server.posture == "Crouch")
		reset = reset or (since > 0 and server.block.sinceJump == 0)
		since = server.block.sinceJump

		hashes[number] = rig.hash(server, SERVER_DEPTH)

		-- The newest command and the ones the Move repeats before it, each held to the server's own state after it
		local move: any = rig.moves[#rig.moves]
		for index: number, sent: number in move.numbers do
			local check: number = move.checks[index]
			if check ~= hashes[sent] then
				return false, `Command {sent} carried check {check}, where the server hashes {hashes[sent]}`
			end
		end
	end

	if not (slid and jumped and crouched and reset) then
		local seen: string = `slide {slid}, jump {jumped}, crouch {crouched}, rules reset {reset}`
		return false, `The stream missed a part this case proves, so it proves less than it says: {seen}`
	end

	return true, nil
end
