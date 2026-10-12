--!strict
-- Validation helpers for untrusted client payloads.

local Validate = {}

function Validate.String(value: any, maxLength: number?): string?
	if type(value) ~= "string" then
		return nil
	end
	if #value == 0 or #value > (maxLength or 64) then
		return nil
	end
	return value
end

function Validate.Integer(value: any, min: number, max: number): number?
	if type(value) ~= "number" or value ~= value then
		return nil
	end
	if value ~= math.floor(value) or value < min or value > max then
		return nil
	end
	return value
end

function Validate.Boolean(value: any): boolean?
	if type(value) ~= "boolean" then
		return nil
	end
	return value
end

-- Returns the key if it exists in the dictionary, else nil.
function Validate.Key<T>(value: any, dictionary: { [string]: T }): string?
	if type(value) ~= "string" or #value > 64 then
		return nil
	end
	if dictionary[value] == nil then
		return nil
	end
	return value
end

return Validate
