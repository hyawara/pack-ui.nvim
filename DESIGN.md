# 架构说明

## 设计目标

这个插件刻意保持小巧，但依然分离了职责，让维护工作不依赖一次性记住所有 Neovim API。

核心原则：

1. 命令入口保持简单。
2. 插件数据保持纯粹。
3. 渲染从状态派生，不做突变。
4. 副作用集中在控制器层。

## 数据流

完整的运行时流程：

1. `:PackUI` 调用 `require('packui').open()`。
2. `lua/packui/init.lua` 把 `source`、`actions`、`ui` 三个依赖一起注入。
3. `ui/controller.lua` 通过 `win.lua` 创建 `nui.popup` 弹窗和初始状态。
4. `source/init.lua` 从 `vim.pack.get()` 返回插件列表；如果数据库为空则回退到 lock file。
5. `ui/state.lua` 存取插件列表，以插件名作为选中标识。
6. `ui/render.lua` 把状态转换为缓冲区文本和高亮元数据（纯函数，不修改 state）。
7. `ui/controller.lua` 通过 `sync_render_state` 把渲染结果同步回状态，再应用高亮和光标。

核心规则：选择状态始终存储在 `selected_name` 字段里，而不是 `selected_line`。刷新时屏幕行号可能变化，但插件名不会，所以用名字比用行号安全得多。

## 模块边界

### `plugin/packui.lua`

只定义用户命令。零状态、零逻辑。

### `lua/packui/init.lua`

组合根。如果你以后想替换数据源或动作实现，从这个文件改起。

### `lua/packui/git.lua`

Git 异步门面。它用 `plenary.job` 运行 Git 命令，并把结果整理成 `{ code, stdout }`，控制器和缓存层不用直接关心 job 对象。

### `lua/packui/source/*`

数据层只回答一个问题："插件项长什么样？"

- `init.lua` 决定数据从哪来，并用 `plenary.path` 读取 lock file。
- `model.lua` 把 `vim.pack` 或 lock file 的原始数据映射为稳定的 item 结构。
- `cache.lua` 管理异步的更新计数缓存。

数据层不懂窗口、键位、光标位置——一个字都不该知道。

### `lua/packui/ui/state.lua`

这是新手最应该先读的 UI 文件。它回答了：

- state 里有哪些字段？
- 当前选中哪个插件？
- 更新过的插件列表如何重建？
- 刷新后哪些展开的详情需要保留？

### `lua/packui/ui/render.lua`

纯渲染层。不引用 `state.lua`，不做状态修改。

传入 state 表，返回：

- 缓冲区文本行
- 行级高亮元数据
- 每行的 item 映射
- 插件导航顺序
- 当前选中的行号（由 `compute_selected_line` 纯函数计算，不改 state）

当屏幕上效果不对时，从本文件查起。

### `lua/packui/ui/controller.lua`

只拥有副作用：

- 键位绑定
- 刷新编排
- 更新回调
- Git 提交历史加载
- 窗口生命周期

任何代码只要碰了 `vim.schedule`、按键绑定或 UI 生命周期，就应该在这个文件里。Git 进程本身放在 `git.lua`，窗口创建细节放在 `win.lua`。

### `lua/packui/win.lua`

窗口辅助层。它用 `nui.popup` 处理弹窗创建、挂载和卸载，控制器只保存 `main_popup`、`main_buf` 和 `main_win` 三个运行时引用。

## 维护规则

想让这个插件保持"可教学"，请遵守以下规则：

1. 不要把业务逻辑直接放进 `plugin/packui.lua`。
2. 不要把 Neovim 副作用放进 `source/*`。
3. 不要把渲染专用文本存到 item 对象上。
4. 在增加新的状态突变之前，优先考虑在 `ui/render.lua` 里加一个纯函数。
5. 如果 bug 是关于选择或刷新，先修状态模型，再改渲染器。

## 未来改进方向

以下项目是刻意预留的——它们在重构范围之外，但方向已经明确：

1. 为 `source/model.lua` 的 URL 正则添加单元测试。
2. 为 `ui/render.lua` 的快照输出添加单元测试。
3. 新建一个集成测试文件，专门覆盖更新/刷新竞态场景。
