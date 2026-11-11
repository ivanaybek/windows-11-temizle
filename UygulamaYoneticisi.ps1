param([switch]$SelfTest)

$ErrorActionPreference = 'Stop'
if ($SelfTest) {
    $null = @(Get-AppxPackage -ErrorAction Stop)
    $null = Get-ItemProperty 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*' -ErrorAction SilentlyContinue
    Write-Output 'Self-test passed: AppX and uninstall registry are readable.'
    exit 0
}

if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    try {
        Start-Process powershell.exe -Verb RunAs -ArgumentList @('-NoLogo', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', ('"' + $PSCommandPath + '"'))
        exit 0
    } catch {
        Add-Type -AssemblyName System.Windows.Forms
        [System.Windows.Forms.MessageBox]::Show('Uygulama yöneticisi için yönetici izni gerekiyor. Tekrar çalıştırıp izin verebilirsin.', 'Yönetici izni') | Out-Null
        exit 1
    }
}

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()
$script:appItems = @()
$script:startupItems = @()
$script:backupRoot = 'HKCU:\Software\UygulamaYoneticisi\StartupBackup'

function Message([string]$text, [string]$title = 'Uygulama Yöneticisi') {
    [System.Windows.Forms.MessageBox]::Show($text, $title, 'OK', 'Information') | Out-Null
}
function Confirm([string]$text) {
    return [System.Windows.Forms.MessageBox]::Show($text, 'Onay', 'YesNo', 'Warning') -eq 'Yes'
}
function New-Button([string]$text, [int]$x, [int]$y, [int]$width) {
    $button = New-Object System.Windows.Forms.Button
    $button.Text = $text; $button.SetBounds($x, $y, $width, 32)
    $button.FlatStyle = 'Flat'; $button.BackColor = [System.Drawing.Color]::FromArgb(232, 239, 250)
    $button.ForeColor = [System.Drawing.Color]::FromArgb(35, 65, 105)
    $button.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(192, 207, 228)
    return $button
}
function New-Grid {
    $grid = New-Object System.Windows.Forms.DataGridView
    $grid.SetBounds(12, 52, 1000, 440)
    $grid.Anchor = 'Top,Left'
    $grid.ReadOnly = $true; $grid.AllowUserToAddRows = $false; $grid.AllowUserToDeleteRows = $false
    $grid.SelectionMode = 'FullRowSelect'; $grid.MultiSelect = $false
    $grid.AutoSizeColumnsMode = 'None'; $grid.ScrollBars = 'Both'; $grid.RowHeadersVisible = $false
    $grid.BackgroundColor = [System.Drawing.Color]::White; $grid.BorderStyle = 'None'
    $grid.CellBorderStyle = 'SingleHorizontal'; $grid.GridColor = [System.Drawing.Color]::FromArgb(235, 239, 245)
    $grid.EnableHeadersVisualStyles = $false; $grid.ColumnHeadersHeight = 38
    $grid.ColumnHeadersDefaultCellStyle.BackColor = [System.Drawing.Color]::FromArgb(235, 241, 250)
    $grid.ColumnHeadersDefaultCellStyle.ForeColor = [System.Drawing.Color]::FromArgb(44, 63, 87)
    $grid.DefaultCellStyle.SelectionBackColor = [System.Drawing.Color]::FromArgb(218, 232, 252)
    $grid.DefaultCellStyle.SelectionForeColor = [System.Drawing.Color]::FromArgb(30, 48, 72)
    $grid.AlternatingRowsDefaultCellStyle.BackColor = [System.Drawing.Color]::FromArgb(248, 250, 253)
    $grid.RowTemplate.Height = 46
    return $grid
}
function Add-Column($grid, [string]$name, [string]$label, [int]$weight) {
    $col = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
    $col.Name = $name; $col.HeaderText = $label; $col.FillWeight = $weight
    [void]$grid.Columns.Add($col)
}

$form = New-Object System.Windows.Forms.Form
$form.Text = 'Uygulama Yöneticisi'; $form.Size = New-Object System.Drawing.Size(1060, 665)
$form.MinimumSize = New-Object System.Drawing.Size(900, 550); $form.StartPosition = 'CenterScreen'
$form.Font = New-Object System.Drawing.Font('Segoe UI', 9)
$form.BackColor = [System.Drawing.Color]::FromArgb(246, 249, 253)
$tabs = New-Object System.Windows.Forms.TabControl
$tabs.Dock = 'Fill'
$appsTab = New-Object System.Windows.Forms.TabPage; $appsTab.Text = 'Yüklü uygulamalar'
$startupTab = New-Object System.Windows.Forms.TabPage; $startupTab.Text = 'Başlangıç'
$securityTab = New-Object System.Windows.Forms.TabPage; $securityTab.Text = 'Defender'
$tabs.TabPages.AddRange(@($appsTab, $startupTab, $securityTab)); $form.Controls.Add($tabs)
foreach ($page in @($appsTab, $startupTab, $securityTab)) { $page.BackColor = [System.Drawing.Color]::FromArgb(246, 249, 253) }
$header = New-Object System.Windows.Forms.Panel; $header.Dock = 'Top'; $header.Height = 67
$header.BackColor = [System.Drawing.Color]::FromArgb(30, 54, 89)
$title = New-Object System.Windows.Forms.Label; $title.Text = 'Uygulama Yöneticisi'; $title.SetBounds(18, 8, 450, 28)
$title.Font = New-Object System.Drawing.Font('Segoe UI', 14, [System.Drawing.FontStyle]::Bold); $title.ForeColor = [System.Drawing.Color]::White
$subtitle = New-Object System.Windows.Forms.Label; $subtitle.Text = 'Uygulamaları, başlangıcı ve güvenlik ayarlarını yönet'; $subtitle.SetBounds(20, 38, 600, 20)
$subtitle.ForeColor = [System.Drawing.Color]::FromArgb(200, 216, 238)
$header.Controls.AddRange(@($title, $subtitle)); $form.Controls.Add($header); $tabs.BringToFront()

$searchLabel = New-Object System.Windows.Forms.Label; $searchLabel.Text = 'Ara:'; $searchLabel.SetBounds(12, 17, 35, 22)
$search = New-Object System.Windows.Forms.TextBox; $search.SetBounds(50, 13, 300, 25)
$refreshApps = New-Button 'Listeyi yenile' 365 10 120
$appGrid = New-Grid
$iconColumn = New-Object System.Windows.Forms.DataGridViewImageColumn
$iconColumn.Name = 'Icon'; $iconColumn.HeaderText = ''; $iconColumn.AutoSizeMode = 'None'; $iconColumn.Width = 52
$iconColumn.ImageLayout = 'Zoom'; [void]$appGrid.Columns.Add($iconColumn)
Add-Column $appGrid 'Name' 'Ad' 32; Add-Column $appGrid 'Type' 'Tür' 17; Add-Column $appGrid 'Publisher' 'Yayımcı' 23; Add-Column $appGrid 'Version' 'Sürüm' 15; Add-Column $appGrid 'Size' 'Boyut' 13
$appGrid.Columns['Name'].Width = 310; $appGrid.Columns['Type'].Width = 160
$appGrid.Columns['Publisher'].Width = 240; $appGrid.Columns['Version'].Width = 150; $appGrid.Columns['Size'].Width = 130
$appMenu = New-Object System.Windows.Forms.ContextMenuStrip
$openLocation = New-Object System.Windows.Forms.ToolStripMenuItem
$openLocation.Text = 'Dosya konumunu aç'
[void]$appMenu.Items.Add($openLocation)
$appGrid.ContextMenuStrip = $appMenu
$uninstall = New-Button 'Seçileni kaldır' 500 10 155
$uninstall.BackColor = [System.Drawing.Color]::FromArgb(185, 55, 62); $uninstall.ForeColor = [System.Drawing.Color]::White
$uninstall.Anchor = 'Top,Left'
$appNote = New-Object System.Windows.Forms.Label; $appNote.SetBounds(670, 16, 350, 25); $appNote.Anchor = 'Top,Left'
$appNote.Text = 'Dosya konumu için uygulamaya sağ tıkla.'
$progress = New-Object System.Windows.Forms.ProgressBar; $progress.SetBounds(12, 52, 220, 20); $progress.Style = 'Marquee'; $progress.MarqueeAnimationSpeed = 25; $progress.Visible = $false
$progressText = New-Object System.Windows.Forms.Label; $progressText.SetBounds(245, 52, 700, 25); $progressText.Visible = $false
$appsTab.Controls.AddRange(@($searchLabel, $search, $refreshApps, $appGrid, $uninstall, $appNote, $progress, $progressText))

$refreshStartup = New-Button 'Listeyi yenile' 12 10 120
$startupGrid = New-Grid
Add-Column $startupGrid 'Name' 'Ad' 25; Add-Column $startupGrid 'Status' 'Durum' 14; Add-Column $startupGrid 'Location' 'Kapsam' 20; Add-Column $startupGrid 'Command' 'Komut' 41
$startupGrid.Columns['Name'].Width = 270; $startupGrid.Columns['Status'].Width = 155; $startupGrid.Columns['Location'].Width = 190; $startupGrid.Columns['Command'].Width = 500
$disableStartup = New-Button 'Başlangıcı kapat' 145 10 155; $disableStartup.Anchor = 'Top,Left'
$enableStartup = New-Button 'Tekrar aç' 310 10 120; $enableStartup.Anchor = 'Top,Left'
$startupNote = New-Object System.Windows.Forms.Label; $startupNote.SetBounds(445, 10, 500, 40); $startupNote.Anchor = 'Top,Left'
$startupNote.Text = 'Kayıt var: Otomatik başlatma kaydı bulundu; şu an çalıştığı veya Görev Yöneticisi tarafından etkin olduğu kesin değildir. Yalnızca Run kayıtları listelenir.'
$startupTab.Controls.AddRange(@($refreshStartup, $startupGrid, $disableStartup, $enableStartup, $startupNote))

function Update-ListLayout {
    foreach ($layout in @(
        @{ Page=$appsTab; Grid=$appGrid; Note=$appNote; NoteX=670; GridTop=82 },
        @{ Page=$startupTab; Grid=$startupGrid; Note=$startupNote; NoteX=445; GridTop=52 }
    )) {
        $width = $layout.Page.ClientSize.Width; $height = $layout.Page.ClientSize.Height
        if ($width -lt 300 -or $height -lt 180) { continue }
        $layout.Grid.SetBounds(12, $layout.GridTop, ($width - 24), [Math]::Max(80, ($height - $layout.GridTop - 12)))
        $layout.Note.SetBounds($layout.NoteX, 10, [Math]::Max(100, ($width - $layout.NoteX - 15)), 40)
    }
}
$appsTab.Add_Resize({ Update-ListLayout })
$startupTab.Add_Resize({ Update-ListLayout })
$tabs.Add_SelectedIndexChanged({ Update-ListLayout })

$securityText = New-Object System.Windows.Forms.Label; $securityText.SetBounds(20, 20, 880, 105)
$securityText.Text = "Microsoft Defender gerçek zamanlı koruması`r`n`r`nKoruma kapatıldığında bilgisayar zararlı yazılımlara karşı daha savunmasız olur. Windows korumayı yeniden açabilir veya kurcalama koruması değişikliği engelleyebilir."
$securityStatus = New-Object System.Windows.Forms.Label; $securityStatus.SetBounds(20, 135, 850, 28)
$securityRefresh = New-Button 'Durumu yenile' 20 175 140
$securityOff = New-Button 'Gerçek zamanlı korumayı kapat' 170 175 230
$securityOn = New-Button 'Korumayı aç' 410 175 140
$securityOpen = New-Button 'Windows Güvenliğini aç' 560 175 190
$securityTab.Controls.AddRange(@($securityText, $securityStatus, $securityRefresh, $securityOff, $securityOn, $securityOpen))

function Get-AppIcon($item) {
    try {
        if ($item.Kind -eq 'Win32' -and $item.IconPath) {
            $path = [Environment]::ExpandEnvironmentVariables([string]$item.IconPath).Trim()
            if ($path -match '^"([^"]+)"') { $path = $matches[1] }
            else { $path = $path -replace ',\s*-?\d+$', '' }
            if (Test-Path -LiteralPath $path -PathType Leaf) {
                $icon = [System.Drawing.Icon]::ExtractAssociatedIcon($path)
                if ($icon) { try { return $icon.ToBitmap() } finally { $icon.Dispose() } }
            }
        }
        if ($item.Kind -eq 'Appx' -and $item.InstallLocation) {
            $assets = Join-Path $item.InstallLocation 'Assets'
            if (Test-Path -LiteralPath $assets) {
                $logo = Get-ChildItem -LiteralPath $assets -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -match '(?i)(square44x44logo|smalllogo|appicon).*\.png$' } | Select-Object -First 1
                if ($logo) { $image = [System.Drawing.Image]::FromFile($logo.FullName); try { return New-Object System.Drawing.Bitmap($image) } finally { $image.Dispose() } }
            }
        }
    } catch { }
    return [System.Drawing.SystemIcons]::Application.ToBitmap()
}

function Refresh-AppRows {
    $appGrid.Rows.Clear()
    $needle = $search.Text.Trim()
    foreach ($item in $script:appItems) {
        if ($needle -and ($item.Name + ' ' + $item.Publisher + ' ' + $item.Type) -notlike ('*' + $needle + '*')) { continue }
        if (-not $item.Icon) { $item.Icon = Get-AppIcon $item }
        $i = $appGrid.Rows.Add($item.Icon, [string]$item.Name, [string]$item.Type, [string]$item.Publisher, [string]$item.Version, [string]$item.SizeText)
        $appGrid.Rows[$i].Tag = $item
    }
}
function Format-Size($kilobytes) {
    if ($null -eq $kilobytes -or $kilobytes -le 0) { return 'Bilinmiyor' }
    if ($kilobytes -ge 1MB) { return ('{0:N2} GB' -f ($kilobytes / 1MB)) }
    if ($kilobytes -ge 1KB) { return ('{0:N1} MB' -f ($kilobytes / 1KB)) }
    return ('{0:N0} KB' -f $kilobytes)
}
function Get-AppLocation($item) {
    if ($item.InstallLocation) {
        $location = [Environment]::ExpandEnvironmentVariables([string]$item.InstallLocation).Trim().Trim('"')
        if (Test-Path -LiteralPath $location -PathType Container -ErrorAction SilentlyContinue) { return $location }
    }
    if ($item.Kind -eq 'Win32' -and $item.IconPath) {
        $iconPath = [Environment]::ExpandEnvironmentVariables([string]$item.IconPath).Trim()
        if ($iconPath -match '^"([^"]+)"') { $iconPath = $matches[1] }
        else { $iconPath = $iconPath -replace ',\s*-?\d+$', '' }
        if ($iconPath -match '\.(exe|com)$' -and (Test-Path -LiteralPath $iconPath -PathType Leaf -ErrorAction SilentlyContinue)) {
            return [IO.Path]::GetDirectoryName($iconPath)
        }
    }
    return $null
}
function Load-Apps {
    $form.Cursor = [System.Windows.Forms.Cursors]::WaitCursor
    try {
        $items = New-Object 'System.Collections.Generic.List[object]'
        foreach ($pkg in @(Get-AppxPackage -PackageTypeFilter Main,Bundle,Framework,Resource -ErrorAction SilentlyContinue)) {
            $label = $pkg.Name
            if ($pkg.NonRemovable) { $type = 'Windows / Korumalı' } elseif ($pkg.IsFramework) { $type = 'Windows / Framework' } elseif ($pkg.IsResourcePackage) { $type = 'Windows / Kaynak' } else { $type = 'Windows / Store' }
            $items.Add([pscustomobject]@{ Name=$label; Type=$type; Publisher=$pkg.Publisher; Version=$pkg.Version; Kind='Appx'; Package=$pkg.PackageFullName; Command=$null; IconPath=$null; InstallLocation=$pkg.InstallLocation; Icon=$null; SizeText='Bilinmiyor'; Protected=[bool]$pkg.NonRemovable; RegistryPath=$null; NoRemove=$false })
        }
        $paths = @('HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*', 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*', 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*', 'HKCU:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*')
        foreach ($path in $paths) {
            foreach ($entry in @(Get-ItemProperty -Path $path -ErrorAction SilentlyContinue)) {
                if (-not $entry.DisplayName) { continue }
                $size = Format-Size $entry.EstimatedSize
                $items.Add([pscustomobject]@{ Name=$entry.DisplayName; Type='Masaüstü'; Publisher=$entry.Publisher; Version=$entry.DisplayVersion; Kind='Win32'; Package=$null; Command=$entry.UninstallString; IconPath=$entry.DisplayIcon; InstallLocation=$entry.InstallLocation; Icon=$null; SizeText=$size; Protected=$false; RegistryPath=$entry.PSPath; NoRemove=([bool]$entry.NoRemove) })
            }
        }
        foreach ($old in $script:appItems) { if ($old.Icon) { $old.Icon.Dispose() } }
        $script:appItems = @($items | Sort-Object Name,Type)
        Refresh-AppRows
        $appsTab.Text = 'Yüklü uygulamalar (' + $script:appItems.Count + ')'
    } catch { Message ('Liste okunamadı: ' + $_.Exception.Message) } finally { $form.Cursor = [System.Windows.Forms.Cursors]::Default }
}

function Load-Startup {
    $startupGrid.Rows.Clear()
    $locations = @(
        @{ Path='HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'; Label='Geçerli kullanıcı' },
        @{ Path='HKLM:\Software\Microsoft\Windows\CurrentVersion\Run'; Label='Tüm kullanıcılar (64 bit)' },
        @{ Path='HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Run'; Label='Tüm kullanıcılar (32 bit)' }
    )
    $items = New-Object 'System.Collections.Generic.List[object]'
    foreach ($loc in $locations) {
        if (-not (Test-Path $loc.Path)) { continue }
        $key = Get-Item -LiteralPath $loc.Path
        foreach ($name in $key.GetValueNames()) {
            $items.Add([pscustomobject]@{ Name=$name; Status='Kayıt var'; Location=$loc.Label; Command=[string]$key.GetValue($name, $null, 'DoNotExpandEnvironmentNames'); Path=$loc.Path; Backup=$null; ValueKind=$key.GetValueKind($name).ToString() })
        }
    }
    if (Test-Path $script:backupRoot) {
        foreach ($key in @(Get-ChildItem $script:backupRoot)) {
            $b = Get-ItemProperty -LiteralPath $key.PSPath
            $items.Add([pscustomobject]@{ Name=$b.EntryName; Status='Bu araçla kapalı'; Location=$b.Location; Command=$b.Command; Path=$b.SourcePath; Backup=$key.PSPath; ValueKind=$b.ValueKind })
        }
    }
    $script:startupItems = @($items | Sort-Object Name)
    foreach ($item in $script:startupItems) {
        $i = $startupGrid.Rows.Add([string]$item.Name, [string]$item.Status, [string]$item.Location, [string]$item.Command)
        $startupGrid.Rows[$i].Tag = $item
    }
}
function Update-SecurityStatus {
    try {
        $status = Get-MpComputerStatus -ErrorAction Stop
        if ($status.RealTimeProtectionEnabled) { $securityStatus.Text = 'Durum: Gerçek zamanlı koruma açık.' }
        else { $securityStatus.Text = 'Durum: Gerçek zamanlı koruma kapalı.' }
    } catch { $securityStatus.Text = 'Durum okunamadı: ' + $_.Exception.Message }
}

$search.Add_TextChanged({ Refresh-AppRows })
$appGrid.Add_CellMouseDown({
    param($sender, $e)
    if ($e.Button -eq [System.Windows.Forms.MouseButtons]::Right -and $e.RowIndex -ge 0) {
        $sender.ClearSelection(); $sender.Rows[$e.RowIndex].Selected = $true
        $sender.CurrentCell = $sender.Rows[$e.RowIndex].Cells['Name']
    }
})
$appMenu.Add_Opening({ param($sender, $e) if (-not $appGrid.CurrentRow) { $e.Cancel = $true } })
$openLocation.Add_Click({
    if (-not $appGrid.CurrentRow -or -not $appGrid.CurrentRow.Tag) { return }
    try {
        $location = Get-AppLocation $appGrid.CurrentRow.Tag
        if (-not $location) { Message 'Bu uygulama için geçerli bir dosya konumu bulunamadı.'; return }
        Start-Process -FilePath 'explorer.exe' -ArgumentList ('"' + $location + '"') -ErrorAction Stop | Out-Null
    } catch { Message ('Dosya konumu açılamadı: ' + $_.Exception.Message) }
})
$refreshApps.Add_Click({ Load-Apps })
$refreshStartup.Add_Click({ try { Load-Startup } catch { Message ('Başlangıç listesi okunamadı: ' + $_.Exception.Message) } })
$script:removeWorker = $null
$script:removeResult = $null
$script:removeKind = $null
$script:removeItem = $null
$removeTimer = New-Object System.Windows.Forms.Timer; $removeTimer.Interval = 250
$removeTimer.Add_Tick({
    if (-not $script:removeResult.IsCompleted) { return }
    $removeTimer.Stop()
    $errorText = $null
    $exitCode = $null
    try { $resultOutput = @($script:removeWorker.EndInvoke($script:removeResult)); if ($script:removeKind -eq 'Win32' -and $resultOutput.Count -gt 0) { $exitCode = $resultOutput[-1] } }
    catch { $errorText = $_.Exception.Message }
    finally {
        $script:removeWorker.Dispose(); $script:removeWorker = $null; $script:removeResult = $null
        $progress.Visible = $false; $progressText.Visible = $false
        $uninstall.Enabled = $true; $refreshApps.Enabled = $true
    }
    if ($errorText) {
        if ($errorText -match '0x80070032|cannot be uninstalled on a per-user basis|0x80073CFA') {
            Message ('Windows kaldırma işlemini tamamlamadı. Uygulama bir sistem bileşeni olabilir veya başka bir nedenle korunuyor olabilir. Ayrıntı: ' + $errorText)
        } else { Message ('Kaldırma başarısız oldu: ' + $errorText) }
    } elseif ($script:removeKind -eq 'Appx') {
        try {
            $stillPresent = @(Get-AppxPackage -ErrorAction Stop | Where-Object { $_.PackageFullName -eq $script:removeItem.Package }).Count -gt 0
            if ($stillPresent) { Message 'Komut sona erdi ancak paket hâlâ yüklü görünüyor. Kaldırma tamamlanmamış olabilir.' }
            else { Message 'Paket artık bu kullanıcının uygulama listesinde görünmüyor.' }
        } catch { Message 'Kaldırma komutu sona erdi, ancak paket durumu doğrulanamadı. Listeyi kontrol et.' }
    } else {
        $stillPresent = $script:removeItem.RegistryPath -and (Test-Path -LiteralPath $script:removeItem.RegistryPath -ErrorAction SilentlyContinue)
        if ($stillPresent) {
            Message ("Kaldırıcı kapandı ancak uygulamanın Windows kaydı hâlâ var. Kaldırma tamamlanmamış, iptal edilmiş veya arka planda devam ediyor olabilir. İşlem kodu: $exitCode")
        } elseif ($exitCode -ne 0 -and $null -ne $exitCode) {
            Message ("Uygulamanın kayıt defteri girdisi artık bulunmuyor, ancak kaldırıcı $exitCode koduyla çıktı. Programın durumunu kontrol et.")
        } else { Message 'Uygulamanın kaldırma kaydı artık bulunmuyor. Kalan dosyalar varsa ayrıca kontrol etmek gerekebilir.' }
    }
    Load-Apps
})
$uninstall.Add_Click({
    if (-not $appGrid.CurrentRow) { Message 'Önce bir uygulama seç.'; return }
    $item = $appGrid.CurrentRow.Tag
    if (-not $item) { return }
    if ($item.Protected) { Message 'Bu uygulama Windows tarafından kaldırılamayan bir sistem bileşeni olarak işaretlenmiş. Bu araçla kaldırılamaz.'; return }
    if ($item.Kind -eq 'Win32' -and -not $item.Command) { Message 'Bu program kaldırma komutu kaydetmemiş. Windows Ayarları veya programın kendi kaldırma aracını kullanabilirsin.'; return }
    $commandToRun = $item.Command
    $isEdge = $item.Kind -eq 'Win32' -and $item.Name -eq 'Microsoft Edge' -and $item.RegistryPath -match '\\Uninstall\\Microsoft Edge$'
    if ($isEdge) {
        if (-not (Confirm 'Microsoft Edge için zorlamalı kaldırma denenecek. Edge kullanan web uygulamaları ve Windows özellikleri etkilenebilir. Windows bu işlemi yine de engelleyebilir. Devam edilsin mi?')) { return }
        if ($commandToRun -notmatch '(?i)(?:^|\s)--force-uninstall(?:\s|$)') { $commandToRun += ' --force-uninstall' }
    } elseif ($item.NoRemove -and -not (Confirm 'Windows bu uygulama için normal kaldırma seçeneğini gizliyor. Kaldırıcı çalışsa bile işlem başarısız olabilir. Yine de denensin mi?')) { return }
    if (-not (Confirm ("$($item.Name) kaldırılsın mı?`r`n`r`nBazı uygulamalar veri kaybına yol açabilir veya başka uygulamalar tarafından kullanılıyor olabilir."))) { return }
    try {
        if ($item.Kind -eq 'Win32') { Message 'Programın kendi kaldırma ekranı açılacak. Oradaki adımları tamamla.' }
        $script:removeKind = $item.Kind
        $script:removeItem = $item
        $script:removeWorker = [PowerShell]::Create()
        [void]$script:removeWorker.AddScript({
            param($kind, $package, $command)
            $ErrorActionPreference = 'Stop'
            if ($kind -eq 'Appx') { Remove-AppxPackage -Package $package -ErrorAction Stop }
            else { $process = Start-Process -FilePath $env:ComSpec -ArgumentList @('/d', '/s', '/c', ('"' + $command + '"')) -Wait -PassThru -ErrorAction Stop; $process.ExitCode }
        }).AddArgument($item.Kind).AddArgument($item.Package).AddArgument($commandToRun)
        $script:removeResult = $script:removeWorker.BeginInvoke()
        $uninstall.Enabled = $false; $refreshApps.Enabled = $false
        $progressText.Text = 'Kaldırma sürüyor... Gerçek yüzde bilgisi bu işlemde alınamıyor.'
        $progress.Visible = $true; $progressText.Visible = $true
        $removeTimer.Start()
    } catch { Message ('Kaldırma başarısız oldu: ' + $_.Exception.Message) }
})
$disableStartup.Add_Click({
    if (-not $startupGrid.CurrentRow) { Message 'Önce bir başlangıç kaydı seç.'; return }
    $item = $startupGrid.CurrentRow.Tag
    if ($item.Backup) { Message 'Bu kayıt zaten bu araçla kapatılmış.'; return }
    if (-not (Confirm ("$($item.Name) başlangıçta çalışmasın mı?"))) { return }
    try {
        $source = Get-Item -LiteralPath $item.Path -ErrorAction Stop
        if ($source.GetValueNames() -notcontains $item.Name) { throw 'Kayıt artık bulunamadı. Listeyi yenile.' }
        $currentValue = $source.GetValue($item.Name, $null, 'DoNotExpandEnvironmentNames')
        $kind = $source.GetValueKind($item.Name).ToString()
        if ($kind -notin @('String','ExpandString')) { throw 'Bu kayıt türü desteklenmiyor.' }
        $id = [guid]::NewGuid().ToString()
        $path = Join-Path $script:backupRoot $id
        New-Item -Path $path -Force | Out-Null
        Set-ItemProperty -LiteralPath $path -Name EntryName -Value $item.Name
        Set-ItemProperty -LiteralPath $path -Name SourcePath -Value $item.Path
        Set-ItemProperty -LiteralPath $path -Name Location -Value $item.Location
        Set-ItemProperty -LiteralPath $path -Name Command -Value ([string]$currentValue)
        Set-ItemProperty -LiteralPath $path -Name ValueKind -Value $kind
        Remove-ItemProperty -LiteralPath $item.Path -Name $item.Name -ErrorAction Stop
        Load-Startup
    } catch { Message ('Başlangıç kaydı değiştirilemedi: ' + $_.Exception.Message) }
})
$enableStartup.Add_Click({
    if (-not $startupGrid.CurrentRow) { Message 'Önce bir başlangıç kaydı seç.'; return }
    $item = $startupGrid.CurrentRow.Tag
    if (-not $item.Backup) { Message 'Bu kayıt bu araçla kapatılmamış. Görev Yöneticisi başlangıç durumunu ayrıca kontrol edebilirsin.'; return }
    if (-not (Confirm ("$($item.Name) başlangıçta tekrar çalışsın mı?"))) { return }
    try {
        if (-not (Test-Path $item.Path)) { New-Item -Path $item.Path -Force | Out-Null }
        $key = Get-Item -LiteralPath $item.Path
        if ($key.GetValueNames() -contains $item.Name) { throw 'Aynı isimde bir başlangıç kaydı zaten var. Mevcut kayıt değiştirilmedi.' }
        $kind = [Microsoft.Win32.RegistryValueKind]::$($item.ValueKind)
        $key.SetValue($item.Name, $item.Command, $kind)
        Remove-Item -LiteralPath $item.Backup -Force -ErrorAction Stop
        Load-Startup
    } catch { Message ('Başlangıç kaydı geri açılamadı: ' + $_.Exception.Message) }
})
$securityRefresh.Add_Click({ Update-SecurityStatus })
$securityOpen.Add_Click({ try { Start-Process 'windowsdefender:' } catch { Message ('Windows Güvenliği açılamadı: ' + $_.Exception.Message) } })
$securityOff.Add_Click({
    if (-not (Confirm 'Gerçek zamanlı koruma kapatılmaya çalışılsın mı? Bu, zararlı yazılımlara karşı korumayı azaltır. Windows bu değişikliği engelleyebilir veya sonradan geri alabilir.')) { return }
    try { Set-MpPreference -DisableRealtimeMonitoring $true -ErrorAction Stop; Update-SecurityStatus; Message $securityStatus.Text }
    catch { Update-SecurityStatus; Message ('İşlem uygulanamadı: ' + $_.Exception.Message + "`r`nWindows Güvenliği ayarlarını kontrol edebilirsin.") }
})
$securityOn.Add_Click({
    try { Set-MpPreference -DisableRealtimeMonitoring $false -ErrorAction Stop; Update-SecurityStatus; Message $securityStatus.Text }
    catch { Update-SecurityStatus; Message ('Koruma açılamadı: ' + $_.Exception.Message) }
})
$form.Add_Shown({ Update-ListLayout; Load-Apps; try { Load-Startup } catch { Message ('Başlangıç listesi okunamadı: ' + $_.Exception.Message) }; Update-SecurityStatus })
[void]$form.ShowDialog()
