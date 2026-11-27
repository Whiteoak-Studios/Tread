--[[
    A copy of the leg bend's maths in src/Client/Rigs/Animate.luau: its
    rotation helpers and the bend of one leg, which solves the hip's, knee's
    and ankle's Transforms and gives them back for its caller to write
--]]

--!strict
--!native
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Packages = ReplicatedStorage.Packages

local Animate = require(Packages.Tread.Client.Rigs.Animate)

local NEARLY: number = 1e-6 -- The shortest length, or the widest a cross of two directions, that still points a way
local FORWARD: vector = vector.create(0, 0, -1) -- The rig's facing in its root's space, the way every knee bends
local UP: vector = vector.create(0, 1, 0) -- The rig's up in its root's space, which a hinge falls back on

type Frame = Animate.Frame
type Place = Animate.Place

local Bend = {}

-- A rotation's columns applied to a direction
local function turn(x: vector, y: vector, z: vector, direction: vector): vector
	return x * direction.x + y * direction.y + z * direction.z
end

-- A direction in a rotation's own axes, the rotation undone
local function unturn(x: vector, y: vector, z: vector, direction: vector): vector
	return vector.create(vector.dot(x, direction), vector.dot(y, direction), vector.dot(z, direction))
end

-- A Transform that moves nothing and turns by the rotation whose columns these are
local function rotation(x: vector, y: vector, z: vector): CFrame
	return CFrame.new(0, 0, 0, x.x, y.x, z.x, x.y, y.y, z.y, x.z, y.z, z.z)
end

--[[
    Bends one leg so its ankle's pivot meets its target, from the hips'
    pose this step: the knee ahead of the line from the hip to the target,
    along the rig's facing, and the leg straight toward a target out of
    reach. Each Transform turns its joint's axes from where they rest to
    where the bend puts them: the hip by the thigh's, the knee by the
    shin's against the thigh's, and the ankle back by the shin's, so the
    foot keeps the way it rests

    @ target | where the ankle's pivot goes, in the root's space
    @ tx | the hips' pose this step, its rotation's columns and its move
--]]

function Bend.solve(
	place: Place,
	target: vector,
	tx: vector,
	ty: vector,
	tz: vector,
	tp: vector
): (CFrame, CFrame, CFrame)
	local base: Frame = place.base
	local mount: Frame = place.mount

	-- 1) The hip's pivot and axes under the hips' pose
	local lx: vector = turn(base.x, base.y, base.z, tx)
	local ly: vector = turn(base.x, base.y, base.z, ty)
	local lz: vector = turn(base.x, base.y, base.z, tz)
	local lp: vector = base.p + turn(base.x, base.y, base.z, tp)

	local hx: vector = turn(lx, ly, lz, mount.x)
	local hy: vector = turn(lx, ly, lz, mount.y)
	local hz: vector = turn(lx, ly, lz, mount.z)
	local hip: vector = lp + turn(lx, ly, lz, mount.p)

	-- 2) The way to the target, and the hinge across it and the facing, which the knee turns about
	local line: vector = target - hip
	local distance: number = vector.magnitude(line)
	local along: vector = place.line
	if distance > NEARLY then
		along = line / distance
	end

	local hinge: vector = vector.cross(along, FORWARD)
	local width: number = vector.magnitude(hinge)
	if width > NEARLY then
		hinge /= width
	else
		hinge = vector.normalize(vector.cross(along, UP))
	end
	local ahead: vector = vector.cross(hinge, along)

	-- 3) The bones from the law of cosines, the reach held between folded and straight
	local upper: number = place.upper
	local lower: number = place.lower
	local reach: number = math.clamp(distance, math.max(math.abs(upper - lower), NEARLY), upper + lower)
	local cosine: number = math.clamp((upper * upper + reach * reach - lower * lower) / (2 * upper * reach), -1, 1)
	local thigh: vector = along * cosine + ahead * math.sqrt(1 - cosine * cosine)
	local shin: vector = vector.normalize(along * reach - thigh * upper)

	-- The bent bones' axes, the hinge first, as the place's rest axes are built
	local thighY: vector = -thigh
	local thighZ: vector = vector.cross(hinge, thighY)
	local shinY: vector = -shin
	local shinZ: vector = vector.cross(hinge, shinY)

	-- 4) The hip, against the axes the hips' pose leaves it in
	local hipInThigh: Frame = place.hipInThigh
	local hipX: vector = turn(hinge, thighY, thighZ, hipInThigh.x)
	local hipY: vector = turn(hinge, thighY, thighZ, hipInThigh.y)
	local hipZ: vector = turn(hinge, thighY, thighZ, hipInThigh.z)
	local hipTransform: CFrame = rotation(unturn(hx, hy, hz, hipX), unturn(hx, hy, hz, hipY), unturn(hx, hy, hz, hipZ))

	-- 5) The knee, by the shin's axes in the thigh's
	local kneeInShin: Frame = place.kneeInShin
	local thighInKnee: Frame = place.thighInKnee
	local sx: vector = unturn(hinge, thighY, thighZ, hinge)
	local sy: vector = unturn(hinge, thighY, thighZ, shinY)
	local sz: vector = unturn(hinge, thighY, thighZ, shinZ)
	local kneeX: vector = turn(sx, sy, sz, kneeInShin.x)
	local kneeY: vector = turn(sx, sy, sz, kneeInShin.y)
	local kneeZ: vector = turn(sx, sy, sz, kneeInShin.z)
	local kneeTransform: CFrame = rotation(
		turn(thighInKnee.x, thighInKnee.y, thighInKnee.z, kneeX),
		turn(thighInKnee.x, thighInKnee.y, thighInKnee.z, kneeY),
		turn(thighInKnee.x, thighInKnee.y, thighInKnee.z, kneeZ)
	)

	-- 6) The ankle, the shin's turn undone
	local ankleAxes: Frame = place.ankleAxes
	local shinInAnkle: Frame = place.shinInAnkle
	local ankleX: vector = unturn(hinge, shinY, shinZ, ankleAxes.x)
	local ankleY: vector = unturn(hinge, shinY, shinZ, ankleAxes.y)
	local ankleZ: vector = unturn(hinge, shinY, shinZ, ankleAxes.z)
	local ankleTransform: CFrame = rotation(
		turn(shinInAnkle.x, shinInAnkle.y, shinInAnkle.z, ankleX),
		turn(shinInAnkle.x, shinInAnkle.y, shinInAnkle.z, ankleY),
		turn(shinInAnkle.x, shinInAnkle.y, shinInAnkle.z, ankleZ)
	)

	return hipTransform, kneeTransform, ankleTransform
end

return Bend
