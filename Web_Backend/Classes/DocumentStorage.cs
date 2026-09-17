namespace Web_Backend.Classes
{
    // Storage for the Agent-visible Documents library
    // (Database/migrations/0063_agent_document_library.sql). Deliberately
    // NOT under wwwroot: everything there is served unauthenticated by
    // Program.cs's UseStaticFiles(), which would make a "restricted to
    // specific agents" document fetchable by anyone holding its URL,
    // regardless of mst.Document.VisibilityScope. Files live in a private
    // folder next to wwwroot instead, and are only ever read back through
    // DocumentsController's authenticated, visibility-checked actions —
    // never a direct static-file URL.
    public interface IDocumentStorage
    {
        // Returns the generated on-disk file name (not a URL — this is a
        // private store), or null if the upload was empty/rejected.
        Task<string?> SaveAsync(IFormFile? file);

        Task<Stream?> OpenReadAsync(string storedFileName);

        void Delete(string? storedFileName);
    }

    public class DocumentStorage : IDocumentStorage
    {
        // View-only in the Agent portal (Controllers/Agent/DocumentsController.cs
        // renders these inline, never offers a download link), so the
        // allowed set is deliberately limited to what a browser can preview
        // natively with no extra viewer/library — PDF and common image
        // formats. Office documents are intentionally excluded: making
        // those genuinely view-only would need an external viewer
        // (Office/Google Docs embed), which is its own can of worms and out
        // of scope here.
        private static readonly string[] AllowedExtensions = { ".pdf", ".jpg", ".jpeg", ".png", ".webp" };
        private const long MaxBytes = 10 * 1024 * 1024; // 10 MB

        private readonly string storageRoot;

        public DocumentStorage(IWebHostEnvironment env)
        {
            // Sibling of wwwroot, e.g. .../Web_Backend/PrivateStorage/Documents —
            // outside the static-file-served ContentRoot\wwwroot tree.
            storageRoot = Path.Combine(env.ContentRootPath, "PrivateStorage", "Documents");
        }

        public async Task<string?> SaveAsync(IFormFile? file)
        {
            if (file == null || file.Length == 0) return null;

            var ext = Path.GetExtension(file.FileName).ToLowerInvariant();
            if (!AllowedExtensions.Contains(ext))
                throw new InvalidOperationException($"Unsupported file type '{ext}'. Allowed: {string.Join(", ", AllowedExtensions)}.");
            if (file.Length > MaxBytes)
                throw new InvalidOperationException($"File is larger than the {MaxBytes / (1024 * 1024)} MB limit.");

            Directory.CreateDirectory(storageRoot);

            // Generated name, never the client-supplied one — same reasoning
            // as ImageUploader: a caller-controlled filename could contain
            // path segments or collide with/overwrite an existing file.
            var fileName = $"{Guid.NewGuid():N}{ext}";
            var absolutePath = Path.Combine(storageRoot, fileName);

            using (var stream = new FileStream(absolutePath, FileMode.Create))
            {
                await file.CopyToAsync(stream);
            }

            return fileName;
        }

        public Task<Stream?> OpenReadAsync(string storedFileName)
        {
            var path = ResolveSafePath(storedFileName);
            if (path == null || !File.Exists(path)) return Task.FromResult<Stream?>(null);
            return Task.FromResult<Stream?>(new FileStream(path, FileMode.Open, FileAccess.Read));
        }

        public void Delete(string? storedFileName)
        {
            var path = ResolveSafePath(storedFileName);
            if (path != null && File.Exists(path)) File.Delete(path);
        }

        // Guards against a stored value containing path segments (e.g. a
        // corrupted DB row) resolving outside storageRoot — same idiom as
        // ImageUploader.Delete's uploads-root containment check.
        private string? ResolveSafePath(string? storedFileName)
        {
            if (string.IsNullOrWhiteSpace(storedFileName)) return null;
            if (storedFileName.Contains('/') || storedFileName.Contains('\\')) return null;

            var absolute = Path.GetFullPath(Path.Combine(storageRoot, storedFileName));
            var root = Path.GetFullPath(storageRoot);
            if (!absolute.StartsWith(root, StringComparison.OrdinalIgnoreCase)) return null;

            return absolute;
        }
    }
}
