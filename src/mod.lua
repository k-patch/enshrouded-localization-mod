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
    -- Search for translation CSV files matching pattern: {lang}.csv
    local data_dir = "data"
    local translation_files = {}
    
    if io.list_files then
        local files = io.list_files(data_dir) or {}
        for _, file in ipairs(files) do
            -- Check if file ends with .csv
            if file:sub(-4) == ".csv" then
                -- Get filename without extension
                local lang_code = file:sub(1, -5)
                
                -- Validate format: exactly xx_xx (5 characters, underscore at position 3)
                if #lang_code == 5 and lang_code:sub(3, 3) == "_" then
                    table.insert(translation_files, {
                        path = data_dir .. "/" .. file,
                        lang = normalize_lang_code(lang_code)
                    })
                end
            end
        end
    end
    
    -- Fallback: try standard paths
    if #translation_files == 0 then
        local candidates = {
            {path = "data/ko_kr.csv", lang = "Ko_Kr"},
            {path = "data/en_us.csv", lang = "En_Us"},
        }
        for _, candidate in ipairs(candidates) do
            if io.exists(candidate.path) then
                table.insert(translation_files, candidate)
            end
        end
    end
    
    if #translation_files == 0 then
        warn("No translation files found in " .. data_dir)
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
    
    -- Process each translation file
    for _, trans_file in ipairs(translation_files) do
        print("Processing: " .. trans_file.path .. " for language: " .. trans_file.lang)
        
        local content_str = io.read_to_string(trans_file.path)
        if not content_str then
            warn("Failed to read: " .. trans_file.path)
            goto continue
        end
        
        local translations = parse_csv(content_str)
        local count = 0
        for _ in pairs(translations) do count = count + 1 end
        print("Loaded " .. count .. " translations.")

        -- Find matching language entry
        local lang_entry = nil
        for _, lang in ipairs(loca_entry.languages) do
            if tostring(lang.language) == trans_file.lang then
                lang_entry = lang
                break
            end
        end

        if not lang_entry then
            warn("Language entry not found: " .. trans_file.lang)
            goto continue
        end

        -- Load original content
        local old_guid_str = game.guid.from_content_hash(lang_entry.dataHash)
        local old_content = game.assets.get_content(old_guid_str)
        if not old_content then
            warn("Original content not found: " .. old_guid_str)
            goto continue
        end

        local buf = old_content:read_data()
        local data_obj = buf:read_resource("keen::LocaTagCollectionResourceData")
        
        -- Patch
        local patched_count = 0
        for _, tag in ipairs(data_obj.tags) do
            local new_text = translations[tag.id.value]
            if new_text then
                tag.text = new_text
                patched_count = patched_count + 1
            end
        end
        
        print("Patched " .. patched_count .. " strings for " .. trans_file.lang)

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
                print(trans_file.lang .. " updated successfully. size=" .. new_hash.size)
            else
                warn("Failed to convert GUID to ContentHash for " .. trans_file.lang)
            end
        else
            warn("Failed to create new content for " .. trans_file.lang)
        end
        
        ::continue::
    end
end

if loader.features.patch then
    apply_translation()
else
    warn("Patch feature not enabled.")
end
