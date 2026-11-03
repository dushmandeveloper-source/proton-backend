using System.IO.Compression;
using System.Text;

namespace Web_Backend.Classes
{
    // Reads versionCode / versionName straight out of an uploaded APK (its
    // compiled binary AndroidManifest.xml), so publishing a release is just
    // uploading the APK -- no version to type into appsettings. Cached per
    // file (path + size + last write), so the version endpoint stays free.
    public static class ApkVersionReader
    {
        public record ApkVersion(int VersionCode, string VersionName, long SizeBytes);

        private static readonly object Gate = new();
        private static (string Key, ApkVersion? Value)? cache;

        public static ApkVersion? Read(string apkPath)
        {
            var fi = new FileInfo(apkPath);
            if (!fi.Exists) return null;
            var key = $"{fi.FullName}|{fi.Length}|{fi.LastWriteTimeUtc.Ticks}";
            lock (Gate)
            {
                if (cache?.Key == key) return cache.Value.Value;
            }

            ApkVersion? value = null;
            try
            {
                using var zip = ZipFile.OpenRead(apkPath);
                var entry = zip.GetEntry("AndroidManifest.xml");
                if (entry != null)
                {
                    using var s = entry.Open();
                    using var ms = new MemoryStream();
                    s.CopyTo(ms);
                    var (code, name) = ParseManifest(ms.ToArray());
                    if (code > 0) value = new ApkVersion(code, name, fi.Length);
                }
            }
            catch (Exception)
            {
                // Half-uploaded or not an APK: report "no release" until it's fixed.
                value = null;
            }

            lock (Gate) cache = (key, value);
            return value;
        }

        // Android binary XML: a string pool, then element chunks. Only the
        // first element (<manifest>) is needed.
        private static (int Code, string Name) ParseManifest(byte[] b)
        {
            string[] strings = Array.Empty<string>();
            var pos = 8; // file header
            while (pos + 8 <= b.Length)
            {
                var type = U16(b, pos);
                var headerSize = U16(b, pos + 2);
                var size = (int)U32(b, pos + 4);
                if (size <= 0) break;

                if (type == 0x0001) strings = ReadStringPool(b, pos);
                else if (type == 0x0102) // start element
                {
                    var attrStart = pos + headerSize + U16(b, pos + 16 + 8);
                    var attrSize = U16(b, pos + 16 + 10);
                    var attrCount = U16(b, pos + 16 + 12);
                    int code = 0;
                    string name = "";
                    for (var i = 0; i < attrCount; i++)
                    {
                        var a = attrStart + i * attrSize;
                        var attrName = Str(strings, U32(b, a + 4));
                        var raw = U32(b, a + 8);
                        var dataType = b[a + 15];
                        var data = U32(b, a + 16);
                        if (attrName == "versionCode") code = (int)data;
                        else if (attrName == "versionName")
                            name = raw != 0xFFFFFFFF ? Str(strings, raw) : dataType == 0x03 ? Str(strings, data) : "";
                    }
                    return (code, name);
                }
                pos += size;
            }
            return (0, "");
        }

        private static string[] ReadStringPool(byte[] b, int chunk)
        {
            var count = (int)U32(b, chunk + 8);
            var utf8 = (U32(b, chunk + 16) & 0x100) != 0;
            var stringsStart = chunk + (int)U32(b, chunk + 20);
            var offsets = chunk + U16(b, chunk + 2);
            var result = new string[count];
            for (var i = 0; i < count; i++)
            {
                var p = stringsStart + (int)U32(b, offsets + i * 4);
                if (utf8)
                {
                    p += (b[p] & 0x80) != 0 ? 2 : 1; // char count
                    var len = b[p] & 0x7F;
                    if ((b[p] & 0x80) != 0) { len = (len << 8) | b[p + 1]; p += 2; } else p += 1;
                    result[i] = Encoding.UTF8.GetString(b, p, len);
                }
                else
                {
                    int len = U16(b, p);
                    if ((len & 0x8000) != 0) { len = ((len & 0x7FFF) << 16) | U16(b, p + 2); p += 4; } else p += 2;
                    result[i] = Encoding.Unicode.GetString(b, p, len * 2);
                }
            }
            return result;
        }

        private static string Str(string[] s, uint i) => i < s.Length ? s[i] : "";
        private static int U16(byte[] b, int p) => b[p] | (b[p + 1] << 8);
        private static uint U32(byte[] b, int p) => (uint)(b[p] | (b[p + 1] << 8) | (b[p + 2] << 16) | (b[p + 3] << 24));
    }
}
