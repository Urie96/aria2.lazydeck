# aria2.lazycmd

aria2 JSON-RPC 客户端插件，提供下载任务浏览、基础任务操作和新增下载。

## 功能

- 一级目录：`未完成`、`已完成`
- `未完成`：合并显示 `aria2.tellActive`、`aria2.tellWaiting`，以及 `aria2.tellStopped` 中状态为 `error` 的任务
- `未完成` 列表按状态排序，`下载中` 任务排在最上面，其次是 `等待中`、`暂停`、`失败`
- `已完成`：显示 `aria2.tellStopped` 中最近的已完成任务
- 右侧预览展示 GID、进度、速度、ETA、文件路径、错误信息
- 支持新增 URL / magnet 下载
- 支持暂停、恢复、删除任务
- 在已完成任务上可直接打开下载文件
- `R`：清缓存并刷新
- 本地 RPC 端口未启动时可自动在后台拉起 `aria2c`

## 配置

在 `~/.config/lazycmd/init.lua` 中配置：

```lua
{
  dir = 'plugins/aria2.lazycmd',
  config = function()
    require('aria2').setup {
      rpc_url = os.getenv 'ARIA2_RPC_URL',
      rpc_secret = os.getenv 'ARIA2_RPC_SECRET',
      page_size = 200,
      stopped_fetch_size = 400,
      auto_start = true,
      auto_start_delay = 1,
      download_dir = nil, -- nil means current working directory
      keymap = {
        enter = '<enter>',
        actions = 'a',
        open_file = 'o',
        pause = 'p',
        resume = 'r',
        delete = 'dd',
        add = 'n',
        refresh = 'R',
      },
      -- 可选：覆盖默认启动命令
      -- start_cmd = { 'aria2c', '--enable-rpc=true', '--daemon=true' },
    }
  end,
},
```

## 环境变量

- `ARIA2_RPC_URL`，默认 `http://127.0.0.1:6800/jsonrpc`
- `ARIA2_RPC_SECRET`，对应 aria2 `--rpc-secret`

## 自动启动

- 仅当 `rpc_url` 指向本机地址时才会自动启动 `aria2c`
- 默认启动命令会带上 `--enable-rpc=true`、`--daemon=true` 和匹配 `rpc_url` 的监听端口
- `download_dir` 可指定默认下载目录；为 `nil` 时使用启动 `lazycmd` 时的当前工作目录
- 如果设置了 `rpc_secret`，启动时会自动附加 `--rpc-secret`
- 可通过 `auto_start = false` 关闭
- 可通过 `start_cmd = {...}` 覆盖默认启动命令

## 键位

- 所有动作都使用 entry 级 keymap，而不是注册全局 `main` keymap
- `preview` 和 `keymap` 都通过 entry metatable 动态提供，不直接挂在每个 entry 表上
- 默认键位可通过 `setup { keymap = { ... } }` 覆盖
- `enter`
  - 在一级目录上进入状态列表
  - 在任务上打开动作菜单
- `actions`：打开当前任务的动作菜单
- `add`：新增下载，输入 URL 或 magnet 链接
- `open_file`：打开已完成任务对应文件
- `pause`：暂停当前任务
- `resume`：恢复当前任务
- `delete`：删除当前任务
- `refresh`：清缓存并刷新

## 说明

- 插件通过 aria2 JSON-RPC 获取和操作下载任务
- 新增下载当前使用 `aria2.addUri`，适合 HTTP/HTTPS/FTP/magnet 等 URI
- 删除运行中/等待中任务使用 `forceRemove`，删除已完成任务使用 `removeDownloadResult`
- 恢复操作只对 `paused` 状态任务调用 `aria2.unpause`，不会对普通 `waiting` 或 `error` 任务显示
- `已完成` 列表会从 `tellStopped` 中筛选最近完成的任务

## 结构

- `aria2/init.lua`: UI、列表渲染、预览和键位绑定
- `aria2/config.lua`: 配置读取和归一化
- `aria2/api.lua`: aria2 JSON-RPC 请求、缓存和写操作
- `aria2/actions.lua`: 条目动作、刷新和下载新增
- `aria2/preview.lua`: 条目预览渲染
- `aria2/metas.lua`: 通过 metatable 注入 entry 级 `preview` 和 `keymap`
