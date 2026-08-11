using System.Security.Cryptography;
using Microsoft.AspNetCore.Mvc;
using Web_Backend.Areas.Admin.Data;
using Web_Backend.Areas.Admin.Models;
using Web_Backend.Classes;

namespace Web_Backend.Areas.Admin.Controllers
{
    [Area("Admin")]
    public class UserController : Controller
    {
        private readonly IUserData userRep;
        private readonly IUserAuthData authRep;
        private readonly IUserTypeData userTypeRep;

        public UserController(IUserData userRep, IUserAuthData authRep, IUserTypeData userTypeRep)
        {
            this.userRep = userRep;
            this.authRep = authRep;
            this.userTypeRep = userTypeRep;
        }

        [HttpGet]
        public async Task<IActionResult> Add()
        {
            Auth.CheckUser();
            ViewBag.CurrentUser = Auth.GetUser();
            ViewBag.UserTypes = await userTypeRep.GetList(isActive: "A");
            return View(new AddUserViewModel());
        }

        [HttpPost, ValidateAntiForgeryToken]
        public async Task<IActionResult> Add(AddUserViewModel model)
        {
            Auth.CheckUser();
            ViewBag.CurrentUser = Auth.GetUser();
            ViewBag.UserTypes = await userTypeRep.GetList(isActive: "A");

            if (!ModelState.IsValid)
                return View(model);

            var existing = await userRep.GetByEmail(model.Email);
            if (existing != null)
            {
                ModelState.AddModelError(nameof(model.Email), "A user with this email already exists.");
                return View(model);
            }

            var name = $"{model.FirstName} {model.LastName}".Trim();
            var userId = await userRep.AddEdit(new AppUser
            {
                FullName = name,
                FirstName = model.FirstName,
                LastName = model.LastName,
                Email = model.Email,
                UserTypeID = model.Role,
                IsActive = "A"
            });

            // No account-creation email is wired up yet, so the temp password
            // is surfaced once here instead of silently vanishing.
            var tempPassword = GenerateTempPassword();
            var (hash, salt) = PasswordHasher.Hash(tempPassword);
            await authRep.AddEdit("", userId, model.Email, model.Email, hash, salt);

            TempData["SuccessMessage"] =
                $"User '{name}' created. Temporary password: {tempPassword} " +
                "(dev mode — no email sender configured yet, share this securely).";
            return RedirectToAction("Add");
        }

        private static string GenerateTempPassword()
        {
            const string chars = "ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789";
            var bytes = RandomNumberGenerator.GetBytes(12);
            return new string(bytes.Select(b => chars[b % chars.Length]).ToArray());
        }
    }
}
