$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

Add-Type @"
using System;
using System.Text;
using System.Runtime.InteropServices;

public static class SageLabelNativeMethods
{
    public delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);

    [DllImport("user32.dll")]
    public static extern bool EnumWindows(EnumWindowsProc enumProc, IntPtr lParam);

    [DllImport("user32.dll")]
    public static extern int GetWindowText(IntPtr hWnd, StringBuilder text, int count);

    [DllImport("user32.dll")]
    public static extern int GetWindowTextLength(IntPtr hWnd);

    [DllImport("user32.dll")]
    public static extern bool IsWindowVisible(IntPtr hWnd);

    [DllImport("user32.dll")]
    public static extern bool SetForegroundWindow(IntPtr hWnd);

    [DllImport("user32.dll")]
    public static extern IntPtr GetForegroundWindow();

    [DllImport("user32.dll")]
    public static extern bool SetCursorPos(int x, int y);

    [DllImport("user32.dll")]
    public static extern void mouse_event(int flags, int dx, int dy, int data, int extraInfo);

    [DllImport("user32.dll")]
    public static extern short GetAsyncKeyState(int virtualKeyCode);
}
"@

$Script:ConfigPath = Join-Path $PSScriptRoot 'print-steps.ini'
$Script:AbortRequested = $false
$Script:StatusLabel = $null

function New-DefaultConfig {
    param([string] $Path)

    $content = @'
[Settings]
WindowTitle=Sage 200
DelayMs=300
UsePrinterCopies=false

[Steps]
; Replace these example steps with the exact Sage actions needed to print one label.
; Use {label} wherever the pallet label value should be typed.
; Use {copies} wherever the labels-per-pallet value should be typed.
1=tooltip|Printing {label}
2=send|^p
3=sleep|500
4=text|{label}
5=send|{Enter}
'@

    Set-Content -LiteralPath $Path -Value $content -Encoding UTF8
}

function Read-IniFile {
    param([string] $Path)

    if (!(Test-Path -LiteralPath $Path)) {
        New-DefaultConfig -Path $Path
    }

    $ini = @{}
    $section = ''

    foreach ($line in Get-Content -LiteralPath $Path) {
        $trimmed = $line.Trim()

        if ($trimmed.Length -eq 0 -or $trimmed.StartsWith(';') -or $trimmed.StartsWith('#')) {
            continue
        }

        if ($trimmed.StartsWith('[') -and $trimmed.EndsWith(']')) {
            $section = $trimmed.Substring(1, $trimmed.Length - 2)
            if (!$ini.ContainsKey($section)) {
                $ini[$section] = @{}
            }
            continue
        }

        $separator = $trimmed.IndexOf('=')
        if ($separator -lt 0) {
            continue
        }

        if (!$ini.ContainsKey($section)) {
            $ini[$section] = @{}
        }

        $key = $trimmed.Substring(0, $separator).Trim()
        $value = $trimmed.Substring($separator + 1).Trim()
        $ini[$section][$key] = $value
    }

    return $ini
}

function Get-IniValue {
    param(
        [hashtable] $Ini,
        [string] $Section,
        [string] $Key,
        [string] $Default
    )

    if ($Ini.ContainsKey($Section) -and $Ini[$Section].ContainsKey($Key)) {
        return $Ini[$Section][$Key]
    }

    return $Default
}

function Get-StepList {
    param([hashtable] $Ini)

    if (!$Ini.ContainsKey('Steps')) {
        throw 'print-steps.ini is missing the [Steps] section.'
    }

    return @(
        $Ini['Steps'].Keys |
            Where-Object { $_ -match '^\d+$' } |
            Sort-Object { [int] $_ } |
            ForEach-Object { $Ini['Steps'][$_] }
    )
}

function ConvertTo-PositiveInteger {
    param(
        [string] $Value,
        [string] $FieldName
    )

    $number = 0
    if (![int]::TryParse($Value, [ref] $number) -or $number -lt 1) {
        throw "$FieldName must be a positive whole number."
    }

    return $number
}

function ConvertTo-BooleanSetting {
    param(
        [string] $Value,
        [bool] $Default
    )

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return $Default
    }

    switch ($Value.Trim().ToLowerInvariant()) {
        '1' { return $true }
        'true' { return $true }
        'yes' { return $true }
        'on' { return $true }
        '0' { return $false }
        'false' { return $false }
        'no' { return $false }
        'off' { return $false }
        default { return $Default }
    }
}

function Get-Labels {
    param(
        [string] $Prefix,
        [string] $StartSuffix,
        [string] $SuffixWidth,
        [string] $PalletCount,
        [string] $ExactLabels
    )

    $labels = New-Object System.Collections.Generic.List[string]

    if (![string]::IsNullOrWhiteSpace($ExactLabels)) {
        foreach ($rawLabel in $ExactLabels.Split(',')) {
            $label = $rawLabel.Trim()
            if ($label.Length -gt 0) {
                $labels.Add($label)
            }
        }

        if ($labels.Count -eq 0) {
            throw 'Exact labels was filled in, but no labels were found.'
        }

        return $labels
    }

    $cleanPrefix = $Prefix.Trim()
    if ($cleanPrefix.Length -eq 0) {
        throw 'Prefix / order number is required.'
    }

    $start = ConvertTo-PositiveInteger -Value $StartSuffix -FieldName 'Start suffix'
    $width = ConvertTo-PositiveInteger -Value $SuffixWidth -FieldName 'Suffix width'
    $count = ConvertTo-PositiveInteger -Value $PalletCount -FieldName 'Number of pallets'

    for ($index = 0; $index -lt $count; $index++) {
        $suffix = ($start + $index).ToString().PadLeft($width, '0')
        $labels.Add("$cleanPrefix-$suffix")
    }

    return $labels
}

function Get-PreviewText {
    param(
        [System.Collections.Generic.List[string]] $Labels,
        [int] $Copies
    )

    $lines = New-Object System.Collections.Generic.List[string]
    $maxLines = 40

    foreach ($label in $Labels) {
        for ($copy = 0; $copy -lt $Copies; $copy++) {
            if ($lines.Count -ge $maxLines) {
                $remaining = ($Labels.Count * $Copies) - $lines.Count
                if ($remaining -gt 0) {
                    $lines.Add("...and $remaining more label(s).")
                }
                return ($lines -join [Environment]::NewLine)
            }

            $lines.Add($label)
        }
    }

    return ($lines -join [Environment]::NewLine)
}

function Set-Status {
    param([string] $Message)

    if ($null -ne $Script:StatusLabel) {
        $Script:StatusLabel.Text = $Message
        [System.Windows.Forms.Application]::DoEvents()
    }

    Write-Host $Message
}

function Test-StopRequested {
    # 0x1B is the Escape key. This works even while Sage has focus.
    if (([SageLabelNativeMethods]::GetAsyncKeyState(0x1B) -band 0x8000) -ne 0) {
        $Script:AbortRequested = $true
    }

    return $Script:AbortRequested
}

function Find-WindowByTitle {
    param([string] $Title)

    $Script:FoundWindow = [IntPtr]::Zero
    $comparison = [StringComparison]::OrdinalIgnoreCase

    $callback = [SageLabelNativeMethods+EnumWindowsProc] {
        param([IntPtr] $hWnd, [IntPtr] $lParam)

        if (![SageLabelNativeMethods]::IsWindowVisible($hWnd)) {
            return $true
        }

        $length = [SageLabelNativeMethods]::GetWindowTextLength($hWnd)
        if ($length -le 0) {
            return $true
        }

        $builder = New-Object System.Text.StringBuilder($length + 1)
        [void] [SageLabelNativeMethods]::GetWindowText($hWnd, $builder, $builder.Capacity)
        $windowTitle = $builder.ToString()

        if ($windowTitle.IndexOf($Title, $comparison) -ge 0) {
            $Script:FoundWindow = $hWnd
            return $false
        }

        return $true
    }

    [void] [SageLabelNativeMethods]::EnumWindows($callback, [IntPtr]::Zero)
    return $Script:FoundWindow
}

function Get-ForegroundWindowTitle {
    $hWnd = [SageLabelNativeMethods]::GetForegroundWindow()
    if ($hWnd -eq [IntPtr]::Zero) {
        return ''
    }

    $length = [SageLabelNativeMethods]::GetWindowTextLength($hWnd)
    if ($length -le 0) {
        return ''
    }

    $builder = New-Object System.Text.StringBuilder($length + 1)
    [void] [SageLabelNativeMethods]::GetWindowText($hWnd, $builder, $builder.Capacity)
    return $builder.ToString()
}

function Invoke-ActivateWindow {
    param([string] $Title)

    $hWnd = Find-WindowByTitle -Title $Title
    if ($hWnd -eq [IntPtr]::Zero) {
        throw "Could not find a window containing: $Title"
    }

    [void] [SageLabelNativeMethods]::SetForegroundWindow($hWnd)
    Start-Sleep -Milliseconds 300
}

function Wait-ForWindow {
    param(
        [string] $Title,
        [switch] $Active
    )

    $deadline = (Get-Date).AddSeconds(10)

    while ((Get-Date) -lt $deadline) {
        if (Test-StopRequested) {
            return
        }

        if ($Active) {
            $currentTitle = Get-ForegroundWindowTitle
            if ($currentTitle.IndexOf($Title, [StringComparison]::OrdinalIgnoreCase) -ge 0) {
                return
            }
        } else {
            if ((Find-WindowByTitle -Title $Title) -ne [IntPtr]::Zero) {
                return
            }
        }

        Start-Sleep -Milliseconds 200
    }

    if ($Active) {
        throw "Timed out waiting for active window: $Title"
    }

    throw "Timed out waiting for window: $Title"
}

function Convert-SendKeysSyntax {
    param([string] $Keys)

    # AutoHotkey uses ! for Alt. Windows Forms SendKeys uses % for Alt.
    return $Keys.Replace('!', '%')
}

function Send-LiteralText {
    param([string] $Text)

    if ($Text.Length -eq 0) {
        return
    }

    $previousClipboard = ''
    $hadTextClipboard = $false

    try {
        $hadTextClipboard = [System.Windows.Forms.Clipboard]::ContainsText()
        if ($hadTextClipboard) {
            $previousClipboard = [System.Windows.Forms.Clipboard]::GetText()
        }
    } catch {
        $hadTextClipboard = $false
    }

    [System.Windows.Forms.Clipboard]::SetText($Text)
    [System.Windows.Forms.SendKeys]::SendWait('^v')
    Start-Sleep -Milliseconds 100

    if ($hadTextClipboard -and $null -ne $previousClipboard) {
        [System.Windows.Forms.Clipboard]::SetText($previousClipboard)
    } else {
        [System.Windows.Forms.Clipboard]::Clear()
    }
}

function Invoke-MouseClick {
    param(
        [int] $X,
        [int] $Y
    )

    [void] [SageLabelNativeMethods]::SetCursorPos($X, $Y)
    Start-Sleep -Milliseconds 50
    [SageLabelNativeMethods]::mouse_event(0x0002, 0, 0, 0, 0)
    [SageLabelNativeMethods]::mouse_event(0x0004, 0, 0, 0, 0)
}

function Expand-StepTokens {
    param(
        [string] $Value,
        [string] $Label,
        [int] $Copies
    )

    return $Value.Replace('{label}', $Label).Replace('{copies}', $Copies.ToString())
}

function Invoke-Step {
    param(
        [string] $Step,
        [string] $Label,
        [int] $Copies,
        [int] $DefaultDelayMs
    )

    $separator = $Step.IndexOf('|')
    if ($separator -lt 0) {
        $command = $Step.Trim().ToLowerInvariant()
        $argument = ''
    } else {
        $command = $Step.Substring(0, $separator).Trim().ToLowerInvariant()
        $argument = Expand-StepTokens -Value $Step.Substring($separator + 1).Trim() -Label $Label -Copies $Copies
    }

    switch ($command) {
        'send' {
            [System.Windows.Forms.SendKeys]::SendWait((Convert-SendKeysSyntax -Keys $argument))
        }
        'text' {
            Send-LiteralText -Text $argument
        }
        'sleep' {
            Start-Sleep -Milliseconds (ConvertTo-PositiveInteger -Value $argument -FieldName 'sleep')
        }
        'click' {
            $parts = $argument.Split('|')
            if ($parts.Count -lt 2) {
                throw 'Click step must be formatted as click|x|y.'
            }

            Invoke-MouseClick -X ([int] $parts[0]) -Y ([int] $parts[1])
        }
        'activate' {
            Invoke-ActivateWindow -Title $argument
        }
        'waitwin' {
            Wait-ForWindow -Title $argument
        }
        'waitactive' {
            Wait-ForWindow -Title $argument -Active
        }
        'tooltip' {
            Set-Status -Message $argument
            Start-Sleep -Milliseconds $DefaultDelayMs
        }
        default {
            throw "Unknown step command: $command"
        }
    }

    Start-Sleep -Milliseconds $DefaultDelayMs
}

function Invoke-PrintOneLabel {
    param(
        [string] $Label,
        [int] $Copies,
        [string[]] $Steps,
        [int] $DefaultDelayMs
    )

    foreach ($step in $Steps) {
        if (Test-StopRequested) {
            return
        }

        Invoke-Step -Step $step -Label $Label -Copies $Copies -DefaultDelayMs $DefaultDelayMs
    }
}

function Invoke-PrintRun {
    param(
        [string] $Prefix,
        [string] $StartSuffix,
        [string] $SuffixWidth,
        [string] $PalletCount,
        [string] $LabelsPerPallet,
        [string] $ExactLabels,
        [bool] $DryRun
    )

    $labels = Get-Labels -Prefix $Prefix -StartSuffix $StartSuffix -SuffixWidth $SuffixWidth -PalletCount $PalletCount -ExactLabels $ExactLabels
    $copies = ConvertTo-PositiveInteger -Value $LabelsPerPallet -FieldName 'Labels per pallet'
    $preview = Get-PreviewText -Labels $labels -Copies $copies
    $ini = Read-IniFile -Path $Script:ConfigPath
    $confirmBeforeRun = ConvertTo-BooleanSetting -Value (Get-IniValue -Ini $ini -Section 'Settings' -Key 'ConfirmBeforeRun' -Default 'true') -Default $true
    $showCompleteMessage = ConvertTo-BooleanSetting -Value (Get-IniValue -Ini $ini -Section 'Settings' -Key 'ShowCompleteMessage' -Default 'true') -Default $true

    if ($confirmBeforeRun) {
        $confirm = [System.Windows.Forms.MessageBox]::Show(
            "The macro will process labels in this order:`r`n`r`n$preview",
            'Confirm label order',
            [System.Windows.Forms.MessageBoxButtons]::OKCancel,
            [System.Windows.Forms.MessageBoxIcon]::Information
        )

        if ($confirm -ne [System.Windows.Forms.DialogResult]::OK) {
            return
        }
    }

    if ($DryRun) {
        [void] [System.Windows.Forms.MessageBox]::Show(
            "Dry run only. Nothing was sent to Sage.`r`n`r`n$preview",
            'Dry run complete',
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Information
        )
        return
    }

    $windowTitle = Get-IniValue -Ini $ini -Section 'Settings' -Key 'WindowTitle' -Default 'Sage 200'
    $delayMs = ConvertTo-PositiveInteger -Value (Get-IniValue -Ini $ini -Section 'Settings' -Key 'DelayMs' -Default '300') -FieldName 'DelayMs'
    $usePrinterCopies = ConvertTo-BooleanSetting -Value (Get-IniValue -Ini $ini -Section 'Settings' -Key 'UsePrinterCopies' -Default 'false') -Default $false
    $steps = Get-StepList -Ini $ini

    if ($steps.Count -eq 0) {
        throw 'print-steps.ini does not contain any numbered steps.'
    }

    $Script:AbortRequested = $false
    Invoke-ActivateWindow -Title $windowTitle

    foreach ($label in $labels) {
        $repeatCount = $copies
        if ($usePrinterCopies) {
            $repeatCount = 1
        }

        for ($copy = 0; $copy -lt $repeatCount; $copy++) {
            if (Test-StopRequested) {
                [void] [System.Windows.Forms.MessageBox]::Show('Stopped before printing the next label.', 'Stopped')
                return
            }

            if ($usePrinterCopies) {
                Set-Status -Message "Printing $label ($copies printer copies)"
            } else {
                Set-Status -Message "Printing $label ($($copy + 1) of $copies)"
            }

            Invoke-PrintOneLabel -Label $label -Copies $copies -Steps $steps -DefaultDelayMs $delayMs
            Start-Sleep -Milliseconds $delayMs
        }
    }

    if ($showCompleteMessage) {
        [void] [System.Windows.Forms.MessageBox]::Show(
            "Finished printing $($labels.Count) pallet(s), $copies label(s) each.",
            'Complete',
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Information
        )
    } else {
        Set-Status -Message "Finished printing $($labels.Count) pallet(s), $copies label(s) each."
    }
}

function Add-Label {
    param(
        [System.Windows.Forms.Form] $Form,
        [string] $Text,
        [int] $X,
        [int] $Y,
        [int] $Width = 120
    )

    $label = New-Object System.Windows.Forms.Label
    $label.Text = $Text
    $label.Location = New-Object System.Drawing.Point($X, $Y)
    $label.Size = New-Object System.Drawing.Size($Width, 20)
    [void] $Form.Controls.Add($label)
    return $label
}

function Add-TextBox {
    param(
        [System.Windows.Forms.Form] $Form,
        [string] $Text,
        [int] $X,
        [int] $Y,
        [int] $Width = 120
    )

    $textBox = New-Object System.Windows.Forms.TextBox
    $textBox.Text = $Text
    $textBox.Location = New-Object System.Drawing.Point($X, $Y)
    $textBox.Size = New-Object System.Drawing.Size($Width, 24)
    [void] $Form.Controls.Add($textBox)
    return $textBox
}

function Show-MainForm {
    if (!(Test-Path -LiteralPath $Script:ConfigPath)) {
        New-DefaultConfig -Path $Script:ConfigPath
    }

    $form = New-Object System.Windows.Forms.Form
    $form.Text = 'Label Printer Macro'
    $form.StartPosition = 'CenterScreen'
    $form.Size = New-Object System.Drawing.Size(430, 275)
    $form.FormBorderStyle = 'FixedDialog'
    $form.MaximizeBox = $false

    [void] (Add-Label -Form $form -Text 'Pages to print, comma-separated' -X 16 -Y 18 -Width 240)
    $pagesBox = Add-TextBox -Form $form -Text '1,2,3,4,5,6,7' -X 16 -Y 40 -Width 380

    [void] (Add-Label -Form $form -Text 'Labels per pallet' -X 16 -Y 82 -Width 130)
    $copiesBox = Add-TextBox -Form $form -Text '2' -X 16 -Y 104 -Width 110

    $dryRunBox = New-Object System.Windows.Forms.CheckBox
    $dryRunBox.Text = 'Dry run - show order without printing'
    $dryRunBox.Location = New-Object System.Drawing.Point(16, 140)
    $dryRunBox.Size = New-Object System.Drawing.Size(300, 24)
    $dryRunBox.Checked = $true
    [void] $form.Controls.Add($dryRunBox)

    $runButton = New-Object System.Windows.Forms.Button
    $runButton.Text = 'Run'
    $runButton.Location = New-Object System.Drawing.Point(16, 177)
    $runButton.Size = New-Object System.Drawing.Size(90, 30)
    [void] $form.Controls.Add($runButton)

    $openStepsButton = New-Object System.Windows.Forms.Button
    $openStepsButton.Text = 'Open steps'
    $openStepsButton.Location = New-Object System.Drawing.Point(116, 177)
    $openStepsButton.Size = New-Object System.Drawing.Size(95, 30)
    [void] $form.Controls.Add($openStepsButton)

    $copyMouseButton = New-Object System.Windows.Forms.Button
    $copyMouseButton.Text = 'Copy click'
    $copyMouseButton.Location = New-Object System.Drawing.Point(221, 177)
    $copyMouseButton.Size = New-Object System.Drawing.Size(95, 30)
    [void] $form.Controls.Add($copyMouseButton)

    $Script:StatusLabel = New-Object System.Windows.Forms.Label
    $Script:StatusLabel.Text = 'Ready. Press Esc during printing to stop after the current step.'
    $Script:StatusLabel.Location = New-Object System.Drawing.Point(16, 220)
    $Script:StatusLabel.Size = New-Object System.Drawing.Size(380, 30)
    [void] $form.Controls.Add($Script:StatusLabel)

    $runButton.Add_Click({
        try {
            if ([string]::IsNullOrWhiteSpace($pagesBox.Text)) {
                throw 'Pages to print is required. Example: 1,2,3,4,5,6,7'
            }

            Invoke-PrintRun `
                -Prefix 'Page' `
                -StartSuffix '1' `
                -SuffixWidth '1' `
                -PalletCount '1' `
                -LabelsPerPallet $copiesBox.Text `
                -ExactLabels $pagesBox.Text `
                -DryRun $dryRunBox.Checked
        } catch {
            [void] [System.Windows.Forms.MessageBox]::Show(
                "Macro stopped:`r`n`r`n$($_.Exception.Message)",
                'Label Printer Macro',
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Error
            )
        }
    })

    $openStepsButton.Add_Click({
        Start-Process -FilePath notepad.exe -ArgumentList "`"$Script:ConfigPath`""
    })

    $copyMouseButton.Add_Click({
        $copyMouseButton.Enabled = $false
        Set-Status -Message 'Move the mouse over the Sage field to click. Capturing in 3 seconds...'
        [System.Windows.Forms.Application]::DoEvents()
        Start-Sleep -Seconds 3

        $position = [System.Windows.Forms.Cursor]::Position
        $step = "click|$($position.X)|$($position.Y)"
        [System.Windows.Forms.Clipboard]::SetText($step)
        Set-Status -Message "Copied to clipboard: $step"
        $copyMouseButton.Enabled = $true
    })

    [void] $form.ShowDialog()
}

Show-MainForm
