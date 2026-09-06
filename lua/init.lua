-- Sync5 Lua 镜像的公共前缀助手(docs/design/mirror.md §3)。
-- 每个模块用 `local P = (...):match("^(.-)[^%.]+$") or ""` 取自己的包前缀,
-- 再 `require(P .. "card")` 引兄弟模块;引根目录的 num/rng/data 用 `init.root(P)`。
-- 这样整目录拷到任何位置(scripts/sync5/…)都不用改一行 require。
local M = {}

-- "sync5.core." → "sync5."; "core." → ""; "" → ""
function M.root(P)
	P = P or ""
	local r = P:gsub("core%.$", ""):gsub("app%.$", ""):gsub("tools%.$", "")
	return r
end

M.version = _VERSION
M.jit = (rawget(_G, "jit") and jit.version) or nil
-- 5.3+ 有整数子类型;5.1/LuaJIT 全是 double。镜像不依赖这个差别, 只用于诊断输出。
M.has_int = math.type ~= nil

return M
