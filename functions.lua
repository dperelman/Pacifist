PacifistMod = PacifistMod or {}
require("__Pacifist__.config")
require("__Pacifist__.functions.technology")

local array = require("__Pacifist__.lib.array")
local data_raw = require("__Pacifist__.lib.data_raw")
local string = require("__Pacifist__.lib.string")

local military_info = require("__Pacifist__.functions.military-info")



-- recipes that generate any of the given items
function PacifistMod.find_recipes_for(resulting_items)
    local function is_military_result(entry)
        local name = (type(entry) == "string" and entry) or entry.name or entry[1]
        return name and array.contains(resulting_items, name)
    end

    local function contains_result(section)
        if section.result then
            return is_military_result(section.result)
        elseif section.results then
            for _, result_entry in pairs(section.results) do
                if is_military_result(result_entry) then
                    return true
                end
            end
            return false
        else
            return false
        end
    end

    local function is_relevant_recipe(recipe)
        return contains_result(recipe)
                or (recipe.normal and contains_result(recipe.normal))
                or (recipe.expensive and contains_result(recipe.expensive))
    end

    local relevant_recipes = {}
    for _, recipe in pairs(data.raw.recipe) do
        if is_relevant_recipe(recipe) then
            table.insert(relevant_recipes, recipe.name)
        end
    end
    return relevant_recipes
end

function PacifistMod.remove_recipes(obsolete_recipe_names)
    data_raw.remove_all("recipe", obsolete_recipe_names)

    -- productivity module limitations contain recipe names
    for _, module in pairs(data.raw.module) do
        array.remove_all_values(module.limitation, obsolete_recipe_names)
    end
end

function PacifistMod.treat_military_science_pack_requirements()

    local function is_ingredient_military_science_pack(ingredient)
        -- ingredients have either the format {"science-pack", 5}
        -- or {type="tool", name="science-pack", amount=5}
        local ingredient_name = ingredient.name or ingredient[1]
        return data.raw.tool[ingredient_name] and array.contains(military_info.items.tool, ingredient_name)
    end

    for _, technology in pairs(data.raw.technology) do
        array.remove_in_place(technology.unit.ingredients, is_ingredient_military_science_pack)
    end

    -- labs should not show/take the science packs any more even if we can't produce them
    for _, lab in pairs(data.raw.lab) do
        array.remove_all_values(lab.inputs, PacifistMod.military_science_packs)
    end

end

function PacifistMod.remove_military_recipe_ingredients(military_item_names, military_item_recipes)
    local function has_no_ingredients(recipe)
        if recipe.ingredients then
            return array.is_empty(recipe.ingredients)
        end
        return (recipe.normal and array.is_empty(recipe.normal.ingredients or {}))
                or (recipe.expensive and array.is_empty(recipe.expensive.ingredients or {}))
    end

    local function is_ignored_result(result)
        if type(result) == "string" then
            return not array.contains(PacifistMod.ignore.result_items, result)
        else
            return array.is_empty(result) or array.contains(PacifistMod.ignore.result_items, result.name or result[1])
        end
    end

    local function has_no_results(recipe)
        local function section_has_no_result(section)
            if not section then return false end

            if section.result then
                is_ignored_result(section.result)
            elseif section.results then
                return array.all_of(section.results, is_ignored_result)
            else
                return false
            end
        end

        return section_has_no_result(recipe)
                or section_has_no_result(recipe.normal)
                or section_has_no_result(recipe.expensive)
                or array.any_of(PacifistMod.ignore.recipe_pred, function(predicate) return predicate(recipe) end)
    end

    local obsolete_recipes = {}
    for _, recipe in pairs(data.raw.recipe) do
        if not has_no_ingredients(recipe) then
            local removed = {}
            local function is_ingredient_military_item(ingredient)
                -- ingredients have either the format {"advanced-circuit", 5}
                -- or {type="fluid", name="water", amount=50}
                local ingredient_name = ingredient.name or ingredient[1]
                if array.contains(military_item_names, ingredient_name) then
                    table.insert(removed, ingredient_name)
                    return true
                end
                return false
            end

            array.remove_in_place(recipe.ingredients, is_ingredient_military_item)
            array.remove_in_place(recipe.normal and recipe.normal.ingredients, is_ingredient_military_item)
            array.remove_in_place(recipe.expensive and recipe.expensive.ingredients, is_ingredient_military_item)
            if (has_no_ingredients(recipe)) and has_no_results(recipe) then
                table.insert(obsolete_recipes, recipe.name)
            elseif (not array.is_empty(removed)) and (not array.contains(military_item_recipes, recipe.name)) then
                log("removing ingredient(s) " .. array.to_string(removed) .. " from recipe " .. recipe.name)
            end
        end
    end
    if (not array.is_empty(obsolete_recipes)) then
        debug_log("removing recipes with no ingredients and no results left: " .. array.to_string(obsolete_recipes, "\n    "))
        PacifistMod.remove_recipes(obsolete_recipes)
    end
    return obsolete_recipes
end

function PacifistMod.remove_military_entities()
    debug_log("removing entities: " .. array.to_string(military_info.entities.names, "\n  "))
    local entity_types = PacifistMod.military_entity_types
    array.append(entity_types, PacifistMod.extra.entity_types)

    for _, type in pairs(entity_types) do
        data_raw.remove_all(type, military_info.entities.names)
    end

    for _, type in pairs(PacifistMod.military_equipment_types) do
        data_raw.remove_all(type, military_info.equipment.names)
    end
end

function PacifistMod.disable_gun_slots()
    local x_icon = "__core__/graphics/set-bar-slot.png"
    local tool_icon = "__Pacifist__/graphics/slot-icon-tool.png"
    local icon_kinds = { "gun", "ammo" }
    for _, kind in pairs(icon_kinds) do
        local icon = x_icon
        if (not array.is_empty(PacifistMod.exceptions[kind])) then
            icon = tool_icon
        end
        for _, to_replace in pairs({ "slot_icon_" .. kind, "slot_icon_" .. kind .. "_black" }) do
            data.raw["utility-sprites"].default[to_replace].filename = icon
        end
    end
end

function PacifistMod.remove_vehicle_guns()
    for _, type in pairs(PacifistMod.vehicle_types) do
        for _, vehicle in pairs(data.raw[type]) do
            vehicle.guns = nil
        end
    end
end

function PacifistMod.remove_unit_attacks()
    for _, name in pairs(PacifistMod.units_to_disarm) do
        if data.raw["unit"][name].attack_parameters.ammo_type then
            data.raw["unit"][name].attack_parameters.ammo_type.action = nil
        end
    end
end

function PacifistMod.remove_armor_references()
    for _, corpse in pairs(data.raw["character-corpse"]) do
        if corpse.armor_picture_mapping then
            for _, armor in pairs(PacifistMod.extra.armor) do
                corpse.armor_picture_mapping[armor] = nil
            end
        end
    end

    for _, character in pairs(data.raw["character"]) do
        for _, animation in pairs(character.animations) do
            if animation.armors then
                array.remove_all_values(animation.armors, PacifistMod.extra.armor)
            end
        end
    end
end

function PacifistMod.remove_military_items_signals(military_item_names)
    local function is_military_item_signal(signal_color_mapping)
        return signal_color_mapping.type == "item"
                and array.contains(military_item_names, signal_color_mapping.name)
    end

    for _, lamp in pairs(data.raw["lamp"] or {}) do
        array.remove_in_place(lamp.signal_to_color_mapping, is_military_item_signal)
    end
end

function PacifistMod.remove_military_items(military_item_table)
    for type, items in pairs(military_item_table) do
        debug_log("removing " .. type .. " prototypes: " .. array.to_string(items, "\n  "))
        data_raw.remove_all(type, items)
    end
end

function PacifistMod.remove_misc()
    -- the tips and tricks items that refers to removed technology/weapons
    if PacifistMod.settings.remove_walls then
        data_raw.remove("tips-and-tricks-item", "gate-over-rail")
    end
    data_raw.remove_all("tips-and-tricks-item", { "shoot-targeting", "shoot-targeting-controller" })

    -- achievements involving military means
    data_raw.remove("dont-build-entity-achievement", "raining-bullets")
    data_raw.remove("group-attack-achievement", "it-stinks-and-they-dont-like-it")
    data_raw.remove("kill-achievement", "steamrolled")
    data_raw.remove("kill-achievement", "pyromaniac")
    data_raw.remove("combat-robot-count", "minions")

    -- some main menu simulations won't run when the according prototypes are missing
    -- also we don't want to see biters and characters slaughtering each other
    local simulations = data.raw["utility-constants"]["default"].main_menu_simulations
    for _, name in pairs(PacifistMod.extra.main_menu_simulations) do
        simulations[name] = nil
    end

    for _, entry in pairs(PacifistMod.extra.misc) do
        assert(entry[1] and entry[2])
        data_raw.remove(entry[1], entry[2])
    end
end

function PacifistMod.disable_biters_in_presets()
    local presets = data.raw["map-gen-presets"]["default"]
    presets["death-world"] = nil
    presets["death-world-marathon"] = nil

    for key, preset in pairs(presets) do
        if not array.contains({ "type", "name", "default" }, key) then
            preset.basic_settings = preset.basic_settings or {}
            preset.basic_settings.autoplace_controls = preset.basic_settings.autoplace_controls or {}
            preset.basic_settings.autoplace_controls["enemy-base"] = { size = "none" }
            preset.advanced_settings = preset.advanced_settings or {}
            preset.advanced_settings.pollution = { enabled = false }
        end
    end

    presets["pacifist-default"] = {
        order = "a",
        basic_settings = {
            autoplace_controls = { ["enemy-base"] = { size = "none" } }
        },
        advanced_settings = {
            pollution = { enabled = false }
        }
    }
    presets.default.order = "aa"
end

function PacifistMod.remove_pollution_emission()
    -- Make all buildings generate no pollution to remove it from the
    -- tooltips as pollution has no effect with Pacifist enabled.
    for _, list in pairs(data.raw) do
        for _, entity in pairs(list) do
            local energy_source = entity.energy_source or entity.burner
            if energy_source then
                energy_source.emissions_per_minute = nil
            end
        end
    end

    for _, module in pairs(data.raw.module) do
        module.effect.pollution = nil
    end
end

function PacifistMod.relabel_item_groups()
    data.raw["item-group"].combat.icon = "__Pacifist__/graphics/item-group/equipment.png"
    data.raw["item-group"].enemies.icon = "__Pacifist__/graphics/item-group/units.png"
end

function PacifistMod.mod_preprocessing()
    if mods["ScienceCostTweakerM"] then
        local function is_waste_processing_recipe(effect)
            return effect.type == "unlock-recipe" and string.starts_with(effect.recipe, "sct-waste-processing")
        end
        local military_science_pack_tech = data.raw.technology["sct-military-science-pack"]
        array.remove_in_place(military_science_pack_tech.effects, is_waste_processing_recipe)
    end

    if mods["SeaBlock"] then
        local military_tech = data.raw.technology["military"]
        if military_tech then

            -- create a clone of the military tech just for the repair pack with appropriate name and icon
            local repair_pack_tech = table.deepcopy(military_tech)
            repair_pack_tech.name = "pacifist-repair-pack"
            repair_pack_tech.localised_name = { "item-name.repair-pack" }
            if mods["boblogistics"] and not mods["reskins-bobs"] then
                repair_pack_tech.icon = "__boblogistics__/graphics/icons/technology/repair-pack.png"
                repair_pack_tech.icon_size = 32
                repair_pack_tech.icon_mipmaps = 1
            else
                repair_pack_tech.icon = "__base__/graphics/icons/repair-pack.png"
                repair_pack_tech.icon_size = 64
                repair_pack_tech.icon_mipmaps = 4
            end
            data:extend({ repair_pack_tech })

            -- remove the recipe unlock from military tech. Pacifist's general processing will remove it later
            local function is_repair_pack_unlock(effect)
                return effect.type == "unlock-recipe" and effect.recipe == "repair-pack"
            end
            array.remove_in_place(military_tech.effects, is_repair_pack_unlock)

            -- repair pack 2 should have repair pack as prerequisite
            local repair_pack_2_tech = data.raw.technology["bob-repair-pack-2"]
            if repair_pack_2_tech then
                array.append(repair_pack_2_tech.prerequisites, { "pacifist-repair-pack" })
            end
        end
    end
end

function PacifistMod.mod_postprocessing()
    if mods["stargate"] then
        data.raw["land-mine"]["stargate-sensor"].minable = nil
    end
    if mods["Krastorio2"] then
        data.raw["tile"]["kr-creep"].minable = nil
        local biotech = data.raw.technology["kr-bio-processing"]
        if biotech then
            biotech.icon = "__Pacifist__/graphics/technology/kr-fertilizers.png"
        end
    end
    if mods["exotic-industries"] then
        -- In Exotic Industries, alien flowers are supposed to be killed. We make them minable instead.
        -- This is necessary to get the necessary alien seeds to kickstart the alien resin production.
        for name, entity in pairs(data.raw["simple-entity"]) do
            if string.starts_with(name, "ei_alien-flowers") and entity.loot then
                entity.minable = {
                    mining_time = 1,
                    results = {}
                }
                for _, loot_item in pairs(entity.loot) do
                    local mining_product = {
                        name = loot_item.item,
                        probability = loot_item.probability,
                        amount_min = loot_item.count_min or 1,
                        amount_max = loot_item.count_max or 1
                    }
                    table.insert(entity.minable.results, mining_product)
                end
                entity.loot = nil
            end
        end

        -- When alien flowers are killed or mined, guardians with blood explosions may get spawned.
        -- While we destroy them immediately in control.lua, we can not destroy the immediate particle effects
        -- Therefore we remove the effects from the prototype here
        data.raw.explosion["blood-explosion-huge"].created_effect = nil
    end
    if mods["Power Armor MK3"] then
        local heavy_vest_technology = data.raw.technology["heavy-armor"]
        if heavy_vest_technology then
            heavy_vest_technology.localised_name = { "technology-name.pamk3-heavy-vest" }
            heavy_vest_technology.localised_description = { "technology-description.pamk3-heavy-vest" }
        end
    end
end
