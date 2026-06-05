defmodule FairIndex.Server do
  @moduledoc """
  Fair dynamic HTTP server (Elixir) — behaviourally identical to the Erlang twin.
  Same as the index server EXCEPT the body is GENERATED at request time
  (current epoch milliseconds), not read from a cached file.
  """

  @recv_timeout 5000
  @backlog 1024

  def child_spec(port) do
    %{id: __MODULE__, start: {__MODULE__, :start_link, [port]}, type: :worker, restart: :permanent}
  end

  def start_link(port) do
    {:ok, spawn_link(fn -> init_listen(port) end)}
  end

  defp init_listen(port) do
    {:ok, listen} =
      :gen_tcp.listen(port,
        [:binary, packet: :raw, active: false, reuseaddr: true, backlog: @backlog, nodelay: true]
      )

    accept_loop(listen)
  end

  defp accept_loop(listen) do
    case :gen_tcp.accept(listen) do
      {:ok, sock} ->
        spawn(fn -> handle(sock) end)
        accept_loop(listen)

      {:error, _reason} ->
        :timer.sleep(100)
        accept_loop(listen)
    end
  end

  defp handle(sock) do
    method = read_request(sock, <<>>)
    :gen_tcp.send(sock, response(method))
    :gen_tcp.close(sock)
  end

  defp read_request(sock, acc) do
    case :gen_tcp.recv(sock, 0, @recv_timeout) do
      {:ok, data} ->
        acc2 = acc <> data

        if :binary.match(acc2, "\r\n\r\n") == :nomatch do
          read_request(sock, acc2)
        else
          method_of(acc2)
        end

      {:error, _} ->
        method_of(acc)
    end
  end

  defp method_of(bin) do
    case :binary.split(bin, " ") do
      [m | _] -> m
      _ -> "GET"
    end
  end

  # Dynamic: response body generated per request (current machine time, ms).
  defp body do
    t = Integer.to_string(System.os_time(:millisecond))
    "<!DOCTYPE html><html><body><p>Current time (ms): " <> t <> "</p></body></html>"
  end

  defp response("POST"), do: "HTTP/1.1 204 No Content\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"

  defp response(_method) do
    b = body()
    cl = Integer.to_string(byte_size(b))

    "HTTP/1.1 200 OK\r\n" <>
      "Content-Type: text/html; charset=utf-8\r\n" <>
      "Content-Length: " <> cl <> "\r\n" <>
      "Connection: close\r\n\r\n" <> b
  end
end
