local M = {}

local api = require 'aria2.api'

local function span(text, color)
  local s = deck.style.span(tostring(text or ''))
  if color and color ~= '' then s = s:fg(color) end
  return s
end

local function line(parts) return deck.style.line(parts) end

local function trim(s)
  if not s then return '' end
  return tostring(s):match '^%s*(.-)%s*$'
end

local function primary_file(task)
  local files = task and task.files or {}
  if not files or #files == 0 then return nil end
  for _, file in ipairs(files) do
    local path = trim(file.path)
    if path ~= '' then return file end
  end
  return files[1]
end

local function task_name(task)
  local file = primary_file(task)
  if file then
    local path = trim(file.path)
    if path ~= '' then return path:match '[^/]+$' or path end
    for _, uri in ipairs(file.uris or {}) do
      local uri_value = trim(uri.uri)
      if uri_value ~= '' then return uri_value end
    end
  end
  return 'gid:' .. tostring(task and task.gid or '?')
end

local function task_path(task)
  local file = primary_file(task)
  if not file then return nil end
  local path = trim(file.path)
  if path ~= '' then return path end
  return nil
end

local function show_error(err)
  deck.notify(line {
    span('aria2: ', 'red'),
    span(err or 'unknown error', 'red'),
  })
end

local function show_info(msg)
  deck.notify(line {
    span('aria2: ', 'cyan'),
    span(msg or '', 'white'),
  })
end

local function refresh_after_action(msg)
  if msg and msg ~= '' then show_info(msg) end
  deck.cmd 'reload'
end

function M.can_open(task)
  local path = task_path(task)
  return task and task.status == 'complete' and path and path ~= ''
end

function M.can_pause(task) return task and (task.status == 'active' or task.status == 'waiting') end

function M.can_resume(task) return task and task.status == 'paused' end

function M.can_remove(task) return task and task.gid and task.gid ~= '' and task.status ~= 'removed' end

function M.can_restart(task) return task and task.status == 'error' end

function M.hovered_task()
  local hovered = deck.api.get_hovered()
  if hovered and hovered.kind == 'task' then return hovered.task end
  return nil
end

function M.open_task_file(task)
  local path = task_path(task)
  if not path or path == '' then
    show_error 'no file path for selected task'
    return false
  end
  local stat = deck.fs.stat(path)
  if not stat.exists then
    show_error('file does not exist: ' .. path)
    return false
  end
  deck.system.open(path)
  return true
end

function M.open_hovered_file()
  local task = M.hovered_task()
  if not task then return false end
  if not M.can_open(task) then
    show_error 'selected task has no downloadable file to open'
    return true
  end
  return M.open_task_file(task)
end

function M.pause_hovered_task()
  local task = M.hovered_task()
  if not task or not M.can_pause(task) then return false end
  api.pause(task.gid, function(_, err)
    if err then
      show_error(err)
      return
    end
    refresh_after_action 'task paused'
  end)
  return true
end

function M.resume_hovered_task()
  local task = M.hovered_task()
  if not task or not M.can_resume(task) then return false end
  api.resume(task.gid, function(_, err)
    if err then
      show_error(err)
      return
    end
    refresh_after_action 'task resumed'
  end)
  return true
end

function M.remove_hovered_task()
  local task = M.hovered_task()
  if not task or not M.can_remove(task) then return false end
  deck.confirm {
    title = 'Remove aria2 Task',
    prompt = 'Remove task "' .. task_name(task) .. '"?',
    on_confirm = function()
      api.remove(task.gid, task.status, function(_, err)
        if err then
          show_error(err)
          return
        end
        refresh_after_action 'task removed'
      end)
    end,
  }
  return true
end

function M.add_download_from_input()
  deck.input {
    prompt = 'Add download URL',
    placeholder = 'https://example.com/file.iso or magnet:?... (支持多行)',
    on_submit = function(input)
      local uri = trim(input)
      if uri == '' then return end
      api.add_uri(uri, function(gid, err)
        if err then
          show_error(err)
          return
        end
        refresh_after_action('download added: ' .. tostring(gid or uri))
      end)
    end,
  }
end

local function get_task_uris(task)
  -- 尝试从 files 中获取 URIs
  local files = task and task.files or {}
  for _, file in ipairs(files) do
    local uris = file.uris or {}
    local result = {}
    for _, uri_info in ipairs(uris) do
      local uri_value = trim(uri_info.uri)
      if uri_value ~= '' then
        table.insert(result, uri_value)
      end
    end
    if #result > 0 then return result end
  end
  -- 如果没有 URIs，尝试从 files[1].path 获取（对于本地种子文件等）
  return nil
end

function M.restart_hovered_task()
  local task = M.hovered_task()
  if not task or not M.can_restart(task) then return false end

  local uris = get_task_uris(task)
  if not uris or #uris == 0 then
    show_error 'cannot restart: no URIs found for this task'
    return true
  end

  local task_nm = task_name(task)
  lc.confirm {
    title = 'Restart aria2 Task',
    prompt = 'Restart download "' .. task_nm .. '"?',
    on_confirm = function()
      api.remove(task.gid, task.status, function(_, remove_err)
        if remove_err then
          show_error(remove_err)
          return
        end
        api.add_uri(table.concat(uris, '\n'), function(gid, add_err)
          if add_err then
            show_error(add_err)
            return
          end
          refresh_after_action('download restarted: ' .. task_nm)
        end)
      end)
    end,
  }
  return true
end

function M.task_actions()
  local task = M.hovered_task()
  if not task then return false end

  local options = {}
  if M.can_open(task) then
    table.insert(options, {
      value = 'open',
      display = line { span('Open file', 'cyan') },
    })
  end
  if M.can_pause(task) then
    table.insert(options, {
      value = 'pause',
      display = line { span('Pause task', 'yellow') },
    })
  end
  if M.can_resume(task) then
    table.insert(options, {
      value = 'resume',
      display = line { span('Resume task', 'green') },
    })
  end
  if M.can_restart(task) then
    table.insert(options, {
      value = 'restart',
      display = line { span('Restart download', 'lightred') },
    })
  end
  if M.can_remove(task) then
    table.insert(options, {
      value = 'remove',
      display = line { span('Remove task', 'red') },
    })
  end

  if #options == 0 then
    show_info 'no available actions for selected task'
    return true
  end

  deck.select({
    prompt = 'Select aria2 action',
    options = options,
  }, function(choice)
    if choice == 'open' then
      M.open_task_file(task)
      return
    end
    if choice == 'pause' then
      M.pause_hovered_task()
      return
    end
    if choice == 'resume' then
      M.resume_hovered_task()
      return
    end
    if choice == 'restart' then
      M.restart_hovered_task()
      return
    end
    if choice == 'remove' then M.remove_hovered_task() end
  end)
  return true
end

return M
