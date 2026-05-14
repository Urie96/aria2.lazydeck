local M = {}

local cfg = {
  rpc_url = os.getenv 'ARIA2_RPC_URL' or 'http://127.0.0.1:6800/jsonrpc',
  rpc_secret = os.getenv 'ARIA2_RPC_SECRET',
  page_size = 200,
  stopped_fetch_size = 400,
  auto_start = true,
  auto_start_delay = 1,
  download_dir = nil,
  start_cmd = nil,
  keymap = {
    actions = '<enter>',
    open_file = 'o',
    pause = 'p',
    resume = 'r',
  },
}

local function trim(s)
  if s == nil then return nil end
  return tostring(s):match '^%s*(.-)%s*$'
end

local function normalize(next_cfg)
  local out = deck.tbl_extend('force', {}, next_cfg or {})
  out.rpc_url = trim(out.rpc_url)
  out.rpc_secret = trim(out.rpc_secret)
  out.page_size = tonumber(out.page_size) or cfg.page_size
  out.stopped_fetch_size = tonumber(out.stopped_fetch_size) or cfg.stopped_fetch_size
  out.auto_start = out.auto_start ~= false
  out.auto_start_delay = tonumber(out.auto_start_delay) or cfg.auto_start_delay
  out.download_dir = trim(out.download_dir)
  if type(out.start_cmd) ~= 'table' or #out.start_cmd == 0 then out.start_cmd = nil end
  return out
end

function M.setup(opt)
  local global_keymap = deck.config.get().keymap
  cfg = normalize(deck.tbl_deep_extend('force', cfg, { keymap = global_keymap }, opt or {}))
end

function M.get() return cfg end

return M
