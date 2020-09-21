--<<
helper = wesnoth.require("lua/helper.lua")
local on_event = wesnoth.require("on_event")
local wc2_era = {}
wc2_era.factions_wml = {}
wc2_era.hero_types = {}
wc2_era.hero_traits = {}

local function remove_dublicates(t)
	local found = {}
	for i = #t, 1, -1 do
		local v = t[i]
		if found[v] then
			table.remove(t, i)
		else
			found[v] = true
		end
	end
end

-- the wc2 recruit pair logic.
on_event("recruit", function(ctx)
	local unit = wesnoth.get_unit(ctx.x1, ctx.y1)
	
	local side_num = unit.side
	local side = wesnoth.sides[side_num]
	local unittype = unit.type
	
	for i,v in ipairs(wml.array_access.get("wc2.pair", side)) do
		local p = wc2_utils.split_to_array(v.types)
		if p[1] == unittype and p[2] ~= nil then
			wesnoth.wml_actions.disallow_recruit {
				side = side_num,
				type = p[1],
			}
			wesnoth.wml_actions.allow_recruit {
				side = side_num,
				type = p[2],
			}
			p[1],p[2] = p[2],p[1]
			wesnoth.set_side_variable(side_num, "wc2.pair[" .. (i - 1) .. "].types", table.concat(p, ","))
			wesnoth.allow_undo(false)
			return
		end
	end
end)

function fix_faction_wml(cfg)
	for p in wml.child_range(cfg, "pair") do
		local u1 = wml.get_child(p, "unit")
		local u2 = wml.get_child(p, "replace") or {}
		if u1 then
			for k,v in pairs(p) do p[k]=nil end
			p.types = table.concat({u1.type, u2.type}, ",")
		end
	end
end

function wc2_era.get_faction(id)
	if type(id) == "number" then
		id = wesnoth.get_side_variable(id, "wc2.faction_id") or wesnoth.sides[id].faction
	end
	for i, faction in ipairs(wc2_era.factions_wml) do
		if faction.id == id then
			return faction
		end
	end
end

local function init_side(side_num)
		
	if wesnoth.get_side_variable(side_num, "wc2.faction_id") ~= nil then
		-- don't do this twice.
		return
	end
	local old_faction = wml.variables["player[" .. side_num .. "].faction.id"]
	if old_faction then
		--compatabiltiy code: remove all in player[side_num] except training.
		-- don't keep heroes, commanders, pairs, etc. They will be regenerated.
		local training = wml.array_access.get("player[" .. side_num .. "].training")
		wml.variables["player[" .. side_num .. "]"] = {}
		wml.array_access.set("player[" .. side_num .. "].training", training)
	end
	local side = wesnoth.sides[side_num]
	local faction = wc2_era.get_faction(old_faction or side_num)

	if faction and wesnoth.get_side_variable(side_num, "wc2.pair.length") == 0 and wml.get_child(faction, "pair") then
		wesnoth.set_side_variable(side_num, "wc2.faction_id", faction.id)
		wesnoth.wml_actions.disallow_recruit { side = side_num, recruit="" }
		local i = 0
		for v in wml.child_range(faction, "pair") do
			i = i + 1
			local p = wc2_utils.split_to_array(v.types)
			if wesnoth.random(1,2) == 2 then
				p[1],p[2] = p[2],p[1]
			end
			wesnoth.wml_actions.allow_recruit {
				side = side_num,
				type = p[1],
			}
			wesnoth.set_side_variable(side_num, "wc2.pair[" .. (i - 1) .. "].types", table.concat(p, ","))
		end
	end
	
	if not faction and #wc2_era.factions_wml > 0 then
		faction = wc2_era.factions_wml[wesnoth.random(#wc2_era.factions_wml)]
	end

	if not faction then
		return
	end

	local heroes = wc2_era.expand_hero_types(faction.heroes)
	local deserters = wc2_era.expand_hero_types(faction.deserters)
	local commanders = wc2_era.expand_hero_types(faction.commanders)

	helper.shuffle(heroes)
	helper.shuffle(deserters)
	helper.shuffle(commanders)

	wesnoth.set_side_variable(side_num, "wc2.heroes", table.concat(heroes, ","))
	wesnoth.set_side_variable(side_num, "wc2.deserters", table.concat(deserters, ","))
	wesnoth.set_side_variable(side_num, "wc2.commanders", table.concat(commanders, ","))
end

function wesnoth.wml_actions.wc2_init_era(cfg)
	cfg = wml.literal(cfg)
	
	if cfg.clear then
		wc2_era.factions_wml = {}
		wc2_era.hero_types = {}
		wc2_era.hero_traits = {}
	end
	
	wc2_era.wc2_era_id = cfg.wc2_era_id -- TODO removed for testing or error("missing wc2_era_id")
	for faction in wml.child_range(cfg, "faction") do
		fix_faction_wml(faction)
		table.insert(wc2_era.factions_wml, faction)
	end
	for i,v in ipairs(wml.get_child(cfg, "hero_types")) do
		wc2_era.hero_types[v[1]] = v[2]
	end
	for trait_extra in wml.child_range(cfg, "trait_extra") do
		
		local types = wc2_utils.split_to_set(trait_extra.types)
		local trait = wml.get_child(trait_extra, "trait") or helper.wml_error("missing [trait] in [trait_extra]")
		table.insert(wc2_era.hero_traits, { types = types, trait = trait} )
	end
end

function wc2_era.pick_deserter(side_num)
	local deserters = wc2_utils.split_to_array(wesnoth.get_side_variable(side_num, "wc2.deserters"))
	local index = #deserters
	local res = deserters[index]
	table.remove(deserters, index)
	wesnoth.set_side_variable(side_num, "wc2.deserters", table.concat(deserters, ","))
	return res
end

function wc2_era.expand_hero_types(types_str)
	local types = wc2_utils.split_to_array(types_str)
	local types_new = {}
	local types_res = {}
	while #types > 0 do
		for i,v in ipairs(types) do
			if wesnoth.unit_types[v] then
				table.insert(types_res, v)
			else
				local group = wc2_era.hero_types[v] or helper.wml_error("invalid group id '" .. v .. "'")
				wc2_utils.split_to_array(group.types, types_new)
			end
		end
		types = types_new
		types_new = {}
	end
	remove_dublicates(types_res)
	return types_res
end

function wc2_era.expand_hero_names(types_str, only_unitnames)
	local types = wc2_utils.split_to_array(types_str)
	local types_new = {}
	local names_res = {}
	while #types > 0 do
		for i,v in ipairs(types) do
			local ut = wesnoth.unit_types[v]
			if ut then
				table.insert(names_res, ut.name)
			else
				local group = wc2_era.hero_types[v]
				if group.name and not only_unitnames then
					table.insert(names_res, group.name)
				else
					wc2_utils.split_to_array(group.types, types_new)
				end
			end
		end
		types = types_new
		types_new = {}
	end
	return names_res
end

on_event("prestart", function()
	for i, s in ipairs(wesnoth.sides) do
		init_side(i)
	end
end)

function wc2_era.generate_bonus_heroes()
	return wc2_era.expand_hero_types("Dude")
end

function wesnoth.wml_actions.wc2_recruit_info(cfg)
		
	local side_num = wesnoth.get_viewing_side()
	local faction = wc2_era.get_faction(side_num)
	if not faction then
		wesnoth.wml_actions.message {
			scroll = false,
			canrecruit = true,
			side = side_num,
			message = _ "You are not using a WC2 faction.",
		}
		return
	end
	local message = {
		scroll = false,
		canrecruit = true,
		side = side_num,
		caption = faction.name,
		message = cfg.message,
	}
	
	for i,v in ipairs(wml.array_access.get("wc2.pair", side_num)) do
		local p = wc2_utils.split_to_array(v.types)
		local ut1 = wesnoth.unit_types[p[1]]
		local ut2 = wesnoth.unit_types[p[2]]
		local img = "misc/blank.png~SCALE(144,72)" .. 
			"~BLIT(" .. ut1.image .. "~TC(" .. side_num .. ",magenta))" ..
			"~BLIT(" .. ut2.image .. "~TC(" .. side_num .. ",magenta),72,0)"
		table.insert(message, {"option", {
			image = img,
			label= ut1.name,
			description = ut2.name,
		}})
	end
	wesnoth.wml_actions.message(message)
end

return wc2_era
-->>
