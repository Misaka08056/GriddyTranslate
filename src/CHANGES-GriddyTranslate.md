# GriddyTranslate: independent translation fork

## Latest fixes and portable packaging

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
- Text stays in memory; only preferences are saved to `user://translator.cfg`. Translation sends text to the selected service; examples query the relevant dictionary.

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
```

For graphical tests set `GRIDDY_TEST_OUTPUT` to an absolute capture directory. `--test` isolates preferences. Tests also run from the exported exe. Actual Vulkan checks on the GTX 1080 supplement headless tests.

Original repository, engine and bundled Symbols Nerd Font licenses are included.
