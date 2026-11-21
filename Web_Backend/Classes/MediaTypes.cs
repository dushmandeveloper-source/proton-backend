using Microsoft.AspNetCore.StaticFiles;

namespace Web_Backend.Classes
{
    // One place for the file types lecture materials and homework answers
    // accept, and how an upload is classified (LectureMaterial.FileType).
    // Used by Admin LectureNote, Lecturer Notes, Classroom (both portals) and
    // Student Homework submissions.
    public static class MediaTypes
    {
        // .weba = in-browser recording (Chrome/Edge record audio/webm;
        // .webm stays "Video" so existing uploads keep their meaning).
        public static readonly string[] AudioExtensions = { ".mp3", ".m4a", ".wav", ".ogg", ".oga", ".opus", ".aac", ".weba" };
        private static readonly string[] VideoExtensions = { ".mp4", ".mov", ".webm" };
        private static readonly string[] ImageExtensions = { ".jpg", ".jpeg", ".png", ".webp", ".gif", ".svg" };

        public static readonly string[] MaterialExtensions =
            new[] { ".pdf", ".doc", ".docx", ".ppt", ".pptx", ".xls", ".xlsx", ".jpg", ".jpeg", ".png", ".gif", ".svg", ".webp", ".mp4", ".mov", ".webm" }
            .Concat(AudioExtensions).ToArray();

        public static string Classify(string fileName)
        {
            var ext = Path.GetExtension(fileName).ToLowerInvariant();
            if (ImageExtensions.Contains(ext)) return "Image";
            if (VideoExtensions.Contains(ext)) return "Video";
            if (AudioExtensions.Contains(ext)) return "Audio";
            return "Document";
        }

        public static bool IsAudioUrl(string? url) =>
            !string.IsNullOrEmpty(url) && AudioExtensions.Contains(Path.GetExtension(url.Split('?')[0]).ToLowerInvariant());

        // Uploads are served with nosniff, so every audio type needs an exact
        // Content-Type or the browser refuses to play it.
        public static FileExtensionContentTypeProvider ContentTypes()
        {
            var p = new FileExtensionContentTypeProvider();
            p.Mappings[".mp3"] = "audio/mpeg";
            p.Mappings[".m4a"] = "audio/mp4";
            p.Mappings[".wav"] = "audio/wav";
            p.Mappings[".ogg"] = "audio/ogg";
            p.Mappings[".oga"] = "audio/ogg";
            p.Mappings[".opus"] = "audio/ogg";
            p.Mappings[".aac"] = "audio/aac";
            p.Mappings[".weba"] = "audio/webm";
            return p;
        }
    }
}
