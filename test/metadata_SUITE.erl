-module(metadata_SUITE).

-export([
         %% suite/0,
         init_per_suite/1,
         end_per_suite/1,
         init_per_testcase/2,
         end_per_testcase/2,
         all/0
        ]).

-export([
    read_write_delete_test/1,
    partitioned_cluster_test/1
        ]).

-include_lib("common_test/include/ct.hrl").
-include_lib("eunit/include/eunit.hrl").
-include_lib("kernel/include/inet.hrl").


%% ===================================================================
%% common_test callbacks
%% ===================================================================

init_per_suite(_Config) ->
    lager:start(),
    %% this might help, might not...
    os:cmd(os:find_executable("epmd")++" -daemon"),
    {ok, Hostname} = inet:gethostname(),
    case net_kernel:start([list_to_atom("runner@"++Hostname), shortnames]) of
        {ok, _} -> ok;
        {error, {already_started, _}} -> ok
    end,
    lager:info("node name ~p", [node()]),
    _Config.

end_per_suite(_Config) ->
    application:stop(lager),
    _Config.

init_per_testcase(Case, Config) ->
    Nodes = pmap(fun(N) ->
                    start_node(N, Case, true)
            end, [electra, katana, flail, gargoyle]),
    {ok, _} = ct_cover:add_nodes(Nodes),
    [{nodes, Nodes}|Config].

end_per_testcase(_, _Config) ->
    pmap(fun(Node) ->ct_slave:stop(Node) end, [electra, katana, flail, gargoyle]),
    ok.

all() ->
    [read_write_delete_test, partitioned_cluster_test].

read_write_delete_test(Config) ->
    [Node1|OtherNodes] = Nodes = proplists:get_value(nodes, Config),
    [?assertEqual(ok, rpc:call(Node, plumtree_peer_service, join, [Node1]))
     || Node <- OtherNodes],
    Expected = lists:sort(Nodes),
    ok = wait_until_joined(Nodes, Expected),
    [?assertEqual({Node, Expected}, {Node,
                                     lists:sort(get_cluster_members(Node))})
     || Node <- Nodes],
    ?assertEqual(undefined, get_metadata(Node1, {foo, bar}, baz, [])),
    ok = put_metadata(Node1, {foo, bar}, baz, quux, []),
    ?assertEqual(quux, get_metadata(Node1, {foo, bar}, baz, [])),
    ok = wait_until_converged(Nodes, {foo, bar}, baz, quux),
    ok = put_metadata(Node1, {foo, bar}, baz, norf, []),
    ok = wait_until_converged(Nodes, {foo, bar}, baz, norf),
    ok = delete_metadata(Node1, {foo, bar}, baz),
    ok = wait_until_converged(Nodes, {foo, bar}, baz, undefined),
    ok.

partitioned_cluster_test(Config) ->
    [Node1|OtherNodes] = Nodes = proplists:get_value(nodes, Config),
    [?assertEqual(ok, rpc:call(Node, plumtree_peer_service, join, [Node1]))
     || Node <- OtherNodes],
    Expected = lists:sort(Nodes),
    ok = wait_until_joined(Nodes, Expected),
    [?assertEqual({Node, Expected}, {Node,
                                     lists:sort(get_cluster_members(Node))})
     || Node <- Nodes],
    ok = wait_until_converged(Nodes, {foo, bar}, baz, undefined),
    ok = put_metadata(Node1, {foo, bar}, baz, quux, []),
    ok = wait_until_converged(Nodes, {foo, bar}, baz, quux),
    {ANodes, BNodes} = lists:split(2, Nodes),
    partition_cluster(ANodes, BNodes),
    %% write to one side
    ok = put_metadata(Node1, {foo, bar}, baz, norf, []),
    %% check that whole side has the new value
    ok = wait_until_converged(ANodes, {foo, bar}, baz, norf),
    %% the far side should have the old value
    ok = wait_until_converged(BNodes, {foo, bar}, baz, quux),
    heal_cluster(ANodes, BNodes),
    %% all the nodes should see the new value
    ok = wait_until_converged(Nodes, {foo, bar}, baz, norf),
    ok.

%% ===================================================================
%% utility functions
%% ===================================================================

get_metadata(Node, Prefix, Key, Opts) ->
    rpc:call(Node, plumtree_metadata, get, [Prefix, Key, Opts]).

put_metadata(Node, Prefix, Key, ValueOrFun, Opts) ->
    rpc:call(Node, plumtree_metadata, put, [Prefix, Key, ValueOrFun, Opts]).

delete_metadata(Node, Prefix, Key) ->
    rpc:call(Node, plumtree_metadata, delete, [Prefix, Key]).

get_cluster_members(Node) ->
    {Node, {ok, Res}} = {Node, rpc:call(Node, plumtree_peer_service_manager, get_local_state, [])},
    riak_dt_orswot:value(Res).

pmap(F, L) ->
    Parent = self(),
    lists:foldl(
        fun(X, N) ->
                spawn_link(fun() ->
                            Parent ! {pmap, N, F(X)}
                    end),
                N+1
        end, 0, L),
    L2 = [receive {pmap, N, R} -> {N,R} end || _ <- L],
    {_, L3} = lists:unzip(lists:keysort(1, L2)),
    L3.

wait_until(Fun, Retry, Delay) when Retry > 0 ->
    Res = Fun(),
    case Res of
        true ->
            ok;
        _ when Retry == 1 ->
            {fail, Res};
        _ ->
            timer:sleep(Delay),
            wait_until(Fun, Retry-1, Delay)
    end.

%wait_until_left(Nodes, LeavingNode) ->
    %wait_until(fun() ->
                %lists:all(fun(X) -> X == true end, [begin
                            %not
                            %lists:member(LeavingNode,
                                         %get_cluster_members(Node))
                        %end
                            %|| Node <-
                            %Nodes])
        %end, 60*2, 500).

wait_until_joined(Nodes, ExpectedCluster) ->
    wait_until(fun() ->
                lists:all(fun(X) -> X == true end, [
                        lists:sort(ExpectedCluster) ==
                        lists:sort(get_cluster_members(Node))
                        || Node <-
                           Nodes])
        end, 60*2, 500).

wait_until_offline(Node) ->
    wait_until(fun() ->
                pang == net_adm:ping(Node)
        end, 60*2, 500).

wait_until_disconnected(Node1, Node2) ->
    wait_until(fun() ->
                pang == rpc:call(Node1, net_adm, ping, [Node2])
        end, 60*2, 500).

wait_until_connected(Node1, Node2) ->
    wait_until(fun() ->
                pong == rpc:call(Node1, net_adm, ping, [Node2])
        end, 60*2, 500).

wait_until_converged(Nodes, Prefix, Key, ExpectedValue) ->
    wait_until(fun() ->
                lists:all(fun(X) -> X == true end, [begin
                            ExpectedValue == get_metadata(Node, Prefix, Key,
                                                          [])
                        end
                            || Node <-
                            Nodes])
        end, 60*2, 500).

start_node(Name, Case, Clean) ->
    CodePath = lists:filter(fun filelib:is_dir/1, code:get_path()),
    %% have the slave nodes monitor the runner node, so they can't outlive it
    NodeConfig = [
            {monitor_master, true},
            {erl_flags, "-smp"}, %% smp for the eleveldb god
            {startup_functions, [
                    {code, set_path, [CodePath]}
                    ]}],
    case ct_slave:start(Name, NodeConfig) of
        {ok, Node} ->
            NodeDir = filename:join(["/tmp", Node, Case]),
            case Clean of
                true ->
                    %% yolo, if this deletes your HDD, I'm sorry...
                    os:cmd("rm -rf "++NodeDir);
                _ ->
                    ok
            end,
            ok = rpc:call(Node, application, load, [plumtree]),
            ok = rpc:call(Node, application, load, [lager]),
            ok = rpc:call(Node, application, set_env, [lager,
                                                       log_root,
                                                       NodeDir]),
            ok = rpc:call(Node, application, set_env, [plumtree,
                                                       plumtree_data_dir,
                                                       NodeDir]),
            {ok, _} = rpc:call(Node, application, ensure_all_started, [plumtree]),
            ok = wait_until(fun() ->
                            case rpc:call(Node, plumtree_peer_service_manager, get_local_state, []) of
                                {ok, _Res} -> true;
                                _ -> false
                            end
                    end, 60, 500),
            Node;
        {error, already_started, Node} ->
            ct_slave:stop(Name),
            wait_until_offline(Node),
            start_node(Name, Case, Clean)
    end.

partition_cluster(ANodes, BNodes) ->
    [begin
            true = rpc:call(Node1, erlang, set_cookie, [Node2, canttouchthis]),
            true = rpc:call(Node1, erlang, disconnect_node, [Node2]),
            ok = wait_until_disconnected(Node1, Node2)
        end
     || Node1 <- ANodes, Node2 <- BNodes],
    ok.

heal_cluster(ANodes, BNodes) ->
    GoodCookie = erlang:get_cookie(),
    [begin
            true = rpc:call(Node1, erlang, set_cookie, [Node2, GoodCookie]),
            ok = wait_until_connected(Node1, Node2)
        end
     || Node1 <- ANodes, Node2 <- BNodes],
    ok.

