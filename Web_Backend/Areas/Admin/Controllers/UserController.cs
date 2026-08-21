using System.Security.Cryptography;
using Microsoft.AspNetCore.Mvc;
using Web_Backend.Areas.Admin.Data;
using Web_Backend.Areas.Admin.Models;
using Web_Backend.Classes;

namespace Web_Backend.Areas.Admin.Controllers
{
    // Single "User Management" hub: Users and Roles list side by side as
    // tabs on one page, with Add/Edit for either opening as a third,
    // dynamic tab rather than a full separate page.
    [Area("Admin")]
    public class UserController : Controller
    {
        private const string AdminRoleName = "Admin";

        private readonly IUserData userRep;
        private readonly IUserAuthData authRep;
        private readonly IUserTypeData userTypeRep;
        private readonly IEmailSender emailSender;
        private readonly IRolePermissionData rolePermissionRep;
        private readonly IUserPermissionOverrideData userPermissionOverrideRep;

        public UserController(IUserData userRep, IUserAuthData authRep, IUserTypeData userTypeRep,
            IEmailSender emailSender, IRolePermissionData rolePermissionRep, IUserPermissionOverrideData userPermissionOverrideRep)
        {
            this.userRep = userRep;
            this.authRep = authRep;
            this.userTypeRep = userTypeRep;
            this.emailSender = emailSender;
            this.rolePermissionRep = rolePermissionRep;
            this.userPermissionOverrideRep = userPermissionOverrideRep;
        }

        private async Task PopulateLists(UserManagementViewModel model, bool showInactive = false)
        {
            // Deleted (soft-deleted) rows drop out of the default view — the
            // data is retained (IsActive='I'); "Show inactive" brings them
            // back into view so they can be restored via Edit.
            model.Users = await userRep.GetList(new AppUserSearchView { IsActive = showInactive ? "" : "A" });
            model.Roles = await userTypeRep.GetList(isActive: showInactive ? "" : "A");
            model.ShowInactive = showInactive;
        }

        [HttpGet]
        public async Task<IActionResult> Index(string tab = "users", bool showInactive = false)
        {
            Auth.CheckUser();
            ViewBag.CurrentUser = Auth.GetUser();
            var model = new UserManagementViewModel { ActiveTab = tab == "roles" ? "roles" : "users" };
            await PopulateLists(model, showInactive);
            return View(model);
        }

        [HttpGet]
        public async Task<IActionResult> Add()
        {
            Auth.CheckUser();
            ViewBag.CurrentUser = Auth.GetUser();
            var model = new UserManagementViewModel { ActiveTab = "addUser", AddUserForm = new AddUserViewModel() };
            await PopulateLists(model);
            return View("Index", model);
        }

        [HttpPost, ValidateAntiForgeryToken]
        public async Task<IActionResult> Add(AddUserViewModel form)
        {
            Auth.CheckUser();
            ViewBag.CurrentUser = Auth.GetUser();

            if (ModelState.IsValid)
            {
                var existing = await userRep.GetByEmail(form.Email);
                if (existing != null)
                    ModelState.AddModelError(nameof(form.Email), "A user with this email already exists.");
            }

            if (!ModelState.IsValid)
            {
                var model = new UserManagementViewModel { ActiveTab = "addUser", AddUserForm = form };
                await PopulateLists(model);
                return View("Index", model);
            }

            var name = $"{form.FirstName} {form.LastName}".Trim();
            var userId = await userRep.AddEdit(new AppUser
            {
                FullName = name,
                FirstName = form.FirstName,
                LastName = form.LastName,
                Email = form.Email,
                UserTypeID = form.Role,
                IsActive = "A"
            });

            var tempPassword = GenerateTempPassword();
            var (hash, salt) = PasswordHasher.Hash(tempPassword);
            await authRep.AddEdit("", userId, form.Email, form.Email, hash, salt);

            var loginUrl = Url.Action("Login", "Account", new { area = "Admin" }, Request.Scheme) ?? "#";
            var description =
                $"Your Proton Admin account has been created.<br/><br/>" +
                $"Email: <strong>{form.Email}</strong><br/>" +
                $"Temporary Password: <strong>{tempPassword}</strong><br/><br/>" +
                "Please sign in and change your password as soon as possible.";
            var emailSent = await emailSender.SendTemplateEmailAsync(form.Email, name, "WELCOME_EMAIL", description, "Sign In", loginUrl);

            // Surfaced via a persistent reveal panel (Index.cshtml) rather
            // than the auto-dismissing toast — a one-time password must stay
            // visible until the admin has actually copied it, whether or not
            // the email send also succeeded.
            TempData["NewCredentialsName"] = name;
            TempData["NewCredentialsEmail"] = form.Email;
            TempData["NewCredentialsPassword"] = tempPassword;
            TempData["NewCredentialsEmailSent"] = emailSent;
            return RedirectToAction("Index", new { tab = "users" });
        }

        [HttpGet]
        public async Task<IActionResult> Edit(string id)
        {
            Auth.CheckUser();
            ViewBag.CurrentUser = Auth.GetUser();

            var user = await userRep.Get(id);
            if (user == null) return RedirectToAction("Index", new { tab = "users" });

            var model = new UserManagementViewModel
            {
                ActiveTab = "editUser",
                EditUserForm = new EditUserViewModel
                {
                    UserID = user.UserID,
                    FirstName = user.FirstName,
                    LastName = user.LastName,
                    Email = user.Email,
                    Role = user.UserTypeID,
                    IsActive = user.IsActive == "A"
                }
            };
            await PopulateLists(model);
            return View("Index", model);
        }

        [HttpPost, ValidateAntiForgeryToken]
        public async Task<IActionResult> Edit(EditUserViewModel form)
        {
            Auth.CheckUser();
            ViewBag.CurrentUser = Auth.GetUser();

            if (ModelState.IsValid)
            {
                var existing = await userRep.GetByEmail(form.Email);
                if (existing != null && existing.UserID != form.UserID)
                    ModelState.AddModelError(nameof(form.Email), "A user with this email already exists.");
            }

            if (!ModelState.IsValid)
            {
                var model = new UserManagementViewModel { ActiveTab = "editUser", EditUserForm = form };
                await PopulateLists(model);
                return View("Index", model);
            }

            await userRep.AddEdit(new AppUser
            {
                UserID = form.UserID,
                FullName = $"{form.FirstName} {form.LastName}".Trim(),
                FirstName = form.FirstName,
                LastName = form.LastName,
                Email = form.Email,
                UserTypeID = form.Role,
                IsActive = form.IsActive ? "A" : "I"
            });

            TempData["SuccessMessage"] = $"User '{form.FirstName} {form.LastName}' updated.";
            return RedirectToAction("Index", new { tab = "users" });
        }

        [HttpPost, ValidateAntiForgeryToken]
        public async Task<IActionResult> Delete(string id)
        {
            Auth.CheckUser();
            try
            {
                await userRep.Delete(id);
                TempData["SuccessMessage"] = "User deleted.";
            }
            catch (Exception ex)
            {
                TempData["ErrorMessage"] = "Could not delete user: " + ex.Message;
            }
            return RedirectToAction("Index", new { tab = "users" });
        }

        [HttpPost, ValidateAntiForgeryToken]
        public async Task<IActionResult> ResetPassword(string id)
        {
            Auth.CheckUser();

            var user = await userRep.Get(id);
            if (user == null)
            {
                TempData["ErrorMessage"] = "User not found.";
                return RedirectToAction("Index", new { tab = "users" });
            }

            var auth = await authRep.FindForLogin(user.Email);
            if (auth == null)
            {
                TempData["ErrorMessage"] = $"'{user.FullName}' has no password login to reset.";
                return RedirectToAction("Index", new { tab = "users" });
            }

            var tempPassword = GenerateTempPassword();
            var (hash, salt) = PasswordHasher.Hash(tempPassword);
            await authRep.EditPassword(auth.AuthID, hash, salt);

            var loginUrl = Url.Action("Login", "Account", new { area = "Admin" }, Request.Scheme) ?? "#";
            var description =
                $"Your Proton Admin password has been reset by an administrator.<br/><br/>" +
                $"Email: <strong>{user.Email}</strong><br/>" +
                $"New Temporary Password: <strong>{tempPassword}</strong><br/><br/>" +
                "Please sign in and change your password as soon as possible.";
            var emailSent = await emailSender.SendTemplateEmailAsync(user.Email, user.FullName, "WELCOME_EMAIL", description, "Sign In", loginUrl);

            TempData["NewCredentialsName"] = user.FullName;
            TempData["NewCredentialsEmail"] = user.Email;
            TempData["NewCredentialsPassword"] = tempPassword;
            TempData["NewCredentialsEmailSent"] = emailSent;
            return RedirectToAction("Index", new { tab = "users" });
        }

        [HttpPost, ValidateAntiForgeryToken]
        public async Task<JsonResult> SetRole(string id, string role)
        {
            Auth.CheckUser();
            await userRep.SetUserType(id, role);
            return Json(new { success = true });
        }

        [HttpGet]
        public async Task<IActionResult> AddRole()
        {
            Auth.CheckUser();
            ViewBag.CurrentUser = Auth.GetUser();
            var model = new UserManagementViewModel
            {
                ActiveTab = "addRole",
                RoleForm = new RoleFormViewModel
                {
                    Permissions = PermissionCode.All.Select(m => new PermissionGridViewModel
                    {
                        ModuleCode = m.Code,
                        ModuleLabel = m.Label,
                        CanView = false,
                        CanAdd = false,
                        CanEdit = false,
                        CanDelete = false
                    }).ToList()
                }
            };
            await PopulateLists(model);
            return View("Index", model);
        }

        [HttpPost, ValidateAntiForgeryToken]
        public async Task<IActionResult> AddRole(RoleFormViewModel form)
        {
            Auth.CheckUser();
            ViewBag.CurrentUser = Auth.GetUser();

            if (ModelState.IsValid && await RoleNameTaken(form.UserTypeName, excludingId: null))
                ModelState.AddModelError(nameof(form.UserTypeName), "A role with this name already exists.");

            if (!ModelState.IsValid)
            {
                var model = new UserManagementViewModel { ActiveTab = "addRole", RoleForm = form };
                await PopulateLists(model);
                return View("Index", model);
            }

            var newRoleId = await userTypeRep.AddEdit(new UserType
            {
                UserTypeName = form.UserTypeName,
                Description = form.Description,
                IsActive = form.IsActive ? "A" : "I"
            });

            foreach (var module in form.Permissions)
            {
                await rolePermissionRep.Save(new RolePermission
                {
                    UserTypeID = newRoleId,
                    ModuleCode = module.ModuleCode,
                    CanView = module.CanView ?? false,
                    CanAdd = module.CanAdd ?? false,
                    CanEdit = module.CanEdit ?? false,
                    CanDelete = module.CanDelete ?? false
                });
            }

            TempData["SuccessMessage"] = $"Role '{form.UserTypeName}' created.";
            return RedirectToAction("Index", new { tab = "roles" });
        }

        // Mirrors the Add/Edit User email check: verified in C# before the
        // stored procedure runs, so a duplicate name surfaces as a field
        // error instead of an unhandled SqlException from the proc's own
        // uniqueness check (usr.UserType_AddEdit).
        private async Task<bool> RoleNameTaken(string name, string? excludingId)
        {
            var roles = await userTypeRep.GetList(isActive: "");
            return roles.Any(r =>
                string.Equals(r.UserTypeName, name, StringComparison.OrdinalIgnoreCase) &&
                r.UserTypeID != excludingId);
        }

        [HttpGet]
        public async Task<IActionResult> EditRole(string id)
        {
            Auth.CheckUser();
            ViewBag.CurrentUser = Auth.GetUser();

            var role = await userTypeRep.Get(id);
            if (role == null) return RedirectToAction("Index", new { tab = "roles" });

            var rolePermissions = await rolePermissionRep.GetForRole(id);
            var permissionGrid = id == Auth.MasterAdminRoleId
                ? PermissionCode.All.Select(m => new PermissionGridViewModel
                {
                    ModuleCode = m.Code,
                    ModuleLabel = m.Label,
                    CanView = true,
                    CanAdd = true,
                    CanEdit = true,
                    CanDelete = true
                }).ToList()
                : PermissionGridViewModel.BuildFromRole(rolePermissions);

            var model = new UserManagementViewModel
            {
                ActiveTab = "editRole",
                RoleForm = new RoleFormViewModel
                {
                    UserTypeID = role.UserTypeID,
                    UserTypeName = role.UserTypeName,
                    Description = role.Description,
                    IsActive = role.IsActive == "A",
                    Permissions = permissionGrid
                }
            };
            await PopulateLists(model);
            return View("Index", model);
        }

        [HttpPost, ValidateAntiForgeryToken]
        public async Task<IActionResult> EditRole(RoleFormViewModel form)
        {
            Auth.CheckUser();
            ViewBag.CurrentUser = Auth.GetUser();

            if (form.UserTypeID == Auth.MasterAdminRoleId)
            {
                TempData["ErrorMessage"] = "The Master Admin role can't be changed.";
                return RedirectToAction("Index", new { tab = "roles" });
            }

            if (ModelState.IsValid && await RoleNameTaken(form.UserTypeName, excludingId: form.UserTypeID))
                ModelState.AddModelError(nameof(form.UserTypeName), "A role with this name already exists.");

            if (!ModelState.IsValid)
            {
                var model = new UserManagementViewModel { ActiveTab = "editRole", RoleForm = form };
                await PopulateLists(model);
                return View("Index", model);
            }

            await userTypeRep.AddEdit(new UserType
            {
                UserTypeID = form.UserTypeID,
                UserTypeName = form.UserTypeName,
                Description = form.Description,
                IsActive = form.IsActive ? "A" : "I"
            });

            foreach (var module in form.Permissions)
            {
                await rolePermissionRep.Save(new RolePermission
                {
                    UserTypeID = form.UserTypeID,
                    ModuleCode = module.ModuleCode,
                    CanView = module.CanView ?? false,
                    CanAdd = module.CanAdd ?? false,
                    CanEdit = module.CanEdit ?? false,
                    CanDelete = module.CanDelete ?? false
                });
            }

            TempData["SuccessMessage"] = $"Role '{form.UserTypeName}' updated.";
            return RedirectToAction("Index", new { tab = "roles" });
        }

        [HttpPost, ValidateAntiForgeryToken]
        public async Task<IActionResult> DeleteRole(string id)
        {
            Auth.CheckUser();

            if (id == Auth.MasterAdminRoleId)
            {
                TempData["ErrorMessage"] = "The Master Admin role can't be removed.";
                return RedirectToAction("Index", new { tab = "roles" });
            }

            var role = await userTypeRep.Get(id);
            if (role != null && role.UserTypeName.Equals(AdminRoleName, StringComparison.OrdinalIgnoreCase))
            {
                TempData["ErrorMessage"] = "The Admin role can't be removed.";
                return RedirectToAction("Index", new { tab = "roles" });
            }

            try
            {
                await userTypeRep.Delete(id);
                TempData["SuccessMessage"] = "Role deleted.";
            }
            catch (Exception ex)
            {
                TempData["ErrorMessage"] = "Could not delete role: " + ex.Message;
            }
            return RedirectToAction("Index", new { tab = "roles" });
        }

        private static string GenerateTempPassword()
        {
            const string chars = "ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789";
            var bytes = RandomNumberGenerator.GetBytes(12);
            return new string(bytes.Select(b => chars[b % chars.Length]).ToArray());
        }
    }
}
