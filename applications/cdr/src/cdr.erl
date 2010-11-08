%%% @author James Aimonetti <james@2600hz.org>
%%% @copyright (C) 2010, James Aimonetti
%%% @doc
%%% CDR logger
%%% @end
%%% Created :  8 Nov 2010 by James Aimonetti <james@2600hz.org>

-module(cdr).

-author('James Aimonetti <james@2600hz.com>').
-export([start/0, start_link/0, stop/0]).

%% @spec start_link() -> {ok,Pid::pid()}
%% @doc Starts the app for inclusion in a supervisor tree
start_link() ->
    ensure_started(sasl),
    ensure_started(crypto),
    ensure_started(whistle_amqp),
    ensure_started(dynamic_compile),
    ensure_started(log_roller),
    ensure_started(couchbeam),
    cdr_sup:start_link().

%% @spec start() -> ok
%% @doc Start the callmgr server.
start() ->
    ensure_started(sasl),
    ensure_started(crypto),
    ensure_started(whistle_amqp),
    ensure_started(dynamic_compile),
    ensure_started(log_roller),
    ensure_started(couchbeam),
    application:start(cdr).

%% @spec stop() -> ok
%% @doc Stop the cdr server.
stop() ->
    application:stop(cdr).

ensure_started(App) ->
    case application:start(App) of
	ok ->
	    ok;
	{error, {already_started, App}} ->
	    ok
    end.