using Web_Backend.Areas.Admin.Models;

namespace Web_Backend.Areas.Admin.Data
{
    public interface IUniversityData
    {
        Task<List<University>> GetList(UniversitySearchView search);
        Task<University?> Get(string id);
        Task<string> AddEdit(University university);
        Task Delete(string id);

        Task<List<UniversityGalleryItem>> GetGallery(string universityId);
        Task<string> AddEditGallery(UniversityGalleryItem item);
        Task DeleteGallery(string id);

        Task<List<UniversityFeature>> GetFeatures(string universityId);
        Task<string> AddEditFeature(UniversityFeature feature);
        Task DeleteFeature(string id);

        Task<List<UniversityProgram>> GetPrograms(string universityId);
        Task<string> AddEditProgram(UniversityProgram program);
        Task DeleteProgram(string id);

        Task<List<UniversityIntake>> GetIntakes(string universityId);
        Task<string> AddEditIntake(UniversityIntake intake);
        Task DeleteIntake(string id);
    }
}
