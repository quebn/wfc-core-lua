local utils = {}

---@param model WFCModel
function utils.log_model(model)
    local printf = utils.printf
    printf("WFC Model '%s' = %s: \n", model.name, model.category)
    printf("    Width:\t  %s\n", model.width)
    printf("    Height:\t  %s\n", model.height)
    printf("    Tile Count:   %s\n", model.tile_count)
    printf("    Pattern Size: %s\n", model.pattern_size)
    printf("    Ground:\t  %s\n", model.ground)
    printf("    Periodic:\t  %s\n", model.periodic)
    printf("    Heuristic:\t  %s\n", model.heuristic)
    printf("    Starting Entropy: %s\n", model.starting_entropy)
end


---@param fmt string
---@param ... any
function utils.printf(fmt, ...)
    if type(fmt) ~= "string" then
        fmt = string.format("%s", fmt)
    end
    local msg = string.format(fmt, ...)
    io.write(msg)
end

---@param bitmap WFCBitmap<integer>|integer[]
---@param value? fun(a:integer):string
---@param size? integer
function utils.print_bitmap(bitmap, value, size)
    value = value or function(a)
        return string.char(a)
    end
    utils.printf("{\n")
    for y = 0, (size or bitmap.height) - 1 do
        utils.printf("    ")
        for x = 0, (size or bitmap.width) - 1 do
            local index = x + y * (size or bitmap.width) + 1
            utils.printf("%s ", value(bitmap[index]))
        end
        io.write("\n")
    end
    utils.printf("}\n")
end

---@param list string[]
---@return integer[]
function utils.bytes(list)
    for i = 1, #list do
        ---@cast list integer[]
        list[i] = string.byte(list[i])
    end
    return list
end

---@param list integer[]
---@return string[]
function utils.chars(list)
    for i = 1, #list do
        local char = string.char(list[i])
        ---@cast list string[]
        list[i] = char
    end
    return list
end

---@param bitmap WFCBitmap<string>
---@return WFCBitmap<integer>
function utils.bytemap(bitmap)
    ---@type WFCBitmap<integer>
    local bm = {
        width = bitmap.width,
        height = bitmap.height,
    }
    for i = 1, #bitmap do
        bm[i] = string.byte(bitmap[i])
    end
    return bm
end

---@param bitmap WFCBitmap<integer>
---@return WFCBitmap<string>
function utils.charmap(bitmap)
    ---@type WFCBitmap<string>
    local cm = {
        width = bitmap.width,
        height = bitmap.height,
    }
    for i = 1, #bitmap do
        cm[i] = string.char(bitmap[i])
    end
    return cm
end


---@param array any[]
---@param type string
function utils.print_array(array, type)
    utils.printf("[ ")
    for i = 1, #array do
        local value = array[i]
        if type == "byte" then
            utils.printf("%d ", string.byte(value))
        elseif type == "char" then
            utils.printf("%s ", string.char(value))
        elseif type == "number" then
            utils.printf("%d ", value)
        else
            utils.printf("%s ", value)
        end
    end
    utils.printf(" ]\n")
end

---@param index integer
---@param max? integer
function utils.assert_index(index, max)
    assert(index ~= 0, string.format("Assert: %d should not be equal to 0 of min value", index))
    if max == nil then
        return
    end
    local out_of_bound = max + 1
    assert(index ~= out_of_bound, string.format("Assert: %d should be equal or less than the max value of %d", index, max))
end

---@param value number
---@param name? string
function utils.assert_number(value, name)
    if name == nil then
        name = "value"
    end
    assert(value == value, name.." is NaN: ")
    assert(value ~= math.huge, name.." is +inf")
    assert(value ~= -math.huge, name.." is -inf")
end

return utils

