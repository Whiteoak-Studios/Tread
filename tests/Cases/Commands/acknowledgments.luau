--[[
    A connection acknowledges the newest relay sequence its Moves named,
    wrap-safe, with the masks naming it merged, ignores a Move that arrives
    behind a newer one, and keeps its own apart from other connections'
--]]

--!strict
local Intake = require("../../Fixtures/Commands/Intake")

local DELAY: number = 150 -- Milliseconds, the delay the Moves give
local OLD_DELAY: number = 240 -- What a Move that arrives behind a newer one gives

-- Each Move's acknowledgments, and the sequence and mask the connection then reports
type Step = { acknowledged: number, received: number, sequence: number, mask: number, delay: number }

local STEPS: { Step } = {
	{ acknowledged = 5, received = 0b11, sequence = 5, mask = 0b11, delay = DELAY },
	{ acknowledged = 4, received = 0b1, sequence = 5, mask = 0b11, delay = DELAY }, -- Arrives behind the newer Move
	{ acknowledged = 5, received = 0b100, sequence = 5, mask = 0b111, delay = DELAY }, -- Names the same, knowing more
	{ acknowledged = 9, received = 0b10000, sequence = 9, mask = 0b10000, delay = DELAY },
	{ acknowledged = 30000, received = 0, sequence = 30000, mask = 0, delay = DELAY },
	{ acknowledged = 60000, received = 1, sequence = 60000, mask = 1, delay = DELAY },
	{ acknowledged = 65535, received = 0, sequence = 65535, mask = 0, delay = DELAY },
	{ acknowledged = 2, received = 0b100, sequence = 2, mask = 0b100, delay = DELAY }, -- Past the u16 wrap
	{ acknowledged = 65534, received = 0, sequence = 2, mask = 0b100, delay = DELAY }, -- Behind it again
}

return function (): (boolean, string | nil)
	local rig: Intake.Intake = Intake.new()
	local Commands: any = rig.Commands

	local sequence: number, mask: number = Commands.acknowledged(rig.connection)
	if sequence ~= 0 or mask ~= 0 or Commands.delay(rig.connection) ~= 0 then
		return false, "A connection that sent no Move acknowledged something"
	end

	for index: number, step: Step in STEPS do
		local delay: number = DELAY
		if step.sequence ~= step.acknowledged then
			delay = OLD_DELAY
		end

		rig:send({}, step.acknowledged, step.received, delay)

		sequence, mask = Commands.acknowledged(rig.connection)
		if sequence ~= step.sequence or mask ~= step.mask then
			return false, `Move {index} left {sequence}, {mask} acknowledged, not {step.sequence}, {step.mask}`
		elseif Commands.delay(rig.connection) ~= step.delay then
			return false, `After Move {index} the delay is {Commands.delay(rig.connection)}, not {step.delay}`
		end
	end

	-- Another connection's Move changes only its own
	local other: any = rig.Connections.add({ Name = "Other" })
	rig:encode({}, 7, 1, DELAY)
	rig:deliver(other)

	local otherSequence: number, otherMask: number = Commands.acknowledged(other)
	sequence, mask = Commands.acknowledged(rig.connection)
	if otherSequence ~= 7 or otherMask ~= 1 then
		return false, `The other connection acknowledged {otherSequence}, {otherMask}, not its own 7, 1`
	elseif sequence ~= 2 or mask ~= 0b100 then
		return false, `Another connection's Move changed this one's acknowledgments to {sequence}, {mask}`
	end

	return true, nil
end
