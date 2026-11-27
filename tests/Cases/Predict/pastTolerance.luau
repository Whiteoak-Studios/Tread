--[[
    A server's state past the tolerance replays and raises one correction
    with its size in studs: 3 quanta off is small with no flag flipped, a
    velocity a quantum off is a correction of no size, and a posture or
    grounded that differs flips a flag
--]]

--!strict
local Harness = require("../../Fixtures/Predict/Harness")

local QUANTUM: number = 1 / 512
local VELOCITY_QUANTUM: number = 1 / 64

type Row = {
	label: string,
	change: (state: any) -> (),
	size: number,
	flagged: boolean,
}

local ROWS: { Row } = {
	{
		label = "3 quanta off",
		change = function (state: any)
			state.position += vector.create(3 * QUANTUM, 0, 0)
		end,
		size = 3 * QUANTUM,
		flagged = false,
	},
	{
		label = "a velocity a quantum off",
		change = function (state: any)
			state.velocity += vector.create(0, 0, VELOCITY_QUANTUM)
		end,
		size = 0,
		flagged = false,
	},
	{
		label = "crouched",
		change = function (state: any)
			state.posture = "Crouch"
		end,
		size = 0,
		flagged = true,
	},
	{
		label = "in the air",
		change = function (state: any)
			state.grounded = false
			state.mode = "Air"
		end,
		size = 0,
		flagged = true,
	},
	{
		label = "with another rule-state block",
		change = function (state: any)
			state.block.sinceShot = 3
		end,
		size = 0,
		flagged = false,
	},
}

return function (): (boolean, string | nil)
	for _, row: Row in ROWS do
		local rig: any = Harness.new()
		rig.spawn()
		rig.frames(4)

		local server: any = rig.twin(2)
		row.change(server)
		rig.Predict.receive(rig.owner(server, 2))

		local corrections: { any } = rig.corrections
		if #corrections ~= 1 then
			return false, `A server's state {row.label} raised {#corrections} corrections, not 1`
		end

		local correction: any = corrections[1]
		if math.abs(correction.size - row.size) > 1e-12 or correction.flagged ~= row.flagged then
			local got: string = `{correction.size} studs, flagged {correction.flagged}`
			return false, `A server's state {row.label} raised {got}, not {row.size} studs, flagged {row.flagged}`
		end
	end

	return true, nil
end
