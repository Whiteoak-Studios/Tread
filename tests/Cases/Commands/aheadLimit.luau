--[[
    A command up to ticks.ahead past the newest tick stepped waits for its
    tick, one further ahead is dropped and reported once a Move with its
    ticks ahead, and the same command sent again inside the limit is filed
--]]

--!strict
local Intake = require("../../Fixtures/Commands/Intake")

local START: number = 100 -- The first tick stepped
local AHEAD: number = 5 -- Frontier Zero's ticks.ahead

return function (): (boolean, string | nil)
	local rig: Intake.Intake = Intake.new()
	rig:take(START)

	-- Commands 7, 6, 5, 4 and 3 ticks ahead
	rig:send(rig:commands(START + 7, 5))

	local ahead: { number | string } = rig:reported("ahead")
	if #ahead ~= 1 or ahead[1] ~= AHEAD + 2 then
		return false, `A Move with two commands past the limit reported ahead {#ahead} times, not once with {AHEAD + 2}`
	end

	local depth: number = rig.Commands.depth(rig.connection)
	if depth ~= 3 then
		return false, `{depth} commands wait, where the three at most {AHEAD} ticks ahead were filed`
	end

	rig:take(START + 1)
	rig:take(START + 2)

	-- The furthest again, now 5 ticks ahead, which is filed this time
	rig:send(rig:commands(START + 7, 1))

	if #rig:reported("ahead") ~= 1 then
		return false, "A Move inside the limit was reported ahead"
	end

	for tick: number = START + 3, START + 7 do
		local command: any, standIn: boolean = rig:take(tick)
		local dropped: boolean = tick == START + AHEAD + 1

		if standIn and not dropped then
			return false, `Tick {tick} ran a stand-in, where its command was filed`
		elseif dropped and not standIn then
			return false, `Tick {tick} ran a command, where its command was dropped`
		elseif not standIn and command.number ~= tick then
			return false, `Tick {tick} ran command {command.number}, not its own`
		end
	end

	return true, nil
end
