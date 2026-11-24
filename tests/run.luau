-- Test runner: `lune run tests/run.luau [filter]`. Runs every tests/specs/*.spec.luau, prints a summary and, on
-- GitHub Actions, one error annotation per failure so the failure shows on the pull request.

local fs = require("@lune/fs")
local process = require("@lune/process")

local Loader = require("./lib/Loader")

local filter = process.args[1]
local onCi = process.env.GITHUB_ACTIONS == "true"

local function serialize(v: any): string
	if type(v) == "string" then
		return string.format("%q", v)
	elseif type(v) ~= "table" then
		return tostring(v)
	end
	local keys = {}
	for k in v do
		table.insert(keys, k)
	end
	table.sort(keys, function(a, b)
		return tostring(a) < tostring(b)
	end)
	local parts = {}
	for _, k in keys do
		table.insert(parts, tostring(k) .. "=" .. serialize(v[k]))
	end
	return "{" .. table.concat(parts, ", ") .. "}"
end

local expect = {}

function expect.eq(actual: any, expected: any, message: string?)
	if actual ~= expected then
		error(
			string.format(
				"%sexpected %s, got %s",
				if message then message .. ": " else "",
				serialize(expected),
				serialize(actual)
			),
			2
		)
	end
end

function expect.same(actual: any, expected: any, message: string?)
	local a, e = serialize(actual), serialize(expected)
	if a ~= e then
		error(string.format("%sexpected %s, got %s", if message then message .. ": " else "", e, a), 2)
	end
end

function expect.truthy(value: any, message: string?)
	if not value then
		error((message or "expected a truthy value") .. ", got " .. serialize(value), 2)
	end
end

function expect.falsy(value: any, message: string?)
	if value then
		error((message or "expected a falsy value") .. ", got " .. serialize(value), 2)
	end
end

function expect.near(actual: number, expected: number, tolerance: number, message: string?)
	if math.abs(actual - expected) > tolerance then
		error(
			string.format(
				"%sexpected %s ± %s, got %s",
				if message then message .. ": " else "",
				expected,
				tolerance,
				actual
			),
			2
		)
	end
end

function expect.errorKey(ok: boolean, result: any, key: string)
	if ok or result ~= key then
		error(string.format("expected failure %q, got ok=%s result=%s", key, tostring(ok), serialize(result)), 2)
	end
end

local tests = {}

local function load(path: string): any
	return Loader.load("src/" .. path)
end

local files = {}
for _, name in fs.readDir("tests/specs") do
	if string.match(name, "%.spec%.luau$") then
		table.insert(files, name)
	end
end
table.sort(files)

for _, name in files do
	local spec = require("./specs/" .. string.gsub(name, "%.luau$", ""))
	spec(function(title: string, fn: () -> ())
		table.insert(tests, { file = name, title = title, fn = fn })
	end, expect, load)
end

local passed, failed = 0, 0
local started = os.clock()
for _, test in tests do
	local full = test.file .. " › " .. test.title
	if filter == nil or string.find(full, filter, 1, true) then
		local t0 = os.clock()
		local ok, err = xpcall(test.fn, debug.traceback)
		local ms = (os.clock() - t0) * 1000
		if ok then
			passed += 1
			print(string.format("  ✓ %s (%.0f ms)", full, ms))
		else
			failed += 1
			print(string.format("  ✗ %s\n%s", full, tostring(err)))
			if onCi then
				local message = string.gsub(string.gsub(tostring(err), "%%", "%%25"), "\n", "%%0A")
				print(string.format("::error file=tests/specs/%s,title=%s::%s", test.file, test.title, message))
			end
		end
	end
end

print(string.format("\n%d passed, %d failed in %.1f s", passed, failed, os.clock() - started))
process.exit(if failed > 0 then 1 else 0)
