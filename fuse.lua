if jit then
    require("ffi")
end

-- Variables

local programArgs = {
    ---@type file*
    input = io.stdin,

    ---@type string?
    inputName = nil,

    ---@type file*
    output = io.stdout,

    ---@type string?
    outputName = nil,

    ---@type string?
    requireFolder = nil,
}

local modules = {}

-- Functions

local function printUsage()
    print("Usage:")
    print("\tlua fuse.lua [input] [-R<dir>] [-o output] ")
    print("options:")
    print("", "-o <file>", "Write output to <file>. default is stdout")
    print("", "-r <dir>", "Directory for the module searcher")
    print("", "-h / -help", "Prints the usage. Will exit immediately after printing.")
end

local function parseArgs()
    local i = 1

    while i <= #arg do
        local argument = arg[i]

        if argument:match("%.([^.]+)$") == "lua" then
            if programArgs.inputName then
                error("input already defined")
            end
            programArgs.inputName = argument
        elseif argument == "-o" then
            if programArgs.outputName then
                error("output already defined")
            end
            programArgs.outputName = arg[i + 1]
            i = i + 1
        elseif argument == "-r" or argument == "-R" then
            if programArgs.requireFolder then
                error("-R already defined")
            end
            programArgs.requireFolder = arg[i + 1]
            i = i + 1
        elseif argument == "-h" or argument == "-help" then
            printUsage()
            os.exit(-1)
        else
            error("invalid argument \"" .. argument .. "\"\10For usage use: -h")
        end

        i = i + 1
    end

    if i == 1 then
        printUsage()
        os.exit(-1)
    end
end

local function openHandles()
    if programArgs.inputName then
        local file, err = io.open(programArgs.inputName, "r+b")

        if file then
            programArgs.input = file
        else
            error("error opening input \"" .. programArgs.inputName .. "\" (" .. err .. ")")
        end
    end

    if programArgs.outputName then
        local file, err = io.open(programArgs.outputName, "w+b")

        if file then
            programArgs.output = file
        else
            error("error opening output \"" .. programArgs.outputName .. "\" (" .. err .. ")")
        end
    end
end

---@type fun(name: string): boolean, filename: string?
local function moduleExists(name)
    local fullname = programArgs.requireFolder .. "/" .. name
    local luaFile = io.open(fullname .. ".lua", "r+")
    if luaFile then
        luaFile:close()
        return true
    end

    luaFile = io.open(fullname .. "/init.lua", "r+")
    if luaFile then
        luaFile:close()
        return true, fullname .. "/init.lua"
    end

    local ext = jit.os == "Windows" and ".dll" or ".so"
    local libFile = io.open(fullname .. ext, "r+")
    if libFile then
        libFile:close()
        return true
    end

    if jit.os == "Linux" then
        libFile = io.open("usr/local/" .. name .. "/init.so", "r+")
        if libFile then
            libFile:close()
            return true
        end
    end

    if package.loaded[name] then
        return true
    end

    return false
end

---@type fun(file: file*)
local function getFileRequires(file)
    ---@type string
    local content = file:read("*a")
    file:seek("set", 0)

    for modName in content:gmatch("require%(\"([A-Za-z%d%.]+)\"%)") do
        local exists, filename = moduleExists(modName:gsub("%.", "/"))
        if not exists then
            error("module '" .. modName .. "' does not exist.")
        end
        if package.loaded[modName] then
            goto continue
        end
        for _, module in next, modules do
            if module[1] == modName then
                goto continue
            end
        end
        local modFilename = filename or programArgs.requireFolder .. "/" .. modName:gsub("%.", "/") .. ".lua"
        local modFile, err = io.open(modFilename, "rb")
        if not modFile then
            error("error opening module " .. err)
        end

        getFileRequires(modFile)

        print(modName)
        table.insert(modules, { modName, modFilename })
        modFile:close()

        ::continue::
    end
end

do
    parseArgs()
    openHandles()

    local input = programArgs.input
    local output = programArgs.output

    getFileRequires(programArgs.input)
    if #modules > 0 then
        math.randomseed(os.time())
        local modulesName = "__MODULES_" .. string.format("%X", math.random(0, 0xFFFFFFF))
        output:write("local ", modulesName, " = {\10")

        for i, mod in next, modules do
            local file, err = io.open(mod[2], "r")
            if not file then
                error("error opening module " .. err)
            end

            output:write("[\"" .. mod[1] .. "\"] = function()\10")
            output:write(file:read("*a"))
            output:write("\10end,\10")
        end

        output:write("}\10")

        output:write("package.loaders = {\10")
        output:write("function(modname)\10")
        output:write("if package.loaded[modname] then\10")
        output:write("return package.loaded[modname]\10")
        output:write("elseif ", modulesName, "[modname] then\10")
        output:write("local moddata =", modulesName, "[modname]\10")
        output:write("package.loaded[modname] = moddata\10")
        output:write("return moddata\10")
        output:write("end\10", "end,\10")
        output:write("package.loaders[1],\10", "package.loaders[3],\10")
        output:write("}\10")
    end

    output:write("do\10")
    output:write(input:read("*a"))
    output:write("\10end")
end
