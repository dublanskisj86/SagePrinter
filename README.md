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

- `macro/SageLabelPrinter.ahk` - AutoHotkey v2 macro with a simple input form.
- `macro/print-steps.sample.ini` - editable example of the Sage print steps.

## Requirements

1. Windows.
2. [AutoHotkey v2](https://www.autohotkey.com/) installed.
3. Sage open on the screen where one label can be printed manually.
4. Toshiba printer/driver copy count set to `1`.

The macro should control the repeat count. The printer driver should not repeat
the whole job.

## Basic use

1. Copy `macro/print-steps.sample.ini` to `macro/print-steps.ini`.
2. Edit `macro/print-steps.ini` for the exact Sage screen.
3. Double-click `macro/SageLabelPrinter.ahk`.
4. Press `F8` to open the macro form.
5. Enter:
   - Prefix/order number, for example `26166`
   - Start suffix, for example `1`
   - Number of pallets, for example `3`
   - Labels per pallet, for example `2`
6. Run once with **Dry run** enabled to verify the order.
7. Clear **Dry run** and run a one-pallet test before using it on a full batch.

Press `Esc` at any time to ask the macro to stop after the current step.

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

- `F9` copies the current mouse position as a `click|x|y` step.
- `F10` copies the active window title, useful for the `WindowTitle` setting.

Start by manually printing one label in Sage, then translate the clicks and keys
you used into `print-steps.ini`. After that, the user only enters quantity and
the macro repeats the process in the correct order.
