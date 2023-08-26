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

namespace Hazelcast.Demo;

public class OtherThingSerializer : CompactSerializerBase<OtherThing>
{
    public override string TypeName => "other-thing";

    public override OtherThing Read(ICompactReader reader)
    {
        return new OtherThing
        {
            Value = reader.ReadString("value")
        };
    }

    public override void Write(ICompactWriter writer, OtherThing value)
    {
        writer.WriteString("value", value.Value);
    }
}
