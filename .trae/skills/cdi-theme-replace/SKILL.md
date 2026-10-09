---
name: "cdi-theme-replace"
description: "给 CrystalDiskInfo 换品牌主题（背景/立绘/版权/exe名/窗口标题），默认 DeepSeek，支持任意品牌。用户说'换背景/换立绘/换主题/换CDI品牌/重新生成/DeepSeek/GPT/Claude/Kimi'时触发。"
---

# CrystalDiskInfo 换肤 + 品牌重命名 Skill（通用）

## 一句话总结

把原版 CrystalDiskInfo（9.9.2 Shizuku Edition）改成**任意 AI 品牌**的定制版：exe 名、窗口标题、版权条、硬盘状态立绘、背景全换。默认是 DeepSeek，但**换品牌只改一个变量**（GPT / Claude / Kimi / 其他都行）。

## 触发场景

- "帮我换一下 CDI 的背景/立绘/主题"
- "把 CrystalDiskInfo 改成 DeepSeek / GPT / Claude / Kimi"
- "重新生成 DeepSeek X64 / GPT X64"
- "给 CDI 换个品牌名/换皮肤"

## 前置条件（目录结构）

```
workspace-root/
  apply_theme.ps1            ← 主脚本（自动发现 新版CDI/）
  新版CDI/                    ← CDI 程序本体（脚本自动查找 .bak 定位）
    {品牌}64S.exe            ← 脚本生成（如 DeepSeek64S.exe / GPT64S.exe）
    {品牌}32S.exe
    {品牌}A64S.exe
    DiskInfo64S.exe.bak      ← 原版 EXE（永久备份，绝不修改）
    DiskInfo32S.exe.bak
    DiskInfoA64S.exe.bak
    DiskInfo.ini
    images/                   ← 用户自定义素材（文件名固定，脚本从这里读）
      背景.jpg
      立绘1_健康.jpg
      立绘2_注意.jpg
      立绘3_损坏.jpg
      立绘4_未知.jpg
    CdiResource/themes/       ← 32 个 Shizuku 主题（脚本修改其中 PNG）
    License/                  ← 运行时依赖
    Smart/                    ← 运行时依赖
```

## 核心脚本

**`apply_theme.ps1`**（workspace-root 下，UTF-8 BOM）

### 换品牌 = 只改一个变量

脚本顶部有个显眼的 `★ 品牌设置` 区块：

```powershell
$brand   = 'DeepSeek'   # ← 改这里就行
$brandCN = [string][char]0x6DF1 + ... # 品牌中文名（版权条里显示）
```

改 `$brand` 后，以下全部自动跟着变：
- exe 文件名：`DeepSeek64S.exe` → `GPT64S.exe` / `Claude64S.exe` / `Kimi64S.exe`
- 窗口标题：`DeepSeek X64` → `GPT X64` / `Claude X64` / `Kimi X64`
- 版权条文字：`DeepSeek 深度求索` → `GPT 生成式预训练` 等（`$brandCN` 改中文部分）

> 素材文件名（背景.jpg / 立绘1~4）**不随品牌变**，任何品牌都用同一套文件名，方便复用。

### 用法

```powershell
# 1. 确认 新版CDI/images/ 里素材齐了（背景+4立绘）
# 2. （想换品牌）改 apply_theme.ps1 顶部的 $brand
# 3. 运行
powershell -NoProfile -ExecutionPolicy Bypass -File apply_theme.ps1
# 4. 以管理员身份运行：新版CDI/{品牌}64S.exe
#    ⚠ WorkingDirectory 必须是 新版CDI/（exe 和资源不能分开！）
```

### 脚本做了啥（4 步）

| Step | 内容 | 风险 |
|------|------|------|
| **0** | 杀残留进程 | — |
| **1** | 从 `.bak` 原版精准 patch exe（**6 步**安全 patch），输出到 `新版CDI/` | 低（每步限量扫描 + P6 魔术字节验证） |
| **2** | 加载 `images/` 素材 | — |
| **3** | 遍历 32 个 Shizuku 主题，替换 608 张 PNG（背景+立绘+版权条） | 低（GDI+） |
| **4** | DiskInfo.ini 幂等清理 `[Layout]` + 加 `SwapPanel="0"` 锁定布局 | — |

## exe 6 步安全 patch（核心！不能乱改！）

每步都**严格限定扫描范围**（CODE 段 < 2MB，RES 段 > 2MB），每步都先**验证命中数量**，超过阈值自动跳过。

| Step | 扫哪个段 | 扫什么串 | 替换成 | 目的 | 命中数 |
|------|---------|---------|--------|------|--------|
| **P1** | CODE (<2MB) | `Crystal` + 后续 null | `{品牌} X64` + null | 换 CODE 段里的 Crystal 标识 | 14-15 |
| **P2** | RES (>2MB) | `CrystalDiskInfo Shizuku Edition` | `{品牌} X64` | 换资源段 ProductName | 2 |
| **P3** | CODE (<2MB) | `Shizuku Edition x64` 等 | 全 0 | 清窗口标题模板尾巴 | 2-4 |
| **P4** | RES (>2MB) | `9.9.2.0` | 全 0 | 清资源段版本号 | 2 |
| **P5** | CODE (<2MB) | `9.9.2`（先确认 ≤3 处） | 全 0 | 清 release 版本号 | 1 |
| **P6** | CODE (<2MB) | 函数首指令魔术字节 | 面板换边机器码 | 版权条点击 → 换边（替代随机换主题） | 1 |

> ⚠ 品牌名长度限制：P1/P2 是"等长替换"。`{品牌} X64` 必须短于原字符串 `CrystalDiskInfo Shizuku Edition`（31 字符）。任何常见品牌名（DeepSeek/GPT/Claude/Kimi/Grok/Mistral 等）都满足，**别用超长自定义名**。

**原理**：窗口标题是运行时由 `%PRODUCT% + %VERSION% + " Shizuku Edition x64"` 拼接的。P1 换 %PRODUCT%（CODE 硬编码），P2 换 RES 段 ProductName，P3 清模板尾巴，P4/P5 清版本号。全做完标题 = 干净的 `{品牌} X64`。

**P6 原理**：`OnBnClickedButtonCopyright()`（`IDC_BUTTON_COPYRIGHT=1099` 的 BN_CLICKED 处理函数）原版用 `rand()` 随机切换 Shizuku 主题。替换为 `m_CharacterPosition ^= 1; UpdateDialogSize();`，点击整个版权黑条 → 切换硬盘数据显示在左/右侧。三架构各有独立偏移和机器码，魔术字节验证防止 CDI 版本升级后写错位置。

## 关键踩坑（必读！）

1. **exe 不能挪出 新版CDI/** → CDI 在 exe **自己所在目录**（ModulePath）找资源，挪出去就弹 "Not Found Graph.html"
2. **CODE 和 RES 分界 = 2MB** → CrystalDiskInfo 9.9.x 代码段全在 2MB 内，资源段从 ~2.8MB 开始。跨段乱 patch 会搞坏 PE 导入表（报"无法定位程序输入点"）
3. **短字符串不能扫全文件** → `9.9.2`（10 字节 UTF-16）在 2.9MB 里撞 3000+ 处！必须先限定扫描范围，再确认命中数 ≤ 安全阈值
4. **资源段版本号是 `9.9.2.0`**（4 段），不是 `9.9.2`（3 段）
5. **原版 zip 里没有 Graph.html** → 不是 bug，原版就没这文件，忽略
6. **PowerShell 5 需要 UTF-8 BOM** → 脚本有中文路径/注释，无 BOM 会 GB2312 读取乱码
7. **中文文字渲染** → 版权条必须用 `Microsoft YaHei` 字体，中文用 Unicode 码点拼接（`[char]0x6DF1` 等）
8. **DiskInfo.ini 幂等** → Step 4 会清理重复的 `[Layout]` 段（历史版本只追加不去重，会堆到 9 个；现在跑多少遍都是 1 个）
9. **.bak 依赖** → `DiskInfo*S.exe.bak`（3 个原版 CrystalDiskInfo）是脚本硬依赖，不可删除；`{品牌}*S.exe.bak`（手动补丁快照）无脚本引用，可安全删除
10. **P6 魔术字节验证失败** → 说明函数偏移变了（通常是 CDI 版本升级），需要重新在 IDA/x64dbg 中定位函数入口、更新 `$funcOff`/`$magic`/`$patchBytes`

## 快速换图（不换品牌）

```powershell
# 素材放 images/ 覆盖原图，然后：
Get-Process DiskInfo*,CDIServer*,* -ErrorAction SilentlyContinue | Stop-Process -Force
powershell -NoProfile -ExecutionPolicy Bypass -File .\apply_theme.ps1
```