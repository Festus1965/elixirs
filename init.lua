elixirs_mod = {}
elixirs_mod.version = "1.0"
elixirs_mod.path = minetest.get_modpath(minetest.get_current_modname())
elixirs_mod.world = minetest.get_worldpath()
elixirs_mod.elixir_armor = true

local elixir_duration = 3600
local armor_mod = minetest.get_modpath("3d_armor") and armor and armor.set_player_armor


if minetest.registered_items['inspire:inspiration'] then
  elixirs_mod.magic_ingredient = 'inspire:inspiration'
elseif minetest.registered_items['mobs_slimes:green_slimeball'] then
  elixirs_mod.magic_ingredient = 'mobs_slimes:green_slimeball'
else
  minetest.register_craftitem("elixirs:magic_placeholder", {
    description = 'Magic Ingredient',
    drawtype = "plantlike",
    paramtype = "light",
    tiles = {'elixirs_elixir.png'},
    inventory_image = 'elixirs_elixir.png',
    groups = {dig_immediate = 3, vessel = 1},
    sounds = default.node_sound_glass_defaults(),
	})

  elixirs_mod.magic_ingredient = 'elixirs:magic_placeholder'
end


elixirs_mod.armor_id = {}
local armor_hud
if not armor_mod then
	armor_hud = function(player)
		if not (player and elixirs_mod.armor_id) then
			return
		end

		local player_name = player:get_player_name()
		if not player_name then
			return
		end

		local armor_icon = {
			hud_elem_type = 'image',
			name = "armor_icon",
			text = 'elixirs_shield.png',
			scale = {x=1,y=1},
			position = {x=0.8, y=1},
			offset = {x = -30, y = -80},
		}

		local armor_text = {
			hud_elem_type = 'text',
			name = "armor_text",
			text = '0%',
			number = 0xFFFFFF,
			position = {x=0.8, y=1},
			offset = {x = 0, y = -80},
		}

		elixirs_mod.armor_id[player_name] = {}
		elixirs_mod.armor_id[player_name].icon = player:hud_add(armor_icon)
		elixirs_mod.armor_id[player_name].text = player:hud_add(armor_text)
	end

	elixirs_mod.display_armor = function(player)
		if not (player and elixirs_mod.armor_id) then
			return
		end

		local player_name = player:get_player_name()
		local armor = player:get_armor_groups()
		if not (player_name and armor and armor.fleshy) then
			return
		end

		player:hud_change(elixirs_mod.armor_id[player_name].text, 'text', (100 - armor.fleshy)..'%')
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
	if elixirs_mod.load_armor_elixir and not armor_mod then
		elixirs_mod.load_armor_elixir(player)
	end
end)

-- support for 3d_armor
-- This may or may not work with all versions.
if armor_mod then
	local old_set_player_armor = armor.set_player_armor

	armor.set_player_armor = function(self, player)
		old_set_player_armor(self, player)
		if elixirs_mod.load_armor_elixir then
			elixirs_mod.load_armor_elixir(player)
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

	minetest.register_craftitem("elixirs:elixir_breathe", {
		description = 'Dr Robertson\'s Patented Easy Breathing Elixir',
		inventory_image = "elixirs_elixir_breathe.png",
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
		type = "shapeless",
		output = 'elixirs:elixir_breathe',
		recipe = {
      elixirs_mod.magic_ingredient,
			'default:coral_skeleton',
			"vessels:glass_bottle",
		},
	})


	elixirs_mod.reconcile_armor = function(elixir_armor, worn_armor)
		if elixir_armor < worn_armor then
			return elixir_armor
		end

		return worn_armor
	end

	-- set_armor assumes any armor mods have already set the normal armor values.
	local function set_armor(player, value, delay)
		if not (player and elixirs_mod.reconcile_armor) then
			return
		end

		local armor = player:get_armor_groups()
		if not (armor and armor.fleshy and armor.fleshy >= value) then
			return
		end

		if armor_mod then
			armor.fleshy = elixirs_mod.reconcile_armor(value, armor.fleshy)
		else
			armor.fleshy = value
		end

		player:set_armor_groups(armor)

		if elixirs_mod.display_armor then
			if delay then
				-- Delay display, in case of lag.
				minetest.after(delay, function()
					elixirs_mod.display_armor(player)
				end)
			else
				elixirs_mod.display_armor(player)
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
		status_mod.set_status(player_name, 'armor_elixir', elixir_duration, {value = value})
	end

	-- called on joinplayer and every time an armor mod updates
	elixirs_mod.load_armor_elixir = function(player)
		if not (player and status_mod.db.status) then
			return
		end

		local player_name = player:get_player_name()
		if not (player_name and type(player_name) == 'string' and player_name ~= '') then
			return
		end

		if status_mod.db.status[player_name] and status_mod.db.status[player_name].armor_elixir then
			local value = status_mod.db.status[player_name].armor_elixir.value
			set_armor(player, value, 3)
		end
	end

	status_mod.register_status({
		name = 'armor_elixir',
		terminate = function(player)
			if not player then
				return
			end

			player:set_armor_groups({fleshy = 100})
			if elixirs_mod.display_armor then
				elixirs_mod.display_armor(player)
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
		{'wood', 95, 'group:wood'},
		{'stone', 90, 'group:stone'},
		{'steel', 80, 'default:steel_ingot'},
		{'copper', 85, 'default:copper_ingot'},
		{'bronze', 70, 'default:bronze_ingot'},
		{'gold', 60, 'default:gold_ingot'},
		{'diamond', 50, 'default:diamond'},
		--{'silver', 40, 'elixirs:silver_ingot'},
		{'mese', 30, 'default:mese_crystal'},
		--{'', 20, ''},
		--{'adamant', 10, 'elixirs:adamant'},
	}

	if elixirs_mod.elixir_armor then
		for _, desc in pairs(descs) do
			local name = desc[1]
			local value = desc[2]
			local cap = name:gsub('^%l', string.upper)
			minetest.register_craftitem("elixirs:liquid_"..name, {
				description = 'Dr Robertson\'s Patented Liquid '..cap..' Elixir',
				drawtype = "plantlike",
				paramtype = "light",
				tiles = {'elixirs_liquid_'..name..'.png'},
				inventory_image = 'elixirs_liquid_'..name..'.png',
				groups = {dig_immediate = 3, vessel = 1},
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
				type = "shapeless",
				output = 'elixirs:liquid_'..name,
				recipe = {
					elixirs_mod.magic_ingredient,
					desc[3],
					"vessels:glass_bottle",
				},
			})
		end
	end
end


minetest.register_chatcommand("armor", {
	params = "",
	description = "Display your armor values",
	privs = {},
	func = function(player_name, param)
		if not (player_name and type(player_name) == 'string' and player_name ~= '' and status_mod.db.status) then
			return
		end

		local player = minetest.get_player_by_name(player_name)
		if not player then
			return
		end

		local armor = player:get_armor_groups()
    print(dump(armor))
		if armor then
			minetest.chat_send_player(player_name, "Armor:")
			for group, value in pairs(armor) do
				minetest.chat_send_player(player_name, "  "..group.." "..value)
			end

			if status_mod.db.status[player_name].armor_elixir then
				local armor_time = status_mod.db.status[player_name].armor_elixir.remove
				local game_time = minetest.get_gametime()
				if not (armor_time and type(armor_time) == 'number' and game_time and type(game_time) == 'number') then
					return
				end

				local min = math.floor(math.max(0, armor_time - game_time) / 60)
				minetest.chat_send_player(player_name, "Your armor elixir will expire in "..min..' minutes.')
			end
		end
	end,
})


dofile(elixirs_mod.path .. "/molotov.lua")