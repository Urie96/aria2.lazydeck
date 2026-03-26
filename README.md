# aria2.lazycmd

aria2 JSON-RPC 客户端插件，提供下载任务浏览、基础任务操作和新增下载。

## 功能

- 一级目录：`下载中`、`等待中`、`已完成`
- `下载中`：显示 `aria2.tellActive`
- `等待中`：显示 `aria2.tellWaiting`
- `已完成`：显示 `aria2.tellStopped` 中最近的已完成任务
- 右侧预览展示 GID、进度、速度、ETA、目录、文件路径、错误信息
- 支持新增 URL / magnet 下载
- 支持暂停、恢复、删除任务
- 在已完成任务上可直接打开下载文件
- `R`：清缓存并刷新

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
      cache_ttl = 3,
    }
  end,
},
```

## 环境变量

- `ARIA2_RPC_URL`，默认 `http://127.0.0.1:6800/jsonrpc`
- `ARIA2_RPC_SECRET`，对应 aria2 `--rpc-secret`

## 键位

- `Enter`
  - 在一级目录上进入状态列表
  - 在任务上打开动作菜单
- `a`：打开当前任务的动作菜单
- `n`：新增下载，输入 URL 或 magnet 链接
- `o`：打开已完成任务对应文件
- `p`：暂停当前任务
- `r`：恢复当前任务
- `dd`：删除当前任务
- `R`：清缓存并刷新

## 说明

- 插件通过 aria2 JSON-RPC 获取和操作下载任务
- 新增下载当前使用 `aria2.addUri`，适合 HTTP/HTTPS/FTP/magnet 等 URI
- 删除运行中/等待中任务使用 `forceRemove`，删除已完成任务使用 `removeDownloadResult`
- `已完成` 列表会从 `tellStopped` 中筛选最近完成的任务

## 结构

- `aria2/init.lua`: UI、列表渲染、预览和键位绑定
- `aria2/config.lua`: 配置读取和归一化
- `aria2/api.lua`: aria2 JSON-RPC 请求、缓存和写操作
