local M = {}

local cfg = {
  rpc_url = os.getenv 'ARIA2_RPC_URL' or 'http://127.0.0.1:6800/jsonrpc',
  rpc_secret = os.getenv 'ARIA2_RPC_SECRET',
  page_size = 200,
  stopped_fetch_size = 400,
  cache_ttl = 3,
}

local function trim(s)
  if s == nil then return nil end
  return tostring(s):match '^%s*(.-)%s*$'
end

local function normalize(next_cfg)
  local out = lc.tbl_extend('force', {}, next_cfg or {})
  out.rpc_url = trim(out.rpc_url)
  out.rpc_secret = trim(out.rpc_secret)
  out.page_size = tonumber(out.page_size) or cfg.page_size
  out.stopped_fetch_size = tonumber(out.stopped_fetch_size) or cfg.stopped_fetch_size
  out.cache_ttl = tonumber(out.cache_ttl) or cfg.cache_ttl
  return out
end

function M.setup(opt) cfg = normalize(lc.tbl_extend('force', cfg, opt or {})) end

function M.get() return cfg end

return M
