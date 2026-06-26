# next-event.ps1 — print the next non-all-day Outlook appointment as "epoch|subject".
#
# Attaches ONLY to an already-running Outlook via GetActiveObject — it never
# force-launches Outlook. Prints nothing if Outlook is closed or there's no
# upcoming event. Fed to classic powershell.exe via STDIN (`-Command -`) by the
# WSL refresher, NOT executed by path: running it from the \\wsl.localhost\ UNC
# path trips PowerShell's AuthorizationManager (untrusted zone). Hence the
# function wrapper, so `return` works under -Command.
$ErrorActionPreference = 'Stop'

function Get-NextEvent {
    try {
        $ol = [Runtime.InteropServices.Marshal]::GetActiveObject('Outlook.Application')
    } catch {
        return  # Outlook not running — emit nothing so the widget clears
    }
    try {
        $cal = $ol.Session.GetDefaultFolder(9)  # 9 = olFolderCalendar
        $items = $cal.Items
        $items.IncludeRecurrences = $true        # expand recurring meetings
        $items.Sort('[Start]')                    # sort before Restrict for recurrences
        $now = Get-Date
        $upcoming = $items.Restrict("[Start] >= '" + $now.ToString('g') + "'")

        $epochBase = [datetime]::SpecifyKind([datetime]'1970-01-01', [DateTimeKind]::Utc)
        foreach ($appt in $upcoming) {
            if ($appt.AllDayEvent) { continue }   # skip all-day events
            $epoch = [int][Math]::Floor((($appt.Start.ToUniversalTime()) - $epochBase).TotalSeconds)
            $subject = ($appt.Subject -replace '\|', '/')  # '|' is our delimiter
            [Console]::Out.Write("$epoch|$subject")
            return
        }
    } catch {
        return
    }
}

Get-NextEvent
