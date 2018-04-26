%%% SEXEC: Screw's erlexec/gproc wrapper
-module(sexec).

-behaviour(gen_server).

%% sexec API
-export([sproc/1, sproc/2,
         start/2, start_link/2, run/3, run_link/3, manage/3, unmanage/3,
         send/3, winsz/4, which_children/1, kill/3, setpgid/3,
         stop/2, stop_and_wait/3, ospid/2, pid/2, status/1, signal/1, debug_exec/2]).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
         code_change/3, terminate/2]).

-define(via_gproc(Name), {via, gproc, {n, l, Name}}).
-define(via_gproc_sexec(Name), {via, gproc, {n, l, {sexec, Name}}}).
-define(via_gproc_erlexec(Name), {via, gproc, {n, l, {erlexec, Name}}}).
-define(gproc_get_sexec_pid(Name), gproc:whereis_name({n, l, {sexec, Name}})).

-record(state, {name, opts, pids}).

-type sproc() :: term().

%%%%%%%%%%%
%%% API %%%
%%%%%%%%%%%
-spec sproc(sproc()) -> pid().
sproc(Name) ->
    sproc(Name, []).

-spec sproc(sproc(), list()) -> pid().
sproc(Name, Opts) ->
    Pid = ?gproc_get_sexec_pid(Name),
    case Pid of
        undefined -> {ok, NewPid} = start(Name, Opts),
                     NewPid;
        _Else -> %% TODO JP. Check Opts match existing sexec's erlexec gen_server?!?
            Pid
    end.

-spec start_link(sproc(), erlexec:exec_options()) -> {ok, pid()} | {error, any()}.
start_link(Name, Opts) when is_list(Opts) ->
    gen_server:start_link(?via_gproc({sexec, Name}), ?MODULE, {Name, Opts}, []).

-spec start(sproc(), erlexec:exec_options()) -> {ok, pid()} | {error, any()}.
start(Name, Opts) when is_list(Opts) ->
    gen_server:start(?via_gproc({sexec, Name}), ?MODULE, {Name, Opts}, []).

-spec run(sproc(), erlexec:cmd(), erlexec:cmd_options()) ->
    {ok, pid(), erlexec:ospid()} | {ok, [{stdout | stderr, [binary()]}]} | {error, any()}.
run(Name, Exe, Opts) when is_list(Exe), is_list(Opts) ->
    do_run(Name, {run, Exe, Opts}, Opts).

-spec run_link(sproc(), erlexec:cmd(), erlexec:cmd_options()) ->
    {ok, pid(), erlexec:ospid()} | {ok, [{stdout | stderr, [binary()]}]} | {error, any()}.
run_link(Name, Exe, Opts) when is_list(Exe), is_list(Opts) ->
    do_run(Name, {run, Exe, Opts}, [link | Opts]).

-spec manage(sproc(), erlexec:ospid() | erlexec:port(), erlexec:cmd_options()) ->
    {ok, pid(), erlexec:ospid()} | {error, any()}.
manage(Name, OsPid, Opts) when is_integer(OsPid) ->
    do_run(Name, {manage, OsPid, Opts}, Opts);
manage(Name, Port, Opts) when is_port(Port) ->
    {os_pid, OsPid} = erlang:port_info(Port, os_pid),
    manage(Name, OsPid, Opts).

-spec unmanage(sproc(), erlexec:ospid() | erlexec:port(), erlexec:cmd_options()) -> ok | {error, any()}.
unmanage(Name, OsPid, Opts) when is_integer(OsPid) ->
    do_run(Name, {unmanage, OsPid}, Opts);
unmanage(Name, Port, Opts) when is_port(Port) ->
    {os_pid, OsPid} = erlang:port_info(Port, os_pid),
    unmanage(Name, OsPid, Opts).


-spec which_children(sproc()) -> [erlexec:ospid(), ...].
which_children(Name) ->
    gen_server:call(?via_gproc_sexec(Name), {port, {list}}).

-spec kill(sproc(), pid() | erlexec:ospid(), integer()) -> ok | {error, any()}.
kill(Name, Pid, Signal) when is_pid(Pid); is_integer(Pid) ->
    gen_server:call(?via_gproc_sexec(Name), {port, {kill, Pid, Signal}});
kill(Name, Port, Signal) when is_port(Port) ->
    {os_pid, Pid} = erlang:port_info(Port, os_pid),
    kill(Name, Pid, Signal).

-spec setpgid(sproc(), erlexec:ospid(), erlexec:osgid()) -> ok | {error, any()}.
setpgid(Name, OsPid, Gid) when is_integer(OsPid), is_integer(Gid) ->
    gen_server:call(?via_gproc_sexec(Name), {port, {setpgid, OsPid, Gid}}).

-spec stop(sproc(), pid() | erlexec:ospid() | port()) -> ok | {error, any()}.
stop(Name, Pid) when is_pid(Pid); is_integer(Pid) ->
    gen_server:call(?via_gproc_sexec(Name), {port, {stop, Pid}}, 30000);
stop(Name, Port) when is_port(Port) ->
    {os_pid, Pid} = erlang:port_info(Port, os_pid),
    stop(Name, Pid).

-spec stop_and_wait(sproc(), pid() | erlexec:ospid() | port(), integer()) -> term() | {error, any()}.
stop_and_wait(Name, OsPid, Timeout) when is_integer(OsPid) ->
    Pid = gen_server:call(?via_gproc_erlexec(Name), {pid, OsPid}),
    case Pid of
        undefined -> {error, not_found};
        Pid -> stop_and_wait(Name, Pid, Timeout)
    end;
stop_and_wait(Name, Pid, Timeout) when is_pid(Pid) ->
    gen_server:call(?via_gproc_sexec(Name), {port, {stop, Pid}}, Timeout),
    receive
    {'DOWN', _Ref, process, Pid, ExitStatus} -> ExitStatus
    after Timeout                            -> {error, timeout}
    end;
stop_and_wait(Name, Port, Timeout) when is_port(Port) ->
    {os_pid, OsPid} = erlang:port_info(Port, os_pid),
    stop_and_wait(Name, OsPid, Timeout).

-spec ospid(sproc(), pid()) -> erlexec:ospid() | {error, Reason::any()}.
ospid(Name, Pid) when is_pid(Pid) ->
    Ref = make_ref(),
    ?gproc_get_sexec_pid(Name) ! {{self(), Ref}, ospid},
    receive
    {Ref, Reply} -> Reply;
    Other        -> Other
    after 5000   -> {error, timeout}
    end.

-spec pid(sproc(), OsPid::erlexec:ospid()) -> pid() | undefined | {error, timeout}.
pid(Name, OsPid) when is_integer(OsPid) ->
    gen_server:call(?via_gproc_erlexec(Name), {pid, OsPid}).

-spec send(sproc(), OsPid::erlexec:ospid() | pid(), binary() | 'eof') -> ok.
send(Name, OsPid, Data)
  when (is_integer(OsPid) orelse is_pid(OsPid)),
       (is_binary(Data)   orelse Data =:= eof) ->
    gen_server:call(?via_gproc_sexec(Name), {port, {send, OsPid, Data}}).

-spec winsz(sproc(), OsPid::erlexec:ospid() | pid(), integer(), integer()) -> ok.
winsz(Name, OsPid, Rows, Cols)
  when (is_integer(OsPid) orelse is_pid(OsPid)),
       is_integer(Rows),
       is_integer(Cols) ->
    gen_server:call(?via_gproc_sexec(Name), {port, {winsz, OsPid, Rows, Cols}}).

-spec debug_exec(sproc(), Level::integer()) -> {ok, OldLevel::integer()} | {error, timeout}.
debug_exec(Name, Level) when is_integer(Level), Level >= 0, Level =< 10 ->
    gen_server:call(?via_gproc_sexec(Name), {port, {debug, Level}}).

-spec status(integer()) ->
        {status, ExitStatus :: integer()} |
        {signal, Singnal :: integer() | atom(), Core :: boolean()}.
status(Status) when is_integer(Status) ->
    erlexec:status(Status).

-spec signal(integer()) -> atom() | integer().
signal(S) ->
    erlexec:signal(S).


%%%----------------------------------------------------------------------
%%% Callback functions from gen_server
%%%----------------------------------------------------------------------
init({Name, Opts}) ->
    sexec:debug("Self: ~p Name: ~p Opts: ~p", [self(), Name, Opts]),
    process_flag(trap_exit, true),
    {ok, _Pid} = gen_server:start_link(?via_gproc({erlexec, Name}), exec, [Opts], []),
    %% TODO JP. self() ! init + pids=[] ???
    {ok, #state{name=Name, opts=Opts, pids=[]}}.

handle_call({port, Instruction}, _From, #state{name=Name, pids=Pids} = State) ->
    sexec:debug("{port, ~p} Name: ~p", [Instruction, Name]),
    case gen_server:call(?via_gproc_erlexec(Name), {port, Instruction}, 30000) of
        {ok, Pid, OsPid, _Sync = true} ->
            Reply = wait_for_ospid_exit(OsPid, Pid, [], []),
            sexec:debug("Reply: ~p", [Reply]),
            {reply, Reply, State};
        {ok, Pid, OsPid, _} ->
            sexec:debug("Pid: ~p OsPid: ~p", [Pid, OsPid]),
            {reply, {ok, Pid, OsPid}, State#state{pids=[Pid]++Pids}};
        {error, not_found} ->
            {reply, {error, not_found}, State};
        ok ->
            {reply, ok, State}
    end;

handle_call(Request, _From, State) ->
    sexec:warning("NOT_IMPLEMENTED Request: ~p", [Request]),
    {reply, {not_implemented, Request}, State}.

handle_cast(Msg, State) ->
    sexec:debug("unknown MSG: ~p", [Msg]),
    {noreply, State}.

handle_info({'DOWN', OsPid, process, Pid, Res}, #state{name=Name, pids=Pids} = State) ->
    case lists:member(Pid, Pids) of
        false -> sexec:debug("{'DOWN'} ~p, process, ~p, ~p} UNKNOWN PID! IGNORE.", [OsPid, Pid, Res]),
                 {noreply, State};
        true  -> sexec:debug("{'DOWN', ~p, process, ~p, ~p}", [OsPid, Pid, Res]),
                 %% TODO JP. CHECK RES FOR info vs warn msg and do something else before stopping ourself???
                 sexec:warning("Name: ~p got 'DOWN' for monitor PID: ~p OsPid: ~p! Stopping sexec process...",
                               [Name, Pid, OsPid]),
                 {stop, {'DOWN', OsPid, process, self(), Res}, State}
    end;
handle_info(Msg, State) ->
    sexec:debug("unknown MSG: ~p", [Msg]),
    {noreply, State}.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

terminate(Reason, #state{name=Name} = State) ->
    sexec:debug("Reason: ~p State: ~p", [Reason, State]),
    gen_server:stop(?via_gproc_erlexec(Name)).


%%%---------------------------------------------------------------------
%%% Internal functions
%%%---------------------------------------------------------------------

-spec do_run(Name::sproc(), Cmd::any(), Opts::erlexec:cmd_options()) ->
    {ok, pid(), erlexec:ospid()} | {ok, [{stdout | stderr, [binary()]}]} | {error, any()}.
do_run(Name, Cmd, Opts) ->
    sexec:debug("Name: ~p Cmd: ~p Opts: ~p", [Name, Cmd, Opts]),
    Link = case {proplists:get_bool(link,    Opts),
                 proplists:get_bool(monitor, Opts)} of
           {true, _} -> link;
           {_, true} -> monitor;
           _         -> undefined
           end,
    Sync = proplists:get_value(sync, Opts, false),
    Cmd2 = {port, {Cmd, Link, Sync}},
    gen_server:call(?via_gproc_sexec(Name), Cmd2, 30000).

wait_for_ospid_exit(OsPid, Pid, OutAcc, ErrAcc) ->
    %% Note when a monitored process exits
    receive
        {stdout, OsPid, Data} ->
            wait_for_ospid_exit(OsPid, Pid, [Data | OutAcc], ErrAcc);
        {stderr, OsPid, Data} ->
            wait_for_ospid_exit(OsPid, Pid, OutAcc, [Data | ErrAcc]);
        {'DOWN', OsPid, process, Pid, normal} ->
            {ok, sync_res(OutAcc, ErrAcc)};
        {'DOWN', OsPid, process, Pid, noproc} ->
            {ok, sync_res(OutAcc, ErrAcc)};
        {'DOWN', OsPid, process, Pid, {exit_status,_}=R} ->
            {error, [R | sync_res(OutAcc, ErrAcc)]}
    end.

sync_res([], []) -> [];
sync_res([], L)  -> [{stderr, lists:reverse(L)}];
sync_res(LO, LE) -> [{stdout, lists:reverse(LO)} | sync_res([], LE)].
