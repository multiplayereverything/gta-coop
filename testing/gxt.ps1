# Prints GTA SA text entries (american.gxt) for the given keys, e.g. testing\gxt.ps1 INT1_AP INTRO2E
# Keys are stored as JAMCRC32 of the upper-case key; the MAIN and all mission tables are searched.
$gxt = Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'GTA San Andreas\text\american.gxt'

if (-not ('GxtReader' -as [type])) {
    Add-Type @"
using System; using System.Collections.Generic; using System.IO; using System.Text;
public static class GxtReader {
    static uint Hash(string s) {
        uint c = 0xFFFFFFFF;
        foreach (char ch in s.ToUpperInvariant()) {
            c ^= (byte)ch;
            for (int k = 0; k < 8; k++) c = (c & 1) != 0 ? 0xEDB88320 ^ (c >> 1) : c >> 1;
        }
        return c;
    }
    public static List<string> Find(string path, string[] keys) {
        byte[] b = File.ReadAllBytes(path);
        var want = new Dictionary<uint, string>();
        foreach (var k in keys) want[Hash(k)] = k;
        var result = new List<string>();
        int tablSize = BitConverter.ToInt32(b, 8);
        for (int o = 12; o < 12 + tablSize; o += 12) {
            string name = Encoding.ASCII.GetString(b, o, 8).TrimEnd('\0');
            int p = BitConverter.ToInt32(b, o + 8);
            if (name != "MAIN") p += 8;
            int keySize = BitConverter.ToInt32(b, p + 4), keys0 = p + 8, tdat = keys0 + keySize;
            for (int e = keys0; e < keys0 + keySize; e += 8) {
                uint h = BitConverter.ToUInt32(b, e + 4);
                string key;
                if (!want.TryGetValue(h, out key)) continue;
                int s = tdat + 8 + BitConverter.ToInt32(b, e), end = s;
                while (b[end] != 0) end++;
                result.Add(string.Format("{0,-9} [{1}] {2}", key, name, Encoding.GetEncoding(1252).GetString(b, s, end - s)));
            }
        }
        return result;
    }
}
"@
}
[GxtReader]::Find($gxt, [string[]]$args)
