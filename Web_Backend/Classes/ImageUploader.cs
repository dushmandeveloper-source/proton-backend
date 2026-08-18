namespace Web_Backend.Classes
{
    public interface IImageUploader
    {
        // Returns the web-relative URL of the saved file, or null if the upload
        // was empty/rejected.
        Task<string?> SaveAsync(IFormFile? file, string subFolder);
        void Delete(string? webRelativeUrl);
    }

    public class ImageUploader : IImageUploader
    {
        private static readonly string[] AllowedExtensions = { ".jpg", ".jpeg", ".png", ".webp", ".gif", ".svg" };
        private const long MaxBytes = 5 * 1024 * 1024; // 5 MB

        private readonly IWebHostEnvironment env;

        public ImageUploader(IWebHostEnvironment env)
        {
            this.env = env;
        }

        public async Task<string?> SaveAsync(IFormFile? file, string subFolder)
        {
            if (file == null || file.Length == 0) return null;

            var ext = Path.GetExtension(file.FileName).ToLowerInvariant();
            if (!AllowedExtensions.Contains(ext))
                throw new InvalidOperationException($"Unsupported image type '{ext}'. Allowed: {string.Join(", ", AllowedExtensions)}.");
            if (file.Length > MaxBytes)
                throw new InvalidOperationException("Image is larger than the 5 MB limit.");

            // Generated name, never the client-supplied one — a caller-controlled
            // filename could contain path segments or overwrite existing files.
            var fileName = $"{Guid.NewGuid():N}{ext}";
            var relativeFolder = Path.Combine("Uploads", subFolder);
            var absoluteFolder = Path.Combine(env.WebRootPath, relativeFolder);
            Directory.CreateDirectory(absoluteFolder);

            var absolutePath = Path.Combine(absoluteFolder, fileName);
            using (var stream = new FileStream(absolutePath, FileMode.Create))
            {
                await file.CopyToAsync(stream);
            }

            return $"/{relativeFolder.Replace('\\', '/')}/{fileName}";
        }

        public void Delete(string? webRelativeUrl)
        {
            if (string.IsNullOrWhiteSpace(webRelativeUrl)) return;
            // Only ever delete inside wwwroot/Uploads, and only a bare file name —
            // guards against a stored value like "/../../appsettings.json".
            if (!webRelativeUrl.StartsWith("/Uploads/", StringComparison.OrdinalIgnoreCase)) return;

            var relative = webRelativeUrl.TrimStart('/').Replace('/', Path.DirectorySeparatorChar);
            var absolute = Path.GetFullPath(Path.Combine(env.WebRootPath, relative));
            var uploadsRoot = Path.GetFullPath(Path.Combine(env.WebRootPath, "Uploads"));
            if (!absolute.StartsWith(uploadsRoot, StringComparison.OrdinalIgnoreCase)) return;

            if (File.Exists(absolute)) File.Delete(absolute);
        }
    }
}
