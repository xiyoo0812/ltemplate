--ltemplate.lua
local type          = type
local ipairs        = ipairs
local iopen         = io.open
local tconcat       = table.concat
local tinsert       = table.insert
local ssub          = string.sub
local sfind         = string.find
local sgsub         = string.gsub
local sformat       = string.format
local sgmatch       = string.gmatch

local open_tag = "{{%"
local close_tag = "%}}"
local equal_tag = "="

local function get_line(content, line_num)
    for line in sgmatch(content, "([^\n]*)\n?") do
    if line_num == 1 then
        return line
    end
    line_num = line_num - 1
    end
end

local function pos_to_line(content, pos)
    local line = 1
    local scontent = ssub(content, 1, pos)
    for _ in sgmatch(scontent, "\n") do
        line = line + 1
    end
    return line
end

local function error_for_pos(code, source_pos, err_msg)
    local source_line_no = pos_to_line(code, source_pos)
    local source_line = get_line(code, source_line_no)
    return sformat("%s [%s]: %s", err_msg, source_line_no, source_line)
end

local function push_token(buffers, ...)
    for _, str in ipairs({...}) do
        tinsert(buffers, str)
    end
end

local function compile_chunks(chunks)
    local buffers = {}
    push_token(buffers, "local _b, _b_i = {}, 0 \n")
    for _, chunk in ipairs(chunks) do
        local tpe = chunk[1]
        if "string" == tpe then
            push_token(buffers, "_b_i = _b_i + 1\n", "_b[_b_i] = ", sformat("%q", chunk[2]), "\n")
        elseif "code" == tpe then
            push_token(buffers, chunk[2], "\n")
        elseif "equal" == tpe then
            push_token(buffers, "_b_i = _b_i + 1\n", "_b[_b_i] = ",  chunk[2], "\n")
        end
    end
    push_token(buffers, "return _b")
    return tconcat(buffers)
end

local function push_chunk(chunks, kind, value)
    local chunk = chunks[#chunks]
    if chunk then
        if kind == "code" then
            chunk[2] = sgsub(chunk[2], "[ \t]+$", "")
            chunks[#chunks] = chunk
        end
        if chunk[1] == "code" and ssub(value, 1, 1) == "\n" then
            value = ssub(value, 2, #value)
        end
    end
    tinsert(chunks, { kind, value })
end

local function next_tag(chunks, content, ppos)
    local start, stop = sfind(content, open_tag, ppos, true)
    if not start then
        push_chunk(chunks, "string", ssub(content, ppos, #content))
        return false
    end
    if start ~= ppos then
        push_chunk(chunks, "string", ssub(content, ppos, start - 1))
    end
    ppos = stop + 1
    local equal
    if ssub(content, ppos, ppos) == equal_tag then
        equal = true
        ppos = ppos + 1
    end
    local close_start, close_stop = sfind(content, close_tag, ppos, true)
    if not close_start then
        return nil, error_for_pos(content, start, "failed to find closing tag")
    end
    push_chunk(chunks, equal and "equal" or "code", ssub(content, ppos, close_start - 1))
    ppos = close_stop + 1
    return ppos
end

local function parse(content)
    local pos, chunks = 1, {}
    while true do
        local found, err = next_tag(chunks, content, pos)
        if err then
            return nil, err
        end
        if not found then
            break
        end
        pos = found
    end
    return chunks
end

local function load_chunk(chunk_code, env)
    local fn, err = load(chunk_code, "template", "bt", env)
    if not fn then
        return nil, err
    end
    return fn
end

--替换字符串模板
--content：字符串模板
--env：环境变量(包含自定义参数)
local function render(content, env)
    local chunks, err = parse(sgsub(content, "\r\n", "\n"))
    if not chunks then
        return nil, err
    end
    local chunk = compile_chunks(chunks)
    setmetatable(env, { __index = function(t, k) return _G[k] end })
    local fn, err2 = load_chunk(chunk, env)
    if not fn then
        return nil, err2
    end
    local buffer, err = fn()
    if buffer then
        return tconcat(buffer)
    end
    return nil, err
end

--导出文件模板
--tpl：文件模板
--tpl_out：输出文件
--tpl_env：环境变量文件(包含自定义参数)
local function render_file(tpl, tpl_out, tpl_env)
    if not tpl or not tpl_out or not tpl_env then
        error("render template file params error!")
        return
    end
    local template_file = iopen(tpl, "rb")
    if not template_file then
        error(sformat("open template file %s failed!", tpl))
        return
    end
    local content = template_file:read("*all")
    template_file:close()
    local env = {}
    local func, err = loadfile(tpl_env, "bt", env)
    if not func then
        error(sformat("open template variable file %s failed :%s", tpl_env, err))
        return
    end
    local ok, res = pcall(func)
    if not ok then
        error(sformat("load template variable file %s failed :%s", tpl_env, res))
        return
    end
    local template, err = render(content, env)
    if not template then
        error(sformat("render template file %s failed: %s", tpl, err))
        return
    end
    local out_file = iopen(tpl_out, "w")
    if not out_file then
        error(sformat("open template out file %s failed!", tpl_out))
        return
    end
    out_file:write(template)
    out_file:close()
    print(sformat("render template file %s to %s success!", tpl, tpl_out))
end

--工具用法
if select("#", ...) == 3 then
    render_file(...)
end

return {
    render = render,
    render_file = render_file
}
