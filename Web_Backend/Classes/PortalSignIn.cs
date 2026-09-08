using System.Security.Cryptography;
using Web_Backend.Areas.Admin.Data;
using Web_Backend.Areas.Admin.Models;

namespace Web_Backend.Classes
{
    // Which portal a sign-in page belongs to. Each portal has its own
    // Login/ForgotPassword/ResetPassword pages so the branding matches where
    // the user actually lands, and so an account can only sign in through the
    // portal it belongs to (a student can't sign in on the Admin page, etc.).
    public enum Portal
    {
        Admin,
        Student,
        Lecturer
    }

    public class SignInOutcome
    {
        public bool Success { get; init; }
        public string? ErrorMessage { get; init; }
    }

    // Shared sign-in / password-reset plumbing behind the three portals'
    // AccountControllers. Without this the ~50 lines of permission assembly and
    // the reset-token flow would be copy-pasted three times and drift apart.
    public class PortalSignIn
    {
        private readonly IUserAuthData authRep;
        private readonly IRolePermissionData rolePermissionRep;
        private readonly IUserPermissionOverrideData userPermissionOverrideRep;
        private readonly IUserTypeData userTypeRep;
        private readonly IPasswordResetData resetRep;

        public PortalSignIn(
            IUserAuthData authRep,
            IRolePermissionData rolePermissionRep,
            IUserPermissionOverrideData userPermissionOverrideRep,
            IUserTypeData userTypeRep,
            IPasswordResetData resetRep)
        {
            this.authRep = authRep;
            this.rolePermissionRep = rolePermissionRep;
            this.userPermissionOverrideRep = userPermissionOverrideRep;
            this.userTypeRep = userTypeRep;
            this.resetRep = resetRep;
        }

        // Resolves which portal an account belongs to from its UserTypeID.
        // Anything that isn't Student or Instructor is staff, so it belongs to
        // the Admin portal — same rule AreaAccessFilter applies.
        public async Task<Portal> GetPortalForUserType(string userTypeId)
        {
            var userTypes = await userTypeRep.GetList();
            var studentTypeId = userTypes.FirstOrDefault(t => t.UserTypeName == "Student")?.UserTypeID;
            if (studentTypeId != null && userTypeId == studentTypeId) return Portal.Student;

            var instructorTypeId = userTypes.FirstOrDefault(t => t.UserTypeName == "Instructor")?.UserTypeID;
            if (instructorTypeId != null && userTypeId == instructorTypeId) return Portal.Lecturer;

            return Portal.Admin;
        }

        public static (string area, string controller, string action) DashboardRoute(Portal portal) =>
            (portal.ToString(), "Dashboard", "Index");

        // Validates credentials and, on success, establishes the session.
        // `portal` is the portal whose login page was used — an account
        // belonging to a different portal is rejected here rather than being
        // signed in and then bounced by AreaAccessFilter, so the user gets a
        // clear "wrong sign-in page" message instead of a silent redirect.
        public async Task<SignInOutcome> SignInAsync(string email, string password, bool rememberMe, Portal portal)
        {
            var auth = await authRep.FindForLogin(email);
            if (auth == null)
                return new SignInOutcome { Success = false, ErrorMessage = "Invalid email or password." };

            if (auth.IsLocked)
                return new SignInOutcome { Success = false, ErrorMessage = "This account is locked after too many failed attempts. Contact an administrator." };

            if (auth.AuthIsActive != "A" || auth.UserIsActive != "A")
                return new SignInOutcome { Success = false, ErrorMessage = "This account has been deactivated. Please contact the administration to have it reactivated." };

            if (!PasswordHasher.Verify(password, auth.PasswordHash, auth.PasswordSalt))
            {
                await authRep.RecordLoginResult(auth.AuthID, success: false);
                return new SignInOutcome { Success = false, ErrorMessage = "Invalid email or password." };
            }

            var accountPortal = await GetPortalForUserType(auth.UserTypeID);
            if (accountPortal != portal)
            {
                var where = accountPortal switch
                {
                    Portal.Student => "the Student sign-in page",
                    Portal.Lecturer => "the Lecturer sign-in page",
                    _ => "the Admin sign-in page"
                };
                return new SignInOutcome { Success = false, ErrorMessage = $"This account signs in through {where}." };
            }

            await authRep.RecordLoginResult(auth.AuthID, success: true);

            var rolePermissions = await rolePermissionRep.GetForRole(auth.UserTypeID);
            var overrides = await userPermissionOverrideRep.GetForUser(auth.UserID);
            var overrideByModule = overrides.ToDictionary(o => o.ModuleCode);

            var effective = PermissionCode.All.ToDictionary(
                m => m.Code,
                m =>
                {
                    var role = rolePermissions.FirstOrDefault(p => p.ModuleCode == m.Code);
                    var ov = overrideByModule.TryGetValue(m.Code, out var o) ? o : null;
                    return new PermissionGridViewModel
                    {
                        ModuleCode = m.Code,
                        ModuleLabel = m.Label,
                        CanView = ov?.CanView ?? role?.CanView ?? false,
                        CanAdd = ov?.CanAdd ?? role?.CanAdd ?? false,
                        CanEdit = ov?.CanEdit ?? role?.CanEdit ?? false,
                        CanDelete = ov?.CanDelete ?? role?.CanDelete ?? false,
                    };
                });

            await Auth.SignIn(new SessionUser
            {
                Id = auth.UserID,
                Name = auth.FullName,
                Email = auth.Email,
                Role = auth.UserTypeID,
                Permissions = effective
            }, rememberMe);

            return new SignInOutcome { Success = true };
        }

        // Issues a reset token for an account, but only if it belongs to the
        // portal whose Forgot Password page was used — otherwise the response
        // is indistinguishable from "no such email", which is also what a
        // genuinely unknown address gets, so neither leaks account existence.
        public async Task<(bool issued, string email, string fullName, string token)> CreateResetTokenAsync(string email, Portal portal)
        {
            var auth = await authRep.FindForLogin(email);
            if (auth == null || auth.AuthIsActive != "A" || auth.UserIsActive != "A")
                return (false, "", "", "");

            var accountPortal = await GetPortalForUserType(auth.UserTypeID);
            if (accountPortal != portal)
                return (false, "", "", "");

            var token = Convert.ToBase64String(RandomNumberGenerator.GetBytes(32))
                .Replace('+', '-').Replace('/', '_').TrimEnd('=');
            await resetRep.CreateToken(auth.AuthID, auth.Email, token, DateTime.UtcNow.AddMinutes(30));

            return (true, auth.Email, auth.FullName, token);
        }

        public Task<PasswordResetTokenRecord?> ValidateResetTokenAsync(string token) => resetRep.Validate(token);

        public async Task ApplyNewPasswordAsync(string token, string authId, string newPassword)
        {
            var (hash, salt) = PasswordHasher.Hash(newPassword);
            await authRep.EditPassword(authId, hash, salt);
            await resetRep.MarkUsed(token);
        }
    }
}
