-module(erlexec_SUITE).

-compile(export_all).

-include_lib("common_test/include/ct.hrl").
-include_lib("eunit/include/eunit.hrl").

%%all() -> [test_monitor, test_100_monitors, test_1000_monitors].
all() -> [{group, exec}].

groups() -> [{exec, [sequence], [test_exec_list]},
             {monitor, [sequence, repeat_until_any_fail], [test_monitor_100_external_process]}].

-define(receiveMatch(A, Timeout),
    (fun() ->
        receive
            A -> true
        after Timeout ->
            ?assertMatch(A, timeout)
        end
    end)()).

-define(recv_n_msg(Msg, Count, Timeout),
        (fun _RecvLoop(0) -> ok;
             _RecvLoop(N) ->
                receive
                    Msg -> _RecvLoop(N-1);
                    _Other -> throw(unknown_msg)
                after Timeout ->
                        throw(receive_timeout)
                end
        end)(Count)).

init_per_suite(Config) ->
    %% ok = application:ensure_started(erlexec),
    Config.

end_per_suite(_Config) ->
    ok.

init_per_testcase(_Name, Config) ->
    Config.


test_exec_list(_Config) ->
    exec:start([{debug, 1}]),
    [exec:run("sleep 15", []) || _N <- lists:seq(0,99)],
    timer:sleep(5000),
    Childs = exec:which_children(),
    io:format(user, "exec-port Childs: ~p~n", [Childs]).

test_monitor(_Config) ->
    monit(self(), 2000),
    ?recv_n_msg({monitor_down, _}, 1, 2000).

test_100_monitors(_Config) ->
    Parent = self(),
    PIDs = [spawn(fun() -> monit(Parent, 2000) end) || _ <- lists:seq(0, 99)],
    ?recv_n_msg({monitor_down, _}, 100, 3000),
    lists:foreach(fun(P) -> ?assertEqual(is_process_alive(P), false) end, PIDs).

test_1000_monitors(_Config) ->
    Parent = self(),
    PIDs = [spawn(fun() -> monit(Parent, 5000) end) || _ <- lists:seq(0, 999)],
    ?recv_n_msg({monitor_down, _}, 1000, 5000),
    lists:foreach(fun(P) -> ?assertEqual(is_process_alive(P), false) end, PIDs).


test_wheel(_Config) ->
    exec:start([root, {user, "root"}, {limit_users, "root"}]),
    {ok, P, _} = exec:run("sleep 1000", [stdout]),
    timer:sleep(1000),
    ok = exec:kill(P, 1),
    timer:sleep(1000),
    ?assertEqual(is_process_alive(P), false).


test_monitor_100_external_process(_Config) ->
    ct:pal("test_monitor_100_external_process..."),
    exec:start([root, {user, "root"}, {limit_users, "root"}]),

    [spawn_sleep_cmd(N, 15) || N <- lists:seq(0,99)],
    timer:sleep(5000),
    io:format(user, "getting PIDs...~n", []),
    Pids = [read_pid_file(N) || N <- lists:seq(0,99)],
    io:format(user, "PIDs: ~p~n", [Pids]),
    lists:foreach(fun(OsPid) -> exec:manage(OsPid, [monitor]) end, Pids),
    ?recv_n_msg({'DOWN', _, _, _, _}, 100, 100000).


monit(Parent, Timeout) ->
    {ok, P, _} = exec:run("echo ok", [{stdout, null}, monitor]),
    ?receiveMatch({'DOWN', _, process, P, normal}, Timeout),
    Parent ! {monitor_down, 1}.


spawn_sleep_cmd(Id, SleepTimeout) ->
    spawn(fun() ->
                  Tmp = "/tmp/pid" ++ integer_to_list(Id),
                  Cmd = "echo $$ > " ++ Tmp ++ "; sleep " ++ integer_to_list(SleepTimeout),
                  os:cmd(Cmd)
          end).

read_pid_file(Id) ->
    Tmp = "/tmp/pid" ++ integer_to_list(Id),
    Pid = list_to_integer(lists:reverse(tl(lists:reverse(binary_to_list(element(2, file:read_file(Tmp))))))),
    file:delete(Tmp),
    Pid.


kill_os_cmd(OsPid) ->
    io:format(user, "Killing OsPid: ~p~n", [OsPid]),
    os:cmd("kill " ++ integer_to_list(OsPid)).
