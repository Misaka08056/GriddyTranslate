# Windows 构建

普通使用请下载 Release 的便携 ZIP；下列步骤用于开发与重新打包。

1. 安装 Windows 64 位 MinGW-w64，并让 `gcc.exe` 出现在 PATH 中。
2. 在项目根目录运行 `./setup-build.ps1`。它下载官方 Godot 4.2.2 Windows 编辑器，并从 `v0.1.0` Release 提取与当前 LuaAPI 匹配的运行时模板；不会覆盖已经存在的工具。
3. 运行 `./build.ps1`。产物位于 `dist/GriddyTranslate`，分享 ZIP 位于 `packages/GriddyTranslate-Windows.zip`。

Godot 编辑器位于 `tools/godot/Godot_v4.2.2-stable_win64.exe`。运行时模板位于 `tools/windows-runtime-template.exe`。发布所用模板包含 debug 特性，因此必须使用 export-debug 与相邻的 Lua debug DLL。

构建脚本设置仅用于当前进程树的 RTSS 兼容变量，编译原生启动器，再执行导出应用的无界面回归测试与有界面渲染测试。测试使用 `--test`，不会读取或覆盖日常偏好设置。图形测试需要能够运行 Vulkan 的桌面环境和网络，截图与日志放在 `qa/`。

本机的 LuaAPI 扩展有时会在导出结束后的卸载阶段使编辑器异常退出。脚本只在资源包完整保存、且实际导出应用的测试全部通过时接受产物；解析错误和测试失败均会终止构建。

`launcher.c` 使用程序自身所在目录寻找 runtime.exe。启动器依赖 Windows 系统 DLL；不依赖开发机器上的 Godot、Python、.NET 或 Codex。不要把开发工具或 `qa/` 中的用户/测试数据放入 Release。
