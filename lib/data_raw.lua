local data_raw = {}
data_raw.removed = {}

data_raw.hide = function(type, name)
    local entry = data.raw[type][name]
    if not entry then
        return
    end
    entry.flags = entry.flags or {}
    table.insert(entry.flags, "hidden")
end

data_raw.remove = function(type, name)
    if name then
        if data.raw[type][name] then
            data.raw[type][name] = nil

            local removed_type = data_raw.removed[type]
            if not removed_type then
                removed_type = {}
                data_raw.removed[type] = removed_type
            end
            removed_type[name] = true
        end
    else
        data.raw[type] = {}
    end
end

data_raw.hide_all = function(type, name_list)
    for _, name in pairs(name_list) do
        data_raw.hide(type, name)
    end
end

data_raw.remove_all = function(type, name_list)
    for _, name in pairs(name_list) do
        data_raw.remove(type, name)
    end
end

data_raw.get_all_names_for = function(type_list)
    local names = {}
    for _, type in pairs(type_list) do
        for _, entity in pairs(data.raw[type]) do
            table.insert(names, entity.name)
        end
    end
    return names
end

return data_raw
