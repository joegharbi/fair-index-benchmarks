%% Fair dynamic HTTP server (Erlang) — behaviourally identical to the Elixir twin.
%% Same as the index server EXCEPT the body is GENERATED at request time
%% (current epoch milliseconds), not read from a cached file.
-module(fair_index_server).
-export([start_link/1, init_listen/1]).

-define(RECV_TIMEOUT, 5000).
-define(BACKLOG, 1024).

start_link(Port) ->
    Pid = spawn_link(?MODULE, init_listen, [Port]),
    {ok, Pid}.

init_listen(Port) ->
    {ok, Listen} = gen_tcp:listen(Port,
        [binary, {packet, raw}, {active, false}, {reuseaddr, true},
         {backlog, ?BACKLOG}, {nodelay, true}]),
    accept_loop(Listen).

accept_loop(Listen) ->
    case gen_tcp:accept(Listen) of
        {ok, Sock} ->
            spawn(fun() -> handle(Sock) end),
            accept_loop(Listen);
        {error, _Reason} ->
            timer:sleep(100),
            accept_loop(Listen)
    end.

handle(Sock) ->
    Method = read_request(Sock, <<>>),
    gen_tcp:send(Sock, response(Method)),
    gen_tcp:close(Sock).

read_request(Sock, Acc) ->
    case gen_tcp:recv(Sock, 0, ?RECV_TIMEOUT) of
        {ok, Data} ->
            Acc2 = <<Acc/binary, Data/binary>>,
            case binary:match(Acc2, <<"\r\n\r\n">>) of
                nomatch -> read_request(Sock, Acc2);
                _ -> method_of(Acc2)
            end;
        {error, _} ->
            method_of(Acc)
    end.

method_of(Bin) ->
    case binary:split(Bin, <<" ">>) of
        [M | _] -> M;
        _ -> <<"GET">>
    end.

%% Dynamic: response body generated per request (current machine time, ms).
body() ->
    T = integer_to_binary(os:system_time(millisecond)),
    <<"<!DOCTYPE html><html><body><p>Current time (ms): ", T/binary, "</p></body></html>">>.

response(<<"POST">>) ->
    <<"HTTP/1.1 204 No Content\r\nContent-Length: 0\r\nConnection: close\r\n\r\n">>;
response(_Method) ->
    Body = body(),
    CL = integer_to_binary(byte_size(Body)),
    Header = <<"HTTP/1.1 200 OK\r\n",
               "Content-Type: text/html; charset=utf-8\r\n",
               "Content-Length: ", CL/binary, "\r\n",
               "Connection: close\r\n\r\n">>,
    <<Header/binary, Body/binary>>.
