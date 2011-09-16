%%%-------------------------------------------------------------------
%%% @author Karl Anderson <karl@2600hz.org>
%%% @author Edouard Swiac <edouard@2600hx.com>
%%%
%%% @copyright (C) 2011, Karl Anderson
%%% @doc
%%%
%%% Implementation of JSON Schema spec
%%% http://tools.ietf.org/html/draft-zyp-json-schema-03
%%% http://nico.vahlas.eu/2010/04/23/json-schema-specifying-and-validating-json-data-structures/
%%%
%%% @end
%%% Created : 18 Feb 2011 by Karl Anderson <karl@2600hz.org>
%%% 28 July 2011 - remove dust & refresh code, json schema still v0.3
%%%-------------------------------------------------------------------
-module(crossbar_schema).

-export([do_validate/2]).

-include("crossbar.hrl").
-include_lib("eunit/include/eunit.hrl").

-define(CROSSBAR_SCHEMA_DB, <<"crossbar%2Fschemas">>).
-define(TRACE, true). %% trace through the validation steps

-type validation_result() :: {ok, []} | {error, binary()}.
-type validation_results() :: validation_result() | [validation_results(),...].
-type attribute_name() :: binary().
-type attribute_value() :: binary() | json_object().

-define(VALID, true).
-define(INVALID, fun validation_error/2).
-define(VALIDATION_FUN, fun({error, _}) -> false; (?VALID) -> true end).
-define(O, fun io:format/2).

val(P, I) ->
    wh_json:get_value(P, I, undefined).


-spec trace_validate/4 :: (Instance, Property, AttrName, AttrValue) -> 'ok' | 'false' when
      Instance :: json_object(),
      Property :: binary(),
      AttrName :: attribute_name(),
      AttrValue :: attribute_value().
trace_validate(_Instance, Property, AttrName, AttrValue) ->
    ?TRACE andalso begin
		       ?O("~nproperty :: ~p - attribute :: ~p - value :: ~p~n", [Property, AttrName, AttrValue])
		   end.
trace_validate(Property, AttrName, AttrValue) ->
    trace_validate(none, Property, AttrName, AttrValue).




trace({IK, IV}, {SK, SV}) ->
    ?TRACE andalso begin
			?O("[TRACE] instance { ~p : ~p } || schema { ~p : ~p }~n", [IK,IV,SK,SV])
		    end;
trace(schema, {SK, SV}) ->
    ?TRACE andalso begin
		       ?O("[TRACE] schema { ~p : ~p }~n", [SK,SV])
		   end;
trace(instance, {IK, IV}) ->
    ?TRACE andalso begin
		       ?O("[TRACE] instance { ~p : ~p }~n", [IK,IV])
		   end.

-spec do_validate/2 :: (File, SchemaName) -> list() when
      File :: string() | json_object(),
      SchemaName :: atom().
do_validate(JObj, SchemaName) when is_binary(SchemaName) ->
    {ok, Schema} = couch_mgr:open_doc(?CROSSBAR_SCHEMA_DB, SchemaName),
    %V = validate(wh_json:set_value(SchemaName, JObj, ?EMPTY_JSON_OBJECT), SchemaName, Schema),
    {struct, SchemaDefinitions} = Schema,
    R = [validate({JObj, AttrName, val(AttrName, JObj)}, {Schema, AttrName, AttrValue}) || {AttrName, AttrValue} <- SchemaDefinitions],
    S = [E || {error, _}=E <- lists:flatten(R)],
    ?O("Result > ~p~n", [S]).


-spec validate/2 :: ({Instance, IAttName, IAttVal}, {Schema, SAttName,SAttVal}) -> validation_results() when
      Instance :: json_object(),
      IAttName :: attribute_name(),
      IAttVal :: attribute_value(),
      Schema :: json_object(),
      SAttName :: attribute_name(),
      SAttVal :: attribute_value().


%% metadata ignored for validation
validate({_, _, _}, {_, <<"_id">>, V}) ->
    %trace(schema, {<<"_id">>, V}),
    ?VALID;
validate({_, _, _}, {_, <<"_rev">>, V}) ->
    %trace(schema, {<<"_rev">>, V}),
    ?VALID;
validate({_, _, _}, {_, <<"id">>, V}) ->
    %trace(schema, {<<"id">>, V}),
    ?VALID;
validate({_, _, _}, {_, <<"\$schema">>, V}) ->
    %trace(schema, {<<"\$schema">>, V}),
    ?VALID;
validate({_, _, _}, {_, <<"description">>, D}) ->
    %trace(schema, {<<"description">>, D}),
    ?VALID;



%% properties define an object
validate({Instance, _, _}, {Schema, <<"properties">>, {struct, Properties}}) ->
    trace(schema, {<<"properties">>, <<"properties_list()">>}),
    [validate(
       {val(AttName, Instance), AttName, val(AttName, Instance)},
       {val([<<"properties">>, AttName], Schema), AttName, SAttValue})
     || {AttName, SAttValue} <- Properties];

%% instance type
validate({_, IAttName, IAttVal}, {_, <<"type">>, <<"string">>}) ->
    trace({IAttName, IAttVal}, {<<"type">>, <<"string">>}),
    ?VALID;

validate({_, IAttName, IAttVal}, {_, <<"type">>, <<"boolean">>}) when is_boolean(IAttVal)->
    trace({IAttName, IAttVal}, {<<"type">>, <<"boolean">>}),
    ?VALID;
validate({_, IAttName, IAttVal}, {_, <<"type">>, <<"boolean">>}) ->
    trace({IAttName, IAttVal}, {<<"type">>, <<"boolean">>}),
    ?VALID;

validate({_, IAttName, IAttVal}, {_, <<"type">>, <<"number">>}) when is_number(IAttVal)->
    trace({IAttName, IAttVal}, {<<"type">>, <<"number">>}),
    ?VALID;
validate({_, IAttName, IAttVal}, {_, <<"type">>, <<"number">>})->
    trace({IAttName, IAttVal}, {<<"type">>, <<"number">>}),
    ?INVALID(IAttVal, <<"must be a number">>);

validate({_, IAttName, IAttVal}, {_, <<"type">>, <<"null">>}) ->
    trace({IAttName, IAttVal}, {<<"type">>, <<"null">>});

validate({_, IAttName, {struct, _}=IAttVal}, {_, <<"type">>, <<"object">>}) ->
    trace({IAttName, IAttVal}, {<<"type">>, <<"object">>}),
    ?VALID;
validate({_, IAttName, IAttVal}, {_, <<"type">>, SAttVal}) ->
    trace({IAttName, IAttVal}, {<<"!type">>, SAttVal});



%% attribute defined in the schema that doesn't exist in the instance
validate({_, IAttName, undefined}, {Schema, SAttName, SAttVal}) ->
    trace({IAttName, undefined}, {SAttName, SAttVal}),
    case val(<<"required">>, Schema) of 
	false -> ?VALID;
        _ -> ?INVALID(IAttName, <<"is undefined">>)
    end;

validate({Instance, AttName, IAttVal}, {Schema, AttName, {struct, SAttValues}}) ->
    trace({AttName, IAttVal}, {AttName, <<"attributes()">>}),
    [validate({Instance, AttName, IAttVal}, {Schema, SAttName, SAttValue}) || {SAttName, SAttValue} <- SAttValues];

validate({_Instance, IAttName, IAttVal}, {_Schema, SAttName, SAttVal}) ->
    trace({IAttName, IAttVal}, {SAttName, SAttVal}),
    ?INVALID(IAttName, <<"error">>).

%%--------------------------------------------------------------------
%% @doc
%% Implementation of draft-zyp-json-schema-03 section 5.7
%% required - This attribute indicates if the instance must have a
%%            value, and not be undefined.
%% @end
%%--------------------------------------------------------------------
validate(Instance, Property, {struct, Definitions}) ->
    [validate(Instance, Property, {Schema, Property}) || {Property, Schema} <- Definitions];

validate(Instance, Property, {<<"required">>, AttrValue}) ->
    trace_validate(Property, <<"required">>, AttrValue),
    case val(Property, Instance) of
	undefined -> ?INVALID(Property, <<"required but not found">>);
	_-> ?VALID
    end;

validate(Instance, Property, {<<"type">>, <<"object">>}) ->
    trace_validate(Property, <<"type">>, <<"object">>),
    case val(Property, Instance) of
	{struct,_} -> ?VALID;
	_ -> ?INVALID(Property, <<"must define properties">>)
    end;

validate(Instance, Property, {<<"properties">>, {struct, Properties}}) ->
    trace_validate(Instance, Property, <<"properties">>, <<"json_props()">>),
    case val(Property, Instance) of
	{struct, _}=ChildInstance -> [validate(ChildInstance, K, V) || {K,V} <- Properties];
	undefined -> ?INVALID(Property, <<"must be of type object">>)
    end;

%%--------------------------------------------------------------------
%% @doc
%% No other functions should run if the Instance is undefined
%% @end
%%--------------------------------------------------------------------


%%--------------------------------------------------------------------
%% @doc
%% Implementation of draft-zyp-json-schema-03 section 5.1
%% type - This attribute defines what the primitive type or the schema
%%        of the instance MUST be in order to validate.
%% @end
%%--------------------------------------------------------------------
validate(Instance, Property, {<<"type">>, <<"null">>}) ->
    trace_validate(Property,<<"type">>, <<"null">>),
    case val(Property, Instance) of
        <<"null">> -> ?VALID;
        null       -> ?VALID;
        _          -> ?INVALID(Instance, <<"must be null">>)
    end;

validate(Instance, Property, {<<"type">>, <<"string">>}) ->
    trace_validate(Property, <<"type">>, <<"string">>),
    case val(Property, Instance) of
        Str when is_atom(Str); is_binary(Str) ->
	    case validate(Instance, Property, {<<"type">>, <<"null">>}) =/= ?VALID
                andalso validate(Instance, Property, {<<"type">>, <<"boolean">>}) =/= ?VALID of
		true  ->
		    ?VALID;
		false ->
		    ?INVALID(Property, <<"must be of type string">>)
	    end;
        _ -> ?INVALID(Property, <<"must be of type string">>)
    end;
validate(Instance, Property, {<<"type">>, <<"number">>}) ->
    trace_validate(Property, <<"type">>, <<"number">>),
    case is_number(val(Property, Instance)) of
	false -> ?INVALID(Property, <<"must be of type number">>);
	true  -> ?VALID
    end;
validate(Instance, Property, {<<"type">>, <<"integer">>}) ->
    trace_validate(Instance, Property, <<"type">>, <<"integer">>),
    case is_integer(val(Property, Instance)) of
	false -> ?INVALID(Property, <<"must be of type integer">>);
	true  -> ?VALID
    end;
validate(Instance, Property, {<<"type">>, <<"boolean">>}) ->
    trace_validate(Property, <<"type">>, <<"boolean">>),
    V = wh_json:get_value(Property, Instance),
    case wh_util:is_true(V) orelse wh_util:is_false(V) of
        true -> ?VALID;
        _ -> ?INVALID(Property, <<"must be of type boolean">>)
    end;
validate(Instance, Property, {<<"type">>, <<"array">>}) ->
    trace_validate(Property, <<"type">>, <<"array">>),
    case val(Property, Instance) of
	[_|_] -> ?VALID;
	[] -> ?VALID;
	_ -> ?INVALID(Property, <<"must be an array">>)
    end;

validate(_Instance, Property, {<<"type">>, <<"any">>}) ->
    trace_validate(Property, <<"type">>, <<"any">>),
    ?VALID;

validate(Instance, Property, {<<"type">>, [{struct, _}=Schema]}) ->
    trace_validate(Property, <<"type">>, struct),
    validate(Instance, Property, Schema);

validate(Instance, Property, {<<"type">>, [{struct, _}=Schema|T]}) ->
    trace_validate(Instance, <<"type">>, struct_list),
    case lists:all(?VALIDATION_FUN, validate(Instance, Property, Schema)) of
	true -> ?VALID;
	false -> ?INVALID(Property, <<"type ", T/binary, " is invalid">>)
    end;

validate(Instance, Property, {<<"type">>, [H]}) ->
    trace_validate(Property, <<"type">>, H),
    case validate(Instance, Property, {<<"type">>, H}) of
	true -> ?VALID;
	_ -> ?INVALID(Property, <<"type ", H, " is invalid">>)
    end;

validate(Instance, Property, {<<"type">>, [H|T]}) ->
    trace_validate(Property, <<"type">>, H),
    case validate(Instance, Property, {<<"type">>, H}) of
        true ->  ?VALID;
        _ -> validate(Instance, Property, { <<"type">>, T})
    end;

%% any type is valid
validate(_Instance, Property, {<<"type">>, Type}) ->
    trace_validate(Property, <<"type">>, Type),
    ?VALID;
%%--------------------------------------------------------------------
%% @doc
%% Implementation of draft-zyp-json-schema-03 section 5.2
%% properties - This attribute is an object with property definitions
%%              that define the valid values of instance object property
%%              values.
%% @end
%%--------------------------------------------------------------------

%%--------------------------------------------------------------------
%% @doc
%% Implementation of draft-zyp-json-schema-03 section 5.3
%% patternProperties - This attribute is an object that defines the
%%                     schema for a set of property names of an object
%%                     instance.
%% @end
%%--------------------------------------------------------------------

%%--------------------------------------------------------------------
%% @doc
%% Implementation of draft-zyp-json-schema-03 section 5.4
%% additionalProperties - This attribute defines a schema for all
%%                        properties that are not explicitly defined in
%%                        an object type definition
%% @end
%%--------------------------------------------------------------------

%%--------------------------------------------------------------------
%% @doc
%% Implementation of draft-zyp-json-schema-03 section 5.5
%% items - This attribute defines the allowed items in an instance array,
%%         and MUST be a schema or an array of schemas.
%% @end
%%--------------------------------------------------------------------
validate(Instance, Property, {<<"items">>, {struct, _} = Schema}) ->
    trace_validate(Property, <<"items">>, items),
    case validate(Instance, Property, {<<"type">>, <<"array">>}) of
	?VALID -> validate(val(Property, Instance), Property , Schema);
	_ -> ?INVALID(Property, <<"must be an array to define items">>)
    end;

%%--------------------------------------------------------------------
%% @doc
%% Implementation of draft-zyp-json-schema-03 section 5.6
%% additionalItems - This provides a definition for additional items in
%%                   an array instance when tuple definitions of the
%%                   items is provided.
%% @end
%%--------------------------------------------------------------------

%% NOTE: Moved section 5.7 to top of function for programatic reasons

%%--------------------------------------------------------------------
%% @doc
%% Implementation of draft-zyp-json-schema-03 section 5.8
%% dependencies - This attribute is an object that defines the
%%                requirements of a property on an instance object.
%% @end
%%--------------------------------------------------------------------

%%--------------------------------------------------------------------
%% @doc
%% Implementation of draft-zyp-json-schema-03 section 5.9
%% minimum - This attribute defines the minimum value of the instance
%%           property when the type of the instance value is a number.
%% @end
%%--------------------------------------------------------------------
validate(Instance, Property, {<<"minimum">>, Minimum})->
    case validate(Instance, Property, {<<"type">>, <<"number">>}) of
	?VALID -> case val(Property, Instance) >= Minimum of
		      ?VALID -> ?VALID;
		      _ -> ?INVALID(Property, <<"is lower than">>, Minimum)
		  end;
	_ -> ?INVALID(Property, <<"must be an integer to have a minimum">>)
    end;

%%--------------------------------------------------------------------
%% @doc
%% Implementation of draft-zyp-json-schema-03 section 5.10
%% maximum - This attribute defines the maximum value of the instance
%%           property when the type of the instance value is a number.
%% @end
%%--------------------------------------------------------------------
validate(Instance, Property, {<<"maximum">>, Maximum}) ->
    case validate(Instance, Property, {<<"type">>, <<"number">>}) of
	?VALID -> case val(Property, Instance) =< Maximum of
		      ?VALID -> ?VALID;
		      _ -> ?INVALID(Property, <<"is greater than">>, Maximum)
		  end;
	_ -> ?INVALID(Property, <<"must be an integer to have a maximum">>)
    end;
%%--------------------------------------------------------------------
%% @doc
%% Implementation of draft-zyp-json-schema-03 section 5.11
%% exclusiveMinimum - his attribute indicates if the value of the
%%                    instance (if the instance is a number) can not
%%                    equal the number defined by the "minimum" attribute.
%% @end
%%--------------------------------------------------------------------
validate(_Instance, _Property, {<<"exclusiveMinimum">>, _Bool}) ->
%    case validate(Instance, Property, {<<"type">>, <<"number">>}) of
%	?VALID -> case val(Property, Instance) >  of
%		      ?VALID -> ?VALID;
%		      _ -> ?INVALID(Property, <<"is not strictly greater than">>, ExclusiveMinimum)
%		  end;
%	_ -> ?INVALID(Property, <<"must be an integer to have a minimum">>)
%    end;
    ?VALID;

%%--------------------------------------------------------------------
%% @doc
%% Implementation of draft-zyp-json-schema-03 section 5.12
%% exclusiveMaximum - This attribute indicates if the value of the
%%                    instance (if the instance is a number) can not
%%                    equal the number defined by the "maximum" attribute.
%% @end
%%--------------------------------------------------------------------
validate(_Instance, _Property, {<<"exclusiveMaximum">>, _Bool}) ->
%    case validate(Instance, Property, {<<"type">>, <<"number">>}) of
%	?VALID -> case val(Property, Instance) < ExclusiveMaximum of
%		      ?VALID -> ?VALID;
%		      _ -> ?INVALID(Property, <<"is not strictly lower than">>, ExclusiveMaximum)
%		  end;
%	_ -> ?INVALID(Property, <<"must be an integer to have a maximum">>)
%    end;
    ?VALID;

%%--------------------------------------------------------------------
%% @doc
%% Implementation of draft-zyp-json-schema-03 section 5.13
%% minItems - This attribute defines the minimum number of values in
%%            an array when the array is the instance value.
%% @end
%%--------------------------------------------------------------------
%validate_instance(Instance, <<"minItems">>, Attribute) ->
%    trace_validate(Instance, <<"minItems">>, Attribute),
%    case not validate_instance(Instance, <<"type">>, <<"array">>)
%        orelse length(Instance) >= Attribute of
%	true -> ?VALID;
%	false -> ?INVALID(Instance, <<"must be an array to have minItems and/or there are less items than minItems in array">>)
%    end;

%%--------------------------------------------------------------------
%% @doc
%% Implementation of draft-zyp-json-schema-03 section 5.14
%% maxItems - This attribute defines the maximum number of values in
%%            an array when the array is the instance value.
%% @end
%%--------------------------------------------------------------------
%validate_instance(Instance, <<"maxItems">>, Attribute) ->
%    trace_validate(Instance, <<"maxItems">>, Attribute),
%    case not validate_instance(Instance, <<"type">>, <<"array">>)
%        orelse length(Instance) =< Attribute of
%	true -> ?VALID;
%	false -> ?INVALID(Instance, <<"must be an array to have maxItems and/or there are more items than maxItems in array">>)
%    end;

%%--------------------------------------------------------------------
%% @doc
%% Implementation of draft-zyp-json-schema-03 section 5.15
%% uniqueItems - This attribute indicates that all items in an array
%%               instance MUST be unique (contains no two identical values).
%% @end
%%--------------------------------------------------------------------
%validate_instance(Instance, <<"uniqueItems">>, _) ->
%    trace_validate(Instance, <<"uniqueItems">>, none),
%    case not validate_instance(Instance, <<"type">>, <<"array">>)
%        orelse length(Instance) =:= length(lists:usort(Instance)) of
%	true -> ?VALID;
%	false -> ?INVALID(Instance, <<"items in array must be unique">>)
%    end;

%%--------------------------------------------------------------------
%% @doc
%% Implementation of draft-zyp-json-schema-03 section 5.16
%% pattern - When the instance value is a string, this provides a
%%           regular expression that a string instance MUST match
%%           in order to be valid.
%% @end
%%--------------------------------------------------------------------

%%--------------------------------------------------------------------
%% @doc
%% Implementation of draft-zyp-json-schema-03 section 5.17
%% minLength - When the instance value is a string, this defines the
%%             minimum length of the string.
%% @end
%%--------------------------------------------------------------------
%validate_instance(Instance, <<"minLength">>, Attribute) ->
%    trace_validate(Instance, <<"minLength">>, Attribute),
%    case not validate_instance(Instance, <<"type">>, <<"string">>)
%        orelse length(wh_util:to_list(Instance)) >= Attribute of
%	true -> ?VALID;
%	false -> ?INVALID(Instance, <<"is too short, min. characters allowed:">>, Attribute)
%    end;
%%--------------------------------------------------------------------
%% @doc
%% Implementation of draft-zyp-json-schema-03 section 5.18
%% maxLength -  When the instance value is a string, this defines
%%              the maximum length of the string.
%% @end
%%--------------------------------------------------------------------
%validate_instance(Instance, <<"maxLength">>, Attribute) ->
%    trace_validate(Instance, <<"maxLength">>, Attribute),
%    case not validate_instance(Instance, <<"type">>, <<"string">>)
%        orelse length(wh_util:to_list(Instance)) =< Attribute of
%	true -> ?VALID;
%	false -> ?INVALID(Instance, <<"is too long, max. characters allowed:">>, Attribute)
%    end;

%%--------------------------------------------------------------------
%% @doc
%% Implementation of draft-zyp-json-schema-03 section 5.19
%% enum - This provides an enumeration of all possible values that are
%%        valid for the instance property.
%% @end
%%--------------------------------------------------------------------
%validate_instance(Instance, <<"enum">>, Attribute) ->
%    trace_validate(Instance, <<"enum">>, Attribute),
%    case lists:member(Instance, Attribute) of
%	true -> ?VALID;
%	false -> ?INVALID(Instance, <<"must be member of the array">>)
%    end;

%%--------------------------------------------------------------------
%% @doc
%% Implementation of draft-zyp-json-schema-03 section 5.20
%% default - This attribute defines the default value of the
%%           instance when the instance is undefined.
%% @end
%%--------------------------------------------------------------------

%%--------------------------------------------------------------------
%% @doc
%% Implementation of draft-zyp-json-schema-03 section 5.21
%% title - This attribute is a string that provides a short
%%         description of the instance property.
%% @end
%%--------------------------------------------------------------------
validate(_Instance, Property, {<<"description">>, AttrValue}) ->
    trace_validate(Property, <<"description">>, AttrValue),
    ?VALID;

%%--------------------------------------------------------------------
%% @doc
%% Implementation of draft-zyp-json-schema-03 section 5.22
%% description - This attribute is a string that provides a full
%%               description of the of purpose the instance property.
%% @end
%%--------------------------------------------------------------------

%%--------------------------------------------------------------------
%% @doc
%% Implementation of draft-zyp-json-schema-03 section 5.23
%% format - This property defines the type of data, content type, or
%%           microformat to be expected in the instance property values.
%% @end
%%--------------------------------------------------------------------

%%--------------------------------------------------------------------
%% @doc
%% Implementation of draft-zyp-json-schema-03 section 5.24
%% divisibleBy - This attribute defines what value the number instance
%%                must be divisible by with no remainder.
%% @end
%%--------------------------------------------------------------------
%validate_instance(Instance, <<"divisibleBy">>, Attribute) ->
%    trace_validate(Instance, <<"divisibleBy">>, Attribute),
%    case validate_instance(Instance, <<"type">>, <<"number">>) =/= true
%        orelse case {Instance, Attribute} of
%                   {_, 0} -> ?INVALID(division_0, <<"Division by 0">>);
%                   {0, _} -> ?VALID;
%                   {I, A} -> case trunc(I/A) == I/A of
%				 true -> ?VALID;
%				 false -> ?INVALID(error, <<"Not divisible">>)
%			     end
%	       end of
%	true -> ?VALID;
%	Error -> Error
%    end;%

%%--------------------------------------------------------------------
%% @doc
%% Implementation of draft-zyp-json-schema-03 section 5.25
%% disallow - This attribute takes the same values as the "type"
%%            attribute, however if the instance matches the type or if
%%            this value is an array and the instance matches any type
%%            or schema in the array, then this instance is not valid.
%% @end
%%--------------------------------------------------------------------
%validate_instance(Instance, <<"disallow">>, Attribute) ->
%    trace_validate(Instance, <<"disallow">>, Attribute),
%    case not validate_instance(Instance, <<"type">>, Attribute) of
%	true -> ?VALID;
%	_ -> ?INVALID(Instance, <<"this type is not allowed">>)
%    end;

%%--------------------------------------------------------------------
%% @doc
%% Implementation of draft-zyp-json-schema-03 section 5.26
%% extends - another schema which will provide a base schema which
%%           the current schema will inherit from
%% @end
%%--------------------------------------------------------------------


%%--------------------------------------------------------------------
%% @doc
%% Implementation of draft-zyp-json-schema-03 section 5.27
%% id - defines the current URI of this schem
%% @end
%%--------------------------------------------------------------------
validate(_Instance, Property, {<<"id">>, AttrValue}) ->
    trace_validate(Property, <<"id">>, AttrValue),
    ?VALID;

%%--------------------------------------------------------------------
%% @doc
%% Implementation of draft-zyp-json-schema-03 section 5.28
%% $ref - defines a URI of a schema that contains the full
%%        representation of this schema
%% @end
%%--------------------------------------------------------------------

%%--------------------------------------------------------------------
%% @doc
%% Implementation of draft-zyp-json-schema-03 section 5.29
%% $schema - defines a URI of a JSON Schema that is the schema of
%%           the current schema
%% @end
%%--------------------------------------------------------------------
validate(_Instance, Property, {<<"\$schema">>, AttrValue}) ->
    trace_validate(Property, <<"\$schema">>, AttrValue),
    ?VALID;

%%--------------------------------------------------------------------
%% @doc
%% Ignore CouchDB document properties
%% @end
%%--------------------------------------------------------------------
validate(_, _, {<<"_id">>, _}) ->
    ?VALID;
validate(_, _, {<<"_rev">>, _}) ->
    ?VALID;
validate(_, _, {<<"name">>, _}) ->
    ?VALID;

%%--------------------------------------------------------------------
%% @doc
%% End of validate_instance
%% @end
%%--------------------------------------------------------------------
validate(_,P,{K,V}) ->
    trace_validate(P, K, V),
    ?INVALID(P, <<"something wrong happened on our side">>).

-spec validation_error/2 :: (Instance, Message) -> validation_result() when
      Instance :: term(),
      Message :: binary().
validation_error({struct, _}, _) ->
    {error, <<"json is invalid">>};
validation_error(Instance, Msg) ->
    {error, <<(wh_util:to_binary(Instance))/binary,
			     " ", (wh_util:to_binary(Msg))/binary>>}.

-spec validation_error/3 :: (Instance, Message, Attribute) -> validation_results() when
      Instance :: term(),
      Message :: binary(),
      Attribute :: term().
validation_error(Instance, Msg, Attribute) ->
    {error, <<(wh_util:to_binary(Instance))/binary,
			     " ", (wh_util:to_binary(Msg))/binary,
                             " ", (wh_util:to_binary(Attribute))/binary>>}.
%% EUNIT TESTING
-ifdef(TEST).

-define(NULL, <<"null">>).
-define(TRUE, <<"true">>).
-define(FALSE, <<"false">>).
-define(NEG1, -1).
-define(ZERO, 0).
-define(POS1, 1).
-define(PI, 3.1416).
-define(STR1, <<"foobar">>).
-define(STR2, barfoo).
-define(OBJ1, {struct, [{<<"foo">>, <<"bar">>}]}).
-define(ARR1, []).
-define(ARR2, [?STR1]).
-define(ARR3, [?STR1, ?STR2]).
-define(ARR4, [?STR1, ?STR2, ?PI]).
-define(ARR5, [?NULL, ?NULL, ?PI]).
-define(ARR6, [?STR1, ?STR1, ?PI]).
-define(ARR7, [?ARR3, ?ARR3, ?PI]).
-define(ARR8, [?OBJ1, ?OBJ1, ?PI]).

%% Section 5.1 - type
%%     string Value MUST be a string
type_string_test() ->
    Schema = "{ \"type\": \"string\" }",
    Succeed = [?STR1, ?STR2],
    Fail = [?NULL, ?TRUE, ?FALSE, ?NEG1, ?ZERO, ?POS1, ?PI, ?ARR1, ?ARR2, ?OBJ1],
    validate_test(Succeed, Fail, Schema).

%%     number Value MUST be a number, floating point numbers are allowed.
type_number_test() ->
    Schema = "{ \"type\": \"number\" }",
    Succeed = [?NEG1, ?ZERO, ?POS1, ?PI],
    Fail = [?NULL, ?TRUE, ?FALSE, ?STR1, ?STR2, ?ARR1, ?ARR2, ?OBJ1],
    validate_test(Succeed, Fail, Schema).

%%     integer Value MUST be an integer, no floating point numbers are allowed
type_integer_test() ->
    Schema = "{ \"type\": \"integer\" }",
    Succeed = [?NEG1, ?ZERO, ?POS1],
    Fail = [?NULL, ?TRUE, ?FALSE, ?PI, ?STR1, ?STR2, ?ARR1, ?ARR2, ?OBJ1],
    validate_test(Succeed, Fail, Schema).

%%     boolean Value MUST be a boolean
type_boolean_test() ->
    Schema = "{ \"type\": \"boolean\" }",
    Succeed = [?TRUE, ?FALSE],
    Fail = [?NULL, ?NEG1, ?ZERO, ?POS1, ?PI, ?STR1, ?STR2, ?ARR1, ?ARR2, ?OBJ1],
    validate_test(Succeed, Fail, Schema).

%%     object Value MUST be an object
type_object_test() ->
    Schema = "{ \"type\": \"object\" }",
    Succeed = [?OBJ1],
    Fail = [?NULL, ?TRUE, ?FALSE, ?NEG1, ?ZERO, ?POS1, ?PI, ?STR1, ?STR2, ?ARR1, ?ARR2],
    validate_test(Succeed, Fail, Schema).

%%    array Value MUST be an array
type_array_test() ->
    Schema = "{ \"type\": \"array\" }",
    Succeed = [?ARR1, ?ARR2],
    Fail = [?NULL, ?TRUE, ?FALSE, ?NEG1, ?ZERO, ?POS1, ?PI, ?STR1, ?STR2, ?OBJ1],
    validate_test(Succeed, Fail, Schema).

%%    null Value MUST be null.
type_null_test() ->
    Schema = "{ \"type\": \"null\" }",
    Succeed = [?NULL],
    Fail = [?TRUE, ?FALSE, ?NEG1, ?ZERO, ?POS1, ?PI, ?STR1, ?STR2, ?ARR1, ?ARR2, ?OBJ1],
    validate_test(Succeed, Fail, Schema).

%%    any value MAY be of any type including null
type_any_test() ->
    Schema = "{ \"type\": \"any\" }",
    Succeed = [?NULL, ?TRUE, ?FALSE, ?NEG1, ?ZERO, ?POS1, ?PI, ?STR1, ?STR2, ?ARR1, ?ARR2, ?OBJ1],
    Fail = [],
    validate_test(Succeed, Fail, Schema).

%%    If the property is not defined or is not in this list, then any type of value is acceptable.
type_unknown_test() ->
    Schema = "{ \"type\": \"foobar\" }",
    Succeed = [?NULL, ?TRUE, ?FALSE, ?NEG1, ?ZERO, ?POS1, ?PI, ?STR1, ?STR2, ?ARR1, ?ARR2, ?OBJ1],
    Fail = [],
    validate_test(Succeed, Fail, Schema).

%%    union types An array of two or more simple type definitions
type_simple_union_test() ->
    Schema = "{ \"type\": [\"string\", \"null\"] }",
    Succeed = [?NULL, ?STR1, ?STR2],
    Fail = [?TRUE, ?FALSE, ?NEG1, ?ZERO, ?POS1, ?PI, ?ARR1, ?ARR2, ?OBJ1],
    validate_test(Succeed, Fail, Schema).

%%    union types An array of type definitions with a nested schema
type_nested_union_test() ->
    Schema = "{ \"type\": [\"string\", { \"type\": \"number\", \"minimum\": -1, \"maximum\": 0}] }",
    Succeed = [?STR1, ?STR2, ?NEG1, ?ZERO],
    Fail = [?NULL, ?TRUE, ?FALSE, ?POS1, ?PI, ?ARR1, ?ARR2, ?OBJ1],
    validate_test(Succeed, Fail, Schema).

%%    union types An array of type definitions with a nested schema
type_complex_union_test() ->
    Schema = "{ \"type\": [{ \"type\": \"number\", \"minimum\": -1, \"maximum\": 0, \"exclusiveMinimum\": true}, \"string\"] }",
    Succeed = [?STR1, ?STR2, ?ZERO],
    Fail = [?NULL, ?TRUE, ?FALSE, ?NEG1, ?POS1, ?PI, ?ARR1, ?ARR2, ?OBJ1],
    validate_test(Succeed, Fail, Schema).

%% Section 5.2 - properties
%%     object with property definitions that define the valid values of instance object property values

%% Section 5.3 - patternProperties
%%     regular expression pattern name attribute is an object that defines the schema

%% Section 5.4 - additionalProperties
%%     attribute defines a schema for all properties that are not explicitly defined

%% Section 5.5 - items
%%     defines the allowed items in an instance array

%% Section 5.6 - additionalItems
%%      definition for additional items in an array instance when tuple definitions of the items is provided

%% Section 5.7 - required
%%      indicates if the instance must have a value

%% Section 5.8 - dependencies
%%      defines the requirements of a property on an instance object

%% Section 5.9 - minimum
%%     defines the minimum value of the instance property when the type of the instance is a number
minimum_test() ->
    Schema = "{ \"minimum\": 0 }",
    Succeed = [?ZERO, ?POS1, ?PI],
    Fail = [?NULL, ?TRUE, ?FALSE, ?NEG1, ?STR1, ?STR2, ?ARR1, ?ARR2, ?OBJ1],
    validate_test(Succeed, Fail, Schema).

%% Section 5.10 - maximum
%%     defines the maxium value of the instance property when the type of the instance is a number
maximum_test() ->
    Schema = "{ \"maximum\": 0 }",
    Succeed = [?NEG1, ?ZERO],
    Fail = [?NULL, ?TRUE, ?FALSE, ?POS1, ?PI, ?STR1, ?STR2, ?ARR1, ?ARR2, ?OBJ1],
    validate_test(Succeed, Fail, Schema).

%% Section 5.11 - exclusiveMinimum
%%     indicates if the value of the instance (if the instance is a number) can not equal the number defined by the 'minimum' attribute
exclusive_minimum_test() ->
    Schema = "{ \"minimum\": 0,  \"exclusiveMinimum\": true }",
    Succeed = [?POS1, ?PI],
    Fail = [?NULL, ?TRUE, ?FALSE, ?NEG1, ?ZERO, ?STR1, ?STR2, ?ARR1, ?ARR2, ?OBJ1],
    validate_test(Succeed, Fail, Schema).

%% Section 5.12 - exclusiveMaximum
%%     indicates if the value of the instance (if the instance is a number) can not equal the number defined by the 'maximum' attribute
exclusive_maximum_test() ->
    Schema = "{ \"maximum\": 0, \"exclusiveMaximum\": true }",
    Succeed = [?NEG1],
    Fail = [?NULL, ?TRUE, ?FALSE, ?ZERO, ?POS1, ?PI, ?STR1, ?STR2, ?ARR1, ?ARR2, ?OBJ1],
    validate_test(Succeed, Fail, Schema).

%% Section 5.13 - minItems
%%     defines the minimum number of values in an array when the array is the instance value
min_items_test() ->
    Schema = "{ \"minItems\": 2 }",
    Succeed = [?ARR3, ?ARR4],
    Fail = [?NULL, ?TRUE, ?FALSE, ?NEG1, ?ZERO, ?POS1, ?PI, ?STR1, ?STR2, ?ARR1, ?ARR2, ?OBJ1],
    validate_test(Succeed, Fail, Schema).

%% Section 5.14 - maxItems
%%     defines the maximum number of values in an array when the array is the instance value
max_items_test() ->
    Schema = "{ \"maxItems\": 2 }",
    Succeed = [?ARR1, ?ARR2, ?ARR3],
    Fail = [?NULL, ?TRUE, ?FALSE, ?NEG1, ?ZERO, ?POS1, ?PI, ?STR1, ?STR2, ?ARR4, ?OBJ1],
    validate_test(Succeed, Fail, Schema).

%% Section 5.15 - uniqueItems
%%     indicates that all items in an array instance MUST be unique (containes no two identical values).
%%      - booleans/numbers/strings/null have the same value
%%      - arrays containes the same number of iteams and each item in the array is equal to teh corresponding item in the other array
%%      - objects contain the same property names, and each property in the object is equal to the corresponding property in the other object
unique_items_test() ->
    Schema = "{ \"uniqueItems\": true }",
    Succeed = [?ARR1, ?ARR2, ?ARR3, ?ARR4],
    Fail = [?NULL, ?TRUE, ?FALSE, ?NEG1, ?ZERO, ?POS1, ?PI, ?STR1, ?STR2, ?ARR5, ?ARR6, ?ARR7, ?ARR8, ?OBJ1],
    validate_test(Succeed, Fail, Schema).

%% Section 5.16 - pattern
%%     When the instance value is a string, this provides a regular expression that a string MUST match
pattern_test() ->
    Schema = "{ \"pattern\": \"tle\$\"}",
    Succeed = [chipotle, <<"chipotle">>],
    Fail = [?NULL, ?TRUE, ?FALSE, ?NEG1, ?ZERO, ?POS1, ?PI, ?STR1, ?STR2, ?ARR1, ?ARR2, ?OBJ1],
    validate_test(Succeed, Fail, Schema).

%% Section 5.17 - minLength
%%     When the instance value is a string, this defines the minimum length of the string
min_length_test() ->
    Schema = "{ \"minLength\": 7}",
    Succeed = [longstring, <<"longstring">>],
    Fail = [?NULL, ?TRUE, ?FALSE, ?NEG1, ?ZERO, ?POS1, ?PI, ?STR1, ?STR2, ?ARR1, ?ARR2, ?OBJ1],
    validate_test(Succeed, Fail, Schema).

%% Section 5.18 - maxLength
%%     When the instance value is a string, this defines the maximum length of the string
max_length_test() ->
    Schema = "{ \"maxLength\": 3}",
    Succeed = [foo, <<"bar">>],
    Fail = [?NULL, ?TRUE, ?FALSE, ?NEG1, ?ZERO, ?POS1, ?PI, ?STR1, ?STR2, ?ARR1, ?ARR2, ?OBJ1],
    validate_test(Succeed, Fail, Schema).

%% Section 5.19 - enum
%%     Enumeration of all possible values that are valid for the instance property
enum_test() ->
    Schema = "{ \"enum\": [\"foobar\", 3.1416]}",
    Succeed = [?STR1, ?PI],
    Fail = [?NULL, ?TRUE, ?FALSE, ?NEG1, ?ZERO, ?POS1, ?STR2, ?ARR1, ?ARR2, ?OBJ1],
    validate_test(Succeed, Fail, Schema).

%% Section 5.20 - default
%% Section 5.21 - title
%% Section 5.22 - description

%% Section 5.23 - format
%%     defines the type of data, content type, or microformat to be expected

%% Section 5.24 - divisibleBy
%%     defines what value the number instance must be divisible by
divisible_by_test() ->
    Schema = "{ \"divisibleBy\": 3}",
    Succeed = [?ZERO, 3, 15],
    Fail = [?NULL, ?TRUE, ?FALSE, ?NEG1, ?POS1, ?PI, ?STR1, ?STR2, ?ARR1, ?ARR2, ?OBJ1],
    validate_test(Succeed, Fail, Schema).

%%     test the true spirt of this property as per the advocate
divisible_by_float_test() ->
    Schema = "{ \"divisibleBy\": 0.01}",
    Succeed = [?NEG1, ?ZERO, ?POS1, 3.15],
    Fail = [?NULL, ?TRUE, ?FALSE, ?PI, ?STR1, ?STR2, ?ARR1, ?ARR2, ?OBJ1],
    validate_test(Succeed, Fail, Schema).

%% Section 5.25 - disallow
%%     string Value MUST NOT be a string
disallow_string_test() ->
    Schema = "{ \"disallow\": \"string\" }",
    Succeed = [?NULL, ?TRUE, ?FALSE, ?NEG1, ?ZERO, ?POS1, ?PI, ?ARR1, ?ARR2, ?OBJ1],
    Fail = [?STR1, ?STR2],
    validate_test(Succeed, Fail, Schema).

%%     number Value MUST NOT be a number, including floating point numbers
disallow_number_test() ->
    Schema = "{ \"disallow\": \"number\" }",
    Succeed = [?NULL, ?TRUE, ?FALSE, ?STR1, ?STR2, ?ARR1, ?ARR2, ?OBJ1],
    Fail = [?NEG1, ?ZERO, ?POS1, ?PI],
    validate_test(Succeed, Fail, Schema).

%%     integer Value MUST NOT be an integer, does not include floating point numbers
disallow_integer_test() ->
    Schema = "{ \"disallow\": \"integer\" }",
    Succeed = [?NULL, ?TRUE, ?FALSE, ?PI, ?STR1, ?STR2, ?ARR1, ?ARR2, ?OBJ1],
    Fail = [?NEG1, ?ZERO, ?POS1],
    validate_test(Succeed, Fail, Schema).

%%     boolean Value MUST NOT be a boolean
disallow_boolean_test() ->
    Schema = "{ \"disallow\": \"boolean\" }",
    Succeed = [?NULL, ?NEG1, ?ZERO, ?POS1, ?PI, ?STR1, ?STR2, ?ARR1, ?ARR2, ?OBJ1],
    Fail = [?TRUE, ?FALSE],
    validate_test(Succeed, Fail, Schema).

%%     object Value MUST NOT be an object
disallow_object_test() ->
    Schema = "{ \"disallow\": \"object\" }",
    Succeed = [?NULL, ?TRUE, ?FALSE, ?NEG1, ?ZERO, ?POS1, ?PI, ?STR1, ?STR2, ?ARR1, ?ARR2],
    Fail = [?OBJ1],
    validate_test(Succeed, Fail, Schema).

%%    array Value MUST NOT be an array
disallow_array_test() ->
    Schema = "{ \"disallow\": \"array\" }",
    Succeed = [?NULL, ?TRUE, ?FALSE, ?NEG1, ?ZERO, ?POS1, ?PI, ?STR1, ?STR2, ?OBJ1],
    Fail = [?ARR1, ?ARR2],
    validate_test(Succeed, Fail, Schema).

%%    null Value MUST NOT be null
disallow_null_test() ->
    Schema = "{ \"disallow\": \"null\" }",
    Succeed = [?TRUE, ?FALSE, ?NEG1, ?ZERO, ?POS1, ?PI, ?STR1, ?STR2, ?ARR1, ?ARR2, ?OBJ1],
    Fail = [?NULL],
    validate_test(Succeed, Fail, Schema).

%%    union types An array of type definitions with a nested schema
disallow_nested_union_test() ->
    Schema = "{ \"disallow\": [\"string\", { \"type\": \"number\", \"maximum\": 0}] }",
    Succeed = [?NULL, ?TRUE, ?FALSE, ?POS1, ?PI, ?ARR1, ?ARR2, ?OBJ1],
    Fail = [?STR1, ?STR2, ?NEG1, ?ZERO],
    validate_test(Succeed, Fail, Schema).

%%    union types An array of type definitions with a nested schema
disallow_complex_union_test() ->
    Schema = "{ \"disallow\": [{ \"type\": \"number\", \"minimum\": -1, \"maximum\": 0, \"exclusiveMinimum\": true}, \"string\"] }",
    Succeed = [?NULL, ?TRUE, ?FALSE, ?NEG1, ?POS1, ?PI, ?ARR1, ?ARR2, ?OBJ1],
    Fail = [?STR1, ?STR2, ?ZERO],
    validate_test(Succeed, Fail, Schema).

%% Section 5.26 - extends
%%     another schema which will provide a base schema which the current schema will inherit from


%% Helper function to run the eunit tests listed above
validate_test(Succeed, Fail, Schema) ->
    {struct, S} = mochijson2:decode(binary:list_to_bin(Schema)),
    lists:foreach(fun(Elem) ->
			  ?O(">>>elem ~p, schema ~p", [Elem, S]),
			  Validation = [validate({none, none, Elem}, {S, AttName, AttValue}) || {AttName, AttValue} <- S],
			  ?O("~n------- VALIDATION SUCCEED----- ~p => ~p~n", [Elem, Validation]),
			  Result = lists:all(?VALIDATION_FUN, Validation),
			  ?debugFmt("~p: ~p: Testing success of ~p => ~p~n", [S, Elem, Validation, Result]),
			  ?assertEqual(true, Result)
		  end, Succeed),
    lists:foreach(fun(Elem) ->
			  Validation = [],
			  ?O("~n------- VALIDATION FAIL----- ~p => ~p~n", [Elem, Validation]),
			  Result = lists:any(?VALIDATION_FUN, Validation),
			  %?debugFmt("~p: ~p: Testing failure of ~p => ~p~n", [S, Elem, Validation, Result]),
			  ?assertEqual(false, Result)
		  end, []).
-endif.