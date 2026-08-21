namespace Web_Backend.Classes
{
    // Distinct from a bare UnauthorizedAccessException (not logged in, which
    // redirects to Login) — this means the user IS logged in but lacks the
    // specific permission for the action they tried. Caught by
    // UnauthorizedRedirectFilter and turned into a Dashboard redirect with a
    // toast instead of bouncing them out to the login page.
    public class PermissionDeniedException : UnauthorizedAccessException
    {
        public PermissionDeniedException(string message) : base(message) { }
    }
}
