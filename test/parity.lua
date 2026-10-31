-- Public-surface parity check against a committed ox_lib 3.39.0 golden.
--
--   lua5.4 test/parity.lua check <resource_dir> [golden.json]
--   lua5.4 test/parity.lua emit  <resource_dir>            (prints surface JSON)
--
-- Offline, plain Lua 5.4, regex-based. Reads files under <resource_dir> only.
-- Anything in the golden but missing from the resource fails the check unless
-- it matches the soft list below. Extras are reported as info.

local SOFT = {
    -- headless shim: no NUI build, no RedM prerelease banner
    ['manifest.ui_page'] = 'headless: no NUI',
    ['manifest.games'] = 'manifest key not carried',
    ['manifest.rdr3_warning'] = 'manifest key not carried',
    ['convars.ox:primaryColor'] = 'headless: NUI theme',
    ['convars.ox:primaryShade'] = 'headless: NUI theme',
}

local function readFile(path)
    local f = io.open(path, 'rb')
    if not f then return nil end
    local s = f:read('*a')
    f:close()
    return s
end

local function listFiles(dir)
    local p = io.popen(('find %q -type f 2>/dev/null | LC_ALL=C sort'):format(dir))
    local out = {}
    for line in p:lines() do out[#out + 1] = line end
    p:close()
    return out
end

local function listDirs(dir)
    local p = io.popen(('find %q -mindepth 1 -maxdepth 1 -type d 2>/dev/null | LC_ALL=C sort'):format(dir))
    local out = {}
    for line in p:lines() do out[#out + 1] = line:match('[^/]+$') end
    p:close()
    return out
end

local function sortedKeys(set)
    local out = {}
    for k in pairs(set) do out[#out + 1] = k end
    table.sort(out)
    return out
end

local function stripComments(src)
    return (src:gsub('%-%-%[(=*)%[.-%]%1%]', ''):gsub('%-%-[^\n]*', ''))
end

local function realmOf(rel)
    for part in rel:gmatch('[^/]+') do
        local name = part:gsub('%.lua$', '')
        if name == 'client' or name == 'server' or name == 'shared' then return name end
    end
    return 'shared'
end

local function extract(root)
    local s = {
        exports = { client = {}, server = {}, shared = {}, dynamic = {} },
        imports = {},
        importFiles = {},
        locales = {},
        manifest = {},
        events = {},
        convars = {},
    }

    for _, dir in ipairs(listDirs(root .. '/imports')) do s.imports[dir] = true end
    for _, path in ipairs(listFiles(root .. '/imports')) do
        local rel = path:sub(#root + 2)
        local mod, file = rel:match('^imports/([^/]+)/(client)%.lua$')
        if not mod then mod, file = rel:match('^imports/([^/]+)/(server)%.lua$') end
        if not mod then mod, file = rel:match('^imports/([^/]+)/(shared)%.lua$') end
        if mod then s.importFiles[mod .. '/' .. file] = true end
    end
    for _, path in ipairs(listFiles(root .. '/locales')) do
        local name = path:match('([^/]+)%.json$')
        if name then s.locales[name] = true end
    end

    local manifest = readFile(root .. '/fxmanifest.lua') or ''
    for line in stripComments(manifest):gmatch('[^\n]+') do
        local key = line:match('^%s*([%w_]+)[%s{\'"]')
        if key then s.manifest[key] = true end
    end

    local function scan(rel, code, isResource)
        local realm = realmOf(rel)
        if isResource then
            for name in code:gmatch('function%s+lib%.([%w_]+)%s*%(') do s.exports[realm][name] = true end
            for name in code:gmatch('[\n;]%s*lib%.([%w_]+)%s*=[^=]') do s.exports[realm][name] = true end
        end
        for name in code:gmatch('exports%s*%(%s*[\'"]([^\'"]+)[\'"]') do
            if name:find('%%s') then s.exports.dynamic[name] = true else s.exports[realm][name] = true end
        end
        for name in code:gmatch('exports%s*%(%s*%(%s*[\'"]([^\'"]+)[\'"]') do
            s.exports.dynamic[name] = true
        end
        for name in code:gmatch('[\'"](ox_lib:[%w_:%%]+)[\'"]') do s.events[name] = true end
        for name in code:gmatch('[\'"](__ox_[%w_]*%%s)[\'"]') do s.events[name] = true end
        for name in code:gmatch('GetConvar%w*%s*%(%s*[\'"](ox:[%w_:]+)[\'"]') do s.convars[name] = true end
    end

    for _, sub in ipairs { 'resource', 'imports' } do
        for _, path in ipairs(listFiles(root .. '/' .. sub)) do
            if path:match('%.lua$') then
                local rel = path:sub(#root + 2)
                scan(rel, stripComments(readFile(path)), sub == 'resource')
            end
        end
    end
    scan('init.lua', stripComments(readFile(root .. '/init.lua') or ''), false)

    return s
end

-- Minimal JSON writer (sorted, 2-space indent) and reader; surface data only.
local function encode(v, indent)
    indent = indent or ''
    if type(v) ~= 'table' then return ('%q'):format(tostring(v)):gsub('\\\n', '\\n') end
    local inner = indent .. '  '
    if #v > 0 or next(v) == nil then
        local parts = {}
        for _, x in ipairs(v) do parts[#parts + 1] = inner .. encode(x, inner) end
        if #parts == 0 then return '[]' end
        return '[\n' .. table.concat(parts, ',\n') .. '\n' .. indent .. ']'
    end
    local parts = {}
    for _, k in ipairs(sortedKeys(v)) do
        parts[#parts + 1] = inner .. encode(k) .. ': ' .. encode(v[k], inner)
    end
    return '{\n' .. table.concat(parts, ',\n') .. '\n' .. indent .. '}'
end

local function decode(src)
    local pos = 1
    local function ws() pos = src:find('[^ \t\r\n]', pos) or #src + 1 end
    local value
    local function str()
        local close = pos + 1
        while src:sub(close, close) ~= '"' do
            close = close + (src:sub(close, close) == '\\' and 2 or 1)
        end
        local raw = src:sub(pos + 1, close - 1)
        pos = close + 1
        return (raw:gsub('\\(.)', { n = '\n', t = '\t', ['"'] = '"', ['\\'] = '\\', ['/'] = '/' }))
    end
    function value()
        ws()
        local c = src:sub(pos, pos)
        if c == '{' then
            local t = {}
            pos = pos + 1
            ws()
            if src:sub(pos, pos) == '}' then pos = pos + 1 return t end
            while true do
                ws()
                local k = str()
                ws()
                assert(src:sub(pos, pos) == ':', 'json: expected ":"')
                pos = pos + 1
                t[k] = value()
                ws()
                local d = src:sub(pos, pos)
                pos = pos + 1
                if d == '}' then return t end
                assert(d == ',', 'json: expected ","')
            end
        elseif c == '[' then
            local t = {}
            pos = pos + 1
            ws()
            if src:sub(pos, pos) == ']' then pos = pos + 1 return t end
            while true do
                t[#t + 1] = value()
                ws()
                local d = src:sub(pos, pos)
                pos = pos + 1
                if d == ']' then return t end
                assert(d == ',', 'json: expected ","')
            end
        elseif c == '"' then
            return str()
        end
        error('json: unsupported value at ' .. pos)
    end
    return value()
end

local function toLists(surface)
    local out = { exports = {} }
    for realm, set in pairs(surface.exports) do out.exports[realm] = sortedKeys(set) end
    for _, group in ipairs { 'imports', 'importFiles', 'locales', 'manifest', 'events', 'convars' } do
        out[group] = sortedKeys(surface[group])
    end
    return out
end

-- Flatten to "group.name" -> true (exports are keyed by realm).
local function flatten(lists)
    local flat = {}
    for realm, names in pairs(lists.exports) do
        for _, n in ipairs(names) do flat['exports.' .. realm .. '.' .. n] = true end
    end
    for _, group in ipairs { 'imports', 'importFiles', 'locales', 'manifest', 'events', 'convars' } do
        for _, n in ipairs(lists[group] or {}) do flat[group .. '.' .. n] = true end
    end
    return flat
end

local function softReason(key)
    return SOFT[key]
end

local mode, root, goldenPath = arg[1], arg[2], arg[3]
if (mode ~= 'check' and mode ~= 'emit') or not root then
    io.stderr:write('usage: parity.lua check|emit <resource_dir> [golden.json]\n')
    os.exit(2)
end
root = root:gsub('/+$', '')

local lists = toLists(extract(root))

if mode == 'emit' then
    lists.meta = { source = 'ox_lib', version = '3.39.0' }
    print(encode(lists))
    return
end

goldenPath = goldenPath or (arg[0]:match('^(.*)/[^/]*$') or '.') .. '/parity.golden.json'
local goldenSrc = readFile(goldenPath)
if not goldenSrc then
    io.stderr:write('cannot read golden: ' .. goldenPath .. '\n')
    os.exit(2)
end
local golden = flatten(decode(goldenSrc))
local actual = flatten(lists)

local missing, soft, extra = {}, {}, {}
for key in pairs(golden) do
    if not actual[key] then
        local reason = softReason(key)
        if reason then soft[#soft + 1] = key .. ' (' .. reason .. ')' else missing[#missing + 1] = key end
    end
end
for key in pairs(actual) do
    if not golden[key] then extra[#extra + 1] = key end
end
table.sort(missing)
table.sort(soft)
table.sort(extra)

local total = 0
for _ in pairs(golden) do total = total + 1 end

for _, k in ipairs(soft) do print('soft:    ' .. k) end
for _, k in ipairs(extra) do print('info:    extra ' .. k) end
for _, k in ipairs(missing) do print('MISSING: ' .. k) end

print(('parity: %d golden entries, %d missing, %d soft, %d extra'):format(total, #missing, #soft, #extra))
if #missing > 0 then os.exit(1) end
print('ok - ox_lib 3.39.0 public surface present')
