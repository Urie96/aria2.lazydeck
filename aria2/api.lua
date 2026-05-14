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
  next_id = 0,
  last_start_at = 0,
  start_pid = nil,
}

local function current_cfg() return config.get() end

local function current_download_dir()
  local cfg = current_cfg()
  return cfg.download_dir or os.getenv 'PWD' or '.'
end

local function ensure_configured()
  local cfg = current_cfg()
  if not cfg.rpc_url or cfg.rpc_url == '' then return nil, 'missing aria2 rpc_url' end
  return cfg
end

local function parse_rpc_url(url)
  local scheme, host, port = tostring(url or ''):match '^(https?)://([^:/]+):?(%d*)/?.*$'
  if not scheme or not host then return nil end
  if port == '' then port = scheme == 'https' and '443' or '80' end
  return {
    scheme = scheme,
    host = host,
    port = tonumber(port) or 6800,
  }
end

local function is_local_rpc_url(url)
  local parsed = parse_rpc_url(url)
  if not parsed then return false end
  return parsed.host == '127.0.0.1' or parsed.host == 'localhost' or parsed.host == '0.0.0.0' or parsed.host == '::1'
end

local function is_connection_error(err)
  local msg = tostring(err or ''):lower()
  return msg:find('error sending request for url', 1, true) ~= nil
    or msg:find('connection refused', 1, true) ~= nil
    or msg:find('tcp connect error', 1, true) ~= nil
end

local function build_start_cmd(cfg)
  if cfg.start_cmd then return cfg.start_cmd end

  local parsed = parse_rpc_url(cfg.rpc_url)
  if not parsed then return nil, 'invalid aria2 rpc_url' end

  local cmd = {
    'aria2c',
    '--enable-rpc=true',
    '--daemon=true',
    '--rpc-listen-all=false',
    '--rpc-allow-origin-all',
    '--rpc-listen-port=' .. tostring(parsed.port),
    '--dir=' .. current_download_dir(),
  }
  if cfg.rpc_secret and cfg.rpc_secret ~= '' then table.insert(cmd, '--rpc-secret=' .. cfg.rpc_secret) end
  return cmd
end

local function local_rpc_unavailable_hint(cfg)
  if not cfg or not is_local_rpc_url(cfg.rpc_url) then return nil end

  local cmd, err = build_start_cmd(cfg)
  if not cmd then return err end

  if not deck.system.executable(cmd[1]) then
    return string.format(
      'cannot connect to aria2 rpc at %s, and %s is not in PATH',
      tostring(cfg.rpc_url),
      tostring(cmd[1])
    )
  end

  return nil
end

local function auto_start_message(pid)
  local msg = 'aria2 daemon started'
  if pid and pid > 0 then msg = msg .. ' (pid ' .. tostring(pid) .. ')' end
  return msg
end

local function ensure_daemon_started(cfg)
  if not cfg.auto_start then return false, 'aria2 auto start disabled' end
  if not is_local_rpc_url(cfg.rpc_url) then return false, 'aria2 auto start only supports local rpc_url' end

  local now = deck.time.now()
  if state.last_start_at > 0 and (now - state.last_start_at) < 5 then
    return true, 'aria2 daemon start already requested'
  end

  local cmd, err = build_start_cmd(cfg)
  if not cmd then return false, err end
  if not deck.system.executable(cmd[1]) then return false, 'command not found: ' .. tostring(cmd[1]) end

  local ok, pid = pcall(deck.system.spawn, cmd)
  if not ok then return false, pid end

  state.last_start_at = now
  state.start_pid = pid
  deck.notify(auto_start_message(pid))
  return true
end

local function clone_params(params)
  local out = {}
  for i, item in ipairs(params or {}) do
    out[i] = item
  end
  return out
end

local function rpc(method, params, cb, opts)
  local cfg, err = ensure_configured()
  if not cfg then
    cb(nil, err)
    return
  end

  state.next_id = state.next_id + 1
  local request_params = clone_params(params)
  if cfg.rpc_secret and cfg.rpc_secret ~= '' then table.insert(request_params, 1, 'token:' .. cfg.rpc_secret) end

  deck.http.request({
    method = 'POST',
    url = cfg.rpc_url,
    headers = {
      ['Content-Type'] = 'application/json',
    },
    body = deck.json.encode {
      jsonrpc = '2.0',
      id = tostring(state.next_id),
      method = 'aria2.' .. method,
      params = request_params,
    },
  }, function(response)
    if not response.success then
      local response_err = response.error or ('HTTP ' .. tostring(response.status))
      local connection_error = is_connection_error(response_err)
      if not (opts and opts.skip_auto_start) and connection_error and ensure_daemon_started(cfg) then
        if deck.system.executable 'sleep' then
          deck.system.exec(
            { 'sleep', tostring(cfg.auto_start_delay or 1) },
            function() rpc(method, params, cb, { skip_auto_start = true }) end
          )
          return
        end
        cb(nil, 'aria2 daemon started in background, please retry')
        return
      end

      if connection_error then
        local hint = local_rpc_unavailable_hint(cfg)
        if hint then
          cb(nil, hint)
          return
        end
      end

      cb(nil, response_err)
      return
    end

    local ok, decoded = pcall(deck.json.decode, response.body or '')
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

local function simple_call(method, params, cb)
  rpc(method, params, function(result, err)
    if err then
      cb(nil, err)
      return
    end
    cb(result or true)
  end)
end

function M.invalidate_cache() end

function M.ensure_configured()
  local cfg, err = ensure_configured()
  if not cfg then return nil, err end
  return true
end

function M.list_active(cb) rpc('tellActive', { TASK_KEYS }, cb) end

function M.list_waiting(cb)
  local cfg, err = ensure_configured()
  if not cfg then
    cb(nil, err)
    return
  end

  rpc('tellWaiting', { 0, cfg.page_size, TASK_KEYS }, cb)
end

function M.list_stopped(cb)
  local cfg, err = ensure_configured()
  if not cfg then
    cb(nil, err)
    return
  end

  rpc('tellStopped', { 0, cfg.stopped_fetch_size, TASK_KEYS }, cb)
end

function M.list_completed(cb)
  local cfg = current_cfg()
  M.list_stopped(function(items, rpc_err)
    if rpc_err then
      cb(nil, rpc_err)
      return
    end

    local completed = {}
    for _, item in ipairs(items or {}) do
      if item.status == 'complete' then table.insert(completed, item) end
      if #completed >= cfg.page_size then break end
    end
    cb(completed)
  end)
end

function M.pause(gid, cb) simple_call('pause', { tostring(gid) }, cb) end

function M.resume(gid, cb) simple_call('unpause', { tostring(gid) }, cb) end

function M.remove(gid, status, cb)
  local method = (status == 'complete' or status == 'error' or status == 'removed') and 'removeDownloadResult'
    or 'forceRemove'
  simple_call(method, { tostring(gid) }, cb)
end

function M.add_uri(uri, cb)
  local uris = {}
  for line in uri:gmatch '[^\r\n]+' do
    line = line:match '^%s*(.-)%s*$'
    if line ~= '' then table.insert(uris, line) end
  end

  local count = #uris
  if count == 0 then
    cb(nil, 'empty uri')
    return
  end

  if count == 1 then
    simple_call('addUri', { { uris[1] }, { dir = current_download_dir() } }, cb)
    return
  end

  -- 多行：逐个添加任务
  local gids = {}
  local pending = count

  local function on_one(gid, err)
    if gid then table.insert(gids, gid) end
    pending = pending - 1
    if pending == 0 then
      if #gids == count then
        cb(table.concat(gids, ', '))
      else
        cb(nil, 'added ' .. tostring(#gids) .. '/' .. tostring(count) .. ' tasks')
      end
    end
  end

  for i = 1, count do
    simple_call('addUri', { { uris[i] }, { dir = current_download_dir() } }, on_one)
  end
end

return M
