--[[
    The Slide scenario's numbers: where it lays its floor and ramp, where
    each of its bots is built, what each run must read within, and how long
    each of its waits may take before it fails
--]]

--!strict
return {
	center = Vector3.new(-2000, 900, 2000), -- The floor's top, clear of the city block and every other scenario's floor
	flat = Vector3.new(-25, 0, 35), -- Where the flat run's bot is built, from the center, its slide along -Z
	jump = Vector3.new(-10, 0, 35), -- The jump run's, in a lane of its own

	ramp = {
		tilt = 25, -- Degrees, the steepest the walk's ground snap follows at the top speed at 20 Hz
		run = 60, -- Studs along X from its low edge to its top, so it rises toward +X
		width = 10, -- Along Z
		thickness = 2,
		foot = Vector3.new(5, 0, 20), -- Its low edge's middle on the floor, from the center
		start = 6, -- Studs down its tilt from its top the bot is built at
		lift = 1, -- Studs over the ramp's face the bot is built at, so it settles onto it
	},

	close = 0.02, -- Studs/s a speed may sit from what it should, past the velocity's 1/64 quanta
	ticks = { fewest = 40, most = 41 }, -- The flat slide's length in ticks at 20 Hz
	distance = { shortest = 23.5, longest = 24.5 }, -- Studs the flat slide covers
	ready = 12, -- Ticks a landed bot waits before it is driven, past the dev rules' 0.5 s jump cooldown from its build
	glide = 6, -- Ticks of the jump run's slide before its jump
	watch = 10, -- Ticks the jump run's second crouch press is watched for a slide

	waits = {
		settle = 5, -- Seconds a bot may take to land where it is built
		sprint = 3, -- Seconds a bot may take to reach the sprint
		slide = 5, -- Seconds a slide may take to start, to reach the top speed, or to end
		air = 3, -- Seconds a jump may take to leave the ground and land again
	},
}
