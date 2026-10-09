using SkiaSharp;

namespace Web_Backend.Classes
{
    // ApplicationSettings:ImageOptimization in appsettings. Defaults are used when the section is missing,
    // so the live server needs no new appsettings values for this to work.
    public class ImageOptimizationOptions
    {
        public bool Enabled { get; set; } = true;
        public int MaxDimension { get; set; } = 1600;   // longest side, px, of the copy the site serves
        public int Quality { get; set; } = 85;          // JPEG/WEBP; 85+ is visually lossless for photos
        public bool KeepOriginals { get; set; } = true; // full-res file kept in App_Data/originals (not web-served)
        public bool OptimizeExistingOnStartup { get; set; } = true;
    }

    // Shrinks an uploaded image in place under wwwroot/Uploads, keeping its format and extension so stored
    // URLs never change. The untouched original is moved to App_Data/originals/<same relative path>.
    // Only jpg/png/webp are touched — PDFs (payment slips), SVGs, GIFs and audio/video uploads are left alone.
    public class ImageOptimizer
    {
        private static readonly HashSet<string> ImageExtensions = new(StringComparer.OrdinalIgnoreCase)
            { ".jpg", ".jpeg", ".jfif", ".jpe", ".png", ".webp" };

        private readonly ImageOptimizationOptions opt;
        private readonly string uploadsRoot, originalsRoot;
        private readonly ILogger<ImageOptimizer> log;

        public ImageOptimizer(IWebHostEnvironment env, IConfiguration config, ILogger<ImageOptimizer> log)
        {
            opt = config.GetSection("ApplicationSettings:ImageOptimization").Get<ImageOptimizationOptions>() ?? new();
            opt.MaxDimension = Math.Clamp(opt.MaxDimension, 400, 8000);
            opt.Quality = Math.Clamp(opt.Quality, 60, 100);
            uploadsRoot = Path.Combine(env.WebRootPath, "Uploads");
            originalsRoot = Path.Combine(env.ContentRootPath, "App_Data", "originals");
            this.log = log;
        }

        public ImageOptimizationOptions Options => opt;

        public static bool IsImage(string path) => ImageExtensions.Contains(Path.GetExtension(path));

        private string OriginalPathFor(string uploadPath)
            => Path.Combine(originalsRoot, Path.GetRelativePath(uploadsRoot, uploadPath));

        // Safe to call repeatedly: a file whose original (or .done marker) is stored has been done.
        // force: run even when Enabled is off (an admin pressed the button).
        public async Task<bool> Optimize(string path, CancellationToken ct = default, bool force = false)
        {
            if (!opt.Enabled && !force) return false;
            if (!IsImage(path) || !File.Exists(path)) return false;
            var original = OriginalPathFor(path);
            if (IsDone(original)) return false;

            var ext = Path.GetExtension(path).ToLowerInvariant();
            var before = new FileInfo(path).Length;
            var tmp = path + ".tmp";
            try
            {
                ct.ThrowIfCancellationRequested();
                var format = ext switch { ".png" => SKEncodedImageFormat.Png, ".webp" => SKEncodedImageFormat.Webp, _ => SKEncodedImageFormat.Jpeg };
                // Re-encoding drops EXIF (camera data, GPS), so turn phone photos upright first.
                using (var encoded = Encode(path, format))
                {
                    if (encoded is null) throw new InvalidDataException("Not a readable image.");
                    await using var output = new FileStream(tmp, FileMode.Create, FileAccess.Write);
                    encoded.SaveTo(output);
                }

                Directory.CreateDirectory(Path.GetDirectoryName(original)!);
                var after = new FileInfo(tmp).Length;
                if (after >= before)
                {
                    // Already lean: leave it alone, but remember so it isn't decoded again every run.
                    File.Delete(tmp);
                    File.WriteAllBytes(original + ".done", []);
                    return false;
                }

                if (opt.KeepOriginals) File.Move(path, original);
                else File.WriteAllBytes(original + ".done", []);
                File.Move(tmp, path, overwrite: true);
                log.LogInformation("Optimized {File}: {Before} KB -> {After} KB", Path.GetFileName(path), before / 1024, after / 1024);
                return true;
            }
            catch (Exception ex) when (ex is not OperationCanceledException)
            {
                // A file we can't decode is still a valid upload; serve it as-is.
                try { if (File.Exists(tmp)) File.Delete(tmp); } catch (IOException) { }
                if (ex is InvalidDataException)
                {
                    // e.g. an AVIF saved as .png: mark it so every restart doesn't retry and re-log it.
                    try { Directory.CreateDirectory(Path.GetDirectoryName(original)!); File.WriteAllBytes(original + ".done", []); } catch (IOException) { }
                    log.LogInformation("Skipped {File}: not a decodable image", Path.GetFileName(path));
                }
                else log.LogWarning(ex, "Could not optimize {File}", path);
                return false;
            }
        }

        private SKData? Encode(string path, SKEncodedImageFormat format)
        {
            using var codec = SKCodec.Create(path);
            if (codec is null) return null;
            using var decoded = SKBitmap.Decode(codec);
            if (decoded is null) return null;
            using var upright = Upright(decoded, codec.EncodedOrigin);
            var src = upright ?? decoded;

            var scale = Math.Min(1.0, (double)opt.MaxDimension / Math.Max(src.Width, src.Height));
            using var resized = scale < 1
                ? src.Resize(new SKImageInfo(Math.Max(1, (int)Math.Round(src.Width * scale)), Math.Max(1, (int)Math.Round(src.Height * scale)), src.ColorType, src.AlphaType),
                             new SKSamplingOptions(SKCubicResampler.Mitchell))
                : null;
            using var image = SKImage.FromBitmap(resized ?? src);
            // PNG is lossless (quality is ignored); JPEG/WEBP use the configured quality.
            return image.Encode(format, opt.Quality);
        }

        // Applies the EXIF orientation to the pixels. null when the image is already upright.
        private static SKBitmap? Upright(SKBitmap src, SKEncodedOrigin origin)
        {
            if (origin is SKEncodedOrigin.TopLeft or SKEncodedOrigin.Default) return null;
            var swap = origin is SKEncodedOrigin.LeftTop or SKEncodedOrigin.RightTop or SKEncodedOrigin.RightBottom or SKEncodedOrigin.LeftBottom;
            var dst = new SKBitmap(new SKImageInfo(swap ? src.Height : src.Width, swap ? src.Width : src.Height, src.ColorType, src.AlphaType));
            using var canvas = new SKCanvas(dst);
            float w = src.Width, h = src.Height;
            switch (origin)
            {
                case SKEncodedOrigin.TopRight: canvas.Scale(-1, 1, w / 2, 0); break;
                case SKEncodedOrigin.BottomRight: canvas.RotateDegrees(180, w / 2, h / 2); break;
                case SKEncodedOrigin.BottomLeft: canvas.Scale(1, -1, 0, h / 2); break;
                case SKEncodedOrigin.LeftTop: canvas.Translate(h, 0); canvas.RotateDegrees(90); canvas.Scale(1, -1, 0, h / 2); break;
                case SKEncodedOrigin.RightTop: canvas.Translate(h, 0); canvas.RotateDegrees(90); break; // most phone portraits
                case SKEncodedOrigin.RightBottom: canvas.Translate(0, w); canvas.RotateDegrees(-90); canvas.Scale(1, -1, 0, h / 2); break;
                case SKEncodedOrigin.LeftBottom: canvas.Translate(0, w); canvas.RotateDegrees(-90); break;
            }
            using var srcImage = SKImage.FromBitmap(src);
            canvas.DrawImage(srcImage, 0, 0, SKSamplingOptions.Default);
            return dst;
        }

        private static bool IsDone(string original) => File.Exists(original) || File.Exists(original + ".done");

        private IEnumerable<string> Uploads()
            => Directory.Exists(uploadsRoot)
                ? Directory.EnumerateFiles(uploadsRoot, "*", SearchOption.AllDirectories).Where(IsImage)
                : [];

        // One run at a time: the startup backfill and the admin button share this.
        private readonly SemaphoreSlim running = new(1, 1);
        public bool IsRunning => running.CurrentCount == 0;

        // Returns how many files were shrunk, or null if a run is already in progress.
        public async Task<int?> OptimizeAll(CancellationToken ct, bool force = false)
        {
            if (!await running.WaitAsync(0, ct)) return null;
            try
            {
                var count = 0;
                foreach (var file in Uploads().ToList())
                {
                    ct.ThrowIfCancellationRequested();
                    if (await Optimize(file, ct, force)) count++;
                }
                return count;
            }
            finally { running.Release(); }
        }

        public ImageStats Stats()
        {
            var stats = new ImageStats { Running = IsRunning, Options = opt };
            foreach (var file in Uploads())
            {
                stats.Total++;
                stats.ServedBytes += new FileInfo(file).Length;
                var original = OriginalPathFor(file);
                if (File.Exists(original)) { stats.Optimized++; stats.OriginalBytes += new FileInfo(original).Length; }
                else if (File.Exists(original + ".done")) stats.Optimized++;
                else stats.Pending++;
            }
            return stats;
        }
    }

    public class ImageStats
    {
        public int Total { get; set; }
        public int Optimized { get; set; }
        public int Pending { get; set; }
        public long ServedBytes { get; set; }   // what visitors download (all upload images)
        public long OriginalBytes { get; set; } // full-size copies kept in App_Data/originals
        public bool Running { get; set; }
        public ImageOptimizationOptions Options { get; set; } = new();
    }

    // Shrinks images uploaded before optimization existed. Runs once in the background after startup.
    public class ImageBackfillService(ImageOptimizer optimizer, ILogger<ImageBackfillService> log) : BackgroundService
    {
        protected override async Task ExecuteAsync(CancellationToken ct)
        {
            if (!optimizer.Options.Enabled || !optimizer.Options.OptimizeExistingOnStartup) return;
            await Task.Delay(TimeSpan.FromSeconds(10), ct); // let the first requests through first
            try { await optimizer.OptimizeAll(ct); }
            catch (OperationCanceledException) { }
            catch (Exception ex) { log.LogError(ex, "Image backfill failed"); }
        }
    }
}
