# GriddyTranslate

把 GriddyCode 的文字画布改成翻译器：保留泛光、字体、镜头聚焦和滑入设置，通过快捷键操作，打开即可输入。

A keyboard-first translator forked from [GriddyCode](https://github.com/face-hh/griddycode), retaining its canvas, glow, animated panels and camera focus. Windows portable app with Youdao and MyMemory.

## 下载与运行

前往 [Releases](https://github.com/Misaka08056/GriddyTranslate/releases/latest)，下载 **GriddyTranslate-Windows.zip**，解压整个文件夹，再双击 **GriddyTranslate.exe**。

无需安装 GriddyCode、Godot、Python 或 Codex。需要 Windows 10/11 64 位、支持 Vulkan 的显卡及正常驱动；翻译和例句需要联网。运行时、资源包和 Lua DLL 必须与启动器放在同一目录。

## 操作

| 快捷键 | 作用 |
| --- | --- |
| Ctrl + Enter | 翻译 |
| Ctrl + Tab | 原文 / 译文切换 |
| Ctrl + , | 设置 |
| Ctrl + P / Ctrl + O | 播放原文 / 译文读音 |
| Ctrl + D | 收藏原文中选中的单词或完整短语 |
| Ctrl + B | 打开 / 收起单词本 |
| Ctrl + Shift + O | 在 Obsidian 打开单词本当前词条 |
| Ctrl + L | 选择语言 |
| Ctrl + T | 选择主题 |
| Ctrl + Shift + C | 复制译文 |
| Ctrl + 加号 / 减号 / 0 | 放大 / 缩小 / 恢复缩放 |
| F11 | 全屏 / 窗口切换 |
| Esc | 收起面板 / 返回原文 |

设置包含有道与 MyMemory 翻译来源、英译中例句、原文保留与下一行译文、自动换行与每行长度、开屏动画、泛光与 Shader、屏幕晃动、动画速度、缩放和全屏。开屏首页名称为 **cybertranslator**：原生启动器先播放 Full HD 动画，覆盖引擎初始化空白，编辑器在后方加载。沿用参考视频的完整约 11 秒节奏、红黑背景、锐角黄色字标和青色故障闪动；完整 logo 显示至少半秒且编辑器首帧完成后，任意键或点击可跳过。跳过与正常结束都有约 0.45 秒退场动画，也可在 Ctrl+, 设置中关闭。

主题预览复用现有控件和字体，避免反复重建造成掉帧；选中与重复单词高亮会保护文字对比度。展开选择菜单时，菜单跟随按钮在同一帧一起浮动，保持相对间隔；Ctrl+T 主题按钮位于原文输入左侧。启动只解析选中的系统字体，首次打开设置时才构建控件，开启音乐后才加载音频。

单词本沿用原画布的字体、泛光和面板动画。没有选区时收藏完整输入；长句提示先选词，不自动拆词。支持搜索、查看详情、编辑译文/标签/笔记、读音和删除，同一词与语言方向的重复收藏会合并。音标与真实词典例句在可获取时补充。

Obsidian 联动在现有设置中选择保管库、同步文件夹及自动同步开关。首次使用优先发现当前打开的保管库，支持 iCloud Drive；默认保存到保管库内的 `GriddyTranslate/单词本`，每词一篇 Markdown。后台更新保留手写笔记，删除本地词条会按同步设置将对应 Obsidian 文件移到系统回收站。删除失败或离线时保留待同步记录，支持重启后重试。详情与快捷键见使用说明。

自动翻译在停止输入约 0.5 秒后请求，手动翻译立即请求；更改文本会取消旧请求。长文本按服务限制分段，最多并行两段。有道读音复用翻译返回的对应语音地址，播放过的音频会在内存中缓存。

例句查询保留完整单词或短语，只显示包含对应词或完整短语的真实词典例句；长句与没有完整词条的输入不显示例句。例句先以乱码逐字出现，再恢复为英文和中文。语言列表按内容居中，并适配窗口与全屏。

![语言选择界面](docs/screenshots/languages.png)

详细操作见 [使用说明](src/使用说明.md)，已知问题的原因与修复见 [修复说明](docs/修复说明.md)。

原文和译文仅保存在内存中，关闭应用后不会保留；主动收藏的词条保存在 `%APPDATA%\Godot\app_userdata\GriddyTranslate\wordbook.json`，偏好设置在同目录的 `translator.cfg`。便携 ZIP 包含程序，个人单词本与设置位于本机用户目录。翻译请求会将文本发送给选中的服务；例句与收藏详情查询会发送完整词或短语给相应词典；读音快捷键将对应文本发送给有道语音服务。Obsidian 联动直接写入选定的本地保管库，iCloud 同步由 iCloud 客户端完成。有道公开体验接口及 MyMemory 免费服务的额度和可用性由服务方决定。

## 源码与构建

Godot 项目位于 `src/`，可用 Godot **4.2.2** 打开 `src/project.godot`。`src/Original/` 保留对照用的原版场景、脚本和插件，使用 `.gdignore` 排除导入。

Windows 构建需要 MinGW-w64 的 `gcc.exe` 已在 PATH 中。先准备固定版本的 Godot 和已验证的运行时模板，再运行构建脚本：

```powershell
.\setup-build.ps1
.\build.ps1
```

`setup-build.ps1` 从 Godot 官方发布下载 4.2.2，并从本项目首个 Release 提取运行时模板。脚本使用项目相对路径。构建会验证导出的应用，然后生成 `packages/GriddyTranslate-Windows.zip`。详见 [构建说明](tools/README.md)。

## 来源与许可

直接基于 [face-hh/griddycode](https://github.com/face-hh/griddycode) v1.2.2，原始提交 `4fb81e9d9e5974ee0c953998f27933042ed82f31`，原作者 FaceDevStuff / face-hh。GriddyTranslate 是个人维护的翻译分支。

保留原项目的 [Apache-2.0 许可](LICENSE) 和署名；Godot、LuaAPI 和字体等第三方组件的许可见 [tools/licenses](tools/licenses)。
