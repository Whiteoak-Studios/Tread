--[[
    P10's messages and their answers: the recorded boxes split at whole
    boxes under the piece size behind P7's rebuilt ones, each placed by its
    first box, and a clone's answers put back at those places in any order
--]]

--!strict
local Harness = require("../../Fixtures/DevServer/Harness")
local Kit = require("../../Fixtures/Exploits/Kit")

local BOUNDS: string = "dev/Server/Parallel/Bounds.luau"
local BOX_VALUES: number = 6 -- A box's f64s, its center then its size
local VALUE_BYTES: number = 8
local BOX_BYTES: number = BOX_VALUES * VALUE_BYTES
local SPILL: number = 792 -- Recorded boxes past one whole piece, so a second message carries them

-- Recorded boxes, each box's center x its place among them from 0, so a piece shows which boxes it holds
local function recorded(count: number): buffer
	local boxes: buffer = buffer.create(count * BOX_BYTES)
	for box: number = 0, count - 1 do
		buffer.writef64(boxes, box * BOX_BYTES, box)
	end

	return boxes
end

-- Why a message's boxes are not that many recorded boxes from that place, or nil when they are
local function wrongBoxes(boxes: buffer, from: number, count: number): string?
	if buffer.len(boxes) ~= count * BOX_BYTES then
		return `it holds {buffer.len(boxes) // BOX_BYTES} boxes, not {count}`
	end

	for box: number = 0, count - 1 do
		local place: number = buffer.readf64(boxes, box * BOX_BYTES)
		if place ~= from + box then
			return `its box {box + 1} is recorded box {place + 1}, not {from + box + 1}`
		end
	end

	return nil
end

-- A clone's answers to a message, each its box's place among every box it was sent, so the whole shows where each went
local function answering(message: any): any
	local count: number = message.count + buffer.len(message.boxes) // BOX_BYTES
	local answers: buffer = buffer.create(count * VALUE_BYTES)
	for box: number = 0, count - 1 do
		buffer.writef64(answers, box * VALUE_BYTES, message.at + box)
	end

	return { at = message.at, answers = answers }
end

return function (): (boolean, string | nil)
	local loaded: Harness.Loaded = Harness.load()
	local dataModel: any = loaded.game
	local server: any = dataModel:GetService("ServerScriptService").Server
	local shared: any = dataModel:GetService("ReplicatedStorage").Shared
	local step: any = loaded.require(server.Config.Parallel).step

	-- The dev shared table stands in empty, since splitting and assembling read nothing of it
	local results: { [any]: any } = { [shared.Dev.Config] = {} }
	local Bounds: any =
		Kit.loader(dataModel, { [server.Parallel.Bounds] = BOUNDS }, results, loaded.require)(server.Parallel.Bounds)

	local perPiece: number = step.pieceBytes // BOX_BYTES
	local total: number = perPiece + SPILL

	-- 1) Past one piece, the first message rebuilds P7's boxes and carries a whole piece, the second the rest
	local messages: { any } = Bounds.messages(recorded(total))
	if #messages ~= 2 then
		return false, `{total} recorded boxes went in {#messages} messages, not 2`
	end

	local first: any, second: any = messages[1], messages[2]
	if first.at ~= 0 or first.count ~= step.boxes then
		return false,
			`The first message starts at box {first.at} rebuilding {first.count}, not at 0 rebuilding {step.boxes}`
	elseif second.at ~= step.boxes + perPiece or second.count ~= 0 then
		local expected: number = step.boxes + perPiece
		return false,
			`The second message starts at box {second.at} rebuilding {second.count}, not at {expected} rebuilding 0`
	end

	local wrong: string? = wrongBoxes(first.boxes, 0, perPiece) or wrongBoxes(second.boxes, perPiece, SPILL)
	if wrong then
		return false, `A message's boxes are off: {wrong}`
	end

	-- 2) With nothing recorded, one message rebuilds P7's boxes alone
	local alone: { any } = Bounds.messages(recorded(0))
	if #alone ~= 1 or alone[1].at ~= 0 or alone[1].count ~= step.boxes or buffer.len(alone[1].boxes) ~= 0 then
		return false, `With nothing recorded there were {#alone} messages, the first not P7's boxes alone`
	end

	-- 3) A clone's answers come back in any order and are put back at their boxes
	local sent: number = step.boxes + total
	local whole: any = Bounds.assemble({ answering(second), answering(first) }, sent)
	if type(whole) ~= "buffer" then
		return false, `Both messages' answers were refused: {whole}`
	elseif buffer.len(whole) ~= sent * VALUE_BYTES then
		return false, `The answers held {buffer.len(whole) // VALUE_BYTES} boxes, not {sent}`
	end

	for box: number = 0, sent - 1 do
		local place: number = buffer.readf64(whole, box * VALUE_BYTES)
		if place ~= box then
			return false, `Box {box + 1}'s answer was the one for box {place + 1}`
		end
	end

	-- 4) Answers short of every box, or past them, are refused with what they held
	local short: any = Bounds.assemble({ answering(first) }, sent)
	if short ~= `its answers held {step.boxes + perPiece} of the {sent} boxes it was sent` then
		return false, `One message's answers alone gave {short}`
	end

	local past: any = Bounds.assemble({ answering(first), answering(second) }, sent - 1)
	if past ~= `{SPILL} answers from box {second.at + 1} run past the {sent - 1} boxes it was sent` then
		return false, `Answers past the boxes sent gave {past}`
	end

	return true, nil
end
