using System.Security.Cryptography;

namespace Web_Backend.Classes
{
    // PBKDF2 with a random per-user salt, matching the UserAuth.PasswordHash /
    // PasswordSalt columns. Verification recomputes the hash with the stored
    // salt and compares in constant time — the raw hash is never trusted
    // from the caller, unlike a scheme that compares a client-supplied hash.
    //
    // Iteration count: new hashes use 600,000 (OWASP's PBKDF2-SHA256 figure)
    // and record it in the salt column as "600000$<salt>". A salt without
    // that prefix is a legacy 100,000-iteration hash; NeedsUpgrade lets the
    // login paths re-hash it once the password has been verified.
    public static class PasswordHasher
    {
        private const int SaltSize = 16;
        private const int HashSize = 32;
        private const int LegacyIterations = 100_000;
        private const int Iterations = 600_000;

        public static (string Hash, string Salt) Hash(string password)
        {
            var salt = RandomNumberGenerator.GetBytes(SaltSize);
            var hash = Rfc2898DeriveBytes.Pbkdf2(password, salt, Iterations, HashAlgorithmName.SHA256, HashSize);
            return (Convert.ToBase64String(hash), $"{Iterations}${Convert.ToBase64String(salt)}");
        }

        public static bool Verify(string password, string storedHash, string storedSalt)
        {
            var (iterations, saltText) = Parse(storedSalt);
            var salt = Convert.FromBase64String(saltText);
            var expected = Convert.FromBase64String(storedHash);
            var actual = Rfc2898DeriveBytes.Pbkdf2(password, salt, iterations, HashAlgorithmName.SHA256, HashSize);
            return CryptographicOperations.FixedTimeEquals(expected, actual);
        }

        public static bool NeedsUpgrade(string storedSalt) => Parse(storedSalt).Iterations < Iterations;

        private static (int Iterations, string Salt) Parse(string storedSalt)
        {
            var sep = storedSalt.IndexOf('$');
            if (sep > 0 && int.TryParse(storedSalt[..sep], out var n))
                return (n, storedSalt[(sep + 1)..]);
            return (LegacyIterations, storedSalt);
        }
    }
}
