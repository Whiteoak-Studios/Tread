--[[
    Whether a call errors with a message holding the text given, so a case
    tells the refusal it means from any other failure
--]]

--!strict
return function (text: string, call: (...any) -> ...any, ...: any): (boolean, string)
	local ran: boolean, message: any = pcall(call, ...)

	if ran then
		return false, "it ran without an error"
	elseif not string.find(`{message}`, text, 1, true) then
		return false, `it errored with {message}, which doesn't hold {text}`
	end

	return true, `{message}`
end
