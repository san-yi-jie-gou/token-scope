# App Review 说明

TokenScope 是菜单栏应用，`LSUIElement` 已启用，因此不会常驻 Dock。

首次启动流程：

1. 应用会显示 macOS 文件选择器。
2. 请选择当前用户的个人主目录并点击“授权”。
3. TokenScope 仅扫描以下已知的本地用量目录：`.codex`、`.claude`、`.kimi-code`、`.pi`、`.local/share/opencode` 和 `.gemini`。
4. 左键点击菜单栏的 TokenScope 图标可显示或隐藏桌面组件；右键点击显示设置菜单。

如果审核设备上没有受支持 Coding Agent 的本地日志，应用会正常显示“今天还没有 Token 记录”。系统 Widget 需要主应用运行，通过 127.0.0.1:47833 读取聚合快照，不访问外部网络。

应用不需要登录，不提供内购，不收集数据，也不使用受管制加密。

发布前补充：审核联系人、公开支持 URL、隐私政策 URL，以及需要时附加的合成测试日志。
