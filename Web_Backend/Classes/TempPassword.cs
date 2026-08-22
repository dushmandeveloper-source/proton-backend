using System.Security.Cryptography;

namespace Web_Backend.Classes
{
    // Shared by any flow that creates a login without the user choosing their
    // own password up front (admin-created users, admin-registered students).
    public static class TempPassword
    {
        private const string Chars = "ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789";

        public static string Generate()
        {
            var bytes = RandomNumberGenerator.GetBytes(12);
            return new string(bytes.Select(b => Chars[b % Chars.Length]).ToArray());
        }
    }
}
