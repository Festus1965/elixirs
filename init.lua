-- Elixirs init.lua
-- Copyright Duane Robertson (duane@duanerobertson.com), 2017
-- Distributed under the LGPLv2.1 (https://www.gnu.org/licenses/old-licenses/lgpl-2.1.en.html)

elixirs = {}
local mod = elixirs
local mod_name = 'elixirs'
mod.version = '1.0'
mod.path = minetest.get_modpath(minetest.get_current_modname())
mod.world = minetest.get_worldpath()
mod.elixir_armor = true

local elixir_duration = 3600
local armor_mod = minetest.get_modpath('3d_armor') and armor and armor.set_player_armor
local gravity_off = { gravity = 0.1 }
local gravity_on = { gravity = 1 }


function mod.clone_node(name)
	if not (name and type(name) == 'string') then
		return
	end

	local node = minetest.registered_nodes[name]
	local node2 = table.copy(node)
	return node2
end


if minetest.registered_items['nmobs:slime_ball'] then
	mod.magic_ingredient = 'nmobs:slime_ball'
elseif minetest.registered_items['inspire:inspiration'] then
	mod.magic_ingredient = 'inspire:inspiration'
elseif minetest.registered_items['mobs_slimes:green_slimeball'] then
	mod.magic_ingredient = 'mobs_slimes:green_slimeball'
else
	minetest.register_craftitem(mod_name..':magic_placeholder', {
		description = 'Magic Ingredient',
		drawtype = 'plantlike',
		paramtype = 'light',
		tiles = { 'elixirs_elixir.png' },
		inventory_image = 'elixirs_elixir.png',
		groups = { dig_immediate = 3, vessel = 1 },
		sounds = default.node_sound_glass_defaults(),
	})

	mod.magic_ingredient = mod_name..':magic_placeholder'
end


mod.armor_id = {}
local armor_hud
if not armor_mod then
	armor_hud = function(player)
		if not (player and mod.armor_id) then
			return
		end

		local player_name = player:get_player_name()
		if not player_name then
			return
		end

		local armor_icon = {
			hud_elem_type = 'image',
			name = 'armor_icon',
			text = 'elixirs_shield.png',
			scale = { x=1,y=1 },
			position = { x=0.8, y=1 },
			offset = { x = -30, y = -80 },
		}

		local armor_text = {
			hud_elem_type = 'text',
			name = 'armor_text',
			text = '0%',
			number = 0xFFFFFF,
			position = { x=0.8, y=1 },
			offset = { x = 0, y = -80 },
		}

		mod.armor_id[player_name] = {}
		mod.armor_id[player_name].icon = player:hud_add(armor_icon)
		mod.armor_id[player_name].text = player:hud_add(armor_text)
	end

	mod.display_armor = function(player)
		if not (player and mod.armor_id) then
			return
		end

		local player_name = player:get_player_name()
		local armor = player:get_armor_groups()
		if not (player_name and armor and armor.fleshy) then
			return
		end

		player:hud_change(mod.armor_id[player_name].text, 'text', (100 - armor.fleshy)..'%')
	end
end


minetest.register_on_joinplayer(function(player)
	if not player then
		return
	end
	if armor_hud then
		armor_hud(player)
	end

	-- If there's an armor mod, we wait for it to load armor.
	if mod.load_armor_elixir and not armor_mod then
		mod.load_armor_elixir(player)
	end

	local player_name = player:get_player_name()
	if status_mod.has_status(player_name, 'high_jump') then
		player:set_physics_override(gravity_off)
	end
end)

-- support for 3d_armor
-- This may or may not work with all versions.
if armor_mod then
	local old_set_player_armor = armor.set_player_armor

	armor.set_player_armor = function(self, player)
		old_set_player_armor(self, player)
		if mod.load_armor_elixir then
			mod.load_armor_elixir(player)
		end
	end
end


if status_mod.register_status and status_mod.set_status then
	status_mod.register_status({
		name = 'breathe',
		terminate = function(player)
			if not player then
				return
			end

			local player_name = player:get_player_name()
			minetest.chat_send_player(player_name, minetest.colorize('#FF0000', 'Your breathing becomes more difficult...'))
		end,
	})

	minetest.register_craftitem(mod_name..':elixir_breathe', {
		description = 'Dr Robertson\'s Patented Easy Breathing Elixir',
		inventory_image = 'elixirs_elixir_breathe.png',
		on_use = function(itemstack, user, pointed_thing)
			if not (itemstack and user) then
				return
			end

			local player_name = user:get_player_name()
			if not (player_name and type(player_name) == 'string' and player_name ~= '') then
				return
			end

			status_mod.set_status(player_name, 'breathe', elixir_duration)
			minetest.chat_send_player(player_name, 'Your breathing becomes easier...')
			itemstack:take_item()
			return itemstack
		end,
	})

	minetest.register_craft({
		type = 'shapeless',
		output = mod_name..':elixir_breathe',
		recipe = {
			mod.magic_ingredient,
			'default:coral_skeleton',
			'vessels:glass_bottle',
		},
	})


	mod.reconcile_armor = function(elixir_armor, worn_armor)
		if elixir_armor < worn_armor then
			return elixir_armor
		end

		return worn_armor
	end

	-- set_armor assumes any armor mods have already set the normal armor values.
	local function set_armor(player, value, delay)
		if not (player and mod.reconcile_armor) then
			return
		end

		local armor = player:get_armor_groups()
		if not (armor and armor.fleshy and armor.fleshy >= value) then
			return
		end

		if armor_mod then
			armor.fleshy = mod.reconcile_armor(value, armor.fleshy)
		else
			armor.fleshy = value
		end

		player:set_armor_groups(armor)

		if mod.display_armor then
			if delay then
				-- Delay display, in case of lag.
				minetest.after(delay, function()
					mod.display_armor(player)
				end)
			else
				mod.display_armor(player)
			end
		end

		return true
	end

	-- called only by armor elixirs
	local function ingest_armor_elixir(player, value)
		if not (player and status_mod.set_status) then
			return
		end

		-- support for 3d_armor
		-- This may or may not work with all versions.
		if armor_mod then
			armor:set_player_armor(player)
		end

		if not set_armor(player, value) then
			return
		end

		local player_name = player:get_player_name()
		if not (player_name and type(player_name) == 'string' and player_name ~= '') then
			return
		end

		minetest.chat_send_player(player_name, 'Your skin feels harder...')
		status_mod.set_status(player_name, 'armor_elixir', elixir_duration, { value = value })
	end

	-- called on joinplayer and every time an armor mod updates
	mod.load_armor_elixir = function(player)
		if not player then
			return
		end

		local player_name = player:get_player_name()

		if status_mod.has_status(player_name, 'armor_elixir') then
			local status = status_mod.get_status(player_name, 'armor_elixir')
			if status and type(status.value) == 'number' then
				set_armor(player, status.value, 3)
			end
		end
	end

	status_mod.register_status({
		name = 'armor_elixir',
		terminate = function(player)
			if not player then
				return
			end

			player:set_armor_groups({ fleshy = 100 })
			if mod.display_armor then
				mod.display_armor(player)
			end

			-- support for 3d_armor
			-- This may or may not work with all versions.
			if armor_mod then
				minetest.after(1, function()
					armor:set_player_armor(player)
				end)
			end

			local player_name = player:get_player_name()
			if not (player_name and type(player_name) == 'string' and player_name ~= '') then
				return
			end

			minetest.chat_send_player(player_name, minetest.colorize('#FF0000', 'Your skin feels softer...'))
		end,
	})

	local descs = {
		{ 'wood', 90, 'group:wood' },
		{ 'stone', 80, 'group:stone' },
		{ 'granite', 70, 'mapgen:granite' },
		{ 'steel', 60, 'default:steel_ingot' },
		{ 'gold', 50, 'default:gold_ingot' },
		{ 'mese', 30, 'default:mese_crystal' },
		{ 'diamond', 20, 'default:diamond' },
		--{ 'adamant', 10, mod_name..':adamant' },
	}

	if mod.elixir_armor then
		for _, desc in pairs(descs) do
			local name = desc[1]
			local value = desc[2]
			local cap = name:gsub('^%l', string.upper)
			minetest.register_craftitem(mod_name..':liquid_'..name, {
				description = 'Dr Robertson\'s Patented Liquid '..cap..' Elixir',
				drawtype = 'plantlike',
				paramtype = 'light',
				tiles = { 'elixirs_liquid_'..name..'.png' },
				inventory_image = 'elixirs_liquid_'..name..'.png',
				groups = { dig_immediate = 3, vessel = 1 },
				sounds = default.node_sound_glass_defaults(),
				on_use = function(itemstack, user, pointed_thing)
					if not (itemstack and user) then
						return
					end

					ingest_armor_elixir(user, value)
					itemstack:take_item()
					return itemstack
				end,
			})

			minetest.register_craft({
				type = 'shapeless',
				output = mod_name..':liquid_'..name,
				recipe = {
					mod.magic_ingredient,
					desc[3],
					'vessels:glass_bottle',
				},
			})
		end
	end
end


minetest.register_chatcommand('armor', {
	params = '',
	description = 'Display your armor values',
	privs = {},
	func = function(player_name, param)
		if type(player_name) ~= 'string' or player_name == '' then
			return
		end

		local player = minetest.get_player_by_name(player_name)
		if not player then
			return
		end

		local armor = player:get_armor_groups()
		if armor then
			minetest.chat_send_player(player_name, 'Armor:')
			for group, value in pairs(armor) do
				minetest.chat_send_player(player_name, '  '..group..' '..value)
			end

			if status_mod.has_status(player_name, 'armor_elixir') then
				local status = status_mod.get_status(player_name, 'armor_elixir')
				if not status then
					return
				end

				local armor_time = status.remove
				local game_time = minetest.get_gametime()
				if type(armor_time) ~= 'number'
					or type(game_time) ~= 'number' then
					return
				end

				local min = math.floor(math.max(0, armor_time - game_time) / 60)
				minetest.chat_send_player(player_name, 'Your armor elixir will expire in '..min..' minutes.')
			end
		end
	end,
})


minetest.register_craftitem(mod_name..':naptha', {
	description = 'Bottle of Naptha',
	inventory_image = 'elixirs_naptha.png',
})

minetest.register_craft({
	output = mod_name..':naptha',
	type = 'shapeless',
	recipe = {
		'vessels:glass_bottle', 'group:coal', mod.magic_ingredient,
	},
})

if minetest.registered_items['bucket:bucket_empty'] then
	minetest.register_craftitem(mod_name..':bucket_of_naptha', {
		description = 'Bucket of Naptha',
		inventory_image = 'elixirs_bucket_naptha.png',
	})

	minetest.register_craft({
		output = mod_name..':bucket_of_naptha',
		recipe = {
			{mod_name..':naptha', mod_name..':naptha', mod_name..':naptha', },
			{mod_name..':naptha', 'bucket:bucket_empty', mod_name..':naptha', },
			{mod_name..':naptha', mod_name..':naptha', mod_name..':naptha', },
		},
		replacements = {
			{ mod_name..':naptha', 'vessels:glass_bottle' },
			{ mod_name..':naptha', 'vessels:glass_bottle' },
			{ mod_name..':naptha', 'vessels:glass_bottle' },
			{ mod_name..':naptha', 'vessels:glass_bottle' },
			{ mod_name..':naptha', 'vessels:glass_bottle' },
			{ mod_name..':naptha', 'vessels:glass_bottle' },
			{ mod_name..':naptha', 'vessels:glass_bottle' },
			{ mod_name..':naptha', 'vessels:glass_bottle' },
		},
	})
end

if minetest.registered_items['wooden_bucket:bucket_wood_empty'] then
	minetest.register_craftitem(mod_name..':wood_bucket_of_naptha', {
		description = 'Wooden Bucket of Naptha',
		inventory_image = 'elixirs_wood_bucket_naptha.png',
	})

	minetest.register_craft({
		output = mod_name..':wood_bucket_of_naptha',
		recipe = {
			{mod_name..':naptha', mod_name..':naptha', mod_name..':naptha', },
			{mod_name..':naptha', 'wooden_bucket:bucket_wood_empty', mod_name..':naptha', },
			{mod_name..':naptha', mod_name..':naptha', mod_name..':naptha', },
		},
		replacements = {
			{ mod_name..':naptha', 'vessels:glass_bottle' },
			{ mod_name..':naptha', 'vessels:glass_bottle' },
			{ mod_name..':naptha', 'vessels:glass_bottle' },
			{ mod_name..':naptha', 'vessels:glass_bottle' },
			{ mod_name..':naptha', 'vessels:glass_bottle' },
			{ mod_name..':naptha', 'vessels:glass_bottle' },
			{ mod_name..':naptha', 'vessels:glass_bottle' },
			{ mod_name..':naptha', 'vessels:glass_bottle' },
		},
	})
end

minetest.register_craft({
	type = 'fuel',
	recipe = mod_name..':naptha',
	burntime = 5,
})


dofile(mod.path .. '/bombs_api.lua')

mod:register_throwitem(mod_name..':molotov_cocktail', 'Molotov Cocktail', {
	textures = 'more_fire_molotov_cocktail.png',
	recipe = { 'farming:cotton', mod_name..':naptha', },
	recipe_type = 'shapeless',
	explosion = {
		shape = 'sphere_cover',
		radius = 5,
		block = 'fire:basic_flame',
		particles = false,
		sound = 'more_fire_shatter'
		--sound = 'more_fire_ignite'
	}
})

-- fuel recipes
minetest.register_craft({
	type = 'fuel',
	recipe = mod_name..':molotov_cocktail',
	burntime = 5,
})


mod:register_throwitem(mod_name..':grenade', 'Grenado', {
	textures = 'elixirs_grenade.png',
	recipe = { 'farming:cotton', 'vessels:steel_bottle', 'tnt:gunpowder', },
	recipe_type = 'shapeless',
	hit_node = function (self, pos)
		tnt.boom(pos, { damage_radius=5,radius=1,ignore_protection=false })
	end,
})


if minetest.get_modpath('mapgen') then
	local cnode = mod.clone_node('default:glass')
	cnode.description = 'Moon Glass'
	cnode.light_source = 14
	minetest.register_node(mod_name..':moon_glass', cnode)

	minetest.register_craft({
		output = mod_name..':moon_glass',
		type = 'shapeless',
		recipe = { 'default:glass', 'mapgen:glowing_fungus', mod.magic_ingredient },
	})
end


do
	local function ingest_jump_elixir(player)
		if not (player and status_mod.set_status) then
			return
		end

		local player_name = player:get_player_name()
		if not (player_name and type(player_name) == 'string' and player_name ~= '') then
			return
		end

		player:set_physics_override(gravity_off)
		minetest.chat_send_player(player_name, 'You fell lightheaded... and footed...')
		status_mod.set_status(player_name, 'high_jump', elixir_duration, {})
	end

	minetest.register_craftitem(mod_name..':elixir_jump', {
		description = 'Dr Robertson\'s Patented Springy Step Elixir',
		drawtype = 'plantlike',
		paramtype = 'light',
		tiles = { 'elixirs_elixir_jump.png' },
		inventory_image = 'elixirs_elixir_jump.png',
		groups = { dig_immediate = 3, vessel = 1 },
		sounds = default.node_sound_glass_defaults(),
		on_use = function(itemstack, user, pointed_thing)
			if not (itemstack and user) then
				return
			end

			ingest_jump_elixir(user, value)
			itemstack:take_item()
			return itemstack
		end,
	})

	status_mod.register_status({
		name = 'high_jump',
		terminate = function(player)
			if not player then
				return
			end

			player:set_physics_override(gravity_on)

			local player_name = player:get_player_name()
			if not (player_name and type(player_name) == 'string' and player_name ~= '') then
				return
			end

			minetest.chat_send_player(player_name, minetest.colorize('#FF0000', 'Your feet feel leaden.'))
		end,
	})
	minetest.register_craft({
		type = 'shapeless',
		output = mod_name..':elixir_jump',
		recipe = {
			mod.magic_ingredient,
			'flowers:mushroom_red',
			'flowers:mushroom_brown',
			'vessels:glass_bottle',
		},
	})
end


if false then
	local function turn_to_gold(pos, params)
		if not (params and params.self and pos) then
			return
		end

		local player = params.self.placer
		local player_name = player:get_player_name()
		if not (player_name and type(player_name) == 'string' and player_name ~= '') then
			return
		end

		local privs = minetest.check_player_privs(player_name, { server=true })
		if not privs then
			return
		end

		print('Elixirs: '..player_name..' used the Midas grenade')

		pos = vector.round(pos)

		local radius = math.floor(params.radius)
		local minp = vector.subtract(pos, radius)
		minp.y = minp.y - math.ceil(radius / 2)
		local maxp = vector.add(pos, radius)
		maxp.y = maxp.y + math.ceil(radius / 2)

		local air = minetest.get_content_id('air')
		local gold = minetest.get_content_id('default:goldblock')
		local silver = minetest.get_content_id('default:steelblock')
		local ignore = minetest.get_content_id('default:ignore')
		local stone = minetest.get_content_id('default:stone')
		local water = minetest.get_content_id('default:water_source')

		local waters = {}
		waters[minetest.get_content_id('default:water_source')] = true
		waters[minetest.get_content_id('default:river_water_source')] = true
		local stone_types = { 'default:stone', 'default:desert_stone', 'default:sandstone', 'default:dirt', 'fun_caves:dirt', 'default:dirt_with_snow', 'default:dirt_with_grass', 'default:dirt_with_dry_grass', 'default:sand', 'default:desert_sand', 'squaresville:concrete', 'squaresville:concrete2', 'squaresville:concrete3', 'squaresville:concrete4' }
		local stones = {}
		for i = 1, #stone_types do
			stones[minetest.get_content_id(stone_types[i])] = true
		end

		local vm = minetest.get_voxel_manip(minp, maxp)
		if not vm then
			return
		end

		local emin, emax = vm:read_from_map(minp, maxp)
		local area = VoxelArea:new({ MinEdge = emin, MaxEdge = emax })
		local data = vm:get_data()
		local heightmap = {}
		local height_avg = 0
		local count = 0

		for z = minp.z, maxp.z do
			local dz = z - minp.z
			for x = minp.x, maxp.x do
				local dx = x - minp.x
				local r = math.max(math.abs(radius - dx), math.abs(radius - dz)) / radius
				if r < 1 then
					local ivm = area:index(x, minp.y, z)
					for y = minp.y, maxp.y do
						if data[ivm] ~= air and data[ivm] ~= ignore and not waters[data[ivm]] then
							if stones[data[ivm]] then
								data[ivm] = gold
							else
								data[ivm] = silver
							end
						end
						ivm = ivm + area.ystride
					end
				end
			end
		end

		vm:set_data(data)
		--vm:set_lighting({ day = 15, night = 0 }, minp, maxp)
		--vm:calc_lighting(minp, maxp)
		vm:update_liquids()
		vm:write_to_map()
		vm:update_map()
	end


	mod:register_throwitem(mod_name..':midas_grenade', 'Trump Grenade', {
		textures = 'elixirs_grenade.png',
		recipe = {
			'farming:cotton',
			'vessels:steel_bottle',
			'tnt:gunpowder',
			'default:gold_ingot',
			'default:gold_ingot',
			elixirs.magic_ingredient,
			elixirs.magic_ingredient,
			elixirs.magic_ingredient
		},
		recipe_type = 'shapeless',
		hit_node = function (self, pos)
			turn_to_gold(pos, { self=self,radius=100,ignore_protection=false })
		end,
	})
end
