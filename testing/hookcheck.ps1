# Shows where hooked call sites in a running gta_sa.exe point to (which module owns the target).
# Finds hook conflicts between CoopAndreas (plugin-sdk) and other ASI mods.
#
#   powershell -ExecutionPolicy Bypass -File testing\hookcheck.ps1 [0x53E981 0x748CFB ...]

param([string[]]$Addresses = @('0x53E981', '0x748CFB', '0x53BF8D', '0x53EAD3', '0x53E58E', '0x748995', '0x74872D'))

Add-Type @"
using System; using System.Runtime.InteropServices; using System.Collections.Generic;
public static class Mem {
    [DllImport("kernel32.dll")] static extern IntPtr OpenProcess(int a, bool i, int pid);
    [DllImport("kernel32.dll")] static extern bool ReadProcessMemory(IntPtr h, IntPtr addr, byte[] buf, int size, out int read);
    [DllImport("kernel32.dll")] static extern bool CloseHandle(IntPtr h);
    [DllImport("kernel32.dll")] static extern IntPtr CreateToolhelp32Snapshot(uint flags, int pid);
    [DllImport("kernel32.dll", CharSet=CharSet.Unicode)] static extern bool Module32FirstW(IntPtr s, ref ME e);
    [DllImport("kernel32.dll", CharSet=CharSet.Unicode)] static extern bool Module32NextW(IntPtr s, ref ME e);
    [StructLayout(LayoutKind.Sequential, CharSet=CharSet.Unicode)] public struct ME {
        public uint dwSize, th32ModuleID, th32ProcessID, GlblcntUsage, ProccntUsage; public IntPtr modBaseAddr; public uint modBaseSize; public IntPtr hModule;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst=256)] public string szModule;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst=260)] public string szExePath; }
    public static byte[] Read(int pid, long addr, int n) {
        IntPtr h = OpenProcess(0x0010 | 0x0400, false, pid); var b = new byte[n]; int r; ReadProcessMemory(h, new IntPtr(addr), b, n, out r); CloseHandle(h); return b; }
    public static List<string> Modules(int pid) {
        var list = new List<string>(); IntPtr s = CreateToolhelp32Snapshot(0x8 | 0x10, pid);
        var e = new ME(); e.dwSize = (uint)Marshal.SizeOf(typeof(ME));
        if (Module32FirstW(s, ref e)) do { list.Add(e.modBaseAddr.ToInt64() + "|" + e.modBaseSize + "|" + e.szModule); } while (Module32NextW(s, ref e));
        CloseHandle(s); return list; }
}
"@

$p = Get-Process gta_sa -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $p) { throw 'gta_sa.exe is not running' }
$mods = [Mem]::Modules($p.Id) | ForEach-Object { $a = $_ -split '\|'; [pscustomobject]@{ Base = [int64]$a[0]; Size = [int64]$a[1]; Name = $a[2] } }

function Owner([int64]$addr) {
    $m = $mods | Where-Object { $addr -ge $_.Base -and $addr -lt $_.Base + $_.Size } | Select-Object -First 1
    if ($m) { '{0}+0x{1:X}' -f $m.Name, ($addr - $m.Base) } else { 'unknown (heap/trampoline)' }
}

foreach ($a in $Addresses) {
    $addr = [Convert]::ToInt64($a, 16)
    $b = [Mem]::Read($p.Id, $addr, 5)
    if ($b[0] -eq 0xE8 -or $b[0] -eq 0xE9) {
        $target = $addr + 5 + [BitConverter]::ToInt32($b, 1)
        $kind = if ($b[0] -eq 0xE8) { 'call' } else { 'jmp' }
        '{0}: {1} 0x{2:X8} -> {3}' -f $a, $kind, $target, (Owner $target)
    } else {
        '{0}: bytes {1}' -f $a, (($b | ForEach-Object { $_.ToString('X2') }) -join ' ')
    }
}
