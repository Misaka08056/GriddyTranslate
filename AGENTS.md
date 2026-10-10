# GriddyTranslate development

The user chose `D:\Documents\GriddyTranslate` as the permanent home for this project. Develop in `src`, build with `build.ps1`, and distribute `packages/GriddyTranslate-Windows.zip`. Do not develop in the older dated Codex checkout.

This is a direct GriddyCode Godot fork. Preserve its original canvas, HDR glow, fonts, shortcuts, animated overlays and focus behavior. Put new options in the existing Ctrl+comma settings panel; do not introduce persistent toolbars or a separate translator UI.

The portable entry point is a native Windows launcher (`tools/launcher.c`) that starts its adjacent `GriddyTranslate.runtime.exe` with scoped RTSS compatibility variables. Keep all executable/PCK/Lua DLL paths relative to the unpacked app folder, with no dependency on the user's GriddyCode installation.

Use the bundled Godot 4.2.2. The current custom template has debug features, so export-debug and the matching Lua debug DLL are required. A post-export LuaAPI unload crash is not proof of a working build: accept the output only after packaged regression and graphical update tests pass. Build scripts stop on parse/load errors.

Preserve user settings in the independent GriddyTranslate user-data directory and do not reset their text or preferences during updates. `--test` isolates preferences. Test logs, captures and unpacked validation live in `qa`. Keep the usage guide and repair explanation current.

Prepare and verify updates locally. The user now requires confirmation before any synchronization to `https://github.com/Misaka08056/GriddyTranslate` or GitHub Release publication. Do not push, update remote refs, upload assets or publish until the user approves the particular update. This supersedes the earlier automatic synchronization request. Exclude local tools, QA data, credentials, preferences and wordbook/vault contents from source commits and release packages.
