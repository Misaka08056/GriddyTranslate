# GriddyTranslate development

Develop the Godot project in src. Use Godot 4.2.2; run setup-build.ps1 and build.ps1 from the project root. The Windows portable package is packages/GriddyTranslate-Windows.zip.

This is a direct GriddyCode fork. Preserve its original canvas, HDR glow, fonts, shortcuts, animated overlays and caret focus. Use the Ctrl+comma settings panel for new options, with no persistent toolbar.

Use export-debug and the matching Lua debug DLL with the verified runtime template. Accept an export only after packaged regression and graphical update tests pass. Keep runtime and launcher paths relative to the unpacked package.

Preserve preferences and in-memory user text. Tests use --test to isolate preferences. Keep logs, captures and local validation in qa. Update the usage guide and repair explanations when behavior changes. Do not commit build outputs, local tools, credentials or user preferences.

The user requires every completed, verified update to be synchronized to `https://github.com/Misaka08056/GriddyTranslate`, including the corresponding tested portable ZIP in GitHub Releases. This standing request authorizes future synchronization; do not ask for the same permission again. Exclude QA data, credentials, preferences and wordbook/vault contents from source commits and release packages.
