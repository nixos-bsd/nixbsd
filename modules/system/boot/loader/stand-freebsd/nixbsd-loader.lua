-- nixbsd loader entry point
-- Modify the menu to have all the kernels and kernel settings available in /boot/available-systems

local menu = require("menu")
local core = require("core")
local config = require("config")
local color = require("color")
local orig_entries_func = menu.welcome.entries

local nixbsd_config = require("stand_config")

local cached_systems = nil;
local function systemList()
	loader.setenv("system", nixbsd_config.tags[1])
	return nixbsd_config.tags;
end

menu.welcome.all_entries.kernel_options = {
	entry_type = core.MENU_CAROUSEL_ENTRY,
	carousel_id = "system",
	items = systemList,
	name = function(idx, choice, all_choices)
		if #all_choices == 0 then
			return "System: "
		end

		local is_default = (idx == 1)
		local kernel_name = ""
		local name_color
		if is_default then
			name_color = color.escapefg(color.GREEN)
			--kernel_name = "default/"
		else
			name_color = color.escapefg(color.BLUE)
		end
		kernel_name = kernel_name .. name_color ..
		    nixbsd_config.entries[choice].label .. color.resetfg()
		return "S" .. color.highlight("y") .. "stem: " ..
		    kernel_name .. " (" .. idx .. " of " ..
		    #all_choices .. ")"
	end,
	func = function(_, choice, _)
		if loader.getenv("kernelname") ~= nil then
			loader.perform("unload")
		end
		config.selectKernel(choice)
	end,
	alias = {"y", "Y"},
}

orig_loadKernel = config.loadKernel
function config.loadKernel(other_kernel)
	local system = other_kernel or loader.getenv("system")
	local entry = nixbsd_config.entries[system]
	loader.setenv("init_path", entry.init)
	for k, v in pairs(entry.kernelEnvironment) do
		loader.setenv(k, v)
	end
	orig_loadKernel(entry.kernel)
end

require("loader_orig")
