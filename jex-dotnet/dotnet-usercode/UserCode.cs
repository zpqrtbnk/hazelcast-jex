using Hazelcast;
using Hazelcast.Demo;
using Hazelcast.UserCode;
using Hazelcast.UserCode.Data;
using Microsoft.Extensions.Logging;

// expected class 'UserCode' in the root namespace
// ReSharper disable once CheckNamespace
// ReSharper disable once UnusedMember.Global
#pragma warning disable CA1050 // wants namespace
public class UserCode : IUserCodeMethod<IMapEntry, IMapEntry>, IUserCodeConfigureClient
#pragma warning restore CA1050
{
    private int _count;

    public ValueTask<IMapEntry> Execute(IMapEntry input, UserCodeContext context)
    {
        var (key, value) = input.Of<string, SomeThing>();

        context.Logger.LogDebug($"EXECUTE: input key={key}, value={value}.");

        // compute result, with "state"
        var count = Interlocked.Increment(ref _count);
        var result = new OtherThing { Value = $"__{value.Value}__{count}__" };

        context.Logger.LogDebug($"EXECUTE: output key={key}, value={result}.");

        return new ValueTask<IMapEntry>(IMapEntry.New(key, result));
    }

    public void ConfigureClient(HazelcastOptionsBuilder optionsBuilder)
    {
        optionsBuilder.With(options =>
        {
            var compact = options.Serialization.Compact;

            // register serializers - we want this in order to use
            // well-known polyglot type-name and property names
            compact.AddSerializer(new SomeThingSerializer());
            compact.AddSerializer(new OtherThingSerializer());
        });
    }
}