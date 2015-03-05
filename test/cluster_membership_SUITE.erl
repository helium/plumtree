-module(cluster_membership_SUITE).

-export([
         %% suite/0,
         init_per_suite/1,
         end_per_suite/1,
         init_per_testcase/2,
         end_per_testcase/2,
         all/0
        ]).

-export([
    singleton_test/1,
    join_test/1,
    join_nonexistant_node_test/1,
    join_self_test/1,
    leave_test/1,
    sticky_membership_test/1
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
    os:cmd("empd -daemon"),
    {ok, Hostname} = inet:gethostname(),
    {ok, _} = net_kernel:start([list_to_atom("runner@"++Hostname), shortnames]),
    lager:info("node name ~p", [node()]),
    _Config.

end_per_suite(_Config) ->
    application:stop(lager),
    _Config.

init_per_testcase(Case, Config) ->
    Nodes = pmap(fun(N) ->
                    start_node(N, Case, true)
            end, [jaguar, shadow, thorn, pyros]),
    {ok, _} = ct_cover:add_nodes(Nodes),
    [{nodes, Nodes}|Config].

end_per_testcase(_, _Config) ->
    [ct_slave:stop(Node) || Node <- [jaguar, shadow, thorn, pyros]],
    ok.

all() ->
    [singleton_test, join_test, join_nonexistant_node_test, join_self_test,
    leave_test].
    %[sticky_membership_test].

singleton_test(Config) ->
    Nodes = proplists:get_value(nodes, Config),
    ok = ct_cover:remove_nodes(Nodes),
    [[Node] = get_cluster_members(Node) || Node <- Nodes],
    ok.

join_test(Config) ->
    [Node1, Node2 |Nodes] = proplists:get_value(nodes, Config),
    ?assertEqual(ok, rpc:call(Node1, plumtree_peer_service, join, [Node2])),
    Expected = lists:sort([Node1, Node2]),
    wait_until_joined([Node1, Node2], Expected),
    ?assertEqual(Expected, lists:sort(get_cluster_members(Node1))),
    ?assertEqual(Expected, lists:sort(get_cluster_members(Node2))),
    %% make sure the last 2 are still singletons
    [?assertEqual([Node], get_cluster_members(Node)) || Node <- Nodes],
    ok.

join_nonexistant_node_test(Config) ->
    [Node1|_] = proplists:get_value(nodes, Config),
    ?assertEqual({error, not_reachable}, rpc:call(Node1, plumtree_peer_service, join,
                              [fake@fakehost])),
    ?assertEqual([Node1], get_cluster_members(Node1)),
    ok.

join_self_test(Config) ->
    [Node1|_] = proplists:get_value(nodes, Config),
    ?assertEqual({error, self_join}, rpc:call(Node1, plumtree_peer_service, join,
                              [Node1])),
    ?assertEqual([Node1], get_cluster_members(Node1)),
    ok.

leave_test(Config) ->
    [Node1|OtherNodes] = Nodes = proplists:get_value(nodes, Config),
    [?assertEqual(ok, rpc:call(Node, plumtree_peer_service, join, [Node1]))
     || Node <- OtherNodes],
    Expected = lists:sort(Nodes),
    wait_until_joined(Nodes, Expected),
    [?assertEqual({Node, Expected}, {Node,
                                     lists:sort(get_cluster_members(Node))})
     || Node <- Nodes],
    ?assertEqual(ok, rpc:call(Node1, plumtree_peer_service, leave, [])),
    Expected2 = lists:sort(OtherNodes),
    ok = wait_until_left(OtherNodes, Node1),
    %% should be a 3 node cluster now
    [?assertEqual({Node, Expected2}, {Node,
                                      lists:sort(get_cluster_members(Node))})
     || Node <- OtherNodes],
    %% node1 should be offline
    ?assertEqual(pang, net_adm:ping(Node1)),
    ok.

sticky_membership_test(Config) ->
    [Node1|OtherNodes] = Nodes = proplists:get_value(nodes, Config),
    [?assertEqual(ok, rpc:call(Node, plumtree_peer_service, join, [Node1]))
     || Node <- OtherNodes],
    Expected = lists:sort(Nodes),
    wait_until_joined(Nodes, Expected),
    [?assertEqual({Node, Expected}, {Node,
                                     lists:sort(get_cluster_members(Node))})
     || Node <- Nodes],
    ct_slave:stop(jaguar),
    wait_until_offline(Node1),
    %% check the membership is the same
    [?assertEqual({Node, Expected}, {Node,
                                     lists:sort(get_cluster_members(Node))})
     || Node <- OtherNodes],
    start_node(jaguar, sticky_membership_test, false),
    ?assertEqual({Node1, Expected}, {Node1,
                                    lists:sort(get_cluster_members(Node1))}),
    ct_slave:stop(jaguar),
    wait_until_offline(Node1),
    [Node2|LastTwo] = OtherNodes,
    ?assertEqual(ok, rpc:call(Node2, plumtree_peer_service, leave, [])),
    ok = wait_until_left(LastTwo, Node2),
    wait_until_offline(Node2),
    Expected2 = lists:sort(Nodes -- [Node2]),
    [?assertEqual({Node, Expected2}, {Node,
                                      lists:sort(get_cluster_members(Node))})
     || Node <- LastTwo],
    start_node(jaguar, sticky_membership_test, false),
    ok = wait_until_left([Node1], Node2),
    ?assertEqual({Node1, Expected2}, {Node1,
                                    lists:sort(get_cluster_members(Node1))}),
    ok.


%% ===================================================================
%% utility functions
%% ===================================================================

get_cluster_members(Node) ->
    {ok, Res} = rpc:call(Node, plumtree_peer_service_manager, get_local_state, []),
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

wait_until_left(Nodes, LeavingNode) ->
    %ct:pal("waiting for ~p to leave ~p", [LeavingNode, Nodes]),
    wait_until(fun() ->
                lists:all(fun(X) -> X == true end, [begin
                            %ct:pal("Node ~p - ~p -- ~p = ~p", [Node,
                                                          %get_cluster_members(Node),
                                                          %LeavingNode, not
                                                               %lists:member(LeavingNode,
                                                                            %get_cluster_members(Node))]),
                            not
                            lists:member(LeavingNode,
                                         get_cluster_members(Node))
                        end
                            || Node <-
                            Nodes])
        end, 60*2, 500).

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

start_node(Name, Case, Clean) ->
    CodePath = lists:filter(fun filelib:is_dir/1, code:get_path()),
    %% have the slave nodes monitor the runner node, so they can't outlive it
    NodeConfig = [
            {monitor_master, true},
            {startup_functions, [
                    {code, set_path, [CodePath]}
                    ]}],
    {ok, Node} = ct_slave:start(Name, NodeConfig),
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
                    undefined /= rpc:call(Node, ets, info,
                                          [cluster_state])
            end, 5, 100),
    Node.


