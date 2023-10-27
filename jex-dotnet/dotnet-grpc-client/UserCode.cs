using Hazelcast;
using Hazelcast.UserCode;

// expected class 'UserCode' in the root namespace
// ReSharper disable once CheckNamespace
// ReSharper disable once UnusedMember.Global
#pragma warning disable CA1050 // wants namespace
public class UserCode : IUserCodeMethod<string, string>
#pragma warning restore CA1050
{
    public ValueTask<string> Execute(string input, UserCodeContext context)
    {
        return new ValueTask<string>(input + "!!");
    }

    public void ConfigureClient(HazelcastOptionsBuilder optionsBuilder)
    { }

    public void ConfigureContext(UserCodeContext context)
    { }
}