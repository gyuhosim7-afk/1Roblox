--!strict
-- Client entry point.

local Controllers = script.Parent:WaitForChild("Controllers")

local ORDER = {
	"StateController",
	"UIController",
	"WorldController",
	"GuardController",
	"TreadmillController",
	"EffectController",
	"InputController",
}

local loaded = {}
for _, name in ORDER do
	loaded[name] = (require :: any)(Controllers:WaitForChild(name))
end
for _, name in ORDER do
	local controller = loaded[name]
	if controller.Init then
		controller.Init()
	end
end
for _, name in ORDER do
	local controller = loaded[name]
	if controller.Start then
		controller.Start()
	end
end
