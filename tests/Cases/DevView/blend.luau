--[[
    The dev view sits at the eye until a press blends it out over the right
    shoulder, eased over the blend time, and back, turning round from where
    a press finds it, swaps the owner's world rig and copy at the midpoint
    each way, and stops where the cast meets the world
--]]

--!strict
local roblox: any = require("@lune/roblox") -- Its typedefs leave out the datatypes

local Harness = require("../../Fixtures/DevClient/Harness")

local Vector3: any = roblox.Vector3

local VIEW: string = "dev/Client/View.luau"
local QUARTER: number = 0.25 -- Seconds a frame of this case takes, a quarter of its blend time
local CLEAR: number = 1 -- Studs the stub cast lets the sphere go before a wall
local ROUNDING: number = 1e-4 -- Studs a float32 place may sit from the one worked out here

-- The case's own view: a blend of a second, so each frame moves it a quarter
local SETTINGS: { [string]: number } = { side = 2, up = 1, back = 4, blend = 1, radius = 0.5 }

return function (): (boolean, string | nil)
	local place: Harness.Game = Harness.new()
	local View: any = place.load(VIEW)

	local swaps: { string } = {}
	local client: any = {
		showBody = function (_: any, part: string, shown: boolean)
			table.insert(swaps, `{part} {shown}`)
		end,
	}

	-- The swaps since the last clear, in the order made
	local function swapped(): string
		return table.concat(swaps, ", ")
	end

	-- Each cast's origin and direction, and the distance the next one gives back, nil for no wall
	local casts: { { any } } = {}
	local wall: number? = nil
	local function cast(origin: any, direction: any): number?
		table.insert(casts, { origin, direction })

		return wall
	end

	local eye: any = Vector3.new(0, 10, 0)
	local look: any = Vector3.new(0, 0, -1)
	local view: any = View.new(client, SETTINGS, cast)

	-- The ease starts and ends at rest and passes the midpoint at half the time, slow at a quarter and fast past it
	local eased: { [number]: number } = { [0] = 0, [0.25] = 0.15625, [0.5] = 0.5, [0.75] = 0.84375, [1] = 1 }
	for share: number, wanted: number in eased do
		if math.abs(View.ease(share) - wanted) > ROUNDING then
			return false, `The ease at {share} of the blend time gave {View.ease(share)}, not {wanted}`
		end
	end

	-- Looking along -Z, the right is +X and the view's own up is +Y
	local shoulder: any = View.shoulder(eye, look, SETTINGS)
	if (shoulder - Vector3.new(2, 11, 4)).Magnitude > ROUNDING then
		return false, `The shoulder view looking along -Z sat at {shoulder}, not right, up and behind the eye`
	end

	local east: any = View.shoulder(eye, Vector3.new(1, 0, 0), SETTINGS)
	if (east - Vector3.new(-4, 11, 2)).Magnitude > ROUNDING then
		return false, `The shoulder view looking along +X sat at {east}, not behind and to the right along +Z`
	end

	-- At the eye it stays there, casts nothing and swaps nothing
	local at: any = view:frame(QUARTER, eye, look)
	if at ~= eye or #casts ~= 0 or #swaps ~= 0 then
		return false, `At the eye the view sat at {at} after {#casts} casts and {#swaps} swaps`
	end

	-- Out over the shoulder, eased: a quarter of the way in time is the ease's share of the way in space
	local function expect(share: number, label: string): string?
		local got: any = view:frame(QUARTER, eye, look)
		local wanted: any = eye + (shoulder - eye) * View.ease(share)
		if (got - wanted).Magnitude > ROUNDING then
			return `{label}, the view sat at {got}, not {wanted}`
		end

		return nil
	end

	view:toggle()
	local out: string? = expect(0.25, "A quarter out") or (#swaps ~= 0 and "It swapped before the midpoint" or nil)
	if out then
		return false, out
	end

	out = expect(0.5, "Half way out")
	if out then
		return false, out
	elseif swapped() ~= "rig true, copy false" then
		return false, `At the midpoint out the view swapped {swapped()}, not the rig shown and the copy hidden`
	end

	out = expect(0.75, "Three quarters out") or expect(1, "All the way out") or expect(1, "A frame after it got there")
	if out then
		return false, out
	elseif #casts == 0 or casts[1][1] ~= eye or (casts[1][2] - (shoulder - eye)).Magnitude > ROUNDING then
		return false, "The cast did not run from the eye toward the whole shoulder view"
	end

	-- Back toward the eye, past the midpoint, then turned round where the second press finds it
	table.clear(swaps)
	view:toggle()
	out = expect(0.75, "A quarter back") or expect(0.5, "Half way back")
	if out then
		return false, out
	elseif #swaps ~= 0 then
		return false, `The view swapped {swapped()} before it was back past the midpoint`
	end

	out = expect(0.25, "Three quarters back")
	if out then
		return false, out
	elseif swapped() ~= "rig false, copy true" then
		return false, `Back past the midpoint the view swapped {swapped()}, not the copy shown again`
	end

	table.clear(swaps)
	view:toggle()
	out = expect(0.5, "Turned round, half way out again") or expect(0.75, "Turned round and on out")
	if out then
		return false, out
	elseif swapped() ~= "rig true, copy false" then
		return false, `Turned round, the view swapped {swapped()} at the midpoint`
	end

	-- A wall the cast meets pulls the view in to it, and one past the shoulder view leaves it where it was
	wall = CLEAR
	local pulled: any = view:frame(QUARTER, eye, look)
	local reach: any = eye + (shoulder - eye).Unit * CLEAR
	if (pulled - reach).Magnitude > ROUNDING then
		return false, `With a wall a stud from the eye the view sat at {pulled}, not at {reach}`
	end

	wall = (shoulder - eye).Magnitude + CLEAR
	local beyond: any = view:frame(QUARTER, eye, look)
	if (beyond - shoulder).Magnitude > ROUNDING then
		return false, `With a wall past the shoulder view the view sat at {beyond}, not at {shoulder}`
	end

	-- A blend of no time is refused
	local refused: boolean = pcall(View.new, client, { side = 2, up = 1, back = 4, blend = 0, radius = 0.5 }, cast)
	if refused then
		return false, "A view with a blend time of 0 was made"
	end

	return true, nil
end
