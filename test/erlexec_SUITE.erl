-module(erlexec_SUITE).

-compile(export_all).

-include_lib("common_test/include/ct.hrl").
-include_lib("eunit/include/eunit.hrl").

%% all() -> [test_monitor, test_100_monitors, test_1000_monitors].
all() -> [test_wheel].

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


monit(Parent, Timeout) ->
    {ok, P, _} = exec:run("echo ok", [{stdout, null}, monitor]),
    ?receiveMatch({'DOWN', _, process, P, normal}, Timeout),
    Parent ! {monitor_down, 1}.

test_monitor(_Config) ->
    monit(self(), 2000),
    ?recv_n_msg({monitor_down, _}, 1, 2000).

test_100_monitors(_Config) ->
    Parent = self(),
    PIDs = [spawn(fun() -> monit(Parent, 2000) end) || _ <- lists:seq(0, 99)],
    ?recv_n_msg({monitor_down, _}, 100, 3000),
    lists:foreach(fun(P) -> ?assertEqual(is_process_alive(P), false) end, PIDs).

test_1000_monitors(Config) ->
    Parent = self(),
    PIDs = [spawn(fun() -> monit(Parent, 5000) end) || _ <- lists:seq(0, 999)],
    ?recv_n_msg({monitor_down, _}, 1000, 5000),
    lists:foreach(fun(P) -> ?assertEqual(is_process_alive(P), false) end, PIDs).


test_wheel(_Config) ->
    exec:start([root, {user, "root"}, {limit_users, "root"}]),
    exec:run("sleep 1000", [sync, stdout]).
