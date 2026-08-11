using System.Data;
using Dapper;
using Microsoft.Data.SqlClient;

namespace DBAccess
{
    // Opens a fresh connection per call (no persistent connection), same as
    // the LMS reference project. Uses CommandType.StoredProcedure directly
    // instead of the string-concatenated parameter list the reference
    // project's Exten.cs builds by hand.
    public class MSSQLDataAccess : IDBAccess
    {
        private readonly string _connectionString;

        public MSSQLDataAccess(string connectionString)
        {
            _connectionString = connectionString;
        }

        private SqlConnection CreateConnection() => new(_connectionString);

        public async Task<string> Execute<T>(string storedProcedure, T parameters)
        {
            var dynamicParams = new DynamicParameters(parameters);
            dynamicParams.Add("@RetValue", dbType: DbType.String, direction: ParameterDirection.Output, size: 50);

            using var conn = CreateConnection();
            await conn.ExecuteAsync(storedProcedure, dynamicParams, commandType: CommandType.StoredProcedure);

            return dynamicParams.Get<string>("@RetValue");
        }

        public async Task ExecuteNonQuery<T>(string storedProcedure, T parameters)
        {
            using var conn = CreateConnection();
            await conn.ExecuteAsync(storedProcedure, parameters, commandType: CommandType.StoredProcedure);
        }

        public async Task<T?> Get<T, U>(string storedProcedure, U parameters)
        {
            using var conn = CreateConnection();
            return await conn.QueryFirstOrDefaultAsync<T>(storedProcedure, parameters, commandType: CommandType.StoredProcedure);
        }

        public async Task<int> GetCount<U>(string storedProcedure, U parameters)
        {
            using var conn = CreateConnection();
            return await conn.ExecuteScalarAsync<int>(storedProcedure, parameters, commandType: CommandType.StoredProcedure);
        }

        public async Task<List<T>> GetList<T, U>(string storedProcedure, U parameters)
        {
            using var conn = CreateConnection();
            var result = await conn.QueryAsync<T>(storedProcedure, parameters, commandType: CommandType.StoredProcedure);
            return result.ToList();
        }
    }
}
