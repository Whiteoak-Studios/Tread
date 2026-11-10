--[[
    The fixture ballistics both realms run: where a bullet's segment first
    meets a capsule, and the nearest zone it strikes on one target, its body
    capsule the broad check, for the server's fixture and the shooter's view
--]]

--!strict
--!native
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Packages = ReplicatedStorage.Packages

local Tread = require(Packages.Tread)

-- What a hotbar slot fires, as the ballistics config lists them
export type Weapon = {
	speed: number, -- Studs a second
	range: number, -- Studs it flies before it falls short
}

local Ballistics = {}

-- Studs along a segment, from its start, at which it enters a sphere, or nil when it never does within its length
local function sphere(from: Vector3, unit: Vector3, length: number, center: Vector3, radius: number): number?
	local offset: Vector3 = from - center
	local along: number = offset:Dot(unit)
	local square: number = along * along - (offset:Dot(offset) - radius * radius)
	if square < 0 then
		return nil
	end

	local distance: number = -along - math.sqrt(square)
	if distance < 0 or distance > length then
		return nil
	end

	return distance
end

-- The nearer of two distances, either of which may be missing
local function nearer(first: number?, second: number?): number?
	if first == nil then
		return second
	elseif second == nil then
		return first
	end

	return math.min(first, second)
end

--[[
    Studs along a segment, from its start, at which it first meets a
    capsule: 0 when it starts inside, else the nearer of its entry through
    the cylinder's side between the two end points and through either end's
    sphere, or nil when it never meets it within its length
--]]

function Ballistics.enter(from: Vector3, unit: Vector3, length: number, shape: Tread.Shape): number?
	local axis: Vector3 = shape.to - shape.from
	local offset: Vector3 = from - shape.from
	local radius: number = shape.radius
	local axisSquared: number = axis:Dot(axis)

	-- Inside when its start is within the radius of the axis' nearest point
	local share: number = axisSquared > 0 and math.clamp(offset:Dot(axis) / axisSquared, 0, 1) or 0
	if (offset - axis * share).Magnitude <= radius then
		return 0
	end

	local side: number? = nil
	local axisAlong: number = axis:Dot(unit)
	local axisOffset: number = axis:Dot(offset)
	local spread: number = axisSquared - axisAlong * axisAlong

	-- A segment along the axis meets the side nowhere an end's sphere doesn't first
	if spread > 0 then
		local half: number = axisSquared * offset:Dot(unit) - axisOffset * axisAlong
		local rest: number = axisSquared * offset:Dot(offset) - axisOffset * axisOffset - radius * radius * axisSquared
		local square: number = half * half - spread * rest

		if square >= 0 then
			local distance: number = (-half - math.sqrt(square)) / spread
			local height: number = axisOffset + distance * axisAlong

			if distance >= 0 and distance <= length and height > 0 and height < axisSquared then
				side = distance
			end
		end
	end

	local low: number? = sphere(from, unit, length, shape.from, radius)
	local high: number? = sphere(from, unit, length, shape.to, radius)

	return nearer(side, nearer(low, high))
end

--[[
    The nearest zone of one target a segment meets and how far along it,
    or nil and 0 when it misses: its body capsule is the broad check, and
    only its zones can be struck

    @ unit | the segment's direction, a unit vector, which it runs length studs along
--]]

function Ballistics.zone(
	from: Vector3,
	unit: Vector3,
	length: number,
	body: Tread.Shape,
	zones: { [string]: Tread.Shape }
): (string?, number)
	if not Ballistics.enter(from, unit, length, body) then
		return nil, 0
	end

	local nearest: string? = nil
	local nearestDistance: number = 0

	for name: string, shape: Tread.Shape in zones do
		local distance: number? = Ballistics.enter(from, unit, length, shape)
		if distance and (nearest == nil or distance < nearestDistance) then
			nearest = name
			nearestDistance = distance
		end
	end

	return nearest, nearestDistance
end

return Ballistics
