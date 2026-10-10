# Windows 构建

普通使用请下载 Release 的便携 ZIP；下列步骤用于开发与重新打包。

1. 安装 Windows 64 位 MinGW-w64，并让 `gcc.exe` 出现在 PATH 中。
2. 在项目根目录运行 `./setup-build.ps1`。它下载官方 Godot 4.2.2 Windows 编辑器，并从 `v0.1.0` Release 提取与当前 LuaAPI 匹配的运行时模板；不会覆盖已经存在的工具。
3. 运行 `./build.ps1`。产物位于 `dist/GriddyTranslate`，分享 ZIP 位于 `packages/GriddyTranslate-Windows.zip`。

Godot 编辑器位于 `tools/godot/Godot_v4.2.2-stable_win64.exe`。运行时模板位于 `tools/windows-runtime-template.exe`。发布所用模板包含 debug 特性，因此必须使用 export-debug 与相邻的 Lua debug DLL。

构建脚本设置仅用于当前进程树的 RTSS 兼容变量，编译原生启动器，再执行导出应用的无界面回归测试与有界面渲染测试。测试使用 `--test`，不会读取或覆盖日常偏好设置。图形测试需要能够运行 Vulkan 的桌面环境和网络，截图与日志放在 `qa/`。

构建还会验证真实鼠标滑块拖动、键盘精调、在线原文/译文读音、快捷键路由和翻译请求替换。性能回归覆盖分段限制、最多两段并发、按序拼接、重复请求合并、取消唤醒及读音地址/音频缓存。若日常应用仍在目标目录运行，脚本会拒绝覆盖它，保护尚未保存的内存文本；可运行 `./build.ps1 -OutputDirectory 'dist\GriddyTranslate-update'` 在另一个目录完成测试并生成相同便携 ZIP。

完整构建包含 14 组检查。主题渲染检查覆盖 18 个附带主题的真实选区截图、重复词高亮、连续预览的 CPU 耗时与帧间隔；菜单检查验证菜单与按钮同帧运动、相对位置稳定、窗口边界及其他界面动画。启动与换行检查覆盖异步加载、字体与音频延迟加载、开屏结束与聚焦、原文不变、软换行宽度和译文布局。

构建还验证备用开屏的跳过/关闭，以及真实便携启动器的自然结束、跳过、关闭三条路径。原生启动器用 Windows WIC 解码随包提供的 `native-startup.frames`（Full HD、330 帧），先绘制动画再启动引擎；画布首帧完成后才退场。完整 logo 至少实际显示半秒，所有结束方式均有 0.45 秒退场。启动及退场时序写入隔离的 QA 输出，并核对本次启动与子进程 ID。独立更新目录生成的 ZIP 仍使用 `GriddyTranslate/` 顶层目录。

只修改启动握手并且其他功能已在此前的完整构建通过时，可加 `-StartupOnly` 重新导出并执行全部六条启动路径；manifest 会记录 `verification: startup`，默认构建仍执行完整检查。没有测试的输出不会标记为已验证。

Godot 资源已导出并通过启动检查，后续仅修改原生启动器时，可使用 `-LauncherOnly` 复用该目录的 runtime/PCK，只编译启动器并检查原生自然结束、跳过与关闭三条路径，随后重新打包。manifest 记录 `verification: native-startup`。自然结束检查关闭原生 PNG 截图，避免压缩截图时暂停 UI 影响性能记录；退出后的引擎截图仍保留。

启动窗口从引擎创建时就无边框，轻量场景加载偏好后选择最终窗口样式。主画布使用 expand，原生与备用开屏按比例铺满。启动器用四个缓冲区后台解码，后台创建并启动运行时；窗口之间不建立跨进程所属关系，避免关联 GUI 队列。高精度等待计时器按帧期限更新；窗口缩放与动画帧缓存复用，退场不重复缩放整图。新编译需要链接 Windows 系统库 winmm，以兼容旧系统的计时器。

单词本回归覆盖本地 JSON 保存/恢复、重复合并、编辑/删除、持久删除记录、重试、快捷键和原版画布聚焦；Obsidian 回归仅写入 `qa/` 下的临时保管库，检查 Unicode、手写内容保留、改名移动、路径穿越/junction、原子替换及外部编辑冲突，并对经过路径校验的 QA 文件验证系统回收站操作。通知回归包含全部主题配色、长文字换行、进入/退出动画和生命周期。`--test` 使用独立单词本并关闭真实保管库自动同步；自动队列测试仅允许内存假后端。

本机的 LuaAPI 扩展有时会在导出结束后的卸载阶段使编辑器异常退出。脚本只在资源包完整保存、且实际导出应用的测试全部通过时接受产物；解析错误和测试失败均会终止构建。

`launcher.c` 使用程序自身所在目录寻找 runtime.exe。启动器依赖 Windows 系统 DLL；不依赖开发机器上的 Godot、Python 或 Codex。Obsidian 路径校验与原子更新使用 Windows 内置 PowerShell/.NET，不需另装开发运行时。不要把开发工具或 `qa/` 中的用户/测试数据放入 Release。

便携程序不会把个人数据写到解压目录：偏好在 `%APPDATA%\Godot\app_userdata\GriddyTranslate\translator.cfg`，词条在同目录的 `wordbook.json` 及恢复副本。Markdown 写入用户选择的保管库内 `GriddyTranslate/单词本`（可配置）；iCloud 同步由其客户端负责。Release ZIP 不应包含这些文件。
