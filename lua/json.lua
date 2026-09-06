-- 最小 JSON 编解码(存档与 Tape 落盘用)。不依赖任何第三方;UTF-8 原样透传。
-- ⚠ 编码时 Lua 表按「是不是序列」分数组/对象;空表编成 {}。数按 %.17g(整值不带小数点)。
local M = {}
local floor = math.floor

local function is_array(t)
	local n = 0
	for k in pairs(t) do
		if type(k) ~= "number" then return false end
		n = n + 1
	end
	return n == #t
end

local ESC = { ['"'] = '\\"', ["\\"] = "\\\\", ["\b"] = "\\b", ["\f"] = "\\f", ["\n"] = "\\n", ["\r"] = "\\r", ["\t"] = "\\t" }

local function enc_str(s)
	return '"' .. s:gsub('[%c"\\]', function(c)
		return ESC[c] or string.format("\\u%04x", c:byte())
	end) .. '"'
end

local function enc(v, out)
	local t = type(v)
	if v == nil then out[#out + 1] = "null"
	elseif t == "boolean" then out[#out + 1] = v and "true" or "false"
	elseif t == "number" then
		if v ~= v or v == math.huge or v == -math.huge then out[#out + 1] = "null"
		elseif floor(v) == v and math.abs(v) < 2 ^ 53 then out[#out + 1] = string.format("%d", v)
		else out[#out + 1] = string.format("%.17g", v) end
	elseif t == "string" then out[#out + 1] = enc_str(v)
	elseif t == "table" then
		if is_array(v) and (#v > 0 or next(v) == nil) then
			out[#out + 1] = "["
			for i = 1, #v do
				if i > 1 then out[#out + 1] = "," end
				enc(v[i], out)
			end
			out[#out + 1] = "]"
		else
			out[#out + 1] = "{"
			local keys = {}
			for k in pairs(v) do keys[#keys + 1] = tostring(k) end
			table.sort(keys)
			for i, k in ipairs(keys) do
				if i > 1 then out[#out + 1] = "," end
				out[#out + 1] = enc_str(k) .. ":"
				local val = v[k]
				if val == nil then val = v[tonumber(k)] end
				enc(val, out)
			end
			out[#out + 1] = "}"
		end
	else
		error("json: cannot encode " .. t)
	end
end

function M.encode(v)
	local out = {}
	enc(v, out)
	return table.concat(out)
end

-- 解码:返回值, 或 nil + 错误串
local function skip(s, i)
	local _, j = s:find("^[ \t\r\n]*", i)
	return j + 1
end

local dec

local function dec_str(s, i)
	local out = {}
	i = i + 1
	while true do
		local c = s:sub(i, i)
		if c == "" then return nil, i, "unterminated string" end
		if c == '"' then return table.concat(out), i + 1 end
		if c == "\\" then
			local e = s:sub(i + 1, i + 1)
			local map = { ['"'] = '"', ["\\"] = "\\", ["/"] = "/", b = "\b", f = "\f", n = "\n", r = "\r", t = "\t" }
			if map[e] then
				out[#out + 1] = map[e]
				i = i + 2
			elseif e == "u" then
				local hex = s:sub(i + 2, i + 5)
				local cp = tonumber(hex, 16) or 0
				if cp < 0x80 then out[#out + 1] = string.char(cp)
				elseif cp < 0x800 then out[#out + 1] = string.char(0xC0 + floor(cp / 64), 0x80 + cp % 64)
				else out[#out + 1] = string.char(0xE0 + floor(cp / 4096), 0x80 + floor(cp / 64) % 64, 0x80 + cp % 64) end
				i = i + 6
			else
				return nil, i, "bad escape"
			end
		else
			out[#out + 1] = c
			i = i + 1
		end
	end
end

dec = function(s, i)
	i = skip(s, i)
	local c = s:sub(i, i)
	if c == "{" then
		local obj = {}
		i = skip(s, i + 1)
		if s:sub(i, i) == "}" then return obj, i + 1 end
		while true do
			i = skip(s, i)
			if s:sub(i, i) ~= '"' then return nil, i, "expected key" end
			local k, ni, err = dec_str(s, i)
			if k == nil then return nil, ni, err end
			i = skip(s, ni)
			if s:sub(i, i) ~= ":" then return nil, i, "expected ':'" end
			local v
			v, i, err = dec(s, i + 1)
			if err then return nil, i, err end
			obj[k] = v
			i = skip(s, i)
			local d = s:sub(i, i)
			if d == "," then i = i + 1
			elseif d == "}" then return obj, i + 1
			else return nil, i, "expected ',' or '}'" end
		end
	elseif c == "[" then
		local arr = {}
		i = skip(s, i + 1)
		if s:sub(i, i) == "]" then return arr, i + 1 end
		while true do
			local v, ni, err = dec(s, i)
			if err then return nil, ni, err end
			arr[#arr + 1] = v
			i = skip(s, ni)
			local d = s:sub(i, i)
			if d == "," then i = i + 1
			elseif d == "]" then return arr, i + 1
			else return nil, i, "expected ',' or ']'" end
		end
	elseif c == '"' then
		return dec_str(s, i)
	elseif s:sub(i, i + 3) == "true" then return true, i + 4
	elseif s:sub(i, i + 4) == "false" then return false, i + 5
	elseif s:sub(i, i + 3) == "null" then return nil, i + 4
	else
		local numstr = s:match("^-?%d+%.?%d*[eE]?[-+]?%d*", i)
		if numstr == nil or numstr == "" then return nil, i, "unexpected char '" .. c .. "'" end
		return tonumber(numstr), i + #numstr
	end
end

function M.decode(s)
	if type(s) ~= "string" then return nil, "not a string" end
	local v, i, err = dec(s, 1)
	if err then return nil, err .. " at " .. tostring(i) end
	return v
end

return M
