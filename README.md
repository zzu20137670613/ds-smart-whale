# ds-smart-whale

A lightweight disk health monitor, originally built for a DeepSeek whale girl. （一个轻量级的硬盘健康监控工具，最初是为一位DeepSeek鲸鱼娘量身定制的。）

Based on CrystalDiskInfo 9.9.2 Shizuku Edition, this tool replaces all Shizuku theme assets (backgrounds, character illustrations, copyright bar) with your own brand. Change brand by editing a single variable — DeepSeek, GPT, Claude, Kimi, or any name you like.

## Quick Start

1. Download **CrystalDiskInfo 9.9.2 Shizuku Edition** and extract it to `新版CDI/`
2. Rename the original exes as `.bak`:
   - `DiskInfo64S.exe` → `DiskInfo64S.exe.bak`
   - `DiskInfo32S.exe` → `DiskInfo32S.exe.bak`
   - `DiskInfoA64S.exe` → `DiskInfoA64S.exe.bak`
3. Put your custom images in `images/` (file names must match exactly):
   - `背景.jpg` — background
   - `立绘1_健康.jpg` — disk healthy
   - `立绘2_注意.jpg` — disk caution
   - `立绘3_损坏.jpg` — disk bad
   - `立绘4_未知.jpg` — disk unknown
4. Edit `apply_theme.ps1` top section — change `$brand` and `$brandCN` to your brand name
5. Run:
   ```
   powershell -NoProfile -ExecutionPolicy Bypass -File apply_theme.ps1
   ```
6. Launch the generated exe as Administrator from `新版CDI/`

## Directory Layout

```
ds-smart-whale/
  apply_theme.ps1          ← one-click branding script
  HANDOFF.md               ← detailed handoff doc (for AI / new contributors)
  README.md                ← you are here
  images/                  ← put your custom images here
    背景.jpg
    立绘1_健康.jpg
    立绘2_注意.jpg
    立绘3_损坏.jpg
    立绘4_未知.jpg
  .trae/skills/            ← AI skill definition (optional)
  新版CDI/                 ← put CrystalDiskInfo here (not tracked by git)
    DiskInfo64S.exe.bak    ← original EXE backups
    DiskInfo32S.exe.bak
    DiskInfoA64S.exe.bak
    CdiResource/           ← Shizuku theme resources
    License/ Smart/        ← runtime dependencies
```

## Features

- **One-variable brand switch** — change `$brand` in `apply_theme.ps1` and everything follows: exe name, window title, copyright bar text
- **608 PNG assets auto-replaced** across 32 Shizuku themes (backgrounds, 4 status illustrations, copyright bar)
- **Clean window title** — no version numbers, no "Shizuku Edition" tail
- **Panel swap on copyright bar click** — click the entire black copyright bar to flip disk data between left and right sides
- **Idempotent** — run the script as many times as you want, no duplicate config entries

## License & Credits

- CrystalDiskInfo is © Noriyuki Miyazaki (hiyohiyo). This project only provides tooling to customize theme assets; it does not distribute CDI binaries.
- This project is open-source. Use it to create your own AI-branded disk monitor.

## For AI Agents

If you are an AI agent helping with this project, read `HANDOFF.md` and load the `cdi-theme-replace` skill from `.trae/skills/cdi-theme-replace/SKILL.md`. Both documents contain all the context needed to work on this codebase with zero prior experience.