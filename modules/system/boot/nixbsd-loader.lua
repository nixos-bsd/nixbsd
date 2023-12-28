-- nixbsd loader entry point
-- Modify the menu to have all the kernels and kernel settings available in /boot/available-systems

local menu = require("menu")
local core = require("core")
local config = require("config")
local color = require("color")
local orig_entries_func = menu.welcome.entries

local cached_systems = nil;
local function systemList()
	if cached_system ~= nil then
		return cached_systems
	end

	local kernels = {}
	local i = 0

	for file, ftype in lfs.dir("/boot/available-systems") do
		if file == "." or file == ".." then
			goto continue
		end

		i = i + 1
		kernels[i] = file

		::continue::
	end

	loader.setenv("kernel", "available-systems/" .. kernels[1])

	-- TODO sort in some way

	core.cached_kernels = kernels
	return core.cached_kernels
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
		    choice .. color.resetfg()
		return "S" .. color.highlight("y") .. "stem: " ..
		    kernel_name .. " (" .. idx .. " of " ..
		    #all_choices .. ")"
	end,
	func = function(_, choice, _)
		if loader.getenv("kernelname") ~= nil then
			loader.perform("unload")
		end
		config.selectKernel("available-systems/" .. choice)
	end,
	alias = {"y", "Y"},
}

orig_loadKernel = config.loadKernel
function config.loadKernel(other_kernel)
	local kernel = other_kernel or loader.getenv("kernel")
	loader.setenv("module_path", kernel .. "/kernel-modules")
	loader.setenv("vfs.root.mountfrom", "ufs:/dev/ada0p2")
	loader.setenv("init_path", "/boot/" .. kernel .. "/init")
	loader.setenv("init_shell", "/boot/" .. kernel .. "/sw/bin/sh")
	loader.setenv("init_script", "/boot/" .. kernel .. "/activate")
	-- TODO load from the kernel-environment
	orig_loadKernel(other_kernel)
end

require("loader_orig")
