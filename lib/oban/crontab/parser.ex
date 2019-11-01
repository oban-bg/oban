# Generated from lib/oban/crontab/parser.ex.exs, do not edit.
# Generated at 2019-11-01 18:29:29Z.

defmodule Oban.Crontab.Parser do
  @moduledoc false

  @doc """
  Parses the given `binary` as cron.

  Returns `{:ok, [token], rest, context, position, byte_offset}` or
  `{:error, reason, rest, context, line, byte_offset}` where `position`
  describes the location of the cron (start position) as {line, column_on_line}.

  ## Options

    * `:line` - the initial line, defaults to 1
    * `:byte_offset` - the initial byte offset, defaults to 0
    * `:context` - the initial context value. It will be converted
      to a map

  """
  @spec cron(binary, keyword) ::
          {:ok, [term], rest, context, line, byte_offset}
          | {:error, reason, rest, context, line, byte_offset}
        when line: {pos_integer, byte_offset},
             byte_offset: pos_integer,
             rest: binary,
             reason: String.t(),
             context: map()
  def cron(binary, opts \\ []) when is_binary(binary) do
    line = Keyword.get(opts, :line, 1)
    offset = Keyword.get(opts, :byte_offset, 0)
    context = Map.new(Keyword.get(opts, :context, []))

    case(cron__0(binary, [], [], context, {line, offset}, offset)) do
      {:ok, acc, rest, context, line, offset} ->
        {:ok, :lists.reverse(acc), rest, context, line, offset}

      {:error, _, _, _, _, _} = error ->
        error
    end
  end

  defp cron__0(rest, acc, stack, context, line, offset) do
    cron__1(rest, [], [acc | stack], context, line, offset)
  end

  defp cron__1(rest, acc, stack, context, line, offset) do
    cron__32(rest, [], [{rest, context, line, offset}, acc | stack], context, line, offset)
  end

  defp cron__3(<<",", rest::binary>>, acc, stack, context, comb__line, comb__offset) do
    cron__4(rest, [] ++ acc, stack, context, comb__line, comb__offset + 1)
  end

  defp cron__3(rest, _acc, _stack, context, line, offset) do
    {:error,
     "expected byte in the range ?0..?9, followed by byte in the range ?0..?9, followed by string \"-\", followed by byte in the range ?0..?9, followed by byte in the range ?0..?9 or byte in the range ?0..?9, followed by byte in the range ?0..?9 or string \"*/\", followed by byte in the range ?0..?9, followed by byte in the range ?0..?9 or string \"*\" or string \",\"",
     rest, context, line, offset}
  end

  defp cron__4(rest, acc, [_, previous_acc | stack], context, line, offset) do
    cron__2(rest, acc ++ previous_acc, stack, context, line, offset)
  end

  defp cron__5(_, _, [{rest, context, line, offset} | _] = stack, _, _, _) do
    cron__3(rest, [], stack, context, line, offset)
  end

  defp cron__6(<<"*", rest::binary>>, acc, stack, context, comb__line, comb__offset) do
    cron__7(rest, [wild: "*"] ++ acc, stack, context, comb__line, comb__offset + 1)
  end

  defp cron__6(rest, acc, stack, context, line, offset) do
    cron__5(rest, acc, stack, context, line, offset)
  end

  defp cron__7(rest, acc, [_, previous_acc | stack], context, line, offset) do
    cron__2(rest, acc ++ previous_acc, stack, context, line, offset)
  end

  defp cron__8(_, _, [{rest, context, line, offset} | _] = stack, _, _, _) do
    cron__6(rest, [], stack, context, line, offset)
  end

  defp cron__9(rest, acc, stack, context, line, offset) do
    cron__10(rest, [], [acc | stack], context, line, offset)
  end

  defp cron__10(<<"*/", rest::binary>>, acc, stack, context, comb__line, comb__offset) do
    cron__11(rest, [] ++ acc, stack, context, comb__line, comb__offset + 2)
  end

  defp cron__10(rest, _acc, stack, context, line, offset) do
    [acc | stack] = stack
    cron__8(rest, acc, stack, context, line, offset)
  end

  defp cron__11(rest, acc, stack, context, line, offset) do
    cron__12(rest, [], [acc | stack], context, line, offset)
  end

  defp cron__12(<<x0::integer, rest::binary>>, acc, stack, context, comb__line, comb__offset)
       when x0 >= 48 and x0 <= 57 do
    cron__13(rest, [x0 - 48] ++ acc, stack, context, comb__line, comb__offset + 1)
  end

  defp cron__12(rest, _acc, stack, context, line, offset) do
    [_, acc | stack] = stack
    cron__8(rest, acc, stack, context, line, offset)
  end

  defp cron__13(rest, acc, stack, context, line, offset) do
    cron__15(rest, acc, [1 | stack], context, line, offset)
  end

  defp cron__15(<<x0::integer, rest::binary>>, acc, stack, context, comb__line, comb__offset)
       when x0 >= 48 and x0 <= 57 do
    cron__16(rest, [x0] ++ acc, stack, context, comb__line, comb__offset + 1)
  end

  defp cron__15(rest, acc, stack, context, line, offset) do
    cron__14(rest, acc, stack, context, line, offset)
  end

  defp cron__14(rest, acc, [_ | stack], context, line, offset) do
    cron__17(rest, acc, stack, context, line, offset)
  end

  defp cron__16(rest, acc, [1 | stack], context, line, offset) do
    cron__17(rest, acc, stack, context, line, offset)
  end

  defp cron__16(rest, acc, [count | stack], context, line, offset) do
    cron__15(rest, acc, [count - 1 | stack], context, line, offset)
  end

  defp cron__17(rest, user_acc, [acc | stack], context, line, offset) do
    cron__18(
      rest,
      (
        [head | tail] = :lists.reverse(user_acc)
        [:lists.foldl(fn x, acc -> x - 48 + acc * 10 end, head, tail)]
      ) ++ acc,
      stack,
      context,
      line,
      offset
    )
  end

  defp cron__18(rest, user_acc, [acc | stack], context, line, offset) do
    cron__19(
      rest,
      [
        step:
          case(:lists.reverse(user_acc)) do
            [one] ->
              one

            many ->
              raise("unwrap_and_tag/3 expected a single token, got: #{inspect(many)}")
          end
      ] ++ acc,
      stack,
      context,
      line,
      offset
    )
  end

  defp cron__19(rest, acc, [_, previous_acc | stack], context, line, offset) do
    cron__2(rest, acc ++ previous_acc, stack, context, line, offset)
  end

  defp cron__20(_, _, [{rest, context, line, offset} | _] = stack, _, _, _) do
    cron__9(rest, [], stack, context, line, offset)
  end

  defp cron__21(rest, acc, stack, context, line, offset) do
    cron__22(rest, [], [acc | stack], context, line, offset)
  end

  defp cron__22(rest, acc, stack, context, line, offset) do
    cron__23(rest, [], [acc | stack], context, line, offset)
  end

  defp cron__23(<<x0::integer, rest::binary>>, acc, stack, context, comb__line, comb__offset)
       when x0 >= 48 and x0 <= 57 do
    cron__24(rest, [x0 - 48] ++ acc, stack, context, comb__line, comb__offset + 1)
  end

  defp cron__23(rest, _acc, stack, context, line, offset) do
    [_, acc | stack] = stack
    cron__20(rest, acc, stack, context, line, offset)
  end

  defp cron__24(rest, acc, stack, context, line, offset) do
    cron__26(rest, acc, [1 | stack], context, line, offset)
  end

  defp cron__26(<<x0::integer, rest::binary>>, acc, stack, context, comb__line, comb__offset)
       when x0 >= 48 and x0 <= 57 do
    cron__27(rest, [x0] ++ acc, stack, context, comb__line, comb__offset + 1)
  end

  defp cron__26(rest, acc, stack, context, line, offset) do
    cron__25(rest, acc, stack, context, line, offset)
  end

  defp cron__25(rest, acc, [_ | stack], context, line, offset) do
    cron__28(rest, acc, stack, context, line, offset)
  end

  defp cron__27(rest, acc, [1 | stack], context, line, offset) do
    cron__28(rest, acc, stack, context, line, offset)
  end

  defp cron__27(rest, acc, [count | stack], context, line, offset) do
    cron__26(rest, acc, [count - 1 | stack], context, line, offset)
  end

  defp cron__28(rest, user_acc, [acc | stack], context, line, offset) do
    cron__29(
      rest,
      (
        [head | tail] = :lists.reverse(user_acc)
        [:lists.foldl(fn x, acc -> x - 48 + acc * 10 end, head, tail)]
      ) ++ acc,
      stack,
      context,
      line,
      offset
    )
  end

  defp cron__29(rest, user_acc, [acc | stack], context, line, offset) do
    cron__30(
      rest,
      [
        literal:
          case(:lists.reverse(user_acc)) do
            [one] ->
              one

            many ->
              raise("unwrap_and_tag/3 expected a single token, got: #{inspect(many)}")
          end
      ] ++ acc,
      stack,
      context,
      line,
      offset
    )
  end

  defp cron__30(rest, acc, [_, previous_acc | stack], context, line, offset) do
    cron__2(rest, acc ++ previous_acc, stack, context, line, offset)
  end

  defp cron__31(_, _, [{rest, context, line, offset} | _] = stack, _, _, _) do
    cron__21(rest, [], stack, context, line, offset)
  end

  defp cron__32(rest, acc, stack, context, line, offset) do
    cron__33(rest, [], [acc | stack], context, line, offset)
  end

  defp cron__33(rest, acc, stack, context, line, offset) do
    cron__34(rest, [], [acc | stack], context, line, offset)
  end

  defp cron__34(<<x0::integer, rest::binary>>, acc, stack, context, comb__line, comb__offset)
       when x0 >= 48 and x0 <= 57 do
    cron__35(rest, [x0 - 48] ++ acc, stack, context, comb__line, comb__offset + 1)
  end

  defp cron__34(rest, _acc, stack, context, line, offset) do
    [_, acc | stack] = stack
    cron__31(rest, acc, stack, context, line, offset)
  end

  defp cron__35(rest, acc, stack, context, line, offset) do
    cron__37(rest, acc, [1 | stack], context, line, offset)
  end

  defp cron__37(<<x0::integer, rest::binary>>, acc, stack, context, comb__line, comb__offset)
       when x0 >= 48 and x0 <= 57 do
    cron__38(rest, [x0] ++ acc, stack, context, comb__line, comb__offset + 1)
  end

  defp cron__37(rest, acc, stack, context, line, offset) do
    cron__36(rest, acc, stack, context, line, offset)
  end

  defp cron__36(rest, acc, [_ | stack], context, line, offset) do
    cron__39(rest, acc, stack, context, line, offset)
  end

  defp cron__38(rest, acc, [1 | stack], context, line, offset) do
    cron__39(rest, acc, stack, context, line, offset)
  end

  defp cron__38(rest, acc, [count | stack], context, line, offset) do
    cron__37(rest, acc, [count - 1 | stack], context, line, offset)
  end

  defp cron__39(rest, user_acc, [acc | stack], context, line, offset) do
    cron__40(
      rest,
      (
        [head | tail] = :lists.reverse(user_acc)
        [:lists.foldl(fn x, acc -> x - 48 + acc * 10 end, head, tail)]
      ) ++ acc,
      stack,
      context,
      line,
      offset
    )
  end

  defp cron__40(<<"-", rest::binary>>, acc, stack, context, comb__line, comb__offset) do
    cron__41(rest, [] ++ acc, stack, context, comb__line, comb__offset + 1)
  end

  defp cron__40(rest, _acc, stack, context, line, offset) do
    [acc | stack] = stack
    cron__31(rest, acc, stack, context, line, offset)
  end

  defp cron__41(rest, acc, stack, context, line, offset) do
    cron__42(rest, [], [acc | stack], context, line, offset)
  end

  defp cron__42(<<x0::integer, rest::binary>>, acc, stack, context, comb__line, comb__offset)
       when x0 >= 48 and x0 <= 57 do
    cron__43(rest, [x0 - 48] ++ acc, stack, context, comb__line, comb__offset + 1)
  end

  defp cron__42(rest, _acc, stack, context, line, offset) do
    [_, acc | stack] = stack
    cron__31(rest, acc, stack, context, line, offset)
  end

  defp cron__43(rest, acc, stack, context, line, offset) do
    cron__45(rest, acc, [1 | stack], context, line, offset)
  end

  defp cron__45(<<x0::integer, rest::binary>>, acc, stack, context, comb__line, comb__offset)
       when x0 >= 48 and x0 <= 57 do
    cron__46(rest, [x0] ++ acc, stack, context, comb__line, comb__offset + 1)
  end

  defp cron__45(rest, acc, stack, context, line, offset) do
    cron__44(rest, acc, stack, context, line, offset)
  end

  defp cron__44(rest, acc, [_ | stack], context, line, offset) do
    cron__47(rest, acc, stack, context, line, offset)
  end

  defp cron__46(rest, acc, [1 | stack], context, line, offset) do
    cron__47(rest, acc, stack, context, line, offset)
  end

  defp cron__46(rest, acc, [count | stack], context, line, offset) do
    cron__45(rest, acc, [count - 1 | stack], context, line, offset)
  end

  defp cron__47(rest, user_acc, [acc | stack], context, line, offset) do
    cron__48(
      rest,
      (
        [head | tail] = :lists.reverse(user_acc)
        [:lists.foldl(fn x, acc -> x - 48 + acc * 10 end, head, tail)]
      ) ++ acc,
      stack,
      context,
      line,
      offset
    )
  end

  defp cron__48(rest, user_acc, [acc | stack], context, line, offset) do
    cron__49(rest, [range: :lists.reverse(user_acc)] ++ acc, stack, context, line, offset)
  end

  defp cron__49(rest, acc, [_, previous_acc | stack], context, line, offset) do
    cron__2(rest, acc ++ previous_acc, stack, context, line, offset)
  end

  defp cron__2(rest, acc, stack, context, line, offset) do
    cron__51(rest, [], [{rest, acc, context, line, offset} | stack], context, line, offset)
  end

  defp cron__51(rest, acc, stack, context, line, offset) do
    cron__82(rest, [], [{rest, context, line, offset}, acc | stack], context, line, offset)
  end

  defp cron__53(<<",", rest::binary>>, acc, stack, context, comb__line, comb__offset) do
    cron__54(rest, [] ++ acc, stack, context, comb__line, comb__offset + 1)
  end

  defp cron__53(rest, _acc, stack, context, line, offset) do
    [_, acc | stack] = stack
    cron__50(rest, acc, stack, context, line, offset)
  end

  defp cron__54(rest, acc, [_, previous_acc | stack], context, line, offset) do
    cron__52(rest, acc ++ previous_acc, stack, context, line, offset)
  end

  defp cron__55(_, _, [{rest, context, line, offset} | _] = stack, _, _, _) do
    cron__53(rest, [], stack, context, line, offset)
  end

  defp cron__56(<<"*", rest::binary>>, acc, stack, context, comb__line, comb__offset) do
    cron__57(rest, [wild: "*"] ++ acc, stack, context, comb__line, comb__offset + 1)
  end

  defp cron__56(rest, acc, stack, context, line, offset) do
    cron__55(rest, acc, stack, context, line, offset)
  end

  defp cron__57(rest, acc, [_, previous_acc | stack], context, line, offset) do
    cron__52(rest, acc ++ previous_acc, stack, context, line, offset)
  end

  defp cron__58(_, _, [{rest, context, line, offset} | _] = stack, _, _, _) do
    cron__56(rest, [], stack, context, line, offset)
  end

  defp cron__59(rest, acc, stack, context, line, offset) do
    cron__60(rest, [], [acc | stack], context, line, offset)
  end

  defp cron__60(<<"*/", rest::binary>>, acc, stack, context, comb__line, comb__offset) do
    cron__61(rest, [] ++ acc, stack, context, comb__line, comb__offset + 2)
  end

  defp cron__60(rest, _acc, stack, context, line, offset) do
    [acc | stack] = stack
    cron__58(rest, acc, stack, context, line, offset)
  end

  defp cron__61(rest, acc, stack, context, line, offset) do
    cron__62(rest, [], [acc | stack], context, line, offset)
  end

  defp cron__62(<<x0::integer, rest::binary>>, acc, stack, context, comb__line, comb__offset)
       when x0 >= 48 and x0 <= 57 do
    cron__63(rest, [x0 - 48] ++ acc, stack, context, comb__line, comb__offset + 1)
  end

  defp cron__62(rest, _acc, stack, context, line, offset) do
    [_, acc | stack] = stack
    cron__58(rest, acc, stack, context, line, offset)
  end

  defp cron__63(rest, acc, stack, context, line, offset) do
    cron__65(rest, acc, [1 | stack], context, line, offset)
  end

  defp cron__65(<<x0::integer, rest::binary>>, acc, stack, context, comb__line, comb__offset)
       when x0 >= 48 and x0 <= 57 do
    cron__66(rest, [x0] ++ acc, stack, context, comb__line, comb__offset + 1)
  end

  defp cron__65(rest, acc, stack, context, line, offset) do
    cron__64(rest, acc, stack, context, line, offset)
  end

  defp cron__64(rest, acc, [_ | stack], context, line, offset) do
    cron__67(rest, acc, stack, context, line, offset)
  end

  defp cron__66(rest, acc, [1 | stack], context, line, offset) do
    cron__67(rest, acc, stack, context, line, offset)
  end

  defp cron__66(rest, acc, [count | stack], context, line, offset) do
    cron__65(rest, acc, [count - 1 | stack], context, line, offset)
  end

  defp cron__67(rest, user_acc, [acc | stack], context, line, offset) do
    cron__68(
      rest,
      (
        [head | tail] = :lists.reverse(user_acc)
        [:lists.foldl(fn x, acc -> x - 48 + acc * 10 end, head, tail)]
      ) ++ acc,
      stack,
      context,
      line,
      offset
    )
  end

  defp cron__68(rest, user_acc, [acc | stack], context, line, offset) do
    cron__69(
      rest,
      [
        step:
          case(:lists.reverse(user_acc)) do
            [one] ->
              one

            many ->
              raise("unwrap_and_tag/3 expected a single token, got: #{inspect(many)}")
          end
      ] ++ acc,
      stack,
      context,
      line,
      offset
    )
  end

  defp cron__69(rest, acc, [_, previous_acc | stack], context, line, offset) do
    cron__52(rest, acc ++ previous_acc, stack, context, line, offset)
  end

  defp cron__70(_, _, [{rest, context, line, offset} | _] = stack, _, _, _) do
    cron__59(rest, [], stack, context, line, offset)
  end

  defp cron__71(rest, acc, stack, context, line, offset) do
    cron__72(rest, [], [acc | stack], context, line, offset)
  end

  defp cron__72(rest, acc, stack, context, line, offset) do
    cron__73(rest, [], [acc | stack], context, line, offset)
  end

  defp cron__73(<<x0::integer, rest::binary>>, acc, stack, context, comb__line, comb__offset)
       when x0 >= 48 and x0 <= 57 do
    cron__74(rest, [x0 - 48] ++ acc, stack, context, comb__line, comb__offset + 1)
  end

  defp cron__73(rest, _acc, stack, context, line, offset) do
    [_, acc | stack] = stack
    cron__70(rest, acc, stack, context, line, offset)
  end

  defp cron__74(rest, acc, stack, context, line, offset) do
    cron__76(rest, acc, [1 | stack], context, line, offset)
  end

  defp cron__76(<<x0::integer, rest::binary>>, acc, stack, context, comb__line, comb__offset)
       when x0 >= 48 and x0 <= 57 do
    cron__77(rest, [x0] ++ acc, stack, context, comb__line, comb__offset + 1)
  end

  defp cron__76(rest, acc, stack, context, line, offset) do
    cron__75(rest, acc, stack, context, line, offset)
  end

  defp cron__75(rest, acc, [_ | stack], context, line, offset) do
    cron__78(rest, acc, stack, context, line, offset)
  end

  defp cron__77(rest, acc, [1 | stack], context, line, offset) do
    cron__78(rest, acc, stack, context, line, offset)
  end

  defp cron__77(rest, acc, [count | stack], context, line, offset) do
    cron__76(rest, acc, [count - 1 | stack], context, line, offset)
  end

  defp cron__78(rest, user_acc, [acc | stack], context, line, offset) do
    cron__79(
      rest,
      (
        [head | tail] = :lists.reverse(user_acc)
        [:lists.foldl(fn x, acc -> x - 48 + acc * 10 end, head, tail)]
      ) ++ acc,
      stack,
      context,
      line,
      offset
    )
  end

  defp cron__79(rest, user_acc, [acc | stack], context, line, offset) do
    cron__80(
      rest,
      [
        literal:
          case(:lists.reverse(user_acc)) do
            [one] ->
              one

            many ->
              raise("unwrap_and_tag/3 expected a single token, got: #{inspect(many)}")
          end
      ] ++ acc,
      stack,
      context,
      line,
      offset
    )
  end

  defp cron__80(rest, acc, [_, previous_acc | stack], context, line, offset) do
    cron__52(rest, acc ++ previous_acc, stack, context, line, offset)
  end

  defp cron__81(_, _, [{rest, context, line, offset} | _] = stack, _, _, _) do
    cron__71(rest, [], stack, context, line, offset)
  end

  defp cron__82(rest, acc, stack, context, line, offset) do
    cron__83(rest, [], [acc | stack], context, line, offset)
  end

  defp cron__83(rest, acc, stack, context, line, offset) do
    cron__84(rest, [], [acc | stack], context, line, offset)
  end

  defp cron__84(<<x0::integer, rest::binary>>, acc, stack, context, comb__line, comb__offset)
       when x0 >= 48 and x0 <= 57 do
    cron__85(rest, [x0 - 48] ++ acc, stack, context, comb__line, comb__offset + 1)
  end

  defp cron__84(rest, _acc, stack, context, line, offset) do
    [_, acc | stack] = stack
    cron__81(rest, acc, stack, context, line, offset)
  end

  defp cron__85(rest, acc, stack, context, line, offset) do
    cron__87(rest, acc, [1 | stack], context, line, offset)
  end

  defp cron__87(<<x0::integer, rest::binary>>, acc, stack, context, comb__line, comb__offset)
       when x0 >= 48 and x0 <= 57 do
    cron__88(rest, [x0] ++ acc, stack, context, comb__line, comb__offset + 1)
  end

  defp cron__87(rest, acc, stack, context, line, offset) do
    cron__86(rest, acc, stack, context, line, offset)
  end

  defp cron__86(rest, acc, [_ | stack], context, line, offset) do
    cron__89(rest, acc, stack, context, line, offset)
  end

  defp cron__88(rest, acc, [1 | stack], context, line, offset) do
    cron__89(rest, acc, stack, context, line, offset)
  end

  defp cron__88(rest, acc, [count | stack], context, line, offset) do
    cron__87(rest, acc, [count - 1 | stack], context, line, offset)
  end

  defp cron__89(rest, user_acc, [acc | stack], context, line, offset) do
    cron__90(
      rest,
      (
        [head | tail] = :lists.reverse(user_acc)
        [:lists.foldl(fn x, acc -> x - 48 + acc * 10 end, head, tail)]
      ) ++ acc,
      stack,
      context,
      line,
      offset
    )
  end

  defp cron__90(<<"-", rest::binary>>, acc, stack, context, comb__line, comb__offset) do
    cron__91(rest, [] ++ acc, stack, context, comb__line, comb__offset + 1)
  end

  defp cron__90(rest, _acc, stack, context, line, offset) do
    [acc | stack] = stack
    cron__81(rest, acc, stack, context, line, offset)
  end

  defp cron__91(rest, acc, stack, context, line, offset) do
    cron__92(rest, [], [acc | stack], context, line, offset)
  end

  defp cron__92(<<x0::integer, rest::binary>>, acc, stack, context, comb__line, comb__offset)
       when x0 >= 48 and x0 <= 57 do
    cron__93(rest, [x0 - 48] ++ acc, stack, context, comb__line, comb__offset + 1)
  end

  defp cron__92(rest, _acc, stack, context, line, offset) do
    [_, acc | stack] = stack
    cron__81(rest, acc, stack, context, line, offset)
  end

  defp cron__93(rest, acc, stack, context, line, offset) do
    cron__95(rest, acc, [1 | stack], context, line, offset)
  end

  defp cron__95(<<x0::integer, rest::binary>>, acc, stack, context, comb__line, comb__offset)
       when x0 >= 48 and x0 <= 57 do
    cron__96(rest, [x0] ++ acc, stack, context, comb__line, comb__offset + 1)
  end

  defp cron__95(rest, acc, stack, context, line, offset) do
    cron__94(rest, acc, stack, context, line, offset)
  end

  defp cron__94(rest, acc, [_ | stack], context, line, offset) do
    cron__97(rest, acc, stack, context, line, offset)
  end

  defp cron__96(rest, acc, [1 | stack], context, line, offset) do
    cron__97(rest, acc, stack, context, line, offset)
  end

  defp cron__96(rest, acc, [count | stack], context, line, offset) do
    cron__95(rest, acc, [count - 1 | stack], context, line, offset)
  end

  defp cron__97(rest, user_acc, [acc | stack], context, line, offset) do
    cron__98(
      rest,
      (
        [head | tail] = :lists.reverse(user_acc)
        [:lists.foldl(fn x, acc -> x - 48 + acc * 10 end, head, tail)]
      ) ++ acc,
      stack,
      context,
      line,
      offset
    )
  end

  defp cron__98(rest, user_acc, [acc | stack], context, line, offset) do
    cron__99(rest, [range: :lists.reverse(user_acc)] ++ acc, stack, context, line, offset)
  end

  defp cron__99(rest, acc, [_, previous_acc | stack], context, line, offset) do
    cron__52(rest, acc ++ previous_acc, stack, context, line, offset)
  end

  defp cron__50(_, _, [{rest, acc, context, line, offset} | stack], _, _, _) do
    cron__100(rest, acc, stack, context, line, offset)
  end

  defp cron__52(
         inner_rest,
         inner_acc,
         [{rest, acc, context, line, offset} | stack],
         inner_context,
         inner_line,
         inner_offset
       ) do
    _ = {rest, acc, context, line, offset}

    cron__51(
      inner_rest,
      [],
      [{inner_rest, inner_acc ++ acc, inner_context, inner_line, inner_offset} | stack],
      inner_context,
      inner_line,
      inner_offset
    )
  end

  defp cron__100(rest, user_acc, [acc | stack], context, line, offset) do
    cron__101(rest, [minutes: :lists.reverse(user_acc)] ++ acc, stack, context, line, offset)
  end

  defp cron__101(<<" ", rest::binary>>, acc, stack, context, comb__line, comb__offset) do
    cron__102(rest, [] ++ acc, stack, context, comb__line, comb__offset + 1)
  end

  defp cron__101(rest, _acc, _stack, context, line, offset) do
    {:error, "expected string \" \"", rest, context, line, offset}
  end

  defp cron__102(rest, acc, stack, context, line, offset) do
    cron__103(rest, [], [acc | stack], context, line, offset)
  end

  defp cron__103(rest, acc, stack, context, line, offset) do
    cron__134(rest, [], [{rest, context, line, offset}, acc | stack], context, line, offset)
  end

  defp cron__105(<<",", rest::binary>>, acc, stack, context, comb__line, comb__offset) do
    cron__106(rest, [] ++ acc, stack, context, comb__line, comb__offset + 1)
  end

  defp cron__105(rest, _acc, _stack, context, line, offset) do
    {:error,
     "expected byte in the range ?0..?9, followed by byte in the range ?0..?9, followed by string \"-\", followed by byte in the range ?0..?9, followed by byte in the range ?0..?9 or byte in the range ?0..?9, followed by byte in the range ?0..?9 or string \"*/\", followed by byte in the range ?0..?9, followed by byte in the range ?0..?9 or string \"*\" or string \",\"",
     rest, context, line, offset}
  end

  defp cron__106(rest, acc, [_, previous_acc | stack], context, line, offset) do
    cron__104(rest, acc ++ previous_acc, stack, context, line, offset)
  end

  defp cron__107(_, _, [{rest, context, line, offset} | _] = stack, _, _, _) do
    cron__105(rest, [], stack, context, line, offset)
  end

  defp cron__108(<<"*", rest::binary>>, acc, stack, context, comb__line, comb__offset) do
    cron__109(rest, [wild: "*"] ++ acc, stack, context, comb__line, comb__offset + 1)
  end

  defp cron__108(rest, acc, stack, context, line, offset) do
    cron__107(rest, acc, stack, context, line, offset)
  end

  defp cron__109(rest, acc, [_, previous_acc | stack], context, line, offset) do
    cron__104(rest, acc ++ previous_acc, stack, context, line, offset)
  end

  defp cron__110(_, _, [{rest, context, line, offset} | _] = stack, _, _, _) do
    cron__108(rest, [], stack, context, line, offset)
  end

  defp cron__111(rest, acc, stack, context, line, offset) do
    cron__112(rest, [], [acc | stack], context, line, offset)
  end

  defp cron__112(<<"*/", rest::binary>>, acc, stack, context, comb__line, comb__offset) do
    cron__113(rest, [] ++ acc, stack, context, comb__line, comb__offset + 2)
  end

  defp cron__112(rest, _acc, stack, context, line, offset) do
    [acc | stack] = stack
    cron__110(rest, acc, stack, context, line, offset)
  end

  defp cron__113(rest, acc, stack, context, line, offset) do
    cron__114(rest, [], [acc | stack], context, line, offset)
  end

  defp cron__114(<<x0::integer, rest::binary>>, acc, stack, context, comb__line, comb__offset)
       when x0 >= 48 and x0 <= 57 do
    cron__115(rest, [x0 - 48] ++ acc, stack, context, comb__line, comb__offset + 1)
  end

  defp cron__114(rest, _acc, stack, context, line, offset) do
    [_, acc | stack] = stack
    cron__110(rest, acc, stack, context, line, offset)
  end

  defp cron__115(rest, acc, stack, context, line, offset) do
    cron__117(rest, acc, [1 | stack], context, line, offset)
  end

  defp cron__117(<<x0::integer, rest::binary>>, acc, stack, context, comb__line, comb__offset)
       when x0 >= 48 and x0 <= 57 do
    cron__118(rest, [x0] ++ acc, stack, context, comb__line, comb__offset + 1)
  end

  defp cron__117(rest, acc, stack, context, line, offset) do
    cron__116(rest, acc, stack, context, line, offset)
  end

  defp cron__116(rest, acc, [_ | stack], context, line, offset) do
    cron__119(rest, acc, stack, context, line, offset)
  end

  defp cron__118(rest, acc, [1 | stack], context, line, offset) do
    cron__119(rest, acc, stack, context, line, offset)
  end

  defp cron__118(rest, acc, [count | stack], context, line, offset) do
    cron__117(rest, acc, [count - 1 | stack], context, line, offset)
  end

  defp cron__119(rest, user_acc, [acc | stack], context, line, offset) do
    cron__120(
      rest,
      (
        [head | tail] = :lists.reverse(user_acc)
        [:lists.foldl(fn x, acc -> x - 48 + acc * 10 end, head, tail)]
      ) ++ acc,
      stack,
      context,
      line,
      offset
    )
  end

  defp cron__120(rest, user_acc, [acc | stack], context, line, offset) do
    cron__121(
      rest,
      [
        step:
          case(:lists.reverse(user_acc)) do
            [one] ->
              one

            many ->
              raise("unwrap_and_tag/3 expected a single token, got: #{inspect(many)}")
          end
      ] ++ acc,
      stack,
      context,
      line,
      offset
    )
  end

  defp cron__121(rest, acc, [_, previous_acc | stack], context, line, offset) do
    cron__104(rest, acc ++ previous_acc, stack, context, line, offset)
  end

  defp cron__122(_, _, [{rest, context, line, offset} | _] = stack, _, _, _) do
    cron__111(rest, [], stack, context, line, offset)
  end

  defp cron__123(rest, acc, stack, context, line, offset) do
    cron__124(rest, [], [acc | stack], context, line, offset)
  end

  defp cron__124(rest, acc, stack, context, line, offset) do
    cron__125(rest, [], [acc | stack], context, line, offset)
  end

  defp cron__125(<<x0::integer, rest::binary>>, acc, stack, context, comb__line, comb__offset)
       when x0 >= 48 and x0 <= 57 do
    cron__126(rest, [x0 - 48] ++ acc, stack, context, comb__line, comb__offset + 1)
  end

  defp cron__125(rest, _acc, stack, context, line, offset) do
    [_, acc | stack] = stack
    cron__122(rest, acc, stack, context, line, offset)
  end

  defp cron__126(rest, acc, stack, context, line, offset) do
    cron__128(rest, acc, [1 | stack], context, line, offset)
  end

  defp cron__128(<<x0::integer, rest::binary>>, acc, stack, context, comb__line, comb__offset)
       when x0 >= 48 and x0 <= 57 do
    cron__129(rest, [x0] ++ acc, stack, context, comb__line, comb__offset + 1)
  end

  defp cron__128(rest, acc, stack, context, line, offset) do
    cron__127(rest, acc, stack, context, line, offset)
  end

  defp cron__127(rest, acc, [_ | stack], context, line, offset) do
    cron__130(rest, acc, stack, context, line, offset)
  end

  defp cron__129(rest, acc, [1 | stack], context, line, offset) do
    cron__130(rest, acc, stack, context, line, offset)
  end

  defp cron__129(rest, acc, [count | stack], context, line, offset) do
    cron__128(rest, acc, [count - 1 | stack], context, line, offset)
  end

  defp cron__130(rest, user_acc, [acc | stack], context, line, offset) do
    cron__131(
      rest,
      (
        [head | tail] = :lists.reverse(user_acc)
        [:lists.foldl(fn x, acc -> x - 48 + acc * 10 end, head, tail)]
      ) ++ acc,
      stack,
      context,
      line,
      offset
    )
  end

  defp cron__131(rest, user_acc, [acc | stack], context, line, offset) do
    cron__132(
      rest,
      [
        literal:
          case(:lists.reverse(user_acc)) do
            [one] ->
              one

            many ->
              raise("unwrap_and_tag/3 expected a single token, got: #{inspect(many)}")
          end
      ] ++ acc,
      stack,
      context,
      line,
      offset
    )
  end

  defp cron__132(rest, acc, [_, previous_acc | stack], context, line, offset) do
    cron__104(rest, acc ++ previous_acc, stack, context, line, offset)
  end

  defp cron__133(_, _, [{rest, context, line, offset} | _] = stack, _, _, _) do
    cron__123(rest, [], stack, context, line, offset)
  end

  defp cron__134(rest, acc, stack, context, line, offset) do
    cron__135(rest, [], [acc | stack], context, line, offset)
  end

  defp cron__135(rest, acc, stack, context, line, offset) do
    cron__136(rest, [], [acc | stack], context, line, offset)
  end

  defp cron__136(<<x0::integer, rest::binary>>, acc, stack, context, comb__line, comb__offset)
       when x0 >= 48 and x0 <= 57 do
    cron__137(rest, [x0 - 48] ++ acc, stack, context, comb__line, comb__offset + 1)
  end

  defp cron__136(rest, _acc, stack, context, line, offset) do
    [_, acc | stack] = stack
    cron__133(rest, acc, stack, context, line, offset)
  end

  defp cron__137(rest, acc, stack, context, line, offset) do
    cron__139(rest, acc, [1 | stack], context, line, offset)
  end

  defp cron__139(<<x0::integer, rest::binary>>, acc, stack, context, comb__line, comb__offset)
       when x0 >= 48 and x0 <= 57 do
    cron__140(rest, [x0] ++ acc, stack, context, comb__line, comb__offset + 1)
  end

  defp cron__139(rest, acc, stack, context, line, offset) do
    cron__138(rest, acc, stack, context, line, offset)
  end

  defp cron__138(rest, acc, [_ | stack], context, line, offset) do
    cron__141(rest, acc, stack, context, line, offset)
  end

  defp cron__140(rest, acc, [1 | stack], context, line, offset) do
    cron__141(rest, acc, stack, context, line, offset)
  end

  defp cron__140(rest, acc, [count | stack], context, line, offset) do
    cron__139(rest, acc, [count - 1 | stack], context, line, offset)
  end

  defp cron__141(rest, user_acc, [acc | stack], context, line, offset) do
    cron__142(
      rest,
      (
        [head | tail] = :lists.reverse(user_acc)
        [:lists.foldl(fn x, acc -> x - 48 + acc * 10 end, head, tail)]
      ) ++ acc,
      stack,
      context,
      line,
      offset
    )
  end

  defp cron__142(<<"-", rest::binary>>, acc, stack, context, comb__line, comb__offset) do
    cron__143(rest, [] ++ acc, stack, context, comb__line, comb__offset + 1)
  end

  defp cron__142(rest, _acc, stack, context, line, offset) do
    [acc | stack] = stack
    cron__133(rest, acc, stack, context, line, offset)
  end

  defp cron__143(rest, acc, stack, context, line, offset) do
    cron__144(rest, [], [acc | stack], context, line, offset)
  end

  defp cron__144(<<x0::integer, rest::binary>>, acc, stack, context, comb__line, comb__offset)
       when x0 >= 48 and x0 <= 57 do
    cron__145(rest, [x0 - 48] ++ acc, stack, context, comb__line, comb__offset + 1)
  end

  defp cron__144(rest, _acc, stack, context, line, offset) do
    [_, acc | stack] = stack
    cron__133(rest, acc, stack, context, line, offset)
  end

  defp cron__145(rest, acc, stack, context, line, offset) do
    cron__147(rest, acc, [1 | stack], context, line, offset)
  end

  defp cron__147(<<x0::integer, rest::binary>>, acc, stack, context, comb__line, comb__offset)
       when x0 >= 48 and x0 <= 57 do
    cron__148(rest, [x0] ++ acc, stack, context, comb__line, comb__offset + 1)
  end

  defp cron__147(rest, acc, stack, context, line, offset) do
    cron__146(rest, acc, stack, context, line, offset)
  end

  defp cron__146(rest, acc, [_ | stack], context, line, offset) do
    cron__149(rest, acc, stack, context, line, offset)
  end

  defp cron__148(rest, acc, [1 | stack], context, line, offset) do
    cron__149(rest, acc, stack, context, line, offset)
  end

  defp cron__148(rest, acc, [count | stack], context, line, offset) do
    cron__147(rest, acc, [count - 1 | stack], context, line, offset)
  end

  defp cron__149(rest, user_acc, [acc | stack], context, line, offset) do
    cron__150(
      rest,
      (
        [head | tail] = :lists.reverse(user_acc)
        [:lists.foldl(fn x, acc -> x - 48 + acc * 10 end, head, tail)]
      ) ++ acc,
      stack,
      context,
      line,
      offset
    )
  end

  defp cron__150(rest, user_acc, [acc | stack], context, line, offset) do
    cron__151(rest, [range: :lists.reverse(user_acc)] ++ acc, stack, context, line, offset)
  end

  defp cron__151(rest, acc, [_, previous_acc | stack], context, line, offset) do
    cron__104(rest, acc ++ previous_acc, stack, context, line, offset)
  end

  defp cron__104(rest, acc, stack, context, line, offset) do
    cron__153(rest, [], [{rest, acc, context, line, offset} | stack], context, line, offset)
  end

  defp cron__153(rest, acc, stack, context, line, offset) do
    cron__184(rest, [], [{rest, context, line, offset}, acc | stack], context, line, offset)
  end

  defp cron__155(<<",", rest::binary>>, acc, stack, context, comb__line, comb__offset) do
    cron__156(rest, [] ++ acc, stack, context, comb__line, comb__offset + 1)
  end

  defp cron__155(rest, _acc, stack, context, line, offset) do
    [_, acc | stack] = stack
    cron__152(rest, acc, stack, context, line, offset)
  end

  defp cron__156(rest, acc, [_, previous_acc | stack], context, line, offset) do
    cron__154(rest, acc ++ previous_acc, stack, context, line, offset)
  end

  defp cron__157(_, _, [{rest, context, line, offset} | _] = stack, _, _, _) do
    cron__155(rest, [], stack, context, line, offset)
  end

  defp cron__158(<<"*", rest::binary>>, acc, stack, context, comb__line, comb__offset) do
    cron__159(rest, [wild: "*"] ++ acc, stack, context, comb__line, comb__offset + 1)
  end

  defp cron__158(rest, acc, stack, context, line, offset) do
    cron__157(rest, acc, stack, context, line, offset)
  end

  defp cron__159(rest, acc, [_, previous_acc | stack], context, line, offset) do
    cron__154(rest, acc ++ previous_acc, stack, context, line, offset)
  end

  defp cron__160(_, _, [{rest, context, line, offset} | _] = stack, _, _, _) do
    cron__158(rest, [], stack, context, line, offset)
  end

  defp cron__161(rest, acc, stack, context, line, offset) do
    cron__162(rest, [], [acc | stack], context, line, offset)
  end

  defp cron__162(<<"*/", rest::binary>>, acc, stack, context, comb__line, comb__offset) do
    cron__163(rest, [] ++ acc, stack, context, comb__line, comb__offset + 2)
  end

  defp cron__162(rest, _acc, stack, context, line, offset) do
    [acc | stack] = stack
    cron__160(rest, acc, stack, context, line, offset)
  end

  defp cron__163(rest, acc, stack, context, line, offset) do
    cron__164(rest, [], [acc | stack], context, line, offset)
  end

  defp cron__164(<<x0::integer, rest::binary>>, acc, stack, context, comb__line, comb__offset)
       when x0 >= 48 and x0 <= 57 do
    cron__165(rest, [x0 - 48] ++ acc, stack, context, comb__line, comb__offset + 1)
  end

  defp cron__164(rest, _acc, stack, context, line, offset) do
    [_, acc | stack] = stack
    cron__160(rest, acc, stack, context, line, offset)
  end

  defp cron__165(rest, acc, stack, context, line, offset) do
    cron__167(rest, acc, [1 | stack], context, line, offset)
  end

  defp cron__167(<<x0::integer, rest::binary>>, acc, stack, context, comb__line, comb__offset)
       when x0 >= 48 and x0 <= 57 do
    cron__168(rest, [x0] ++ acc, stack, context, comb__line, comb__offset + 1)
  end

  defp cron__167(rest, acc, stack, context, line, offset) do
    cron__166(rest, acc, stack, context, line, offset)
  end

  defp cron__166(rest, acc, [_ | stack], context, line, offset) do
    cron__169(rest, acc, stack, context, line, offset)
  end

  defp cron__168(rest, acc, [1 | stack], context, line, offset) do
    cron__169(rest, acc, stack, context, line, offset)
  end

  defp cron__168(rest, acc, [count | stack], context, line, offset) do
    cron__167(rest, acc, [count - 1 | stack], context, line, offset)
  end

  defp cron__169(rest, user_acc, [acc | stack], context, line, offset) do
    cron__170(
      rest,
      (
        [head | tail] = :lists.reverse(user_acc)
        [:lists.foldl(fn x, acc -> x - 48 + acc * 10 end, head, tail)]
      ) ++ acc,
      stack,
      context,
      line,
      offset
    )
  end

  defp cron__170(rest, user_acc, [acc | stack], context, line, offset) do
    cron__171(
      rest,
      [
        step:
          case(:lists.reverse(user_acc)) do
            [one] ->
              one

            many ->
              raise("unwrap_and_tag/3 expected a single token, got: #{inspect(many)}")
          end
      ] ++ acc,
      stack,
      context,
      line,
      offset
    )
  end

  defp cron__171(rest, acc, [_, previous_acc | stack], context, line, offset) do
    cron__154(rest, acc ++ previous_acc, stack, context, line, offset)
  end

  defp cron__172(_, _, [{rest, context, line, offset} | _] = stack, _, _, _) do
    cron__161(rest, [], stack, context, line, offset)
  end

  defp cron__173(rest, acc, stack, context, line, offset) do
    cron__174(rest, [], [acc | stack], context, line, offset)
  end

  defp cron__174(rest, acc, stack, context, line, offset) do
    cron__175(rest, [], [acc | stack], context, line, offset)
  end

  defp cron__175(<<x0::integer, rest::binary>>, acc, stack, context, comb__line, comb__offset)
       when x0 >= 48 and x0 <= 57 do
    cron__176(rest, [x0 - 48] ++ acc, stack, context, comb__line, comb__offset + 1)
  end

  defp cron__175(rest, _acc, stack, context, line, offset) do
    [_, acc | stack] = stack
    cron__172(rest, acc, stack, context, line, offset)
  end

  defp cron__176(rest, acc, stack, context, line, offset) do
    cron__178(rest, acc, [1 | stack], context, line, offset)
  end

  defp cron__178(<<x0::integer, rest::binary>>, acc, stack, context, comb__line, comb__offset)
       when x0 >= 48 and x0 <= 57 do
    cron__179(rest, [x0] ++ acc, stack, context, comb__line, comb__offset + 1)
  end

  defp cron__178(rest, acc, stack, context, line, offset) do
    cron__177(rest, acc, stack, context, line, offset)
  end

  defp cron__177(rest, acc, [_ | stack], context, line, offset) do
    cron__180(rest, acc, stack, context, line, offset)
  end

  defp cron__179(rest, acc, [1 | stack], context, line, offset) do
    cron__180(rest, acc, stack, context, line, offset)
  end

  defp cron__179(rest, acc, [count | stack], context, line, offset) do
    cron__178(rest, acc, [count - 1 | stack], context, line, offset)
  end

  defp cron__180(rest, user_acc, [acc | stack], context, line, offset) do
    cron__181(
      rest,
      (
        [head | tail] = :lists.reverse(user_acc)
        [:lists.foldl(fn x, acc -> x - 48 + acc * 10 end, head, tail)]
      ) ++ acc,
      stack,
      context,
      line,
      offset
    )
  end

  defp cron__181(rest, user_acc, [acc | stack], context, line, offset) do
    cron__182(
      rest,
      [
        literal:
          case(:lists.reverse(user_acc)) do
            [one] ->
              one

            many ->
              raise("unwrap_and_tag/3 expected a single token, got: #{inspect(many)}")
          end
      ] ++ acc,
      stack,
      context,
      line,
      offset
    )
  end

  defp cron__182(rest, acc, [_, previous_acc | stack], context, line, offset) do
    cron__154(rest, acc ++ previous_acc, stack, context, line, offset)
  end

  defp cron__183(_, _, [{rest, context, line, offset} | _] = stack, _, _, _) do
    cron__173(rest, [], stack, context, line, offset)
  end

  defp cron__184(rest, acc, stack, context, line, offset) do
    cron__185(rest, [], [acc | stack], context, line, offset)
  end

  defp cron__185(rest, acc, stack, context, line, offset) do
    cron__186(rest, [], [acc | stack], context, line, offset)
  end

  defp cron__186(<<x0::integer, rest::binary>>, acc, stack, context, comb__line, comb__offset)
       when x0 >= 48 and x0 <= 57 do
    cron__187(rest, [x0 - 48] ++ acc, stack, context, comb__line, comb__offset + 1)
  end

  defp cron__186(rest, _acc, stack, context, line, offset) do
    [_, acc | stack] = stack
    cron__183(rest, acc, stack, context, line, offset)
  end

  defp cron__187(rest, acc, stack, context, line, offset) do
    cron__189(rest, acc, [1 | stack], context, line, offset)
  end

  defp cron__189(<<x0::integer, rest::binary>>, acc, stack, context, comb__line, comb__offset)
       when x0 >= 48 and x0 <= 57 do
    cron__190(rest, [x0] ++ acc, stack, context, comb__line, comb__offset + 1)
  end

  defp cron__189(rest, acc, stack, context, line, offset) do
    cron__188(rest, acc, stack, context, line, offset)
  end

  defp cron__188(rest, acc, [_ | stack], context, line, offset) do
    cron__191(rest, acc, stack, context, line, offset)
  end

  defp cron__190(rest, acc, [1 | stack], context, line, offset) do
    cron__191(rest, acc, stack, context, line, offset)
  end

  defp cron__190(rest, acc, [count | stack], context, line, offset) do
    cron__189(rest, acc, [count - 1 | stack], context, line, offset)
  end

  defp cron__191(rest, user_acc, [acc | stack], context, line, offset) do
    cron__192(
      rest,
      (
        [head | tail] = :lists.reverse(user_acc)
        [:lists.foldl(fn x, acc -> x - 48 + acc * 10 end, head, tail)]
      ) ++ acc,
      stack,
      context,
      line,
      offset
    )
  end

  defp cron__192(<<"-", rest::binary>>, acc, stack, context, comb__line, comb__offset) do
    cron__193(rest, [] ++ acc, stack, context, comb__line, comb__offset + 1)
  end

  defp cron__192(rest, _acc, stack, context, line, offset) do
    [acc | stack] = stack
    cron__183(rest, acc, stack, context, line, offset)
  end

  defp cron__193(rest, acc, stack, context, line, offset) do
    cron__194(rest, [], [acc | stack], context, line, offset)
  end

  defp cron__194(<<x0::integer, rest::binary>>, acc, stack, context, comb__line, comb__offset)
       when x0 >= 48 and x0 <= 57 do
    cron__195(rest, [x0 - 48] ++ acc, stack, context, comb__line, comb__offset + 1)
  end

  defp cron__194(rest, _acc, stack, context, line, offset) do
    [_, acc | stack] = stack
    cron__183(rest, acc, stack, context, line, offset)
  end

  defp cron__195(rest, acc, stack, context, line, offset) do
    cron__197(rest, acc, [1 | stack], context, line, offset)
  end

  defp cron__197(<<x0::integer, rest::binary>>, acc, stack, context, comb__line, comb__offset)
       when x0 >= 48 and x0 <= 57 do
    cron__198(rest, [x0] ++ acc, stack, context, comb__line, comb__offset + 1)
  end

  defp cron__197(rest, acc, stack, context, line, offset) do
    cron__196(rest, acc, stack, context, line, offset)
  end

  defp cron__196(rest, acc, [_ | stack], context, line, offset) do
    cron__199(rest, acc, stack, context, line, offset)
  end

  defp cron__198(rest, acc, [1 | stack], context, line, offset) do
    cron__199(rest, acc, stack, context, line, offset)
  end

  defp cron__198(rest, acc, [count | stack], context, line, offset) do
    cron__197(rest, acc, [count - 1 | stack], context, line, offset)
  end

  defp cron__199(rest, user_acc, [acc | stack], context, line, offset) do
    cron__200(
      rest,
      (
        [head | tail] = :lists.reverse(user_acc)
        [:lists.foldl(fn x, acc -> x - 48 + acc * 10 end, head, tail)]
      ) ++ acc,
      stack,
      context,
      line,
      offset
    )
  end

  defp cron__200(rest, user_acc, [acc | stack], context, line, offset) do
    cron__201(rest, [range: :lists.reverse(user_acc)] ++ acc, stack, context, line, offset)
  end

  defp cron__201(rest, acc, [_, previous_acc | stack], context, line, offset) do
    cron__154(rest, acc ++ previous_acc, stack, context, line, offset)
  end

  defp cron__152(_, _, [{rest, acc, context, line, offset} | stack], _, _, _) do
    cron__202(rest, acc, stack, context, line, offset)
  end

  defp cron__154(
         inner_rest,
         inner_acc,
         [{rest, acc, context, line, offset} | stack],
         inner_context,
         inner_line,
         inner_offset
       ) do
    _ = {rest, acc, context, line, offset}

    cron__153(
      inner_rest,
      [],
      [{inner_rest, inner_acc ++ acc, inner_context, inner_line, inner_offset} | stack],
      inner_context,
      inner_line,
      inner_offset
    )
  end

  defp cron__202(rest, user_acc, [acc | stack], context, line, offset) do
    cron__203(rest, [hours: :lists.reverse(user_acc)] ++ acc, stack, context, line, offset)
  end

  defp cron__203(<<" ", rest::binary>>, acc, stack, context, comb__line, comb__offset) do
    cron__204(rest, [] ++ acc, stack, context, comb__line, comb__offset + 1)
  end

  defp cron__203(rest, _acc, _stack, context, line, offset) do
    {:error, "expected string \" \"", rest, context, line, offset}
  end

  defp cron__204(rest, acc, stack, context, line, offset) do
    cron__205(rest, [], [acc | stack], context, line, offset)
  end

  defp cron__205(rest, acc, stack, context, line, offset) do
    cron__236(rest, [], [{rest, context, line, offset}, acc | stack], context, line, offset)
  end

  defp cron__207(<<",", rest::binary>>, acc, stack, context, comb__line, comb__offset) do
    cron__208(rest, [] ++ acc, stack, context, comb__line, comb__offset + 1)
  end

  defp cron__207(rest, _acc, _stack, context, line, offset) do
    {:error,
     "expected byte in the range ?0..?9, followed by byte in the range ?0..?9, followed by string \"-\", followed by byte in the range ?0..?9, followed by byte in the range ?0..?9 or byte in the range ?0..?9, followed by byte in the range ?0..?9 or string \"*/\", followed by byte in the range ?0..?9, followed by byte in the range ?0..?9 or string \"*\" or string \",\"",
     rest, context, line, offset}
  end

  defp cron__208(rest, acc, [_, previous_acc | stack], context, line, offset) do
    cron__206(rest, acc ++ previous_acc, stack, context, line, offset)
  end

  defp cron__209(_, _, [{rest, context, line, offset} | _] = stack, _, _, _) do
    cron__207(rest, [], stack, context, line, offset)
  end

  defp cron__210(<<"*", rest::binary>>, acc, stack, context, comb__line, comb__offset) do
    cron__211(rest, [wild: "*"] ++ acc, stack, context, comb__line, comb__offset + 1)
  end

  defp cron__210(rest, acc, stack, context, line, offset) do
    cron__209(rest, acc, stack, context, line, offset)
  end

  defp cron__211(rest, acc, [_, previous_acc | stack], context, line, offset) do
    cron__206(rest, acc ++ previous_acc, stack, context, line, offset)
  end

  defp cron__212(_, _, [{rest, context, line, offset} | _] = stack, _, _, _) do
    cron__210(rest, [], stack, context, line, offset)
  end

  defp cron__213(rest, acc, stack, context, line, offset) do
    cron__214(rest, [], [acc | stack], context, line, offset)
  end

  defp cron__214(<<"*/", rest::binary>>, acc, stack, context, comb__line, comb__offset) do
    cron__215(rest, [] ++ acc, stack, context, comb__line, comb__offset + 2)
  end

  defp cron__214(rest, _acc, stack, context, line, offset) do
    [acc | stack] = stack
    cron__212(rest, acc, stack, context, line, offset)
  end

  defp cron__215(rest, acc, stack, context, line, offset) do
    cron__216(rest, [], [acc | stack], context, line, offset)
  end

  defp cron__216(<<x0::integer, rest::binary>>, acc, stack, context, comb__line, comb__offset)
       when x0 >= 48 and x0 <= 57 do
    cron__217(rest, [x0 - 48] ++ acc, stack, context, comb__line, comb__offset + 1)
  end

  defp cron__216(rest, _acc, stack, context, line, offset) do
    [_, acc | stack] = stack
    cron__212(rest, acc, stack, context, line, offset)
  end

  defp cron__217(rest, acc, stack, context, line, offset) do
    cron__219(rest, acc, [1 | stack], context, line, offset)
  end

  defp cron__219(<<x0::integer, rest::binary>>, acc, stack, context, comb__line, comb__offset)
       when x0 >= 48 and x0 <= 57 do
    cron__220(rest, [x0] ++ acc, stack, context, comb__line, comb__offset + 1)
  end

  defp cron__219(rest, acc, stack, context, line, offset) do
    cron__218(rest, acc, stack, context, line, offset)
  end

  defp cron__218(rest, acc, [_ | stack], context, line, offset) do
    cron__221(rest, acc, stack, context, line, offset)
  end

  defp cron__220(rest, acc, [1 | stack], context, line, offset) do
    cron__221(rest, acc, stack, context, line, offset)
  end

  defp cron__220(rest, acc, [count | stack], context, line, offset) do
    cron__219(rest, acc, [count - 1 | stack], context, line, offset)
  end

  defp cron__221(rest, user_acc, [acc | stack], context, line, offset) do
    cron__222(
      rest,
      (
        [head | tail] = :lists.reverse(user_acc)
        [:lists.foldl(fn x, acc -> x - 48 + acc * 10 end, head, tail)]
      ) ++ acc,
      stack,
      context,
      line,
      offset
    )
  end

  defp cron__222(rest, user_acc, [acc | stack], context, line, offset) do
    cron__223(
      rest,
      [
        step:
          case(:lists.reverse(user_acc)) do
            [one] ->
              one

            many ->
              raise("unwrap_and_tag/3 expected a single token, got: #{inspect(many)}")
          end
      ] ++ acc,
      stack,
      context,
      line,
      offset
    )
  end

  defp cron__223(rest, acc, [_, previous_acc | stack], context, line, offset) do
    cron__206(rest, acc ++ previous_acc, stack, context, line, offset)
  end

  defp cron__224(_, _, [{rest, context, line, offset} | _] = stack, _, _, _) do
    cron__213(rest, [], stack, context, line, offset)
  end

  defp cron__225(rest, acc, stack, context, line, offset) do
    cron__226(rest, [], [acc | stack], context, line, offset)
  end

  defp cron__226(rest, acc, stack, context, line, offset) do
    cron__227(rest, [], [acc | stack], context, line, offset)
  end

  defp cron__227(<<x0::integer, rest::binary>>, acc, stack, context, comb__line, comb__offset)
       when x0 >= 48 and x0 <= 57 do
    cron__228(rest, [x0 - 48] ++ acc, stack, context, comb__line, comb__offset + 1)
  end

  defp cron__227(rest, _acc, stack, context, line, offset) do
    [_, acc | stack] = stack
    cron__224(rest, acc, stack, context, line, offset)
  end

  defp cron__228(rest, acc, stack, context, line, offset) do
    cron__230(rest, acc, [1 | stack], context, line, offset)
  end

  defp cron__230(<<x0::integer, rest::binary>>, acc, stack, context, comb__line, comb__offset)
       when x0 >= 48 and x0 <= 57 do
    cron__231(rest, [x0] ++ acc, stack, context, comb__line, comb__offset + 1)
  end

  defp cron__230(rest, acc, stack, context, line, offset) do
    cron__229(rest, acc, stack, context, line, offset)
  end

  defp cron__229(rest, acc, [_ | stack], context, line, offset) do
    cron__232(rest, acc, stack, context, line, offset)
  end

  defp cron__231(rest, acc, [1 | stack], context, line, offset) do
    cron__232(rest, acc, stack, context, line, offset)
  end

  defp cron__231(rest, acc, [count | stack], context, line, offset) do
    cron__230(rest, acc, [count - 1 | stack], context, line, offset)
  end

  defp cron__232(rest, user_acc, [acc | stack], context, line, offset) do
    cron__233(
      rest,
      (
        [head | tail] = :lists.reverse(user_acc)
        [:lists.foldl(fn x, acc -> x - 48 + acc * 10 end, head, tail)]
      ) ++ acc,
      stack,
      context,
      line,
      offset
    )
  end

  defp cron__233(rest, user_acc, [acc | stack], context, line, offset) do
    cron__234(
      rest,
      [
        literal:
          case(:lists.reverse(user_acc)) do
            [one] ->
              one

            many ->
              raise("unwrap_and_tag/3 expected a single token, got: #{inspect(many)}")
          end
      ] ++ acc,
      stack,
      context,
      line,
      offset
    )
  end

  defp cron__234(rest, acc, [_, previous_acc | stack], context, line, offset) do
    cron__206(rest, acc ++ previous_acc, stack, context, line, offset)
  end

  defp cron__235(_, _, [{rest, context, line, offset} | _] = stack, _, _, _) do
    cron__225(rest, [], stack, context, line, offset)
  end

  defp cron__236(rest, acc, stack, context, line, offset) do
    cron__237(rest, [], [acc | stack], context, line, offset)
  end

  defp cron__237(rest, acc, stack, context, line, offset) do
    cron__238(rest, [], [acc | stack], context, line, offset)
  end

  defp cron__238(<<x0::integer, rest::binary>>, acc, stack, context, comb__line, comb__offset)
       when x0 >= 48 and x0 <= 57 do
    cron__239(rest, [x0 - 48] ++ acc, stack, context, comb__line, comb__offset + 1)
  end

  defp cron__238(rest, _acc, stack, context, line, offset) do
    [_, acc | stack] = stack
    cron__235(rest, acc, stack, context, line, offset)
  end

  defp cron__239(rest, acc, stack, context, line, offset) do
    cron__241(rest, acc, [1 | stack], context, line, offset)
  end

  defp cron__241(<<x0::integer, rest::binary>>, acc, stack, context, comb__line, comb__offset)
       when x0 >= 48 and x0 <= 57 do
    cron__242(rest, [x0] ++ acc, stack, context, comb__line, comb__offset + 1)
  end

  defp cron__241(rest, acc, stack, context, line, offset) do
    cron__240(rest, acc, stack, context, line, offset)
  end

  defp cron__240(rest, acc, [_ | stack], context, line, offset) do
    cron__243(rest, acc, stack, context, line, offset)
  end

  defp cron__242(rest, acc, [1 | stack], context, line, offset) do
    cron__243(rest, acc, stack, context, line, offset)
  end

  defp cron__242(rest, acc, [count | stack], context, line, offset) do
    cron__241(rest, acc, [count - 1 | stack], context, line, offset)
  end

  defp cron__243(rest, user_acc, [acc | stack], context, line, offset) do
    cron__244(
      rest,
      (
        [head | tail] = :lists.reverse(user_acc)
        [:lists.foldl(fn x, acc -> x - 48 + acc * 10 end, head, tail)]
      ) ++ acc,
      stack,
      context,
      line,
      offset
    )
  end

  defp cron__244(<<"-", rest::binary>>, acc, stack, context, comb__line, comb__offset) do
    cron__245(rest, [] ++ acc, stack, context, comb__line, comb__offset + 1)
  end

  defp cron__244(rest, _acc, stack, context, line, offset) do
    [acc | stack] = stack
    cron__235(rest, acc, stack, context, line, offset)
  end

  defp cron__245(rest, acc, stack, context, line, offset) do
    cron__246(rest, [], [acc | stack], context, line, offset)
  end

  defp cron__246(<<x0::integer, rest::binary>>, acc, stack, context, comb__line, comb__offset)
       when x0 >= 48 and x0 <= 57 do
    cron__247(rest, [x0 - 48] ++ acc, stack, context, comb__line, comb__offset + 1)
  end

  defp cron__246(rest, _acc, stack, context, line, offset) do
    [_, acc | stack] = stack
    cron__235(rest, acc, stack, context, line, offset)
  end

  defp cron__247(rest, acc, stack, context, line, offset) do
    cron__249(rest, acc, [1 | stack], context, line, offset)
  end

  defp cron__249(<<x0::integer, rest::binary>>, acc, stack, context, comb__line, comb__offset)
       when x0 >= 48 and x0 <= 57 do
    cron__250(rest, [x0] ++ acc, stack, context, comb__line, comb__offset + 1)
  end

  defp cron__249(rest, acc, stack, context, line, offset) do
    cron__248(rest, acc, stack, context, line, offset)
  end

  defp cron__248(rest, acc, [_ | stack], context, line, offset) do
    cron__251(rest, acc, stack, context, line, offset)
  end

  defp cron__250(rest, acc, [1 | stack], context, line, offset) do
    cron__251(rest, acc, stack, context, line, offset)
  end

  defp cron__250(rest, acc, [count | stack], context, line, offset) do
    cron__249(rest, acc, [count - 1 | stack], context, line, offset)
  end

  defp cron__251(rest, user_acc, [acc | stack], context, line, offset) do
    cron__252(
      rest,
      (
        [head | tail] = :lists.reverse(user_acc)
        [:lists.foldl(fn x, acc -> x - 48 + acc * 10 end, head, tail)]
      ) ++ acc,
      stack,
      context,
      line,
      offset
    )
  end

  defp cron__252(rest, user_acc, [acc | stack], context, line, offset) do
    cron__253(rest, [range: :lists.reverse(user_acc)] ++ acc, stack, context, line, offset)
  end

  defp cron__253(rest, acc, [_, previous_acc | stack], context, line, offset) do
    cron__206(rest, acc ++ previous_acc, stack, context, line, offset)
  end

  defp cron__206(rest, acc, stack, context, line, offset) do
    cron__255(rest, [], [{rest, acc, context, line, offset} | stack], context, line, offset)
  end

  defp cron__255(rest, acc, stack, context, line, offset) do
    cron__286(rest, [], [{rest, context, line, offset}, acc | stack], context, line, offset)
  end

  defp cron__257(<<",", rest::binary>>, acc, stack, context, comb__line, comb__offset) do
    cron__258(rest, [] ++ acc, stack, context, comb__line, comb__offset + 1)
  end

  defp cron__257(rest, _acc, stack, context, line, offset) do
    [_, acc | stack] = stack
    cron__254(rest, acc, stack, context, line, offset)
  end

  defp cron__258(rest, acc, [_, previous_acc | stack], context, line, offset) do
    cron__256(rest, acc ++ previous_acc, stack, context, line, offset)
  end

  defp cron__259(_, _, [{rest, context, line, offset} | _] = stack, _, _, _) do
    cron__257(rest, [], stack, context, line, offset)
  end

  defp cron__260(<<"*", rest::binary>>, acc, stack, context, comb__line, comb__offset) do
    cron__261(rest, [wild: "*"] ++ acc, stack, context, comb__line, comb__offset + 1)
  end

  defp cron__260(rest, acc, stack, context, line, offset) do
    cron__259(rest, acc, stack, context, line, offset)
  end

  defp cron__261(rest, acc, [_, previous_acc | stack], context, line, offset) do
    cron__256(rest, acc ++ previous_acc, stack, context, line, offset)
  end

  defp cron__262(_, _, [{rest, context, line, offset} | _] = stack, _, _, _) do
    cron__260(rest, [], stack, context, line, offset)
  end

  defp cron__263(rest, acc, stack, context, line, offset) do
    cron__264(rest, [], [acc | stack], context, line, offset)
  end

  defp cron__264(<<"*/", rest::binary>>, acc, stack, context, comb__line, comb__offset) do
    cron__265(rest, [] ++ acc, stack, context, comb__line, comb__offset + 2)
  end

  defp cron__264(rest, _acc, stack, context, line, offset) do
    [acc | stack] = stack
    cron__262(rest, acc, stack, context, line, offset)
  end

  defp cron__265(rest, acc, stack, context, line, offset) do
    cron__266(rest, [], [acc | stack], context, line, offset)
  end

  defp cron__266(<<x0::integer, rest::binary>>, acc, stack, context, comb__line, comb__offset)
       when x0 >= 48 and x0 <= 57 do
    cron__267(rest, [x0 - 48] ++ acc, stack, context, comb__line, comb__offset + 1)
  end

  defp cron__266(rest, _acc, stack, context, line, offset) do
    [_, acc | stack] = stack
    cron__262(rest, acc, stack, context, line, offset)
  end

  defp cron__267(rest, acc, stack, context, line, offset) do
    cron__269(rest, acc, [1 | stack], context, line, offset)
  end

  defp cron__269(<<x0::integer, rest::binary>>, acc, stack, context, comb__line, comb__offset)
       when x0 >= 48 and x0 <= 57 do
    cron__270(rest, [x0] ++ acc, stack, context, comb__line, comb__offset + 1)
  end

  defp cron__269(rest, acc, stack, context, line, offset) do
    cron__268(rest, acc, stack, context, line, offset)
  end

  defp cron__268(rest, acc, [_ | stack], context, line, offset) do
    cron__271(rest, acc, stack, context, line, offset)
  end

  defp cron__270(rest, acc, [1 | stack], context, line, offset) do
    cron__271(rest, acc, stack, context, line, offset)
  end

  defp cron__270(rest, acc, [count | stack], context, line, offset) do
    cron__269(rest, acc, [count - 1 | stack], context, line, offset)
  end

  defp cron__271(rest, user_acc, [acc | stack], context, line, offset) do
    cron__272(
      rest,
      (
        [head | tail] = :lists.reverse(user_acc)
        [:lists.foldl(fn x, acc -> x - 48 + acc * 10 end, head, tail)]
      ) ++ acc,
      stack,
      context,
      line,
      offset
    )
  end

  defp cron__272(rest, user_acc, [acc | stack], context, line, offset) do
    cron__273(
      rest,
      [
        step:
          case(:lists.reverse(user_acc)) do
            [one] ->
              one

            many ->
              raise("unwrap_and_tag/3 expected a single token, got: #{inspect(many)}")
          end
      ] ++ acc,
      stack,
      context,
      line,
      offset
    )
  end

  defp cron__273(rest, acc, [_, previous_acc | stack], context, line, offset) do
    cron__256(rest, acc ++ previous_acc, stack, context, line, offset)
  end

  defp cron__274(_, _, [{rest, context, line, offset} | _] = stack, _, _, _) do
    cron__263(rest, [], stack, context, line, offset)
  end

  defp cron__275(rest, acc, stack, context, line, offset) do
    cron__276(rest, [], [acc | stack], context, line, offset)
  end

  defp cron__276(rest, acc, stack, context, line, offset) do
    cron__277(rest, [], [acc | stack], context, line, offset)
  end

  defp cron__277(<<x0::integer, rest::binary>>, acc, stack, context, comb__line, comb__offset)
       when x0 >= 48 and x0 <= 57 do
    cron__278(rest, [x0 - 48] ++ acc, stack, context, comb__line, comb__offset + 1)
  end

  defp cron__277(rest, _acc, stack, context, line, offset) do
    [_, acc | stack] = stack
    cron__274(rest, acc, stack, context, line, offset)
  end

  defp cron__278(rest, acc, stack, context, line, offset) do
    cron__280(rest, acc, [1 | stack], context, line, offset)
  end

  defp cron__280(<<x0::integer, rest::binary>>, acc, stack, context, comb__line, comb__offset)
       when x0 >= 48 and x0 <= 57 do
    cron__281(rest, [x0] ++ acc, stack, context, comb__line, comb__offset + 1)
  end

  defp cron__280(rest, acc, stack, context, line, offset) do
    cron__279(rest, acc, stack, context, line, offset)
  end

  defp cron__279(rest, acc, [_ | stack], context, line, offset) do
    cron__282(rest, acc, stack, context, line, offset)
  end

  defp cron__281(rest, acc, [1 | stack], context, line, offset) do
    cron__282(rest, acc, stack, context, line, offset)
  end

  defp cron__281(rest, acc, [count | stack], context, line, offset) do
    cron__280(rest, acc, [count - 1 | stack], context, line, offset)
  end

  defp cron__282(rest, user_acc, [acc | stack], context, line, offset) do
    cron__283(
      rest,
      (
        [head | tail] = :lists.reverse(user_acc)
        [:lists.foldl(fn x, acc -> x - 48 + acc * 10 end, head, tail)]
      ) ++ acc,
      stack,
      context,
      line,
      offset
    )
  end

  defp cron__283(rest, user_acc, [acc | stack], context, line, offset) do
    cron__284(
      rest,
      [
        literal:
          case(:lists.reverse(user_acc)) do
            [one] ->
              one

            many ->
              raise("unwrap_and_tag/3 expected a single token, got: #{inspect(many)}")
          end
      ] ++ acc,
      stack,
      context,
      line,
      offset
    )
  end

  defp cron__284(rest, acc, [_, previous_acc | stack], context, line, offset) do
    cron__256(rest, acc ++ previous_acc, stack, context, line, offset)
  end

  defp cron__285(_, _, [{rest, context, line, offset} | _] = stack, _, _, _) do
    cron__275(rest, [], stack, context, line, offset)
  end

  defp cron__286(rest, acc, stack, context, line, offset) do
    cron__287(rest, [], [acc | stack], context, line, offset)
  end

  defp cron__287(rest, acc, stack, context, line, offset) do
    cron__288(rest, [], [acc | stack], context, line, offset)
  end

  defp cron__288(<<x0::integer, rest::binary>>, acc, stack, context, comb__line, comb__offset)
       when x0 >= 48 and x0 <= 57 do
    cron__289(rest, [x0 - 48] ++ acc, stack, context, comb__line, comb__offset + 1)
  end

  defp cron__288(rest, _acc, stack, context, line, offset) do
    [_, acc | stack] = stack
    cron__285(rest, acc, stack, context, line, offset)
  end

  defp cron__289(rest, acc, stack, context, line, offset) do
    cron__291(rest, acc, [1 | stack], context, line, offset)
  end

  defp cron__291(<<x0::integer, rest::binary>>, acc, stack, context, comb__line, comb__offset)
       when x0 >= 48 and x0 <= 57 do
    cron__292(rest, [x0] ++ acc, stack, context, comb__line, comb__offset + 1)
  end

  defp cron__291(rest, acc, stack, context, line, offset) do
    cron__290(rest, acc, stack, context, line, offset)
  end

  defp cron__290(rest, acc, [_ | stack], context, line, offset) do
    cron__293(rest, acc, stack, context, line, offset)
  end

  defp cron__292(rest, acc, [1 | stack], context, line, offset) do
    cron__293(rest, acc, stack, context, line, offset)
  end

  defp cron__292(rest, acc, [count | stack], context, line, offset) do
    cron__291(rest, acc, [count - 1 | stack], context, line, offset)
  end

  defp cron__293(rest, user_acc, [acc | stack], context, line, offset) do
    cron__294(
      rest,
      (
        [head | tail] = :lists.reverse(user_acc)
        [:lists.foldl(fn x, acc -> x - 48 + acc * 10 end, head, tail)]
      ) ++ acc,
      stack,
      context,
      line,
      offset
    )
  end

  defp cron__294(<<"-", rest::binary>>, acc, stack, context, comb__line, comb__offset) do
    cron__295(rest, [] ++ acc, stack, context, comb__line, comb__offset + 1)
  end

  defp cron__294(rest, _acc, stack, context, line, offset) do
    [acc | stack] = stack
    cron__285(rest, acc, stack, context, line, offset)
  end

  defp cron__295(rest, acc, stack, context, line, offset) do
    cron__296(rest, [], [acc | stack], context, line, offset)
  end

  defp cron__296(<<x0::integer, rest::binary>>, acc, stack, context, comb__line, comb__offset)
       when x0 >= 48 and x0 <= 57 do
    cron__297(rest, [x0 - 48] ++ acc, stack, context, comb__line, comb__offset + 1)
  end

  defp cron__296(rest, _acc, stack, context, line, offset) do
    [_, acc | stack] = stack
    cron__285(rest, acc, stack, context, line, offset)
  end

  defp cron__297(rest, acc, stack, context, line, offset) do
    cron__299(rest, acc, [1 | stack], context, line, offset)
  end

  defp cron__299(<<x0::integer, rest::binary>>, acc, stack, context, comb__line, comb__offset)
       when x0 >= 48 and x0 <= 57 do
    cron__300(rest, [x0] ++ acc, stack, context, comb__line, comb__offset + 1)
  end

  defp cron__299(rest, acc, stack, context, line, offset) do
    cron__298(rest, acc, stack, context, line, offset)
  end

  defp cron__298(rest, acc, [_ | stack], context, line, offset) do
    cron__301(rest, acc, stack, context, line, offset)
  end

  defp cron__300(rest, acc, [1 | stack], context, line, offset) do
    cron__301(rest, acc, stack, context, line, offset)
  end

  defp cron__300(rest, acc, [count | stack], context, line, offset) do
    cron__299(rest, acc, [count - 1 | stack], context, line, offset)
  end

  defp cron__301(rest, user_acc, [acc | stack], context, line, offset) do
    cron__302(
      rest,
      (
        [head | tail] = :lists.reverse(user_acc)
        [:lists.foldl(fn x, acc -> x - 48 + acc * 10 end, head, tail)]
      ) ++ acc,
      stack,
      context,
      line,
      offset
    )
  end

  defp cron__302(rest, user_acc, [acc | stack], context, line, offset) do
    cron__303(rest, [range: :lists.reverse(user_acc)] ++ acc, stack, context, line, offset)
  end

  defp cron__303(rest, acc, [_, previous_acc | stack], context, line, offset) do
    cron__256(rest, acc ++ previous_acc, stack, context, line, offset)
  end

  defp cron__254(_, _, [{rest, acc, context, line, offset} | stack], _, _, _) do
    cron__304(rest, acc, stack, context, line, offset)
  end

  defp cron__256(
         inner_rest,
         inner_acc,
         [{rest, acc, context, line, offset} | stack],
         inner_context,
         inner_line,
         inner_offset
       ) do
    _ = {rest, acc, context, line, offset}

    cron__255(
      inner_rest,
      [],
      [{inner_rest, inner_acc ++ acc, inner_context, inner_line, inner_offset} | stack],
      inner_context,
      inner_line,
      inner_offset
    )
  end

  defp cron__304(rest, user_acc, [acc | stack], context, line, offset) do
    cron__305(rest, [days: :lists.reverse(user_acc)] ++ acc, stack, context, line, offset)
  end

  defp cron__305(<<" ", rest::binary>>, acc, stack, context, comb__line, comb__offset) do
    cron__306(rest, [] ++ acc, stack, context, comb__line, comb__offset + 1)
  end

  defp cron__305(rest, _acc, _stack, context, line, offset) do
    {:error, "expected string \" \"", rest, context, line, offset}
  end

  defp cron__306(rest, acc, stack, context, line, offset) do
    cron__307(rest, [], [acc | stack], context, line, offset)
  end

  defp cron__307(rest, acc, stack, context, line, offset) do
    cron__359(rest, [], [{rest, context, line, offset}, acc | stack], context, line, offset)
  end

  defp cron__309(rest, acc, stack, context, line, offset) do
    cron__340(rest, [], [{rest, context, line, offset}, acc | stack], context, line, offset)
  end

  defp cron__311(<<",", rest::binary>>, acc, stack, context, comb__line, comb__offset) do
    cron__312(rest, [] ++ acc, stack, context, comb__line, comb__offset + 1)
  end

  defp cron__311(rest, _acc, _stack, context, line, offset) do
    {:error,
     "expected string \"JAN\" or string \"FEB\" or string \"MAR\" or string \"APR\" or string \"MAY\" or string \"JUN\" or string \"JUL\" or string \"AUG\" or string \"SEP\" or string \"OCT\" or string \"NOV\" or string \"DEC\" or byte in the range ?0..?9, followed by byte in the range ?0..?9, followed by string \"-\", followed by byte in the range ?0..?9, followed by byte in the range ?0..?9 or byte in the range ?0..?9, followed by byte in the range ?0..?9 or string \"*/\", followed by byte in the range ?0..?9, followed by byte in the range ?0..?9 or string \"*\" or string \",\"",
     rest, context, line, offset}
  end

  defp cron__312(rest, acc, [_, previous_acc | stack], context, line, offset) do
    cron__310(rest, acc ++ previous_acc, stack, context, line, offset)
  end

  defp cron__313(_, _, [{rest, context, line, offset} | _] = stack, _, _, _) do
    cron__311(rest, [], stack, context, line, offset)
  end

  defp cron__314(<<"*", rest::binary>>, acc, stack, context, comb__line, comb__offset) do
    cron__315(rest, [wild: "*"] ++ acc, stack, context, comb__line, comb__offset + 1)
  end

  defp cron__314(rest, acc, stack, context, line, offset) do
    cron__313(rest, acc, stack, context, line, offset)
  end

  defp cron__315(rest, acc, [_, previous_acc | stack], context, line, offset) do
    cron__310(rest, acc ++ previous_acc, stack, context, line, offset)
  end

  defp cron__316(_, _, [{rest, context, line, offset} | _] = stack, _, _, _) do
    cron__314(rest, [], stack, context, line, offset)
  end

  defp cron__317(rest, acc, stack, context, line, offset) do
    cron__318(rest, [], [acc | stack], context, line, offset)
  end

  defp cron__318(<<"*/", rest::binary>>, acc, stack, context, comb__line, comb__offset) do
    cron__319(rest, [] ++ acc, stack, context, comb__line, comb__offset + 2)
  end

  defp cron__318(rest, _acc, stack, context, line, offset) do
    [acc | stack] = stack
    cron__316(rest, acc, stack, context, line, offset)
  end

  defp cron__319(rest, acc, stack, context, line, offset) do
    cron__320(rest, [], [acc | stack], context, line, offset)
  end

  defp cron__320(<<x0::integer, rest::binary>>, acc, stack, context, comb__line, comb__offset)
       when x0 >= 48 and x0 <= 57 do
    cron__321(rest, [x0 - 48] ++ acc, stack, context, comb__line, comb__offset + 1)
  end

  defp cron__320(rest, _acc, stack, context, line, offset) do
    [_, acc | stack] = stack
    cron__316(rest, acc, stack, context, line, offset)
  end

  defp cron__321(rest, acc, stack, context, line, offset) do
    cron__323(rest, acc, [1 | stack], context, line, offset)
  end

  defp cron__323(<<x0::integer, rest::binary>>, acc, stack, context, comb__line, comb__offset)
       when x0 >= 48 and x0 <= 57 do
    cron__324(rest, [x0] ++ acc, stack, context, comb__line, comb__offset + 1)
  end

  defp cron__323(rest, acc, stack, context, line, offset) do
    cron__322(rest, acc, stack, context, line, offset)
  end

  defp cron__322(rest, acc, [_ | stack], context, line, offset) do
    cron__325(rest, acc, stack, context, line, offset)
  end

  defp cron__324(rest, acc, [1 | stack], context, line, offset) do
    cron__325(rest, acc, stack, context, line, offset)
  end

  defp cron__324(rest, acc, [count | stack], context, line, offset) do
    cron__323(rest, acc, [count - 1 | stack], context, line, offset)
  end

  defp cron__325(rest, user_acc, [acc | stack], context, line, offset) do
    cron__326(
      rest,
      (
        [head | tail] = :lists.reverse(user_acc)
        [:lists.foldl(fn x, acc -> x - 48 + acc * 10 end, head, tail)]
      ) ++ acc,
      stack,
      context,
      line,
      offset
    )
  end

  defp cron__326(rest, user_acc, [acc | stack], context, line, offset) do
    cron__327(
      rest,
      [
        step:
          case(:lists.reverse(user_acc)) do
            [one] ->
              one

            many ->
              raise("unwrap_and_tag/3 expected a single token, got: #{inspect(many)}")
          end
      ] ++ acc,
      stack,
      context,
      line,
      offset
    )
  end

  defp cron__327(rest, acc, [_, previous_acc | stack], context, line, offset) do
    cron__310(rest, acc ++ previous_acc, stack, context, line, offset)
  end

  defp cron__328(_, _, [{rest, context, line, offset} | _] = stack, _, _, _) do
    cron__317(rest, [], stack, context, line, offset)
  end

  defp cron__329(rest, acc, stack, context, line, offset) do
    cron__330(rest, [], [acc | stack], context, line, offset)
  end

  defp cron__330(rest, acc, stack, context, line, offset) do
    cron__331(rest, [], [acc | stack], context, line, offset)
  end

  defp cron__331(<<x0::integer, rest::binary>>, acc, stack, context, comb__line, comb__offset)
       when x0 >= 48 and x0 <= 57 do
    cron__332(rest, [x0 - 48] ++ acc, stack, context, comb__line, comb__offset + 1)
  end

  defp cron__331(rest, _acc, stack, context, line, offset) do
    [_, acc | stack] = stack
    cron__328(rest, acc, stack, context, line, offset)
  end

  defp cron__332(rest, acc, stack, context, line, offset) do
    cron__334(rest, acc, [1 | stack], context, line, offset)
  end

  defp cron__334(<<x0::integer, rest::binary>>, acc, stack, context, comb__line, comb__offset)
       when x0 >= 48 and x0 <= 57 do
    cron__335(rest, [x0] ++ acc, stack, context, comb__line, comb__offset + 1)
  end

  defp cron__334(rest, acc, stack, context, line, offset) do
    cron__333(rest, acc, stack, context, line, offset)
  end

  defp cron__333(rest, acc, [_ | stack], context, line, offset) do
    cron__336(rest, acc, stack, context, line, offset)
  end

  defp cron__335(rest, acc, [1 | stack], context, line, offset) do
    cron__336(rest, acc, stack, context, line, offset)
  end

  defp cron__335(rest, acc, [count | stack], context, line, offset) do
    cron__334(rest, acc, [count - 1 | stack], context, line, offset)
  end

  defp cron__336(rest, user_acc, [acc | stack], context, line, offset) do
    cron__337(
      rest,
      (
        [head | tail] = :lists.reverse(user_acc)
        [:lists.foldl(fn x, acc -> x - 48 + acc * 10 end, head, tail)]
      ) ++ acc,
      stack,
      context,
      line,
      offset
    )
  end

  defp cron__337(rest, user_acc, [acc | stack], context, line, offset) do
    cron__338(
      rest,
      [
        literal:
          case(:lists.reverse(user_acc)) do
            [one] ->
              one

            many ->
              raise("unwrap_and_tag/3 expected a single token, got: #{inspect(many)}")
          end
      ] ++ acc,
      stack,
      context,
      line,
      offset
    )
  end

  defp cron__338(rest, acc, [_, previous_acc | stack], context, line, offset) do
    cron__310(rest, acc ++ previous_acc, stack, context, line, offset)
  end

  defp cron__339(_, _, [{rest, context, line, offset} | _] = stack, _, _, _) do
    cron__329(rest, [], stack, context, line, offset)
  end

  defp cron__340(rest, acc, stack, context, line, offset) do
    cron__341(rest, [], [acc | stack], context, line, offset)
  end

  defp cron__341(rest, acc, stack, context, line, offset) do
    cron__342(rest, [], [acc | stack], context, line, offset)
  end

  defp cron__342(<<x0::integer, rest::binary>>, acc, stack, context, comb__line, comb__offset)
       when x0 >= 48 and x0 <= 57 do
    cron__343(rest, [x0 - 48] ++ acc, stack, context, comb__line, comb__offset + 1)
  end

  defp cron__342(rest, _acc, stack, context, line, offset) do
    [_, acc | stack] = stack
    cron__339(rest, acc, stack, context, line, offset)
  end

  defp cron__343(rest, acc, stack, context, line, offset) do
    cron__345(rest, acc, [1 | stack], context, line, offset)
  end

  defp cron__345(<<x0::integer, rest::binary>>, acc, stack, context, comb__line, comb__offset)
       when x0 >= 48 and x0 <= 57 do
    cron__346(rest, [x0] ++ acc, stack, context, comb__line, comb__offset + 1)
  end

  defp cron__345(rest, acc, stack, context, line, offset) do
    cron__344(rest, acc, stack, context, line, offset)
  end

  defp cron__344(rest, acc, [_ | stack], context, line, offset) do
    cron__347(rest, acc, stack, context, line, offset)
  end

  defp cron__346(rest, acc, [1 | stack], context, line, offset) do
    cron__347(rest, acc, stack, context, line, offset)
  end

  defp cron__346(rest, acc, [count | stack], context, line, offset) do
    cron__345(rest, acc, [count - 1 | stack], context, line, offset)
  end

  defp cron__347(rest, user_acc, [acc | stack], context, line, offset) do
    cron__348(
      rest,
      (
        [head | tail] = :lists.reverse(user_acc)
        [:lists.foldl(fn x, acc -> x - 48 + acc * 10 end, head, tail)]
      ) ++ acc,
      stack,
      context,
      line,
      offset
    )
  end

  defp cron__348(<<"-", rest::binary>>, acc, stack, context, comb__line, comb__offset) do
    cron__349(rest, [] ++ acc, stack, context, comb__line, comb__offset + 1)
  end

  defp cron__348(rest, _acc, stack, context, line, offset) do
    [acc | stack] = stack
    cron__339(rest, acc, stack, context, line, offset)
  end

  defp cron__349(rest, acc, stack, context, line, offset) do
    cron__350(rest, [], [acc | stack], context, line, offset)
  end

  defp cron__350(<<x0::integer, rest::binary>>, acc, stack, context, comb__line, comb__offset)
       when x0 >= 48 and x0 <= 57 do
    cron__351(rest, [x0 - 48] ++ acc, stack, context, comb__line, comb__offset + 1)
  end

  defp cron__350(rest, _acc, stack, context, line, offset) do
    [_, acc | stack] = stack
    cron__339(rest, acc, stack, context, line, offset)
  end

  defp cron__351(rest, acc, stack, context, line, offset) do
    cron__353(rest, acc, [1 | stack], context, line, offset)
  end

  defp cron__353(<<x0::integer, rest::binary>>, acc, stack, context, comb__line, comb__offset)
       when x0 >= 48 and x0 <= 57 do
    cron__354(rest, [x0] ++ acc, stack, context, comb__line, comb__offset + 1)
  end

  defp cron__353(rest, acc, stack, context, line, offset) do
    cron__352(rest, acc, stack, context, line, offset)
  end

  defp cron__352(rest, acc, [_ | stack], context, line, offset) do
    cron__355(rest, acc, stack, context, line, offset)
  end

  defp cron__354(rest, acc, [1 | stack], context, line, offset) do
    cron__355(rest, acc, stack, context, line, offset)
  end

  defp cron__354(rest, acc, [count | stack], context, line, offset) do
    cron__353(rest, acc, [count - 1 | stack], context, line, offset)
  end

  defp cron__355(rest, user_acc, [acc | stack], context, line, offset) do
    cron__356(
      rest,
      (
        [head | tail] = :lists.reverse(user_acc)
        [:lists.foldl(fn x, acc -> x - 48 + acc * 10 end, head, tail)]
      ) ++ acc,
      stack,
      context,
      line,
      offset
    )
  end

  defp cron__356(rest, user_acc, [acc | stack], context, line, offset) do
    cron__357(rest, [range: :lists.reverse(user_acc)] ++ acc, stack, context, line, offset)
  end

  defp cron__357(rest, acc, [_, previous_acc | stack], context, line, offset) do
    cron__310(rest, acc ++ previous_acc, stack, context, line, offset)
  end

  defp cron__310(rest, acc, [_, previous_acc | stack], context, line, offset) do
    cron__308(rest, acc ++ previous_acc, stack, context, line, offset)
  end

  defp cron__358(_, _, [{rest, context, line, offset} | _] = stack, _, _, _) do
    cron__309(rest, [], stack, context, line, offset)
  end

  defp cron__359(rest, acc, stack, context, line, offset) do
    cron__360(rest, [], [acc | stack], context, line, offset)
  end

  defp cron__360(<<"JAN", rest::binary>>, acc, stack, context, comb__line, comb__offset) do
    cron__361(rest, [1] ++ acc, stack, context, comb__line, comb__offset + 3)
  end

  defp cron__360(<<"FEB", rest::binary>>, acc, stack, context, comb__line, comb__offset) do
    cron__361(rest, [2] ++ acc, stack, context, comb__line, comb__offset + 3)
  end

  defp cron__360(<<"MAR", rest::binary>>, acc, stack, context, comb__line, comb__offset) do
    cron__361(rest, [3] ++ acc, stack, context, comb__line, comb__offset + 3)
  end

  defp cron__360(<<"APR", rest::binary>>, acc, stack, context, comb__line, comb__offset) do
    cron__361(rest, [4] ++ acc, stack, context, comb__line, comb__offset + 3)
  end

  defp cron__360(<<"MAY", rest::binary>>, acc, stack, context, comb__line, comb__offset) do
    cron__361(rest, [5] ++ acc, stack, context, comb__line, comb__offset + 3)
  end

  defp cron__360(<<"JUN", rest::binary>>, acc, stack, context, comb__line, comb__offset) do
    cron__361(rest, [6] ++ acc, stack, context, comb__line, comb__offset + 3)
  end

  defp cron__360(<<"JUL", rest::binary>>, acc, stack, context, comb__line, comb__offset) do
    cron__361(rest, [7] ++ acc, stack, context, comb__line, comb__offset + 3)
  end

  defp cron__360(<<"AUG", rest::binary>>, acc, stack, context, comb__line, comb__offset) do
    cron__361(rest, '\b' ++ acc, stack, context, comb__line, comb__offset + 3)
  end

  defp cron__360(<<"SEP", rest::binary>>, acc, stack, context, comb__line, comb__offset) do
    cron__361(rest, '\t' ++ acc, stack, context, comb__line, comb__offset + 3)
  end

  defp cron__360(<<"OCT", rest::binary>>, acc, stack, context, comb__line, comb__offset) do
    cron__361(rest, '\n' ++ acc, stack, context, comb__line, comb__offset + 3)
  end

  defp cron__360(<<"NOV", rest::binary>>, acc, stack, context, comb__line, comb__offset) do
    cron__361(rest, '\v' ++ acc, stack, context, comb__line, comb__offset + 3)
  end

  defp cron__360(<<"DEC", rest::binary>>, acc, stack, context, comb__line, comb__offset) do
    cron__361(rest, '\f' ++ acc, stack, context, comb__line, comb__offset + 3)
  end

  defp cron__360(rest, _acc, stack, context, line, offset) do
    [acc | stack] = stack
    cron__358(rest, acc, stack, context, line, offset)
  end

  defp cron__361(rest, user_acc, [acc | stack], context, line, offset) do
    cron__362(
      rest,
      [
        literal:
          case(:lists.reverse(user_acc)) do
            [one] ->
              one

            many ->
              raise("unwrap_and_tag/3 expected a single token, got: #{inspect(many)}")
          end
      ] ++ acc,
      stack,
      context,
      line,
      offset
    )
  end

  defp cron__362(rest, acc, [_, previous_acc | stack], context, line, offset) do
    cron__308(rest, acc ++ previous_acc, stack, context, line, offset)
  end

  defp cron__308(rest, acc, stack, context, line, offset) do
    cron__364(rest, [], [{rest, acc, context, line, offset} | stack], context, line, offset)
  end

  defp cron__364(rest, acc, stack, context, line, offset) do
    cron__416(rest, [], [{rest, context, line, offset}, acc | stack], context, line, offset)
  end

  defp cron__366(rest, acc, stack, context, line, offset) do
    cron__397(rest, [], [{rest, context, line, offset}, acc | stack], context, line, offset)
  end

  defp cron__368(<<",", rest::binary>>, acc, stack, context, comb__line, comb__offset) do
    cron__369(rest, [] ++ acc, stack, context, comb__line, comb__offset + 1)
  end

  defp cron__368(rest, _acc, stack, context, line, offset) do
    [_, _, _, acc | stack] = stack
    cron__363(rest, acc, stack, context, line, offset)
  end

  defp cron__369(rest, acc, [_, previous_acc | stack], context, line, offset) do
    cron__367(rest, acc ++ previous_acc, stack, context, line, offset)
  end

  defp cron__370(_, _, [{rest, context, line, offset} | _] = stack, _, _, _) do
    cron__368(rest, [], stack, context, line, offset)
  end

  defp cron__371(<<"*", rest::binary>>, acc, stack, context, comb__line, comb__offset) do
    cron__372(rest, [wild: "*"] ++ acc, stack, context, comb__line, comb__offset + 1)
  end

  defp cron__371(rest, acc, stack, context, line, offset) do
    cron__370(rest, acc, stack, context, line, offset)
  end

  defp cron__372(rest, acc, [_, previous_acc | stack], context, line, offset) do
    cron__367(rest, acc ++ previous_acc, stack, context, line, offset)
  end

  defp cron__373(_, _, [{rest, context, line, offset} | _] = stack, _, _, _) do
    cron__371(rest, [], stack, context, line, offset)
  end

  defp cron__374(rest, acc, stack, context, line, offset) do
    cron__375(rest, [], [acc | stack], context, line, offset)
  end

  defp cron__375(<<"*/", rest::binary>>, acc, stack, context, comb__line, comb__offset) do
    cron__376(rest, [] ++ acc, stack, context, comb__line, comb__offset + 2)
  end

  defp cron__375(rest, _acc, stack, context, line, offset) do
    [acc | stack] = stack
    cron__373(rest, acc, stack, context, line, offset)
  end

  defp cron__376(rest, acc, stack, context, line, offset) do
    cron__377(rest, [], [acc | stack], context, line, offset)
  end

  defp cron__377(<<x0::integer, rest::binary>>, acc, stack, context, comb__line, comb__offset)
       when x0 >= 48 and x0 <= 57 do
    cron__378(rest, [x0 - 48] ++ acc, stack, context, comb__line, comb__offset + 1)
  end

  defp cron__377(rest, _acc, stack, context, line, offset) do
    [_, acc | stack] = stack
    cron__373(rest, acc, stack, context, line, offset)
  end

  defp cron__378(rest, acc, stack, context, line, offset) do
    cron__380(rest, acc, [1 | stack], context, line, offset)
  end

  defp cron__380(<<x0::integer, rest::binary>>, acc, stack, context, comb__line, comb__offset)
       when x0 >= 48 and x0 <= 57 do
    cron__381(rest, [x0] ++ acc, stack, context, comb__line, comb__offset + 1)
  end

  defp cron__380(rest, acc, stack, context, line, offset) do
    cron__379(rest, acc, stack, context, line, offset)
  end

  defp cron__379(rest, acc, [_ | stack], context, line, offset) do
    cron__382(rest, acc, stack, context, line, offset)
  end

  defp cron__381(rest, acc, [1 | stack], context, line, offset) do
    cron__382(rest, acc, stack, context, line, offset)
  end

  defp cron__381(rest, acc, [count | stack], context, line, offset) do
    cron__380(rest, acc, [count - 1 | stack], context, line, offset)
  end

  defp cron__382(rest, user_acc, [acc | stack], context, line, offset) do
    cron__383(
      rest,
      (
        [head | tail] = :lists.reverse(user_acc)
        [:lists.foldl(fn x, acc -> x - 48 + acc * 10 end, head, tail)]
      ) ++ acc,
      stack,
      context,
      line,
      offset
    )
  end

  defp cron__383(rest, user_acc, [acc | stack], context, line, offset) do
    cron__384(
      rest,
      [
        step:
          case(:lists.reverse(user_acc)) do
            [one] ->
              one

            many ->
              raise("unwrap_and_tag/3 expected a single token, got: #{inspect(many)}")
          end
      ] ++ acc,
      stack,
      context,
      line,
      offset
    )
  end

  defp cron__384(rest, acc, [_, previous_acc | stack], context, line, offset) do
    cron__367(rest, acc ++ previous_acc, stack, context, line, offset)
  end

  defp cron__385(_, _, [{rest, context, line, offset} | _] = stack, _, _, _) do
    cron__374(rest, [], stack, context, line, offset)
  end

  defp cron__386(rest, acc, stack, context, line, offset) do
    cron__387(rest, [], [acc | stack], context, line, offset)
  end

  defp cron__387(rest, acc, stack, context, line, offset) do
    cron__388(rest, [], [acc | stack], context, line, offset)
  end

  defp cron__388(<<x0::integer, rest::binary>>, acc, stack, context, comb__line, comb__offset)
       when x0 >= 48 and x0 <= 57 do
    cron__389(rest, [x0 - 48] ++ acc, stack, context, comb__line, comb__offset + 1)
  end

  defp cron__388(rest, _acc, stack, context, line, offset) do
    [_, acc | stack] = stack
    cron__385(rest, acc, stack, context, line, offset)
  end

  defp cron__389(rest, acc, stack, context, line, offset) do
    cron__391(rest, acc, [1 | stack], context, line, offset)
  end

  defp cron__391(<<x0::integer, rest::binary>>, acc, stack, context, comb__line, comb__offset)
       when x0 >= 48 and x0 <= 57 do
    cron__392(rest, [x0] ++ acc, stack, context, comb__line, comb__offset + 1)
  end

  defp cron__391(rest, acc, stack, context, line, offset) do
    cron__390(rest, acc, stack, context, line, offset)
  end

  defp cron__390(rest, acc, [_ | stack], context, line, offset) do
    cron__393(rest, acc, stack, context, line, offset)
  end

  defp cron__392(rest, acc, [1 | stack], context, line, offset) do
    cron__393(rest, acc, stack, context, line, offset)
  end

  defp cron__392(rest, acc, [count | stack], context, line, offset) do
    cron__391(rest, acc, [count - 1 | stack], context, line, offset)
  end

  defp cron__393(rest, user_acc, [acc | stack], context, line, offset) do
    cron__394(
      rest,
      (
        [head | tail] = :lists.reverse(user_acc)
        [:lists.foldl(fn x, acc -> x - 48 + acc * 10 end, head, tail)]
      ) ++ acc,
      stack,
      context,
      line,
      offset
    )
  end

  defp cron__394(rest, user_acc, [acc | stack], context, line, offset) do
    cron__395(
      rest,
      [
        literal:
          case(:lists.reverse(user_acc)) do
            [one] ->
              one

            many ->
              raise("unwrap_and_tag/3 expected a single token, got: #{inspect(many)}")
          end
      ] ++ acc,
      stack,
      context,
      line,
      offset
    )
  end

  defp cron__395(rest, acc, [_, previous_acc | stack], context, line, offset) do
    cron__367(rest, acc ++ previous_acc, stack, context, line, offset)
  end

  defp cron__396(_, _, [{rest, context, line, offset} | _] = stack, _, _, _) do
    cron__386(rest, [], stack, context, line, offset)
  end

  defp cron__397(rest, acc, stack, context, line, offset) do
    cron__398(rest, [], [acc | stack], context, line, offset)
  end

  defp cron__398(rest, acc, stack, context, line, offset) do
    cron__399(rest, [], [acc | stack], context, line, offset)
  end

  defp cron__399(<<x0::integer, rest::binary>>, acc, stack, context, comb__line, comb__offset)
       when x0 >= 48 and x0 <= 57 do
    cron__400(rest, [x0 - 48] ++ acc, stack, context, comb__line, comb__offset + 1)
  end

  defp cron__399(rest, _acc, stack, context, line, offset) do
    [_, acc | stack] = stack
    cron__396(rest, acc, stack, context, line, offset)
  end

  defp cron__400(rest, acc, stack, context, line, offset) do
    cron__402(rest, acc, [1 | stack], context, line, offset)
  end

  defp cron__402(<<x0::integer, rest::binary>>, acc, stack, context, comb__line, comb__offset)
       when x0 >= 48 and x0 <= 57 do
    cron__403(rest, [x0] ++ acc, stack, context, comb__line, comb__offset + 1)
  end

  defp cron__402(rest, acc, stack, context, line, offset) do
    cron__401(rest, acc, stack, context, line, offset)
  end

  defp cron__401(rest, acc, [_ | stack], context, line, offset) do
    cron__404(rest, acc, stack, context, line, offset)
  end

  defp cron__403(rest, acc, [1 | stack], context, line, offset) do
    cron__404(rest, acc, stack, context, line, offset)
  end

  defp cron__403(rest, acc, [count | stack], context, line, offset) do
    cron__402(rest, acc, [count - 1 | stack], context, line, offset)
  end

  defp cron__404(rest, user_acc, [acc | stack], context, line, offset) do
    cron__405(
      rest,
      (
        [head | tail] = :lists.reverse(user_acc)
        [:lists.foldl(fn x, acc -> x - 48 + acc * 10 end, head, tail)]
      ) ++ acc,
      stack,
      context,
      line,
      offset
    )
  end

  defp cron__405(<<"-", rest::binary>>, acc, stack, context, comb__line, comb__offset) do
    cron__406(rest, [] ++ acc, stack, context, comb__line, comb__offset + 1)
  end

  defp cron__405(rest, _acc, stack, context, line, offset) do
    [acc | stack] = stack
    cron__396(rest, acc, stack, context, line, offset)
  end

  defp cron__406(rest, acc, stack, context, line, offset) do
    cron__407(rest, [], [acc | stack], context, line, offset)
  end

  defp cron__407(<<x0::integer, rest::binary>>, acc, stack, context, comb__line, comb__offset)
       when x0 >= 48 and x0 <= 57 do
    cron__408(rest, [x0 - 48] ++ acc, stack, context, comb__line, comb__offset + 1)
  end

  defp cron__407(rest, _acc, stack, context, line, offset) do
    [_, acc | stack] = stack
    cron__396(rest, acc, stack, context, line, offset)
  end

  defp cron__408(rest, acc, stack, context, line, offset) do
    cron__410(rest, acc, [1 | stack], context, line, offset)
  end

  defp cron__410(<<x0::integer, rest::binary>>, acc, stack, context, comb__line, comb__offset)
       when x0 >= 48 and x0 <= 57 do
    cron__411(rest, [x0] ++ acc, stack, context, comb__line, comb__offset + 1)
  end

  defp cron__410(rest, acc, stack, context, line, offset) do
    cron__409(rest, acc, stack, context, line, offset)
  end

  defp cron__409(rest, acc, [_ | stack], context, line, offset) do
    cron__412(rest, acc, stack, context, line, offset)
  end

  defp cron__411(rest, acc, [1 | stack], context, line, offset) do
    cron__412(rest, acc, stack, context, line, offset)
  end

  defp cron__411(rest, acc, [count | stack], context, line, offset) do
    cron__410(rest, acc, [count - 1 | stack], context, line, offset)
  end

  defp cron__412(rest, user_acc, [acc | stack], context, line, offset) do
    cron__413(
      rest,
      (
        [head | tail] = :lists.reverse(user_acc)
        [:lists.foldl(fn x, acc -> x - 48 + acc * 10 end, head, tail)]
      ) ++ acc,
      stack,
      context,
      line,
      offset
    )
  end

  defp cron__413(rest, user_acc, [acc | stack], context, line, offset) do
    cron__414(rest, [range: :lists.reverse(user_acc)] ++ acc, stack, context, line, offset)
  end

  defp cron__414(rest, acc, [_, previous_acc | stack], context, line, offset) do
    cron__367(rest, acc ++ previous_acc, stack, context, line, offset)
  end

  defp cron__367(rest, acc, [_, previous_acc | stack], context, line, offset) do
    cron__365(rest, acc ++ previous_acc, stack, context, line, offset)
  end

  defp cron__415(_, _, [{rest, context, line, offset} | _] = stack, _, _, _) do
    cron__366(rest, [], stack, context, line, offset)
  end

  defp cron__416(rest, acc, stack, context, line, offset) do
    cron__417(rest, [], [acc | stack], context, line, offset)
  end

  defp cron__417(<<"JAN", rest::binary>>, acc, stack, context, comb__line, comb__offset) do
    cron__418(rest, [1] ++ acc, stack, context, comb__line, comb__offset + 3)
  end

  defp cron__417(<<"FEB", rest::binary>>, acc, stack, context, comb__line, comb__offset) do
    cron__418(rest, [2] ++ acc, stack, context, comb__line, comb__offset + 3)
  end

  defp cron__417(<<"MAR", rest::binary>>, acc, stack, context, comb__line, comb__offset) do
    cron__418(rest, [3] ++ acc, stack, context, comb__line, comb__offset + 3)
  end

  defp cron__417(<<"APR", rest::binary>>, acc, stack, context, comb__line, comb__offset) do
    cron__418(rest, [4] ++ acc, stack, context, comb__line, comb__offset + 3)
  end

  defp cron__417(<<"MAY", rest::binary>>, acc, stack, context, comb__line, comb__offset) do
    cron__418(rest, [5] ++ acc, stack, context, comb__line, comb__offset + 3)
  end

  defp cron__417(<<"JUN", rest::binary>>, acc, stack, context, comb__line, comb__offset) do
    cron__418(rest, [6] ++ acc, stack, context, comb__line, comb__offset + 3)
  end

  defp cron__417(<<"JUL", rest::binary>>, acc, stack, context, comb__line, comb__offset) do
    cron__418(rest, [7] ++ acc, stack, context, comb__line, comb__offset + 3)
  end

  defp cron__417(<<"AUG", rest::binary>>, acc, stack, context, comb__line, comb__offset) do
    cron__418(rest, '\b' ++ acc, stack, context, comb__line, comb__offset + 3)
  end

  defp cron__417(<<"SEP", rest::binary>>, acc, stack, context, comb__line, comb__offset) do
    cron__418(rest, '\t' ++ acc, stack, context, comb__line, comb__offset + 3)
  end

  defp cron__417(<<"OCT", rest::binary>>, acc, stack, context, comb__line, comb__offset) do
    cron__418(rest, '\n' ++ acc, stack, context, comb__line, comb__offset + 3)
  end

  defp cron__417(<<"NOV", rest::binary>>, acc, stack, context, comb__line, comb__offset) do
    cron__418(rest, '\v' ++ acc, stack, context, comb__line, comb__offset + 3)
  end

  defp cron__417(<<"DEC", rest::binary>>, acc, stack, context, comb__line, comb__offset) do
    cron__418(rest, '\f' ++ acc, stack, context, comb__line, comb__offset + 3)
  end

  defp cron__417(rest, _acc, stack, context, line, offset) do
    [acc | stack] = stack
    cron__415(rest, acc, stack, context, line, offset)
  end

  defp cron__418(rest, user_acc, [acc | stack], context, line, offset) do
    cron__419(
      rest,
      [
        literal:
          case(:lists.reverse(user_acc)) do
            [one] ->
              one

            many ->
              raise("unwrap_and_tag/3 expected a single token, got: #{inspect(many)}")
          end
      ] ++ acc,
      stack,
      context,
      line,
      offset
    )
  end

  defp cron__419(rest, acc, [_, previous_acc | stack], context, line, offset) do
    cron__365(rest, acc ++ previous_acc, stack, context, line, offset)
  end

  defp cron__363(_, _, [{rest, acc, context, line, offset} | stack], _, _, _) do
    cron__420(rest, acc, stack, context, line, offset)
  end

  defp cron__365(
         inner_rest,
         inner_acc,
         [{rest, acc, context, line, offset} | stack],
         inner_context,
         inner_line,
         inner_offset
       ) do
    _ = {rest, acc, context, line, offset}

    cron__364(
      inner_rest,
      [],
      [{inner_rest, inner_acc ++ acc, inner_context, inner_line, inner_offset} | stack],
      inner_context,
      inner_line,
      inner_offset
    )
  end

  defp cron__420(rest, user_acc, [acc | stack], context, line, offset) do
    cron__421(rest, [months: :lists.reverse(user_acc)] ++ acc, stack, context, line, offset)
  end

  defp cron__421(<<" ", rest::binary>>, acc, stack, context, comb__line, comb__offset) do
    cron__422(rest, [] ++ acc, stack, context, comb__line, comb__offset + 1)
  end

  defp cron__421(rest, _acc, _stack, context, line, offset) do
    {:error, "expected string \" \"", rest, context, line, offset}
  end

  defp cron__422(rest, acc, stack, context, line, offset) do
    cron__423(rest, [], [acc | stack], context, line, offset)
  end

  defp cron__423(rest, acc, stack, context, line, offset) do
    cron__475(rest, [], [{rest, context, line, offset}, acc | stack], context, line, offset)
  end

  defp cron__425(rest, acc, stack, context, line, offset) do
    cron__456(rest, [], [{rest, context, line, offset}, acc | stack], context, line, offset)
  end

  defp cron__427(<<",", rest::binary>>, acc, stack, context, comb__line, comb__offset) do
    cron__428(rest, [] ++ acc, stack, context, comb__line, comb__offset + 1)
  end

  defp cron__427(rest, _acc, _stack, context, line, offset) do
    {:error,
     "expected string \"MON\" or string \"TUE\" or string \"WED\" or string \"THU\" or string \"FRI\" or string \"SAT\" or string \"SUN\" or byte in the range ?0..?9, followed by byte in the range ?0..?9, followed by string \"-\", followed by byte in the range ?0..?9, followed by byte in the range ?0..?9 or byte in the range ?0..?9, followed by byte in the range ?0..?9 or string \"*/\", followed by byte in the range ?0..?9, followed by byte in the range ?0..?9 or string \"*\" or string \",\"",
     rest, context, line, offset}
  end

  defp cron__428(rest, acc, [_, previous_acc | stack], context, line, offset) do
    cron__426(rest, acc ++ previous_acc, stack, context, line, offset)
  end

  defp cron__429(_, _, [{rest, context, line, offset} | _] = stack, _, _, _) do
    cron__427(rest, [], stack, context, line, offset)
  end

  defp cron__430(<<"*", rest::binary>>, acc, stack, context, comb__line, comb__offset) do
    cron__431(rest, [wild: "*"] ++ acc, stack, context, comb__line, comb__offset + 1)
  end

  defp cron__430(rest, acc, stack, context, line, offset) do
    cron__429(rest, acc, stack, context, line, offset)
  end

  defp cron__431(rest, acc, [_, previous_acc | stack], context, line, offset) do
    cron__426(rest, acc ++ previous_acc, stack, context, line, offset)
  end

  defp cron__432(_, _, [{rest, context, line, offset} | _] = stack, _, _, _) do
    cron__430(rest, [], stack, context, line, offset)
  end

  defp cron__433(rest, acc, stack, context, line, offset) do
    cron__434(rest, [], [acc | stack], context, line, offset)
  end

  defp cron__434(<<"*/", rest::binary>>, acc, stack, context, comb__line, comb__offset) do
    cron__435(rest, [] ++ acc, stack, context, comb__line, comb__offset + 2)
  end

  defp cron__434(rest, _acc, stack, context, line, offset) do
    [acc | stack] = stack
    cron__432(rest, acc, stack, context, line, offset)
  end

  defp cron__435(rest, acc, stack, context, line, offset) do
    cron__436(rest, [], [acc | stack], context, line, offset)
  end

  defp cron__436(<<x0::integer, rest::binary>>, acc, stack, context, comb__line, comb__offset)
       when x0 >= 48 and x0 <= 57 do
    cron__437(rest, [x0 - 48] ++ acc, stack, context, comb__line, comb__offset + 1)
  end

  defp cron__436(rest, _acc, stack, context, line, offset) do
    [_, acc | stack] = stack
    cron__432(rest, acc, stack, context, line, offset)
  end

  defp cron__437(rest, acc, stack, context, line, offset) do
    cron__439(rest, acc, [1 | stack], context, line, offset)
  end

  defp cron__439(<<x0::integer, rest::binary>>, acc, stack, context, comb__line, comb__offset)
       when x0 >= 48 and x0 <= 57 do
    cron__440(rest, [x0] ++ acc, stack, context, comb__line, comb__offset + 1)
  end

  defp cron__439(rest, acc, stack, context, line, offset) do
    cron__438(rest, acc, stack, context, line, offset)
  end

  defp cron__438(rest, acc, [_ | stack], context, line, offset) do
    cron__441(rest, acc, stack, context, line, offset)
  end

  defp cron__440(rest, acc, [1 | stack], context, line, offset) do
    cron__441(rest, acc, stack, context, line, offset)
  end

  defp cron__440(rest, acc, [count | stack], context, line, offset) do
    cron__439(rest, acc, [count - 1 | stack], context, line, offset)
  end

  defp cron__441(rest, user_acc, [acc | stack], context, line, offset) do
    cron__442(
      rest,
      (
        [head | tail] = :lists.reverse(user_acc)
        [:lists.foldl(fn x, acc -> x - 48 + acc * 10 end, head, tail)]
      ) ++ acc,
      stack,
      context,
      line,
      offset
    )
  end

  defp cron__442(rest, user_acc, [acc | stack], context, line, offset) do
    cron__443(
      rest,
      [
        step:
          case(:lists.reverse(user_acc)) do
            [one] ->
              one

            many ->
              raise("unwrap_and_tag/3 expected a single token, got: #{inspect(many)}")
          end
      ] ++ acc,
      stack,
      context,
      line,
      offset
    )
  end

  defp cron__443(rest, acc, [_, previous_acc | stack], context, line, offset) do
    cron__426(rest, acc ++ previous_acc, stack, context, line, offset)
  end

  defp cron__444(_, _, [{rest, context, line, offset} | _] = stack, _, _, _) do
    cron__433(rest, [], stack, context, line, offset)
  end

  defp cron__445(rest, acc, stack, context, line, offset) do
    cron__446(rest, [], [acc | stack], context, line, offset)
  end

  defp cron__446(rest, acc, stack, context, line, offset) do
    cron__447(rest, [], [acc | stack], context, line, offset)
  end

  defp cron__447(<<x0::integer, rest::binary>>, acc, stack, context, comb__line, comb__offset)
       when x0 >= 48 and x0 <= 57 do
    cron__448(rest, [x0 - 48] ++ acc, stack, context, comb__line, comb__offset + 1)
  end

  defp cron__447(rest, _acc, stack, context, line, offset) do
    [_, acc | stack] = stack
    cron__444(rest, acc, stack, context, line, offset)
  end

  defp cron__448(rest, acc, stack, context, line, offset) do
    cron__450(rest, acc, [1 | stack], context, line, offset)
  end

  defp cron__450(<<x0::integer, rest::binary>>, acc, stack, context, comb__line, comb__offset)
       when x0 >= 48 and x0 <= 57 do
    cron__451(rest, [x0] ++ acc, stack, context, comb__line, comb__offset + 1)
  end

  defp cron__450(rest, acc, stack, context, line, offset) do
    cron__449(rest, acc, stack, context, line, offset)
  end

  defp cron__449(rest, acc, [_ | stack], context, line, offset) do
    cron__452(rest, acc, stack, context, line, offset)
  end

  defp cron__451(rest, acc, [1 | stack], context, line, offset) do
    cron__452(rest, acc, stack, context, line, offset)
  end

  defp cron__451(rest, acc, [count | stack], context, line, offset) do
    cron__450(rest, acc, [count - 1 | stack], context, line, offset)
  end

  defp cron__452(rest, user_acc, [acc | stack], context, line, offset) do
    cron__453(
      rest,
      (
        [head | tail] = :lists.reverse(user_acc)
        [:lists.foldl(fn x, acc -> x - 48 + acc * 10 end, head, tail)]
      ) ++ acc,
      stack,
      context,
      line,
      offset
    )
  end

  defp cron__453(rest, user_acc, [acc | stack], context, line, offset) do
    cron__454(
      rest,
      [
        literal:
          case(:lists.reverse(user_acc)) do
            [one] ->
              one

            many ->
              raise("unwrap_and_tag/3 expected a single token, got: #{inspect(many)}")
          end
      ] ++ acc,
      stack,
      context,
      line,
      offset
    )
  end

  defp cron__454(rest, acc, [_, previous_acc | stack], context, line, offset) do
    cron__426(rest, acc ++ previous_acc, stack, context, line, offset)
  end

  defp cron__455(_, _, [{rest, context, line, offset} | _] = stack, _, _, _) do
    cron__445(rest, [], stack, context, line, offset)
  end

  defp cron__456(rest, acc, stack, context, line, offset) do
    cron__457(rest, [], [acc | stack], context, line, offset)
  end

  defp cron__457(rest, acc, stack, context, line, offset) do
    cron__458(rest, [], [acc | stack], context, line, offset)
  end

  defp cron__458(<<x0::integer, rest::binary>>, acc, stack, context, comb__line, comb__offset)
       when x0 >= 48 and x0 <= 57 do
    cron__459(rest, [x0 - 48] ++ acc, stack, context, comb__line, comb__offset + 1)
  end

  defp cron__458(rest, _acc, stack, context, line, offset) do
    [_, acc | stack] = stack
    cron__455(rest, acc, stack, context, line, offset)
  end

  defp cron__459(rest, acc, stack, context, line, offset) do
    cron__461(rest, acc, [1 | stack], context, line, offset)
  end

  defp cron__461(<<x0::integer, rest::binary>>, acc, stack, context, comb__line, comb__offset)
       when x0 >= 48 and x0 <= 57 do
    cron__462(rest, [x0] ++ acc, stack, context, comb__line, comb__offset + 1)
  end

  defp cron__461(rest, acc, stack, context, line, offset) do
    cron__460(rest, acc, stack, context, line, offset)
  end

  defp cron__460(rest, acc, [_ | stack], context, line, offset) do
    cron__463(rest, acc, stack, context, line, offset)
  end

  defp cron__462(rest, acc, [1 | stack], context, line, offset) do
    cron__463(rest, acc, stack, context, line, offset)
  end

  defp cron__462(rest, acc, [count | stack], context, line, offset) do
    cron__461(rest, acc, [count - 1 | stack], context, line, offset)
  end

  defp cron__463(rest, user_acc, [acc | stack], context, line, offset) do
    cron__464(
      rest,
      (
        [head | tail] = :lists.reverse(user_acc)
        [:lists.foldl(fn x, acc -> x - 48 + acc * 10 end, head, tail)]
      ) ++ acc,
      stack,
      context,
      line,
      offset
    )
  end

  defp cron__464(<<"-", rest::binary>>, acc, stack, context, comb__line, comb__offset) do
    cron__465(rest, [] ++ acc, stack, context, comb__line, comb__offset + 1)
  end

  defp cron__464(rest, _acc, stack, context, line, offset) do
    [acc | stack] = stack
    cron__455(rest, acc, stack, context, line, offset)
  end

  defp cron__465(rest, acc, stack, context, line, offset) do
    cron__466(rest, [], [acc | stack], context, line, offset)
  end

  defp cron__466(<<x0::integer, rest::binary>>, acc, stack, context, comb__line, comb__offset)
       when x0 >= 48 and x0 <= 57 do
    cron__467(rest, [x0 - 48] ++ acc, stack, context, comb__line, comb__offset + 1)
  end

  defp cron__466(rest, _acc, stack, context, line, offset) do
    [_, acc | stack] = stack
    cron__455(rest, acc, stack, context, line, offset)
  end

  defp cron__467(rest, acc, stack, context, line, offset) do
    cron__469(rest, acc, [1 | stack], context, line, offset)
  end

  defp cron__469(<<x0::integer, rest::binary>>, acc, stack, context, comb__line, comb__offset)
       when x0 >= 48 and x0 <= 57 do
    cron__470(rest, [x0] ++ acc, stack, context, comb__line, comb__offset + 1)
  end

  defp cron__469(rest, acc, stack, context, line, offset) do
    cron__468(rest, acc, stack, context, line, offset)
  end

  defp cron__468(rest, acc, [_ | stack], context, line, offset) do
    cron__471(rest, acc, stack, context, line, offset)
  end

  defp cron__470(rest, acc, [1 | stack], context, line, offset) do
    cron__471(rest, acc, stack, context, line, offset)
  end

  defp cron__470(rest, acc, [count | stack], context, line, offset) do
    cron__469(rest, acc, [count - 1 | stack], context, line, offset)
  end

  defp cron__471(rest, user_acc, [acc | stack], context, line, offset) do
    cron__472(
      rest,
      (
        [head | tail] = :lists.reverse(user_acc)
        [:lists.foldl(fn x, acc -> x - 48 + acc * 10 end, head, tail)]
      ) ++ acc,
      stack,
      context,
      line,
      offset
    )
  end

  defp cron__472(rest, user_acc, [acc | stack], context, line, offset) do
    cron__473(rest, [range: :lists.reverse(user_acc)] ++ acc, stack, context, line, offset)
  end

  defp cron__473(rest, acc, [_, previous_acc | stack], context, line, offset) do
    cron__426(rest, acc ++ previous_acc, stack, context, line, offset)
  end

  defp cron__426(rest, acc, [_, previous_acc | stack], context, line, offset) do
    cron__424(rest, acc ++ previous_acc, stack, context, line, offset)
  end

  defp cron__474(_, _, [{rest, context, line, offset} | _] = stack, _, _, _) do
    cron__425(rest, [], stack, context, line, offset)
  end

  defp cron__475(rest, acc, stack, context, line, offset) do
    cron__476(rest, [], [acc | stack], context, line, offset)
  end

  defp cron__476(<<"MON", rest::binary>>, acc, stack, context, comb__line, comb__offset) do
    cron__477(rest, [1] ++ acc, stack, context, comb__line, comb__offset + 3)
  end

  defp cron__476(<<"TUE", rest::binary>>, acc, stack, context, comb__line, comb__offset) do
    cron__477(rest, [2] ++ acc, stack, context, comb__line, comb__offset + 3)
  end

  defp cron__476(<<"WED", rest::binary>>, acc, stack, context, comb__line, comb__offset) do
    cron__477(rest, [3] ++ acc, stack, context, comb__line, comb__offset + 3)
  end

  defp cron__476(<<"THU", rest::binary>>, acc, stack, context, comb__line, comb__offset) do
    cron__477(rest, [4] ++ acc, stack, context, comb__line, comb__offset + 3)
  end

  defp cron__476(<<"FRI", rest::binary>>, acc, stack, context, comb__line, comb__offset) do
    cron__477(rest, [5] ++ acc, stack, context, comb__line, comb__offset + 3)
  end

  defp cron__476(<<"SAT", rest::binary>>, acc, stack, context, comb__line, comb__offset) do
    cron__477(rest, [6] ++ acc, stack, context, comb__line, comb__offset + 3)
  end

  defp cron__476(<<"SUN", rest::binary>>, acc, stack, context, comb__line, comb__offset) do
    cron__477(rest, [0] ++ acc, stack, context, comb__line, comb__offset + 3)
  end

  defp cron__476(rest, _acc, stack, context, line, offset) do
    [acc | stack] = stack
    cron__474(rest, acc, stack, context, line, offset)
  end

  defp cron__477(rest, user_acc, [acc | stack], context, line, offset) do
    cron__478(
      rest,
      [
        literal:
          case(:lists.reverse(user_acc)) do
            [one] ->
              one

            many ->
              raise("unwrap_and_tag/3 expected a single token, got: #{inspect(many)}")
          end
      ] ++ acc,
      stack,
      context,
      line,
      offset
    )
  end

  defp cron__478(rest, acc, [_, previous_acc | stack], context, line, offset) do
    cron__424(rest, acc ++ previous_acc, stack, context, line, offset)
  end

  defp cron__424(rest, acc, stack, context, line, offset) do
    cron__480(rest, [], [{rest, acc, context, line, offset} | stack], context, line, offset)
  end

  defp cron__480(rest, acc, stack, context, line, offset) do
    cron__532(rest, [], [{rest, context, line, offset}, acc | stack], context, line, offset)
  end

  defp cron__482(rest, acc, stack, context, line, offset) do
    cron__513(rest, [], [{rest, context, line, offset}, acc | stack], context, line, offset)
  end

  defp cron__484(<<",", rest::binary>>, acc, stack, context, comb__line, comb__offset) do
    cron__485(rest, [] ++ acc, stack, context, comb__line, comb__offset + 1)
  end

  defp cron__484(rest, _acc, stack, context, line, offset) do
    [_, _, _, acc | stack] = stack
    cron__479(rest, acc, stack, context, line, offset)
  end

  defp cron__485(rest, acc, [_, previous_acc | stack], context, line, offset) do
    cron__483(rest, acc ++ previous_acc, stack, context, line, offset)
  end

  defp cron__486(_, _, [{rest, context, line, offset} | _] = stack, _, _, _) do
    cron__484(rest, [], stack, context, line, offset)
  end

  defp cron__487(<<"*", rest::binary>>, acc, stack, context, comb__line, comb__offset) do
    cron__488(rest, [wild: "*"] ++ acc, stack, context, comb__line, comb__offset + 1)
  end

  defp cron__487(rest, acc, stack, context, line, offset) do
    cron__486(rest, acc, stack, context, line, offset)
  end

  defp cron__488(rest, acc, [_, previous_acc | stack], context, line, offset) do
    cron__483(rest, acc ++ previous_acc, stack, context, line, offset)
  end

  defp cron__489(_, _, [{rest, context, line, offset} | _] = stack, _, _, _) do
    cron__487(rest, [], stack, context, line, offset)
  end

  defp cron__490(rest, acc, stack, context, line, offset) do
    cron__491(rest, [], [acc | stack], context, line, offset)
  end

  defp cron__491(<<"*/", rest::binary>>, acc, stack, context, comb__line, comb__offset) do
    cron__492(rest, [] ++ acc, stack, context, comb__line, comb__offset + 2)
  end

  defp cron__491(rest, _acc, stack, context, line, offset) do
    [acc | stack] = stack
    cron__489(rest, acc, stack, context, line, offset)
  end

  defp cron__492(rest, acc, stack, context, line, offset) do
    cron__493(rest, [], [acc | stack], context, line, offset)
  end

  defp cron__493(<<x0::integer, rest::binary>>, acc, stack, context, comb__line, comb__offset)
       when x0 >= 48 and x0 <= 57 do
    cron__494(rest, [x0 - 48] ++ acc, stack, context, comb__line, comb__offset + 1)
  end

  defp cron__493(rest, _acc, stack, context, line, offset) do
    [_, acc | stack] = stack
    cron__489(rest, acc, stack, context, line, offset)
  end

  defp cron__494(rest, acc, stack, context, line, offset) do
    cron__496(rest, acc, [1 | stack], context, line, offset)
  end

  defp cron__496(<<x0::integer, rest::binary>>, acc, stack, context, comb__line, comb__offset)
       when x0 >= 48 and x0 <= 57 do
    cron__497(rest, [x0] ++ acc, stack, context, comb__line, comb__offset + 1)
  end

  defp cron__496(rest, acc, stack, context, line, offset) do
    cron__495(rest, acc, stack, context, line, offset)
  end

  defp cron__495(rest, acc, [_ | stack], context, line, offset) do
    cron__498(rest, acc, stack, context, line, offset)
  end

  defp cron__497(rest, acc, [1 | stack], context, line, offset) do
    cron__498(rest, acc, stack, context, line, offset)
  end

  defp cron__497(rest, acc, [count | stack], context, line, offset) do
    cron__496(rest, acc, [count - 1 | stack], context, line, offset)
  end

  defp cron__498(rest, user_acc, [acc | stack], context, line, offset) do
    cron__499(
      rest,
      (
        [head | tail] = :lists.reverse(user_acc)
        [:lists.foldl(fn x, acc -> x - 48 + acc * 10 end, head, tail)]
      ) ++ acc,
      stack,
      context,
      line,
      offset
    )
  end

  defp cron__499(rest, user_acc, [acc | stack], context, line, offset) do
    cron__500(
      rest,
      [
        step:
          case(:lists.reverse(user_acc)) do
            [one] ->
              one

            many ->
              raise("unwrap_and_tag/3 expected a single token, got: #{inspect(many)}")
          end
      ] ++ acc,
      stack,
      context,
      line,
      offset
    )
  end

  defp cron__500(rest, acc, [_, previous_acc | stack], context, line, offset) do
    cron__483(rest, acc ++ previous_acc, stack, context, line, offset)
  end

  defp cron__501(_, _, [{rest, context, line, offset} | _] = stack, _, _, _) do
    cron__490(rest, [], stack, context, line, offset)
  end

  defp cron__502(rest, acc, stack, context, line, offset) do
    cron__503(rest, [], [acc | stack], context, line, offset)
  end

  defp cron__503(rest, acc, stack, context, line, offset) do
    cron__504(rest, [], [acc | stack], context, line, offset)
  end

  defp cron__504(<<x0::integer, rest::binary>>, acc, stack, context, comb__line, comb__offset)
       when x0 >= 48 and x0 <= 57 do
    cron__505(rest, [x0 - 48] ++ acc, stack, context, comb__line, comb__offset + 1)
  end

  defp cron__504(rest, _acc, stack, context, line, offset) do
    [_, acc | stack] = stack
    cron__501(rest, acc, stack, context, line, offset)
  end

  defp cron__505(rest, acc, stack, context, line, offset) do
    cron__507(rest, acc, [1 | stack], context, line, offset)
  end

  defp cron__507(<<x0::integer, rest::binary>>, acc, stack, context, comb__line, comb__offset)
       when x0 >= 48 and x0 <= 57 do
    cron__508(rest, [x0] ++ acc, stack, context, comb__line, comb__offset + 1)
  end

  defp cron__507(rest, acc, stack, context, line, offset) do
    cron__506(rest, acc, stack, context, line, offset)
  end

  defp cron__506(rest, acc, [_ | stack], context, line, offset) do
    cron__509(rest, acc, stack, context, line, offset)
  end

  defp cron__508(rest, acc, [1 | stack], context, line, offset) do
    cron__509(rest, acc, stack, context, line, offset)
  end

  defp cron__508(rest, acc, [count | stack], context, line, offset) do
    cron__507(rest, acc, [count - 1 | stack], context, line, offset)
  end

  defp cron__509(rest, user_acc, [acc | stack], context, line, offset) do
    cron__510(
      rest,
      (
        [head | tail] = :lists.reverse(user_acc)
        [:lists.foldl(fn x, acc -> x - 48 + acc * 10 end, head, tail)]
      ) ++ acc,
      stack,
      context,
      line,
      offset
    )
  end

  defp cron__510(rest, user_acc, [acc | stack], context, line, offset) do
    cron__511(
      rest,
      [
        literal:
          case(:lists.reverse(user_acc)) do
            [one] ->
              one

            many ->
              raise("unwrap_and_tag/3 expected a single token, got: #{inspect(many)}")
          end
      ] ++ acc,
      stack,
      context,
      line,
      offset
    )
  end

  defp cron__511(rest, acc, [_, previous_acc | stack], context, line, offset) do
    cron__483(rest, acc ++ previous_acc, stack, context, line, offset)
  end

  defp cron__512(_, _, [{rest, context, line, offset} | _] = stack, _, _, _) do
    cron__502(rest, [], stack, context, line, offset)
  end

  defp cron__513(rest, acc, stack, context, line, offset) do
    cron__514(rest, [], [acc | stack], context, line, offset)
  end

  defp cron__514(rest, acc, stack, context, line, offset) do
    cron__515(rest, [], [acc | stack], context, line, offset)
  end

  defp cron__515(<<x0::integer, rest::binary>>, acc, stack, context, comb__line, comb__offset)
       when x0 >= 48 and x0 <= 57 do
    cron__516(rest, [x0 - 48] ++ acc, stack, context, comb__line, comb__offset + 1)
  end

  defp cron__515(rest, _acc, stack, context, line, offset) do
    [_, acc | stack] = stack
    cron__512(rest, acc, stack, context, line, offset)
  end

  defp cron__516(rest, acc, stack, context, line, offset) do
    cron__518(rest, acc, [1 | stack], context, line, offset)
  end

  defp cron__518(<<x0::integer, rest::binary>>, acc, stack, context, comb__line, comb__offset)
       when x0 >= 48 and x0 <= 57 do
    cron__519(rest, [x0] ++ acc, stack, context, comb__line, comb__offset + 1)
  end

  defp cron__518(rest, acc, stack, context, line, offset) do
    cron__517(rest, acc, stack, context, line, offset)
  end

  defp cron__517(rest, acc, [_ | stack], context, line, offset) do
    cron__520(rest, acc, stack, context, line, offset)
  end

  defp cron__519(rest, acc, [1 | stack], context, line, offset) do
    cron__520(rest, acc, stack, context, line, offset)
  end

  defp cron__519(rest, acc, [count | stack], context, line, offset) do
    cron__518(rest, acc, [count - 1 | stack], context, line, offset)
  end

  defp cron__520(rest, user_acc, [acc | stack], context, line, offset) do
    cron__521(
      rest,
      (
        [head | tail] = :lists.reverse(user_acc)
        [:lists.foldl(fn x, acc -> x - 48 + acc * 10 end, head, tail)]
      ) ++ acc,
      stack,
      context,
      line,
      offset
    )
  end

  defp cron__521(<<"-", rest::binary>>, acc, stack, context, comb__line, comb__offset) do
    cron__522(rest, [] ++ acc, stack, context, comb__line, comb__offset + 1)
  end

  defp cron__521(rest, _acc, stack, context, line, offset) do
    [acc | stack] = stack
    cron__512(rest, acc, stack, context, line, offset)
  end

  defp cron__522(rest, acc, stack, context, line, offset) do
    cron__523(rest, [], [acc | stack], context, line, offset)
  end

  defp cron__523(<<x0::integer, rest::binary>>, acc, stack, context, comb__line, comb__offset)
       when x0 >= 48 and x0 <= 57 do
    cron__524(rest, [x0 - 48] ++ acc, stack, context, comb__line, comb__offset + 1)
  end

  defp cron__523(rest, _acc, stack, context, line, offset) do
    [_, acc | stack] = stack
    cron__512(rest, acc, stack, context, line, offset)
  end

  defp cron__524(rest, acc, stack, context, line, offset) do
    cron__526(rest, acc, [1 | stack], context, line, offset)
  end

  defp cron__526(<<x0::integer, rest::binary>>, acc, stack, context, comb__line, comb__offset)
       when x0 >= 48 and x0 <= 57 do
    cron__527(rest, [x0] ++ acc, stack, context, comb__line, comb__offset + 1)
  end

  defp cron__526(rest, acc, stack, context, line, offset) do
    cron__525(rest, acc, stack, context, line, offset)
  end

  defp cron__525(rest, acc, [_ | stack], context, line, offset) do
    cron__528(rest, acc, stack, context, line, offset)
  end

  defp cron__527(rest, acc, [1 | stack], context, line, offset) do
    cron__528(rest, acc, stack, context, line, offset)
  end

  defp cron__527(rest, acc, [count | stack], context, line, offset) do
    cron__526(rest, acc, [count - 1 | stack], context, line, offset)
  end

  defp cron__528(rest, user_acc, [acc | stack], context, line, offset) do
    cron__529(
      rest,
      (
        [head | tail] = :lists.reverse(user_acc)
        [:lists.foldl(fn x, acc -> x - 48 + acc * 10 end, head, tail)]
      ) ++ acc,
      stack,
      context,
      line,
      offset
    )
  end

  defp cron__529(rest, user_acc, [acc | stack], context, line, offset) do
    cron__530(rest, [range: :lists.reverse(user_acc)] ++ acc, stack, context, line, offset)
  end

  defp cron__530(rest, acc, [_, previous_acc | stack], context, line, offset) do
    cron__483(rest, acc ++ previous_acc, stack, context, line, offset)
  end

  defp cron__483(rest, acc, [_, previous_acc | stack], context, line, offset) do
    cron__481(rest, acc ++ previous_acc, stack, context, line, offset)
  end

  defp cron__531(_, _, [{rest, context, line, offset} | _] = stack, _, _, _) do
    cron__482(rest, [], stack, context, line, offset)
  end

  defp cron__532(rest, acc, stack, context, line, offset) do
    cron__533(rest, [], [acc | stack], context, line, offset)
  end

  defp cron__533(<<"MON", rest::binary>>, acc, stack, context, comb__line, comb__offset) do
    cron__534(rest, [1] ++ acc, stack, context, comb__line, comb__offset + 3)
  end

  defp cron__533(<<"TUE", rest::binary>>, acc, stack, context, comb__line, comb__offset) do
    cron__534(rest, [2] ++ acc, stack, context, comb__line, comb__offset + 3)
  end

  defp cron__533(<<"WED", rest::binary>>, acc, stack, context, comb__line, comb__offset) do
    cron__534(rest, [3] ++ acc, stack, context, comb__line, comb__offset + 3)
  end

  defp cron__533(<<"THU", rest::binary>>, acc, stack, context, comb__line, comb__offset) do
    cron__534(rest, [4] ++ acc, stack, context, comb__line, comb__offset + 3)
  end

  defp cron__533(<<"FRI", rest::binary>>, acc, stack, context, comb__line, comb__offset) do
    cron__534(rest, [5] ++ acc, stack, context, comb__line, comb__offset + 3)
  end

  defp cron__533(<<"SAT", rest::binary>>, acc, stack, context, comb__line, comb__offset) do
    cron__534(rest, [6] ++ acc, stack, context, comb__line, comb__offset + 3)
  end

  defp cron__533(<<"SUN", rest::binary>>, acc, stack, context, comb__line, comb__offset) do
    cron__534(rest, [0] ++ acc, stack, context, comb__line, comb__offset + 3)
  end

  defp cron__533(rest, _acc, stack, context, line, offset) do
    [acc | stack] = stack
    cron__531(rest, acc, stack, context, line, offset)
  end

  defp cron__534(rest, user_acc, [acc | stack], context, line, offset) do
    cron__535(
      rest,
      [
        literal:
          case(:lists.reverse(user_acc)) do
            [one] ->
              one

            many ->
              raise("unwrap_and_tag/3 expected a single token, got: #{inspect(many)}")
          end
      ] ++ acc,
      stack,
      context,
      line,
      offset
    )
  end

  defp cron__535(rest, acc, [_, previous_acc | stack], context, line, offset) do
    cron__481(rest, acc ++ previous_acc, stack, context, line, offset)
  end

  defp cron__479(_, _, [{rest, acc, context, line, offset} | stack], _, _, _) do
    cron__536(rest, acc, stack, context, line, offset)
  end

  defp cron__481(
         inner_rest,
         inner_acc,
         [{rest, acc, context, line, offset} | stack],
         inner_context,
         inner_line,
         inner_offset
       ) do
    _ = {rest, acc, context, line, offset}

    cron__480(
      inner_rest,
      [],
      [{inner_rest, inner_acc ++ acc, inner_context, inner_line, inner_offset} | stack],
      inner_context,
      inner_line,
      inner_offset
    )
  end

  defp cron__536(rest, user_acc, [acc | stack], context, line, offset) do
    cron__537(rest, [weekdays: :lists.reverse(user_acc)] ++ acc, stack, context, line, offset)
  end

  defp cron__537(rest, acc, _stack, context, line, offset) do
    {:ok, acc, rest, context, line, offset}
  end
end
