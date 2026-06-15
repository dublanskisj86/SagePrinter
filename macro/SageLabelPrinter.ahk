#Requires AutoHotkey v2.0
#SingleInstance Force

ConfigPath := A_ScriptDir "\print-steps.ini"
AbortRequested := false

F8::OpenMainGui()
Esc::RequestAbort()
F9::CopyMouseClickStep()
F10::CopyActiveWindowTitle()

OpenMainGui() {
    global ConfigPath

    if !FileExist(ConfigPath) {
        CreateDefaultConfig(ConfigPath)
    }

    mainGui := Gui(, "Label Printer Macro")
    mainGui.SetFont("s10", "Segoe UI")
    mainGui.MarginX := 14
    mainGui.MarginY := 12

    mainGui.Add("Text", "xm ym", "Prefix / order number")
    mainGui.Add("Edit", "vPrefix w150", "26166")

    mainGui.Add("Text", "x+18 yp", "Start suffix")
    mainGui.Add("Edit", "vStartSuffix w70 Number", "1")

    mainGui.Add("Text", "x+18 yp", "Suffix width")
    mainGui.Add("Edit", "vSuffixWidth w70 Number", "2")

    mainGui.Add("Text", "xm y+14", "Number of pallets")
    mainGui.Add("Edit", "vPalletCount w100 Number", "3")

    mainGui.Add("Text", "x+18 yp", "Labels per pallet")
    mainGui.Add("Edit", "vLabelsPerPallet w110 Number", "2")

    mainGui.Add("Text", "xm y+14", "Optional exact labels, comma-separated")
    mainGui.Add("Edit", "vLabelList xm y+4 w430", "")

    mainGui.Add("Checkbox", "vDryRun xm y+12 Checked", "Dry run - show order without printing")

    runButton := mainGui.Add("Button", "xm y+14 w120 Default", "Run")
    configButton := mainGui.Add("Button", "x+8 yp w120", "Open steps")
    closeButton := mainGui.Add("Button", "x+8 yp w90", "Close")

    mainGui.Add("Text", "xm y+12 w430", "F9 copies a click step. F10 copies the active window title. Esc stops after the current step.")

    runButton.OnEvent("Click", (*) => RunFromGui(mainGui))
    configButton.OnEvent("Click", (*) => Run("notepad.exe " Quote(ConfigPath)))
    closeButton.OnEvent("Click", (*) => mainGui.Destroy())

    mainGui.Show()
}

RunFromGui(mainGui) {
    global AbortRequested, ConfigPath

    values := mainGui.Submit(false)

    try {
        labels := BuildLabelList(values)
        copies := PositiveInteger(values.LabelsPerPallet, "Labels per pallet")
        dryRun := values.DryRun = 1

        preview := BuildPreview(labels, copies)
        if MsgBox("The macro will process labels in this order:`n`n" preview, "Confirm label order", "OKCancel Iconi") = "Cancel" {
            return
        }

        AbortRequested := false

        if dryRun {
            MsgBox("Dry run only. Nothing was sent to Sage.`n`n" preview, "Dry run complete", "Iconi")
            return
        }

        windowTitle := IniRead(ConfigPath, "Settings", "WindowTitle", "Sage 200")
        delayMs := PositiveInteger(IniRead(ConfigPath, "Settings", "DelayMs", "300"), "DelayMs")
        usePrinterCopies := BooleanSetting(IniRead(ConfigPath, "Settings", "UsePrinterCopies", "false"), false)
        ActivateSageWindow(windowTitle)

        for , label in labels {
            repeatCount := usePrinterCopies ? 1 : copies
            Loop repeatCount {
                if AbortRequested {
                    MsgBox("Stopped before printing the next label.", "Stopped", "Icon!")
                    return
                }

                PrintOneLabel(label, copies, delayMs)
                Sleep(delayMs)
            }
        }

        MsgBox("Finished printing " labels.Length " pallet(s), " copies " label(s) each.", "Complete", "Iconi")
    } catch as err {
        MsgBox("Macro stopped:`n`n" err.Message, "Label Printer Macro", "Iconx")
    }
}

BuildLabelList(values) {
    explicitLabels := Trim(values.LabelList)
    labels := []

    if explicitLabels != "" {
        for , rawLabel in StrSplit(explicitLabels, ",") {
            label := Trim(rawLabel)
            if label != "" {
                labels.Push(label)
            }
        }

        if labels.Length = 0 {
            throw Error("Exact labels was filled in, but no labels were found.")
        }

        return labels
    }

    prefix := Trim(values.Prefix)
    if prefix = "" {
        throw Error("Prefix / order number is required.")
    }

    startSuffix := PositiveInteger(values.StartSuffix, "Start suffix")
    suffixWidth := PositiveInteger(values.SuffixWidth, "Suffix width")
    palletCount := PositiveInteger(values.PalletCount, "Number of pallets")
    formatString := "{:0" suffixWidth "}"

    Loop palletCount {
        suffix := Format(formatString, startSuffix + A_Index - 1)
        labels.Push(prefix "-" suffix)
    }

    return labels
}

BuildPreview(labels, copies) {
    output := ""
    lineCount := 0

    for , label in labels {
        Loop copies {
            lineCount += 1
            output .= label "`n"

            if lineCount >= 40 {
                remaining := (labels.Length * copies) - lineCount
                if remaining > 0 {
                    output .= "...and " remaining " more label(s).`n"
                }
                return output
            }
        }
    }

    return output
}

PrintOneLabel(label, copies, defaultDelayMs) {
    global ConfigPath, AbortRequested

    Loop {
        step := Trim(IniRead(ConfigPath, "Steps", A_Index, ""))
        if step = "" {
            break
        }

        if AbortRequested {
            return
        }

        ExecuteStep(step, label, copies, defaultDelayMs)
    }
}

ExecuteStep(step, label, copies, defaultDelayMs) {
    firstSeparator := InStr(step, "|")
    if firstSeparator = 0 {
        command := StrLower(Trim(step))
        argument := ""
    } else {
        command := StrLower(Trim(SubStr(step, 1, firstSeparator - 1)))
        argument := ReplaceTokens(Trim(SubStr(step, firstSeparator + 1)), label, copies)
    }

    switch command {
        case "send":
            Send(argument)
        case "text":
            SendText(argument)
        case "sleep":
            Sleep(PositiveInteger(argument, "sleep"))
        case "click":
            coordinates := StrSplit(argument, "|")
            if coordinates.Length < 2 {
                throw Error("Click step must be formatted as click|x|y.")
            }
            MouseClick("Left", coordinates[1] + 0, coordinates[2] + 0)
        case "activate":
            WinActivate(argument)
        case "waitwin":
            if !WinWait(argument, , 10) {
                throw Error("Timed out waiting for window: " argument)
            }
        case "waitactive":
            if !WinWaitActive(argument, , 10) {
                throw Error("Timed out waiting for active window: " argument)
            }
        case "tooltip":
            ToolTip(argument)
            Sleep(defaultDelayMs)
            ToolTip()
        default:
            throw Error("Unknown step command: " command)
    }

    Sleep(defaultDelayMs)
}

ReplaceTokens(value, label, copies) {
    value := StrReplace(value, "{label}", label)
    return StrReplace(value, "{copies}", copies)
}

ActivateSageWindow(windowTitle) {
    if !WinExist(windowTitle) {
        throw Error("Could not find Sage window matching: " windowTitle)
    }

    WinActivate(windowTitle)
    if !WinWaitActive(windowTitle, , 5) {
        throw Error("Could not activate Sage window matching: " windowTitle)
    }
}

PositiveInteger(value, fieldName) {
    number := value + 0
    if number < 1 || number != Floor(number) {
        throw Error(fieldName " must be a positive whole number.")
    }

    return number
}

BooleanSetting(value, defaultValue) {
    normalized := StrLower(Trim(value))
    switch normalized {
        case "1", "true", "yes", "on":
            return true
        case "0", "false", "no", "off":
            return false
        default:
            return defaultValue
    }
}

RequestAbort() {
    global AbortRequested
    AbortRequested := true
    ToolTip("Label Printer Macro: stop requested")
    SetTimer(() => ToolTip(), -1500)
}

CopyMouseClickStep() {
    MouseGetPos(&x, &y)
    A_Clipboard := "click|" x "|" y
    ToolTip("Copied: " A_Clipboard)
    SetTimer(() => ToolTip(), -1500)
}

CopyActiveWindowTitle() {
    title := WinGetTitle("A")
    A_Clipboard := title
    ToolTip("Copied window title: " title)
    SetTimer(() => ToolTip(), -1500)
}

CreateDefaultConfig(path) {
    defaultConfig := "
    (
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
    )"

    FileAppend(defaultConfig, path, "UTF-8")
}

Quote(value) {
    return '"' value '"'
}
