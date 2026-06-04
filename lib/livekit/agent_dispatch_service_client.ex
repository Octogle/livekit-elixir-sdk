defmodule Livekit.AgentDispatchServiceClient do
  @moduledoc """
  Client for the Livekit AgentDispatchService API.

  Used to explicitly dispatch a named agent to a LiveKit room (and the inverse:
  delete a dispatch by id). Mirrors the shape of `Livekit.RoomServiceClient` —
  Tesla over Twirp/Protobuf with a short-lived JWT carrying a `roomAdmin`
  grant.

  ## Why Protobuf (not JSON)

  LiveKit's AgentDispatchService Twirp endpoints accept Protobuf-encoded
  bodies with `Content-Type: application/protobuf`. JSON bodies are rejected
  with a misleading `401 unauthenticated / permissions denied` rather than a
  `415 Unsupported Media Type`, which is easy to mistake for a credentials
  problem.
  """

  alias Livekit.AccessToken
  alias Livekit.{AgentDispatch, CreateAgentDispatchRequest, DeleteAgentDispatchRequest}

  require Logger

  defstruct [:base_url, :api_key, :api_secret, :client, :ttl]

  @default_recv_timeout 30_000
  @default_ttl 600

  @doc """
  Creates a new AgentDispatchServiceClient instance.

  `base_url` may be passed with the `ws://` / `wss://` scheme used by the
  LiveKit websocket endpoint — it is normalised to `http://` / `https://`
  for the Twirp REST hop.

  ## Options

  - `:recv_timeout` — Tesla/Hackney receive timeout in milliseconds.
    Defaults to `#{@default_recv_timeout}`. Lower this when the call is
    blocking a latency-sensitive caller (e.g. a Phoenix channel join).
  - `:ttl` — JWT TTL in seconds. Defaults to `#{@default_ttl}`. Lower this
    for short-lived service tokens minted per-call.
  """
  def new(base_url, api_key, api_secret, opts \\ []) do
    base_url =
      base_url
      |> String.replace(~r{^ws://}, "http://")
      |> String.replace(~r{^wss://}, "https://")

    recv_timeout = Keyword.get(opts, :recv_timeout, @default_recv_timeout)
    ttl = Keyword.get(opts, :ttl, @default_ttl)

    middleware = [
      {Tesla.Middleware.BaseUrl, base_url},
      {Tesla.Middleware.Headers,
       [
         {"Content-Type", "application/protobuf"},
         {"Accept", "application/protobuf"}
       ]},
      {Tesla.Middleware.Logger,
       [
         debug: false,
         filter_headers: ["authorization"],
         formatter: fn env, _opts ->
           "#{env.method} #{env.url} -> #{env.status}"
         end
       ]}
    ]

    client = Tesla.client(middleware, {Tesla.Adapter.Hackney, [recv_timeout: recv_timeout]})

    %__MODULE__{
      base_url: base_url,
      api_key: api_key,
      api_secret: api_secret,
      client: client,
      ttl: ttl
    }
  end

  @doc """
  Explicitly dispatches a named agent to a room.

  Returns the resulting `Livekit.AgentDispatch` struct on success — `id` is
  the LiveKit-assigned dispatch identifier, needed for later `delete_dispatch/3`.
  """
  @spec create_dispatch(
          %__MODULE__{},
          agent_name :: String.t(),
          room :: String.t(),
          opts :: keyword()
        ) ::
          {:ok, AgentDispatch.t()}
          | {:error, {status :: pos_integer(), body :: binary()}}
          | {:error, term()}
  def create_dispatch(%__MODULE__{} = client, agent_name, room, opts \\ []) do
    path = "/twirp/livekit.AgentDispatchService/CreateDispatch"

    request =
      struct(CreateAgentDispatchRequest, %{
        agent_name: agent_name,
        room: room,
        metadata: Keyword.get(opts, :metadata, ""),
        restart_policy: Keyword.get(opts, :restart_policy, :JRP_ON_FAILURE),
        deployment: Keyword.get(opts, :deployment, "")
      })
      |> CreateAgentDispatchRequest.encode()

    headers = auth_header(client, %{room_admin: true, room: room})

    case Tesla.post(client.client, path, request, headers: headers) do
      {:ok, %{status: 200, body: body}} ->
        {:ok, AgentDispatch.decode(body)}

      {:ok, %{status: status, body: body}} ->
        Logger.error("AgentDispatch.CreateDispatch failed status=#{status} body=#{inspect(body)}")
        {:error, {status, body}}

      {:error, reason} ->
        Logger.error("AgentDispatch.CreateDispatch network error: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Deletes an existing agent dispatch by id.

  Treats 404 (dispatch already gone — room already ended) as success so the
  caller's stop_dispatch flow stays idempotent.
  """
  @spec delete_dispatch(
          %__MODULE__{},
          dispatch_id :: String.t(),
          room :: String.t()
        ) ::
          {:ok, AgentDispatch.t() | :already_gone}
          | {:error, {status :: pos_integer(), body :: binary()}}
          | {:error, term()}
  def delete_dispatch(%__MODULE__{} = client, dispatch_id, room) do
    path = "/twirp/livekit.AgentDispatchService/DeleteDispatch"

    request =
      struct(DeleteAgentDispatchRequest, %{dispatch_id: dispatch_id, room: room})
      |> DeleteAgentDispatchRequest.encode()

    headers = auth_header(client, %{room_admin: true, room: room})

    case Tesla.post(client.client, path, request, headers: headers) do
      {:ok, %{status: 200, body: body}} ->
        {:ok, AgentDispatch.decode(body)}

      {:ok, %{status: 404}} ->
        {:ok, :already_gone}

      {:ok, %{status: status, body: body}} ->
        Logger.error("AgentDispatch.DeleteDispatch failed status=#{status} body=#{inspect(body)}")
        {:error, {status, body}}

      {:error, reason} ->
        Logger.error("AgentDispatch.DeleteDispatch network error: #{inspect(reason)}")
        {:error, reason}
    end
  end

  # Private functions

  defp auth_header(client, video_grant) do
    token =
      AccessToken.new(client.api_key, client.api_secret)
      |> AccessToken.with_identity("service")
      |> AccessToken.with_ttl(client.ttl)
      |> AccessToken.add_grant(video_grant)
      |> AccessToken.to_jwt()

    [
      {"Authorization", "Bearer #{token}"},
      {"User-Agent", "Livekit Elixir SDK"}
    ]
  end
end
