--[[
    The rig pool takes the character draw distance of the device's class: a
    console's on a television, a desktop's with no touch or with a keyboard,
    a phone's on a small touch screen and a tablet's on a larger one
--]]

--!strict
local Handle = require("../../Fixtures/Client/Handle")

type Trial = {
	name: string,
	device: { tenFoot: boolean, touch: boolean, keyboard: boolean, display: string },
	expected: string,
}

-- Distances apart from each other, so each class shows which it got
local DISTANCES: { [string]: number } = { desktop = 1000, console = 900, phone = 300, tablet = 600 }

local TRIALS: { Trial } = {
	{
		name = "a desktop",
		device = { tenFoot = false, touch = false, keyboard = true, display = "Large" },
		expected = "desktop",
	},
	{
		name = "a console",
		device = { tenFoot = true, touch = false, keyboard = false, display = "Large" },
		expected = "console",
	},
	{
		name = "a phone",
		device = { tenFoot = false, touch = true, keyboard = false, display = "Small" },
		expected = "phone",
	},
	{
		name = "a tablet",
		device = { tenFoot = false, touch = true, keyboard = false, display = "Medium" },
		expected = "tablet",
	},
	{
		name = "a touch laptop",
		device = { tenFoot = false, touch = true, keyboard = true, display = "Large" },
		expected = "desktop",
	},
}

return function (): (boolean, string | nil)
	for _, trial: Trial in TRIALS do
		local rig: any = Handle.new({ device = trial.device, start = false })
		rig.client.drawDistance = table.clone(DISTANCES)
		rig.start()

		local expected: number = DISTANCES[trial.expected]
		if rig.pool.drawDistance ~= expected then
			return false, `On {trial.name} the pool got a draw distance of {rig.pool.drawDistance}, not {expected}`
		end
	end

	return true, nil
end
