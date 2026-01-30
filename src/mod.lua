local function parse_csv(str)
    local data = {}
    for line in str:gmatch("[^\r\n]+") do
        -- Assuming standard CSV format: ID,Target
        local s_id, target = line:match("^(0x%x+),(.*)$")
        if s_id and target then
            -- Handle optional quotes if target has commas
            if target:sub(1,1) == '"' and target:sub(-1,-1) == '"' then
                target = target:sub(2, -2):gsub('""', '"')
            end
            
            -- Unescape newlines (restore \n escaped by extract_loca.rs)
            target = target:gsub("\\n", "\n")
            
            local id = tonumber(s_id)
            if id then
                data[id] = target
            end
        end
    end
    return data
end

-- Convert filename language code to enum format
-- e.g., "ko_kr" -> "Ko_Kr", "en_us" -> "En_Us"
local function normalize_lang_code(lang_str)
    local parts = {}
    for part in lang_str:gmatch("[^_]+") do
        table.insert(parts, part:sub(1,1):upper() .. part:sub(2):lower())
    end
    return table.concat(parts, "_")
end

local function apply_translation()
    -- Search for translation CSV file matching pattern: {lang}.csv
    local data_dir = "data"
    local translation_file = nil
    local target_lang = nil
    
    if io.list_files then
        local files = io.list_files(data_dir) or {}
        for _, file in ipairs(files) do
            -- Match pattern: (optional path/)xx_xx.csv
            local lang_code = file:match("([a-z][a-z]_[a-z][a-z])%.csv$")
            
            if lang_code then
                translation_file = file
                target_lang = normalize_lang_code(lang_code)
                break  -- Use the first valid file found
            end
        end
    end
    
    if not translation_file then
        warn("No translation file found in " .. data_dir)
        warn("Expected filename pattern: {lang}.csv (e.g., ko_kr.csv, en_us.csv)")
        return
    end

    -- Find LocaTagCollectionResource
    local resources = game.assets.get_resources_by_type("keen::LocaTagCollectionResource")
    if #resources == 0 then
        warn("LocaTagCollectionResource not found.")
        return
    end
    
    local loca_res = resources[1]
    local loca_entry = loca_res.data
    
    -- Process the translation file
    print("Processing: " .. translation_file .. " for language: " .. target_lang)
    
    local content_str = io.read_to_string(translation_file)
    if not content_str then
        warn("Failed to read: " .. translation_file)
        return
    end
    
    local translations = parse_csv(content_str)
    print("Loaded translations from " .. translation_file)

    -- Find matching language entry
    local lang_entry = nil
    for _, lang in ipairs(loca_entry.languages) do
        if tostring(lang.language) == target_lang then
            lang_entry = lang
            break
        end
    end

    if not lang_entry then
        warn("Language entry not found: " .. target_lang)
        return
    end

    -- Load original content
    local old_guid_str = game.guid.from_content_hash(lang_entry.dataHash)
    local old_content = game.assets.get_content(old_guid_str)
    if not old_content then
        warn("Original content not found: " .. old_guid_str)
        return
    end

    local buf = old_content:read_data()
    local data_obj = buf:read_resource("keen::LocaTagCollectionResourceData")
    
    -- Patch
    for _, tag in ipairs(data_obj.tags) do
        local new_text = translations[tag.id.value]
        if new_text then
            tag.text = new_text
        end
    end

    -- Create new content
    local new_buf = buffer.create()
    new_buf:write_resource("keen::LocaTagCollectionResourceData", data_obj)
    local new_content = game.assets.create_content(new_buf)
    
    if new_content and new_content.guid then
        -- Use official API to convert GUID to ContentHash
        local new_hash = game.guid.to_content_hash(new_content.guid)
        
        if new_hash then
            local dh = lang_entry.dataHash
            dh.size = new_hash.size
            dh.hash0 = new_hash.hash0
            dh.hash1 = new_hash.hash1
            dh.hash2 = new_hash.hash2
            
            loca_res.data = loca_entry 
            print(target_lang .. " updated successfully. size=" .. new_hash.size)
        else
            warn("Failed to convert GUID to ContentHash for " .. target_lang)
        end
    else
        warn("Failed to create new content for " .. target_lang)
    end
end

if loader.features.patch then
    apply_translation()
else
    warn("Patch feature not enabled.")
end
