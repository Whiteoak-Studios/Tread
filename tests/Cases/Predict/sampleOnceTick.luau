--[[
    The sample hook runs once a simulation tick and never between ticks,
    and nothing samples, steps or sends before the first OwnerState starts
    the body, which until then draws as nil
--]]

--!strict
local Harness = require("../../Fixtures/Predict/Harness")

return function (): (boolean, string | nil)
	local rig: any = Harness.new()
	local delta: number = rig.delta

	rig.frames(1, 1)
	if rig.samples ~= 0 or #rig.moves ~= 0 or rig.Predict.state() ~= nil then
		return false, `Before the first OwnerState a frame sampled {rig.samples} times and sent {#rig.moves} Moves`
	end

	rig.spawn()

	-- 2.4 ticks owed runs 2, and 0.3 more leaves 2.7 owed, so none runs
	local owed: { { number } } = { { 2.4, 2 }, { 0.3, 2 }, { 0.4, 3 }, { 0, 3 }, { 0.95, 4 } }
	for _, row: { number } in owed do
		rig.frames(1, delta * row[1])

		if rig.samples ~= row[2] then
			return false, `After a frame of {row[1]} ticks the sample had run {rig.samples} times, not {row[2]}`
		end
	end

	if rig.Predict.state() == nil then
		return false, "Once the first OwnerState started the body, the drawn state was still nil"
	end

	return true, nil
end
