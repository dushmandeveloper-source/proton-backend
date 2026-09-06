namespace DBAccess
{
    // Mirrors the LMS reference project's DBAccess abstraction: every call is
    // a stored procedure name plus a parameter object. Execute<T> is for
    // write sprocs that return their result via a @RetValue OUT parameter.
    public interface IDBAccess
    {
        Task<string> Execute<T>(string storedProcedure, T parameters);
        Task ExecuteNonQuery<T>(string storedProcedure, T parameters);
        Task<T?> Get<T, U>(string storedProcedure, U parameters);
        Task<int> GetCount<U>(string storedProcedure, U parameters);
        Task<List<T>> GetList<T, U>(string storedProcedure, U parameters);
    }
}
