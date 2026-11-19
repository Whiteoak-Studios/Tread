--[[
    The scaffold probe's step fixture: a fixed state run through fixed
    commands against fixed collision answers, giving every number the step
    produces in a fixed order, each written as the hex of its 8 bytes
--]]

--!strict
--!native
local FIXTURE: Fixture = {
	tickRate = 60,
	gravity = 68.1,
	walkSpeed = 16,
	acceleration = 10,
	friction = 6,
	maxSpeed = 6,
	jumpSpeed = 25,
	walkable = 0.643,
	snapDistance = 0.1,
	skin = 0.02,
	bumps = 4,
	positionScale = 512,
	velocityScale = 64,

	start = {
		x = 10.25,
		y = 3.1,
		z = -4.5,
		velocityX = 3.7, -- The input flip changes: the lowest bit of its 8 bytes is flipped before the run
		velocityY = 0,
		velocityZ = -1.3,
		grounded = true,
	},

	-- One command a tick, with its collision answers: the rest height under the hull and each sweep hit in bump order
	ticks = {
		{
			moveX = 1,
			moveZ = 0,
			jump = false,
			rest = 3.1,
			hits = {},
		},
		{
			moveX = 0.6,
			moveZ = -0.8,
			jump = false,
			rest = 3.1,
			hits = {
				{ fraction = 0.4, normal = vector.create(-1, 0, 0) },
			},
		},
		{
			moveX = 0.6,
			moveZ = -0.8,
			jump = true,
			rest = 3.1,
			hits = {},
		},
		{
			moveX = 0,
			moveZ = -1,
			jump = false,
			rest = 2.4,
			hits = {
				{ fraction = 0.7, normal = vector.create(-0.6, 0, 0.8) },
			},
		},
		{
			moveX = -0.8,
			moveZ = -0.6,
			jump = false,
			rest = 2.4,
			hits = {
				{ fraction = 0.5, normal = vector.create(0, -1, 0) },
				{ fraction = 0.25, normal = vector.create(0.6, 0, 0.8) },
			},
		},
		{
			moveX = -0.8,
			moveZ = -0.6,
			jump = false,
			rest = 2.4,
			hits = {},
		},
		{
			moveX = 0,
			moveZ = 0,
			jump = false,
			rest = 2.4,
			hits = {
				{ fraction = 0.3, normal = vector.create(0, 0.8, -0.6) },
			},
		},
		{
			moveX = 0.7071,
			moveZ = 0.7071,
			jump = false,
			rest = 3.95,
			hits = {},
		},
	},
}

local F64_BYTES: number = 8
local LOWEST_BIT: number = 1 -- On byte 0, which holds the lowest mantissa bits of a little-endian f64
local HIGH_WORD: number = 4 -- The offset of the sign, exponent and top mantissa bits
local HEX: string = "%08x%08x" -- Zero-padded hex, which interpolation cannot write

type Hit = {
	fraction: number,
	normal: vector,
}

type Tick = {
	moveX: number,
	moveZ: number,
	jump: boolean,
	rest: number,
	hits: { Hit },
}

type Start = {
	x: number,
	y: number,
	z: number,
	velocityX: number,
	velocityY: number,
	velocityZ: number,
	grounded: boolean,
}

type Fixture = {
	tickRate: number,
	gravity: number,
	walkSpeed: number,
	acceleration: number,
	friction: number,
	maxSpeed: number,
	jumpSpeed: number,
	walkable: number,
	snapDistance: number,
	skin: number,
	bumps: number,
	positionScale: number,
	velocityScale: number,
	start: Start,
	ticks: { Tick },
}

local Probe = {}

--[[
    The step's one interpolation, written out in plain arithmetic, since
    native code fuses the built-in lerps and rounds them differently
--]]

local function lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end

local function flipLowestBit(value: number): number
	local bytes: buffer = buffer.create(F64_BYTES)
	buffer.writef64(bytes, 0, value)
	buffer.writeu8(bytes, 0, bit32.bxor(buffer.readu8(bytes, 0), LOWEST_BIT))

	return buffer.readf64(bytes, 0)
end

local function append(values: { number }, ...: number)
	table.move({ ... }, 1, select("#", ...), #values + 1, values)
end

--[[
    Runs the fixture's ticks from its start state and returns every number
    the step produces, in the order it produces them. With flip, the start
    velocity's x has the lowest bit of its 8 bytes flipped first
--]]

function Probe.run(flip: boolean): { number }
	local start: Start = FIXTURE.start
	local dt: number = 1 / FIXTURE.tickRate
	local control: number = math.clamp(FIXTURE.acceleration * dt, 0, 1)
	local values: { number } = {}

	local x: number, y: number, z: number = start.x, start.y, start.z
	local velocityX: number = flip and flipLowestBit(start.velocityX) or start.velocityX
	local velocityY: number, velocityZ: number = start.velocityY, start.velocityZ
	local grounded: boolean = start.grounded

	for _, tick: Tick in FIXTURE.ticks do
		-- Friction takes a share of the ground speed
		local speed: number = math.sqrt(velocityX * velocityX + velocityZ * velocityZ)
		local kept: number = 1

		if grounded and speed > 0 then
			kept = math.max(speed - speed * FIXTURE.friction * dt, 0) / speed
		end

		velocityX *= kept
		velocityZ *= kept

		-- Accelerate toward the commanded move, then clamp the ground speed
		local wish: vector = vector.create(tick.moveX, 0, tick.moveZ) * FIXTURE.walkSpeed
		velocityX = lerp(velocityX, wish.x, control)
		velocityZ = lerp(velocityZ, wish.z, control)

		local horizontal: number = math.sqrt(velocityX * velocityX + velocityZ * velocityZ)
		local clamp: number = horizontal > FIXTURE.maxSpeed and FIXTURE.maxSpeed / horizontal or 1
		velocityX *= clamp
		velocityZ *= clamp

		if tick.jump and grounded then
			velocityY = FIXTURE.jumpSpeed
		else
			velocityY -= FIXTURE.gravity * dt
		end

		append(values, speed, kept, wish.x, wish.z, horizontal, clamp)

		-- Each hit stops the move a skin short, and what it cut off slides along its plane
		local moveX: number, moveY: number, moveZ: number = velocityX * dt, velocityY * dt, velocityZ * dt
		grounded = false

		for bump: number = 1, math.min(#tick.hits, FIXTURE.bumps) do
			local hit: Hit = tick.hits[bump]
			local normal: vector = hit.normal
			local length: number = math.sqrt(moveX * moveX + moveY * moveY + moveZ * moveZ)
			local travel: number = math.max(length * hit.fraction - FIXTURE.skin, 0)
			local share: number = length > 0 and travel / length or 0

			x += moveX * share
			y += moveY * share
			z += moveZ * share

			local remaining: number = 1 - share
			moveX *= remaining
			moveY *= remaining
			moveZ *= remaining

			local into: number = moveX * normal.x + moveY * normal.y + moveZ * normal.z
			local push: vector = normal * into
			moveX -= push.x
			moveY -= push.y
			moveZ -= push.z

			-- The velocity loses only the part that presses into the plane
			local pressing: number = velocityX * normal.x + velocityY * normal.y + velocityZ * normal.z

			if pressing < 0 then
				velocityX -= normal.x * pressing
				velocityY -= normal.y * pressing
				velocityZ -= normal.z * pressing
			end

			if normal.y >= FIXTURE.walkable then
				grounded = true
			end

			append(values, length, travel, share, into, pressing)
		end

		x += moveX
		y += moveY
		z += moveZ

		-- Snap down onto ground within reach under the hull
		local gap: number = y - tick.rest

		if velocityY <= 0 and gap <= FIXTURE.snapDistance then
			y = tick.rest
			velocityY = 0
			grounded = true
		end

		append(values, gap, x, y, z, velocityX, velocityY, velocityZ)

		-- Quantize the state to the precisions the server sends
		x = math.round(x * FIXTURE.positionScale) / FIXTURE.positionScale
		y = math.round(y * FIXTURE.positionScale) / FIXTURE.positionScale
		z = math.round(z * FIXTURE.positionScale) / FIXTURE.positionScale
		velocityX = math.round(velocityX * FIXTURE.velocityScale) / FIXTURE.velocityScale
		velocityY = math.round(velocityY * FIXTURE.velocityScale) / FIXTURE.velocityScale
		velocityZ = math.round(velocityZ * FIXTURE.velocityScale) / FIXTURE.velocityScale

		append(values, x, y, z, velocityX, velocityY, velocityZ)
	end

	return values
end

--[[
    Writes each number as the 16 hex digits of its 8 bytes, high byte first,
    one a line, so both realms' runs compare as text
--]]

function Probe.encode(values: { number }): string
	local bytes: buffer = buffer.create(F64_BYTES)
	local lines: { string } = {}

	for _, value: number in values do
		buffer.writef64(bytes, 0, value)
		table.insert(lines, string.format(HEX, buffer.readu32(bytes, HIGH_WORD), buffer.readu32(bytes, 0)))
	end

	return table.concat(lines, "\n")
end

return Probe
