%% Fair index static HTTP server (Erlang) — behaviourally identical to the Elixir twin.
%% Raw gen_tcp. Reads the full request, replies with Content-Length + Connection: close.
-module(fair_index_server).
-export([start_link/1, init_listen/1]).

-define(INDEX_PATH, "/var/www/html/index.html").
-define(RECV_TIMEOUT, 5000).
-define(BACKLOG, 1024).

start_link(Port) ->
    Pid = spawn_link(?MODULE, init_listen, [Port]),
    {ok, Pid}.

init_listen(Port) ->
    {ok, Body} = file:read_file(?INDEX_PATH),
    {ok, Listen} = gen_tcp:listen(Port,
        [binary, {packet, raw}, {active, false}, {reuseaddr, true},
         {backlog, ?BACKLOG}, {nodelay, true}]),
    accept_loop(Listen, Body).

accept_loop(Listen, Body) ->
    case gen_tcp:accept(Listen) of
        {ok, Sock} ->
            spawn(fun() -> handle(Sock, Body) end),
            accept_loop(Listen, Body);
        {error, _Reason} ->
            timer:sleep(100),
            accept_loop(Listen, Body)
    end.

handle(Sock, Body) ->
    Method = read_request(Sock, <<>>),
    gen_tcp:send(Sock, response(Method, Body)),
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

response(<<"POST">>, _Body) ->
    <<"HTTP/1.1 204 No Content\r\nContent-Length: 0\r\nConnection: close\r\n\r\n">>;
response(_Method, Body) ->
    CL = integer_to_binary(byte_size(Body)),
    Header = <<"HTTP/1.1 200 OK\r\n",
               "Content-Type: text/html; charset=utf-8\r\n",
               "Content-Length: ", CL/binary, "\r\n",
               "Connection: close\r\n\r\n">>,
    <<Header/binary, Body/binary>>.
