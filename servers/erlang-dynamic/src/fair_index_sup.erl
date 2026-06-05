-module(fair_index_sup).
-behaviour(supervisor).
-export([start_link/0, init/1]).

start_link() ->
    supervisor:start_link({local, ?MODULE}, ?MODULE, []).

init([]) ->
    Port = 80,
    Child = #{id => fair_index_server,
              start => {fair_index_server, start_link, [Port]},
              restart => permanent,
              shutdown => 5000,
              type => worker,
              modules => [fair_index_server]},
    {ok, {{one_for_one, 10, 10}, [Child]}}.
