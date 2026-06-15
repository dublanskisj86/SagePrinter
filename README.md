# SagePrinter

Small Windows macro helper for printing Sage pallet labels on a Toshiba label
printer in pallet-grouped order.

## Problem this solves

If Sage or the Toshiba driver is set to print two copies of the whole print job,
labels can come out like this:

```text
26166-01
26166-02
26166-03
26166-01
26166-02
26166-03
```

For pallet labels, the desired order is usually:

```text
26166-01
26166-01
26166-02
26166-02
26166-03
26166-03
```

The macro in this repository loops through each pallet first, then prints the
required number of labels for that pallet before moving to the next one.

## Files

- `macro/RunSageLabelPrinter.bat` - no-install launcher for standard Windows PCs.
- `macro/SageLabelPrinter.ps1` - no-install PowerShell macro with a simple input form.
- `macro/SageLabelPrinter.ahk` - optional AutoHotkey v2 version.
- `macro/print-steps.sample.ini` - editable example of the Sage print steps.

## Requirements

1. Windows.
2. Sage open on the screen where one label can be printed manually.
3. Toshiba printer/driver copy count set to `1`.

The macro should control the repeat count. The printer driver should not repeat
the whole job.

AutoHotkey is optional. Use the PowerShell version if you do not have admin
rights to install anything.

## Basic use without admin rights

1. Copy `macro/print-steps.sample.ini` to `macro/print-steps.ini`.
2. Edit `macro/print-steps.ini` for the exact Sage screen.
3. Double-click `macro/RunSageLabelPrinter.bat`.
4. Enter:
   - Prefix/order number, for example `26166`
   - Start suffix, for example `1`
   - Number of pallets, for example `3`
   - Labels per pallet, for example `2`
5. Run once with **Dry run** enabled to verify the order.
6. Clear **Dry run** and run a one-pallet test before using it on a full batch.

Press `Esc` at any time to ask the macro to stop after the current step.

If Windows shows a security warning for the downloaded ZIP, right-click the ZIP,
choose **Properties**, check **Unblock** if it appears, then unzip it again.

## Optional AutoHotkey use

If AutoHotkey v2 is already installed, you can double-click
`macro/SageLabelPrinter.ahk` and press `F8` to open the same style of macro
form.

## Teaching the macro how Sage prints one label

The macro works by repeating the same "print one label" steps. Those steps live
in `macro/print-steps.ini`.

Typical steps are things like:

```ini
1=click|420|310
2=send|^a
3=text|{label}
4=send|{Enter}
5=sleep|500
6=send|!p
```

Available step commands:

- `send|...` - sends AutoHotkey key syntax, such as `^p`, `{Enter}`, or `!p`.
- `text|...` - types literal text. Use `{label}` where the pallet label goes.
- `click|x|y` - left-clicks a screen coordinate.
- `sleep|milliseconds` - waits.
- `activate|Window title` - activates a window.
- `waitwin|Window title` - waits for a window to exist.
- `waitactive|Window title` - waits for a window to be active.
- `tooltip|Message` - briefly shows a message.

Helper hotkeys while the script is running:

- PowerShell version: use **Copy click** and **Copy title** buttons.
- AutoHotkey version: `F9` copies the current mouse position as a `click|x|y`
  step, and `F10` copies the active window title.

Start by manually printing one label in Sage, then translate the clicks and keys
you used into `print-steps.ini`. After that, the user only enters quantity and
the macro repeats the process in the correct order.
