--[[
    The dev place's view: first person at Tread's eye, or over the right
    shoulder, behind and beside the eye along the look and pulled in short
    of any wall, with a press blending from one to the other
--]]

--!strict
local View = {}
View.__index = View

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Packages = ReplicatedStorage.Packages

local Tread = require(Packages.Tread)

local Math = require(Packages.Tread.Step.Math)

local HALF: number = 0.5 -- The blend's midpoint, where the owner's world rig and first-person copy swap
local FIRST_PERSON: number = 0 -- The blend at the eye
local SHOULDER: number = 1 -- The blend over the shoulder

-- The view's values, which the dev client's Config holds
type Settings = {
	side: number, -- Studs right of the eye the shoulder view sits
	up: number, -- Studs above it, along the view's own up
	back: number, -- Studs behind it, along the look
	blend: number, -- Seconds a blend from one view to the other takes
	radius: number, -- Studs of the sphere cast that pulls the shoulder view in short of a wall
}

-- How far a sphere from an origin gets along a direction before it meets the world, or nil when it gets all the way
type Cast = (origin: Vector3, direction: Vector3) -> number?

type Fields = {
	_client: Tread.Client,
	_settings: Settings,
	_cast: Cast,
	_blend: number, -- From the eye at 0 to over the shoulder at 1, linear in time
	_out: boolean, -- Whether it blends out to the shoulder, or back to the eye
	_outside: boolean, -- Whether the owner's world rig shows and the copy hides, past the blend's midpoint
}

--[[
    A view at the eye, the owner's body as Tread starts it: the copy shown
    and the world rig hidden

    @ cast | the sphere cast against the world the shoulder view is pulled in by
--]]

function View.new(client: Tread.Client, settings: Settings, cast: Cast): Self
	if not (settings.blend > 0) then
		error(`The view's blend time must be above 0 seconds, not {settings.blend}`, 2)
	elseif not (settings.radius >= 0) then
		error(`The view's cast radius must be 0 studs or more, not {settings.radius}`, 2)
	end

	return setmetatable({
		_client = client,
		_settings = settings,
		_cast = cast,
		_blend = FIRST_PERSON,
		_out = false,
		_outside = false,
	}, View)
end

--[[
    Turns the blend around: out to the shoulder from the eye, or back to
    the eye, from wherever a blend under way has reached
--]]

function View.toggle(self: Self)
	self._out = not self._out
end

--[[
    The blend's ease from its share of the blend time: slow at either end
    and fastest at the midpoint, which it passes at half the time
--]]

function View.ease(share: number): number
	return share * share * (3 - 2 * share)
end

--[[
    The shoulder view's place for an eye and its look: behind the eye along
    the look, to its right and up along the view's own axes, so it orbits
    the eye as the look turns. The look is never straight up or down, which
    the dev input holds short of
--]]

function View.shoulder(eye: Vector3, look: Vector3, settings: Settings): Vector3
	local right: Vector3 = Vector3.new(-look.Z, 0, look.X).Unit
	local up: Vector3 = right:Cross(look)

	return eye + right * settings.side + up * settings.up - look * settings.back
end

--[[
    One frame of the view: the blend moved on by the frame's time, the
    owner's bodies swapped as it passes the midpoint, and the camera's
    place, from the eye toward the shoulder view as far as the blend has
    gone, never past where the sphere cast meets the world. The camera
    looks along the look in either view
--]]

function View.frame(self: Self, dt: number, eye: Vector3, look: Vector3): Vector3
	local settings: Settings = self._settings
	local step: number = dt / settings.blend

	if self._out then
		self._blend = math.min(self._blend + step, SHOULDER)
	else
		self._blend = math.max(self._blend - step, FIRST_PERSON)
	end

	-- Past the midpoint the owner sees their world rig as others do, and short of it their copy
	local outside: boolean = self._blend >= HALF
	if outside ~= self._outside then
		self._outside = outside
		self._client:showBody("rig", outside)
		self._client:showBody("copy", not outside)
	end

	if self._blend == FIRST_PERSON then
		return eye
	end

	-- The cast runs to the whole shoulder view, so the eye's way to wherever the blend has reached is clear too
	local toward: Vector3 = View.shoulder(eye, look, settings) - eye
	local clear: number? = self._cast(eye, toward)
	if clear ~= nil and clear < toward.Magnitude then
		toward = toward.Unit * clear
	end

	local share: number = View.ease(self._blend)
	local x: number = Math.lerp(eye.X, eye.X + toward.X, share)
	local y: number = Math.lerp(eye.Y, eye.Y + toward.Y, share)
	local z: number = Math.lerp(eye.Z, eye.Z + toward.Z, share)

	return Vector3.new(x, y, z)
end

export type View = Self
type Self = typeof(setmetatable({} :: Fields, View))

return View
