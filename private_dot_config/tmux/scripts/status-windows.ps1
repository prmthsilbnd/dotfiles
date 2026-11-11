# Windows (psmux) counterpart of status-metric, status-battery and
# status-identity. Every psmux session starts it with `run -b` in tmux.conf;
# only the first copy stays (a named mutex makes it a per-user singleton). It
# samples CPU, memory and battery every few seconds and writes the finished
# status-right text to ~/.cache/psmux-status-right.txt, which status-right
# reads with `#(cmd /c type ...)`.
#
# Why not a plain `#(...)` script: each refresh would start a fresh pwsh
# (~0.6s) and compile the Win32 calls below (~1.5s). Why a file rather than
# `psmux set -g @option`: psmux runs one server per session and pre-starts a
# standby `__warm__` server that is renamed when claimed, so a pushed option
# can land in the wrong session. The loop itself is C#, because interpreted
# PowerShell cost several percent of a core at a 3 s interval. It exits once
# no psmux process is left.
param([int]$Interval = 3)

$mutex = [Threading.Mutex]::new($false, 'Local\dotfiles-psmux-status-right')
if (-not $mutex.WaitOne(0)) { exit }

Add-Type -TypeDefinition @'
using System;
using System.Diagnostics;
using System.IO;
using System.Runtime.InteropServices;
using System.Threading;

public static class DotfilesPsmuxStatus {
  [DllImport("kernel32.dll")] static extern bool GetSystemTimes(out long idle, out long kernel, out long user);
  [StructLayout(LayoutKind.Sequential)] struct MemoryStatus { public uint Length, Load; public ulong TotalPhys, AvailPhys, TotalPageFile, AvailPageFile, TotalVirtual, AvailVirtual, AvailExtendedVirtual; }
  [DllImport("kernel32.dll")] static extern bool GlobalMemoryStatusEx(ref MemoryStatus status);
  [StructLayout(LayoutKind.Sequential)] struct PowerStatus { public byte AcLine, Flags, Percent, Reserved; public uint LifeTime, FullLifeTime; }
  [DllImport("kernel32.dll")] static extern bool GetSystemPowerStatus(out PowerStatus status);

  const string Normal = "#[fg=#D8DEE9,nobold,nounderscore]";
  const string Alert = "#[fg=red,nobold,nounderscore]";
  const string Charging = "#[fg=#A3BE8C,nobold,nounderscore]";

  static string Metric(string label, long percent) {
    return percent >= 80 ? Alert + label + Normal + " " + percent + "%" : Normal + label + " " + percent + "%";
  }

  static string Battery() {
    PowerStatus p;
    // Flags 128 = no system battery; Percent 255 = unknown.
    if (!GetSystemPowerStatus(out p) || (p.Flags & 128) != 0 || p.Percent == 255) return "";
    string style = Normal, suffix = "";
    if (p.Percent < 20) style = Alert;
    else if ((p.Flags & 8) != 0) { style = Charging; suffix = "+"; }
    return " " + style + "BAT " + p.Percent + "%" + suffix + Normal;
  }

  static bool PsmuxRunning() {
    foreach (string name in new[] { "psmux", "tmux", "pmux" })
      if (Process.GetProcessesByName(name).Length > 0) return true;
    return false;
  }

  public static void Run(string output, string identity, int intervalSeconds) {
    string tmp = output + ".tmp";
    long idle0, kernel0, user0, idle1, kernel1, user1;
    GetSystemTimes(out idle0, out kernel0, out user0);
    Thread.Sleep(1000);
    for (int tick = 0; tick % 20 != 0 || PsmuxRunning(); tick++) {
      GetSystemTimes(out idle1, out kernel1, out user1);
      long total = (kernel1 - kernel0) + (user1 - user0);  // kernel time includes idle time
      long cpu = total > 0 ? (long)Math.Round(100.0 * (total - (idle1 - idle0)) / total) : 0;
      idle0 = idle1; kernel0 = kernel1; user0 = user1;

      MemoryStatus m = new MemoryStatus();
      m.Length = (uint)Marshal.SizeOf(typeof(MemoryStatus));
      GlobalMemoryStatusEx(ref m);

      // Write then rename, so a concurrent `type` never sees a half-written file.
      File.WriteAllText(tmp, Metric("CPU", cpu) + " " + Metric("MEM", m.Load) + Battery() + " " + Normal + "| " + identity + " ");
      File.Move(tmp, output, true);
      Thread.Sleep(intervalSeconds * 1000);
    }
  }
}
'@

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
$hostName = $env:COMPUTERNAME.ToUpper()
$identity = if ($isAdmin) { "#[fg=colour220,bold,nounderscore]$hostName" } else { "#[fg=#D8DEE9,nobold,nounderscore]$($env:USERNAME.ToUpper()) | #[fg=magenta,bold,nounderscore]$hostName" }

$output = Join-Path $HOME '.cache\psmux-status-right.txt'
[void](New-Item -ItemType Directory -Force (Split-Path $output))
[DotfilesPsmuxStatus]::Run($output, $identity, $Interval)
