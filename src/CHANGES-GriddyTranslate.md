# GriddyTranslate: independent translation fork

## 文字高亮、主题帧率与菜单稳定

- 修复 Rose Pine Moon 等主题的不透明重复单词高亮遮住文字；明确选中文字颜色，并保护当前行、选择与重复词背景叠加后的对比度。单词本编辑框也使用可读的选区配色。
- 主题预览不再重建设置列表；隐藏的界面在打开时更新，合并同一控件的样式更新。复用菜单行、行样式和已准备的字体，同一主题的预览与确认不重复加载。
- 提示弹窗先同步完成字体和坐标测量，再等待布局更新，避免快速替换提示时异步任务留下绘制资源并导致退出异常。
- 所有下拉菜单展开期间固定菜单和触发按钮，其他界面继续运动。收起时按钮平滑恢复；窗口缩放后重新适配，长列表的鼠标、滚动及键盘选择保留。

## 主题通知与删除同步

- 左上角通知改为无外框的直角卡片与左侧色条，使用当前主题的背景、文字与关键字强调色；新增滑入淡入和滑出淡出，长内容自适应换行，不拦截鼠标，新通知平滑替换旧通知。
- 本地删除现在同步到 Obsidian，按固定 ID 查找已改名或移动的笔记，将完整文件移入系统回收站。失败记录随单词本持久保存，重启后可重试；删除发生在后台，并处理新增尚未完成就删除的顺序。升级时可识别完整旧备份中的最近一次单词删除。

## 单词本与 Obsidian（本次更新）

- Ctrl+D 收藏选中单词或完整短语，Ctrl+B 在原画布呼出单词本；Enter 详情，Ctrl+E 编辑译文/标签/笔记，Ctrl+Enter 保存，Ctrl+P/O 播放所选原词/译文。重复收藏按词与语言方向合并；长句需先选词。有道词典可在后台补充可用音标与真实例句。
- 现有设置增加保管库、同步文件夹、自动同步与立即同步；首次选择优先发现 Obsidian 当前打开的库，支持 iCloud。默认库内路径为 `GriddyTranslate/单词本`，Ctrl+Shift+O 打开所选词条笔记。同步和查找均在后台执行。
- 每词一篇 Markdown，以固定 ID 追踪配置目录内的改名/移动。管理内容更新保留手写笔记、用户标题、未知 frontmatter 和 Obsidian 用户标签。Windows 使用原子 File.Replace 和最终 SHA256 冲突检查；拒绝普通文件碰撞、ID 副本、路径越界及重定向链接，允许 iCloud 占位文件；不变内容不重写。
- 主动收藏存入 `user://wordbook.json`，保存前验证，保留 `.bak` 和可能的 `.rollback` 恢复文件。主文件缺失可恢复完整副本；损坏文件保留并暂停改写。测试隔离单词本且不向真实库同步，便携 ZIP 不包含个人数据。

## Latest fixes and portable packaging

- Reduced automatic translation's typing pause from 1.2s to 0.5s. Manual translation starts immediately; edits/provider/language changes cancel obsolete work, and generation checks prevent late results from changing newer requests.
- Replaced Youdao's inherited 450-byte splitting with POST requests of at most 1000 UTF-16 units, retaining MyMemory's 450-byte limit. Up to two ordered chunk requests run concurrently; matching in-flight requests are coalesced.
- Reuse exact source/translation Youdao speech URLs with a bounded, expiring memory registry. Sentence speech skips the frequently failing dictionary attempt; played audio is cached in memory. No speculative speech requests.

- Stabilized only the dragged slider and its value in screen space, including unfinished camera-focus transitions, while the camera and all other UI continue animating. Release smoothly returns the controls to their row; Escape/rebuild/window-focus loss also restores them without changing the saved motion preference. Extended tracks and preserved keyboard step adjustments.
- Ctrl+P speaks original input; Ctrl+O speaks translated text in the language of that result. Language selection remains on Ctrl+L.
- Redesigned theme and settings selection lists in screen space with pixel-sized MSDF text, aligned anchors, theme colors and bounded scrolling. Preserved the old native menu and reference screenshot in `Original/SelectionMenuBeforeRedesign`.
- Made notice overlays ignore mouse input so their invisible fullscreen roots cannot block settings after a theme or network message appears.

- Removed keyword extraction from example lookups. Full phrases stay intact across providers/fallbacks; exact dictionary entries and whole-phrase sentence matches prevent sentence input from producing unrelated examples.
- Replaced the finite world-space background with a viewport-sized background canvas, fixing the gray strip at minimum zoom.
- Centered the language picker using its measured content and viewport size, keeping the last languages and key hints visible in windowed/fullscreen modes.

- Fixed missing Youdao examples by reading `blng_sents_part.sentence-pair`, dictionary object/array variants, and a real Wiktionary fallback. No generated examples or fabricated translations.
- Examples now share CodeEdit's world-space camera and use fixed glyph positions during scrambling, avoiding transform drift and random reflow.
- Added screen-motion switch, adjustable settings animation speed, source-plus-next-line translation, zoom slider/shortcuts, and fullscreen setting/F11 with persisted state.
- Repaired inherited VHS/CRT overexposure (brightness 6 -> 1.08) and overlay UV handling. Shader switches are mutually exclusive.
- Corrected caret-blink labels and numeric preference types. Camera following uses a single continuous response rather than overlapping per-frame tweens; panel navigation and original zoom/framing remain.
- Migrated development to `D:\Documents\GriddyTranslate`. Portable ZIP includes a native launcher, Godot runtime, PCK and Lua DLL; no GriddyCode installation or Codex environment is required.

Personal Windows translation fork of GriddyCode v1.2.2, commit `4fb81e9d9e5974ee0c953998f27933042ed82f31` from https://github.com/face-hh/griddycode.

The app directly uses the original `Scenes/editor.tscn` Node2D/CodeEdit/Camera2D layout. Original scripts, scenes and addons are retained in `Original/` for comparison, with `.gdignore` preventing duplicate imports. `Original/FirstTranslator` preserves the superseded two-column implementation.

## Preserved from GriddyCode

- Original camera framing, floating movement, caret focus and music pulse behavior form the foundation, with the stability fixes and configurable controls listed above.
- Settings use Ctrl+comma, the original 270-unit slide and original 0.2-second slide/fade plus 1-second focus defaults. The speed slider scales their durations.
- Original HDR environment: glow enabled, threshold 0, original blend mode; original `theme.tres`, Fira Code MSDF import settings, 18 Lua palettes, Sunlight and music. VHS/CRT preserves the effect with corrected brightness and coordinates.
- Original theme picker, settings widgets and help-panel animation. Shortcut dispatch is centralized to prevent double handling.

## Translation changes

- The original canvas starts empty. Ctrl+Enter translates into the same canvas; Ctrl+Tab returns to the original. No permanent toolbar or second pane.
- Original file-picker interaction becomes language selection. Source and target commit together; Escape cancels unfinished choices.
- Settings offer MyMemory and Youdao. Youdao uses its public keyless experience endpoint, without private API credentials. Sources have separate caches and do not silently fall back to one another.
- Optional English-to-Chinese examples use Youdao bilingual dictionary examples in Youdao mode, or Free Dictionary/Wiktionary plus MyMemory in MyMemory mode. Garbage characters appear first and resolve left to right. Returning to source, disabling examples or changing source invalidates pending examples.
- The settings-side jumping-cat animation is removed at the user's request. Panel movement and camera focus remain original.
- Chinese/emoji font fallbacks and bundled Nerd Font symbols avoid missing glyphs. The original default font is represented in the existing dropdown. Font choice persists by name.
- Canvas text stays in memory; preferences are saved to `user://translator.cfg` and explicitly collected vocabulary to `user://wordbook.json`. Translation sends text to the selected service; examples and vocabulary metadata query the relevant dictionary. Obsidian synchronization writes only the configured local managed folder.

## Windows runtime and build

Use Godot 4.2.2 and the matching LuaAPI addon. The local template is the stripped runtime from the official GriddyCode Windows release. It has debug features, so this build uses `--export-debug` and ships `libluaapi.windows.template_debug.x86_64.dll` beside the exe. A standard release template can instead use `--export-release` with the matching release DLL.

The original LuaAPI addon can make the editor/export process exit abnormally after `savepack: end` on this PC. The output was validated by running the exported application: regression, live translation, rendering, camera/shortcut and example-animation tests passed. Accept a build only after runtime checks, not merely because a PCK exists.

The native `GriddyTranslate.exe` launcher sets `DISABLE_RTSS_LAYER=1` and `VK_LOADER_LAYERS_DISABLE=VK_LAYER_RTSS` only for the launched process tree. It uses relative paths and has only Windows system DLL dependencies.

Tests run through the normal scene:

```powershell
$env:DISABLE_RTSS_LAYER='1'
$env:VK_LOADER_LAYERS_DISABLE='VK_LAYER_RTSS'
godot --path . -- --test --regression-test
godot --path . -- --test --visual-test
godot --path . -- --test --examples-test
godot --path . -- --test --effects-test
godot --path . -- --test --wordbook-storage-test
godot --path . -- --test --obsidian-test
godot --path . -- --test --wordbook-ui-test
godot --path . -- --test --wordbook-test
```

For graphical tests set `GRIDDY_TEST_OUTPUT` to an absolute capture directory. `--test` isolates preferences. Tests also run from the exported exe. Actual Vulkan checks on the GTX 1080 supplement headless tests.

Original repository, engine and bundled Symbols Nerd Font licenses are included.
