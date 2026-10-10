namespace Web_Backend.Classes
{
    public interface IImageUploader
    {
        // Returns the web-relative URL of the saved file, or null if the upload
        // was empty/rejected.
        Task<string?> SaveAsync(IFormFile? file, string subFolder);

        // Same save mechanics (generated filename, folder creation, web-relative
        // URL) but with a caller-supplied extension whitelist and size limit —
        // for non-image uploads (audio/video exam-question attachments) where
        // the image-only defaults below don't apply.
        Task<string?> SaveMediaAsync(IFormFile? file, string subFolder, string[] allowedExtensions, long maxBytes);

        void Delete(string? webRelativeUrl);
    }

    public class ImageUploader : IImageUploader
    {
        // Includes .pdf alongside image formats: SaveAsync's default whitelist
        // is also used for payment/deposit slip uploads (Admin StudentController
        // and the public EnrollmentsApiController), and both registration UIs
        // invite PDF slips (accept="image/*,.pdf") — without it, a PDF slip
        // throws InvalidOperationException and surfaces as an unhandled 500.
        private static readonly string[] AllowedExtensions = { ".jpg", ".jpeg", ".jfif", ".jpe", ".png", ".webp", ".gif", ".bmp", ".tif", ".tiff", ".avif", ".heic", ".heif", ".svg", ".pdf" };
        private const long MaxBytes = 5 * 1024 * 1024; // 5 MB

        private readonly UploadPaths paths;
        private readonly ImageOptimizer optimizer;

        public ImageUploader(UploadPaths paths, ImageOptimizer optimizer)
        {
            this.paths = paths;
            this.optimizer = optimizer;
        }

        public Task<string?> SaveAsync(IFormFile? file, string subFolder) =>
            SaveMediaAsync(file, subFolder, AllowedExtensions, MaxBytes);

        public async Task<string?> SaveMediaAsync(IFormFile? file, string subFolder, string[] allowedExtensions, long maxBytes)
        {
            if (file == null || file.Length == 0) return null;

            var ext = Path.GetExtension(file.FileName).ToLowerInvariant();
            if (!allowedExtensions.Contains(ext))
                throw new InvalidOperationException($"Unsupported file type '{ext}'. Allowed: {string.Join(", ", allowedExtensions)}.");
            if (file.Length > maxBytes)
                throw new InvalidOperationException($"File is larger than the {maxBytes / (1024 * 1024)} MB limit.");

            // Generated name, never the client-supplied one — a caller-controlled
            // filename could contain path segments or overwrite existing files.
            var fileName = $"{Guid.NewGuid():N}{ext}";
            // Folder comes from UploadPaths (wwwroot/Uploads, or the configured
            // ApplicationSettings:Uploads:Path); the public URL is the same either way.
            var safeSub = string.Join("_", subFolder.Split(Path.GetInvalidFileNameChars())).Replace("..", "");
            var absoluteFolder = Path.Combine(paths.Root, safeSub);
            Directory.CreateDirectory(absoluteFolder);

            var absolutePath = Path.Combine(absoluteFolder, fileName);
            using (var stream = new FileStream(absolutePath, FileMode.Create))
            {
                await file.CopyToAsync(stream);
            }

            // Shrink photos right away (resize/re-encode, strip EXIF); a no-op for non-images.
            await optimizer.Optimize(absolutePath);

            return $"/Uploads/{safeSub}/{fileName}";
        }

        public void Delete(string? webRelativeUrl)
        {
            if (string.IsNullOrWhiteSpace(webRelativeUrl)) return;
            // Only ever delete inside wwwroot/Uploads, and only a bare file name —
            // guards against a stored value like "/../../appsettings.json".
            // PhysicalPathFor returns null for anything outside the uploads folder.
            var absolute = paths.PhysicalPathFor(webRelativeUrl);
            if (absolute != null && File.Exists(absolute)) File.Delete(absolute);
        }
    }
}
