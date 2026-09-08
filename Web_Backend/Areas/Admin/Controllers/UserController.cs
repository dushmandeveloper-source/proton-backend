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
        private static readonly string[] ProtectedRoleNames = { "Admin", "Student", "Instructor" };

        // Student and Instructor specifically (not Admin) must also never be
        // deactivated — a real dev-data incident showed these rows can end
        // up IsActive='I' via EditRole's status toggle even though renaming
        // and deleting were already blocked. Kept separate from
        // ProtectedRoleNames since Admin isn't included here.
        private static readonly string[] NonDeactivatableRoleNames = { "Student", "Instructor" };

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

        private async Task PopulateLists(UserManagementViewModel model, bool showInactive = false, string keyW = "", string roleFilter = "")
        {
            // Deleted (soft-deleted) rows drop out of the default view — the
            // data is retained (IsActive='I'); "Show inactive" brings them
            // back into view so they can be restored via Edit.
            // KeyW/roleFilter narrow the Users tab's list further (matched
            // against FullName/Email and UserTypeID respectively by
            // usr.Users_List, which already supports both params).
            model.Users = await userRep.GetList(new AppUserSearchView
            {
                KeyW = keyW,
                UserTypeID = roleFilter,
                IsActive = showInactive ? "" : "A"
            });
            model.Roles = await userTypeRep.GetList(isActive: showInactive ? "" : "A");
            model.ShowInactive = showInactive;
            model.KeyW = keyW;
            model.RoleFilter = roleFilter;
        }

        [HttpGet]
        public async Task<IActionResult> Index(string tab = "users", bool showInactive = false, string KeyW = "", string roleFilter = "")
        {
            Auth.CheckPermission(PermissionCode.UserManagement, 'V');
            ViewBag.CurrentUser = Auth.GetUser();
            var model = new UserManagementViewModel { ActiveTab = tab == "roles" ? "roles" : "users" };
            await PopulateLists(model, showInactive, KeyW, roleFilter);

            // Only worth the per-user round trip when the permanent-delete
            // button is actually rendered — the counts only fill its dialog.
            if (Auth.HasPermission(PermissionCode.UserManagement, 'D'))
            {
                foreach (var user in model.Users)
                {
                    var impact = await userRep.GetDeleteImpact(user.UserID);
                    if (impact != null) model.DeleteImpacts[user.UserID] = impact;
                }
            }

            return View(model);
        }

        // Every role's permission grid, keyed by UserTypeID, for the Add/Edit
        // User form's client-side role-switch preview (Index.cshtml's
        // data-role-defaults) — so picking a role shows what it grants
        // without a server round-trip.
        private async Task<Dictionary<string, List<PermissionGridViewModel>>> BuildRolePermissionsByRole(List<UserType> roles)
        {
            var result = new Dictionary<string, List<PermissionGridViewModel>>();
            foreach (var role in roles)
            {
                var rp = role.UserTypeID == Auth.MasterAdminRoleId
                    ? PermissionCode.All.Select(m => new PermissionGridViewModel { ModuleCode = m.Code, ModuleLabel = m.Label, CanView = true, CanAdd = true, CanEdit = true, CanDelete = true }).ToList()
                    : PermissionGridViewModel.BuildFromRole(await rolePermissionRep.GetForRole(role.UserTypeID));
                result[role.UserTypeID] = rp;
            }
            return result;
        }

        [HttpGet]
        public async Task<IActionResult> Add()
        {
            Auth.CheckPermission(PermissionCode.UserManagement, 'V');
            ViewBag.CurrentUser = Auth.GetUser();
            var model = new UserManagementViewModel
            {
                ActiveTab = "addUser",
                AddUserForm = new AddUserViewModel
                {
                    PermissionOverrides = PermissionCode.All.Select(m => new PermissionGridViewModel
                    {
                        ModuleCode = m.Code,
                        ModuleLabel = m.Label
                    }).ToList()
                }
            };
            await PopulateLists(model);
            ViewBag.RolePermissionsByRole = await BuildRolePermissionsByRole(model.Roles);
            return View("Index", model);
        }

        [HttpPost, ValidateAntiForgeryToken]
        public async Task<IActionResult> Add(AddUserViewModel form)
        {
            Auth.CheckPermission(PermissionCode.UserManagement, 'A');
            ViewBag.CurrentUser = Auth.GetUser();

            // Only an existing Master Admin can grant Master Admin — otherwise
            // any user with plain UserManagement Add access could hand
            // themselves (or anyone) unconditional full access via this form.
            if (form.Role == Auth.MasterAdminRoleId && Auth.GetUser()?.Role != Auth.MasterAdminRoleId)
                ModelState.AddModelError(nameof(form.Role), "Only a Master Admin can assign the Master Admin role.");

            // Students must only ever be created through the Student
            // Registration flow (it collects DOB/passport/address/emergency
            // contact that this generic Add User form doesn't ask for).
            var addRoles = await userTypeRep.GetList(isActive: "");
            var addStudentRole = addRoles.FirstOrDefault(t => t.UserTypeName.Equals("Student", StringComparison.OrdinalIgnoreCase));
            if (addStudentRole != null && string.Equals(form.Role, addStudentRole.UserTypeID, StringComparison.OrdinalIgnoreCase))
                ModelState.AddModelError(nameof(form.Role), "Students can't be created here — use the Students section to register a new student.");

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

            foreach (var module in form.PermissionOverrides.Where(m => m.CanView != null || m.CanAdd != null || m.CanEdit != null || m.CanDelete != null))
            {
                await userPermissionOverrideRep.Save(new UserPermissionOverride
                {
                    UserID = userId,
                    ModuleCode = module.ModuleCode,
                    CanView = module.CanView,
                    CanAdd = module.CanAdd,
                    CanEdit = module.CanEdit,
                    CanDelete = module.CanDelete
                });
            }

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
            Auth.CheckPermission(PermissionCode.UserManagement, 'V');
            ViewBag.CurrentUser = Auth.GetUser();

            var user = await userRep.Get(id);
            if (user == null) return RedirectToAction("Index", new { tab = "users" });

            var overrides = await userPermissionOverrideRep.GetForUser(id);

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
                    IsActive = user.IsActive == "A",
                    PermissionOverrides = PermissionGridViewModel.BuildOverridesFromUser(overrides)
                }
            };
            await PopulateLists(model);
            ViewBag.RolePermissionsByRole = await BuildRolePermissionsByRole(model.Roles);

            return View("Index", model);
        }

        [HttpPost, ValidateAntiForgeryToken]
        public async Task<IActionResult> Edit(EditUserViewModel form)
        {
            Auth.CheckPermission(PermissionCode.UserManagement, 'E');
            ViewBag.CurrentUser = Auth.GetUser();

            // Only an existing Master Admin can grant Master Admin — otherwise
            // any user with plain UserManagement Edit access could hand
            // themselves (or anyone) unconditional full access via this form.
            if (form.Role == Auth.MasterAdminRoleId && Auth.GetUser()?.Role != Auth.MasterAdminRoleId)
                ModelState.AddModelError(nameof(form.Role), "Only a Master Admin can assign the Master Admin role.");

            if (ModelState.IsValid)
            {
                var existing = await userRep.GetByEmail(form.Email);
                if (existing != null && existing.UserID != form.UserID)
                    ModelState.AddModelError(nameof(form.Email), "A user with this email already exists.");
            }

            // Once a user is a Student, this generic form can't move them to
            // a different role — students are managed from the Students
            // section, which owns the extra registration data (DOB,
            // passport, address, emergency contact) this form never touches.
            var currentUser = await userRep.Get(form.UserID);
            var roles = await userTypeRep.GetList(isActive: "");
            var studentRole = roles.FirstOrDefault(t => t.UserTypeName.Equals("Student", StringComparison.OrdinalIgnoreCase));
            if (currentUser != null && studentRole != null &&
                currentUser.UserTypeID == studentRole.UserTypeID &&
                !string.Equals(form.Role, currentUser.UserTypeID, StringComparison.OrdinalIgnoreCase))
            {
                ModelState.AddModelError(nameof(form.Role), "A student's role can't be changed here — manage this student from the Students section instead.");
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

            foreach (var module in form.PermissionOverrides)
            {
                await userPermissionOverrideRep.Save(new UserPermissionOverride
                {
                    UserID = form.UserID,
                    ModuleCode = module.ModuleCode,
                    CanView = module.CanView,
                    CanAdd = module.CanAdd,
                    CanEdit = module.CanEdit,
                    CanDelete = module.CanDelete
                });
            }

            TempData["SuccessMessage"] = $"User '{form.FirstName} {form.LastName}' updated.";
            return RedirectToAction("Index", new { tab = "users" });
        }

        [HttpPost, ValidateAntiForgeryToken]
        public async Task<IActionResult> Delete(string id)
        {
            Auth.CheckPermission(PermissionCode.UserManagement, 'D');
            try
            {
                await userRep.Delete(id);
                TempData["SuccessMessage"] = "User deactivated.";
            }
            catch (Exception ex)
            {
                TempData["ErrorMessage"] = "Could not deactivate user: " + ex.Message;
            }
            return RedirectToAction("Index", new { tab = "users" });
        }

        [HttpPost, ValidateAntiForgeryToken]
        public async Task<IActionResult> Activate(string id)
        {
            Auth.CheckPermission(PermissionCode.UserManagement, 'E');
            try
            {
                var user = await userRep.Get(id);
                if (user == null)
                {
                    TempData["ErrorMessage"] = "User not found.";
                    return RedirectToAction("Index", new { tab = "users" });
                }
                user.IsActive = "A";
                await userRep.AddEdit(user);
                TempData["SuccessMessage"] = "User activated.";
            }
            catch (Exception ex)
            {
                TempData["ErrorMessage"] = "Could not activate user: " + ex.Message;
            }
            return RedirectToAction("Index", new { tab = "users", showInactive = true });
        }

        // Permanent counterpart to Delete above, which only deactivates. The
        // stored procedure refuses when the account carries real history
        // (registrations, batch assignments, reschedules, materials), so the
        // guard rails live in one place rather than being re-checked here.
        [HttpPost, ValidateAntiForgeryToken]
        public async Task<IActionResult> HardDelete(string id)
        {
            Auth.CheckPermission(PermissionCode.UserManagement, 'D');
            try
            {
                await userRep.HardDelete(id, Auth.GetUserId());
                TempData["SuccessMessage"] = "User permanently deleted.";
            }
            catch (Exception ex)
            {
                TempData["ErrorMessage"] = "Could not permanently delete user: " + ex.Message;
            }
            return RedirectToAction("Index", new { tab = "users" });
        }

        [HttpPost, ValidateAntiForgeryToken]
        public async Task<IActionResult> ResetPassword(string id)
        {
            Auth.CheckPermission(PermissionCode.UserManagement, 'E');

            var user = await userRep.Get(id);
            if (user == null)
            {
                TempData["ErrorMessage"] = "User not found.";
                return RedirectToAction("Index", new { tab = "users" });
            }

            // Looked up by UserID (the real relationship), not by email —
            // the user's usr.Users.Email may have been edited since their
            // usr.UserAuth row was created, and that row's own Email/
            // Username column is never kept in sync automatically.
            var auth = await authRep.FindByUserId(user.UserID);
            var tempPassword = GenerateTempPassword();
            var (hash, salt) = PasswordHasher.Hash(tempPassword);

            if (auth == null)
            {
                // No usr.UserAuth row exists yet — create it now rather than
                // failing, so "reset password" always results in a working
                // login the admin can hand to the user.
                await authRep.AddEdit("", user.UserID, user.Email, user.Email, hash, salt);
            }
            else
            {
                // Pass the existing AuthID + the CURRENT email so a stale
                // Username/Email on this row gets corrected at the same
                // time the password resets.
                await authRep.AddEdit(auth.AuthID, user.UserID, user.Email, user.Email, hash, salt);
            }

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
        public async Task<IActionResult> Unlock(string id)
        {
            Auth.CheckPermission(PermissionCode.UserManagement, 'E');

            var user = await userRep.Get(id);
            if (user == null)
            {
                TempData["ErrorMessage"] = "User not found.";
                return RedirectToAction("Index", new { tab = "users" });
            }

            // Looked up by UserID, same as ResetPassword above — the auth
            // row's own Email/Username column can go stale independently of
            // usr.Users.Email.
            var auth = await authRep.FindByUserId(user.UserID);
            if (auth == null)
            {
                TempData["ErrorMessage"] = "This user has no login set up yet.";
                return RedirectToAction("Index", new { tab = "users" });
            }

            await authRep.Unlock(auth.AuthID);
            TempData["SuccessMessage"] = $"'{user.FullName}' has been unlocked and can sign in again.";
            return RedirectToAction("Index", new { tab = "users" });
        }

        [HttpPost, ValidateAntiForgeryToken]
        public async Task<JsonResult> SetRole(string id, string role)
        {
            Auth.CheckPermission(PermissionCode.UserManagement, 'E');

            // Only an existing Master Admin can grant Master Admin — otherwise
            // any user with plain UserManagement Edit access could hand
            // themselves (or anyone) unconditional full access via this
            // quick-role-select dropdown.
            if (role == Auth.MasterAdminRoleId && Auth.GetUser()?.Role != Auth.MasterAdminRoleId)
                return Json(new { success = false, message = "Only a Master Admin can assign the Master Admin role." });

            // Same Student rules as the Add/Edit User forms, enforced here
            // too since this quick-role-select dropdown is a separate path
            // to the same underlying change: never assign Student through
            // here, and never move an existing Student to something else.
            var quickRoles = await userTypeRep.GetList(isActive: "");
            var quickStudentRole = quickRoles.FirstOrDefault(t => t.UserTypeName.Equals("Student", StringComparison.OrdinalIgnoreCase));
            if (quickStudentRole != null)
            {
                var quickUser = await userRep.Get(id);
                if (role == quickStudentRole.UserTypeID)
                    return Json(new { success = false, message = "Students can't be assigned here — use the Students section to register a new student." });
                if (quickUser != null && quickUser.UserTypeID == quickStudentRole.UserTypeID)
                    return Json(new { success = false, message = "A student's role can't be changed here — manage this student from the Students section instead." });
            }

            await userRep.SetUserType(id, role);
            return Json(new { success = true });
        }

        [HttpGet]
        public async Task<IActionResult> AddRole()
        {
            Auth.CheckPermission(PermissionCode.UserManagement, 'V');
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
            Auth.CheckPermission(PermissionCode.UserManagement, 'A');
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
            Auth.CheckPermission(PermissionCode.UserManagement, 'V');
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
            Auth.CheckPermission(PermissionCode.UserManagement, 'E');
            ViewBag.CurrentUser = Auth.GetUser();

            if (form.UserTypeID == Auth.MasterAdminRoleId)
            {
                TempData["ErrorMessage"] = "The Master Admin role can't be changed.";
                return RedirectToAction("Index", new { tab = "roles" });
            }

            // Block renaming a protected role (e.g. "Admin" -> "Adminx") even
            // though the row itself isn't locked from other edits — otherwise
            // a rename followed by DeleteRole would bypass the protected-name
            // check there, since that check only matches on the current name.
            var currentRole = await userTypeRep.Get(form.UserTypeID);
            if (currentRole != null &&
                ProtectedRoleNames.Any(n => currentRole.UserTypeName.Equals(n, StringComparison.OrdinalIgnoreCase)) &&
                !currentRole.UserTypeName.Equals(form.UserTypeName, StringComparison.OrdinalIgnoreCase))
            {
                ModelState.AddModelError(nameof(form.UserTypeName), "This role's name can't be changed.");
            }

            // Block deactivating Student/Instructor outright — only renaming
            // and deleting were guarded before, which is how these two ended
            // up IsActive='I' in dev data via this very toggle.
            if (currentRole != null && !form.IsActive &&
                NonDeactivatableRoleNames.Any(n => currentRole.UserTypeName.Equals(n, StringComparison.OrdinalIgnoreCase)))
            {
                ModelState.AddModelError(nameof(form.IsActive), $"The '{currentRole.UserTypeName}' role can't be deactivated.");
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
            Auth.CheckPermission(PermissionCode.UserManagement, 'D');

            if (id == Auth.MasterAdminRoleId)
            {
                TempData["ErrorMessage"] = "The Master Admin role can't be removed.";
                return RedirectToAction("Index", new { tab = "roles" });
            }

            var role = await userTypeRep.Get(id);
            if (role != null && ProtectedRoleNames.Any(n => role.UserTypeName.Equals(n, StringComparison.OrdinalIgnoreCase)))
            {
                TempData["ErrorMessage"] = $"The '{role.UserTypeName}' role can't be removed.";
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
