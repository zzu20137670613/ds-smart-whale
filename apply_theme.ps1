<#
.SYNOPSIS
  One-click: 从原版 .bak 精准 patch exe + 替换 Shizuku 主题素材 + 改 DiskInfo.ini。

.DIRECTORY LAYOUT (REQUIRED):
  workspace-root/
    apply_theme.ps1          ← 本脚本（放在哪都行，自动发现 CDI 目录）
    新版CDI/                 ← CDI 程序本体（脚本自动发现，含 .bak 和资源）
      DeepSeek64S.exe        ← 脚本生成的 patch 后 exe（运行时在 新版CDI/ 下，跟资源同目录）
      DeepSeek32S.exe
      DeepSeekA64S.exe
      DiskInfo64S.exe.bak    ← 原版 EXE（永久备份，绝不修改）
      DiskInfo32S.exe.bak
      DiskInfoA64S.exe.bak
      DiskInfo.ini
      images/                ← 用户自定义素材（脚本从这里读）
        背景.jpg
        立绘1_健康.jpg
        立绘2_注意.jpg
        立绘3_损坏.jpg
        立绘4_未知.jpg
      CdiResource/themes/    ← Shizuku 主题（脚本会修改其中 PNG）
      License/               ← 运行时依赖
      Smart/                 ← 运行时依赖

.USAGE
  powershell -NoProfile -ExecutionPolicy Bypass -File apply_theme.ps1
  然后以管理员身份运行 新版CDI/DeepSeek64S.exe
  ⚠ 必须在 新版CDI/ 目录下运行（WorkingDirectory = 新版CDI/），否则资源文件找不到

.WHAT IT DOES
  Step 0: 杀掉残留的 DeepSeek/DiskInfo 进程
  Step 1: 从 .bak 原版精准 patch exe（6 步安全 patch），输出到 新版CDI/（跟资源同目录）
  Step 2: 加载 images/ 里的素材
  Step 3: 遍历 32 个 Shizuku 主题，替换 608 张 PNG（背景+立绘+版权条）
  Step 4: 锁定 DiskInfo.ini 的面板布局
#>

param([string]$Ws = (Split-Path -Parent $MyInvocation.MyCommand.Path))

Add-Type -AssemblyName System.Drawing

# ============================================================
# 先找 CDI 安装目录（含 .bak 原版），所有后续路径基于它
# ============================================================
$cdiRoot = $null
foreach ($f in [IO.Directory]::EnumerateFiles($Ws, 'DiskInfo64S.exe.bak', [IO.SearchOption]::AllDirectories)) {
    $cdiRoot = [IO.Path]::GetDirectoryName($f); break
}
if (-not $cdiRoot) {
    foreach ($f in [IO.Directory]::EnumerateFiles($Ws, 'DiskInfo.ini', [IO.SearchOption]::AllDirectories)) {
        $cdiRoot = [IO.Path]::GetDirectoryName($f); break
    }
}
if (-not $cdiRoot) { Write-Host '  ERROR: CDI folder (with .bak or DiskInfo.ini) not found!'; exit 1 }
Write-Host ('  CDI root: ' + $cdiRoot)

# ============================================================
# CONFIG（路径 = 基于 cdiRoot + 用户素材目录）
# ============================================================

# ============================================================
# ★ 品牌设置 —— 换品牌只改这里！
#   $brand   : 品牌英文名。出现在窗口标题/ exe 文件名的前缀/ 版权条文字
#   $brandCN : 品牌中文名。版权条文字 "Brand 中文名"
#   注意：窗口标题 = "$brand X64/X32/ARM64"，exe 名 = "$brand{64S,32S,A64S}.exe"
#   例：/  GPT   → 窗口标题 "GPT X64"，exe 名 "GPT64S.exe"，版权条 "GPT 生成式预训练"
#      / Claude → 窗口标题 "Claude X64"，exe 名 "Claude64S.exe"，版权条 "Claude 克劳德"
#      / Kimi   → 窗口标题 "Kimi X64"，exe 名 "Kimi64S.exe"，版权条 "Kimi 月之暗面"
# ============================================================
$brand   = 'DeepSeek'   # ← 改这里
$brandCN = [string][char]0x6DF1 + [char]0x5EA6 + [char]0x6C42 + [char]0x7D22  # 深度求索（中文名）
# ============================================================

$imgDir = Join-Path $cdiRoot 'images'
$bgFile   = Join-Path $imgDir ([string][char]0x80CC + [char]0x666F + '.jpg')
$goodFile = Join-Path $imgDir ([string][char]0x7ACB + [char]0x7ED8 + '1_' + [char]0x5065 + [char]0x5EB7 + '.jpg')
$cautFile = Join-Path $imgDir ([string][char]0x7ACB + [char]0x7ED8 + '2_' + [char]0x6CE8 + [char]0x610F + '.jpg')
$badFile  = Join-Path $imgDir ([string][char]0x7ACB + [char]0x7ED8 + '3_' + [char]0x635F + [char]0x574F + '.jpg')
$unkFile  = Join-Path $imgDir ([string][char]0x7ACB + [char]0x7ED8 + '4_' + [char]0x672A + [char]0x77E5 + '.jpg')

# exe 变体：Old = .bak 里的原版名, New = 输出到 cdiRoot 的新名（前缀 = $brand）
$variants = @(
    @{ Old='DiskInfo64S.exe';  New=($brand + '64S.exe');  Title=($brand + ' X64');   Ver='x64'   },
    @{ Old='DiskInfo32S.exe';  New=($brand + '32S.exe');  Title=($brand + ' X32');   Ver='x32'   },
    @{ Old='DiskInfoA64S.exe'; New=($brand + 'A64S.exe'); Title=($brand + ' ARM64'); Ver='ARM64' }
)

$copyrightText = $brand + ' ' + $brandCN
$bgPadColor = [System.Drawing.Color]::FromArgb(30, 60, 110)

# PE 代码段和资源段的分界点：约 2MB 处
# （经过验证，CrystalDiskInfo 9.9.x 系列代码段全部在 2MB 内，资源段从 ~2.8MB 开始）
$codeSectionLimit = 2000000

# 主题缩放后缀（文件名里 100=33%, 300=100%）
$scaleSuffixes = @('100','125','150','200','250','300')
$scaleFactors  = @(0.333, 0.417, 0.5, 0.667, 0.833, 1.0)
# ============================================================

Write-Host ''
Write-Host '============================================'
Write-Host ('  CrystalDiskInfo -> ' + $brand + ' Theme Tool')
Write-Host '============================================'

# --- Step 0: 杀残留进程 ---
Write-Host ''
Write-Host '[0/4] Stopping CDI processes...'
Get-Process | Where-Object { $_.ProcessName -match ('DiskInfo|CDIServer|' + $brand) } | Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 1

# --- Step 1: 从 .bak 原版 patch exe，输出到 root ---
Write-Host ''
Write-Host '[1/4] Patching exes (from .bak originals)...'

foreach ($v in $variants) {
    $bak = Join-Path $cdiRoot ($v.Old + '.bak')   # 原版：DiskInfo64S.exe.bak（永不修改）
    $out = Join-Path $cdiRoot $v.New              # 输出：新版CDI/DeepSeek64S.exe（跟资源同目录）

    if (-not (Test-Path -LiteralPath $bak)) {
        Write-Host ('  SKIP: .bak missing — ' + $bak); continue
    }

    # 如果 cdiRoot 已有同名 exe，先删（避免文件锁）
    if (Test-Path -LiteralPath $out) { Remove-Item -LiteralPath $out -Force }

    $bytes = [IO.File]::ReadAllBytes($bak)
    $titleBytes = [Text.Encoding]::Unicode.GetBytes($v.Title)
    $titleVer   = $v.Ver  # x64 / x32 / ARM64

    # ========================================================
    # 6-STEP SAFE PATCH
    # 每步都严格限定扫描范围，绝不交叉污染！
    # 原理：CrystalDiskInfo 窗口标题是运行时由 %PRODUCT% + " " + %VERSION% + " " + "Shizuku Edition x64" 拼接的。
    #   %PRODUCT% 来自 RES 段 ProductName（P2 替换）
    #   %VERSION% 来自 RES 段 FileVersion 或 CODE 段硬编码（P4/P5 清零）
    #   尾巴 "Shizuku Edition x64" 来自 CODE 段模板（P3 清零）
    # P1 替换的是 CODE 段里直接显示 "CrystalDiskInfo..." 的硬编码字符串。
    # ========================================================

    # P1: CODE 段 —— 所有 "Crystal..." + null 终止 → title + null pad
    #   限定范围：offset < 2,000,000（代码段）
    #   先统计数量（应在 14-15 之间），异常则跳过
    $crystal = [Text.Encoding]::Unicode.GetBytes('Crystal')
    $hits = @()
    for ($i = 0; $i -le $codeSectionLimit - $crystal.Length; $i += 2) {
        $ok = $true; for ($j = 0; $j -lt $crystal.Length; $j++) { if ($bytes[$i + $j] -ne $crystal[$j]) { $ok = $false; break } }
        if ($ok) { $hits += $i }
    }
    if ($hits.Count -lt 5 -or $hits.Count -gt 30) {
        Write-Host ('  WARN: Crystal hits=' + $hits.Count + ' (expect 14-15), skip ' + $v.New); continue
    }
    $p1 = 0
    foreach ($hit in $hits) {
        $end = -1
        for ($k = $hit + $crystal.Length; $k -lt [math]::Min($hit + 5000, $codeSectionLimit - 1); $k += 2) {
            if ($bytes[$k] -eq 0 -and $bytes[$k + 1] -eq 0) { $end = $k + 2; break }
        }
        if ($end -lt 0) { continue }
        $len = $end - $hit
        if ($len -lt $titleBytes.Length + 2) { continue }
        for ($j = 0; $j -lt [math]::Min($titleBytes.Length, $len - 2); $j++) { $bytes[$hit + $j] = $titleBytes[$j] }
        for ($j = $titleBytes.Length; $j -lt $len; $j++) { $bytes[$hit + $j] = 0 }
        $p1++
    }

    # P2: RES 段 —— ProductName "CrystalDiskInfo Shizuku Edition" → title
    #   限定范围：offset > 2,000,000（资源段）
    #   精确匹配（资源段只有 2 处），null 终止检测后替换
    $pn = [Text.Encoding]::Unicode.GetBytes('CrystalDiskInfo Shizuku Edition')
    $p2 = 0
    for ($i = 2000000; $i -le $bytes.Length - $pn.Length; $i += 2) {
        $ok = $true; for ($j = 0; $j -lt $pn.Length; $j++) { if ($bytes[$i + $j] -ne $pn[$j]) { $ok = $false; break } }
        if ($ok) {
            $end = -1
            for ($k = $i + $pn.Length; $k -lt [math]::Min($i + 500, $bytes.Length - 1); $k += 2) {
                if ($bytes[$k] -eq 0 -and $bytes[$k + 1] -eq 0) { $end = $k + 2; break }
            }
            if ($end -lt 0) { continue }
            $len = $end - $i
            for ($j = 0; $j -lt [math]::Min($titleBytes.Length, $len - 2); $j++) { $bytes[$i + $j] = $titleBytes[$j] }
            for ($j = $titleBytes.Length; $j -lt $len; $j++) { $bytes[$i + $j] = 0 }
            $p2++
        }
    }

    # P3: CODE 段 —— 清零 "Shizuku Edition" 尾巴
    #   先清完整尾巴 "Shizuku Edition x64"（窗口标题模板里的）
    #   再清独立的 "Shizuku Edition"（只在后面跟着 xNN/%/9 时才清，避免误杀）
    $p3 = 0
    $sf = [Text.Encoding]::Unicode.GetBytes('Shizuku Edition ' + $titleVer)
    for ($i = 0; $i -le $codeSectionLimit - $sf.Length; $i += 2) {
        $ok = $true; for ($j = 0; $j -lt $sf.Length; $j++) { if ($bytes[$i + $j] -ne $sf[$j]) { $ok = $false; break } }
        if ($ok) { for ($j = 0; $j -lt $sf.Length; $j++) { $bytes[$i + $j] = 0 }; $p3++ }
    }
    $so = [Text.Encoding]::Unicode.GetBytes('Shizuku Edition')
    for ($i = 0; $i -le $codeSectionLimit - $so.Length; $i += 2) {
        $ok = $true; for ($j = 0; $j -lt $so.Length; $j++) { if ($bytes[$i + $j] -ne $so[$j]) { $ok = $false; break } }
        if ($ok) {
            $next = [Text.Encoding]::Unicode.GetString($bytes, $i + $so.Length, [math]::Min(4, $codeSectionLimit - ($i + $so.Length)))
            if ($next -match ' x|%| 9') { for ($j = 0; $j -lt $so.Length; $j++) { $bytes[$i + $j] = 0 }; $p3++ }
        }
    }

    # P4: RES 段 —— 清零 FileVersion/ProductVersion "9.9.2.0"
    #   限定范围：offset > 2,000,000（资源段）
    #   精确匹配（资源段只有 2 处：FileVersion 和 ProductVersion）
    $verLong = [Text.Encoding]::Unicode.GetBytes('9.9.2.0')
    $p4 = 0
    for ($i = 2000000; $i -le $bytes.Length - $verLong.Length; $i += 2) {
        $ok = $true; for ($j = 0; $j -lt $verLong.Length; $j++) { if ($bytes[$i + $j] -ne $verLong[$j]) { $ok = $false; break } }
        if ($ok) { for ($j = 0; $j -lt $verLong.Length; $j++) { $bytes[$i + $j] = 0 }; $p4++ }
    }

    # P5: CODE 段 —— 清零剩余的 release 版本号 "9.9.2"
    #   限定范围：offset < 2,000,000（代码段）
    #   先确认数量 ≤ 3 才敢动手（原版 .bak 里 CODE 段只有 1 处）
    #   只清零后面没跟 ".0" 的（因为跟 ".0" 的是资源段里的，不在此范围）
    $vShort = [Text.Encoding]::Unicode.GetBytes('9.9.2')
    $vCount = 0
    for ($i = 0; $i -le $codeSectionLimit - $vShort.Length; $i += 2) {
        $ok = $true; for ($j = 0; $j -lt $vShort.Length; $j++) { if ($bytes[$i + $j] -ne $vShort[$j]) { $ok = $false; break } }
        if ($ok) { $vCount++ }
    }
    $p5 = 0
    if ($vCount -le 3) {
        for ($i = 0; $i -le $codeSectionLimit - $vShort.Length; $i += 2) {
            $ok = $true; for ($j = 0; $j -lt $vShort.Length; $j++) { if ($bytes[$i + $j] -ne $vShort[$j]) { $ok = $false; break } }
            if ($ok) {
                $after = [Text.Encoding]::Unicode.GetString($bytes, $i + $vShort.Length, [math]::Min(6, $codeSectionLimit - ($i + $vShort.Length)))
                if (-not $after.StartsWith('.0')) { for ($j = 0; $j -lt $vShort.Length; $j++) { $bytes[$i + $j] = 0 }; $p5++ }
            }
        }
    }

    # ════════════════════════════════════════════════════════════
    # P6: CODE 段 —— 版权条点击换边（替代随机换主题）
    #   把 OnBnClickedButtonCopyright() 替换为：
    #     m_CharacterPosition ^= 1; UpdateDialogSize();
    #   x64:   RCX=this, m_CharacterPosition=this+0x223 (547)
    #   x86:   ESI=this, m_CharacterPosition=this+0x173 (371)
    #   ARM64: X0=this,  m_CharacterPosition=this+0x223 (547)
    # ════════════════════════════════════════════════════════════
    $p6 = 0
    switch ($titleVer) {
        'x64' {
            $funcOff = 0x8810; $funcSize = 52
            $magic = [byte[]]@(0x40, 0x53)  # PUSH RBX
            $patchBytes = [byte[]]@(
                0x80, 0xB1, 0x23, 0x02, 0x00, 0x00, 0x01,  # XOR byte [RCX+0x223], 1
                0x48, 0x83, 0xEC, 0x28,                     # SUB RSP, 0x28
                0xE8, 0x70, 0x3C, 0x00, 0x00,               # CALL UpdateDialogSize (RVA 0xD090)
                0x48, 0x83, 0xC4, 0x28,                     # ADD RSP, 0x28
                0xC3                                          # RET
            )
            $padByte = 0xCC  # INT3 padding
        }
        'x32' {
            $funcOff = 0x6F5E; $funcSize = 34
            $magic = [byte[]]@(0x56)  # PUSH ESI
            $patchBytes = [byte[]]@(
                0x80, 0xB6, 0x73, 0x01, 0x00, 0x00, 0x01,  # XOR byte [ESI+0x173], 1
                0x56,                                         # PUSH ESI
                0x8B, 0xCE,                                   # MOV ECX, ESI
                0xE8, 0x03, 0x2B, 0x00, 0x00,               # CALL UpdateDialogSize (RVA 0xA670)
                0x5E,                                         # POP ESI
                0xC3                                          # RET
            )
            $padByte = 0xCC
        }
        'ARM64' {
            $funcOff = 0x9788; $funcSize = 84
            $magic = [byte[]]@(0xF3, 0x53)  # STP X19, X20
            $patchBytes = [byte[]]@(
                0x08, 0x8C, 0x48, 0x39,  # LDRB W8, [X0, #0x223]
                0x08, 0x01, 0x00, 0x52,  # EOR W8, W8, #1
                0x08, 0x8C, 0x08, 0x39,  # STRB W8, [X0, #0x223]
                0x0C, 0x0E, 0x00, 0x94,  # BL UpdateDialogSize (RVA 0xDBC8)
                0xC0, 0x03, 0x5F, 0xD6   # RET
            )
            $padByte = $null  # ARM64 用 NOP
        }
    }
    # 验原函数魔术字节：防止 CDI 版本升级后静默写错位置
    $magicMatch = $true
    for ($j = 0; $j -lt $magic.Count; $j++) {
        if ($bytes[$funcOff + $j] -ne $magic[$j]) { $magicMatch = $false; break }
    }
    if ($magicMatch) {
        for ($j = 0; $j -lt $patchBytes.Count; $j++) {
            $bytes[$funcOff + $j] = $patchBytes[$j]
        }
        if ($titleVer -eq 'ARM64') {
            $nop = [byte[]]@(0x1F, 0x20, 0x03, 0xD5)
            for ($j = $patchBytes.Count; $j -lt $funcSize; $j += 4) {
                $bytes[$funcOff + $j] = $nop[0]
                $bytes[$funcOff + $j + 1] = $nop[1]
                $bytes[$funcOff + $j + 2] = $nop[2]
                $bytes[$funcOff + $j + 3] = $nop[3]
            }
        } else {
            for ($j = $patchBytes.Count; $j -lt $funcSize; $j++) {
                $bytes[$funcOff + $j] = $padByte
            }
        }
        $p6 = 1
    } else {
        $actualMagic = ($bytes[$funcOff..($funcOff + [math]::Min(7, $magic.Count - 1))] | ForEach-Object { '{0:X2}' -f $_ }) -join ' '
        $expectMagic = ($magic | ForEach-Object { '{0:X2}' -f $_ }) -join ' '
        Write-Host ('  WARN: P6 magic mismatch — expect ' + $expectMagic + ', got ' + $actualMagic + '. CDI version may have changed.')
    }

    [IO.File]::WriteAllBytes($out, $bytes)
    Write-Host ('  ' + $v.Old + '.bak -> ' + $v.New + '  (P1=' + $p1 + ' P2=' + $p2 + ' P3=' + $p3 + ' P4=' + $p4 + ' P5=' + $p5 + ' P6=' + $p6 + ')')
}

# --- Step 2: 加载用户素材 ---
Write-Host ''
Write-Host '[2/4] Loading image assets from ' + $imgDir

function Load-Image($path) {
    if (-not (Test-Path -LiteralPath $path)) { Write-Host ('  ERROR: missing ' + $path); exit 1 }
    return [System.Drawing.Image]::FromFile($path)
}

$bgSrc   = Load-Image $bgFile
$goodSrc = Load-Image $goodFile
$cautSrc = Load-Image $cautFile
$badSrc  = Load-Image $badFile
$unkSrc  = Load-Image $unkFile
Write-Host ('  bg: ' + $bgSrc.Width + 'x' + $bgSrc.Height)

# --- Step 3: 遍历所有 Shizuku 主题，替换素材 ---
Write-Host ''
Write-Host '[3/4] Iterating all Shizuku themes...'

$themesDir = Join-Path $cdiRoot 'CdiResource\themes'
$themeDirs = [IO.Directory]::EnumerateDirectories($themesDir) | Where-Object { (Split-Path $_ -Leaf) -match '^Shizuku' }
Write-Host ('  Themes found: ' + $themeDirs.Count)

$totalSaved = 0
$themeCount = 0

foreach ($themeDir in $themeDirs) {
    $themeCount++

    # --- Background (每个主题只有 1 张: ShizukuBackground-300.png = 3000x3000) ---
    $bgPath = Join-Path $themeDir 'ShizukuBackground-300.png'
    if (Test-Path -LiteralPath $bgPath) {
        $bmp = New-Object System.Drawing.Bitmap(3000, 3000)
        $g   = [System.Drawing.Graphics]::FromImage($bmp)
        $g.SmoothingMode = 'HighQuality'
        $g.InterpolationMode = 'HighQualityBicubic'
        $g.Clear($bgPadColor)
        $ratio = 3000 / [double]$bgSrc.Width
        $drawH = [int]($bgSrc.Height * $ratio)
        if ($drawH -gt 3000) { $drawH = 3000 }
        $g.DrawImage($bgSrc, 0, 0, 3000, $drawH)
        $g.Dispose()
        $bmp.Save($bgPath, [System.Drawing.Imaging.ImageFormat]::Png)
        $bmp.Dispose()
        $totalSaved++
    }

    # --- 每个缩放等级: SDdiskStatus (立绘) + ShizukuCopyright (版权条) ---
    foreach ($si in 0..5) {
        $suffix = $scaleSuffixes[$si]
        $factor = $scaleFactors[$si]

        # --- SDdiskStatus ---
        $sdBaseW = [int](384 * $factor)
        $sdBaseH = [int](576 * $factor)
        $states = @(
            @{ Name='Good';    Img=$goodSrc },
            @{ Name='Good100'; Img=$goodSrc },
            @{ Name='Caution'; Img=$cautSrc },
            @{ Name='Bad';     Img=$badSrc },
            @{ Name='Unknown'; Img=$unkSrc }
        )
        foreach ($st in $states) {
            $sdPath = Join-Path $themeDir ('SDdiskStatus' + $st.Name + '-' + $suffix + '.png')
            if (-not (Test-Path -LiteralPath $sdPath)) { continue }

            $sbmp = New-Object System.Drawing.Bitmap($sdBaseW, $sdBaseH)
            $sg   = [System.Drawing.Graphics]::FromImage($sbmp)
            $sg.SmoothingMode = 'HighQuality'
            $sg.InterpolationMode = 'HighQualityBicubic'
            $sg.Clear([System.Drawing.Color]::Transparent)
            $rw = $sbmp.Width / [double]$st.Img.Width
            $rh = $sbmp.Height / [double]$st.Img.Height
            $rr = [math]::Min($rw, $rh)
            $dw = [int]($st.Img.Width * $rr)
            $dh = [int]($st.Img.Height * $rr)
            $dx = ($sbmp.Width - $dw) / 2
            $dy = ($sbmp.Height - $dh) / 2
            $sg.DrawImage($st.Img, $dx, $dy, $dw, $dh)
            $sg.Dispose()
            $sbmp.Save($sdPath, [System.Drawing.Imaging.ImageFormat]::Png)
            $sbmp.Dispose()
            $totalSaved++
        }

        # --- Copyright ---
        $tagW = [int](984 * $factor)
        $tagH = [int](72  * $factor)
        $cpPath = Join-Path $themeDir ('ShizukuCopyright-' + $suffix + '.png')
        if (-not (Test-Path -LiteralPath $cpPath)) { continue }

        $cbmp = New-Object System.Drawing.Bitmap($tagW, $tagH)
        $cg   = [System.Drawing.Graphics]::FromImage($cbmp)
        $cg.SmoothingMode = 'HighQuality'
        $cg.TextRenderingHint = 'AntiAliasGridFit'
        $cg.Clear([System.Drawing.Color]::Transparent)
        $bgBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(200, 30, 30, 30))
        $cg.FillRectangle($bgBrush, 0, 0, $tagW, $tagH)
        $bgBrush.Dispose()
        $fontSize = [math]::Max(8, [int](26 * $factor))
        $font = New-Object System.Drawing.Font('Microsoft YaHei', $fontSize, [System.Drawing.FontStyle]::Bold)
        $brush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::White)
        $sf = New-Object System.Drawing.StringFormat
        $sf.Alignment = 'Center'
        $sf.LineAlignment = 'Center'
        $cg.DrawString($copyrightText, $font, $brush, (New-Object System.Drawing.RectangleF(0,0,$tagW,$tagH)), $sf)
        $font.Dispose(); $brush.Dispose(); $cg.Dispose()
        $cbmp.Save($cpPath, [System.Drawing.Imaging.ImageFormat]::Png)
        $cbmp.Dispose()
        $totalSaved++
    }

    Write-Host ('  [' + $themeCount + '/' + $themeDirs.Count + '] ' + (Split-Path $themeDir -Leaf))
}

$bgSrc.Dispose(); $goodSrc.Dispose(); $cautSrc.Dispose(); $badSrc.Dispose(); $unkSrc.Dispose()
Write-Host ('  Total images saved: ' + $totalSaved)

# --- Step 4: 锁定 DiskInfo.ini 面板布局（幂等：已有则不重复追加） ---
Write-Host ''
Write-Host '[4/4] Locking DiskInfo.ini layout...'
$iniPath = Join-Path $cdiRoot 'DiskInfo.ini'
# 清理 [Layout] 段：
#   - 任何情况下都绝不重复追加 [Layout]/SwapPanel（历史脚本追加过多次，这里一并去重）
#   - 保留第一个 [Layout] 段，丢弃其余重复段及其内容
#   - 若第一个 [Layout] 段里没有 SwapPanel="0"，则补一行
if (Test-Path -LiteralPath $iniPath) {
    $lines = [IO.File]::ReadAllLines($iniPath)
    $out = New-Object System.Collections.ArrayList
    $layoutCount   = 0    # 遇到 [Layout] 段头的次数
    $inLayout      = $false
    $hasSwap       = $false
    $layoutHeader  = -1   # 第一个 [Layout] 段头在 $out 里的下标

    for ($i = 0; $i -lt $lines.Length; $i++) {
        $t = $lines[$i].Trim()
        $isHeader = $t -match '^\[[^\]]+\]$'

        if ($isHeader -and $t -eq '[Layout]') {
            $layoutCount++
            $inLayout = $true
            if ($layoutCount -eq 1) {
                $layoutHeader = $out.Count
                [void]$out.Add($lines[$i])
            }
            continue   # 第二个及以后的 [Layout] 段头直接丢弃
        }

        if ($inLayout) {
            if ($isHeader) {
                $inLayout = $false   # 离开 [Layout] 段，继续正常处理该行
            } elseif ($layoutCount -gt 1) {
                continue             # 重复段的内容全部丢弃
            } elseif ($t -match '^SwapPanel\s*=') {
                if ($hasSwap) { continue }   # 同段内重复键去重（保留第一个）
                $hasSwap = $true
                [void]$out.Add($lines[$i])
                continue
            } else {
                [void]$out.Add($lines[$i])
                continue
            }
        }

        [void]$out.Add($lines[$i])
    }

    # 补充缺失的 [Layout] 段或 SwapPanel 键
    if ($layoutCount -eq 0) {
        [void]$out.Add('[Layout]')
        [void]$out.Add('SwapPanel="0"')
        Write-Host '  DiskInfo.ini: added [Layout] SwapPanel="0" (new)'
    } elseif (-not $hasSwap) {
        $out.Insert($layoutHeader + 1, 'SwapPanel="0"')
        Write-Host '  DiskInfo.ini: added missing SwapPanel="0"'
    }

    [IO.File]::WriteAllLines($iniPath, $out)
    $dups = ($out | Where-Object { $_.Trim() -eq '[Layout]' }).Count
    Write-Host ('  DiskInfo.ini cleaned ([Layout] sections: ' + $dups + ', SwapPanel: ' + $(($out | Where-Object { $_.Trim() -match '^SwapPanel\s*=' }).Count) + ')')
}

Write-Host ''
Write-Host '============================================'
Write-Host '  DONE! Run as Admin: DeepSeek64S.exe'
Write-Host '============================================'
