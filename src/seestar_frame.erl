%%% Copyright 2014 Aleksey Yeschenko
%%%
%%% Licensed under the Apache License, Version 2.0 (the "License");
%%% you may not use this file except in compliance with the License.
%%% You may obtain a copy of the License at
%%%
%%%     http://www.apache.org/licenses/LICENSE-2.0
%%%
%%% Unless required by applicable law or agreed to in writing, software
%%% distributed under the License is distributed on an "AS IS" BASIS,
%%% WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
%%% See the License for the specific language governing permissions and
%%% limitations under the License.

%%% @private
-module(seestar_frame).

-export([new/5, id/1, flags/1, has_flag/2, opcode/1,
         body/1, warnings/1, encode/1, pending_size/1, decode/1]).

-type stream_id() :: -1..127.
-type flag() :: compression | tracing.
-type opcode() :: 16#00..16#0C.
-export_type([stream_id/0, flag/0, opcode/0, frame/0]).

-define(COMPRESSION, 16#01).
-define(TRACING, 16#02).
-define(WARNING, 16#08).

-define(REQ_VSN3,  16#03).
-define(RESP_VSN3, 16#83).
-define(REQ_VSN4,  16#04).
-define(RESP_VSN4, 16#84).

-record(frame, {proto,
                id :: stream_id(),
                flags = [] :: [flag()],
                opcode :: opcode(),
                body :: binary(),
                warnings = [] :: [binary()]}).
-opaque frame() :: #frame{}.

%% -------------------------------------------------------------------------
%% API
%% -------------------------------------------------------------------------

-spec new(integer(), stream_id(), [flag()], opcode(), binary()) -> frame().
new(ProtoVsn, ID, Flags, Op, Body) ->
    #frame{proto=ProtoVsn, id = ID, flags = Flags, opcode = Op, body = Body}.

-spec id(frame()) -> stream_id().
id(Frame) ->
    Frame#frame.id.

-spec flags(frame()) -> [flag()].
flags(Frame) ->
    Frame#frame.flags.

-spec has_flag(frame(), flag()) -> boolean().
has_flag(Frame, Flag) ->
    lists:member(Flag, flags(Frame)).

-spec opcode(frame()) -> opcode().
opcode(Frame) ->
    Frame#frame.opcode.

-spec body(frame()) -> binary().
body(Frame) ->
    Frame#frame.body.

-spec warnings(frame()) -> list(binary()).
warnings(Frame) ->
    Frame#frame.warnings.

-spec encode(frame()) -> binary().
encode(#frame{proto=ProtoVsn, id = ID, flags = Flags, opcode = Op, body = Body}) ->
    <<ProtoVsn, (encode_flags(Flags)), ID:16/signed, Op, (size(Body)):32, Body/binary>>.

encode_flags(Flags) ->
    lists:foldl(fun(Flag, Byte) -> encode_flag(Flag) bor Byte end, 0, Flags).

encode_flag(compression) -> ?COMPRESSION;
encode_flag(tracing)     -> ?TRACING.

-spec pending_size(binary()) -> pos_integer().
pending_size(<<16#84, _Flags, _ID:16/signed, _Op, Size:32, _/binary>>) ->
    Size + 8;
pending_size(_) ->
    undefined.

-spec decode(binary()) -> {[frame()], binary()}.
decode(Stream) ->
    assert_protocol_version(Stream),
    decode(Stream, []).
decode(<<_ProtoVsn, Flags, ID:16/signed, Op, Size:32, Body:Size/binary, Rest/binary>>, Acc) ->
    {Warnings, Body2} = maybe_decode_warning(Flags, Body),
    Frame = #frame{id = ID, flags = decode_flags(Flags), opcode = Op, body = Body2, warnings = Warnings},
    decode(Rest, [Frame|Acc]);
decode(Stream, Acc) ->
    {lists:reverse(Acc), Stream}.

assert_protocol_version(<<?RESP_VSN3, _/binary>>) -> ok;
assert_protocol_version(<<?RESP_VSN4, _/binary>>) -> ok;
assert_protocol_version(<<>>)                     -> ok.

maybe_decode_warning(Flags, Body) when Flags band ?WARNING =:= ?WARNING ->
    %% Warning flag set
    seestar_types:decode_string_list(Body);
maybe_decode_warning(_Flags, Body) ->
    {[], Body}.

decode_flags(Byte) ->
    F = fun(Mask, Flags) when Byte band Mask =:= Mask ->
            [decode_flag(Mask)|Flags];
           (_Mask, Flags) ->
            Flags
        end,
    lists:foldl(F, [], [?COMPRESSION, ?TRACING, ?WARNING]).

decode_flag(?COMPRESSION) -> compression;
decode_flag(?TRACING)     -> tracing;
decode_flag(?WARNING)     -> warning.
