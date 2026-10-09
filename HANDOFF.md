# CrystalDiskInfo 品牌换肤 交接文档（给下一个 AI）

> 读完这个文档 + 触发 `.trae/skills/cdi-theme-replace/SKILL.md`，你就能 0 经验接手这个项目。
> 本项目默认品牌为 DeepSeek，但已泛化为**任意品牌通用**（GPT / Claude / Kimi / Grok / Mistral……换品牌只改一个变量）。

---

## 0. 项目目标（一句话）

把原版 CrystalDiskInfo 9.9.2 Shizuku Edition 重品牌化为指定品牌（默认 DeepSeek），同时替换所有 Shizuku 主题的背景图、磁盘状态立绘、版权条。窗口标题必须是**干净的 `{品牌} X64`**（无 Shizuku、无版本号、无尾巴）。

## 0.5 换品牌 = 改一个变量

脚本顶部有 `★ 品牌设置` 区块：

```powershell
$brand   = 'DeepSeek'   # ← 只改这里
$brandCN = [string][char]0x6DF1 + ...  # 中文名（版权条显示）
```

改 `$brand` 后自动联动：exe 文件名（`{品牌}64S.exe`）、窗口标题（`{品牌} X64`）、版权条（`{品牌} {中文名}`）。
素材文件名固定（背景.jpg / 立绘1~4），不随品牌变，任何品牌复用同一套图。

⚠ 唯一约束：`{品牌} X64` 必须短于原字符串 `CrystalDiskInfo Shizuku Edition`（31 字符）。常见品牌名都满足。

## 1. 为什么要升级版本？

用户最初用的是 CrystalDiskInfo **7.7.0**（2017 年老版本），在 Windows 11 + NVMe SSD 环境下完全检测不到硬盘——老版本只支持 ATA SMART 查询，不支持 NVMe 的 NVMe-MI 查询接口。

所以必须升级到 CDI **9.9.2**（2026 年版），原生支持 NVMe。

## 2. 目录结构（必须严格遵守）

```
workspace-root/
  apply_theme.ps1            ← 主脚本（自动发现 新版CDI/）
  HANDOFF.md                 ← 本文档
  readme.txt                 ← 快速上手
  .trae/skills/cdi-theme-replace/SKILL.md  ← Skill 定义
  新版CDI/                    ← CDI 程序本体（脚本自动查找 .bak 定位）
    {品牌}64S.exe            ← 脚本生成（如 DeepSeek64S.exe / GPT64S.exe）
    {品牌}32S.exe
    {品牌}A64S.exe
    DiskInfo64S.exe.bak      ← 原版 EXE（永久备份，绝不修改）
    DiskInfo32S.exe.bak
    DiskInfoA64S.exe.bak
    DiskInfo.ini
    images/                   ← 用户自定义素材（文件名固定！）
      背景.jpg
      立绘1_健康.jpg
      立绘2_注意.jpg
      立绘3_损坏.jpg
      立绘4_未知.jpg
    CdiResource/themes/       ← 32 个 Shizuku 主题目录（脚本修改其中 PNG）
    License/                  ← 运行时依赖
    Smart/                    ← 运行时依赖
```

### 为什么 exe 不能挪出 新版CDI/？

**CDI 是传统 Windows 桌面程序**，运行时在 **exe 自己所在目录（ModulePath）** 查找资源文件，不是用 WorkingDirectory。如果把 `{品牌}64S.exe` 挪到别处，它会找不到 `CdiResource/themes/` 等目录，弹 "Not Found Graph.html"（原版 zip 里本来就没有这个 HTML，但找不到资源时会尝试加载）。

**结论：exe 必须跟资源目录（CdiResource、License、Smart、DiskInfo.ini）待在一起，不能挪。**

## 3. apply_theme.ps1 工作流程

### Step 0：杀残留进程
杀所有 DiskInfo*/CDIServer*/`{品牌}`* 进程。如果杀不掉（管理员权限运行的 exe），用：
```powershell
Start-Process taskkill -ArgumentList '/F /PID xxx' -Verb RunAs -Wait
```

### Step 1：从 .bak 原版 patch exe（6 步安全 patch）

**为什么要 6 步？为什么不能一把梭扫全文件替换？**

因为 CrystalDiskInfo 的 exe 有两个 PE Section：
- **CODE 段**（偏移 0 ~ 2,000,000）：存放代码和硬编码字符串。窗口标题模板、About 对话框文案都在这里。
- **RES 段**（偏移 2,800,000+）：PE Resource Section，包含 String Table、Version Info 等。ProductName、FileVersion 在这。

跨段乱 patch 的后果：
1. **扫全文件替换 `9.9.2`** → 短字符串 `9.9.2`（10 字节 UTF-16）在 2.9MB 里撞 **3000+ 处**！把 PE 导入表（DLL 入口点索引）搞坏 → 启动报"无法定位程序输入点"
2. **修改 RES 段的 String Table** → RES 段有固定格式（length-prefixed strings），乱改长度会破坏整个资源段 → 同样崩

所以每步都**严格限定扫描范围**，每步都**先验证命中数量**。

#### 6 步详解

| Step | 扫描范围 | 匹配串 | 替换策略 | 目的 | 正常命中数 |
|------|---------|--------|---------|------|-----------|
| **P1** | CODE (<2MB) | `Crystal` | 找到后扫描后续 null 终止符（≤5000 字节内），整段替换为 `{品牌} X64` + 尾部补 0 | 替换 CODE 段里所有硬编码的 "CrystalDiskInfo..." 字符串 | 14-15 |
| **P2** | RES (>2MB) | `CrystalDiskInfo Shizuku Edition` | 精确匹配 + null 终止检测 | 替换资源段 ProductName（窗口标题 %PRODUCT% 来源） | 2 |
| **P3** | CODE (<2MB) | `Shizuku Edition xNN` + 独立 `Shizuku Edition`（后面跟 xNN/%/9 时） | 全部清零 | 清窗口标题模板里的固定尾巴 | 2-4 |
| **P4** | RES (>2MB) | `9.9.2.0`（4 段格式！） | 全部清零 | 清资源段 FileVersion/ProductVersion（%VERSION% 来源） | 2 |
| **P5** | CODE (<2MB) | `9.9.2`（**先确认 ≤3 处才动手**） | 清零后不跟 `.0` 的那些 | 清最后残留的 release 版本号 | 1 |
| **P6** | CODE (<2MB) | 函数首指令魔术字节 | 整段替换为面板换边机器码 | 版权条点击 → 换边（替代随机换主题） | 1 |

**窗口标题拼接原理**：CDI 运行时把窗口标题拼成 `%PRODUCT% %VERSION% %TAIL%`：

| 片段 | 来源 | 处理 |
|------|------|------|
| `%PRODUCT%` | RES 段 ProductName | P2 替换为 `{品牌} X64` |
| `%VERSION%` | RES 段 FileVersion / CODE 硬编码 | P4/P5 清零 |
| `%TAIL%` | CODE 段硬编码 " Shizuku Edition xNN" | P3 清零 |

全部做完 → 干净的 `{品牌} X64`。

**P6 额外说明**：P6 替换的是 `IDC_BUTTON_COPYRIGHT(1099)` 的 `BN_CLICKED` 消息处理函数 `OnBnClickedButtonCopyright()`。原函数做 `rand() % themeCount → SendMessage(WM_THEME_ID)` 随机切换主题，替换为 `m_CharacterPosition ^= 1; UpdateDialogSize()` 面板换边切换。三架构偏移和机器码不同（详见脚本内注释），P6 通过魔术字节验证防止 CDI 版本升级后写错位置。

#### 安全机制

- P1 先检查 `hits.Count` 是否在 5-30 之间，否则跳过（说明不是原版 exe）
- P5 先统计 CODE 段 `9.9.2` 数量，≤3 才动手（原版里刚好 1 处）
- P6 先验函数首指令魔术字节匹配才动手（不匹配则跳过并打印 WARN），防止 CDI 版本升级后函数偏移改变导致静默写坏
- 每步只在**自己负责的段**里扫（CODE 段 <2MB，RES 段 >2MB），绝不跨段

### Step 2：加载用户素材
从 `新版CDI/images/` 读 5 张图。路径用中文文件名匹配（Unicode 码点硬编码，避免 GB2312 读错）。

### Step 3：遍历 32 个 Shizuku 主题替换 PNG
每个 Shizuku 主题文件夹有 6 个缩放等级的 PNG（100=33%, 300=100%）：
- `ShizukuBackground-300.png`（每主题 1 张，3000×3000）
- `SDdiskStatus{Good|Good100|Caution|Bad|Unknown}-{100..300}.png`（5 状态 × 6 缩放）
- `ShizukuCopyright-{100..300}.png`（版权条，6 张）

> ⚠ 部分主题（如 `Shizuku7thAnniversary`）原版就只有背景图，没有立绘/版权条——这是**设计如此**（继承父主题），脚本只在文件存在时替换，缺失是正常的，别当 bug。皮肤类主题（如 `ShizukuDark~TenmuShinryuusai`）靠 `theme.ini` 的 `ParentTheme` 继承父主题资源。

脚本用 GDI+ System.Drawing 做图像变换：
- 背景：按宽度拉满 3000，保持等比，不做左右填补（CDI 顶部对齐裁底部）
- 立绘：按比例缩放到目标画布内居中，保持透明
- 版权条：半透明深灰底 + 白字 `{品牌} {中文名}`（Microsoft YaHei，中文码点拼接）

### Step 4：DiskInfo.ini 幂等清理 + 锁定布局
- **幂等清理**：只保留一个 `[Layout]` 段、一个 `SwapPanel="0"`，历史追加产生的 9 个重复段会被合并成一个（跑多少遍都是 1 个）
- 锁定面板布局，防止 CDI 自动交换左右面板

## 4. 历史踩过的坑（按严重程度排序）

### 🔴 致命：扫全文件替换短字符串（已修）

**第一次崩**：对 .bak 全文件扫描 `9.9.2`（10 字节 UTF-16），命中 **3000+ 处**。其中包括 PE 导入表（IDT）里的 DLL 函数名引用，全清零后 Windows 加载器找不到 DLL 入口点 → 报"无法定位程序输入点 CreateFileW"等。

**教训**：任何短字符串（< 20 字节）**绝对不能扫全文件**。必须限定范围（CODE 段 <2MB）+ 验证命中数 ≤ 安全阈值。

### 🔴 致命：跨段 patch 全文件（已修）

**第二次崩**：把 P1 的范围从 `<2MB` 改成扫全文件（包括 RES 段），把 RES 段里的 String Table 结构破坏了 → 崩溃。

**教训**：CODE 和 RES 必须严格分开。CODE 段代码 + 字符串可以安全改（只要不越界到 PE 头/导入表），RES 段必须用**精确匹配 + 不改变长度**的方式。

### 🟡 GDI+ generic error

**原因**：exe 被管理员权限运行，占用了某些主题 PNG 文件。脚本 Step 0 的 `Stop-Process` 没杀掉（权限不够）。

**解决**：用 `Start-Process taskkill -Verb RunAs` 强杀。

### 🟡 PowerShell 5 中文乱码

脚本里写 `$foo = "背景.jpg"` 在 PS5 下会被按 GB2312 读取（即使保存为 UTF-8 无 BOM），然后读出来乱码 → 找不到文件。

**解决**：
1. 保存脚本时加 **UTF-8 BOM**
2. 中文常量用 Unicode 码点拼接：`[char]0x80CC + [char]0x666F`（背景）
3. 版权条文字同理

### 🟡 CDI 背景图裁剪逻辑

背景图 `ShizukuBackground-300.png` 固定 3000×3000。CDI 窗口是长方形，渲染时**顶部对齐，裁底部**。所以立绘要设计在画布上半部（下半部会被裁掉）。

之前踩过的坑：center-in-canvas + 左右填补纯色（深蓝色），导致窗口两侧出现深蓝色拼条。**正确做法**：按宽度拉满画布，让 CDI 自然裁底部。

### 🟡 DiskInfo.ini 重复 [Layout] 段

历史脚本每次运行都无脑追加 `[Layout]\nSwapPanel="0"`，跑 9 次就堆了 9 个重复段。虽然值一样 CDI 能跑，但文件脏。**已修**：Step 4 现在做幂等清理（保留首个段，丢弃重复段，缺键才补）。

### 🟡 版权条点击换边（P6）vs 重复跑脚本

P6 的版权条点击换边补丁是**集成在 apply_theme.ps1 脚本里**的，每次重跑脚本都会从 .bak 原版出发重新打 P1-P6 全部补丁，所以 P6 不会丢。**但是**：如果手动对已经 patch 过的 exe 再跑脚本，P6 的魔术字节验证会因为 exe 已经被改过（首指令已经不是原版了）而**跳过** —— 此时 P6 输出 WARN，exe 的点击行为退回到原版的随机换主题。解决方法：重新从 .bak 生成即可（脚本每次先删旧的 `{品牌}*S.exe`，从 .bak 重新做起）。

另外，`DiskInfo64S.exe.bak / DiskInfo32S.exe.bak / DiskInfoA64S.exe.bak`（3 个原版 CrystalDiskInfo）是脚本的**硬依赖**，不可删除（缺失则脚本无法定位 CDI 目录并跳过 P1-P6）。`DeepSeek*S.exe.bak`（P6 手动补丁前的快照）无脚本引用，可安全删除。

## 5. 如何验证 patch 成功

```powershell
# 1. 启动（WorkingDirectory 必须是 新版CDI/）
$cdi = Resolve-Path .\新版CDI
Start-Process (Join-Path $cdi '{品牌}64S.exe') -Verb RunAs -WorkingDirectory $cdi

# 2. 等几秒，检查
Get-Process -Name '{品牌}64S' | Select Id, ProcessName, MainWindowTitle, Responding
# 期望：Responding=True，MainWindowTitle="{品牌} X64"（干净，无尾巴）

# 3. 检查 exe 大小和原版差不多（patch 不改变文件长度）
(Get-Item .\新版CDI\{品牌}64S.exe).Length      # ~2.92MB
(Get-Item .\新版CDI\DiskInfo64S.exe.bak).Length
```

### 如果 patch 失败怎么查

| 现象 | 可能原因 | 排查方法 |
|------|---------|---------|
| 启动弹 "无法定位程序输入点" | 导入表被破坏 | 检查 patch 脚本是否在 CODE 段之外写了东西 |
| 启动就崩溃 | RES 段被破坏 | 检查 P2/P4 是否不小心改了 CODE 段 |
| 窗口标题还有尾巴 | P3/P4/P5 没命中 | 手动扫 CODE 段 `9.9.2` 数量 / RES 段 `Shizuku Edition` |
| 窗口标题为空 | P5 清零了不该清的 | 还原 .bak，只跑 P1-P3，跳过 P5 |
| 弹 "Not Found Graph.html" | exe 不在资源目录 | 确保 WorkingDirectory = 新版CDI/ |
| 立绘缺失 | 主题本身没有该文件（继承父主题） | 看该主题 theme.ini 的 ParentTheme，确认父主题有图 |
| 版权条点击无效果（不换边） | P6 没命中（magic 不匹配） | 检查脚本输出是否有 "P6 magic mismatch" WARN；确认 .bak 是原版 CDI 9.9.2 |
| 版权条点击闪一下（随机换主题） | P6 被跳过，退回原版行为 | 重新从 .bak 生成（脚本先删旧的再写新的） |

## 6. 版本升级时要改什么

如果升级到新 CDI 版本，检查：
1. `.bak` 里 CODE/RES 分界是否还是 2MB（`$codeSectionLimit` 在 apply_theme.ps1 顶部）
2. 版本号格式（P4 的 `9.9.2.0` → e.g. `9.9.3.0`）
3. 资源段 ProductName 是否还是 `CrystalDiskInfo Shizuku Edition`（P2）
4. CODE 段窗口标题模板里的架构后缀是否还是 `x64`/`x32`/`ARM64`
5. **P6 函数偏移和魔术字节**：`IDC_BUTTON_COPYRIGHT(1099)` 的 BN_CLICKED 处理函数位置是否改变。在 IDA/x64dbg 中定位 → 反汇编确认首指令 → 找到 `m_CharacterPosition` 访问偏移和 `UpdateDialogSize` RVA → 更新 P6 的 `$funcOff`、`$magic`、`$patchBytes`（`CALL` 和 `BL` 的相对偏移也要重新算）

用以下脚本快速扫描原版定位字符串：
```powershell
$bak = '.\新版CDI\DiskInfo64S.exe.bak'
$b = [IO.File]::ReadAllBytes($bak)
$crystal = [Text.Encoding]::Unicode.GetBytes('Crystal')
for($i=0; $i -le $b.Length - $crystal.Length; $i+=2){
    $ok=$true; for($j=0;$j -lt $crystal.Length;$j++){ if($b[$i+$j] -ne $crystal[$j]){$ok=$false;break} }
    if($ok){
        $seg = if($i -lt 2000000){'CODE'}else{'RES '}
        Write-Host ("offset=$i 0x$($i.ToString('X6')) $seg")
    }
}
```

## 7. 快速上手（给下一个 AI 的最短路径）

1. 读 `HANDOFF.md`（本文档）
2. 触发 `cdi-theme-replace` Skill（读 `.trae/skills/cdi-theme-replace/SKILL.md`）
3. 确认 `新版CDI/images/` 里素材齐了（背景.jpg + 4 个立绘，文件名完全一致）
4. （换品牌）改 apply_theme.ps1 顶部 `$brand`
5. 确认 `新版CDI/` 里有 `.bak` 原版 exe
6. `powershell -NoProfile -ExecutionPolicy Bypass -File apply_theme.ps1`
7. `Start-Process .\新版CDI\{品牌}64S.exe -Verb RunAs -WorkingDirectory .\新版CDI`
8. 验证标题 = 干净的 `{品牌} X64`，Responding=True，NVMe 硬盘能看到