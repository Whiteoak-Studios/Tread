--[[
    The pieces of an arm's report: nearest-rank percentiles, the one-line
    summary each figure gets, and a line added to a report StringValue
--]]

--!strict
local NUMBER_FORMAT: string = "%.4g" -- Four significant digits suit kbps, milliseconds and Stats' raw times alike
local PERCENT: number = 100 -- Turns a fraction into the number a pNN label shows
local SEPARATOR: string = " " -- Between the pieces of one summary

local Report = {}

--[[
    The value at a fraction of the way up a sorted list, by nearest rank,
    so p95 of 120 samples is the 114th smallest
--]]

function Report.percentile(sorted: { number }, fraction: number): number
	local rank: number = math.max(1, math.ceil(fraction * #sorted))

	return sorted[rank]
end

--[[
    One number as every summary formats it
--]]

function Report.number(value: number): string
	return string.format(NUMBER_FORMAT, value)
end

--[[
    Sorts the samples in place and names each asked-for percentile and the
    sample count, as in p50 12.3 p95 45.6 p99 78.9 n 120
--]]

function Report.summary(samples: { number }, fractions: { number }): string
	if #samples == 0 then
		return "no samples"
	end

	table.sort(samples)

	local parts: { string } = {}
	for _, fraction: number in fractions do
		local label: number = math.round(fraction * PERCENT)
		table.insert(parts, `p{label} {Report.number(Report.percentile(samples, fraction))}`)
	end

	table.insert(parts, `n {#samples}`)

	return table.concat(parts, SEPARATOR)
end

--[[
    Adds a line to a report StringValue, one line per run, and prints it
    for the server or client log
--]]

function Report.append(report: StringValue, line: string)
	report.Value = report.Value == "" and line or `{report.Value}\n{line}`

	print(line)
end

return Report
