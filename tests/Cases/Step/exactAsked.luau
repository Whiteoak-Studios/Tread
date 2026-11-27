--[[
    Step.advance's exact argument: left out or false, a still body a part
    moves into is freed only on a tenth command; true, on any command, once
    on a tenth; and left out, every parity fixture hashes as it holds
--]]

--!strict
local Environment = require("../../Environment")

local STEP: string = "src/Step/init.luau"
local MATH: string = "src/Step/Math.luau"
local CONSTANTS: string = "src/Constants.luau"
local SCENE: string = "tests/Fixtures/Step/Scene.luau"
local CASTS: string = "tests/Fixtures/Step/Collision.luau"
local GEOMETRY: string = "tests/Fixtures/Step/Geometry.luau"
local PARITIES: { string } = {
	"tests/Fixtures/Step/Parity.luau",
	"tests/Fixtures/Step/RiderParity.luau",
	"tests/Fixtures/Step/SlideParity.luau",
}

local SPOT_X: number = -20 -- Where the body stands, clear of every fixture part
local SPOT_Z: number = -10
local POST_SIZE: vector = vector.create(1, 8, 1) -- Narrower than the hull and taller, so the rest check never sees it
local MOVED_AFTER: number = 11 -- The command after which the part moves into the body
local TENTH: number = 20 -- The first tenth command after the part moves in
local ASKED: number = 13 -- A command that is no tenth, on which the check is asked for

-- What the case reaches in its environments, loaded once
type Kit = {
	Step: any,
	world: any,
	spot: vector,
	clear: any, -- The fixture's casts over its parts
	posted: any, -- The same with the part moved into the body
	use: (casts: any) -> (), -- Which casts the world's collision answers from
	overlaps: () -> number, -- The exact overlap queries the world's collision has answered
	state: (feet: vector, grounded: boolean) -> any,
}

-- A command with no input, its presses all off
local function newCommand(): any
	return {
		number = 0,
		forward = 0,
		right = 0,
		jump = false,
		crouch = false,
		sprint = false,
		aim = false,
		pressed = { jump = false, crouch = false, sprint = false, aim = false },
		yaw = 0,
		pitch = 0,
		lean = 0,
		headYaw = 0,
		headPitch = 0,
		fields = {},
	}
end

local function load(): Kit
	local Math: any = Environment.load(MATH)
	local Constants: any = Environment.load(CONSTANTS)
	local Scene: any = Environment.load(SCENE)
	local Casts: any = Environment.load(CASTS)
	local Geometry: any = Environment.load(GEOMETRY)

	-- Feet on the quantum, so a still body's rounding never moves it and only the exact check can free it
	local spot: vector = vector.create(SPOT_X, Math.quantize(Geometry.floor + Constants.SKIN), SPOT_Z)
	local post: any = {
		name = "Post",
		center = vector.create(SPOT_X, Geometry.floor + POST_SIZE.y / 2, SPOT_Z),
		size = POST_SIZE,
		tilt = 0,
	}

	local parts: { any } = table.clone(Geometry.parts)
	table.insert(parts, post)

	local inner: any = Casts(Geometry.parts)
	local count: number = 0
	local collision: any = {
		ray = function (origin: vector, direction: vector): any
			return inner.ray(origin, direction)
		end,
		sweep = function (center: vector, size: vector, direction: vector): any
			return inner.sweep(center, size, direction)
		end,
		rest = function (center: vector, size: vector): number?
			return inner.rest(center, size)
		end,
		sphere = function (center: vector, radius: number, direction: vector): any
			return inner.sphere(center, radius, direction)
		end,
		overlap = function (center: vector, size: vector): boolean
			count += 1

			return inner.overlap(center, size)
		end,
		destroy = function () end,
	}

	return {
		Step = Environment.load(STEP),
		world = Scene.world(collision),
		spot = spot,
		clear = Casts(Geometry.parts),
		posted = Casts(parts),
		use = function (casts: any)
			inner = casts
		end,
		overlaps = function (): number
			return count
		end,
		state = Scene.state,
	}
end

--[[
    Steps a body once on a command number, with exact given when given is
    set and left out otherwise, and gives its stuck depth and the exact
    overlap queries the step made
--]]

local function step(kit: Kit, state: any, number: number, exact: boolean?, given: boolean): (number?, number)
	local command: any = newCommand()
	command.number = number
	kit.world.tick = number

	local before: number = kit.overlaps()
	local stuck: number?
	if given then
		local _: number, sank: number? = kit.Step.advance(state, command, kit.world, exact)
		stuck = sank
	else
		local _: number, sank: number? = kit.Step.advance(state, command, kit.world)
		stuck = sank
	end

	return stuck, kit.overlaps() - before
end

-- Why a clear still body's queries were not one more only where the check runs, and once on a tenth, or nil
local function counts(kit: Kit): string?
	kit.use(kit.clear)
	local state: any = kit.state(kit.spot, true)

	local _: number?, plain: number = step(kit, state, 1, nil, false)
	local _: number?, unasked: number = step(kit, state, 2, false, true)
	local _: number?, asked: number = step(kit, state, 3, true, true)
	local _: number?, tenth: number = step(kit, state, 10, nil, false)
	local _: number?, both: number = step(kit, state, TENTH, true, true)

	if state.position ~= kit.spot then
		return `The clear body moved to {state.position} standing still, so its queries test nothing`
	elseif unasked ~= plain then
		return `Exact given as false made {unasked} overlap queries where left out made {plain}`
	elseif asked ~= plain + 1 then
		return `Exact asked for on command 3 made {asked} overlap queries, not the {plain + 1} of one check`
	elseif tenth ~= plain + 1 then
		return `The tenth command left out made {tenth} overlap queries, not the {plain + 1} of its check`
	elseif both ~= tenth then
		return `Exact asked for on a tenth command made {both} overlap queries, not the tenth's {tenth}`
	end

	return nil
end

-- Why the part moved into a still body freed it before its tenth command or not on it, or nil
local function moved(kit: Kit): string?
	kit.use(kit.clear)
	local state: any = kit.state(kit.spot, true)

	for number: number = 1, MOVED_AFTER do
		step(kit, state, number, nil, false)
	end

	-- The first command after the move gives exact as false, the rest leave it out
	kit.use(kit.posted)
	for number: number = MOVED_AFTER + 1, TENTH - 1 do
		local stuck: number? = step(kit, state, number, false, number == MOVED_AFTER + 1)
		if state.position ~= kit.spot or stuck ~= nil then
			return `The still body left the part on command {number}, at {state.position} stuck {stuck}, before its tenth`
		end
	end

	local stuck: number? = step(kit, state, TENTH, nil, false)
	if state.position == kit.spot then
		return `The still body was still inside the part after command {TENTH}, its tenth`
	elseif stuck ~= nil then
		return `The still body was reported stuck {stuck} on command {TENTH}, where a spot a hull width out is clear`
	end

	return nil
end

-- Why a body inside the part was not freed on the command that asked for the check, or nil
local function asked(kit: Kit): string?
	kit.use(kit.posted)
	local state: any = kit.state(kit.spot, true)

	step(kit, state, MOVED_AFTER, nil, false)
	if state.position ~= kit.spot then
		return `The body inside the part left it on command {MOVED_AFTER}, where nothing asked for the check`
	end

	local stuck: number? = step(kit, state, ASKED, true, true)
	if state.position == kit.spot then
		return `The body inside the part was still in it after command {ASKED}, which asked for the check`
	elseif stuck ~= nil then
		return `The body asked for the check on command {ASKED} was reported stuck {stuck}, not freed`
	end

	return nil
end

return function (): (boolean, string | nil)
	local kit: Kit = load()

	local failure: string? = counts(kit) or moved(kit) or asked(kit)
	if failure then
		return false, failure
	end

	for _, path: string in PARITIES do
		local fixture: any = Environment.load(path)
		local hash: number = fixture.run(false)
		if hash ~= fixture.expected then
			return false, `{path} hashed to {hash} with exact left out, where it holds {fixture.expected}`
		end
	end

	return true, nil
end
