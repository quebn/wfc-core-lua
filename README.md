# Core Wave Function Collapse in Lua

Core implementation of the [Wave Function Collapse](https://github.com/mxgmn/WaveFunctionCollapse) algorithm by mxgmn as a module in Lua. the aim of this module is to only implement the core algorithm without the parsing of a file as an input making this perfect for a project that only needs the bitmap data to do stuff.

> [!WARNING]
>  some cases are untested, as I dont need them for my current use case.

## Usage
1. Clone the repo.
```sh
$ git clone https://github.com/quebn/wfc-core-lua.git
```

2.  Use the module
```lua
local wfc_core = require("wfc-core-lua")

-- bitmap is structures as { [integer]:integer, width:integer, height:integer } see `init.lua` for the luadoc structure definitions or can be provided by your lsp for lua.
local foo = wfc_core.overlapping(bitmap, {
    name = "Foo",
    N = 3,
    ground = true,
    periodic = true,
    symmetry = 2,
})
-- generate function ouputs a list of bitmap with 1 item by default
local outputs = foo:generate()
-- do whatever with the generated outputs
```
see `examples.lua` for more usage examples

## Acknowledgments

[Wave Function Collapse algorithm](https://github.com/mxgmn/WaveFunctionCollapse). The original Implementaion written in C#, serves as inspiration for this implementation.

[NWFC -  Wave Function Collapse but LÖVE ](https://github.com/MikuAuahDark/nwfc). another implementation in lua for LÖVE2D development.

## LICENSE
MIT License, see LICENSE for further details.
