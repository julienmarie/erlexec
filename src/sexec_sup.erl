%%% SEXEC Supervisor
-module(sexec_sup).

%% API
-export([start_link/1]).

%% Supervisor callbacks
-export([init/1]).

%% API functions
-export([start_sexec/3, stop_sexec/2]).

-define(via_gproc(Name), {via, gproc, {n, l, Name}}).
-define(gproc_get_pid(Name), gproc:whereis_name({n, l, Name})).

%%====================================================================
%% API functions
%%====================================================================

start_link(Name) ->
    supervisor:start_link(?via_gproc({sexec_sup, Name}), ?MODULE, []).

%%====================================================================
%% Supervisor callbacks
%%====================================================================

init(_Args) ->
    sexec:debug("Self: ~p", [self()]),
    {ok, { {simple_one_for_one, 1, 60},
    [
        {
            sexec,
            {sexec, start_link, []},
            temporary,
            16000,  %% TODO JP. TWEAK THIS TIMEOUT!?! SEXEC DO TAKE A WHILE TO SHUTDOWN ERLEXEC/PORT...
            worker,
            [sexec]
        }
    ]} }.

%%====================================================================
%% API functions
%%====================================================================

start_sexec(Sup, Name, Opts) ->
    sexec:debug("Sup: ~p Name: ~p Opts: ~p", [Sup, Name, Opts]),
    supervisor:start_child(?gproc_get_pid({sexec_sup, Sup}), [Name, Opts]).

stop_sexec(Sup, Name) ->
    sexec:debug("Sup: ~p Name: ~p", [Sup, Name]),
    supervisor:terminate_child(?gproc_get_pid({sexec_sup, Sup}), ?gproc_get_pid({sexec, Name})).
