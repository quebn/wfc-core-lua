---@class WFC
---@field input_filepath? string
---@field output_dirpath? string
local wfc = {}

local DX = { -1, 0, 1, 0 }
local DY = { 0, 1, 0, -1 }
local OPPOSITE = { 2, 3, 0, 1 }

---@alias WFCPair<T> { [1]:T, [2]:T }
---@alias WFCBitmap<T> { [integer]:T, width: integer, height: integer }
---@alias WFCHeuristic "unassigned" | "entropy" | "scanline" | "mrv"
---@alias WFCCategory "simpletiled" | "overlapping"

---@alias WFCTileSymmetry "X"|"T"|"I"|"L"|"F"|"\\"
---@alias WFCTileKind { [1]:string, [2]:integer }

---@class WFCTileNeighbor
---@field left  { [1]: string, [2]:integer }
---@field right { [1]: string, [2]:integer }

---@class WFCOverlappingOpt : WFCOpt
---@field periodic_input? boolean
---@field symmetry? integer
---@field N? integer tile size

---@class WFCSimpleTiledOpt : WFCOpt
---@field periodic_output? boolean
---@field black_background? boolean
---@field subset string[]
---@field unique? boolean

---@class WFCTile
---@field [integer] number[]
---@field name string
---@field symmetry WFCTileSymmetry
---@field weight? number

---@class WFCTileset
---@field tiles { [integer]:WFCTile, size:integer }
---@field neighbors WFCTileNeighbor[]
---@field subsets? string|string[]

---@class WFCOpt
---@field name string
---@field size? integer
---@field width? integer
---@field height? integer
---@field ground? boolean
---@field periodic? boolean
---@field screenshots? integer
---@field heuristic? WFCHeuristic
---@field limit? integer
---@field seed? integer

---@class WFCSimpleTiled : WFCModel
---@field tiles integer[][]
---@field tile_names string[]
---@field tile_size integer
---@field black_background boolean
---@field unique boolean

---@class WFCOverlapping : WFCModel
---@field patterns integer[][]
---@field values number[]

---@class WFCModel
---@field name string
---@field category WFCCategory
---@field wave boolean[][]
---@field propagator integer[][][]
---@field compatible integer[][][]
---@field observed { [integer]:integer, count:integer }
---@field width integer
---@field height integer
---@field tile_count integer tile count
---@field pattern_size integer
---@field ground boolean
---@field weights number[]
---@field stack WFCPair<integer>[]
---@field stack_count integer
---@field distribution number[]
---@field weight_log_weights number[]
---@field sum_of_weights number
---@field sum_of_weight_log_weights number
---@field sums_of_ones number[]
---@field sums_of_weights number[]
---@field sums_of_weight_log_weights number[]
---@field periodic boolean
---@field heuristic WFCHeuristic
---@field starting_entropy number
---@field entropies number[]
---@field screenshots integer
---@field limit integer
local Model = {}
Model.__index = Model

---@param x integer
---@param y integer
---@param size integer
---@return integer
local function index0(x, y, size)
    return x + y * size + 1
end

---@param x integer
---@param y integer
---@param size integer
---@return integer
local function index1(x, y, size)
    return index0(x - 1, y - 1, size)
end

---@param f fun(x:integer, y:integer)
---@param size integer
---@return number[]
local function pattern(f, size)
    local result = {}

    for y = 0, size - 1 do
        for x = 0, size - 1 do
            local index = index0(x, y, size)
            result[index] = f(x, y)
        end
    end

    return result
end

---@param p number[]
---@param size integer
---@return number[]
local function rotate(p, size)
    local f = function(x, y)
        local index = index0(size - 1 - y, x, size)
        return p[index]
    end

    return pattern(f, size)
end

---@param p number[]
---@param size integer
---@return number[]
local function reflect(p, size)
    local f = function(x, y)
        local index = index0(size - 1 - x, y, size)
        return p[index]
    end

    return pattern(f, size)
end

---@param p number[]
---@param c number
---@return number
local function hash(p, c)
    local result, power = 0.0, 1.0

    for i = 0, #p - 1 do
        result = result + p[#p - i] * power
        power = power * c
    end

    return result
end

---@generic T
---@param list T[]
---@param v T
local function list_contains(list, v)
    for i = 1, #list do
        if v == list[i] then
            return true
        end
    end

    return false
end

---@param pattern1 number[]
---@param pattern2 number[]
---@param dx number
---@param dy number
---@param n number
---@return boolean
local function agrees(pattern1, pattern2, dx, dy, n)
    local xmin = dx < 0 and 0 or dx
    local xmax = dx < 0 and dx + n or n
    local ymin = dy < 0 and 0 or dy
    local ymax = dy < 0 and dy + n or n

    for y = ymin, ymax - 1 do
        for x = xmin, xmax - 1 do
            local i1 = index0(x, n, y)
            local i2 = index0(x - dx, n, y - dy)
            if pattern1[i1] ~= pattern2[i2] then
                return false
            end
        end
    end

    return true
end

---@param x integer
---@param y integer
---@param w integer
---@param h integer
---@return boolean
local function in_bounds(x, y, w, h, mx, my)
    return x >= 0 and y >= 0 and w <= mx and h <= my
end

---@param weights number[]
---@return integer
local function weighted_random(weights)
    local sum = 0
    for i = 1, #weights do
        sum = sum + weights[i]
    end
    local threshold = math.random() * sum
    local partial_sum = 0
    for i = 1, #weights do
        partial_sum = partial_sum + weights[i]
        if partial_sum >= threshold then
            return i
        end
    end
    return 1
end

---@param opt WFCOpt
---@return WFCModel
local function create_model(opt)
    ---@type WFCModel
    local model = {
        name = opt.name,
        width = opt.width or opt.size or 24,
        height = opt.height or opt.size or 24,
        ground = opt.ground or false,
        periodic = opt.periodic or false,
        heuristic = opt.heuristic or "entropy",
        size = opt.size,
        weights = {},
        propagator = {},
        screenshots = opt.screenshots or 1,
        limit = opt.limit or -1,
    }

    return setmetatable(model, Model)
end

---@param bitmap WFCBitmap<number>
---@param opt WFCOverlappingOpt
---@return WFCOverlapping
function wfc.overlapping(bitmap, opt)
    opt.size = opt.size or 48
    opt.periodic_input = opt.periodic_input or true
    opt.symmetry = opt.symmetry or 8
    opt.ground =  opt.ground or false

    local model = create_model(opt)
    ---@cast model WFCOverlapping
    model.category = "overlapping"
    model.pattern_size = opt.N or 3
    model.patterns = {}
    model.values = {}

    local bitmap_length = bitmap.width * bitmap.height
    local sample = {}
    local sx = bitmap.width
    local sy = bitmap.height
    local n = model.pattern_size

    local values = model.values

    for i = 1, bitmap_length do
        local byte = bitmap[i]
        local k = 0
        while k < #model.values do
            if values[k + 1] == byte then
                break
            end
            k = k + 1
        end
        if k == #values then
            table.insert(values, byte)
        end
        sample[i] = k + 1
    end

    local patterns = model.patterns
    local pattern_indices = {}
    local weights = model.weights

    local xmax = opt.periodic_input and sx or sx - n + 1
    local ymax = opt.periodic_input and sy or sy - n + 1
    for y = 0, ymax - 1 do
        for x = 0, xmax - 1 do
            ---@type integer[][]
            local ps = {}
            local f = function(dx, dy)
                local index = index0((x + dx) % sx, (y + dy) % sy, sx)
                return sample[index]
            end

            ps[1] = pattern(f, n)
            ps[2] = reflect(ps[1], n)
            ps[3] = rotate(ps[1], n)
            ps[4] = reflect(ps[3], n)
            ps[5] = rotate(ps[3], n)
            ps[6] = reflect(ps[5], n)
            ps[7] = rotate(ps[5], n)
            ps[8] = reflect(ps[7], n)

            for k = 1, opt.symmetry do
                local p = ps[k]
                local h = hash(p, #values)
                if pattern_indices[h] then
                    local index = pattern_indices[h]
                    weights[index] = weights[index] + 1
                else
                    table.insert(weights, 1)
                    pattern_indices[h] = #weights
                    table.insert(patterns, p)
                end
            end
        end
    end

    model.tile_count = #weights

    local propagator = model.propagator

    for d = 1, 4 do
        propagator[d] = {}
        for t1 = 1, model.tile_count do
            propagator[d][t1] = {}
            for t2 = 1, model.tile_count do
                if agrees(patterns[t1], patterns[t2], DX[d], DY[d], n) then
                    table.insert(propagator[d][t1], t2)
                end
            end
        end
    end

    return model
end

---@param tileset WFCTileset
---@param opt WFCSimpleTiledOpt
---@return WFCSimpleTiled
function wfc.simpletiled(tileset, opt)
    local model = create_model(opt)
    ---@cast model WFCSimpleTiled
    model.category = "simpletiled"
    model.pattern_size = 1

    model.black_background = opt.black_background or false
    model.unique = opt.unique or false
    model.tile_names = {}
    model.tiles = {}
    model.tile_size = tileset.tiles.size or math.sqrt(#tileset.tiles[1][1])


    local tiles = model.tiles
    local tile_names = model.tile_names
    local weights = model.weights
    local actions = {} ---@type integer[][]
    local first_occurence = {} ---@type table<string, integer>
    for i = 1, #tileset.tiles do
        local tile = tileset.tiles[i]

        if opt.subset ~= nil and not list_contains(opt.subset, tile.name) then
            goto next
        end

        local rotation, reflection
        local cardinality

        local symmetry = tile.symmetry
        if symmetry == "L" then
            cardinality = 4
            rotation = function(n)
                return (n + 1) % 4
            end
            reflection = function(n)
                if n % 2 == 0 then
                    return n + 1
                end
                return n - 1
            end
        elseif symmetry == "T" then
            cardinality = 4
            rotation = function(n)
                return (n + 1) % 4
            end
            reflection = function(n)
                if n % 2 == 0 then
                    return n
                end
                return 4 - n
            end
        elseif symmetry == "I" then
            cardinality = 2
            rotation = function(n)
                return 1 - n
            end
            reflection = function(n)
                return n
            end
        elseif symmetry == "X" then
            cardinality = 1
            rotation = function(n)
                return n
            end
            reflection = rotation
        elseif symmetry == "F" then
            cardinality = 8
            rotation = function(n)
                if n < 4 then
                    return (n + 1) % 4
                end
                return 4 + (n - 1) % 4
            end
            reflection = function(n)
                if n < 4 then
                    return n + 4
                end
                return n - 4
            end
        else
            cardinality = 2
            rotation = function(n)
                return 1 - n
            end
            reflection = function(n)
                return 1 - n
            end
        end


        model.tile_count = #actions
        first_occurence[tile.name] = model.tile_count + 1

        for t = 0, cardinality - 1 do
            local ps = {}

            ps[1] = t
            ps[2] = rotation(ps[1])
            ps[3] = rotation(ps[2])
            ps[4] = rotation(ps[3])
            ps[5] = reflection(ps[1])
            ps[6] = reflection(ps[2])
            ps[7] = reflection(ps[3])
            ps[8] = reflection(ps[4])

            for s = 1, 8 do
                ps[s] = ps[s] + model.tile_count + 1
            end
            table.insert(actions, ps)
        end
        if model.unique then
            for t = 1, cardinality do
                local bitmap = tile[t]
                table.insert(tiles, bitmap)
                table.insert(tile_names, tile.name.." "..t)
            end
        else
            local bitmap = tile[1]
            table.insert(tiles, bitmap)
            table.insert(tile_names, tile.name.." 1")

            for t = 2, cardinality do
                if t <= 4 then
                    table.insert(tiles, rotate(tiles[#tiles], model.tile_size))
                else
                    table.insert(tiles, reflect(tiles[#tiles], model.tile_size))
                end
                table.insert(tile_names, tile.name.." "..t)
            end

        end

        for _ = 1, cardinality do
            table.insert(weights, tile.weight or 1)
        end
        ::next::
    end

    model.tile_count = #actions

    local propagator = model.propagator
    ---@type boolean[][][]
    local dense_propagator = {}
    for d = 1, 4 do
        dense_propagator[d] = {}
        propagator[d] = {}
        for t = 1, model.tile_count do
            propagator[d][t] = {}
            dense_propagator[d][t] = {}
        end
    end
    for i = 1, #tileset.neighbors do
        local left = tileset.neighbors[i].left
        local right = tileset.neighbors[i].right

        if opt.subset ~= nil and (list_contains(opt.subset, left[1]) or list_contains(opt.subset, right[1])) then
            goto next
        end

        local L = actions[first_occurence[left[1]]][left[2] or 1]
        local D = actions[L][2]
        local R = actions[first_occurence[right[1]]][right[2] or 1]
        local U = actions[R][2]

        dense_propagator[1][R][L] = true
        dense_propagator[1][actions[R][7]][actions[L][7]] = true
        dense_propagator[1][actions[L][5]][actions[R][5]] = true
        dense_propagator[1][actions[L][3]][actions[R][3]] = true

        dense_propagator[2][U][D] = true
        dense_propagator[2][actions[D][7]][actions[U][7]] = true
        dense_propagator[2][actions[U][5]][actions[D][5]] = true
        dense_propagator[2][actions[D][3]][actions[U][3]] = true

        ::next::
    end

    for t2 = 1, model.tile_count do
        for t1 = 1, model.tile_count do
            dense_propagator[3][t2][t1] = dense_propagator[1][t1][t2]
            dense_propagator[4][t2][t1] = dense_propagator[2][t1][t2]
        end
    end

    ---@type integer[][][]
    local sparse_propagator = {}
    for d = 1, 4 do
        sparse_propagator[d] = {}
        for t = 1, model.tile_count do
            sparse_propagator[d][t] = {}
        end
    end

    for d = 1, 4 do
        for t1 = 1, model.tile_count do
            local sp = sparse_propagator[d][t1]
            local tp = dense_propagator[d][t1]

            for t2 = 1, model.tile_count do
                if tp[t2] then
                    table.insert(sp, t2)
                end
            end

            if #sp == 0 then
                print("ERROR: tile '"..tile_names[t1].."' has no neighbors in direction "..d)
            end

            local current = {}
            for i = 1, #sp do
                current[i] = sp[i]
            end
            propagator[d][t1] = current
        end
    end

    return model
end


---@param model WFCModel
local function init(model)
    model.wave = {}
    model.compatible = {}
    for i = 1, model.width * model.height do
        model.wave[i] = {}
        model.compatible[i] = {}
        for t = 1, model.tile_count do
            model.wave[i][t] = false
            model.compatible[i][t] = {}
            for d = 1, 4 do
                model.compatible[i][t][d] = 0
            end
        end
    end
    model.distribution = {}
    model.observed = {}

    model.weight_log_weights = {}
    model.sum_of_weights = 0
    model.sum_of_weight_log_weights = 0

    for t = 1, model.tile_count do
        model.weight_log_weights[t] = model.weights[t] * math.log(model.weights[t])
        model.sum_of_weights = model.sum_of_weights + model.weights[t]
        model.sum_of_weight_log_weights = model.sum_of_weight_log_weights + model.weight_log_weights[t]
    end

    model.starting_entropy = math.log(model.sum_of_weights) - model.sum_of_weight_log_weights / model.sum_of_weights
    model.sums_of_ones = {}
    model.sums_of_weights = {}
    model.sums_of_weight_log_weights = {}
    model.entropies = {}

    model.stack = {}
    model.stack_count = 0
end

---@param i integer
---@param t integer
local function ban(model, i, t)
    model.wave[i][t] = false
    local comp = model.compatible[i][t]
    for d = 1, 4 do
        comp[d] = 0
    end

    model.stack_count = model.stack_count + 1
    model.stack[model.stack_count] = { i, t }

    model.sums_of_ones[i] = model.sums_of_ones[i] - 1
    model.sums_of_weights[i] = model.sums_of_weights[i] - model.weights[t]
    model.sums_of_weight_log_weights[i] = model.sums_of_weight_log_weights[i] - model.weight_log_weights[t]

    local sum = model.sums_of_weights[i]
    model.entropies[i] = math.log(sum) - model.sums_of_weight_log_weights[i] / sum
end

---@param model WFCModel
---@return boolean success
local function propagate(model)
    local n = model.pattern_size
    local w, h = model.width, model.height

    while model.stack_count > 0 do
        local stack = model.stack[model.stack_count]
        local i1, t1 = stack[1], stack[2]
        model.stack_count = model.stack_count - 1

        local x1 = (i1 - 1) % w
        local y1 = math.floor((i1 - 1) / w)

        for d = 1, 4 do
            local x2 = x1 + DX[d]
            local y2 = y1 + DY[d]
            if not model.periodic and not in_bounds(x2, y2, x2+n, y2+n, w, h) then
                goto next
            end
            if x2 < 0 then
                x2 = x2 + w
            elseif x2 >= w then
                x2 = x2 - w
            end

            if y2 < 0 then
                y2 = y2 + h
            elseif y2 >= h then
                y2 = y2 - h
            end

            local i2 = index0(x2, y2, w)
            local p = model.propagator[d][t1]
            local compat = model.compatible[i2]

            for l = 1, #p do
                local t2 = p[l]
                local comp = compat[t2]

                comp[d] = comp[d] - 1
                if comp[d] == 0 then
                    ban(model, i2, t2)
                end
            end
            ::next::
        end
    end
    return model.sums_of_ones[1] > 0
end

---@param model WFCModel
local function clear(model)
    for i = 1, #model.wave do
        for t = 1, model.tile_count do
            model.wave[i][t] = true
            for d = 1, 4 do
                local di = OPPOSITE[d] + 1
                model.compatible[i][t][d] = #model.propagator[di][t]
            end
        end

        model.sums_of_ones[i] = #model.weights
        model.sums_of_weights[i] = model.sum_of_weights
        model.sums_of_weight_log_weights[i] = model.sum_of_weight_log_weights
        model.entropies[i] = model.starting_entropy
        model.observed[i] = 0
    end

    model.observed.count = 0
    if model.ground then
        for x = 1, model.width do
            for t = 1, model.tile_count - 1 do
                local index = index1(x, model.height, model.width)
                ban(model, index, t)
            end
            for y = 1, model.height - 1 do
                local index = index1(x, y, model.width)
                ban(model, index, model.tile_count)
            end
        end
        propagate(model)
    end
end

---@param model WFCModel
---@return integer node_index
local function next_unobserved_node(model)
    local n = model.pattern_size
    local w, h = model.width, model.height
    if model.heuristic == "scanline" then
        for i = model.observed.count, #model.wave - 1 do
            local index = i + 1
            local x = i % w
            local y = math.floor(i / w)
            if not model.periodic and ((x + n > w) or (y + n > h)) then
                goto next
            end
            if model.sums_of_ones[index] > 1 then
                model.observed.count = i + 1
                return index
            end
            ::next::
        end
        return 0
    end
    local min = 1E+4
    local argmin = 0

    for i = 0, #model.wave - 1 do
        local index = i + 1
        local x = i % w
        local y = math.floor(i / w)
        if not model.periodic and ((x + n > w) or (y + n > h)) then
            goto next
        end
        local remaining_values = model.sums_of_ones[index]
        local entropy = model.heuristic == "entropy" and model.entropies[index] or remaining_values
        if remaining_values > 1 and entropy <= min then
            local noise = 1E-6 * math.random()
            if entropy + noise < min then
                min = entropy + noise
                argmin = index
            end
        end
        ::next::
    end
    return argmin
end

---@param model WFCModel
---@param index integer
local function observe(model, index)
    local wave = model.wave[index]

    for t = 1, model.tile_count do
        model.distribution[t] = wave[t] and model.weights[t] or 0
    end
    local r = weighted_random(model.distribution)

    for t = 1, model.tile_count do
        if wave[t] ~= (t == r) then
            ban(model, index, t)
        end
    end
end

---@param model WFCModel
---@param seed integer
---@param limit? integer
---@return boolean
function wfc.run(model, seed, limit)
    if not limit then
        limit = model.limit
    end
    if model.wave == nil or #model.wave == 0 then
        init(model)
    end
    clear(model)
    math.randomseed(seed)
    local l = 0
    while l < limit or limit < 0 do
        local node_index = next_unobserved_node(model)
        if node_index > 0 then
            observe(model, node_index)
            if not propagate(model) then
                return false
            end
        else
            for i = 1, #model.wave do
                for t = 1, model.tile_count do
                    if model.wave[i][t] then
                        model.observed[i] = t
                        break
                    end
                end
            end
            -- assert(false)
            return true
        end
        l = l + 1
    end
    return true
end

---@param model WFCSimpleTiled | WFCModel
---@return WFCBitmap<number>
local function simpletiled_output(model)
    local mx, my = model.width, model.width
    local ts, tc = model.tile_size, model.tile_count
    local tiles = model.tiles
    local output = {
        width  = mx * ts,
        height = my * ts,
    }
    if model.observed[1] > 0 then
        for x = 0, mx - 1 do
            for y = 0, my - 1 do
                local observed = model.observed[index0(x, y, mx)]
                local tile = tiles[observed]
                for dx = 0, ts - 1 do
                    for dy = 0, ts - 1 do
                        local value = tile[index0(dx, dy, ts)]
                        local index = index0(x * ts + dx, y * ts + dy, output.width)
                        output[index] = value
                    end
                end
            end
        end
        return output
    end
    -- NOTE: Untested
    for i = 0, #model.wave - 1 do
        local x ,y = i % mx, i / mx
        if model.black_background and model.sums_of_ones[i] == tc then
            for yt = 0, tc - 1 do
                for xt = 0, tc - 1 do
                    local index = index0(x * ts + xt, y * ts + yt, output.width)
                    output[index] = 0
                end
            end
        else
            local freq = {}
            local wave = model.wave[i]
            for yt = 0, ts - 1 do
                for xt = 0, ts - 1 do
                    local index = index0(xt, yt, ts)
                    for t = 1, tc do
                        if wave[t] then
                            local byte = tiles[t][index]
                            freq[byte] = (freq[byte] or 0) + 1

                        end
                    end
                    local best_value = nil
                    local best_count = -1

                    for value, count in pairs(freq) do
                        if count > best_count then
                            best_value = value
                            best_count = count
                        end
                    end
                    index = index0(x * ts + xt, y * ts + yt, output.width)
                    output[index] = best_value
                end
            end
        end
    end
    return output
end

---@param model WFCOverlapping|WFCModel
---@return WFCBitmap<number>
local function overlapping_output(model)
    local n = model.pattern_size
    local values = model.values
    local patterns = model.patterns
    ---@type WFCBitmap<number>
    local output = {
        width  = model.width,
        height = model.height,
    }
    local w, h = output.width, output.height
    if model.observed[1] > 0 then
        for y = 0, h - 1 do
            local dy = y < h - n + 1 and 0 or n - 1
            for x = 0, w - 1 do
                local dx = x < w - n + 1 and 0 or n - 1
                local oi = index0(x - dx, y - dy, w)
                local px = model.observed[oi]
                local py = index0(dx, dy, n)
                local bi = index0(x, y, w)
                output[bi] = values[patterns[px][py]]
            end
        end
        return output
    end
    local freq = {}
    for i = 0, #model.wave - 1 do
        local index = i + 1
        local x, y = i % w, math.floor(i / w)
        for dy = 0, n - 1 do
            for dx = 0, n - 1 do
                local di = index0(dx, dy, n)
                local sx = x - dx
                if sx < 0 then
                    sx = sx + w
                end

                local sy = y - dy
                if sy < 0 then
                    sy = sy + h
                end

                local s = sx + sy * w + 1
                if not model.periodic and not in_bounds(sx, sy, sx+n, sy+n, w, h) then
                    goto next
                end
                for t = 1, model.tile_count do
                    if model.wave[s][t] then
                        local p = patterns[t][di]
                        freq[p] = (freq[p] or 0) + 1
                    else
                    end
                end
                ::next::
            end
        end
        local highest = 1
        for j = 1, #freq do
            if freq[highest] < freq[j] then
                highest = j
            end
        end
        output[index] = values[highest]
    end
    return output
end

---@param screenshots? integer
---@param limit? integer
---@param seed? number
---@return WFCBitmap<number>[]
function Model:generate(screenshots, limit, seed)
    local outputs = {}
    screenshots = screenshots or self.screenshots
    limit = limit or self.limit
    for _ = 1, screenshots do
        for _ = 1, 10 do
            if wfc.run(self, seed or math.random(os.time()), limit) then
                table.insert(outputs, wfc.output(self))
                break
            else
                print("INFO: '"..self.name.."' Contradiction!")
            end
        end
    end
    return outputs
end

---@param model WFCModel
---@return WFCBitmap<number>
function wfc.output(model)
    if model.category == "overlapping" then
        return overlapping_output(model)
    end
    return simpletiled_output(model)
end

return wfc
