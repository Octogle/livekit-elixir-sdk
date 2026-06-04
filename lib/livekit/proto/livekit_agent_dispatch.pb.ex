defmodule Livekit.JobRestartPolicy do
  @moduledoc false

  use Protobuf, enum: true, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:JRP_ON_FAILURE, 0)
  field(:JRP_NEVER, 1)
end

defmodule Livekit.RoomAgentDispatch do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:name, 1, type: :string)
  field(:identity, 2, type: :string)
  field(:init_request, 3, type: Livekit.InitRequest, json_name: "initRequest")
end

defmodule Livekit.InitRequest do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:prompt, 1, type: :string)
end

defmodule Livekit.CreateAgentDispatchRequest do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:agent_name, 1, type: :string, json_name: "agentName")
  field(:room, 2, type: :string)
  field(:metadata, 3, type: :string)

  field(:restart_policy, 4,
    type: Livekit.JobRestartPolicy,
    enum: true,
    json_name: "restartPolicy"
  )

  field(:deployment, 5, type: :string)
end

defmodule Livekit.DeleteAgentDispatchRequest do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:dispatch_id, 1, type: :string, json_name: "dispatchId")
  field(:room, 2, type: :string)
end

defmodule Livekit.ListAgentDispatchRequest do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:dispatch_id, 1, type: :string, json_name: "dispatchId")
  field(:room, 2, type: :string)
end

defmodule Livekit.AgentDispatch do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:id, 1, type: :string)
  field(:agent_name, 2, type: :string, json_name: "agentName")
  field(:room, 3, type: :string)
  field(:metadata, 4, type: :string)
  # field(:state, 5, ...) — AgentDispatchState references Job from
  # livekit_agent.proto, which this fork does not import. The decoder silently
  # drops unknown field 5, which is fine — callers only need `id`.
  field(:restart_policy, 6,
    type: Livekit.JobRestartPolicy,
    enum: true,
    json_name: "restartPolicy"
  )

  field(:deployment, 7, type: :string)
end

defmodule Livekit.ListAgentDispatchResponse do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:agent_dispatches, 1,
    repeated: true,
    type: Livekit.AgentDispatch,
    json_name: "agentDispatches"
  )
end
