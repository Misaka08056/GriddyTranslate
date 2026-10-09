# 下拉菜单原版样式

这里保留 2026-10-09 本次下拉菜单重设计之前的主题选择场景和脚本，作为用户指定的“原版”参考。该版本使用 Godot 原生 OptionButton / PopupMenu；展开后会显示默认灰底和单选圆点，菜单位置及字体不随编辑器相机缩放正确匹配。

- `Scenes/theme_chooser.tscn`：原版主题选择按钮场景。
- `Scripts/theme_chooser.gd`：原版主题列表初始化脚本。
- `setting.tscn` 与 `settings_list.gd`：使用原生下拉菜单的设置行和配置逻辑。
- `original-menu.png`：用户提供的原版菜单截图。

它们是参考备份。当前开发使用 `src/Scripts/selection_menu.gd` 与 `src/Scripts/theme_chooser.gd`，不在本目录开发。上级 `Original/.gdignore` 保证备份不会作为运行脚本导入。
