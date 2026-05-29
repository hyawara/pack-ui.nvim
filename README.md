# pack-ui.nvim

一个面向 Neovim 0.12+ 的小型 `vim.pack` 管理器 UI。

使用原生 Neovim 悬浮窗口，首次渲染通过 `vim.pack.get(nil, { info = false })` 快速读取包数据。Git 更新计数异步采集并在刷新或包变更前一直缓存。

本仓库刻意以"小型可读插件"的方式组织代码。目标不仅是能跑，还要展示一个 Neovim 插件如何把命令入口、数据加载、UI 状态、渲染和副作用分开。

## 环境要求

- Neovim 0.12+
- Git

## 安装

```lua
vim.pack.add({
    'https://github.com/hyawara/pack-ui.nvim',
})
```

## 使用

```vim
:PackUI
```

## 按键

| 按键 | 动作 |
| --- | --- |
| `g` | 打开选中插件的 GitHub 仓库 |
| `j` / `k` | 上下导航插件列表 |
| `U` | 更新全部插件 |
| `u` | 更新选中的插件 |
| `x` | 删除选中的插件 |
| `r` | 刷新列表 |
| `<CR>` | 展开/收起选中插件的行内详情 |
| `q` | 关闭 |

## 更新行为

- `U` 更新全部插件，`u` 只更新选中的插件。
- 已更新的插件会显示在独立的"Updated"区域，视觉强调更强，且自动展开最近的提交记录。
- 更新或刷新进行中时，顶栏会显示紧凑的状态指示。

## 布局

PackUI 使用单个悬浮窗口 + 懒加载行内详情（类似 lazy.nvim）。

- **顶部**: 分组按键提示和更新/刷新状态指示器
- **Updated 区域**（可选）: 上次更新改动的插件，最近提交自动展开
- **All Plugins 区域**: 完整插件列表，包含 `NAME STATUS VERSION` 三列
- **`<CR>`** 展开/收起的详情在首次展开时构建，后续不再重复计算
- **自适应宽度**: 窗口宽度跟随内容，不使用固定的百分比

运行测试：

```sh
make test
```

## 架构

- `plugin/packui.lua` 只定义 `:PackUI` 命令。
- `lua/packui/init.lua` 连接 source、actions 和 UI。
- `lua/packui/source/` 是数据层。它从 `vim.pack` 或 lock file 读取数据，把原始数据建模为稳定形状，并缓存异步更新计数。
- `lua/packui/ui/state.lua` 拥有 UI 状态，按插件名（而非屏幕行号）管理选中。
- `lua/packui/ui/render.lua` 是纯渲染层。它把状态转为文本行、高亮和插件行导航目标。
- `lua/packui/ui/controller.lua` 处理所有副作用：键位映射、刷新、更新回调、窗口生命周期和异步 git 历史加载。
- `lua/packui/win.lua` 只包含底层的悬浮窗口辅助函数。

最重要的教学点：渲染行为不再决定逻辑。行为先更新 state，渲染层再从 state 派生出屏幕内容。

## 学习路径

如果你是从 Java 转 Lua 的开发者，请按以下顺序阅读项目：

1. `plugin/packui.lua`：命令入口。
2. `lua/packui/init.lua`：依赖注入。
3. `lua/packui/source/init.lua` 和 `lua/packui/source/model.lua`：外部/编辑器数据如何变成插件项模型。
4. `lua/packui/ui/state.lua`：UI 记住了什么。
5. `lua/packui/ui/render.lua`：状态如何变成文本和高亮。
6. `lua/packui/ui/controller.lua`：副作用存在哪里。

如果你已经熟悉 MVC 或 presenter 模式的 UI 代码，大致对应关系如下：

- `source/*` = 数据仓库 + 映射器
- `ui/state.lua` = 状态模型
- `ui/render.lua` = 视图模型渲染器
- `ui/controller.lua` = 控制器 / 协调器

## 项目结构

```text
plugin/packui.lua               命令入口
lua/packui/init.lua             模块连接
lua/packui/actions.lua          更新/删除/打开动作
lua/packui/ui.lua               UI 门面
lua/packui/ui/controller.lua    有状态的 UI 编排
lua/packui/ui/render.lua        纯渲染与详情文本
lua/packui/ui/state.lua         UI 状态与选择规则
lua/packui/win.lua              窗口和缓冲区辅助
lua/packui/utils.lua            通知与 URL 打开
lua/packui/source/init.lua      包列表 API
lua/packui/source/model.lua     包数据规范化
lua/packui/source/cache.lua     异步更新计数缓存
tests/packui_native_ui_spec.lua 交互场景测试
DESIGN.md                       架构维护说明
```
