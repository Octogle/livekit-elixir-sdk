defmodule Livekit.AgentDispatchServiceClientTest do
  use ExUnit.Case

  alias Livekit.AgentDispatchServiceClient

  @api_key "api_key_123"
  @api_secret "secret_456"

  setup do
    bypass = Bypass.open()
    base_url = "http://localhost:#{bypass.port}"
    client = AgentDispatchServiceClient.new(base_url, @api_key, @api_secret)
    {:ok, bypass: bypass, client: client}
  end

  describe "new/4" do
    test "creates a client with default opts" do
      client = AgentDispatchServiceClient.new("http://example.com", @api_key, @api_secret)
      assert client.base_url == "http://example.com"
      assert client.api_key == @api_key
      assert client.api_secret == @api_secret
      # Default TTL is 600s.
      assert client.ttl == 600
    end

    test "accepts :ttl override" do
      client =
        AgentDispatchServiceClient.new("http://example.com", @api_key, @api_secret, ttl: 60)

      assert client.ttl == 60
    end

    test "converts ws:// to http:// and wss:// to https://" do
      ws = AgentDispatchServiceClient.new("ws://example.com", @api_key, @api_secret)
      wss = AgentDispatchServiceClient.new("wss://example.com", @api_key, @api_secret)
      assert ws.base_url == "http://example.com"
      assert wss.base_url == "https://example.com"
    end
  end

  describe "create_dispatch/4" do
    test "sends a protobuf body with Content-Type: application/protobuf", %{
      bypass: bypass,
      client: client
    } do
      response =
        %Livekit.AgentDispatch{
          id: "AD_test_id",
          agent_name: "my_agent",
          room: "room_42",
          metadata: "{}"
        }

      Bypass.expect_once(
        bypass,
        "POST",
        "/twirp/livekit.AgentDispatchService/CreateDispatch",
        fn conn ->
          assert content_type(conn) == "application/protobuf"
          assert {"accept", "application/protobuf"} in conn.req_headers
          assert authorization_present?(conn)

          {:ok, body, conn} = Plug.Conn.read_body(conn)
          request = Livekit.CreateAgentDispatchRequest.decode(body)
          assert request.agent_name == "my_agent"
          assert request.room == "room_42"
          assert request.metadata == ~s({"transcript_id":"t-1"})

          conn
          |> Plug.Conn.put_resp_content_type("application/protobuf")
          |> Plug.Conn.resp(200, Livekit.AgentDispatch.encode(response))
        end
      )

      assert {:ok, dispatch} =
               AgentDispatchServiceClient.create_dispatch(
                 client,
                 "my_agent",
                 "room_42",
                 metadata: ~s({"transcript_id":"t-1"})
               )

      assert dispatch.id == "AD_test_id"
      assert dispatch.agent_name == "my_agent"
      assert dispatch.room == "room_42"
    end

    test "surfaces non-200 as {:error, {status, body}}", %{bypass: bypass, client: client} do
      Bypass.expect_once(
        bypass,
        "POST",
        "/twirp/livekit.AgentDispatchService/CreateDispatch",
        fn conn ->
          Plug.Conn.resp(conn, 401, ~s({"code":"unauthenticated","msg":"permissions denied"}))
        end
      )

      assert {:error, {401, body}} =
               AgentDispatchServiceClient.create_dispatch(client, "my_agent", "room_42")

      assert body =~ "unauthenticated"
    end
  end

  describe "delete_dispatch/3" do
    test "treats 404 as {:ok, :already_gone} (idempotent delete)", %{
      bypass: bypass,
      client: client
    } do
      Bypass.expect_once(
        bypass,
        "POST",
        "/twirp/livekit.AgentDispatchService/DeleteDispatch",
        fn conn ->
          Plug.Conn.resp(conn, 404, "")
        end
      )

      assert {:ok, :already_gone} =
               AgentDispatchServiceClient.delete_dispatch(client, "AD_gone", "room_42")
    end

    test "200 returns the decoded AgentDispatch", %{bypass: bypass, client: client} do
      response = %Livekit.AgentDispatch{id: "AD_ok", agent_name: "my_agent", room: "room_42"}

      Bypass.expect_once(
        bypass,
        "POST",
        "/twirp/livekit.AgentDispatchService/DeleteDispatch",
        fn conn ->
          {:ok, body, conn} = Plug.Conn.read_body(conn)
          request = Livekit.DeleteAgentDispatchRequest.decode(body)
          assert request.dispatch_id == "AD_ok"
          assert request.room == "room_42"

          conn
          |> Plug.Conn.put_resp_content_type("application/protobuf")
          |> Plug.Conn.resp(200, Livekit.AgentDispatch.encode(response))
        end
      )

      assert {:ok, dispatch} =
               AgentDispatchServiceClient.delete_dispatch(client, "AD_ok", "room_42")

      assert dispatch.id == "AD_ok"
    end
  end

  defp content_type(conn) do
    conn.req_headers
    |> List.keyfind("content-type", 0)
    |> case do
      {_, value} -> value |> String.split(";") |> hd() |> String.trim()
      _ -> nil
    end
  end

  defp authorization_present?(conn) do
    case List.keyfind(conn.req_headers, "authorization", 0) do
      {_, "Bearer " <> jwt} -> String.length(jwt) > 20
      _ -> false
    end
  end
end
