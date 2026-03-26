local M = {}
local config = require 'aria2.config'

local TASK_KEYS = {
  'gid',
  'status',
  'totalLength',
  'completedLength',
  'downloadSpeed',
  'uploadSpeed',
  'connections',
  'dir',
  'files',
  'numSeeders',
  'seeder',
  'errorCode',
  'errorMessage',
}

local state = {
  cache = {},
  cache_version = 0,
  config_key = nil,
  next_id = 0,
}

local function current_cfg() return config.get() end

local function config_key(cfg)
  return table.concat({
    tostring(cfg.rpc_url or ''),
    tostring(cfg.rpc_secret or ''),
    tostring(cfg.page_size or ''),
    tostring(cfg.stopped_fetch_size or ''),
  }, '\1')
end

local function ensure_cache_state()
  local cfg = current_cfg()
  local next_key = config_key(cfg)
  if state.config_key == next_key then return cfg end

  state.config_key = next_key
  state.cache = {}
  state.cache_version = 0
  return cfg
end

local function ensure_configured()
  local cfg = ensure_cache_state()
  if not cfg.rpc_url or cfg.rpc_url == '' then return nil, 'missing aria2 rpc_url' end
  return cfg
end

local function clone_params(params)
  local out = {}
  for i, item in ipairs(params or {}) do
    out[i] = item
  end
  return out
end

local function rpc(method, params, cb)
  local cfg, err = ensure_configured()
  if not cfg then
    cb(nil, err)
    return
  end

  state.next_id = state.next_id + 1
  local request_params = clone_params(params)
  if cfg.rpc_secret and cfg.rpc_secret ~= '' then
    table.insert(request_params, 1, 'token:' .. cfg.rpc_secret)
  end

  lc.http.request({
    method = 'POST',
    url = cfg.rpc_url,
    headers = {
      ['Content-Type'] = 'application/json',
    },
    body = lc.json.encode {
      jsonrpc = '2.0',
      id = tostring(state.next_id),
      method = 'aria2.' .. method,
      params = request_params,
    },
  }, function(response)
    if not response.success then
      cb(nil, response.error or ('HTTP ' .. tostring(response.status)))
      return
    end

    local ok, decoded = pcall(lc.json.decode, response.body or '')
    if not ok then
      cb(nil, 'failed to decode aria2 response')
      return
    end

    if decoded.error then
      local rpc_err = decoded.error
      cb(nil, rpc_err.message or ('aria2 rpc error ' .. tostring(rpc_err.code or 'unknown')))
      return
    end

    cb(decoded.result)
  end)
end

local function get_cached(name, loader, cb)
  local cfg = ensure_cache_state()
  local key = table.concat({ state.cache_version, name }, ':')
  local cached = state.cache[key]
  if cached and (lc.time.now() - cached.ts) <= (cfg.cache_ttl or 0) then
    cb(cached.value)
    return
  end

  loader(function(value, err)
    if err then
      cb(nil, err)
      return
    end
    state.cache[key] = {
      ts = lc.time.now(),
      value = value,
    }
    cb(value)
  end)
end

local function simple_call(method, params, cb)
  rpc(method, params, function(result, err)
    if err then
      cb(nil, err)
      return
    end
    M.invalidate_cache()
    cb(result or true)
  end)
end

function M.invalidate_cache()
  state.cache_version = state.cache_version + 1
  state.cache = {}
end

function M.ensure_configured()
  local cfg, err = ensure_configured()
  if not cfg then return nil, err end
  return true
end

function M.list_active(cb)
  get_cached('active', function(done)
    rpc('tellActive', { TASK_KEYS }, done)
  end, cb)
end

function M.list_waiting(cb)
  local cfg, err = ensure_configured()
  if not cfg then
    cb(nil, err)
    return
  end

  get_cached('waiting', function(done)
    rpc('tellWaiting', { 0, cfg.page_size, TASK_KEYS }, done)
  end, cb)
end

function M.list_completed(cb)
  local cfg, err = ensure_configured()
  if not cfg then
    cb(nil, err)
    return
  end

  get_cached('completed', function(done)
    rpc('tellStopped', { 0, cfg.stopped_fetch_size, TASK_KEYS }, function(items, rpc_err)
      if rpc_err then
        done(nil, rpc_err)
        return
      end

      local completed = {}
      for _, item in ipairs(items or {}) do
        if item.status == 'complete' then
          table.insert(completed, item)
        end
        if #completed >= cfg.page_size then break end
      end
      done(completed)
    end)
  end, cb)
end

function M.pause(gid, cb)
  simple_call('pause', { tostring(gid) }, cb)
end

function M.resume(gid, cb)
  simple_call('unpause', { tostring(gid) }, cb)
end

function M.remove(gid, status, cb)
  local method = (status == 'complete' or status == 'error' or status == 'removed') and 'removeDownloadResult'
    or 'forceRemove'
  simple_call(method, { tostring(gid) }, cb)
end

function M.add_uri(uri, cb)
  local value = tostring(uri or ''):match '^%s*(.-)%s*$'
  if value == '' then
    cb(nil, 'empty uri')
    return
  end
  simple_call('addUri', { { value } }, cb)
end

return M
