--[[
    The dev place's test elevator as the one Tread platform both realms
    register, its deck at rest until a call, then up, held and back down,
    and its call button, a press's reach and check, and the spot to press from
--]]

--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Packages = ReplicatedStorage.Packages

local Tread = require(Packages.Tread)

local Hulls = require(Packages.Tread.Step.Hulls)

local Config = require(ReplicatedStorage.Shared.Dev.ElevatorConfig)
local Shared = require(ReplicatedStorage.Shared.Dev.Config)

local RATE: number = Shared.rates.simulation -- Hz, the ticks the path counts in
local REST_X: number = Config.rest.X
local REST_Y: number = Config.rest.Y
local REST_Z: number = Config.rest.Z
local TOP: number = Config.top
local SPEED: number = Config.speed
local BUTTON: CFrame = Config.button
local BUTTON_SIZE: Vector3 = Config.buttonSize
local HALF: Vector3 = BUTTON_SIZE / 2
local REACH: number = Config.reach

local RISE_TICKS: number = TOP / SPEED * RATE -- Ticks from the call to the top, and from leaving it back to rest
local CYCLE_TICKS: number = 2 * RISE_TICKS + Config.wait * RATE
local CYCLE: number = CYCLE_TICKS / RATE -- Seconds from a call until the deck is back at rest

local PLATFORM: Tread.Platform = {
	id = 1, -- The same on both realms, and clear of the 127 the Wiring scenario registers while it runs
	boxes = { { center = Vector3.zero, size = Config.deck } },

	-- Plain arithmetic, since Tread runs it inside the step on every realm: at rest before a call, then from it up at
	-- the speed, held at the top, down at the speed and at rest again, its rise clamped from 0 to the top
	path = function (tick: number, calledAt: number?): Vector3
		if calledAt == nil then
			return Config.rest
		end

		local elapsed: number = tick - calledAt
		local risen: number = math.clamp(math.min(elapsed, CYCLE_TICKS - elapsed) * SPEED / RATE, 0, TOP)

		return Vector3.new(REST_X, REST_Y + risen, REST_Z)
	end,
}

-- Whether the world meets a ray from origin along direction, its whole length
export type Blocked = (origin: Vector3, direction: Vector3) -> boolean

local Elevator = {
	platform = PLATFORM,
	button = BUTTON,
	buttonSize = BUTTON_SIZE,
	reach = REACH,
	cycle = CYCLE,
	spot = Config.spot,
}

--[[
    Whether a press calls the elevator: one naming its id, no sooner than a
    ride's length after the last call, since a call mid-ride starts the
    path again from rest and the deck would jump there, and whose ray from
    the eye along the look meets the button's box within reach before the
    world blocks it

    @ look | a unit vector, with the eye cleared, from the server's state
    @ now | os.clock() at the press, and last at the last call, nil for none
--]]

function Elevator.accepts(
	id: number,
	eye: Vector3,
	look: Vector3,
	blocked: Blocked,
	now: number,
	last: number?
): boolean
	if id ~= PLATFORM.id then
		return false
	elseif last ~= nil and now - last < CYCLE then
		return false
	end

	-- The ray in the button's own space, where its box is centered and square to the axes
	local origin: Vector3 = BUTTON:PointToObjectSpace(eye)
	local direction: Vector3 = BUTTON:VectorToObjectSpace(look * REACH)

	-- A sum less itself is 0 only when every value in it is finite
	local sum: number = origin.X + origin.Y + origin.Z + direction.X + direction.Y + direction.Z
	if sum - sum ~= 0 then
		return false
	end

	local enterX: number, exitX: number = Hulls.slab(-origin.X, HALF.X, direction.X)
	local enterY: number, exitY: number = Hulls.slab(-origin.Y, HALF.Y, direction.Y)
	local enterZ: number, exitZ: number = Hulls.slab(-origin.Z, HALF.Z, direction.Z)
	local enter: number = math.max(enterX, enterY, enterZ)
	local exit: number = math.min(exitX, exitY, exitZ)

	-- The share of the reach it enters the box at, from outside it, as an engine cast passes by a part it starts in
	if not (enter >= 0 and enter < exit and enter <= 1) then
		return false
	end

	-- Nothing in the world may stand nearer along the ray than the button
	return enter == 0 or not blocked(eye, look * (REACH * enter))
end

return Elevator
