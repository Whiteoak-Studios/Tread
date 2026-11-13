--[[
    The test elevator's ride and its button's checks: the deck at rest until
    a call, up at its speed, held, down and at rest again on whole ticks,
    placed alike by Tread's own platforms, and every press it must refuse
--]]

--!strict
local roblox: any = require("@lune/roblox") -- Its typedefs leave out the datatypes

local DevShared = require("../../Fixtures/DevShared/Harness")
local Environment = require("../../Environment")
local Kit = require("../../Fixtures/Exploits/Kit")

local GLOBALS: string = "tests/Fixtures/Environment/Globals.luau"
local ELEVATOR: string = "dev/Shared/Elevator.luau"
local CONFIG: string = "dev/Shared/ElevatorConfig.luau"
local CALLED: number = 1000 -- The tick the ride's call lands on
local AGAIN: number = 5 -- Ticks into a second call, made once the first ride has ended
local CLOSE: number = 1e-4 -- Studs a place may sit from its plain sum, for a Vector3's float32 axes
local NUDGE: number = 1e-3 -- Studs or seconds past an edge a press is put at
local NOW: number = 100 -- The clock at a press, in seconds
local GROUND: number = 0 -- The Asphalt's top under the deck in the dev place
local AHEAD: number = 3 -- Studs off the button's south face a press is made from
local NORTH: any = roblox.Vector3.new(0, 0, -1) -- The look a fresh spawn gives, level along -Z
local ANGLED: any = roblox.Vector3.new(2, 1, 0) -- How far across and up from in front of the face an angled press is

-- The box around (3805, 15.5, -45) that no city block part reaches into, which the ride and the button stay inside
local CLEAR_MIN: any = roblox.Vector3.new(3798, 1.5, -52)
local CLEAR_MAX: any = roblox.Vector3.new(3812, 29.5, -38)

-- Ids the elevator does not hold, which a press may still name inside the schema's 1 to 127
local OTHER_IDS: { number } = { 2, 127 }

-- Stand-ins for the world's cast along a press's ray: one meeting nothing, as the clear box holds
local function clear(_: any, _: any): boolean
	return false
end

local function create(className: string, name: string, parent: any): any
	local instance: any = roblox.Instance.new(className)
	instance.Name = name
	instance.Parent = parent

	return instance
end

--[[
    The elevator's module and its config run in a fresh game as the dev
    place mounts them, beside the dev shared table, with the game's own
    require for Tread's modules
--]]

local function load(): (any, any, any, (target: any) -> any, any)
	local globals: any = Environment.load(GLOBALS)
	local dataModel: any = globals.game
	local replicated: any = dataModel:GetService("ReplicatedStorage")
	local dev: any = create("Folder", "Dev", create("Folder", "Shared", replicated))
	local shared: any = DevShared.load().shared

	local module: any = create("ModuleScript", "Elevator", dev)
	local config: any = create("ModuleScript", "ElevatorConfig", dev)
	local files: { [any]: string } = { [module] = ELEVATOR, [config] = CONFIG }
	local results: { [any]: any } = { [create("ModuleScript", "Config", dev)] = shared }
	local requireDev: (target: any) -> any = Kit.loader(dataModel, files, results, globals.require)

	return requireDev(module), requireDev(config), shared, globals.require, replicated.Packages.Tread
end

-- Where the path puts the deck a whole number of ticks into a ride, as its rise over its rest, or why it is off
local function risen(elevator: any, config: any, tick: number, calledAt: number?): (number?, string?)
	local place: any = elevator.platform.path(tick, calledAt)
	if place.X ~= config.rest.X or place.Z ~= config.rest.Z then
		return nil, `on tick {tick} the deck moved across to {place}`
	end

	return place.Y - config.rest.Y, nil
end

--[[
    The ride: at rest before and without a call, up at the speed a tick,
    held at the top, down at the speed and at rest again, each turn on the
    whole tick the config's numbers give, and a later call riding again
--]]

local function ride(elevator: any, config: any, rate: number): string?
	local perTick: number = config.speed / rate
	local rise: number = config.top / config.speed * rate
	local hold: number = config.wait * rate
	local cycle: number = 2 * rise + hold

	if rise % 1 ~= 0 or hold % 1 ~= 0 then
		return `the ride turns {rise} and {hold} ticks in, not on whole ticks`
	elseif math.abs(elevator.cycle - cycle / rate) > CLOSE then
		return `the elevator gives a ride of {elevator.cycle} s, where its numbers make {cycle / rate} s`
	end

	for _, tick: number in { 0, CALLED, CALLED + cycle } do
		local height: number?, failure: string? = risen(elevator, config, tick, nil)
		if not height then
			return failure
		elseif math.abs(height) > CLOSE then
			return `with no call the deck stood {height} over its rest on tick {tick}`
		end
	end

	for elapsed: number = -2, cycle + 2 do
		local expected: number = 0
		if elapsed > 0 and elapsed < rise then
			expected = elapsed * perTick
		elseif elapsed >= rise and elapsed <= rise + hold then
			expected = config.top
		elseif elapsed > rise + hold and elapsed < cycle then
			expected = (cycle - elapsed) * perTick
		end

		local height: number?, failure: string? = risen(elevator, config, CALLED + elapsed, CALLED)
		if not height then
			return failure
		elseif math.abs(height - expected) > CLOSE then
			return `{elapsed} ticks into the ride the deck stood {height} over its rest, not {expected}`
		end
	end

	-- A call once a ride has ended starts another from rest
	local again: number?, failure: string? = risen(elevator, config, CALLED + cycle + AGAIN, CALLED + cycle)
	if not again then
		return failure
	elseif math.abs(again - AGAIN * perTick) > CLOSE then
		return `{AGAIN} ticks into a second ride the deck stood {again} over its rest`
	end

	return nil
end

--[[
    Tread's own platforms take the elevator and place it on the quantum
    where its path puts it: at rest before the call, at the top and at rest
    again once the ride is over
--]]

local function registers(
	elevator: any,
	config: any,
	rate: number,
	requireTread: (target: any) -> any,
	tread: any
): string?
	local Platforms: any = requireTread(tread.Step.Platforms)
	local Math: any = requireTread(tread.Step.Math)
	local world: any = { platforms = {}, collision = {} }

	local added: boolean, refused: any = pcall(Platforms.add, world, elevator.platform)
	if not added then
		return `Tread's platforms refused the elevator: {refused}`
	end

	Platforms.call(world, elevator.platform.id, CALLED)

	local rise: number = config.top / config.speed * rate
	local cycle: number = 2 * rise + config.wait * rate
	local ticks: { [number]: number } = {
		[CALLED - 1] = 0,
		[CALLED + rise] = config.top,
		[CALLED + cycle] = 0,
	}

	for tick: number, height: number in ticks do
		local at: vector = Platforms.at(world, elevator.platform.id, tick)
		local expected: number = Math.quantize(config.rest.Y + height)
		if at.y ~= expected or at.x ~= Math.quantize(config.rest.X) or at.z ~= Math.quantize(config.rest.Z) then
			return `Tread placed the elevator at {at} on tick {tick}, not {expected} high at its rest`
		end
	end

	return nil
end

--[[
    The ride and the button stay inside the clear box, the deck resting on
    the ground with its top low enough to step onto, and from the press
    spot a fresh spawn's look meets the button, the hull clear of the ride
--]]

local function placed(elevator: any, config: any, step: any, skin: number): string?
	local deck: any = elevator.platform.boxes[1].size
	local rest: any = config.rest
	local bottom: number = rest.Y - deck.Y / 2
	local top: number = rest.Y + deck.Y / 2

	if #elevator.platform.boxes ~= 1 or elevator.platform.boxes[1].center ~= roblox.Vector3.zero then
		return "the elevator is not the one deck centered on its origin"
	elseif math.abs(bottom - GROUND) > CLOSE or top - GROUND > step.stepHeight then
		return `the deck rests from {bottom} to {top}, not on the ground and a step up`
	end

	local low: any = rest - deck / 2
	local high: any = rest + deck / 2 + roblox.Vector3.new(0, config.top + step.standing, 0)
	if low.X < CLEAR_MIN.X or low.Z < CLEAR_MIN.Z or high.X > CLEAR_MAX.X or high.Z > CLEAR_MAX.Z then
		return `the deck's ride spans {low} to {high}, past the clear box's sides`
	elseif high.Y > CLEAR_MAX.Y then
		return `a rider standing on the deck at the top reaches {high.Y}, over the clear box's {CLEAR_MAX.Y}`
	end

	local button: any = elevator.button.Position
	local half: any = elevator.buttonSize / 2
	local below: any = button - half
	local above: any = button + half
	if below.X < CLEAR_MIN.X or below.Y < CLEAR_MIN.Y or below.Z < CLEAR_MIN.Z then
		return `the button reaches down to {below}, outside the clear box`
	elseif above.X > CLEAR_MAX.X or above.Y > CLEAR_MAX.Y or above.Z > CLEAR_MAX.Z then
		return `the button reaches up to {above}, outside the clear box`
	end

	-- The press spot: its hull beside the deck's whole ride, and the eye inside the clear box, so the ray to the
	-- button runs through it with no part between
	local spot: any = elevator.spot
	local apartX: boolean = math.abs(spot.X - rest.X) >= deck.X / 2 + step.radius
	local apartZ: boolean = math.abs(spot.Z - rest.Z) >= deck.Z / 2 + step.radius
	local eye: any = roblox.Vector3.new(spot.X, GROUND + skin + step.eyeStanding, spot.Z)

	if not apartX and not apartZ then
		return `a hull at the press spot {spot} reaches into the deck's ride`
	elseif spot.X - step.radius < CLEAR_MIN.X or spot.X + step.radius > CLEAR_MAX.X then
		return `a hull at the press spot {spot} reaches past the clear box's sides`
	elseif spot.Z - step.radius < CLEAR_MIN.Z or spot.Z + step.radius > CLEAR_MAX.Z then
		return `a hull at the press spot {spot} reaches past the clear box's ends`
	elseif eye.Y < CLEAR_MIN.Y or eye.Y > CLEAR_MAX.Y or spot.Y <= GROUND then
		return `the press spot {spot} stands on no ground, or its eye at {eye.Y} is outside the clear box`
	elseif not elevator.accepts(elevator.platform.id, eye, NORTH, clear, NOW, nil) then
		return `from the press spot's eye at {eye} a fresh spawn's look misses the button`
	end

	return nil
end

--[[
    The presses the server refuses and the ones it lets through: a ray that
    meets the button's box within reach, straight or at an angle, against
    one aimed beside it, pointing away, falling short or starting inside
    it, one the world blocks before the button, another id, a hostile eye
    or look, and a press inside a ride's length of the last call
--]]

local function presses(elevator: any): string?
	local id: number = elevator.platform.id
	local button: any = elevator.button.Position
	local half: any = elevator.buttonSize / 2
	local reach: number = elevator.reach
	local cycle: number = elevator.cycle
	local front: any = button + roblox.Vector3.new(0, 0, half.Z + AHEAD) -- South of the button, looking north at it

	local function accepts(eye: any, look: any): boolean
		return elevator.accepts(id, eye, look, clear, NOW, nil)
	end

	if not accepts(front, NORTH) then
		return `a press from {front} looking straight at the button was refused`
	end

	local angled: any = front + ANGLED
	local toward: any = (button - angled).Unit
	if not accepts(angled, toward) then
		return `a press from {angled} looking at an angle at the button within reach was refused`
	end

	local beside: any = front + roblox.Vector3.new(half.X + NUDGE, 0, 0)
	local over: any = front + roblox.Vector3.new(0, half.Y + NUDGE, 0)
	if accepts(beside, NORTH) or accepts(over, NORTH) then
		return "a press aimed beside or over the button was let through"
	elseif accepts(front, -NORTH) then
		return "a press looking away from the button was let through"
	end

	local short: any = button + roblox.Vector3.new(0, 0, half.Z + reach + NUDGE)
	local edge: any = button + roblox.Vector3.new(0, 0, half.Z + reach - NUDGE)
	if accepts(short, NORTH) then
		return `a press from {short}, whose ray falls short of the button, was let through`
	elseif not accepts(edge, NORTH) then
		return `a press from {edge}, whose ray just reaches the button, was refused`
	elseif accepts(button, NORTH) then
		return "a press from inside the button was let through, where an engine cast passes by it"
	end

	-- The world is cast from the eye to the button's face and no further, and anything it meets refuses the press
	local cast: any = nil
	local function walled(_: any, direction: any): boolean
		cast = direction
		return true
	end

	if elevator.accepts(id, front, NORTH, walled, NOW, nil) then
		return "a press the world blocks before the button was let through"
	elseif cast == nil or math.abs(cast.Magnitude - AHEAD) > CLOSE then
		return `the world was cast {cast} along the ray, not the {AHEAD} studs to the button's face`
	end

	for _, other: number in OTHER_IDS do
		if elevator.accepts(other, front, NORTH, clear, NOW, nil) then
			return `a press naming platform {other} was let through`
		end
	end

	local nan: number = 0 / 0
	local hostile: { { any } } = {
		{ roblox.Vector3.new(nan, 0, 0), NORTH },
		{ roblox.Vector3.new(math.huge, 0, 0), NORTH },
		{ front, roblox.Vector3.new(0, nan, -1) },
		{ front, roblox.Vector3.zero },
	}

	for _, pair: { any } in hostile do
		if accepts(pair[1], pair[2]) then
			return `a press from {pair[1]} looking along {pair[2]} was let through`
		end
	end

	-- Mid-ride a call would start the path again from rest, so only a press a ride's length on calls again
	local now: boolean = elevator.accepts(id, front, NORTH, clear, NOW, NOW)
	local within: boolean = elevator.accepts(id, front, NORTH, clear, NOW, NOW - cycle + NUDGE)
	local after: boolean = elevator.accepts(id, front, NORTH, clear, NOW, NOW - cycle)
	if now or within then
		return "a press within a ride's length of the last call was let through"
	elseif not after then
		return "a press a ride's length after the last call was refused"
	end

	return nil
end

return function (): (boolean, string | nil)
	local elevator: any, config: any, shared: any, requireTread: (target: any) -> any, tread: any = load()
	local rate: number = shared.rates.simulation
	local skin: number = requireTread(tread.Constants).SKIN

	local failure: string? = ride(elevator, config, rate)
		or registers(elevator, config, rate, requireTread, tread)
		or placed(elevator, config, shared.step, skin)
		or presses(elevator)

	if failure then
		return false, failure
	end

	return true, nil
end
