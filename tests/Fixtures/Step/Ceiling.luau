--[[
    The step's fixture geometry beside Geometry's: a ceiling a crouched hull
    fits under and a standing one does not, and every part the step's
    trials, its parity run and its live scenario build
--]]

--!strict
local Geometry = require(script.Parent.Geometry)

local UNDERSIDE: number = 3.5 -- Above the floor: over a crouched hull's 3.06 and under a standing one's 5
local THICKNESS: number = 1

type Part = Geometry.Part

local CEILING: Part = {
	name = "Ceiling",
	center = vector.create(-6, Geometry.floor + UNDERSIDE + THICKNESS / 2, -24),
	size = vector.create(8, THICKNESS, 8),
	tilt = 0,
}

local parts: { Part } = table.clone(Geometry.parts)
table.insert(parts, CEILING)

return {
	ceiling = CEILING,
	underside = Geometry.floor + UNDERSIDE,
	parts = parts,
}
