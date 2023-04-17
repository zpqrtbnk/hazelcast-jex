// Copyright (c) 2008-2023, Hazelcast, Inc. All Rights Reserved.
// 
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
// 
// http://www.apache.org/licenses/LICENSE-2.0
// 
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

using Hazelcast.Serialization;
using Hazelcast.Serialization.Compact;

namespace Hazelcast.Jet.Service;

internal class SomeThingSerializer : CompactSerializerBase<SomeThing>
{
    public static readonly Schema CompactSchema = SchemaBuilder
        .For("some-thing")
        .WithField("value", FieldKind.Int32)
        .Build();

    public override string TypeName => "some-thing";

    public override SomeThing Read(ICompactReader reader)
    {
        return new SomeThing
        {
            Value = reader.ReadInt32("value")
        };
    }

    public override void Write(ICompactWriter writer, SomeThing value)
    {
        writer.WriteInt32("value", value.Value);
    }
}
