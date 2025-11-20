local wfc = require("init")
-- local utils = require("examples.utils")

---@param model WFCModel
local function log_model(model)
    local printf = function(fmt, ...)
        io.write(string.format(fmt, ...))
    end
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

---@param list string[]
---@return integer[]
local function bytes(list)
    for i = 1, #list do
        ---@cast list integer[]
        list[i] = string.byte(list[i])
    end
    return list
end

---@param list integer[]
---@return string[]
local function chars(list)
    for i = 1, #list do
        local char = string.char(list[i])
        ---@cast list string[]
        list[i] = char
    end
    return list
end


---@type WFCTileset
local rooms_data = {
    tiles = {
        {
            bytes({
                '#','.','.',
                '#','.','.',
                '#','#','#',
            }),
            name = "bend",
            symmetry = "L",
            weight = 0.5,
        },
        {
            bytes({
                '.','.','#',
                '.','.','.',
                '.','.','.',
            }),
            name = "corner",
            symmetry = "L",
            weight = 0.5,
        },
        {
            bytes({
                '.','#','.',
                '.','#','.',
                '.','#','.',
            }),
            name = "corridor",
            symmetry = "I",
            weight = 1.0,
        },
        {
            bytes({
                '#','#','#',
                '.','#','.',
                '.','#','.',
            }),
            name = "door",
            symmetry = "T",
            weight = 0.5,
        },
        {
            bytes({
                '#','#','#',
                '#','#','#',
                '#','#','#',
            }),
            name = "empty",
            symmetry = "X",
        },
        {
            bytes({
                '#','#','#',
                '#','#','#',
                '.','.','.',
            }),
            name = "side",
            symmetry = "T",
            weight = 2.0,
        },
        {
            bytes({
                '.','.','.',
                '#','#','#',
                '.','#','.',
            }),
            name = "t",
            symmetry = "T",
            weight = 0.5,
        },
        {
            bytes({
                '#','.','#',
                '#','.','.',
                '#','#','#',
            }),
            name = "turn",
            symmetry = "L",
            weight = 0.25,
        },
        {
            bytes({
                '.','.','.',
                '.','.','.',
                '.','.','.',
            }),
            name = "wall",
            symmetry = "X",
        },
        size = 3,
    },
    ---@type WFCTileNeighbor[]
    neighbors = {
        { left={"corner", 2}, right={"corner"} },
        { left={"corner", 3}, right={"corner"} },
        { left={"corner"}, right={"door"} },
        { left={"corner"}, right={"side", 3} },
        { left={"corner", 2}, right={"side", 2} },
        { left={"corner", 2}, right={"t", 2} },
        { left={"corner", 2}, right={"turn"} },
        { left={"corner", 3}, right={"turn"} },
        { left={"wall"}, right={"corner"} },
        { left={"corridor", 2}, right={"corridor", 2} },
        { left={"corridor", 2}, right={"door", 4} },
        { left={"corridor"}, right={"side", 2} },
        { left={"corridor", 2}, right={"t"} },
        { left={"corridor", 2}, right={"t", 4} },
        { left={"corridor", 2}, right={"turn", 2} },
        { left={"corridor"}, right={"wall"} },
        { left={"door", 2}, right={"door", 4} },
        { left={"door", 4}, right={"empty"} },
        { left={"door"}, right={"side", 3} },
        { left={"door", 2}, right={"t"} },
        { left={"door", 2}, right={"t", 4} },
        { left={"door", 2}, right={"turn", 2} },
        { left={"empty"}, right={"empty"} },
        { left={"empty"}, right={"side", 4} },
        { left={"side"}, right={"side"} },
        { left={"side", 4}, right={"side", 2} },
        { left={"side", 4}, right={"t", 2} },
        { left={"side", 4}, right={"turn"} },
        { left={"side", 4}, right={"wall"} },
        { left={"t"}, right={"t", 3} },
        { left={"t"}, right={"turn", 2} },
        { left={"t", 4}, right={"wall"} },
        { left={"turn"}, right={"turn", 3} },
        { left={"turn", 2}, right={"wall"} },
        { left={"wall"}, right={"wall"} },
        { left={"bend"}, right={"bend", 2} },
        { left={"corner"}, right={"bend", 3} },
        { left={"door"}, right={"bend", 3} },
        { left={"empty"}, right={"bend"} },
        { left={"side"}, right={"bend", 2} },
    }
}

---@type WFCBitmap<integer>
local flowers_data = bytes({
    ".",".",".",".",".",".",".",".",".",".",".",".",".",".",".",
    ".",".",".",".",".",".",".",".",".",".",".",".",".",".",".",
    ".",".",".",".",".","*",".",".",".",".",".",".",".","*",".",
    ".",".",".",".","*","#","*",".",".",".",".",".","*","#","*",
    ".",".",".",".",".","*",".",".",".",".",".",".",".","*",".",
    ".",".",".",".",".","#",".",".",".",".",".",".",".","#",".",
    ".",".",".",".",".","#","#",".",".",".",".",".","#","#",".",
    ".","*",".",".",".",".","#","#",".",".",".","#","#",".",".",
    "*","#","*",".",".",".",".","#",".",".",".","#",".",".",".",
    ".","*",".",".",".",".","#","#",".",".",".","#","#",".",".",
    ".","#",".",".",".",".","#",".",".","*",".",".","#","#",".",
    ".","#","#",".",".","#","#",".","*","#","*",".",".","#",".",
    ".",".","#",".","#","#",".",".",".","*",".",".",".","#",".",
    ".",".","#","#","#",".",".",".",".","#",".",".","#","#",".",
    ".",".",".","#",".",".",".",".",".","#",".","#","#",".",".",
    ".",".",".","#","#",".",".",".",".","#","#","#",".",".",".",
    ".",".",".",".","#","#",".",".",".",".","#",".",".",".",".",
    ".",".",".",".",".","#","#",".",".","#","#",".",".",".",".",
    ".",".",".",".",".",".","#",".","#","#",".",".",".",".",".",
    ".",".",".",".",".",".","#","#","#",".",".",".",".",".",".",
    ".",".",".",".",".",".",".","#",".",".",".",".",".",".",".",
    ".",".",".",".",".",".",".","#",".",".",".",".",".",".",".",
    "=","=","=","=","=","=","=","#","=","=","=","=","=","=","=",
    "=","=","=","=","=","=","=","=","=","=","=","=","=","=","=",
    width = 15, height = 24,
})

local outputs = {}
local flowers = wfc.overlapping(flowers_data, {
    name = "Flowers",
    N = 3,
    ground = true,
    periodic = true,
    symmetry = 2,
})
log_model(flowers)
table.insert(outputs, flowers:generate())

local rooms = wfc.simpletiled(rooms_data, {
    name = "Rooms",
    size = 30,
})
log_model(rooms)
table.insert(outputs, rooms:generate())

print("Outputs Len:", #outputs)
for i = 1, #outputs do
    for j = 1, #outputs[i] do
        io.write("{\n")
        for y = 0, outputs[i][j].height - 1 do
            io.write("    ")
            for x = 0, outputs[i][j].width - 1 do
                local index = x + y * outputs[i][j].width + 1
                io.write(string.format("%s ", string.char(outputs[i][j][index])))
            end
            io.write("\n")
        end
        io.write("}\n")
    end
end
