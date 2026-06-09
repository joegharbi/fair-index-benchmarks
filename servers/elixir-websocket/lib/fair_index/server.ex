defmodule FairIndex.Server do
  @moduledoc """
  Fair WebSocket echo server (Elixir) — raw :gen_tcp, RFC 6455 handshake + framing.
  Behaviourally identical to the Erlang twin: echoes data frames, replies to close.
  """
  @backlog 1024
  @magic "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"
  @timeout 60_000

  def child_spec(port),
    do: %{id: __MODULE__, start: {__MODULE__, :start_link, [port]}, type: :worker, restart: :permanent}

  def start_link(port), do: {:ok, spawn_link(fn -> init_listen(port) end)}

  defp init_listen(port) do
    {:ok, l} =
      :gen_tcp.listen(port,
        [:binary, packet: :raw, active: false, reuseaddr: true, backlog: @backlog, nodelay: true]
      )

    accept_loop(l)
  end

  defp accept_loop(l) do
    case :gen_tcp.accept(l) do
      {:ok, s} -> spawn(fn -> handshake(s) end); accept_loop(l)
      {:error, _} -> :timer.sleep(100); accept_loop(l)
    end
  end

  defp handshake(s) do
    case read_headers(s, <<>>) do
      {:ok, req} ->
        case sec_key(:binary.split(req, "\r\n", [:global])) do
          {:ok, key} ->
            accept = Base.encode64(:crypto.hash(:sha, key <> @magic))

            :gen_tcp.send(
              s,
              "HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Accept: " <>
                accept <> "\r\n\r\n"
            )

            loop(s)

          :error ->
            :gen_tcp.close(s)
        end

      _ ->
        :gen_tcp.close(s)
    end
  end

  defp read_headers(s, acc) do
    case :gen_tcp.recv(s, 0, @timeout) do
      {:ok, d} ->
        a2 = acc <> d
        if :binary.match(a2, "\r\n\r\n") == :nomatch, do: read_headers(s, a2), else: {:ok, a2}

      e ->
        e
    end
  end

  defp sec_key([]), do: :error

  defp sec_key([line | t]) do
    case :binary.split(line, ":") do
      [h, v] ->
        if String.downcase(h) == "sec-websocket-key", do: {:ok, String.trim(v)}, else: sec_key(t)

      _ ->
        sec_key(t)
    end
  end

  defp loop(s) do
    case recv_frame(s) do
      {:data, op, p} -> :gen_tcp.send(s, frame(op, p)); loop(s)
      :close -> :gen_tcp.send(s, frame(8, <<>>)); :gen_tcp.close(s)
      :ignore -> loop(s)
      :error -> :gen_tcp.close(s)
    end
  end

  defp recv_frame(s) do
    case :gen_tcp.recv(s, 2, @timeout) do
      {:ok, <<_fin::1, _rsv::3, op::4, mask::1, l0::7>>} ->
        with {:ok, len} <- payload_len(s, l0),
             {:ok, p} <- masked_payload(s, mask, len) do
          classify(op, p)
        else
          _ -> :error
        end

      _ ->
        :error
    end
  end

  defp payload_len(_s, l) when l <= 125, do: {:ok, l}

  defp payload_len(s, 126) do
    case :gen_tcp.recv(s, 2, @timeout) do
      {:ok, <<l::16>>} -> {:ok, l}
      _ -> :error
    end
  end

  defp payload_len(s, 127) do
    case :gen_tcp.recv(s, 8, @timeout) do
      {:ok, <<l::64>>} -> {:ok, l}
      _ -> :error
    end
  end

  defp masked_payload(_s, 0, 0), do: {:ok, <<>>}

  defp masked_payload(s, 0, len) do
    case :gen_tcp.recv(s, len, @timeout) do
      {:ok, p} -> {:ok, p}
      _ -> :error
    end
  end

  defp masked_payload(s, 1, len) do
    case :gen_tcp.recv(s, 4, @timeout) do
      {:ok, key} ->
        if len == 0 do
          {:ok, <<>>}
        else
          case :gen_tcp.recv(s, len, @timeout) do
            {:ok, m} -> {:ok, unmask(m, key)}
            _ -> :error
          end
        end

      _ ->
        :error
    end
  end

  defp unmask(bin, key), do: :crypto.exor(bin, tile(key, byte_size(bin)))

  defp tile(_key, 0), do: <<>>

  defp tile(key, n) do
    k = byte_size(key)
    :binary.copy(key, div(n, k)) <> :binary.part(key, 0, rem(n, k))
  end

  defp classify(8, _), do: :close
  defp classify(op, p) when op == 1 or op == 2, do: {:data, op, p}
  defp classify(_, _), do: :ignore

  defp frame(op, p) do
    len = byte_size(p)

    h =
      cond do
        len <= 125 -> <<1::1, 0::3, op::4, 0::1, len::7>>
        len <= 65_535 -> <<1::1, 0::3, op::4, 0::1, 126::7, len::16>>
        true -> <<1::1, 0::3, op::4, 0::1, 127::7, len::64>>
      end

    h <> p
  end
end
