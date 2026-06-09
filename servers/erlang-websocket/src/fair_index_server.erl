%% Fair WebSocket echo server (Erlang) — raw gen_tcp, RFC 6455 handshake + framing.
%% Behaviourally identical to the Elixir twin: echoes data frames, replies to close.
-module(fair_index_server).
-export([start_link/1, init_listen/1]).

-define(BACKLOG, 1024).
-define(MAGIC, <<"258EAFA5-E914-47DA-95CA-C5AB0DC85B11">>).
-define(TIMEOUT, 60000).

start_link(Port) ->
    {ok, spawn_link(?MODULE, init_listen, [Port])}.

init_listen(Port) ->
    {ok, L} = gen_tcp:listen(Port, [binary, {packet, raw}, {active, false},
                                    {reuseaddr, true}, {backlog, ?BACKLOG}, {nodelay, true}]),
    accept_loop(L).

accept_loop(L) ->
    case gen_tcp:accept(L) of
        {ok, S} -> spawn(fun() -> handshake(S) end), accept_loop(L);
        {error, _} -> timer:sleep(100), accept_loop(L)
    end.

handshake(S) ->
    case read_headers(S, <<>>) of
        {ok, Req} ->
            case sec_key(binary:split(Req, <<"\r\n">>, [global])) of
                {ok, Key} ->
                    Accept = base64:encode(crypto:hash(sha, <<Key/binary, ?MAGIC/binary>>)),
                    gen_tcp:send(S, [<<"HTTP/1.1 101 Switching Protocols\r\n">>,
                                     <<"Upgrade: websocket\r\n">>,
                                     <<"Connection: Upgrade\r\n">>,
                                     <<"Sec-WebSocket-Accept: ">>, Accept, <<"\r\n\r\n">>]),
                    loop(S);
                error -> gen_tcp:close(S)
            end;
        _ -> gen_tcp:close(S)
    end.

read_headers(S, Acc) ->
    case gen_tcp:recv(S, 0, ?TIMEOUT) of
        {ok, D} ->
            A2 = <<Acc/binary, D/binary>>,
            case binary:match(A2, <<"\r\n\r\n">>) of
                nomatch -> read_headers(S, A2);
                _ -> {ok, A2}
            end;
        E -> E
    end.

sec_key([]) -> error;
sec_key([Line | T]) ->
    case binary:split(Line, <<":">>) of
        [H, V] ->
            case string:lowercase(H) of
                <<"sec-websocket-key">> -> {ok, list_to_binary(string:trim(binary_to_list(V)))};
                _ -> sec_key(T)
            end;
        _ -> sec_key(T)
    end.

loop(S) ->
    case recv_frame(S) of
        {data, Op, P} -> gen_tcp:send(S, frame(Op, P)), loop(S);
        close -> gen_tcp:send(S, frame(8, <<>>)), gen_tcp:close(S);
        ignore -> loop(S);
        error -> gen_tcp:close(S)
    end.

recv_frame(S) ->
    case gen_tcp:recv(S, 2, ?TIMEOUT) of
        {ok, <<_Fin:1, _Rsv:3, Op:4, Mask:1, L0:7>>} ->
            case payload_len(S, L0) of
                {ok, Len} ->
                    case masked_payload(S, Mask, Len) of
                        {ok, P} -> classify(Op, P);
                        _ -> error
                    end;
                _ -> error
            end;
        _ -> error
    end.

payload_len(_S, L) when L =< 125 -> {ok, L};
payload_len(S, 126) ->
    case gen_tcp:recv(S, 2, ?TIMEOUT) of {ok, <<L:16>>} -> {ok, L}; _ -> error end;
payload_len(S, 127) ->
    case gen_tcp:recv(S, 8, ?TIMEOUT) of {ok, <<L:64>>} -> {ok, L}; _ -> error end.

masked_payload(_S, 0, 0) -> {ok, <<>>};
masked_payload(S, 0, Len) ->
    case gen_tcp:recv(S, Len, ?TIMEOUT) of {ok, P} -> {ok, P}; _ -> error end;
masked_payload(S, 1, Len) ->
    case gen_tcp:recv(S, 4, ?TIMEOUT) of
        {ok, Key} ->
            case Len of
                0 -> {ok, <<>>};
                _ -> case gen_tcp:recv(S, Len, ?TIMEOUT) of
                         {ok, M} -> {ok, unmask(M, Key)};
                         _ -> error
                     end
            end;
        _ -> error
    end.

unmask(Bin, Key) -> crypto:exor(Bin, tile(Key, byte_size(Bin))).

tile(_Key, 0) -> <<>>;
tile(Key, N) ->
    K = byte_size(Key),
    Full = binary:copy(Key, N div K),
    Rem = binary:part(Key, 0, N rem K),
    <<Full/binary, Rem/binary>>.

classify(8, _) -> close;
classify(Op, P) when Op =:= 1; Op =:= 2 -> {data, Op, P};
classify(_, _) -> ignore.

frame(Op, P) ->
    Len = byte_size(P),
    H = if
        Len =< 125 -> <<1:1, 0:3, Op:4, 0:1, Len:7>>;
        Len =< 65535 -> <<1:1, 0:3, Op:4, 0:1, 126:7, Len:16>>;
        true -> <<1:1, 0:3, Op:4, 0:1, 127:7, Len:64>>
    end,
    <<H/binary, P/binary>>.
