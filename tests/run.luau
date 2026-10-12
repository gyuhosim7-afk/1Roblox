-- Lune test runner. Usage: lune run tests/run [filter]
-- Spec files live in tests/specs/*.spec.luau and return function(t) ... end
-- where t.describe / t.it / t.expect / t.World are provided.

local fs = require("@lune/fs")
local process = require("@lune/process")

local World = require("./harness/World")

local filter = process.args[1]

local passed, failed = 0, 0
local failures = {}
local currentSuite = {}

local function deepEqual(a, b)
	if a == b then
		return true
	end
	if type(a) ~= "table" or type(b) ~= "table" then
		return false
	end
	for k, v in a do
		if not deepEqual(v, b[k]) then
			return false
		end
	end
	for k in b do
		if a[k] == nil then
			return false
		end
	end
	return true
end

local function fmt(value)
	if type(value) == "string" then
		return string.format("%q", value)
	end
	return tostring(value)
end

local function expect(actual)
	local e = {}
	function e.toBe(expected)
		if actual ~= expected then
			error(string.format("expected %s to be %s", fmt(actual), fmt(expected)), 2)
		end
	end
	function e.toEqual(expected)
		if not deepEqual(actual, expected) then
			error(string.format("expected tables to be deeply equal (got %s)", fmt(actual)), 2)
		end
	end
	function e.toBeCloseTo(expected, tolerance)
		if math.abs(actual - expected) > (tolerance or 1e-6) then
			error(string.format("expected %s to be close to %s", fmt(actual), fmt(expected)), 2)
		end
	end
	function e.toBeTruthy()
		if not actual then
			error(string.format("expected %s to be truthy", fmt(actual)), 2)
		end
	end
	function e.toBeFalsy()
		if actual then
			error(string.format("expected %s to be falsy", fmt(actual)), 2)
		end
	end
	function e.toBeNil()
		if actual ~= nil then
			error(string.format("expected nil, got %s", fmt(actual)), 2)
		end
	end
	function e.toBeGreaterThan(expected)
		if not (actual > expected) then
			error(string.format("expected %s > %s", fmt(actual), fmt(expected)), 2)
		end
	end
	function e.toBeGreaterThanOrEqual(expected)
		if not (actual >= expected) then
			error(string.format("expected %s >= %s", fmt(actual), fmt(expected)), 2)
		end
	end
	function e.toBeLessThan(expected)
		if not (actual < expected) then
			error(string.format("expected %s < %s", fmt(actual), fmt(expected)), 2)
		end
	end
	function e.toBeLessThanOrEqual(expected)
		if not (actual <= expected) then
			error(string.format("expected %s <= %s", fmt(actual), fmt(expected)), 2)
		end
	end
	function e.toContain(expected)
		if type(actual) == "string" then
			if not actual:find(expected, 1, true) then
				error(string.format("expected %s to contain %s", fmt(actual), fmt(expected)), 2)
			end
			return
		end
		for _, v in actual do
			if v == expected then
				return
			end
		end
		error(string.format("expected list to contain %s", fmt(expected)), 2)
	end
	function e.toThrow(pattern)
		local ok, err = pcall(actual)
		if ok then
			error("expected function to throw", 2)
		end
		if pattern and not tostring(err):find(pattern, 1, true) then
			error(string.format("expected error containing %s, got %s", fmt(pattern), fmt(err)), 2)
		end
	end
	return e
end

local t = {}
t.World = World
t.expect = expect

function t.describe(name: string, fn: () -> ())
	table.insert(currentSuite, name)
	fn()
	table.remove(currentSuite)
end

function t.it(name: string, fn: () -> ())
	local fullName = table.concat(currentSuite, " > ") .. " > " .. name
	if filter and not fullName:lower():find(filter:lower(), 1, true) then
		return
	end
	local ok, err = xpcall(fn, function(message)
		return tostring(message) .. "\n" .. debug.traceback(nil, 2)
	end)
	if ok then
		passed += 1
	else
		failed += 1
		table.insert(failures, { name = fullName, err = err })
	end
end

local specs = fs.readDir("tests/specs")
table.sort(specs)
for _, file in specs do
	if file:match("%.spec%.luau$") then
		local specFn = require("./specs/" .. file:gsub("%.luau$", ""))
		table.insert(currentSuite, (file:gsub("%.spec%.luau$", "")))
		local ok, err = pcall(specFn, t)
		table.remove(currentSuite)
		if not ok then
			failed += 1
			table.insert(failures, { name = file .. " (load)", err = tostring(err) })
		end
	end
end

for _, failure in failures do
	print("\27[31mFAIL\27[0m " .. failure.name)
	print("     " .. tostring(failure.err):gsub("\n", "\n     "))
end
print(string.format("\n%d passed, %d failed", passed, failed))
if failed > 0 then
	process.exit(1)
end
