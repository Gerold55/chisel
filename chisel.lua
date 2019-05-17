
local function get_formspec(name, width, height)
	local sizewidth = 8
	local txpos = (sizewidth-width)/2
	if width >= 8 then
		sizewidth = width
		txpos = 0
	end
	local chisel_formspec =
		"size[".. sizewidth ..",".. height+5 .."]" ..
		default.gui_bg ..
		default.gui_bg_img ..
		default.gui_slots ..
		"list[detached:"..name..";main;".. txpos ..",0;".. width ..",".. height ..";]"..
		"list[current_player;main;".. (sizewidth-8)/2 ..",".. height+0.85 ..";8,1;]" ..
		"list[current_player;main;".. (sizewidth-8)/2 ..",".. height+2.08 ..";8,3;8]" ..
		"listring[detached:"..name..";main]"..
		"listring[current_player;main]" ..
		default.get_hotbar_bg((sizewidth-8)/2,height+0.85)
	return chisel_formspec
end

local function inv_to_table(inv)
	local t = {}
	for listname, list in pairs(inv:get_lists()) do
		local size = inv:get_size(listname)
		if size then
			t[listname] = {}
			for i = 1, size, 1 do
				t[listname][i] = inv:get_stack(listname, i):to_table()
			end
		end
	end
	return t
end

local function table_to_inv(inv, t)
	for listname, list in pairs(t) do
		for i, stack in pairs(list) do
			inv:set_stack(listname, i, stack)
		end
	end
end

-- functions to handle upgrades (can be overridden)

-- called on chisel_inv_add_item, chisel_inv_remove_item and save_chisel_inv_itemstack (called on on_move, on_put and on_take)
function chisel.on_change_chisel_inv(chiselstack, chiselinv)
	return chiselstack, chiselinv
end

-- called on open chisel
function chisel.on_open_chisel(chiselstack, chiselinv, player)
	return chiselstack, chiselinv, player
end

-- called on close chisel
function chisel.on_close_chisel(player, fields, name, formname, sound)
	return player, fields, name, formname, sound
end

-- called before open chisel
function chisel.before_open_chisel(itemstack, user, width, height, sound)
	return itemstack, user, width, height, sound
end

-- called on use chisel
function chisel.on_use_chisel(itemstack, user, pointed_thing)
	return itemstack, user, pointed_thing
end

-- called on drop chisel
function chisel.on_drop_chisel(itemstack, dropper, pos)
	minetest.item_drop(itemstack, dropper, pos)
	return itemstack, dropper, pos
end


local function save_chisel_inv_itemstack(inv, stack)
	stack, inv = chisel.on_change_chisel_inv(stack, inv)
	local meta = stack:get_meta()
	meta:set_string("chisel_inv_content", minetest.serialize(inv_to_table(inv)))
	return stack
end

local function save_chisel_inv(inv, player)
	local playerinv = minetest.get_inventory{type="player", name=player:get_player_name()}
	local chisel_id = inv:get_location().name
	local listname = "main"
	local size = playerinv:get_size(listname)
	for i = 1, size, 1 do
		local stack = playerinv:get_stack(listname, i)
		local meta = stack:get_meta()
		if meta:get_string("chisel_chisel_identity") == chisel_id then
			stack = save_chisel_inv_itemstack(inv, stack)
			playerinv:set_stack(listname, i, stack)
		end
	end
end

local mod_storage = minetest.get_mod_storage()
local function create_invname(itemstack)
	local counter = mod_storage:get_int("counter", value) or 0
	counter = counter + 1
	mod_storage:set_int("counter", counter)
	return itemstack:get_name().."_C_"..counter
end

local function stack_to_player_inv(stack, player)
	local payerinv = player:get_inventory()
	if payerinv:room_for_item("main", stack) then
		payerinv:add_item("main", stack)
	else
		minetest.item_drop(stack, player, player:get_pos())
	end
end

local function open_chisel(itemstack, user, width, height, sound)
	itemstack, user, width, height, sound = chisel.before_open_chisel(itemstack, user, width, height, sound) 
	local allow_chisel_input = false
	if minetest.get_item_group(itemstack:get_name(), "chisel_chisel") > 0 then
		allow_chisel_input = true
	end
	local meta = itemstack:get_meta()
	local playername = user:get_player_name()
	local invname = meta:get_string("chisel_chisel_identity")
	
	-- chisel identity
	if invname == "" then
		local item_count = itemstack:get_count()
		if item_count > 1 then
			local newitemstack = itemstack:take_item(item_count-1)
			minetest.after(0.01, stack_to_player_inv, newitemstack, user)
		end
		invname = create_invname(itemstack)
		meta:set_string("chisel_chisel_identity", invname)
	end
	
	meta:set_int("chisel_width", width)
	meta:set_int("chisel_height", height)
	
	local inv = minetest.create_detached_inventory(invname, {
		allow_put = function(inv, listname, index, stack, player)
			if allow_chisel_input then
				if minetest.get_item_group(stack:get_name(), "chisel_chisel") > 0 then
					return 0
				end
			else
				if minetest.get_item_group(stack:get_name(), "chisel") > 0 then
					return 0
				end
			end
			return stack:get_count()
		end,
		on_move = function(inv, from_list, from_index, to_list, to_index, count, player)
			save_chisel_inv(inv, player)
		end,
		on_put = function(inv, listname, index, stack, player)
			save_chisel_inv(inv, player)
		end,
		on_take = function(inv, listname, index, stack, player)
			-- fix swap bug
			local size = inv:get_size(listname)
			for i = 1, size, 1 do
				local stack = inv:get_stack(listname, i)
				local remove_stack = false
				if allow_chisel_input then
					if minetest.get_item_group(stack:get_name(), "chisel_chisel") > 0 then
						remove_stack = true
					end
				else
					if minetest.get_item_group(stack:get_name(), "chisel") > 0 then
						remove_stack = true
					end
				end
				if remove_stack == true then
					inv:set_stack(listname, i, "")
					local playerinv = player:get_inventory()
					if playerinv:room_for_item("main", stack) then
						playerinv:add_item("main", stack)
					else
						minetest.item_drop(save_chisel_inv_itemstack(inv, stack), player, player:get_pos())
						minetest.close_formspec(player:get_player_name(), inv:get_location().name)
					end
				end
			end
			save_chisel_inv(inv, player)
		end,
	}, playername)
	inv:set_size("main", width*height)
	local invmetastring = meta:get_string("chisel_inv_content")
	if invmetastring ~= "" then
		table_to_inv(inv, minetest.deserialize(invmetastring))
		
		itemstack, inv, user = chisel.on_open_chisel(itemstack, inv, user)
		save_chisel_inv_itemstack(inv, itemstack)
	end
	
	if sound then
		minetest.sound_play(sound, {gain = 0.8, object = user, max_hear_distance = 5})
	end
	minetest.show_formspec(playername, invname, get_formspec(invname, width, height))
	return itemstack
end

function chisel.chisel_inv_add_item(chiselstack, itemstack)
	local meta = chiselstack:get_meta()
	local invname = meta:get_string("chisel_chisel_identity")
	if not invname then
		return false
	end
	local inv = minetest.create_detached_inventory(invname, {})
	local width = meta:get_int("chisel_width")
	local height = meta:get_int("chisel_height")
	inv:set_size("main", width*height)
	local invmetastring = meta:get_string("chisel_inv_content")
	if invmetastring ~= "" then
		table_to_inv(inv, minetest.deserialize(invmetastring))
		
		chiselstack, inv = chisel.on_change_chisel_inv(chiselstack, inv)
	end
	if inv:room_for_item("main", itemstack) then
		inv:add_item("main", itemstack)
		return save_chisel_inv_itemstack(inv, chiselstack)
	end
	return false
end

function chisel.chisel_inv_remove_item(chiselstack, itemstack)
	local meta = chiselstack:get_meta()
	local invname = meta:get_string("chisel_chisel_identity")
	if not invname then
		return false
	end
	local inv = minetest.create_detached_inventory(invname, {})
	local width = meta:get_int("chisel_width")
	local height = meta:get_int("chisel_height")
	inv:set_size("main", width*height)
	local invmetastring = meta:get_string("chisel_inv_content")
	if invmetastring ~= "" then
		table_to_inv(inv, minetest.deserialize(invmetastring))
		
		chiselstack, inv = chisel.on_change_chisel_inv(chiselstack, inv)
	end
	if inv:contains_item("main", itemstack) then
		inv:remove_item("main", itemstack)
		return save_chisel_inv_itemstack(inv, chiselstack)
	end
	return false
end

function chisel.register_chisel(name, chiseltable)
	minetest.register_craftitem(name, {
		description = chiseltable.description,
		inventory_image = chiseltable.inventory_image,
		groups = {chisel = 1},
		
		on_secondary_use = function(itemstack, user)
			return open_chisel(itemstack, user, chiseltable.width, chiseltable.height, chiseltable.sound_open)
		end,
		on_place = function(itemstack, placer, pointed_thing)
			return open_chisel(itemstack, placer, chiseltable.width, chiseltable.height, chiseltable.sound_open)
		end,
		on_use = function(itemstack, user, pointed_thing)
			return chisel.on_use_chisel(itemstack, user, pointed_thing)
		end,
		on_drop = function(itemstack, dropper, pos)
			return chisel.on_drop_chisel(itemstack, dropper, pos)
		end
	})
	
	minetest.register_on_player_receive_fields(function(player, formname, fields)
		local nisformn = string.find(formname, name.."_C_")
		if nisformn == 1 then
			if fields.quit then
				player, fields, name, formname, sound = chisel.on_close_chisel(player, fields, name, formname, chiseltable.sound_close)
				if chiseltable.sound_close then
					minetest.sound_play(sound, {gain = 0.8, object = player, max_hear_distance = 5})
				end
			end
		end
		return
	end)
end


chisel.register_chisel("chisel:iron_chisel", { 
	description = "Iron Chisel",
	inventory_image = "chisel_iron.png",
	width = 8,
	height = 4,
	sound_open = "chisel_open_chisel",
	sound_close = "chisel_close_chisel"
})



