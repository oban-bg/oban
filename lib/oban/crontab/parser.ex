# Generated from lib/oban/crontab/parser.ex.exs, do not edit.
# Generated at 2020-05-25 15:18:25Z.

defmodule Oban.Crontab.Parser do
  @moduledoc false

  @doc """
  Parses the given `binary` as cron.

  Returns `{:ok, [token], rest, context, position, byte_offset}` or
  `{:error, reason, rest, context, line, byte_offset}` where `position`
  describes the location of the cron (start position) as `{line, column_on_line}`.

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
    cron__39(rest, [], [{rest, context, line, offset}, acc | stack], context, line, offset)
  end

  defp cron__3(<<",", rest::binary>>, acc, stack, context, comb__line, comb__offset) do
    cron__4(rest, [] ++ acc, stack, context, comb__line, comb__offset + 1)
  end

  defp cron__3(rest, _acc, _stack, context, line, offset) do
    {:error,
     "expected string \"*\" or ASCII character in the range '0' to '9', followed by ASCII character in the range '0' to '9', followed by string \"-\", followed by ASCII character in the range '0' to '9', followed by ASCII character in the range '0' to '9', followed by string \"/\", followed by ASCII character in the range '0' to '9', followed by ASCII character in the range '0' to '9' or ASCII character in the range '0' to '9', followed by ASCII character in the range '0' to '9', followed by string \"-\", followed by ASCII character in the range '0' to '9', followed by ASCII character in the range '0' to '9' or ASCII character in the range '0' to '9', followed by ASCII character in the range '0' to '9' or string \"*\" or string \",\"",
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

  defp cron__10(rest, acc, stack, context, line, offset) do
    cron__11(rest, [], [acc | stack], context, line, offset)
  end

  defp cron__11(<<x0::integer, rest::binary>>, acc, stack, context, comb__line, comb__offset)
       when x0 >= 48 and x0 <= 57 do
    cron__12(rest, [x0 - 48] ++ acc, stack, context, comb__line, comb__offset + 1)
  end

  defp cron__11(rest, _acc, stack, context, line, offset) do
    [_, acc | stack] = stack
    cron__8(rest, acc, stack, context, line, offset)
  end

  defp cron__12(rest, acc, stack, context, line, offset) do
    cron__14(rest, acc, [1 | stack], context, line, offset)
  end

  defp cron__14(<<x0::integer, rest::binary>>, acc, stack, context, comb__line, comb__offset)
       when x0 >= 48 and x0 <= 57 do
    cron__15(rest, [x0] ++ acc, stack, context, comb__line, comb__offset + 1)
  end

  defp cron__14(rest, acc, stack, context, line, offset) do
    cron__13(rest, acc, stack, context, line, offset)
  end

  defp cron__13(rest, acc, [_ | stack], context, line, offset) do
    cron__16(rest, acc, stack, context, line, offset)
  end

  defp cron__15(rest, acc, [1 | stack], context, line, offset) do
    cron__16(rest, acc, stack, context, line, offset)
  end

  defp cron__15(rest, acc, [count | stack], context, line, offset) do
    cron__14(rest, acc, [count - 1 | stack], context, line, offset)
  end

  defp cron__16(rest, user_acc, [acc | stack], context, line, offset) do
    _ = user_acc

    cron__17(
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

  defp cron__17(rest, user_acc, [acc | stack], context, line, offset) do
    _ = user_acc

    cron__18(
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

  defp cron__18(rest, acc, [_, previous_acc | stack], context, line, offset) do
    cron__2(rest, acc ++ previous_acc, stack, context, line, offset)
  end

  defp cron__19(_, _, [{rest, context, line, offset} | _] = stack, _, _, _) do
    cron__9(rest, [], stack, context, line, offset)
  end

  defp cron__20(rest, acc, stack, context, line, offset) do
    cron__21(rest, [], [acc | stack], context, line, offset)
  end

  defp cron__21(rest, acc, stack, context, line, offset) do
    cron__22(rest, [], [acc | stack], context, line, offset)
  end

  defp cron__22(<<x0::integer, rest::binary>>, acc, stack, context, comb__line, comb__offset)
       when x0 >= 48 and x0 <= 57 do
    cron__23(rest, [x0 - 48] ++ acc, stack, context, comb__line, comb__offset + 1)
  end

  defp cron__22(rest, _acc, stack, context, line, offset) do
    [_, acc | stack] = stack
    cron__19(rest, acc, stack, context, line, offset)
  end

  defp cron__23(rest, acc, stack, context, line, offset) do
    cron__25(rest, acc, [1 | stack], context, line, offset)
  end

  defp cron__25(<<x0::integer, rest::binary>>, acc, stack, context, comb__line, comb__offset)
       when x0 >= 48 and x0 <= 57 do
    cron__26(rest, [x0] ++ acc, stack, context, comb__line, comb__offset + 1)
  end

  defp cron__25(rest, acc, stack, context, line, offset) do
    cron__24(rest, acc, stack, context, line, offset)
  end

  defp cron__24(rest, acc, [_ | stack], context, line, offset) do
    cron__27(rest, acc, stack, context, line, offset)
  end

  defp cron__26(rest, acc, [1 | stack], context, line, offset) do
    cron__27(rest, acc, stack, context, line, offset)
  end

  defp cron__26(rest, acc, [count | stack], context, line, offset) do
    cron__25(rest, acc, [count - 1 | stack], context, line, offset)
  end

  defp cron__27(rest, user_acc, [acc | stack], context, line, offset) do
    _ = user_acc

    cron__28(
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

  defp cron__28(<<"-", rest::binary>>, acc, stack, context, comb__line, comb__offset) do
    cron__29(rest, [] ++ acc, stack, context, comb__line, comb__offset + 1)
  end

  defp cron__28(rest, _acc, stack, context, line, offset) do
    [acc | stack] = stack
    cron__19(rest, acc, stack, context, line, offset)
  end

  defp cron__29(rest, acc, stack, context, line, offset) do
    cron__30(rest, [], [acc | stack], context, line, offset)
  end

  defp cron__30(<<x0::integer, rest::binary>>, acc, stack, context, comb__line, comb__offset)
       when x0 >= 48 and x0 <= 57 do
    cron__31(rest, [x0 - 48] ++ acc, stack, context, comb__line, comb__offset + 1)
  end

  defp cron__30(rest, _acc, stack, context, line, offset) do
    [_, acc | stack] = stack
    cron__19(rest, acc, stack, context, line, offset)
  end

  defp cron__31(rest, acc, stack, context, line, offset) do
    cron__33(rest, acc, [1 | stack], context, line, offset)
  end

  defp cron__33(<<x0::integer, rest::binary>>, acc, stack, context, comb__line, comb__offset)
       when x0 >= 48 and x0 <= 57 do
    cron__34(rest, [x0] ++ acc, stack, context, comb__line, comb__offset + 1)
  end

  defp cron__33(rest, acc, stack, context, line, offset) do
    cron__32(rest, acc, stack, context, line, offset)
  end

  defp cron__32(rest, acc, [_ | stack], context, line, offset) do
    cron__35(rest, acc, stack, context, line, offset)
  end

  defp cron__34(rest, acc, [1 | stack], context, line, offset) do
    cron__35(rest, acc, stack, context, line, offset)
  end

  defp cron__34(rest, acc, [count | stack], context, line, offset) do
    cron__33(rest, acc, [count - 1 | stack], context, line, offset)
  end

  defp cron__35(rest, user_acc, [acc | stack], context, line, offset) do
    _ = user_acc

    cron__36(
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

  defp cron__36(rest, user_acc, [acc | stack], context, line, offset) do
    _ = user_acc
    cron__37(rest, [range: :lists.reverse(user_acc)] ++ acc, stack, context, line, offset)
  end

  defp cron__37(rest, acc, [_, previous_acc | stack], context, line, offset) do
    cron__2(rest, acc ++ previous_acc, stack, context, line, offset)
  end

  defp cron__38(_, _, [{rest, context, line, offset} | _] = stack, _, _, _) do
    cron__20(rest, [], stack, context, line, offset)
  end

  defp cron__39(rest, acc, stack, context, line, offset) do
    cron__40(rest, [], [acc | stack], context, line, offset)
  end

  defp cron__40(rest, acc, stack, context, line, offset) do
    cron__61(rest, [], [{rest, context, line, offset}, acc | stack], context, line, offset)
  end

  defp cron__42(rest, acc, stack, context, line, offset) do
    cron__43(rest, [], [acc | stack], context, line, offset)
  end

  defp cron__43(rest, acc, stack, context, line, offset) do
    cron__44(rest, [], [acc | stack], context, line, offset)
  end

  defp cron__44(<<x0::integer, rest::binary>>, acc, stack, context, comb__line, comb__offset)
       when x0 >= 48 and x0 <= 57 do
    cron__45(rest, [x0 - 48] ++ acc, stack, context, comb__line, comb__offset + 1)
  end

  defp cron__44(rest, _acc, stack, context, line, offset) do
    [_, _, _, _, acc | stack] = stack
    cron__38(rest, acc, stack, context, line, offset)
  end

  defp cron__45(rest, acc, stack, context, line, offset) do
    cron__47(rest, acc, [1 | stack], context, line, offset)
  end

  defp cron__47(<<x0::integer, rest::binary>>, acc, stack, context, comb__line, comb__offset)
       when x0 >= 48 and x0 <= 57 do
    cron__48(rest, [x0] ++ acc, stack, context, comb__line, comb__offset + 1)
  end

  defp cron__47(rest, acc, stack, context, line, offset) do
    cron__46(rest, acc, stack, context, line, offset)
  end

  defp cron__46(rest, acc, [_ | stack], context, line, offset) do
    cron__49(rest, acc, stack, context, line, offset)
  end

  defp cron__48(rest, acc, [1 | stack], context, line, offset) do
    cron__49(rest, acc, stack, context, line, offset)
  end

  defp cron__48(rest, acc, [count | stack], context, line, offset) do
    cron__47(rest, acc, [count - 1 | stack], context, line, offset)
  end

  defp cron__49(rest, user_acc, [acc | stack], context, line, offset) do
    _ = user_acc

    cron__50(
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

  defp cron__50(<<"-", rest::binary>>, acc, stack, context, comb__line, comb__offset) do
    cron__51(rest, [] ++ acc, stack, context, comb__line, comb__offset + 1)
  end

  defp cron__50(rest, _acc, stack, context, line, offset) do
    [_, _, _, acc | stack] = stack
    cron__38(rest, acc, stack, context, line, offset)
  end

  defp cron__51(rest, acc, stack, context, line, offset) do
    cron__52(rest, [], [acc | stack], context, line, offset)
  end

  defp cron__52(<<x0::integer, rest::binary>>, acc, stack, context, comb__line, comb__offset)
       when x0 >= 48 and x0 <= 57 do
    cron__53(rest, [x0 - 48] ++ acc, stack, context, comb__line, comb__offset + 1)
  end

  defp cron__52(rest, _acc, stack, context, line, offset) do
    [_, _, _, _, acc | stack] = stack
    cron__38(rest, acc, stack, context, line, offset)
  end

  defp cron__53(rest, acc, stack, context, line, offset) do
    cron__55(rest, acc, [1 | stack], context, line, offset)
  end

  defp cron__55(<<x0::integer, rest::binary>>, acc, stack, context, comb__line, comb__offset)
       when x0 >= 48 and x0 <= 57 do
    cron__56(rest, [x0] ++ acc, stack, context, comb__line, comb__offset + 1)
  end

  defp cron__55(rest, acc, stack, context, line, offset) do
    cron__54(rest, acc, stack, context, line, offset)
  end

  defp cron__54(rest, acc, [_ | stack], context, line, offset) do
    cron__57(rest, acc, stack, context, line, offset)
  end

  defp cron__56(rest, acc, [1 | stack], context, line, offset) do
    cron__57(rest, acc, stack, context, line, offset)
  end

  defp cron__56(rest, acc, [count | stack], context, line, offset) do
    cron__55(rest, acc, [count - 1 | stack], context, line, offset)
  end

  defp cron__57(rest, user_acc, [acc | stack], context, line, offset) do
    _ = user_acc

    cron__58(
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

  defp cron__58(rest, user_acc, [acc | stack], context, line, offset) do
    _ = user_acc
    cron__59(rest, [range: :lists.reverse(user_acc)] ++ acc, stack, context, line, offset)
  end

  defp cron__59(rest, acc, [_, previous_acc | stack], context, line, offset) do
    cron__41(rest, acc ++ previous_acc, stack, context, line, offset)
  end

  defp cron__60(_, _, [{rest, context, line, offset} | _] = stack, _, _, _) do
    cron__42(rest, [], stack, context, line, offset)
  end

  defp cron__61(<<"*", rest::binary>>, acc, stack, context, comb__line, comb__offset) do
    cron__62(rest, [wild: "*"] ++ acc, stack, context, comb__line, comb__offset + 1)
  end

  defp cron__61(rest, acc, stack, context, line, offset) do
    cron__60(rest, acc, stack, context, line, offset)
  end

  defp cron__62(rest, acc, [_, previous_acc | stack], context, line, offset) do
    cron__41(rest, acc ++ previous_acc, stack, context, line, offset)
  end

  defp cron__41(<<"/", rest::binary>>, acc, stack, context, comb__line, comb__offset) do
    cron__63(rest, [] ++ acc, stack, context, comb__line, comb__offset + 1)
  end

  defp cron__41(rest, _acc, stack, context, line, offset) do
    [acc | stack] = stack
    cron__38(rest, acc, stack, context, line, offset)
  end

  defp cron__63(rest, acc, stack, context, line, offset) do
    cron__64(rest, [], [acc | stack], context, line, offset)
  end

  defp cron__64(<<x0::integer, rest::binary>>, acc, stack, context, comb__line, comb__offset)
       when x0 >= 48 and x0 <= 57 do
    cron__65(rest, [x0 - 48] ++ acc, stack, context, comb__line, comb__offset + 1)
  end

  defp cron__64(rest, _acc, stack, context, line, offset) do
    [_, acc | stack] = stack
    cron__38(rest, acc, stack, context, line, offset)
  end

  defp cron__65(rest, acc, stack, context, line, offset) do
    cron__67(rest, acc, [1 | stack], context, line, offset)
  end

  defp cron__67(<<x0::integer, rest::binary>>, acc, stack, context, comb__line, comb__offset)
       when x0 >= 48 and x0 <= 57 do
    cron__68(rest, [x0] ++ acc, stack, context, comb__line, comb__offset + 1)
  end

  defp cron__67(rest, acc, stack, context, line, offset) do
    cron__66(rest, acc, stack, context, line, offset)
  end

  defp cron__66(rest, acc, [_ | stack], context, line, offset) do
    cron__69(rest, acc, stack, context, line, offset)
  end

  defp cron__68(rest, acc, [1 | stack], context, line, offset) do
    cron__69(rest, acc, stack, context, line, offset)
  end

  defp cron__68(rest, acc, [count | stack], context, line, offset) do
    cron__67(rest, acc, [count - 1 | stack], context, line, offset)
  end

  defp cron__69(rest, user_acc, [acc | stack], context, line, offset) do
    _ = user_acc

    cron__70(
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

  defp cron__70(rest, user_acc, [acc | stack], context, line, offset) do
    _ = user_acc
    cron__71(rest, [step: :lists.reverse(user_acc)] ++ acc, stack, context, line, offset)
  end

  defp cron__71(rest, acc, [_, previous_acc | stack], context, line, offset) do
    cron__2(rest, acc ++ previous_acc, stack, context, line, offset)
  end

  defp cron__2(rest, acc, stack, context, line, offset) do
    cron__73(rest, [], [{rest, acc, context, line, offset} | stack], context, line, offset)
  end

  defp cron__73(rest, acc, stack, context, line, offset) do
    cron__111(rest, [], [{rest, context, line, offset}, acc | stack], context, line, offset)
  end

  defp cron__75(<<",", rest::binary>>, acc, stack, context, comb__line, comb__offset) do
    cron__76(rest, [] ++ acc, stack, context, comb__line, comb__offset + 1)
  end

  defp cron__75(rest, _acc, stack, context, line, offset) do
    [_, acc | stack] = stack
    cron__72(rest, acc, stack, context, line, offset)
  end

  defp cron__76(rest, acc, [_, previous_acc | stack], context, line, offset) do
    cron__74(rest, acc ++ previous_acc, stack, context, line, offset)
  end

  defp cron__77(_, _, [{rest, context, line, offset} | _] = stack, _, _, _) do
    cron__75(rest, [], stack, context, line, offset)
  end

  defp cron__78(<<"*", rest::binary>>, acc, stack, context, comb__line, comb__offset) do
    cron__79(rest, [wild: "*"] ++ acc, stack, context, comb__line, comb__offset + 1)
  end

  defp cron__78(rest, acc, stack, context, line, offset) do
    cron__77(rest, acc, stack, context, line, offset)
  end

  defp cron__79(rest, acc, [_, previous_acc | stack], context, line, offset) do
    cron__74(rest, acc ++ previous_acc, stack, context, line, offset)
  end

  defp cron__80(_, _, [{rest, context, line, offset} | _] = stack, _, _, _) do
    cron__78(rest, [], stack, context, line, offset)
  end

  defp cron__81(rest, acc, stack, context, line, offset) do
    cron__82(rest, [], [acc | stack], context, line, offset)
  end

  defp cron__82(rest, acc, stack, context, line, offset) do
    cron__83(rest, [], [acc | stack], context, line, offset)
  end

  defp cron__83(<<x0::integer, rest::binary>>, acc, stack, context, comb__line, comb__offset)
       when x0 >= 48 and x0 <= 57 do
    cron__84(rest, [x0 - 48] ++ acc, stack, context, comb__line, comb__offset + 1)
  end

  defp cron__83(rest, _acc, stack, context, line, offset) do
    [_, acc | stack] = stack
    cron__80(rest, acc, stack, context, line, offset)
  end

  defp cron__84(rest, acc, stack, context, line, offset) do
    cron__86(rest, acc, [1 | stack], context, line, offset)
  end

  defp cron__86(<<x0::integer, rest::binary>>, acc, stack, context, comb__line, comb__offset)
       when x0 >= 48 and x0 <= 57 do
    cron__87(rest, [x0] ++ acc, stack, context, comb__line, comb__offset + 1)
  end

  defp cron__86(rest, acc, stack, context, line, offset) do
    cron__85(rest, acc, stack, context, line, offset)
  end

  defp cron__85(rest, acc, [_ | stack], context, line, offset) do
    cron__88(rest, acc, stack, context, line, offset)
  end

  defp cron__87(rest, acc, [1 | stack], context, line, offset) do
    cron__88(rest, acc, stack, context, line, offset)
  end

  defp cron__87(rest, acc, [count | stack], context, line, offset) do
    cron__86(rest, acc, [count - 1 | stack], context, line, offset)
  end

  defp cron__88(rest, user_acc, [acc | stack], context, line, offset) do
    _ = user_acc

    cron__89(
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

  defp cron__89(rest, user_acc, [acc | stack], context, line, offset) do
    _ = user_acc

    cron__90(
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

  defp cron__90(rest, acc, [_, previous_acc | stack], context, line, offset) do
    cron__74(rest, acc ++ previous_acc, stack, context, line, offset)
  end

  defp cron__91(_, _, [{rest, context, line, offset} | _] = stack, _, _, _) do
    cron__81(rest, [], stack, context, line, offset)
  end

  defp cron__92(rest, acc, stack, context, line, offset) do
    cron__93(rest, [], [acc | stack], context, line, offset)
  end

  defp cron__93(rest, acc, stack, context, line, offset) do
    cron__94(rest, [], [acc | stack], context, line, offset)
  end

  defp cron__94(<<x0::integer, rest::binary>>, acc, stack, context, comb__line, comb__offset)
       when x0 >= 48 and x0 <= 57 do
    cron__95(rest, [x0 - 48] ++ acc, stack, context, comb__line, comb__offset + 1)
  end

  defp cron__94(rest, _acc, stack, context, line, offset) do
    [_, acc | stack] = stack
    cron__91(rest, acc, stack, context, line, offset)
  end

  defp cron__95(rest, acc, stack, context, line, offset) do
    cron__97(rest, acc, [1 | stack], context, line, offset)
  end

  defp cron__97(<<x0::integer, rest::binary>>, acc, stack, context, comb__line, comb__offset)
       when x0 >= 48 and x0 <= 57 do
    cron__98(rest, [x0] ++ acc, stack, context, comb__line, comb__offset + 1)
  end

  defp cron__97(rest, acc, stack, context, line, offset) do
    cron__96(rest, acc, stack, context, line, offset)
  end

  defp cron__96(rest, acc, [_ | stack], context, line, offset) do
    cron__99(rest, acc, stack, context, line, offset)
  end

  defp cron__98(rest, acc, [1 | stack], context, line, offset) do
    cron__99(rest, acc, stack, context, line, offset)
  end

  defp cron__98(rest, acc, [count | stack], context, line, offset) do
    cron__97(rest, acc, [count - 1 | stack], context, line, offset)
  end

  defp cron__99(rest, user_acc, [acc | stack], context, line, offset) do
    _ = user_acc

    cron__100(
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

  defp cron__100(<<"-", rest::binary>>, acc, stack, context, comb__line, comb__offset) do
    cron__101(rest, [] ++ acc, stack, context, comb__line, comb__offset + 1)
  end

  defp cron__100(rest, _acc, stack, context, line, offset) do
    [acc | stack] = stack
    cron__91(rest, acc, stack, context, line, offset)
  end

  defp cron__101(rest, acc, stack, context, line, offset) do
    cron__102(rest, [], [acc | stack], context, line, offset)
  end

  defp cron__102(<<x0::integer, rest::binary>>, acc, stack, context, comb__line, comb__offset)
       when x0 >= 48 and x0 <= 57 do
    cron__103(rest, [x0 - 48] ++ acc, stack, context, comb__line, comb__offset + 1)
  end

  defp cron__102(rest, _acc, stack, context, line, offset) do
    [_, acc | stack] = stack
    cron__91(rest, acc, stack, context, line, offset)
  end

  defp cron__103(rest, acc, stack, context, line, offset) do
    cron__105(rest, acc, [1 | stack], context, line, offset)
  end

  defp cron__105(<<x0::integer, rest::binary>>, acc, stack, context, comb__line, comb__offset)
       when x0 >= 48 and x0 <= 57 do
    cron__106(rest, [x0] ++ acc, stack, context, comb__line, comb__offset + 1)
  end

  defp cron__105(rest, acc, stack, context, line, offset) do
    cron__104(rest, acc, stack, context, line, offset)
  end

  defp cron__104(rest, acc, [_ | stack], context, line, offset) do
    cron__107(rest, acc, stack, context, line, offset)
  end

  defp cron__106(rest, acc, [1 | stack], context, line, offset) do
    cron__107(rest, acc, stack, context, line, offset)
  end

  defp cron__106(rest, acc, [count | stack], context, line, offset) do
    cron__105(rest, acc, [count - 1 | stack], context, line, offset)
  end

  defp cron__107(rest, user_acc, [acc | stack], context, line, offset) do
    _ = user_acc

    cron__108(
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

  defp cron__108(rest, user_acc, [acc | stack], context, line, offset) do
    _ = user_acc
    cron__109(rest, [range: :lists.reverse(user_acc)] ++ acc, stack, context, line, offset)
  end

  defp cron__109(rest, acc, [_, previous_acc | stack], context, line, offset) do
    cron__74(rest, acc ++ previous_acc, stack, context, line, offset)
  end

  defp cron__110(_, _, [{rest, context, line, offset} | _] = stack, _, _, _) do
    cron__92(rest, [], stack, context, line, offset)
  end

  defp cron__111(rest, acc, stack, context, line, offset) do
    cron__112(rest, [], [acc | stack], context, line, offset)
  end

  defp cron__112(rest, acc, stack, context, line, offset) do
    cron__133(rest, [], [{rest, context, line, offset}, acc | stack], context, line, offset)
  end

  defp cron__114(rest, acc, stack, context, line, offset) do
    cron__115(rest, [], [acc | stack], context, line, offset)
  end

  defp cron__115(rest, acc, stack, context, line, offset) do
    cron__116(rest, [], [acc | stack], context, line, offset)
  end

  defp cron__116(<<x0::integer, rest::binary>>, acc, stack, context, comb__line, comb__offset)
       when x0 >= 48 and x0 <= 57 do
    cron__117(rest, [x0 - 48] ++ acc, stack, context, comb__line, comb__offset + 1)
  end

  defp cron__116(rest, _acc, stack, context, line, offset) do
    [_, _, _, _, acc | stack] = stack
    cron__110(rest, acc, stack, context, line, offset)
  end

  defp cron__117(rest, acc, stack, context, line, offset) do
    cron__119(rest, acc, [1 | stack], context, line, offset)
  end

  defp cron__119(<<x0::integer, rest::binary>>, acc, stack, context, comb__line, comb__offset)
       when x0 >= 48 and x0 <= 57 do
    cron__120(rest, [x0] ++ acc, stack, context, comb__line, comb__offset + 1)
  end

  defp cron__119(rest, acc, stack, context, line, offset) do
    cron__118(rest, acc, stack, context, line, offset)
  end

  defp cron__118(rest, acc, [_ | stack], context, line, offset) do
    cron__121(rest, acc, stack, context, line, offset)
  end

  defp cron__120(rest, acc, [1 | stack], context, line, offset) do
    cron__121(rest, acc, stack, context, line, offset)
  end

  defp cron__120(rest, acc, [count | stack], context, line, offset) do
    cron__119(rest, acc, [count - 1 | stack], context, line, offset)
  end

  defp cron__121(rest, user_acc, [acc | stack], context, line, offset) do
    _ = user_acc

    cron__122(
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

  defp cron__122(<<"-", rest::binary>>, acc, stack, context, comb__line, comb__offset) do
    cron__123(rest, [] ++ acc, stack, context, comb__line, comb__offset + 1)
  end

  defp cron__122(rest, _acc, stack, context, line, offset) do
    [_, _, _, acc | stack] = stack
    cron__110(rest, acc, stack, context, line, offset)
  end

  defp cron__123(rest, acc, stack, context, line, offset) do
    cron__124(rest, [], [acc | stack], context, line, offset)
  end

  defp cron__124(<<x0::integer, rest::binary>>, acc, stack, context, comb__line, comb__offset)
       when x0 >= 48 and x0 <= 57 do
    cron__125(rest, [x0 - 48] ++ acc, stack, context, comb__line, comb__offset + 1)
  end

  defp cron__124(rest, _acc, stack, context, line, offset) do
    [_, _, _, _, acc | stack] = stack
    cron__110(rest, acc, stack, context, line, offset)
  end

  defp cron__125(rest, acc, stack, context, line, offset) do
    cron__127(rest, acc, [1 | stack], context, line, offset)
  end

  defp cron__127(<<x0::integer, rest::binary>>, acc, stack, context, comb__line, comb__offset)
       when x0 >= 48 and x0 <= 57 do
    cron__128(rest, [x0] ++ acc, stack, context, comb__line, comb__offset + 1)
  end

  defp cron__127(rest, acc, stack, context, line, offset) do
    cron__126(rest, acc, stack, context, line, offset)
  end

  defp cron__126(rest, acc, [_ | stack], context, line, offset) do
    cron__129(rest, acc, stack, context, line, offset)
  end

  defp cron__128(rest, acc, [1 | stack], context, line, offset) do
    cron__129(rest, acc, stack, context, line, offset)
  end

  defp cron__128(rest, acc, [count | stack], context, line, offset) do
    cron__127(rest, acc, [count - 1 | stack], context, line, offset)
  end

  defp cron__129(rest, user_acc, [acc | stack], context, line, offset) do
    _ = user_acc

    cron__130(
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

  defp cron__130(rest, user_acc, [acc | stack], context, line, offset) do
    _ = user_acc
    cron__131(rest, [range: :lists.reverse(user_acc)] ++ acc, stack, context, line, offset)
  end

  defp cron__131(rest, acc, [_, previous_acc | stack], context, line, offset) do
    cron__113(rest, acc ++ previous_acc, stack, context, line, offset)
  end

  defp cron__132(_, _, [{rest, context, line, offset} | _] = stack, _, _, _) do
    cron__114(rest, [], stack, context, line, offset)
  end

  defp cron__133(<<"*", rest::binary>>, acc, stack, context, comb__line, comb__offset) do
    cron__134(rest, [wild: "*"] ++ acc, stack, context, comb__line, comb__offset + 1)
  end

  defp cron__133(rest, acc, stack, context, line, offset) do
    cron__132(rest, acc, stack, context, line, offset)
  end

  defp cron__134(rest, acc, [_, previous_acc | stack], context, line, offset) do
    cron__113(rest, acc ++ previous_acc, stack, context, line, offset)
  end

  defp cron__113(<<"/", rest::binary>>, acc, stack, context, comb__line, comb__offset) do
    cron__135(rest, [] ++ acc, stack, context, comb__line, comb__offset + 1)
  end

  defp cron__113(rest, _acc, stack, context, line, offset) do
    [acc | stack] = stack
    cron__110(rest, acc, stack, context, line, offset)
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
    cron__110(rest, acc, stack, context, line, offset)
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
    _ = user_acc

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

  defp cron__142(rest, user_acc, [acc | stack], context, line, offset) do
    _ = user_acc
    cron__143(rest, [step: :lists.reverse(user_acc)] ++ acc, stack, context, line, offset)
  end

  defp cron__143(rest, acc, [_, previous_acc | stack], context, line, offset) do
    cron__74(rest, acc ++ previous_acc, stack, context, line, offset)
  end

  defp cron__72(_, _, [{rest, acc, context, line, offset} | stack], _, _, _) do
    cron__144(rest, acc, stack, context, line, offset)
  end

  defp cron__74(
         inner_rest,
         inner_acc,
         [{rest, acc, context, line, offset} | stack],
         inner_context,
         inner_line,
         inner_offset
       ) do
    _ = {rest, acc, context, line, offset}

    cron__73(
      inner_rest,
      [],
      [{inner_rest, inner_acc ++ acc, inner_context, inner_line, inner_offset} | stack],
      inner_context,
      inner_line,
      inner_offset
    )
  end

  defp cron__144(rest, user_acc, [acc | stack], context, line, offset) do
    cron__145(rest, [minutes: :lists.reverse(user_acc)] ++ acc, stack, context, line, offset)
  end

  defp cron__145(rest, acc, stack, context, line, offset) do
    cron__146(rest, [], [acc | stack], context, line, offset)
  end

  defp cron__146(rest, acc, stack, context, line, offset) do
    cron__147(rest, [], [acc | stack], context, line, offset)
  end

  defp cron__147(<<x0::integer, rest::binary>>, acc, stack, context, comb__line, comb__offset)
       when x0 === 32 or x0 === 9 do
    cron__148(rest, acc, stack, context, comb__line, comb__offset + 1)
  end

  defp cron__147(rest, _acc, _stack, context, line, offset) do
    {:error, "expected ASCII character equal to ' ' or equal to '\\t'", rest, context, line,
     offset}
  end

  defp cron__148(<<x0::integer, rest::binary>>, acc, stack, context, comb__line, comb__offset)
       when x0 === 32 or x0 === 9 do
    cron__150(rest, acc, stack, context, comb__line, comb__offset + 1)
  end

  defp cron__148(rest, acc, stack, context, line, offset) do
    cron__149(rest, acc, stack, context, line, offset)
  end

  defp cron__150(rest, acc, stack, context, line, offset) do
    cron__148(rest, acc, stack, context, line, offset)
  end

  defp cron__149(rest, user_acc, [acc | stack], context, line, offset) do
    _ = user_acc
    cron__151(rest, acc, stack, context, line, offset)
  end

  defp cron__151(rest, user_acc, [acc | stack], context, line, offset) do
    _ = user_acc
    cron__152(rest, [] ++ acc, stack, context, line, offset)
  end

  defp cron__152(rest, acc, stack, context, line, offset) do
    cron__153(rest, [], [acc | stack], context, line, offset)
  end

  defp cron__153(rest, acc, stack, context, line, offset) do
    cron__191(rest, [], [{rest, context, line, offset}, acc | stack], context, line, offset)
  end

  defp cron__155(<<",", rest::binary>>, acc, stack, context, comb__line, comb__offset) do
    cron__156(rest, [] ++ acc, stack, context, comb__line, comb__offset + 1)
  end

  defp cron__155(rest, _acc, _stack, context, line, offset) do
    {:error,
     "expected string \"*\" or ASCII character in the range '0' to '9', followed by ASCII character in the range '0' to '9', followed by string \"-\", followed by ASCII character in the range '0' to '9', followed by ASCII character in the range '0' to '9', followed by string \"/\", followed by ASCII character in the range '0' to '9', followed by ASCII character in the range '0' to '9' or ASCII character in the range '0' to '9', followed by ASCII character in the range '0' to '9', followed by string \"-\", followed by ASCII character in the range '0' to '9', followed by ASCII character in the range '0' to '9' or ASCII character in the range '0' to '9', followed by ASCII character in the range '0' to '9' or string \"*\" or string \",\"",
     rest, context, line, offset}
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

  defp cron__162(rest, acc, stack, context, line, offset) do
    cron__163(rest, [], [acc | stack], context, line, offset)
  end

  defp cron__163(<<x0::integer, rest::binary>>, acc, stack, context, comb__line, comb__offset)
       when x0 >= 48 and x0 <= 57 do
    cron__164(rest, [x0 - 48] ++ acc, stack, context, comb__line, comb__offset + 1)
  end

  defp cron__163(rest, _acc, stack, context, line, offset) do
    [_, acc | stack] = stack
    cron__160(rest, acc, stack, context, line, offset)
  end

  defp cron__164(rest, acc, stack, context, line, offset) do
    cron__166(rest, acc, [1 | stack], context, line, offset)
  end

  defp cron__166(<<x0::integer, rest::binary>>, acc, stack, context, comb__line, comb__offset)
       when x0 >= 48 and x0 <= 57 do
    cron__167(rest, [x0] ++ acc, stack, context, comb__line, comb__offset + 1)
  end

  defp cron__166(rest, acc, stack, context, line, offset) do
    cron__165(rest, acc, stack, context, line, offset)
  end

  defp cron__165(rest, acc, [_ | stack], context, line, offset) do
    cron__168(rest, acc, stack, context, line, offset)
  end

  defp cron__167(rest, acc, [1 | stack], context, line, offset) do
    cron__168(rest, acc, stack, context, line, offset)
  end

  defp cron__167(rest, acc, [count | stack], context, line, offset) do
    cron__166(rest, acc, [count - 1 | stack], context, line, offset)
  end

  defp cron__168(rest, user_acc, [acc | stack], context, line, offset) do
    _ = user_acc

    cron__169(
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

  defp cron__169(rest, user_acc, [acc | stack], context, line, offset) do
    _ = user_acc

    cron__170(
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

  defp cron__170(rest, acc, [_, previous_acc | stack], context, line, offset) do
    cron__154(rest, acc ++ previous_acc, stack, context, line, offset)
  end

  defp cron__171(_, _, [{rest, context, line, offset} | _] = stack, _, _, _) do
    cron__161(rest, [], stack, context, line, offset)
  end

  defp cron__172(rest, acc, stack, context, line, offset) do
    cron__173(rest, [], [acc | stack], context, line, offset)
  end

  defp cron__173(rest, acc, stack, context, line, offset) do
    cron__174(rest, [], [acc | stack], context, line, offset)
  end

  defp cron__174(<<x0::integer, rest::binary>>, acc, stack, context, comb__line, comb__offset)
       when x0 >= 48 and x0 <= 57 do
    cron__175(rest, [x0 - 48] ++ acc, stack, context, comb__line, comb__offset + 1)
  end

  defp cron__174(rest, _acc, stack, context, line, offset) do
    [_, acc | stack] = stack
    cron__171(rest, acc, stack, context, line, offset)
  end

  defp cron__175(rest, acc, stack, context, line, offset) do
    cron__177(rest, acc, [1 | stack], context, line, offset)
  end

  defp cron__177(<<x0::integer, rest::binary>>, acc, stack, context, comb__line, comb__offset)
       when x0 >= 48 and x0 <= 57 do
    cron__178(rest, [x0] ++ acc, stack, context, comb__line, comb__offset + 1)
  end

  defp cron__177(rest, acc, stack, context, line, offset) do
    cron__176(rest, acc, stack, context, line, offset)
  end

  defp cron__176(rest, acc, [_ | stack], context, line, offset) do
    cron__179(rest, acc, stack, context, line, offset)
  end

  defp cron__178(rest, acc, [1 | stack], context, line, offset) do
    cron__179(rest, acc, stack, context, line, offset)
  end

  defp cron__178(rest, acc, [count | stack], context, line, offset) do
    cron__177(rest, acc, [count - 1 | stack], context, line, offset)
  end

  defp cron__179(rest, user_acc, [acc | stack], context, line, offset) do
    _ = user_acc

    cron__180(
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

  defp cron__180(<<"-", rest::binary>>, acc, stack, context, comb__line, comb__offset) do
    cron__181(rest, [] ++ acc, stack, context, comb__line, comb__offset + 1)
  end

  defp cron__180(rest, _acc, stack, context, line, offset) do
    [acc | stack] = stack
    cron__171(rest, acc, stack, context, line, offset)
  end

  defp cron__181(rest, acc, stack, context, line, offset) do
    cron__182(rest, [], [acc | stack], context, line, offset)
  end

  defp cron__182(<<x0::integer, rest::binary>>, acc, stack, context, comb__line, comb__offset)
       when x0 >= 48 and x0 <= 57 do
    cron__183(rest, [x0 - 48] ++ acc, stack, context, comb__line, comb__offset + 1)
  end

  defp cron__182(rest, _acc, stack, context, line, offset) do
    [_, acc | stack] = stack
    cron__171(rest, acc, stack, context, line, offset)
  end

  defp cron__183(rest, acc, stack, context, line, offset) do
    cron__185(rest, acc, [1 | stack], context, line, offset)
  end

  defp cron__185(<<x0::integer, rest::binary>>, acc, stack, context, comb__line, comb__offset)
       when x0 >= 48 and x0 <= 57 do
    cron__186(rest, [x0] ++ acc, stack, context, comb__line, comb__offset + 1)
  end

  defp cron__185(rest, acc, stack, context, line, offset) do
    cron__184(rest, acc, stack, context, line, offset)
  end

  defp cron__184(rest, acc, [_ | stack], context, line, offset) do
    cron__187(rest, acc, stack, context, line, offset)
  end

  defp cron__186(rest, acc, [1 | stack], context, line, offset) do
    cron__187(rest, acc, stack, context, line, offset)
  end

  defp cron__186(rest, acc, [count | stack], context, line, offset) do
    cron__185(rest, acc, [count - 1 | stack], context, line, offset)
  end

  defp cron__187(rest, user_acc, [acc | stack], context, line, offset) do
    _ = user_acc

    cron__188(
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

  defp cron__188(rest, user_acc, [acc | stack], context, line, offset) do
    _ = user_acc
    cron__189(rest, [range: :lists.reverse(user_acc)] ++ acc, stack, context, line, offset)
  end

  defp cron__189(rest, acc, [_, previous_acc | stack], context, line, offset) do
    cron__154(rest, acc ++ previous_acc, stack, context, line, offset)
  end

  defp cron__190(_, _, [{rest, context, line, offset} | _] = stack, _, _, _) do
    cron__172(rest, [], stack, context, line, offset)
  end

  defp cron__191(rest, acc, stack, context, line, offset) do
    cron__192(rest, [], [acc | stack], context, line, offset)
  end

  defp cron__192(rest, acc, stack, context, line, offset) do
    cron__213(rest, [], [{rest, context, line, offset}, acc | stack], context, line, offset)
  end

  defp cron__194(rest, acc, stack, context, line, offset) do
    cron__195(rest, [], [acc | stack], context, line, offset)
  end

  defp cron__195(rest, acc, stack, context, line, offset) do
    cron__196(rest, [], [acc | stack], context, line, offset)
  end

  defp cron__196(<<x0::integer, rest::binary>>, acc, stack, context, comb__line, comb__offset)
       when x0 >= 48 and x0 <= 57 do
    cron__197(rest, [x0 - 48] ++ acc, stack, context, comb__line, comb__offset + 1)
  end

  defp cron__196(rest, _acc, stack, context, line, offset) do
    [_, _, _, _, acc | stack] = stack
    cron__190(rest, acc, stack, context, line, offset)
  end

  defp cron__197(rest, acc, stack, context, line, offset) do
    cron__199(rest, acc, [1 | stack], context, line, offset)
  end

  defp cron__199(<<x0::integer, rest::binary>>, acc, stack, context, comb__line, comb__offset)
       when x0 >= 48 and x0 <= 57 do
    cron__200(rest, [x0] ++ acc, stack, context, comb__line, comb__offset + 1)
  end

  defp cron__199(rest, acc, stack, context, line, offset) do
    cron__198(rest, acc, stack, context, line, offset)
  end

  defp cron__198(rest, acc, [_ | stack], context, line, offset) do
    cron__201(rest, acc, stack, context, line, offset)
  end

  defp cron__200(rest, acc, [1 | stack], context, line, offset) do
    cron__201(rest, acc, stack, context, line, offset)
  end

  defp cron__200(rest, acc, [count | stack], context, line, offset) do
    cron__199(rest, acc, [count - 1 | stack], context, line, offset)
  end

  defp cron__201(rest, user_acc, [acc | stack], context, line, offset) do
    _ = user_acc

    cron__202(
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

  defp cron__202(<<"-", rest::binary>>, acc, stack, context, comb__line, comb__offset) do
    cron__203(rest, [] ++ acc, stack, context, comb__line, comb__offset + 1)
  end

  defp cron__202(rest, _acc, stack, context, line, offset) do
    [_, _, _, acc | stack] = stack
    cron__190(rest, acc, stack, context, line, offset)
  end

  defp cron__203(rest, acc, stack, context, line, offset) do
    cron__204(rest, [], [acc | stack], context, line, offset)
  end

  defp cron__204(<<x0::integer, rest::binary>>, acc, stack, context, comb__line, comb__offset)
       when x0 >= 48 and x0 <= 57 do
    cron__205(rest, [x0 - 48] ++ acc, stack, context, comb__line, comb__offset + 1)
  end

  defp cron__204(rest, _acc, stack, context, line, offset) do
    [_, _, _, _, acc | stack] = stack
    cron__190(rest, acc, stack, context, line, offset)
  end

  defp cron__205(rest, acc, stack, context, line, offset) do
    cron__207(rest, acc, [1 | stack], context, line, offset)
  end

  defp cron__207(<<x0::integer, rest::binary>>, acc, stack, context, comb__line, comb__offset)
       when x0 >= 48 and x0 <= 57 do
    cron__208(rest, [x0] ++ acc, stack, context, comb__line, comb__offset + 1)
  end

  defp cron__207(rest, acc, stack, context, line, offset) do
    cron__206(rest, acc, stack, context, line, offset)
  end

  defp cron__206(rest, acc, [_ | stack], context, line, offset) do
    cron__209(rest, acc, stack, context, line, offset)
  end

  defp cron__208(rest, acc, [1 | stack], context, line, offset) do
    cron__209(rest, acc, stack, context, line, offset)
  end

  defp cron__208(rest, acc, [count | stack], context, line, offset) do
    cron__207(rest, acc, [count - 1 | stack], context, line, offset)
  end

  defp cron__209(rest, user_acc, [acc | stack], context, line, offset) do
    _ = user_acc

    cron__210(
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

  defp cron__210(rest, user_acc, [acc | stack], context, line, offset) do
    _ = user_acc
    cron__211(rest, [range: :lists.reverse(user_acc)] ++ acc, stack, context, line, offset)
  end

  defp cron__211(rest, acc, [_, previous_acc | stack], context, line, offset) do
    cron__193(rest, acc ++ previous_acc, stack, context, line, offset)
  end

  defp cron__212(_, _, [{rest, context, line, offset} | _] = stack, _, _, _) do
    cron__194(rest, [], stack, context, line, offset)
  end

  defp cron__213(<<"*", rest::binary>>, acc, stack, context, comb__line, comb__offset) do
    cron__214(rest, [wild: "*"] ++ acc, stack, context, comb__line, comb__offset + 1)
  end

  defp cron__213(rest, acc, stack, context, line, offset) do
    cron__212(rest, acc, stack, context, line, offset)
  end

  defp cron__214(rest, acc, [_, previous_acc | stack], context, line, offset) do
    cron__193(rest, acc ++ previous_acc, stack, context, line, offset)
  end

  defp cron__193(<<"/", rest::binary>>, acc, stack, context, comb__line, comb__offset) do
    cron__215(rest, [] ++ acc, stack, context, comb__line, comb__offset + 1)
  end

  defp cron__193(rest, _acc, stack, context, line, offset) do
    [acc | stack] = stack
    cron__190(rest, acc, stack, context, line, offset)
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
    cron__190(rest, acc, stack, context, line, offset)
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
    _ = user_acc

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
    _ = user_acc
    cron__223(rest, [step: :lists.reverse(user_acc)] ++ acc, stack, context, line, offset)
  end

  defp cron__223(rest, acc, [_, previous_acc | stack], context, line, offset) do
    cron__154(rest, acc ++ previous_acc, stack, context, line, offset)
  end

  defp cron__154(rest, acc, stack, context, line, offset) do
    cron__225(rest, [], [{rest, acc, context, line, offset} | stack], context, line, offset)
  end

  defp cron__225(rest, acc, stack, context, line, offset) do
    cron__263(rest, [], [{rest, context, line, offset}, acc | stack], context, line, offset)
  end

  defp cron__227(<<",", rest::binary>>, acc, stack, context, comb__line, comb__offset) do
    cron__228(rest, [] ++ acc, stack, context, comb__line, comb__offset + 1)
  end

  defp cron__227(rest, _acc, stack, context, line, offset) do
    [_, acc | stack] = stack
    cron__224(rest, acc, stack, context, line, offset)
  end

  defp cron__228(rest, acc, [_, previous_acc | stack], context, line, offset) do
    cron__226(rest, acc ++ previous_acc, stack, context, line, offset)
  end

  defp cron__229(_, _, [{rest, context, line, offset} | _] = stack, _, _, _) do
    cron__227(rest, [], stack, context, line, offset)
  end

  defp cron__230(<<"*", rest::binary>>, acc, stack, context, comb__line, comb__offset) do
    cron__231(rest, [wild: "*"] ++ acc, stack, context, comb__line, comb__offset + 1)
  end

  defp cron__230(rest, acc, stack, context, line, offset) do
    cron__229(rest, acc, stack, context, line, offset)
  end

  defp cron__231(rest, acc, [_, previous_acc | stack], context, line, offset) do
    cron__226(rest, acc ++ previous_acc, stack, context, line, offset)
  end

  defp cron__232(_, _, [{rest, context, line, offset} | _] = stack, _, _, _) do
    cron__230(rest, [], stack, context, line, offset)
  end

  defp cron__233(rest, acc, stack, context, line, offset) do
    cron__234(rest, [], [acc | stack], context, line, offset)
  end

  defp cron__234(rest, acc, stack, context, line, offset) do
    cron__235(rest, [], [acc | stack], context, line, offset)
  end

  defp cron__235(<<x0::integer, rest::binary>>, acc, stack, context, comb__line, comb__offset)
       when x0 >= 48 and x0 <= 57 do
    cron__236(rest, [x0 - 48] ++ acc, stack, context, comb__line, comb__offset + 1)
  end

  defp cron__235(rest, _acc, stack, context, line, offset) do
    [_, acc | stack] = stack
    cron__232(rest, acc, stack, context, line, offset)
  end

  defp cron__236(rest, acc, stack, context, line, offset) do
    cron__238(rest, acc, [1 | stack], context, line, offset)
  end

  defp cron__238(<<x0::integer, rest::binary>>, acc, stack, context, comb__line, comb__offset)
       when x0 >= 48 and x0 <= 57 do
    cron__239(rest, [x0] ++ acc, stack, context, comb__line, comb__offset + 1)
  end

  defp cron__238(rest, acc, stack, context, line, offset) do
    cron__237(rest, acc, stack, context, line, offset)
  end

  defp cron__237(rest, acc, [_ | stack], context, line, offset) do
    cron__240(rest, acc, stack, context, line, offset)
  end

  defp cron__239(rest, acc, [1 | stack], context, line, offset) do
    cron__240(rest, acc, stack, context, line, offset)
  end

  defp cron__239(rest, acc, [count | stack], context, line, offset) do
    cron__238(rest, acc, [count - 1 | stack], context, line, offset)
  end

  defp cron__240(rest, user_acc, [acc | stack], context, line, offset) do
    _ = user_acc

    cron__241(
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

  defp cron__241(rest, user_acc, [acc | stack], context, line, offset) do
    _ = user_acc

    cron__242(
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

  defp cron__242(rest, acc, [_, previous_acc | stack], context, line, offset) do
    cron__226(rest, acc ++ previous_acc, stack, context, line, offset)
  end

  defp cron__243(_, _, [{rest, context, line, offset} | _] = stack, _, _, _) do
    cron__233(rest, [], stack, context, line, offset)
  end

  defp cron__244(rest, acc, stack, context, line, offset) do
    cron__245(rest, [], [acc | stack], context, line, offset)
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
    cron__243(rest, acc, stack, context, line, offset)
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
    _ = user_acc

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

  defp cron__252(<<"-", rest::binary>>, acc, stack, context, comb__line, comb__offset) do
    cron__253(rest, [] ++ acc, stack, context, comb__line, comb__offset + 1)
  end

  defp cron__252(rest, _acc, stack, context, line, offset) do
    [acc | stack] = stack
    cron__243(rest, acc, stack, context, line, offset)
  end

  defp cron__253(rest, acc, stack, context, line, offset) do
    cron__254(rest, [], [acc | stack], context, line, offset)
  end

  defp cron__254(<<x0::integer, rest::binary>>, acc, stack, context, comb__line, comb__offset)
       when x0 >= 48 and x0 <= 57 do
    cron__255(rest, [x0 - 48] ++ acc, stack, context, comb__line, comb__offset + 1)
  end

  defp cron__254(rest, _acc, stack, context, line, offset) do
    [_, acc | stack] = stack
    cron__243(rest, acc, stack, context, line, offset)
  end

  defp cron__255(rest, acc, stack, context, line, offset) do
    cron__257(rest, acc, [1 | stack], context, line, offset)
  end

  defp cron__257(<<x0::integer, rest::binary>>, acc, stack, context, comb__line, comb__offset)
       when x0 >= 48 and x0 <= 57 do
    cron__258(rest, [x0] ++ acc, stack, context, comb__line, comb__offset + 1)
  end

  defp cron__257(rest, acc, stack, context, line, offset) do
    cron__256(rest, acc, stack, context, line, offset)
  end

  defp cron__256(rest, acc, [_ | stack], context, line, offset) do
    cron__259(rest, acc, stack, context, line, offset)
  end

  defp cron__258(rest, acc, [1 | stack], context, line, offset) do
    cron__259(rest, acc, stack, context, line, offset)
  end

  defp cron__258(rest, acc, [count | stack], context, line, offset) do
    cron__257(rest, acc, [count - 1 | stack], context, line, offset)
  end

  defp cron__259(rest, user_acc, [acc | stack], context, line, offset) do
    _ = user_acc

    cron__260(
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

  defp cron__260(rest, user_acc, [acc | stack], context, line, offset) do
    _ = user_acc
    cron__261(rest, [range: :lists.reverse(user_acc)] ++ acc, stack, context, line, offset)
  end

  defp cron__261(rest, acc, [_, previous_acc | stack], context, line, offset) do
    cron__226(rest, acc ++ previous_acc, stack, context, line, offset)
  end

  defp cron__262(_, _, [{rest, context, line, offset} | _] = stack, _, _, _) do
    cron__244(rest, [], stack, context, line, offset)
  end

  defp cron__263(rest, acc, stack, context, line, offset) do
    cron__264(rest, [], [acc | stack], context, line, offset)
  end

  defp cron__264(rest, acc, stack, context, line, offset) do
    cron__285(rest, [], [{rest, context, line, offset}, acc | stack], context, line, offset)
  end

  defp cron__266(rest, acc, stack, context, line, offset) do
    cron__267(rest, [], [acc | stack], context, line, offset)
  end

  defp cron__267(rest, acc, stack, context, line, offset) do
    cron__268(rest, [], [acc | stack], context, line, offset)
  end

  defp cron__268(<<x0::integer, rest::binary>>, acc, stack, context, comb__line, comb__offset)
       when x0 >= 48 and x0 <= 57 do
    cron__269(rest, [x0 - 48] ++ acc, stack, context, comb__line, comb__offset + 1)
  end

  defp cron__268(rest, _acc, stack, context, line, offset) do
    [_, _, _, _, acc | stack] = stack
    cron__262(rest, acc, stack, context, line, offset)
  end

  defp cron__269(rest, acc, stack, context, line, offset) do
    cron__271(rest, acc, [1 | stack], context, line, offset)
  end

  defp cron__271(<<x0::integer, rest::binary>>, acc, stack, context, comb__line, comb__offset)
       when x0 >= 48 and x0 <= 57 do
    cron__272(rest, [x0] ++ acc, stack, context, comb__line, comb__offset + 1)
  end

  defp cron__271(rest, acc, stack, context, line, offset) do
    cron__270(rest, acc, stack, context, line, offset)
  end

  defp cron__270(rest, acc, [_ | stack], context, line, offset) do
    cron__273(rest, acc, stack, context, line, offset)
  end

  defp cron__272(rest, acc, [1 | stack], context, line, offset) do
    cron__273(rest, acc, stack, context, line, offset)
  end

  defp cron__272(rest, acc, [count | stack], context, line, offset) do
    cron__271(rest, acc, [count - 1 | stack], context, line, offset)
  end

  defp cron__273(rest, user_acc, [acc | stack], context, line, offset) do
    _ = user_acc

    cron__274(
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

  defp cron__274(<<"-", rest::binary>>, acc, stack, context, comb__line, comb__offset) do
    cron__275(rest, [] ++ acc, stack, context, comb__line, comb__offset + 1)
  end

  defp cron__274(rest, _acc, stack, context, line, offset) do
    [_, _, _, acc | stack] = stack
    cron__262(rest, acc, stack, context, line, offset)
  end

  defp cron__275(rest, acc, stack, context, line, offset) do
    cron__276(rest, [], [acc | stack], context, line, offset)
  end

  defp cron__276(<<x0::integer, rest::binary>>, acc, stack, context, comb__line, comb__offset)
       when x0 >= 48 and x0 <= 57 do
    cron__277(rest, [x0 - 48] ++ acc, stack, context, comb__line, comb__offset + 1)
  end

  defp cron__276(rest, _acc, stack, context, line, offset) do
    [_, _, _, _, acc | stack] = stack
    cron__262(rest, acc, stack, context, line, offset)
  end

  defp cron__277(rest, acc, stack, context, line, offset) do
    cron__279(rest, acc, [1 | stack], context, line, offset)
  end

  defp cron__279(<<x0::integer, rest::binary>>, acc, stack, context, comb__line, comb__offset)
       when x0 >= 48 and x0 <= 57 do
    cron__280(rest, [x0] ++ acc, stack, context, comb__line, comb__offset + 1)
  end

  defp cron__279(rest, acc, stack, context, line, offset) do
    cron__278(rest, acc, stack, context, line, offset)
  end

  defp cron__278(rest, acc, [_ | stack], context, line, offset) do
    cron__281(rest, acc, stack, context, line, offset)
  end

  defp cron__280(rest, acc, [1 | stack], context, line, offset) do
    cron__281(rest, acc, stack, context, line, offset)
  end

  defp cron__280(rest, acc, [count | stack], context, line, offset) do
    cron__279(rest, acc, [count - 1 | stack], context, line, offset)
  end

  defp cron__281(rest, user_acc, [acc | stack], context, line, offset) do
    _ = user_acc

    cron__282(
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

  defp cron__282(rest, user_acc, [acc | stack], context, line, offset) do
    _ = user_acc
    cron__283(rest, [range: :lists.reverse(user_acc)] ++ acc, stack, context, line, offset)
  end

  defp cron__283(rest, acc, [_, previous_acc | stack], context, line, offset) do
    cron__265(rest, acc ++ previous_acc, stack, context, line, offset)
  end

  defp cron__284(_, _, [{rest, context, line, offset} | _] = stack, _, _, _) do
    cron__266(rest, [], stack, context, line, offset)
  end

  defp cron__285(<<"*", rest::binary>>, acc, stack, context, comb__line, comb__offset) do
    cron__286(rest, [wild: "*"] ++ acc, stack, context, comb__line, comb__offset + 1)
  end

  defp cron__285(rest, acc, stack, context, line, offset) do
    cron__284(rest, acc, stack, context, line, offset)
  end

  defp cron__286(rest, acc, [_, previous_acc | stack], context, line, offset) do
    cron__265(rest, acc ++ previous_acc, stack, context, line, offset)
  end

  defp cron__265(<<"/", rest::binary>>, acc, stack, context, comb__line, comb__offset) do
    cron__287(rest, [] ++ acc, stack, context, comb__line, comb__offset + 1)
  end

  defp cron__265(rest, _acc, stack, context, line, offset) do
    [acc | stack] = stack
    cron__262(rest, acc, stack, context, line, offset)
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
    cron__262(rest, acc, stack, context, line, offset)
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
    _ = user_acc

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

  defp cron__294(rest, user_acc, [acc | stack], context, line, offset) do
    _ = user_acc
    cron__295(rest, [step: :lists.reverse(user_acc)] ++ acc, stack, context, line, offset)
  end

  defp cron__295(rest, acc, [_, previous_acc | stack], context, line, offset) do
    cron__226(rest, acc ++ previous_acc, stack, context, line, offset)
  end

  defp cron__224(_, _, [{rest, acc, context, line, offset} | stack], _, _, _) do
    cron__296(rest, acc, stack, context, line, offset)
  end

  defp cron__226(
         inner_rest,
         inner_acc,
         [{rest, acc, context, line, offset} | stack],
         inner_context,
         inner_line,
         inner_offset
       ) do
    _ = {rest, acc, context, line, offset}

    cron__225(
      inner_rest,
      [],
      [{inner_rest, inner_acc ++ acc, inner_context, inner_line, inner_offset} | stack],
      inner_context,
      inner_line,
      inner_offset
    )
  end

  defp cron__296(rest, user_acc, [acc | stack], context, line, offset) do
    _ = user_acc
    cron__297(rest, [hours: :lists.reverse(user_acc)] ++ acc, stack, context, line, offset)
  end

  defp cron__297(rest, acc, stack, context, line, offset) do
    cron__298(rest, [], [acc | stack], context, line, offset)
  end

  defp cron__298(rest, acc, stack, context, line, offset) do
    cron__299(rest, [], [acc | stack], context, line, offset)
  end

  defp cron__299(<<x0::integer, rest::binary>>, acc, stack, context, comb__line, comb__offset)
       when x0 === 32 or x0 === 9 do
    cron__300(rest, acc, stack, context, comb__line, comb__offset + 1)
  end

  defp cron__299(rest, _acc, _stack, context, line, offset) do
    {:error, "expected ASCII character equal to ' ' or equal to '\\t'", rest, context, line,
     offset}
  end

  defp cron__300(<<x0::integer, rest::binary>>, acc, stack, context, comb__line, comb__offset)
       when x0 === 32 or x0 === 9 do
    cron__302(rest, acc, stack, context, comb__line, comb__offset + 1)
  end

  defp cron__300(rest, acc, stack, context, line, offset) do
    cron__301(rest, acc, stack, context, line, offset)
  end

  defp cron__302(rest, acc, stack, context, line, offset) do
    cron__300(rest, acc, stack, context, line, offset)
  end

  defp cron__301(rest, user_acc, [acc | stack], context, line, offset) do
    _ = user_acc
    cron__303(rest, acc, stack, context, line, offset)
  end

  defp cron__303(rest, user_acc, [acc | stack], context, line, offset) do
    _ = user_acc
    cron__304(rest, [] ++ acc, stack, context, line, offset)
  end

  defp cron__304(rest, acc, stack, context, line, offset) do
    cron__305(rest, [], [acc | stack], context, line, offset)
  end

  defp cron__305(rest, acc, stack, context, line, offset) do
    cron__343(rest, [], [{rest, context, line, offset}, acc | stack], context, line, offset)
  end

  defp cron__307(<<",", rest::binary>>, acc, stack, context, comb__line, comb__offset) do
    cron__308(rest, [] ++ acc, stack, context, comb__line, comb__offset + 1)
  end

  defp cron__307(rest, _acc, _stack, context, line, offset) do
    {:error,
     "expected string \"*\" or ASCII character in the range '0' to '9', followed by ASCII character in the range '0' to '9', followed by string \"-\", followed by ASCII character in the range '0' to '9', followed by ASCII character in the range '0' to '9', followed by string \"/\", followed by ASCII character in the range '0' to '9', followed by ASCII character in the range '0' to '9' or ASCII character in the range '0' to '9', followed by ASCII character in the range '0' to '9', followed by string \"-\", followed by ASCII character in the range '0' to '9', followed by ASCII character in the range '0' to '9' or ASCII character in the range '0' to '9', followed by ASCII character in the range '0' to '9' or string \"*\" or string \",\"",
     rest, context, line, offset}
  end

  defp cron__308(rest, acc, [_, previous_acc | stack], context, line, offset) do
    cron__306(rest, acc ++ previous_acc, stack, context, line, offset)
  end

  defp cron__309(_, _, [{rest, context, line, offset} | _] = stack, _, _, _) do
    cron__307(rest, [], stack, context, line, offset)
  end

  defp cron__310(<<"*", rest::binary>>, acc, stack, context, comb__line, comb__offset) do
    cron__311(rest, [wild: "*"] ++ acc, stack, context, comb__line, comb__offset + 1)
  end

  defp cron__310(rest, acc, stack, context, line, offset) do
    cron__309(rest, acc, stack, context, line, offset)
  end

  defp cron__311(rest, acc, [_, previous_acc | stack], context, line, offset) do
    cron__306(rest, acc ++ previous_acc, stack, context, line, offset)
  end

  defp cron__312(_, _, [{rest, context, line, offset} | _] = stack, _, _, _) do
    cron__310(rest, [], stack, context, line, offset)
  end

  defp cron__313(rest, acc, stack, context, line, offset) do
    cron__314(rest, [], [acc | stack], context, line, offset)
  end

  defp cron__314(rest, acc, stack, context, line, offset) do
    cron__315(rest, [], [acc | stack], context, line, offset)
  end

  defp cron__315(<<x0::integer, rest::binary>>, acc, stack, context, comb__line, comb__offset)
       when x0 >= 48 and x0 <= 57 do
    cron__316(rest, [x0 - 48] ++ acc, stack, context, comb__line, comb__offset + 1)
  end

  defp cron__315(rest, _acc, stack, context, line, offset) do
    [_, acc | stack] = stack
    cron__312(rest, acc, stack, context, line, offset)
  end

  defp cron__316(rest, acc, stack, context, line, offset) do
    cron__318(rest, acc, [1 | stack], context, line, offset)
  end

  defp cron__318(<<x0::integer, rest::binary>>, acc, stack, context, comb__line, comb__offset)
       when x0 >= 48 and x0 <= 57 do
    cron__319(rest, [x0] ++ acc, stack, context, comb__line, comb__offset + 1)
  end

  defp cron__318(rest, acc, stack, context, line, offset) do
    cron__317(rest, acc, stack, context, line, offset)
  end

  defp cron__317(rest, acc, [_ | stack], context, line, offset) do
    cron__320(rest, acc, stack, context, line, offset)
  end

  defp cron__319(rest, acc, [1 | stack], context, line, offset) do
    cron__320(rest, acc, stack, context, line, offset)
  end

  defp cron__319(rest, acc, [count | stack], context, line, offset) do
    cron__318(rest, acc, [count - 1 | stack], context, line, offset)
  end

  defp cron__320(rest, user_acc, [acc | stack], context, line, offset) do
    _ = user_acc

    cron__321(
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

  defp cron__321(rest, user_acc, [acc | stack], context, line, offset) do
    _ = user_acc

    cron__322(
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

  defp cron__322(rest, acc, [_, previous_acc | stack], context, line, offset) do
    cron__306(rest, acc ++ previous_acc, stack, context, line, offset)
  end

  defp cron__323(_, _, [{rest, context, line, offset} | _] = stack, _, _, _) do
    cron__313(rest, [], stack, context, line, offset)
  end

  defp cron__324(rest, acc, stack, context, line, offset) do
    cron__325(rest, [], [acc | stack], context, line, offset)
  end

  defp cron__325(rest, acc, stack, context, line, offset) do
    cron__326(rest, [], [acc | stack], context, line, offset)
  end

  defp cron__326(<<x0::integer, rest::binary>>, acc, stack, context, comb__line, comb__offset)
       when x0 >= 48 and x0 <= 57 do
    cron__327(rest, [x0 - 48] ++ acc, stack, context, comb__line, comb__offset + 1)
  end

  defp cron__326(rest, _acc, stack, context, line, offset) do
    [_, acc | stack] = stack
    cron__323(rest, acc, stack, context, line, offset)
  end

  defp cron__327(rest, acc, stack, context, line, offset) do
    cron__329(rest, acc, [1 | stack], context, line, offset)
  end

  defp cron__329(<<x0::integer, rest::binary>>, acc, stack, context, comb__line, comb__offset)
       when x0 >= 48 and x0 <= 57 do
    cron__330(rest, [x0] ++ acc, stack, context, comb__line, comb__offset + 1)
  end

  defp cron__329(rest, acc, stack, context, line, offset) do
    cron__328(rest, acc, stack, context, line, offset)
  end

  defp cron__328(rest, acc, [_ | stack], context, line, offset) do
    cron__331(rest, acc, stack, context, line, offset)
  end

  defp cron__330(rest, acc, [1 | stack], context, line, offset) do
    cron__331(rest, acc, stack, context, line, offset)
  end

  defp cron__330(rest, acc, [count | stack], context, line, offset) do
    cron__329(rest, acc, [count - 1 | stack], context, line, offset)
  end

  defp cron__331(rest, user_acc, [acc | stack], context, line, offset) do
    _ = user_acc

    cron__332(
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

  defp cron__332(<<"-", rest::binary>>, acc, stack, context, comb__line, comb__offset) do
    cron__333(rest, [] ++ acc, stack, context, comb__line, comb__offset + 1)
  end

  defp cron__332(rest, _acc, stack, context, line, offset) do
    [acc | stack] = stack
    cron__323(rest, acc, stack, context, line, offset)
  end

  defp cron__333(rest, acc, stack, context, line, offset) do
    cron__334(rest, [], [acc | stack], context, line, offset)
  end

  defp cron__334(<<x0::integer, rest::binary>>, acc, stack, context, comb__line, comb__offset)
       when x0 >= 48 and x0 <= 57 do
    cron__335(rest, [x0 - 48] ++ acc, stack, context, comb__line, comb__offset + 1)
  end

  defp cron__334(rest, _acc, stack, context, line, offset) do
    [_, acc | stack] = stack
    cron__323(rest, acc, stack, context, line, offset)
  end

  defp cron__335(rest, acc, stack, context, line, offset) do
    cron__337(rest, acc, [1 | stack], context, line, offset)
  end

  defp cron__337(<<x0::integer, rest::binary>>, acc, stack, context, comb__line, comb__offset)
       when x0 >= 48 and x0 <= 57 do
    cron__338(rest, [x0] ++ acc, stack, context, comb__line, comb__offset + 1)
  end

  defp cron__337(rest, acc, stack, context, line, offset) do
    cron__336(rest, acc, stack, context, line, offset)
  end

  defp cron__336(rest, acc, [_ | stack], context, line, offset) do
    cron__339(rest, acc, stack, context, line, offset)
  end

  defp cron__338(rest, acc, [1 | stack], context, line, offset) do
    cron__339(rest, acc, stack, context, line, offset)
  end

  defp cron__338(rest, acc, [count | stack], context, line, offset) do
    cron__337(rest, acc, [count - 1 | stack], context, line, offset)
  end

  defp cron__339(rest, user_acc, [acc | stack], context, line, offset) do
    _ = user_acc

    cron__340(
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

  defp cron__340(rest, user_acc, [acc | stack], context, line, offset) do
    _ = user_acc
    cron__341(rest, [range: :lists.reverse(user_acc)] ++ acc, stack, context, line, offset)
  end

  defp cron__341(rest, acc, [_, previous_acc | stack], context, line, offset) do
    cron__306(rest, acc ++ previous_acc, stack, context, line, offset)
  end

  defp cron__342(_, _, [{rest, context, line, offset} | _] = stack, _, _, _) do
    cron__324(rest, [], stack, context, line, offset)
  end

  defp cron__343(rest, acc, stack, context, line, offset) do
    cron__344(rest, [], [acc | stack], context, line, offset)
  end

  defp cron__344(rest, acc, stack, context, line, offset) do
    cron__365(rest, [], [{rest, context, line, offset}, acc | stack], context, line, offset)
  end

  defp cron__346(rest, acc, stack, context, line, offset) do
    cron__347(rest, [], [acc | stack], context, line, offset)
  end

  defp cron__347(rest, acc, stack, context, line, offset) do
    cron__348(rest, [], [acc | stack], context, line, offset)
  end

  defp cron__348(<<x0::integer, rest::binary>>, acc, stack, context, comb__line, comb__offset)
       when x0 >= 48 and x0 <= 57 do
    cron__349(rest, [x0 - 48] ++ acc, stack, context, comb__line, comb__offset + 1)
  end

  defp cron__348(rest, _acc, stack, context, line, offset) do
    [_, _, _, _, acc | stack] = stack
    cron__342(rest, acc, stack, context, line, offset)
  end

  defp cron__349(rest, acc, stack, context, line, offset) do
    cron__351(rest, acc, [1 | stack], context, line, offset)
  end

  defp cron__351(<<x0::integer, rest::binary>>, acc, stack, context, comb__line, comb__offset)
       when x0 >= 48 and x0 <= 57 do
    cron__352(rest, [x0] ++ acc, stack, context, comb__line, comb__offset + 1)
  end

  defp cron__351(rest, acc, stack, context, line, offset) do
    cron__350(rest, acc, stack, context, line, offset)
  end

  defp cron__350(rest, acc, [_ | stack], context, line, offset) do
    cron__353(rest, acc, stack, context, line, offset)
  end

  defp cron__352(rest, acc, [1 | stack], context, line, offset) do
    cron__353(rest, acc, stack, context, line, offset)
  end

  defp cron__352(rest, acc, [count | stack], context, line, offset) do
    cron__351(rest, acc, [count - 1 | stack], context, line, offset)
  end

  defp cron__353(rest, user_acc, [acc | stack], context, line, offset) do
    _ = user_acc

    cron__354(
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

  defp cron__354(<<"-", rest::binary>>, acc, stack, context, comb__line, comb__offset) do
    cron__355(rest, [] ++ acc, stack, context, comb__line, comb__offset + 1)
  end

  defp cron__354(rest, _acc, stack, context, line, offset) do
    [_, _, _, acc | stack] = stack
    cron__342(rest, acc, stack, context, line, offset)
  end

  defp cron__355(rest, acc, stack, context, line, offset) do
    cron__356(rest, [], [acc | stack], context, line, offset)
  end

  defp cron__356(<<x0::integer, rest::binary>>, acc, stack, context, comb__line, comb__offset)
       when x0 >= 48 and x0 <= 57 do
    cron__357(rest, [x0 - 48] ++ acc, stack, context, comb__line, comb__offset + 1)
  end

  defp cron__356(rest, _acc, stack, context, line, offset) do
    [_, _, _, _, acc | stack] = stack
    cron__342(rest, acc, stack, context, line, offset)
  end

  defp cron__357(rest, acc, stack, context, line, offset) do
    cron__359(rest, acc, [1 | stack], context, line, offset)
  end

  defp cron__359(<<x0::integer, rest::binary>>, acc, stack, context, comb__line, comb__offset)
       when x0 >= 48 and x0 <= 57 do
    cron__360(rest, [x0] ++ acc, stack, context, comb__line, comb__offset + 1)
  end

  defp cron__359(rest, acc, stack, context, line, offset) do
    cron__358(rest, acc, stack, context, line, offset)
  end

  defp cron__358(rest, acc, [_ | stack], context, line, offset) do
    cron__361(rest, acc, stack, context, line, offset)
  end

  defp cron__360(rest, acc, [1 | stack], context, line, offset) do
    cron__361(rest, acc, stack, context, line, offset)
  end

  defp cron__360(rest, acc, [count | stack], context, line, offset) do
    cron__359(rest, acc, [count - 1 | stack], context, line, offset)
  end

  defp cron__361(rest, user_acc, [acc | stack], context, line, offset) do
    _ = user_acc

    cron__362(
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

  defp cron__362(rest, user_acc, [acc | stack], context, line, offset) do
    _ = user_acc
    cron__363(rest, [range: :lists.reverse(user_acc)] ++ acc, stack, context, line, offset)
  end

  defp cron__363(rest, acc, [_, previous_acc | stack], context, line, offset) do
    cron__345(rest, acc ++ previous_acc, stack, context, line, offset)
  end

  defp cron__364(_, _, [{rest, context, line, offset} | _] = stack, _, _, _) do
    cron__346(rest, [], stack, context, line, offset)
  end

  defp cron__365(<<"*", rest::binary>>, acc, stack, context, comb__line, comb__offset) do
    cron__366(rest, [wild: "*"] ++ acc, stack, context, comb__line, comb__offset + 1)
  end

  defp cron__365(rest, acc, stack, context, line, offset) do
    cron__364(rest, acc, stack, context, line, offset)
  end

  defp cron__366(rest, acc, [_, previous_acc | stack], context, line, offset) do
    cron__345(rest, acc ++ previous_acc, stack, context, line, offset)
  end

  defp cron__345(<<"/", rest::binary>>, acc, stack, context, comb__line, comb__offset) do
    cron__367(rest, [] ++ acc, stack, context, comb__line, comb__offset + 1)
  end

  defp cron__345(rest, _acc, stack, context, line, offset) do
    [acc | stack] = stack
    cron__342(rest, acc, stack, context, line, offset)
  end

  defp cron__367(rest, acc, stack, context, line, offset) do
    cron__368(rest, [], [acc | stack], context, line, offset)
  end

  defp cron__368(<<x0::integer, rest::binary>>, acc, stack, context, comb__line, comb__offset)
       when x0 >= 48 and x0 <= 57 do
    cron__369(rest, [x0 - 48] ++ acc, stack, context, comb__line, comb__offset + 1)
  end

  defp cron__368(rest, _acc, stack, context, line, offset) do
    [_, acc | stack] = stack
    cron__342(rest, acc, stack, context, line, offset)
  end

  defp cron__369(rest, acc, stack, context, line, offset) do
    cron__371(rest, acc, [1 | stack], context, line, offset)
  end

  defp cron__371(<<x0::integer, rest::binary>>, acc, stack, context, comb__line, comb__offset)
       when x0 >= 48 and x0 <= 57 do
    cron__372(rest, [x0] ++ acc, stack, context, comb__line, comb__offset + 1)
  end

  defp cron__371(rest, acc, stack, context, line, offset) do
    cron__370(rest, acc, stack, context, line, offset)
  end

  defp cron__370(rest, acc, [_ | stack], context, line, offset) do
    cron__373(rest, acc, stack, context, line, offset)
  end

  defp cron__372(rest, acc, [1 | stack], context, line, offset) do
    cron__373(rest, acc, stack, context, line, offset)
  end

  defp cron__372(rest, acc, [count | stack], context, line, offset) do
    cron__371(rest, acc, [count - 1 | stack], context, line, offset)
  end

  defp cron__373(rest, user_acc, [acc | stack], context, line, offset) do
    _ = user_acc

    cron__374(
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

  defp cron__374(rest, user_acc, [acc | stack], context, line, offset) do
    _ = user_acc
    cron__375(rest, [step: :lists.reverse(user_acc)] ++ acc, stack, context, line, offset)
  end

  defp cron__375(rest, acc, [_, previous_acc | stack], context, line, offset) do
    cron__306(rest, acc ++ previous_acc, stack, context, line, offset)
  end

  defp cron__306(rest, acc, stack, context, line, offset) do
    cron__377(rest, [], [{rest, acc, context, line, offset} | stack], context, line, offset)
  end

  defp cron__377(rest, acc, stack, context, line, offset) do
    cron__415(rest, [], [{rest, context, line, offset}, acc | stack], context, line, offset)
  end

  defp cron__379(<<",", rest::binary>>, acc, stack, context, comb__line, comb__offset) do
    cron__380(rest, [] ++ acc, stack, context, comb__line, comb__offset + 1)
  end

  defp cron__379(rest, _acc, stack, context, line, offset) do
    [_, acc | stack] = stack
    cron__376(rest, acc, stack, context, line, offset)
  end

  defp cron__380(rest, acc, [_, previous_acc | stack], context, line, offset) do
    cron__378(rest, acc ++ previous_acc, stack, context, line, offset)
  end

  defp cron__381(_, _, [{rest, context, line, offset} | _] = stack, _, _, _) do
    cron__379(rest, [], stack, context, line, offset)
  end

  defp cron__382(<<"*", rest::binary>>, acc, stack, context, comb__line, comb__offset) do
    cron__383(rest, [wild: "*"] ++ acc, stack, context, comb__line, comb__offset + 1)
  end

  defp cron__382(rest, acc, stack, context, line, offset) do
    cron__381(rest, acc, stack, context, line, offset)
  end

  defp cron__383(rest, acc, [_, previous_acc | stack], context, line, offset) do
    cron__378(rest, acc ++ previous_acc, stack, context, line, offset)
  end

  defp cron__384(_, _, [{rest, context, line, offset} | _] = stack, _, _, _) do
    cron__382(rest, [], stack, context, line, offset)
  end

  defp cron__385(rest, acc, stack, context, line, offset) do
    cron__386(rest, [], [acc | stack], context, line, offset)
  end

  defp cron__386(rest, acc, stack, context, line, offset) do
    cron__387(rest, [], [acc | stack], context, line, offset)
  end

  defp cron__387(<<x0::integer, rest::binary>>, acc, stack, context, comb__line, comb__offset)
       when x0 >= 48 and x0 <= 57 do
    cron__388(rest, [x0 - 48] ++ acc, stack, context, comb__line, comb__offset + 1)
  end

  defp cron__387(rest, _acc, stack, context, line, offset) do
    [_, acc | stack] = stack
    cron__384(rest, acc, stack, context, line, offset)
  end

  defp cron__388(rest, acc, stack, context, line, offset) do
    cron__390(rest, acc, [1 | stack], context, line, offset)
  end

  defp cron__390(<<x0::integer, rest::binary>>, acc, stack, context, comb__line, comb__offset)
       when x0 >= 48 and x0 <= 57 do
    cron__391(rest, [x0] ++ acc, stack, context, comb__line, comb__offset + 1)
  end

  defp cron__390(rest, acc, stack, context, line, offset) do
    cron__389(rest, acc, stack, context, line, offset)
  end

  defp cron__389(rest, acc, [_ | stack], context, line, offset) do
    cron__392(rest, acc, stack, context, line, offset)
  end

  defp cron__391(rest, acc, [1 | stack], context, line, offset) do
    cron__392(rest, acc, stack, context, line, offset)
  end

  defp cron__391(rest, acc, [count | stack], context, line, offset) do
    cron__390(rest, acc, [count - 1 | stack], context, line, offset)
  end

  defp cron__392(rest, user_acc, [acc | stack], context, line, offset) do
    _ = user_acc

    cron__393(
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

  defp cron__393(rest, user_acc, [acc | stack], context, line, offset) do
    _ = user_acc

    cron__394(
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

  defp cron__394(rest, acc, [_, previous_acc | stack], context, line, offset) do
    cron__378(rest, acc ++ previous_acc, stack, context, line, offset)
  end

  defp cron__395(_, _, [{rest, context, line, offset} | _] = stack, _, _, _) do
    cron__385(rest, [], stack, context, line, offset)
  end

  defp cron__396(rest, acc, stack, context, line, offset) do
    cron__397(rest, [], [acc | stack], context, line, offset)
  end

  defp cron__397(rest, acc, stack, context, line, offset) do
    cron__398(rest, [], [acc | stack], context, line, offset)
  end

  defp cron__398(<<x0::integer, rest::binary>>, acc, stack, context, comb__line, comb__offset)
       when x0 >= 48 and x0 <= 57 do
    cron__399(rest, [x0 - 48] ++ acc, stack, context, comb__line, comb__offset + 1)
  end

  defp cron__398(rest, _acc, stack, context, line, offset) do
    [_, acc | stack] = stack
    cron__395(rest, acc, stack, context, line, offset)
  end

  defp cron__399(rest, acc, stack, context, line, offset) do
    cron__401(rest, acc, [1 | stack], context, line, offset)
  end

  defp cron__401(<<x0::integer, rest::binary>>, acc, stack, context, comb__line, comb__offset)
       when x0 >= 48 and x0 <= 57 do
    cron__402(rest, [x0] ++ acc, stack, context, comb__line, comb__offset + 1)
  end

  defp cron__401(rest, acc, stack, context, line, offset) do
    cron__400(rest, acc, stack, context, line, offset)
  end

  defp cron__400(rest, acc, [_ | stack], context, line, offset) do
    cron__403(rest, acc, stack, context, line, offset)
  end

  defp cron__402(rest, acc, [1 | stack], context, line, offset) do
    cron__403(rest, acc, stack, context, line, offset)
  end

  defp cron__402(rest, acc, [count | stack], context, line, offset) do
    cron__401(rest, acc, [count - 1 | stack], context, line, offset)
  end

  defp cron__403(rest, user_acc, [acc | stack], context, line, offset) do
    _ = user_acc

    cron__404(
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

  defp cron__404(<<"-", rest::binary>>, acc, stack, context, comb__line, comb__offset) do
    cron__405(rest, [] ++ acc, stack, context, comb__line, comb__offset + 1)
  end

  defp cron__404(rest, _acc, stack, context, line, offset) do
    [acc | stack] = stack
    cron__395(rest, acc, stack, context, line, offset)
  end

  defp cron__405(rest, acc, stack, context, line, offset) do
    cron__406(rest, [], [acc | stack], context, line, offset)
  end

  defp cron__406(<<x0::integer, rest::binary>>, acc, stack, context, comb__line, comb__offset)
       when x0 >= 48 and x0 <= 57 do
    cron__407(rest, [x0 - 48] ++ acc, stack, context, comb__line, comb__offset + 1)
  end

  defp cron__406(rest, _acc, stack, context, line, offset) do
    [_, acc | stack] = stack
    cron__395(rest, acc, stack, context, line, offset)
  end

  defp cron__407(rest, acc, stack, context, line, offset) do
    cron__409(rest, acc, [1 | stack], context, line, offset)
  end

  defp cron__409(<<x0::integer, rest::binary>>, acc, stack, context, comb__line, comb__offset)
       when x0 >= 48 and x0 <= 57 do
    cron__410(rest, [x0] ++ acc, stack, context, comb__line, comb__offset + 1)
  end

  defp cron__409(rest, acc, stack, context, line, offset) do
    cron__408(rest, acc, stack, context, line, offset)
  end

  defp cron__408(rest, acc, [_ | stack], context, line, offset) do
    cron__411(rest, acc, stack, context, line, offset)
  end

  defp cron__410(rest, acc, [1 | stack], context, line, offset) do
    cron__411(rest, acc, stack, context, line, offset)
  end

  defp cron__410(rest, acc, [count | stack], context, line, offset) do
    cron__409(rest, acc, [count - 1 | stack], context, line, offset)
  end

  defp cron__411(rest, user_acc, [acc | stack], context, line, offset) do
    _ = user_acc

    cron__412(
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

  defp cron__412(rest, user_acc, [acc | stack], context, line, offset) do
    _ = user_acc
    cron__413(rest, [range: :lists.reverse(user_acc)] ++ acc, stack, context, line, offset)
  end

  defp cron__413(rest, acc, [_, previous_acc | stack], context, line, offset) do
    cron__378(rest, acc ++ previous_acc, stack, context, line, offset)
  end

  defp cron__414(_, _, [{rest, context, line, offset} | _] = stack, _, _, _) do
    cron__396(rest, [], stack, context, line, offset)
  end

  defp cron__415(rest, acc, stack, context, line, offset) do
    cron__416(rest, [], [acc | stack], context, line, offset)
  end

  defp cron__416(rest, acc, stack, context, line, offset) do
    cron__437(rest, [], [{rest, context, line, offset}, acc | stack], context, line, offset)
  end

  defp cron__418(rest, acc, stack, context, line, offset) do
    cron__419(rest, [], [acc | stack], context, line, offset)
  end

  defp cron__419(rest, acc, stack, context, line, offset) do
    cron__420(rest, [], [acc | stack], context, line, offset)
  end

  defp cron__420(<<x0::integer, rest::binary>>, acc, stack, context, comb__line, comb__offset)
       when x0 >= 48 and x0 <= 57 do
    cron__421(rest, [x0 - 48] ++ acc, stack, context, comb__line, comb__offset + 1)
  end

  defp cron__420(rest, _acc, stack, context, line, offset) do
    [_, _, _, _, acc | stack] = stack
    cron__414(rest, acc, stack, context, line, offset)
  end

  defp cron__421(rest, acc, stack, context, line, offset) do
    cron__423(rest, acc, [1 | stack], context, line, offset)
  end

  defp cron__423(<<x0::integer, rest::binary>>, acc, stack, context, comb__line, comb__offset)
       when x0 >= 48 and x0 <= 57 do
    cron__424(rest, [x0] ++ acc, stack, context, comb__line, comb__offset + 1)
  end

  defp cron__423(rest, acc, stack, context, line, offset) do
    cron__422(rest, acc, stack, context, line, offset)
  end

  defp cron__422(rest, acc, [_ | stack], context, line, offset) do
    cron__425(rest, acc, stack, context, line, offset)
  end

  defp cron__424(rest, acc, [1 | stack], context, line, offset) do
    cron__425(rest, acc, stack, context, line, offset)
  end

  defp cron__424(rest, acc, [count | stack], context, line, offset) do
    cron__423(rest, acc, [count - 1 | stack], context, line, offset)
  end

  defp cron__425(rest, user_acc, [acc | stack], context, line, offset) do
    _ = user_acc

    cron__426(
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

  defp cron__426(<<"-", rest::binary>>, acc, stack, context, comb__line, comb__offset) do
    cron__427(rest, [] ++ acc, stack, context, comb__line, comb__offset + 1)
  end

  defp cron__426(rest, _acc, stack, context, line, offset) do
    [_, _, _, acc | stack] = stack
    cron__414(rest, acc, stack, context, line, offset)
  end

  defp cron__427(rest, acc, stack, context, line, offset) do
    cron__428(rest, [], [acc | stack], context, line, offset)
  end

  defp cron__428(<<x0::integer, rest::binary>>, acc, stack, context, comb__line, comb__offset)
       when x0 >= 48 and x0 <= 57 do
    cron__429(rest, [x0 - 48] ++ acc, stack, context, comb__line, comb__offset + 1)
  end

  defp cron__428(rest, _acc, stack, context, line, offset) do
    [_, _, _, _, acc | stack] = stack
    cron__414(rest, acc, stack, context, line, offset)
  end

  defp cron__429(rest, acc, stack, context, line, offset) do
    cron__431(rest, acc, [1 | stack], context, line, offset)
  end

  defp cron__431(<<x0::integer, rest::binary>>, acc, stack, context, comb__line, comb__offset)
       when x0 >= 48 and x0 <= 57 do
    cron__432(rest, [x0] ++ acc, stack, context, comb__line, comb__offset + 1)
  end

  defp cron__431(rest, acc, stack, context, line, offset) do
    cron__430(rest, acc, stack, context, line, offset)
  end

  defp cron__430(rest, acc, [_ | stack], context, line, offset) do
    cron__433(rest, acc, stack, context, line, offset)
  end

  defp cron__432(rest, acc, [1 | stack], context, line, offset) do
    cron__433(rest, acc, stack, context, line, offset)
  end

  defp cron__432(rest, acc, [count | stack], context, line, offset) do
    cron__431(rest, acc, [count - 1 | stack], context, line, offset)
  end

  defp cron__433(rest, user_acc, [acc | stack], context, line, offset) do
    _ = user_acc

    cron__434(
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

  defp cron__434(rest, user_acc, [acc | stack], context, line, offset) do
    _ = user_acc
    cron__435(rest, [range: :lists.reverse(user_acc)] ++ acc, stack, context, line, offset)
  end

  defp cron__435(rest, acc, [_, previous_acc | stack], context, line, offset) do
    cron__417(rest, acc ++ previous_acc, stack, context, line, offset)
  end

  defp cron__436(_, _, [{rest, context, line, offset} | _] = stack, _, _, _) do
    cron__418(rest, [], stack, context, line, offset)
  end

  defp cron__437(<<"*", rest::binary>>, acc, stack, context, comb__line, comb__offset) do
    cron__438(rest, [wild: "*"] ++ acc, stack, context, comb__line, comb__offset + 1)
  end

  defp cron__437(rest, acc, stack, context, line, offset) do
    cron__436(rest, acc, stack, context, line, offset)
  end

  defp cron__438(rest, acc, [_, previous_acc | stack], context, line, offset) do
    cron__417(rest, acc ++ previous_acc, stack, context, line, offset)
  end

  defp cron__417(<<"/", rest::binary>>, acc, stack, context, comb__line, comb__offset) do
    cron__439(rest, [] ++ acc, stack, context, comb__line, comb__offset + 1)
  end

  defp cron__417(rest, _acc, stack, context, line, offset) do
    [acc | stack] = stack
    cron__414(rest, acc, stack, context, line, offset)
  end

  defp cron__439(rest, acc, stack, context, line, offset) do
    cron__440(rest, [], [acc | stack], context, line, offset)
  end

  defp cron__440(<<x0::integer, rest::binary>>, acc, stack, context, comb__line, comb__offset)
       when x0 >= 48 and x0 <= 57 do
    cron__441(rest, [x0 - 48] ++ acc, stack, context, comb__line, comb__offset + 1)
  end

  defp cron__440(rest, _acc, stack, context, line, offset) do
    [_, acc | stack] = stack
    cron__414(rest, acc, stack, context, line, offset)
  end

  defp cron__441(rest, acc, stack, context, line, offset) do
    cron__443(rest, acc, [1 | stack], context, line, offset)
  end

  defp cron__443(<<x0::integer, rest::binary>>, acc, stack, context, comb__line, comb__offset)
       when x0 >= 48 and x0 <= 57 do
    cron__444(rest, [x0] ++ acc, stack, context, comb__line, comb__offset + 1)
  end

  defp cron__443(rest, acc, stack, context, line, offset) do
    cron__442(rest, acc, stack, context, line, offset)
  end

  defp cron__442(rest, acc, [_ | stack], context, line, offset) do
    cron__445(rest, acc, stack, context, line, offset)
  end

  defp cron__444(rest, acc, [1 | stack], context, line, offset) do
    cron__445(rest, acc, stack, context, line, offset)
  end

  defp cron__444(rest, acc, [count | stack], context, line, offset) do
    cron__443(rest, acc, [count - 1 | stack], context, line, offset)
  end

  defp cron__445(rest, user_acc, [acc | stack], context, line, offset) do
    _ = user_acc

    cron__446(
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

  defp cron__446(rest, user_acc, [acc | stack], context, line, offset) do
    _ = user_acc
    cron__447(rest, [step: :lists.reverse(user_acc)] ++ acc, stack, context, line, offset)
  end

  defp cron__447(rest, acc, [_, previous_acc | stack], context, line, offset) do
    cron__378(rest, acc ++ previous_acc, stack, context, line, offset)
  end

  defp cron__376(_, _, [{rest, acc, context, line, offset} | stack], _, _, _) do
    cron__448(rest, acc, stack, context, line, offset)
  end

  defp cron__378(
         inner_rest,
         inner_acc,
         [{rest, acc, context, line, offset} | stack],
         inner_context,
         inner_line,
         inner_offset
       ) do
    _ = {rest, acc, context, line, offset}

    cron__377(
      inner_rest,
      [],
      [{inner_rest, inner_acc ++ acc, inner_context, inner_line, inner_offset} | stack],
      inner_context,
      inner_line,
      inner_offset
    )
  end

  defp cron__448(rest, user_acc, [acc | stack], context, line, offset) do
    _ = user_acc
    cron__449(rest, [days: :lists.reverse(user_acc)] ++ acc, stack, context, line, offset)
  end

  defp cron__449(rest, acc, stack, context, line, offset) do
    cron__450(rest, [], [acc | stack], context, line, offset)
  end

  defp cron__450(rest, acc, stack, context, line, offset) do
    cron__451(rest, [], [acc | stack], context, line, offset)
  end

  defp cron__451(<<x0::integer, rest::binary>>, acc, stack, context, comb__line, comb__offset)
       when x0 === 32 or x0 === 9 do
    cron__452(rest, acc, stack, context, comb__line, comb__offset + 1)
  end

  defp cron__451(rest, _acc, _stack, context, line, offset) do
    {:error, "expected ASCII character equal to ' ' or equal to '\\t'", rest, context, line,
     offset}
  end

  defp cron__452(<<x0::integer, rest::binary>>, acc, stack, context, comb__line, comb__offset)
       when x0 === 32 or x0 === 9 do
    cron__454(rest, acc, stack, context, comb__line, comb__offset + 1)
  end

  defp cron__452(rest, acc, stack, context, line, offset) do
    cron__453(rest, acc, stack, context, line, offset)
  end

  defp cron__454(rest, acc, stack, context, line, offset) do
    cron__452(rest, acc, stack, context, line, offset)
  end

  defp cron__453(rest, user_acc, [acc | stack], context, line, offset) do
    _ = user_acc
    cron__455(rest, acc, stack, context, line, offset)
  end

  defp cron__455(rest, user_acc, [acc | stack], context, line, offset) do
    _ = user_acc
    cron__456(rest, [] ++ acc, stack, context, line, offset)
  end

  defp cron__456(rest, acc, stack, context, line, offset) do
    cron__457(rest, [], [acc | stack], context, line, offset)
  end

  defp cron__457(rest, acc, stack, context, line, offset) do
    cron__531(rest, [], [{rest, context, line, offset}, acc | stack], context, line, offset)
  end

  defp cron__459(rest, acc, stack, context, line, offset) do
    cron__497(rest, [], [{rest, context, line, offset}, acc | stack], context, line, offset)
  end

  defp cron__461(<<",", rest::binary>>, acc, stack, context, comb__line, comb__offset) do
    cron__462(rest, [] ++ acc, stack, context, comb__line, comb__offset + 1)
  end

  defp cron__461(rest, _acc, _stack, context, line, offset) do
    {:error,
     "expected string \"JAN\" or string \"FEB\" or string \"MAR\" or string \"APR\" or string \"MAY\" or string \"JUN\" or string \"JUL\" or string \"AUG\" or string \"SEP\" or string \"OCT\" or string \"NOV\" or string \"DEC\" or string \"*\" or ASCII character in the range '0' to '9', followed by ASCII character in the range '0' to '9', followed by string \"-\", followed by ASCII character in the range '0' to '9', followed by ASCII character in the range '0' to '9', followed by string \"/\", followed by ASCII character in the range '0' to '9', followed by ASCII character in the range '0' to '9' or ASCII character in the range '0' to '9', followed by ASCII character in the range '0' to '9', followed by string \"-\", followed by ASCII character in the range '0' to '9', followed by ASCII character in the range '0' to '9' or ASCII character in the range '0' to '9', followed by ASCII character in the range '0' to '9' or string \"*\" or string \",\"",
     rest, context, line, offset}
  end

  defp cron__462(rest, acc, [_, previous_acc | stack], context, line, offset) do
    cron__460(rest, acc ++ previous_acc, stack, context, line, offset)
  end

  defp cron__463(_, _, [{rest, context, line, offset} | _] = stack, _, _, _) do
    cron__461(rest, [], stack, context, line, offset)
  end

  defp cron__464(<<"*", rest::binary>>, acc, stack, context, comb__line, comb__offset) do
    cron__465(rest, [wild: "*"] ++ acc, stack, context, comb__line, comb__offset + 1)
  end

  defp cron__464(rest, acc, stack, context, line, offset) do
    cron__463(rest, acc, stack, context, line, offset)
  end

  defp cron__465(rest, acc, [_, previous_acc | stack], context, line, offset) do
    cron__460(rest, acc ++ previous_acc, stack, context, line, offset)
  end

  defp cron__466(_, _, [{rest, context, line, offset} | _] = stack, _, _, _) do
    cron__464(rest, [], stack, context, line, offset)
  end

  defp cron__467(rest, acc, stack, context, line, offset) do
    cron__468(rest, [], [acc | stack], context, line, offset)
  end

  defp cron__468(rest, acc, stack, context, line, offset) do
    cron__469(rest, [], [acc | stack], context, line, offset)
  end

  defp cron__469(<<x0::integer, rest::binary>>, acc, stack, context, comb__line, comb__offset)
       when x0 >= 48 and x0 <= 57 do
    cron__470(rest, [x0 - 48] ++ acc, stack, context, comb__line, comb__offset + 1)
  end

  defp cron__469(rest, _acc, stack, context, line, offset) do
    [_, acc | stack] = stack
    cron__466(rest, acc, stack, context, line, offset)
  end

  defp cron__470(rest, acc, stack, context, line, offset) do
    cron__472(rest, acc, [1 | stack], context, line, offset)
  end

  defp cron__472(<<x0::integer, rest::binary>>, acc, stack, context, comb__line, comb__offset)
       when x0 >= 48 and x0 <= 57 do
    cron__473(rest, [x0] ++ acc, stack, context, comb__line, comb__offset + 1)
  end

  defp cron__472(rest, acc, stack, context, line, offset) do
    cron__471(rest, acc, stack, context, line, offset)
  end

  defp cron__471(rest, acc, [_ | stack], context, line, offset) do
    cron__474(rest, acc, stack, context, line, offset)
  end

  defp cron__473(rest, acc, [1 | stack], context, line, offset) do
    cron__474(rest, acc, stack, context, line, offset)
  end

  defp cron__473(rest, acc, [count | stack], context, line, offset) do
    cron__472(rest, acc, [count - 1 | stack], context, line, offset)
  end

  defp cron__474(rest, user_acc, [acc | stack], context, line, offset) do
    _ = user_acc

    cron__475(
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

  defp cron__475(rest, user_acc, [acc | stack], context, line, offset) do
    _ = user_acc

    cron__476(
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

  defp cron__476(rest, acc, [_, previous_acc | stack], context, line, offset) do
    cron__460(rest, acc ++ previous_acc, stack, context, line, offset)
  end

  defp cron__477(_, _, [{rest, context, line, offset} | _] = stack, _, _, _) do
    cron__467(rest, [], stack, context, line, offset)
  end

  defp cron__478(rest, acc, stack, context, line, offset) do
    cron__479(rest, [], [acc | stack], context, line, offset)
  end

  defp cron__479(rest, acc, stack, context, line, offset) do
    cron__480(rest, [], [acc | stack], context, line, offset)
  end

  defp cron__480(<<x0::integer, rest::binary>>, acc, stack, context, comb__line, comb__offset)
       when x0 >= 48 and x0 <= 57 do
    cron__481(rest, [x0 - 48] ++ acc, stack, context, comb__line, comb__offset + 1)
  end

  defp cron__480(rest, _acc, stack, context, line, offset) do
    [_, acc | stack] = stack
    cron__477(rest, acc, stack, context, line, offset)
  end

  defp cron__481(rest, acc, stack, context, line, offset) do
    cron__483(rest, acc, [1 | stack], context, line, offset)
  end

  defp cron__483(<<x0::integer, rest::binary>>, acc, stack, context, comb__line, comb__offset)
       when x0 >= 48 and x0 <= 57 do
    cron__484(rest, [x0] ++ acc, stack, context, comb__line, comb__offset + 1)
  end

  defp cron__483(rest, acc, stack, context, line, offset) do
    cron__482(rest, acc, stack, context, line, offset)
  end

  defp cron__482(rest, acc, [_ | stack], context, line, offset) do
    cron__485(rest, acc, stack, context, line, offset)
  end

  defp cron__484(rest, acc, [1 | stack], context, line, offset) do
    cron__485(rest, acc, stack, context, line, offset)
  end

  defp cron__484(rest, acc, [count | stack], context, line, offset) do
    cron__483(rest, acc, [count - 1 | stack], context, line, offset)
  end

  defp cron__485(rest, user_acc, [acc | stack], context, line, offset) do
    _ = user_acc

    cron__486(
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

  defp cron__486(<<"-", rest::binary>>, acc, stack, context, comb__line, comb__offset) do
    cron__487(rest, [] ++ acc, stack, context, comb__line, comb__offset + 1)
  end

  defp cron__486(rest, _acc, stack, context, line, offset) do
    [acc | stack] = stack
    cron__477(rest, acc, stack, context, line, offset)
  end

  defp cron__487(rest, acc, stack, context, line, offset) do
    cron__488(rest, [], [acc | stack], context, line, offset)
  end

  defp cron__488(<<x0::integer, rest::binary>>, acc, stack, context, comb__line, comb__offset)
       when x0 >= 48 and x0 <= 57 do
    cron__489(rest, [x0 - 48] ++ acc, stack, context, comb__line, comb__offset + 1)
  end

  defp cron__488(rest, _acc, stack, context, line, offset) do
    [_, acc | stack] = stack
    cron__477(rest, acc, stack, context, line, offset)
  end

  defp cron__489(rest, acc, stack, context, line, offset) do
    cron__491(rest, acc, [1 | stack], context, line, offset)
  end

  defp cron__491(<<x0::integer, rest::binary>>, acc, stack, context, comb__line, comb__offset)
       when x0 >= 48 and x0 <= 57 do
    cron__492(rest, [x0] ++ acc, stack, context, comb__line, comb__offset + 1)
  end

  defp cron__491(rest, acc, stack, context, line, offset) do
    cron__490(rest, acc, stack, context, line, offset)
  end

  defp cron__490(rest, acc, [_ | stack], context, line, offset) do
    cron__493(rest, acc, stack, context, line, offset)
  end

  defp cron__492(rest, acc, [1 | stack], context, line, offset) do
    cron__493(rest, acc, stack, context, line, offset)
  end

  defp cron__492(rest, acc, [count | stack], context, line, offset) do
    cron__491(rest, acc, [count - 1 | stack], context, line, offset)
  end

  defp cron__493(rest, user_acc, [acc | stack], context, line, offset) do
    _ = user_acc

    cron__494(
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

  defp cron__494(rest, user_acc, [acc | stack], context, line, offset) do
    _ = user_acc
    cron__495(rest, [range: :lists.reverse(user_acc)] ++ acc, stack, context, line, offset)
  end

  defp cron__495(rest, acc, [_, previous_acc | stack], context, line, offset) do
    cron__460(rest, acc ++ previous_acc, stack, context, line, offset)
  end

  defp cron__496(_, _, [{rest, context, line, offset} | _] = stack, _, _, _) do
    cron__478(rest, [], stack, context, line, offset)
  end

  defp cron__497(rest, acc, stack, context, line, offset) do
    cron__498(rest, [], [acc | stack], context, line, offset)
  end

  defp cron__498(rest, acc, stack, context, line, offset) do
    cron__519(rest, [], [{rest, context, line, offset}, acc | stack], context, line, offset)
  end

  defp cron__500(rest, acc, stack, context, line, offset) do
    cron__501(rest, [], [acc | stack], context, line, offset)
  end

  defp cron__501(rest, acc, stack, context, line, offset) do
    cron__502(rest, [], [acc | stack], context, line, offset)
  end

  defp cron__502(<<x0::integer, rest::binary>>, acc, stack, context, comb__line, comb__offset)
       when x0 >= 48 and x0 <= 57 do
    cron__503(rest, [x0 - 48] ++ acc, stack, context, comb__line, comb__offset + 1)
  end

  defp cron__502(rest, _acc, stack, context, line, offset) do
    [_, _, _, _, acc | stack] = stack
    cron__496(rest, acc, stack, context, line, offset)
  end

  defp cron__503(rest, acc, stack, context, line, offset) do
    cron__505(rest, acc, [1 | stack], context, line, offset)
  end

  defp cron__505(<<x0::integer, rest::binary>>, acc, stack, context, comb__line, comb__offset)
       when x0 >= 48 and x0 <= 57 do
    cron__506(rest, [x0] ++ acc, stack, context, comb__line, comb__offset + 1)
  end

  defp cron__505(rest, acc, stack, context, line, offset) do
    cron__504(rest, acc, stack, context, line, offset)
  end

  defp cron__504(rest, acc, [_ | stack], context, line, offset) do
    cron__507(rest, acc, stack, context, line, offset)
  end

  defp cron__506(rest, acc, [1 | stack], context, line, offset) do
    cron__507(rest, acc, stack, context, line, offset)
  end

  defp cron__506(rest, acc, [count | stack], context, line, offset) do
    cron__505(rest, acc, [count - 1 | stack], context, line, offset)
  end

  defp cron__507(rest, user_acc, [acc | stack], context, line, offset) do
    _ = user_acc

    cron__508(
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

  defp cron__508(<<"-", rest::binary>>, acc, stack, context, comb__line, comb__offset) do
    cron__509(rest, [] ++ acc, stack, context, comb__line, comb__offset + 1)
  end

  defp cron__508(rest, _acc, stack, context, line, offset) do
    [_, _, _, acc | stack] = stack
    cron__496(rest, acc, stack, context, line, offset)
  end

  defp cron__509(rest, acc, stack, context, line, offset) do
    cron__510(rest, [], [acc | stack], context, line, offset)
  end

  defp cron__510(<<x0::integer, rest::binary>>, acc, stack, context, comb__line, comb__offset)
       when x0 >= 48 and x0 <= 57 do
    cron__511(rest, [x0 - 48] ++ acc, stack, context, comb__line, comb__offset + 1)
  end

  defp cron__510(rest, _acc, stack, context, line, offset) do
    [_, _, _, _, acc | stack] = stack
    cron__496(rest, acc, stack, context, line, offset)
  end

  defp cron__511(rest, acc, stack, context, line, offset) do
    cron__513(rest, acc, [1 | stack], context, line, offset)
  end

  defp cron__513(<<x0::integer, rest::binary>>, acc, stack, context, comb__line, comb__offset)
       when x0 >= 48 and x0 <= 57 do
    cron__514(rest, [x0] ++ acc, stack, context, comb__line, comb__offset + 1)
  end

  defp cron__513(rest, acc, stack, context, line, offset) do
    cron__512(rest, acc, stack, context, line, offset)
  end

  defp cron__512(rest, acc, [_ | stack], context, line, offset) do
    cron__515(rest, acc, stack, context, line, offset)
  end

  defp cron__514(rest, acc, [1 | stack], context, line, offset) do
    cron__515(rest, acc, stack, context, line, offset)
  end

  defp cron__514(rest, acc, [count | stack], context, line, offset) do
    cron__513(rest, acc, [count - 1 | stack], context, line, offset)
  end

  defp cron__515(rest, user_acc, [acc | stack], context, line, offset) do
    _ = user_acc

    cron__516(
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

  defp cron__516(rest, user_acc, [acc | stack], context, line, offset) do
    _ = user_acc
    cron__517(rest, [range: :lists.reverse(user_acc)] ++ acc, stack, context, line, offset)
  end

  defp cron__517(rest, acc, [_, previous_acc | stack], context, line, offset) do
    cron__499(rest, acc ++ previous_acc, stack, context, line, offset)
  end

  defp cron__518(_, _, [{rest, context, line, offset} | _] = stack, _, _, _) do
    cron__500(rest, [], stack, context, line, offset)
  end

  defp cron__519(<<"*", rest::binary>>, acc, stack, context, comb__line, comb__offset) do
    cron__520(rest, [wild: "*"] ++ acc, stack, context, comb__line, comb__offset + 1)
  end

  defp cron__519(rest, acc, stack, context, line, offset) do
    cron__518(rest, acc, stack, context, line, offset)
  end

  defp cron__520(rest, acc, [_, previous_acc | stack], context, line, offset) do
    cron__499(rest, acc ++ previous_acc, stack, context, line, offset)
  end

  defp cron__499(<<"/", rest::binary>>, acc, stack, context, comb__line, comb__offset) do
    cron__521(rest, [] ++ acc, stack, context, comb__line, comb__offset + 1)
  end

  defp cron__499(rest, _acc, stack, context, line, offset) do
    [acc | stack] = stack
    cron__496(rest, acc, stack, context, line, offset)
  end

  defp cron__521(rest, acc, stack, context, line, offset) do
    cron__522(rest, [], [acc | stack], context, line, offset)
  end

  defp cron__522(<<x0::integer, rest::binary>>, acc, stack, context, comb__line, comb__offset)
       when x0 >= 48 and x0 <= 57 do
    cron__523(rest, [x0 - 48] ++ acc, stack, context, comb__line, comb__offset + 1)
  end

  defp cron__522(rest, _acc, stack, context, line, offset) do
    [_, acc | stack] = stack
    cron__496(rest, acc, stack, context, line, offset)
  end

  defp cron__523(rest, acc, stack, context, line, offset) do
    cron__525(rest, acc, [1 | stack], context, line, offset)
  end

  defp cron__525(<<x0::integer, rest::binary>>, acc, stack, context, comb__line, comb__offset)
       when x0 >= 48 and x0 <= 57 do
    cron__526(rest, [x0] ++ acc, stack, context, comb__line, comb__offset + 1)
  end

  defp cron__525(rest, acc, stack, context, line, offset) do
    cron__524(rest, acc, stack, context, line, offset)
  end

  defp cron__524(rest, acc, [_ | stack], context, line, offset) do
    cron__527(rest, acc, stack, context, line, offset)
  end

  defp cron__526(rest, acc, [1 | stack], context, line, offset) do
    cron__527(rest, acc, stack, context, line, offset)
  end

  defp cron__526(rest, acc, [count | stack], context, line, offset) do
    cron__525(rest, acc, [count - 1 | stack], context, line, offset)
  end

  defp cron__527(rest, user_acc, [acc | stack], context, line, offset) do
    _ = user_acc

    cron__528(
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

  defp cron__528(rest, user_acc, [acc | stack], context, line, offset) do
    _ = user_acc
    cron__529(rest, [step: :lists.reverse(user_acc)] ++ acc, stack, context, line, offset)
  end

  defp cron__529(rest, acc, [_, previous_acc | stack], context, line, offset) do
    cron__460(rest, acc ++ previous_acc, stack, context, line, offset)
  end

  defp cron__460(rest, acc, [_, previous_acc | stack], context, line, offset) do
    cron__458(rest, acc ++ previous_acc, stack, context, line, offset)
  end

  defp cron__530(_, _, [{rest, context, line, offset} | _] = stack, _, _, _) do
    cron__459(rest, [], stack, context, line, offset)
  end

  defp cron__531(rest, acc, stack, context, line, offset) do
    cron__532(rest, [], [acc | stack], context, line, offset)
  end

  defp cron__532(<<"JAN", rest::binary>>, acc, stack, context, comb__line, comb__offset) do
    cron__533(rest, [1] ++ acc, stack, context, comb__line, comb__offset + 3)
  end

  defp cron__532(<<"FEB", rest::binary>>, acc, stack, context, comb__line, comb__offset) do
    cron__533(rest, [2] ++ acc, stack, context, comb__line, comb__offset + 3)
  end

  defp cron__532(<<"MAR", rest::binary>>, acc, stack, context, comb__line, comb__offset) do
    cron__533(rest, [3] ++ acc, stack, context, comb__line, comb__offset + 3)
  end

  defp cron__532(<<"APR", rest::binary>>, acc, stack, context, comb__line, comb__offset) do
    cron__533(rest, [4] ++ acc, stack, context, comb__line, comb__offset + 3)
  end

  defp cron__532(<<"MAY", rest::binary>>, acc, stack, context, comb__line, comb__offset) do
    cron__533(rest, [5] ++ acc, stack, context, comb__line, comb__offset + 3)
  end

  defp cron__532(<<"JUN", rest::binary>>, acc, stack, context, comb__line, comb__offset) do
    cron__533(rest, [6] ++ acc, stack, context, comb__line, comb__offset + 3)
  end

  defp cron__532(<<"JUL", rest::binary>>, acc, stack, context, comb__line, comb__offset) do
    cron__533(rest, [7] ++ acc, stack, context, comb__line, comb__offset + 3)
  end

  defp cron__532(<<"AUG", rest::binary>>, acc, stack, context, comb__line, comb__offset) do
    cron__533(rest, '\b' ++ acc, stack, context, comb__line, comb__offset + 3)
  end

  defp cron__532(<<"SEP", rest::binary>>, acc, stack, context, comb__line, comb__offset) do
    cron__533(rest, '\t' ++ acc, stack, context, comb__line, comb__offset + 3)
  end

  defp cron__532(<<"OCT", rest::binary>>, acc, stack, context, comb__line, comb__offset) do
    cron__533(rest, '\n' ++ acc, stack, context, comb__line, comb__offset + 3)
  end

  defp cron__532(<<"NOV", rest::binary>>, acc, stack, context, comb__line, comb__offset) do
    cron__533(rest, '\v' ++ acc, stack, context, comb__line, comb__offset + 3)
  end

  defp cron__532(<<"DEC", rest::binary>>, acc, stack, context, comb__line, comb__offset) do
    cron__533(rest, '\f' ++ acc, stack, context, comb__line, comb__offset + 3)
  end

  defp cron__532(rest, _acc, stack, context, line, offset) do
    [acc | stack] = stack
    cron__530(rest, acc, stack, context, line, offset)
  end

  defp cron__533(rest, user_acc, [acc | stack], context, line, offset) do
    _ = user_acc

    cron__534(
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

  defp cron__534(rest, acc, [_, previous_acc | stack], context, line, offset) do
    cron__458(rest, acc ++ previous_acc, stack, context, line, offset)
  end

  defp cron__458(rest, acc, stack, context, line, offset) do
    cron__536(rest, [], [{rest, acc, context, line, offset} | stack], context, line, offset)
  end

  defp cron__536(rest, acc, stack, context, line, offset) do
    cron__610(rest, [], [{rest, context, line, offset}, acc | stack], context, line, offset)
  end

  defp cron__538(rest, acc, stack, context, line, offset) do
    cron__576(rest, [], [{rest, context, line, offset}, acc | stack], context, line, offset)
  end

  defp cron__540(<<",", rest::binary>>, acc, stack, context, comb__line, comb__offset) do
    cron__541(rest, [] ++ acc, stack, context, comb__line, comb__offset + 1)
  end

  defp cron__540(rest, _acc, stack, context, line, offset) do
    [_, _, _, acc | stack] = stack
    cron__535(rest, acc, stack, context, line, offset)
  end

  defp cron__541(rest, acc, [_, previous_acc | stack], context, line, offset) do
    cron__539(rest, acc ++ previous_acc, stack, context, line, offset)
  end

  defp cron__542(_, _, [{rest, context, line, offset} | _] = stack, _, _, _) do
    cron__540(rest, [], stack, context, line, offset)
  end

  defp cron__543(<<"*", rest::binary>>, acc, stack, context, comb__line, comb__offset) do
    cron__544(rest, [wild: "*"] ++ acc, stack, context, comb__line, comb__offset + 1)
  end

  defp cron__543(rest, acc, stack, context, line, offset) do
    cron__542(rest, acc, stack, context, line, offset)
  end

  defp cron__544(rest, acc, [_, previous_acc | stack], context, line, offset) do
    cron__539(rest, acc ++ previous_acc, stack, context, line, offset)
  end

  defp cron__545(_, _, [{rest, context, line, offset} | _] = stack, _, _, _) do
    cron__543(rest, [], stack, context, line, offset)
  end

  defp cron__546(rest, acc, stack, context, line, offset) do
    cron__547(rest, [], [acc | stack], context, line, offset)
  end

  defp cron__547(rest, acc, stack, context, line, offset) do
    cron__548(rest, [], [acc | stack], context, line, offset)
  end

  defp cron__548(<<x0::integer, rest::binary>>, acc, stack, context, comb__line, comb__offset)
       when x0 >= 48 and x0 <= 57 do
    cron__549(rest, [x0 - 48] ++ acc, stack, context, comb__line, comb__offset + 1)
  end

  defp cron__548(rest, _acc, stack, context, line, offset) do
    [_, acc | stack] = stack
    cron__545(rest, acc, stack, context, line, offset)
  end

  defp cron__549(rest, acc, stack, context, line, offset) do
    cron__551(rest, acc, [1 | stack], context, line, offset)
  end

  defp cron__551(<<x0::integer, rest::binary>>, acc, stack, context, comb__line, comb__offset)
       when x0 >= 48 and x0 <= 57 do
    cron__552(rest, [x0] ++ acc, stack, context, comb__line, comb__offset + 1)
  end

  defp cron__551(rest, acc, stack, context, line, offset) do
    cron__550(rest, acc, stack, context, line, offset)
  end

  defp cron__550(rest, acc, [_ | stack], context, line, offset) do
    cron__553(rest, acc, stack, context, line, offset)
  end

  defp cron__552(rest, acc, [1 | stack], context, line, offset) do
    cron__553(rest, acc, stack, context, line, offset)
  end

  defp cron__552(rest, acc, [count | stack], context, line, offset) do
    cron__551(rest, acc, [count - 1 | stack], context, line, offset)
  end

  defp cron__553(rest, user_acc, [acc | stack], context, line, offset) do
    _ = user_acc

    cron__554(
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

  defp cron__554(rest, user_acc, [acc | stack], context, line, offset) do
    _ = user_acc

    cron__555(
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

  defp cron__555(rest, acc, [_, previous_acc | stack], context, line, offset) do
    cron__539(rest, acc ++ previous_acc, stack, context, line, offset)
  end

  defp cron__556(_, _, [{rest, context, line, offset} | _] = stack, _, _, _) do
    cron__546(rest, [], stack, context, line, offset)
  end

  defp cron__557(rest, acc, stack, context, line, offset) do
    cron__558(rest, [], [acc | stack], context, line, offset)
  end

  defp cron__558(rest, acc, stack, context, line, offset) do
    cron__559(rest, [], [acc | stack], context, line, offset)
  end

  defp cron__559(<<x0::integer, rest::binary>>, acc, stack, context, comb__line, comb__offset)
       when x0 >= 48 and x0 <= 57 do
    cron__560(rest, [x0 - 48] ++ acc, stack, context, comb__line, comb__offset + 1)
  end

  defp cron__559(rest, _acc, stack, context, line, offset) do
    [_, acc | stack] = stack
    cron__556(rest, acc, stack, context, line, offset)
  end

  defp cron__560(rest, acc, stack, context, line, offset) do
    cron__562(rest, acc, [1 | stack], context, line, offset)
  end

  defp cron__562(<<x0::integer, rest::binary>>, acc, stack, context, comb__line, comb__offset)
       when x0 >= 48 and x0 <= 57 do
    cron__563(rest, [x0] ++ acc, stack, context, comb__line, comb__offset + 1)
  end

  defp cron__562(rest, acc, stack, context, line, offset) do
    cron__561(rest, acc, stack, context, line, offset)
  end

  defp cron__561(rest, acc, [_ | stack], context, line, offset) do
    cron__564(rest, acc, stack, context, line, offset)
  end

  defp cron__563(rest, acc, [1 | stack], context, line, offset) do
    cron__564(rest, acc, stack, context, line, offset)
  end

  defp cron__563(rest, acc, [count | stack], context, line, offset) do
    cron__562(rest, acc, [count - 1 | stack], context, line, offset)
  end

  defp cron__564(rest, user_acc, [acc | stack], context, line, offset) do
    _ = user_acc

    cron__565(
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

  defp cron__565(<<"-", rest::binary>>, acc, stack, context, comb__line, comb__offset) do
    cron__566(rest, [] ++ acc, stack, context, comb__line, comb__offset + 1)
  end

  defp cron__565(rest, _acc, stack, context, line, offset) do
    [acc | stack] = stack
    cron__556(rest, acc, stack, context, line, offset)
  end

  defp cron__566(rest, acc, stack, context, line, offset) do
    cron__567(rest, [], [acc | stack], context, line, offset)
  end

  defp cron__567(<<x0::integer, rest::binary>>, acc, stack, context, comb__line, comb__offset)
       when x0 >= 48 and x0 <= 57 do
    cron__568(rest, [x0 - 48] ++ acc, stack, context, comb__line, comb__offset + 1)
  end

  defp cron__567(rest, _acc, stack, context, line, offset) do
    [_, acc | stack] = stack
    cron__556(rest, acc, stack, context, line, offset)
  end

  defp cron__568(rest, acc, stack, context, line, offset) do
    cron__570(rest, acc, [1 | stack], context, line, offset)
  end

  defp cron__570(<<x0::integer, rest::binary>>, acc, stack, context, comb__line, comb__offset)
       when x0 >= 48 and x0 <= 57 do
    cron__571(rest, [x0] ++ acc, stack, context, comb__line, comb__offset + 1)
  end

  defp cron__570(rest, acc, stack, context, line, offset) do
    cron__569(rest, acc, stack, context, line, offset)
  end

  defp cron__569(rest, acc, [_ | stack], context, line, offset) do
    cron__572(rest, acc, stack, context, line, offset)
  end

  defp cron__571(rest, acc, [1 | stack], context, line, offset) do
    cron__572(rest, acc, stack, context, line, offset)
  end

  defp cron__571(rest, acc, [count | stack], context, line, offset) do
    cron__570(rest, acc, [count - 1 | stack], context, line, offset)
  end

  defp cron__572(rest, user_acc, [acc | stack], context, line, offset) do
    _ = user_acc

    cron__573(
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

  defp cron__573(rest, user_acc, [acc | stack], context, line, offset) do
    _ = user_acc
    cron__574(rest, [range: :lists.reverse(user_acc)] ++ acc, stack, context, line, offset)
  end

  defp cron__574(rest, acc, [_, previous_acc | stack], context, line, offset) do
    cron__539(rest, acc ++ previous_acc, stack, context, line, offset)
  end

  defp cron__575(_, _, [{rest, context, line, offset} | _] = stack, _, _, _) do
    cron__557(rest, [], stack, context, line, offset)
  end

  defp cron__576(rest, acc, stack, context, line, offset) do
    cron__577(rest, [], [acc | stack], context, line, offset)
  end

  defp cron__577(rest, acc, stack, context, line, offset) do
    cron__598(rest, [], [{rest, context, line, offset}, acc | stack], context, line, offset)
  end

  defp cron__579(rest, acc, stack, context, line, offset) do
    cron__580(rest, [], [acc | stack], context, line, offset)
  end

  defp cron__580(rest, acc, stack, context, line, offset) do
    cron__581(rest, [], [acc | stack], context, line, offset)
  end

  defp cron__581(<<x0::integer, rest::binary>>, acc, stack, context, comb__line, comb__offset)
       when x0 >= 48 and x0 <= 57 do
    cron__582(rest, [x0 - 48] ++ acc, stack, context, comb__line, comb__offset + 1)
  end

  defp cron__581(rest, _acc, stack, context, line, offset) do
    [_, _, _, _, acc | stack] = stack
    cron__575(rest, acc, stack, context, line, offset)
  end

  defp cron__582(rest, acc, stack, context, line, offset) do
    cron__584(rest, acc, [1 | stack], context, line, offset)
  end

  defp cron__584(<<x0::integer, rest::binary>>, acc, stack, context, comb__line, comb__offset)
       when x0 >= 48 and x0 <= 57 do
    cron__585(rest, [x0] ++ acc, stack, context, comb__line, comb__offset + 1)
  end

  defp cron__584(rest, acc, stack, context, line, offset) do
    cron__583(rest, acc, stack, context, line, offset)
  end

  defp cron__583(rest, acc, [_ | stack], context, line, offset) do
    cron__586(rest, acc, stack, context, line, offset)
  end

  defp cron__585(rest, acc, [1 | stack], context, line, offset) do
    cron__586(rest, acc, stack, context, line, offset)
  end

  defp cron__585(rest, acc, [count | stack], context, line, offset) do
    cron__584(rest, acc, [count - 1 | stack], context, line, offset)
  end

  defp cron__586(rest, user_acc, [acc | stack], context, line, offset) do
    _ = user_acc

    cron__587(
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

  defp cron__587(<<"-", rest::binary>>, acc, stack, context, comb__line, comb__offset) do
    cron__588(rest, [] ++ acc, stack, context, comb__line, comb__offset + 1)
  end

  defp cron__587(rest, _acc, stack, context, line, offset) do
    [_, _, _, acc | stack] = stack
    cron__575(rest, acc, stack, context, line, offset)
  end

  defp cron__588(rest, acc, stack, context, line, offset) do
    cron__589(rest, [], [acc | stack], context, line, offset)
  end

  defp cron__589(<<x0::integer, rest::binary>>, acc, stack, context, comb__line, comb__offset)
       when x0 >= 48 and x0 <= 57 do
    cron__590(rest, [x0 - 48] ++ acc, stack, context, comb__line, comb__offset + 1)
  end

  defp cron__589(rest, _acc, stack, context, line, offset) do
    [_, _, _, _, acc | stack] = stack
    cron__575(rest, acc, stack, context, line, offset)
  end

  defp cron__590(rest, acc, stack, context, line, offset) do
    cron__592(rest, acc, [1 | stack], context, line, offset)
  end

  defp cron__592(<<x0::integer, rest::binary>>, acc, stack, context, comb__line, comb__offset)
       when x0 >= 48 and x0 <= 57 do
    cron__593(rest, [x0] ++ acc, stack, context, comb__line, comb__offset + 1)
  end

  defp cron__592(rest, acc, stack, context, line, offset) do
    cron__591(rest, acc, stack, context, line, offset)
  end

  defp cron__591(rest, acc, [_ | stack], context, line, offset) do
    cron__594(rest, acc, stack, context, line, offset)
  end

  defp cron__593(rest, acc, [1 | stack], context, line, offset) do
    cron__594(rest, acc, stack, context, line, offset)
  end

  defp cron__593(rest, acc, [count | stack], context, line, offset) do
    cron__592(rest, acc, [count - 1 | stack], context, line, offset)
  end

  defp cron__594(rest, user_acc, [acc | stack], context, line, offset) do
    _ = user_acc

    cron__595(
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

  defp cron__595(rest, user_acc, [acc | stack], context, line, offset) do
    _ = user_acc
    cron__596(rest, [range: :lists.reverse(user_acc)] ++ acc, stack, context, line, offset)
  end

  defp cron__596(rest, acc, [_, previous_acc | stack], context, line, offset) do
    cron__578(rest, acc ++ previous_acc, stack, context, line, offset)
  end

  defp cron__597(_, _, [{rest, context, line, offset} | _] = stack, _, _, _) do
    cron__579(rest, [], stack, context, line, offset)
  end

  defp cron__598(<<"*", rest::binary>>, acc, stack, context, comb__line, comb__offset) do
    cron__599(rest, [wild: "*"] ++ acc, stack, context, comb__line, comb__offset + 1)
  end

  defp cron__598(rest, acc, stack, context, line, offset) do
    cron__597(rest, acc, stack, context, line, offset)
  end

  defp cron__599(rest, acc, [_, previous_acc | stack], context, line, offset) do
    cron__578(rest, acc ++ previous_acc, stack, context, line, offset)
  end

  defp cron__578(<<"/", rest::binary>>, acc, stack, context, comb__line, comb__offset) do
    cron__600(rest, [] ++ acc, stack, context, comb__line, comb__offset + 1)
  end

  defp cron__578(rest, _acc, stack, context, line, offset) do
    [acc | stack] = stack
    cron__575(rest, acc, stack, context, line, offset)
  end

  defp cron__600(rest, acc, stack, context, line, offset) do
    cron__601(rest, [], [acc | stack], context, line, offset)
  end

  defp cron__601(<<x0::integer, rest::binary>>, acc, stack, context, comb__line, comb__offset)
       when x0 >= 48 and x0 <= 57 do
    cron__602(rest, [x0 - 48] ++ acc, stack, context, comb__line, comb__offset + 1)
  end

  defp cron__601(rest, _acc, stack, context, line, offset) do
    [_, acc | stack] = stack
    cron__575(rest, acc, stack, context, line, offset)
  end

  defp cron__602(rest, acc, stack, context, line, offset) do
    cron__604(rest, acc, [1 | stack], context, line, offset)
  end

  defp cron__604(<<x0::integer, rest::binary>>, acc, stack, context, comb__line, comb__offset)
       when x0 >= 48 and x0 <= 57 do
    cron__605(rest, [x0] ++ acc, stack, context, comb__line, comb__offset + 1)
  end

  defp cron__604(rest, acc, stack, context, line, offset) do
    cron__603(rest, acc, stack, context, line, offset)
  end

  defp cron__603(rest, acc, [_ | stack], context, line, offset) do
    cron__606(rest, acc, stack, context, line, offset)
  end

  defp cron__605(rest, acc, [1 | stack], context, line, offset) do
    cron__606(rest, acc, stack, context, line, offset)
  end

  defp cron__605(rest, acc, [count | stack], context, line, offset) do
    cron__604(rest, acc, [count - 1 | stack], context, line, offset)
  end

  defp cron__606(rest, user_acc, [acc | stack], context, line, offset) do
    _ = user_acc

    cron__607(
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

  defp cron__607(rest, user_acc, [acc | stack], context, line, offset) do
    _ = user_acc
    cron__608(rest, [step: :lists.reverse(user_acc)] ++ acc, stack, context, line, offset)
  end

  defp cron__608(rest, acc, [_, previous_acc | stack], context, line, offset) do
    cron__539(rest, acc ++ previous_acc, stack, context, line, offset)
  end

  defp cron__539(rest, acc, [_, previous_acc | stack], context, line, offset) do
    cron__537(rest, acc ++ previous_acc, stack, context, line, offset)
  end

  defp cron__609(_, _, [{rest, context, line, offset} | _] = stack, _, _, _) do
    cron__538(rest, [], stack, context, line, offset)
  end

  defp cron__610(rest, acc, stack, context, line, offset) do
    cron__611(rest, [], [acc | stack], context, line, offset)
  end

  defp cron__611(<<"JAN", rest::binary>>, acc, stack, context, comb__line, comb__offset) do
    cron__612(rest, [1] ++ acc, stack, context, comb__line, comb__offset + 3)
  end

  defp cron__611(<<"FEB", rest::binary>>, acc, stack, context, comb__line, comb__offset) do
    cron__612(rest, [2] ++ acc, stack, context, comb__line, comb__offset + 3)
  end

  defp cron__611(<<"MAR", rest::binary>>, acc, stack, context, comb__line, comb__offset) do
    cron__612(rest, [3] ++ acc, stack, context, comb__line, comb__offset + 3)
  end

  defp cron__611(<<"APR", rest::binary>>, acc, stack, context, comb__line, comb__offset) do
    cron__612(rest, [4] ++ acc, stack, context, comb__line, comb__offset + 3)
  end

  defp cron__611(<<"MAY", rest::binary>>, acc, stack, context, comb__line, comb__offset) do
    cron__612(rest, [5] ++ acc, stack, context, comb__line, comb__offset + 3)
  end

  defp cron__611(<<"JUN", rest::binary>>, acc, stack, context, comb__line, comb__offset) do
    cron__612(rest, [6] ++ acc, stack, context, comb__line, comb__offset + 3)
  end

  defp cron__611(<<"JUL", rest::binary>>, acc, stack, context, comb__line, comb__offset) do
    cron__612(rest, [7] ++ acc, stack, context, comb__line, comb__offset + 3)
  end

  defp cron__611(<<"AUG", rest::binary>>, acc, stack, context, comb__line, comb__offset) do
    cron__612(rest, '\b' ++ acc, stack, context, comb__line, comb__offset + 3)
  end

  defp cron__611(<<"SEP", rest::binary>>, acc, stack, context, comb__line, comb__offset) do
    cron__612(rest, '\t' ++ acc, stack, context, comb__line, comb__offset + 3)
  end

  defp cron__611(<<"OCT", rest::binary>>, acc, stack, context, comb__line, comb__offset) do
    cron__612(rest, '\n' ++ acc, stack, context, comb__line, comb__offset + 3)
  end

  defp cron__611(<<"NOV", rest::binary>>, acc, stack, context, comb__line, comb__offset) do
    cron__612(rest, '\v' ++ acc, stack, context, comb__line, comb__offset + 3)
  end

  defp cron__611(<<"DEC", rest::binary>>, acc, stack, context, comb__line, comb__offset) do
    cron__612(rest, '\f' ++ acc, stack, context, comb__line, comb__offset + 3)
  end

  defp cron__611(rest, _acc, stack, context, line, offset) do
    [acc | stack] = stack
    cron__609(rest, acc, stack, context, line, offset)
  end

  defp cron__612(rest, user_acc, [acc | stack], context, line, offset) do
    _ = user_acc

    cron__613(
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

  defp cron__613(rest, acc, [_, previous_acc | stack], context, line, offset) do
    cron__537(rest, acc ++ previous_acc, stack, context, line, offset)
  end

  defp cron__535(_, _, [{rest, acc, context, line, offset} | stack], _, _, _) do
    cron__614(rest, acc, stack, context, line, offset)
  end

  defp cron__537(
         inner_rest,
         inner_acc,
         [{rest, acc, context, line, offset} | stack],
         inner_context,
         inner_line,
         inner_offset
       ) do
    _ = {rest, acc, context, line, offset}

    cron__536(
      inner_rest,
      [],
      [{inner_rest, inner_acc ++ acc, inner_context, inner_line, inner_offset} | stack],
      inner_context,
      inner_line,
      inner_offset
    )
  end

  defp cron__614(rest, user_acc, [acc | stack], context, line, offset) do
    _ = user_acc
    cron__615(rest, [months: :lists.reverse(user_acc)] ++ acc, stack, context, line, offset)
  end

  defp cron__615(rest, acc, stack, context, line, offset) do
    cron__616(rest, [], [acc | stack], context, line, offset)
  end

  defp cron__616(rest, acc, stack, context, line, offset) do
    cron__617(rest, [], [acc | stack], context, line, offset)
  end

  defp cron__617(<<x0::integer, rest::binary>>, acc, stack, context, comb__line, comb__offset)
       when x0 === 32 or x0 === 9 do
    cron__618(rest, acc, stack, context, comb__line, comb__offset + 1)
  end

  defp cron__617(rest, _acc, _stack, context, line, offset) do
    {:error, "expected ASCII character equal to ' ' or equal to '\\t'", rest, context, line,
     offset}
  end

  defp cron__618(<<x0::integer, rest::binary>>, acc, stack, context, comb__line, comb__offset)
       when x0 === 32 or x0 === 9 do
    cron__620(rest, acc, stack, context, comb__line, comb__offset + 1)
  end

  defp cron__618(rest, acc, stack, context, line, offset) do
    cron__619(rest, acc, stack, context, line, offset)
  end

  defp cron__620(rest, acc, stack, context, line, offset) do
    cron__618(rest, acc, stack, context, line, offset)
  end

  defp cron__619(rest, user_acc, [acc | stack], context, line, offset) do
    _ = user_acc
    cron__621(rest, acc, stack, context, line, offset)
  end

  defp cron__621(rest, user_acc, [acc | stack], context, line, offset) do
    _ = user_acc
    cron__622(rest, [] ++ acc, stack, context, line, offset)
  end

  defp cron__622(rest, acc, stack, context, line, offset) do
    cron__623(rest, [], [acc | stack], context, line, offset)
  end

  defp cron__623(rest, acc, stack, context, line, offset) do
    cron__697(rest, [], [{rest, context, line, offset}, acc | stack], context, line, offset)
  end

  defp cron__625(rest, acc, stack, context, line, offset) do
    cron__663(rest, [], [{rest, context, line, offset}, acc | stack], context, line, offset)
  end

  defp cron__627(<<",", rest::binary>>, acc, stack, context, comb__line, comb__offset) do
    cron__628(rest, [] ++ acc, stack, context, comb__line, comb__offset + 1)
  end

  defp cron__627(rest, _acc, _stack, context, line, offset) do
    {:error,
     "expected string \"MON\" or string \"TUE\" or string \"WED\" or string \"THU\" or string \"FRI\" or string \"SAT\" or string \"SUN\" or string \"*\" or ASCII character in the range '0' to '9', followed by ASCII character in the range '0' to '9', followed by string \"-\", followed by ASCII character in the range '0' to '9', followed by ASCII character in the range '0' to '9', followed by string \"/\", followed by ASCII character in the range '0' to '9', followed by ASCII character in the range '0' to '9' or ASCII character in the range '0' to '9', followed by ASCII character in the range '0' to '9', followed by string \"-\", followed by ASCII character in the range '0' to '9', followed by ASCII character in the range '0' to '9' or ASCII character in the range '0' to '9', followed by ASCII character in the range '0' to '9' or string \"*\" or string \",\"",
     rest, context, line, offset}
  end

  defp cron__628(rest, acc, [_, previous_acc | stack], context, line, offset) do
    cron__626(rest, acc ++ previous_acc, stack, context, line, offset)
  end

  defp cron__629(_, _, [{rest, context, line, offset} | _] = stack, _, _, _) do
    cron__627(rest, [], stack, context, line, offset)
  end

  defp cron__630(<<"*", rest::binary>>, acc, stack, context, comb__line, comb__offset) do
    cron__631(rest, [wild: "*"] ++ acc, stack, context, comb__line, comb__offset + 1)
  end

  defp cron__630(rest, acc, stack, context, line, offset) do
    cron__629(rest, acc, stack, context, line, offset)
  end

  defp cron__631(rest, acc, [_, previous_acc | stack], context, line, offset) do
    cron__626(rest, acc ++ previous_acc, stack, context, line, offset)
  end

  defp cron__632(_, _, [{rest, context, line, offset} | _] = stack, _, _, _) do
    cron__630(rest, [], stack, context, line, offset)
  end

  defp cron__633(rest, acc, stack, context, line, offset) do
    cron__634(rest, [], [acc | stack], context, line, offset)
  end

  defp cron__634(rest, acc, stack, context, line, offset) do
    cron__635(rest, [], [acc | stack], context, line, offset)
  end

  defp cron__635(<<x0::integer, rest::binary>>, acc, stack, context, comb__line, comb__offset)
       when x0 >= 48 and x0 <= 57 do
    cron__636(rest, [x0 - 48] ++ acc, stack, context, comb__line, comb__offset + 1)
  end

  defp cron__635(rest, _acc, stack, context, line, offset) do
    [_, acc | stack] = stack
    cron__632(rest, acc, stack, context, line, offset)
  end

  defp cron__636(rest, acc, stack, context, line, offset) do
    cron__638(rest, acc, [1 | stack], context, line, offset)
  end

  defp cron__638(<<x0::integer, rest::binary>>, acc, stack, context, comb__line, comb__offset)
       when x0 >= 48 and x0 <= 57 do
    cron__639(rest, [x0] ++ acc, stack, context, comb__line, comb__offset + 1)
  end

  defp cron__638(rest, acc, stack, context, line, offset) do
    cron__637(rest, acc, stack, context, line, offset)
  end

  defp cron__637(rest, acc, [_ | stack], context, line, offset) do
    cron__640(rest, acc, stack, context, line, offset)
  end

  defp cron__639(rest, acc, [1 | stack], context, line, offset) do
    cron__640(rest, acc, stack, context, line, offset)
  end

  defp cron__639(rest, acc, [count | stack], context, line, offset) do
    cron__638(rest, acc, [count - 1 | stack], context, line, offset)
  end

  defp cron__640(rest, user_acc, [acc | stack], context, line, offset) do
    _ = user_acc

    cron__641(
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

  defp cron__641(rest, user_acc, [acc | stack], context, line, offset) do
    _ = user_acc

    cron__642(
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

  defp cron__642(rest, acc, [_, previous_acc | stack], context, line, offset) do
    cron__626(rest, acc ++ previous_acc, stack, context, line, offset)
  end

  defp cron__643(_, _, [{rest, context, line, offset} | _] = stack, _, _, _) do
    cron__633(rest, [], stack, context, line, offset)
  end

  defp cron__644(rest, acc, stack, context, line, offset) do
    cron__645(rest, [], [acc | stack], context, line, offset)
  end

  defp cron__645(rest, acc, stack, context, line, offset) do
    cron__646(rest, [], [acc | stack], context, line, offset)
  end

  defp cron__646(<<x0::integer, rest::binary>>, acc, stack, context, comb__line, comb__offset)
       when x0 >= 48 and x0 <= 57 do
    cron__647(rest, [x0 - 48] ++ acc, stack, context, comb__line, comb__offset + 1)
  end

  defp cron__646(rest, _acc, stack, context, line, offset) do
    [_, acc | stack] = stack
    cron__643(rest, acc, stack, context, line, offset)
  end

  defp cron__647(rest, acc, stack, context, line, offset) do
    cron__649(rest, acc, [1 | stack], context, line, offset)
  end

  defp cron__649(<<x0::integer, rest::binary>>, acc, stack, context, comb__line, comb__offset)
       when x0 >= 48 and x0 <= 57 do
    cron__650(rest, [x0] ++ acc, stack, context, comb__line, comb__offset + 1)
  end

  defp cron__649(rest, acc, stack, context, line, offset) do
    cron__648(rest, acc, stack, context, line, offset)
  end

  defp cron__648(rest, acc, [_ | stack], context, line, offset) do
    cron__651(rest, acc, stack, context, line, offset)
  end

  defp cron__650(rest, acc, [1 | stack], context, line, offset) do
    cron__651(rest, acc, stack, context, line, offset)
  end

  defp cron__650(rest, acc, [count | stack], context, line, offset) do
    cron__649(rest, acc, [count - 1 | stack], context, line, offset)
  end

  defp cron__651(rest, user_acc, [acc | stack], context, line, offset) do
    _ = user_acc

    cron__652(
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

  defp cron__652(<<"-", rest::binary>>, acc, stack, context, comb__line, comb__offset) do
    cron__653(rest, [] ++ acc, stack, context, comb__line, comb__offset + 1)
  end

  defp cron__652(rest, _acc, stack, context, line, offset) do
    [acc | stack] = stack
    cron__643(rest, acc, stack, context, line, offset)
  end

  defp cron__653(rest, acc, stack, context, line, offset) do
    cron__654(rest, [], [acc | stack], context, line, offset)
  end

  defp cron__654(<<x0::integer, rest::binary>>, acc, stack, context, comb__line, comb__offset)
       when x0 >= 48 and x0 <= 57 do
    cron__655(rest, [x0 - 48] ++ acc, stack, context, comb__line, comb__offset + 1)
  end

  defp cron__654(rest, _acc, stack, context, line, offset) do
    [_, acc | stack] = stack
    cron__643(rest, acc, stack, context, line, offset)
  end

  defp cron__655(rest, acc, stack, context, line, offset) do
    cron__657(rest, acc, [1 | stack], context, line, offset)
  end

  defp cron__657(<<x0::integer, rest::binary>>, acc, stack, context, comb__line, comb__offset)
       when x0 >= 48 and x0 <= 57 do
    cron__658(rest, [x0] ++ acc, stack, context, comb__line, comb__offset + 1)
  end

  defp cron__657(rest, acc, stack, context, line, offset) do
    cron__656(rest, acc, stack, context, line, offset)
  end

  defp cron__656(rest, acc, [_ | stack], context, line, offset) do
    cron__659(rest, acc, stack, context, line, offset)
  end

  defp cron__658(rest, acc, [1 | stack], context, line, offset) do
    cron__659(rest, acc, stack, context, line, offset)
  end

  defp cron__658(rest, acc, [count | stack], context, line, offset) do
    cron__657(rest, acc, [count - 1 | stack], context, line, offset)
  end

  defp cron__659(rest, user_acc, [acc | stack], context, line, offset) do
    _ = user_acc

    cron__660(
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

  defp cron__660(rest, user_acc, [acc | stack], context, line, offset) do
    _ = user_acc
    cron__661(rest, [range: :lists.reverse(user_acc)] ++ acc, stack, context, line, offset)
  end

  defp cron__661(rest, acc, [_, previous_acc | stack], context, line, offset) do
    cron__626(rest, acc ++ previous_acc, stack, context, line, offset)
  end

  defp cron__662(_, _, [{rest, context, line, offset} | _] = stack, _, _, _) do
    cron__644(rest, [], stack, context, line, offset)
  end

  defp cron__663(rest, acc, stack, context, line, offset) do
    cron__664(rest, [], [acc | stack], context, line, offset)
  end

  defp cron__664(rest, acc, stack, context, line, offset) do
    cron__685(rest, [], [{rest, context, line, offset}, acc | stack], context, line, offset)
  end

  defp cron__666(rest, acc, stack, context, line, offset) do
    cron__667(rest, [], [acc | stack], context, line, offset)
  end

  defp cron__667(rest, acc, stack, context, line, offset) do
    cron__668(rest, [], [acc | stack], context, line, offset)
  end

  defp cron__668(<<x0::integer, rest::binary>>, acc, stack, context, comb__line, comb__offset)
       when x0 >= 48 and x0 <= 57 do
    cron__669(rest, [x0 - 48] ++ acc, stack, context, comb__line, comb__offset + 1)
  end

  defp cron__668(rest, _acc, stack, context, line, offset) do
    [_, _, _, _, acc | stack] = stack
    cron__662(rest, acc, stack, context, line, offset)
  end

  defp cron__669(rest, acc, stack, context, line, offset) do
    cron__671(rest, acc, [1 | stack], context, line, offset)
  end

  defp cron__671(<<x0::integer, rest::binary>>, acc, stack, context, comb__line, comb__offset)
       when x0 >= 48 and x0 <= 57 do
    cron__672(rest, [x0] ++ acc, stack, context, comb__line, comb__offset + 1)
  end

  defp cron__671(rest, acc, stack, context, line, offset) do
    cron__670(rest, acc, stack, context, line, offset)
  end

  defp cron__670(rest, acc, [_ | stack], context, line, offset) do
    cron__673(rest, acc, stack, context, line, offset)
  end

  defp cron__672(rest, acc, [1 | stack], context, line, offset) do
    cron__673(rest, acc, stack, context, line, offset)
  end

  defp cron__672(rest, acc, [count | stack], context, line, offset) do
    cron__671(rest, acc, [count - 1 | stack], context, line, offset)
  end

  defp cron__673(rest, user_acc, [acc | stack], context, line, offset) do
    _ = user_acc

    cron__674(
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

  defp cron__674(<<"-", rest::binary>>, acc, stack, context, comb__line, comb__offset) do
    cron__675(rest, [] ++ acc, stack, context, comb__line, comb__offset + 1)
  end

  defp cron__674(rest, _acc, stack, context, line, offset) do
    [_, _, _, acc | stack] = stack
    cron__662(rest, acc, stack, context, line, offset)
  end

  defp cron__675(rest, acc, stack, context, line, offset) do
    cron__676(rest, [], [acc | stack], context, line, offset)
  end

  defp cron__676(<<x0::integer, rest::binary>>, acc, stack, context, comb__line, comb__offset)
       when x0 >= 48 and x0 <= 57 do
    cron__677(rest, [x0 - 48] ++ acc, stack, context, comb__line, comb__offset + 1)
  end

  defp cron__676(rest, _acc, stack, context, line, offset) do
    [_, _, _, _, acc | stack] = stack
    cron__662(rest, acc, stack, context, line, offset)
  end

  defp cron__677(rest, acc, stack, context, line, offset) do
    cron__679(rest, acc, [1 | stack], context, line, offset)
  end

  defp cron__679(<<x0::integer, rest::binary>>, acc, stack, context, comb__line, comb__offset)
       when x0 >= 48 and x0 <= 57 do
    cron__680(rest, [x0] ++ acc, stack, context, comb__line, comb__offset + 1)
  end

  defp cron__679(rest, acc, stack, context, line, offset) do
    cron__678(rest, acc, stack, context, line, offset)
  end

  defp cron__678(rest, acc, [_ | stack], context, line, offset) do
    cron__681(rest, acc, stack, context, line, offset)
  end

  defp cron__680(rest, acc, [1 | stack], context, line, offset) do
    cron__681(rest, acc, stack, context, line, offset)
  end

  defp cron__680(rest, acc, [count | stack], context, line, offset) do
    cron__679(rest, acc, [count - 1 | stack], context, line, offset)
  end

  defp cron__681(rest, user_acc, [acc | stack], context, line, offset) do
    _ = user_acc

    cron__682(
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

  defp cron__682(rest, user_acc, [acc | stack], context, line, offset) do
    _ = user_acc
    cron__683(rest, [range: :lists.reverse(user_acc)] ++ acc, stack, context, line, offset)
  end

  defp cron__683(rest, acc, [_, previous_acc | stack], context, line, offset) do
    cron__665(rest, acc ++ previous_acc, stack, context, line, offset)
  end

  defp cron__684(_, _, [{rest, context, line, offset} | _] = stack, _, _, _) do
    cron__666(rest, [], stack, context, line, offset)
  end

  defp cron__685(<<"*", rest::binary>>, acc, stack, context, comb__line, comb__offset) do
    cron__686(rest, [wild: "*"] ++ acc, stack, context, comb__line, comb__offset + 1)
  end

  defp cron__685(rest, acc, stack, context, line, offset) do
    cron__684(rest, acc, stack, context, line, offset)
  end

  defp cron__686(rest, acc, [_, previous_acc | stack], context, line, offset) do
    cron__665(rest, acc ++ previous_acc, stack, context, line, offset)
  end

  defp cron__665(<<"/", rest::binary>>, acc, stack, context, comb__line, comb__offset) do
    cron__687(rest, [] ++ acc, stack, context, comb__line, comb__offset + 1)
  end

  defp cron__665(rest, _acc, stack, context, line, offset) do
    [acc | stack] = stack
    cron__662(rest, acc, stack, context, line, offset)
  end

  defp cron__687(rest, acc, stack, context, line, offset) do
    cron__688(rest, [], [acc | stack], context, line, offset)
  end

  defp cron__688(<<x0::integer, rest::binary>>, acc, stack, context, comb__line, comb__offset)
       when x0 >= 48 and x0 <= 57 do
    cron__689(rest, [x0 - 48] ++ acc, stack, context, comb__line, comb__offset + 1)
  end

  defp cron__688(rest, _acc, stack, context, line, offset) do
    [_, acc | stack] = stack
    cron__662(rest, acc, stack, context, line, offset)
  end

  defp cron__689(rest, acc, stack, context, line, offset) do
    cron__691(rest, acc, [1 | stack], context, line, offset)
  end

  defp cron__691(<<x0::integer, rest::binary>>, acc, stack, context, comb__line, comb__offset)
       when x0 >= 48 and x0 <= 57 do
    cron__692(rest, [x0] ++ acc, stack, context, comb__line, comb__offset + 1)
  end

  defp cron__691(rest, acc, stack, context, line, offset) do
    cron__690(rest, acc, stack, context, line, offset)
  end

  defp cron__690(rest, acc, [_ | stack], context, line, offset) do
    cron__693(rest, acc, stack, context, line, offset)
  end

  defp cron__692(rest, acc, [1 | stack], context, line, offset) do
    cron__693(rest, acc, stack, context, line, offset)
  end

  defp cron__692(rest, acc, [count | stack], context, line, offset) do
    cron__691(rest, acc, [count - 1 | stack], context, line, offset)
  end

  defp cron__693(rest, user_acc, [acc | stack], context, line, offset) do
    _ = user_acc

    cron__694(
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

  defp cron__694(rest, user_acc, [acc | stack], context, line, offset) do
    _ = user_acc
    cron__695(rest, [step: :lists.reverse(user_acc)] ++ acc, stack, context, line, offset)
  end

  defp cron__695(rest, acc, [_, previous_acc | stack], context, line, offset) do
    cron__626(rest, acc ++ previous_acc, stack, context, line, offset)
  end

  defp cron__626(rest, acc, [_, previous_acc | stack], context, line, offset) do
    cron__624(rest, acc ++ previous_acc, stack, context, line, offset)
  end

  defp cron__696(_, _, [{rest, context, line, offset} | _] = stack, _, _, _) do
    cron__625(rest, [], stack, context, line, offset)
  end

  defp cron__697(rest, acc, stack, context, line, offset) do
    cron__698(rest, [], [acc | stack], context, line, offset)
  end

  defp cron__698(<<"MON", rest::binary>>, acc, stack, context, comb__line, comb__offset) do
    cron__699(rest, [1] ++ acc, stack, context, comb__line, comb__offset + 3)
  end

  defp cron__698(<<"TUE", rest::binary>>, acc, stack, context, comb__line, comb__offset) do
    cron__699(rest, [2] ++ acc, stack, context, comb__line, comb__offset + 3)
  end

  defp cron__698(<<"WED", rest::binary>>, acc, stack, context, comb__line, comb__offset) do
    cron__699(rest, [3] ++ acc, stack, context, comb__line, comb__offset + 3)
  end

  defp cron__698(<<"THU", rest::binary>>, acc, stack, context, comb__line, comb__offset) do
    cron__699(rest, [4] ++ acc, stack, context, comb__line, comb__offset + 3)
  end

  defp cron__698(<<"FRI", rest::binary>>, acc, stack, context, comb__line, comb__offset) do
    cron__699(rest, [5] ++ acc, stack, context, comb__line, comb__offset + 3)
  end

  defp cron__698(<<"SAT", rest::binary>>, acc, stack, context, comb__line, comb__offset) do
    cron__699(rest, [6] ++ acc, stack, context, comb__line, comb__offset + 3)
  end

  defp cron__698(<<"SUN", rest::binary>>, acc, stack, context, comb__line, comb__offset) do
    cron__699(rest, [0] ++ acc, stack, context, comb__line, comb__offset + 3)
  end

  defp cron__698(rest, _acc, stack, context, line, offset) do
    [acc | stack] = stack
    cron__696(rest, acc, stack, context, line, offset)
  end

  defp cron__699(rest, user_acc, [acc | stack], context, line, offset) do
    _ = user_acc

    cron__700(
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

  defp cron__700(rest, acc, [_, previous_acc | stack], context, line, offset) do
    cron__624(rest, acc ++ previous_acc, stack, context, line, offset)
  end

  defp cron__624(rest, acc, stack, context, line, offset) do
    cron__702(rest, [], [{rest, acc, context, line, offset} | stack], context, line, offset)
  end

  defp cron__702(rest, acc, stack, context, line, offset) do
    cron__776(rest, [], [{rest, context, line, offset}, acc | stack], context, line, offset)
  end

  defp cron__704(rest, acc, stack, context, line, offset) do
    cron__742(rest, [], [{rest, context, line, offset}, acc | stack], context, line, offset)
  end

  defp cron__706(<<",", rest::binary>>, acc, stack, context, comb__line, comb__offset) do
    cron__707(rest, [] ++ acc, stack, context, comb__line, comb__offset + 1)
  end

  defp cron__706(rest, _acc, stack, context, line, offset) do
    [_, _, _, acc | stack] = stack
    cron__701(rest, acc, stack, context, line, offset)
  end

  defp cron__707(rest, acc, [_, previous_acc | stack], context, line, offset) do
    cron__705(rest, acc ++ previous_acc, stack, context, line, offset)
  end

  defp cron__708(_, _, [{rest, context, line, offset} | _] = stack, _, _, _) do
    cron__706(rest, [], stack, context, line, offset)
  end

  defp cron__709(<<"*", rest::binary>>, acc, stack, context, comb__line, comb__offset) do
    cron__710(rest, [wild: "*"] ++ acc, stack, context, comb__line, comb__offset + 1)
  end

  defp cron__709(rest, acc, stack, context, line, offset) do
    cron__708(rest, acc, stack, context, line, offset)
  end

  defp cron__710(rest, acc, [_, previous_acc | stack], context, line, offset) do
    cron__705(rest, acc ++ previous_acc, stack, context, line, offset)
  end

  defp cron__711(_, _, [{rest, context, line, offset} | _] = stack, _, _, _) do
    cron__709(rest, [], stack, context, line, offset)
  end

  defp cron__712(rest, acc, stack, context, line, offset) do
    cron__713(rest, [], [acc | stack], context, line, offset)
  end

  defp cron__713(rest, acc, stack, context, line, offset) do
    cron__714(rest, [], [acc | stack], context, line, offset)
  end

  defp cron__714(<<x0::integer, rest::binary>>, acc, stack, context, comb__line, comb__offset)
       when x0 >= 48 and x0 <= 57 do
    cron__715(rest, [x0 - 48] ++ acc, stack, context, comb__line, comb__offset + 1)
  end

  defp cron__714(rest, _acc, stack, context, line, offset) do
    [_, acc | stack] = stack
    cron__711(rest, acc, stack, context, line, offset)
  end

  defp cron__715(rest, acc, stack, context, line, offset) do
    cron__717(rest, acc, [1 | stack], context, line, offset)
  end

  defp cron__717(<<x0::integer, rest::binary>>, acc, stack, context, comb__line, comb__offset)
       when x0 >= 48 and x0 <= 57 do
    cron__718(rest, [x0] ++ acc, stack, context, comb__line, comb__offset + 1)
  end

  defp cron__717(rest, acc, stack, context, line, offset) do
    cron__716(rest, acc, stack, context, line, offset)
  end

  defp cron__716(rest, acc, [_ | stack], context, line, offset) do
    cron__719(rest, acc, stack, context, line, offset)
  end

  defp cron__718(rest, acc, [1 | stack], context, line, offset) do
    cron__719(rest, acc, stack, context, line, offset)
  end

  defp cron__718(rest, acc, [count | stack], context, line, offset) do
    cron__717(rest, acc, [count - 1 | stack], context, line, offset)
  end

  defp cron__719(rest, user_acc, [acc | stack], context, line, offset) do
    _ = user_acc

    cron__720(
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

  defp cron__720(rest, user_acc, [acc | stack], context, line, offset) do
    _ = user_acc

    cron__721(
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

  defp cron__721(rest, acc, [_, previous_acc | stack], context, line, offset) do
    cron__705(rest, acc ++ previous_acc, stack, context, line, offset)
  end

  defp cron__722(_, _, [{rest, context, line, offset} | _] = stack, _, _, _) do
    cron__712(rest, [], stack, context, line, offset)
  end

  defp cron__723(rest, acc, stack, context, line, offset) do
    cron__724(rest, [], [acc | stack], context, line, offset)
  end

  defp cron__724(rest, acc, stack, context, line, offset) do
    cron__725(rest, [], [acc | stack], context, line, offset)
  end

  defp cron__725(<<x0::integer, rest::binary>>, acc, stack, context, comb__line, comb__offset)
       when x0 >= 48 and x0 <= 57 do
    cron__726(rest, [x0 - 48] ++ acc, stack, context, comb__line, comb__offset + 1)
  end

  defp cron__725(rest, _acc, stack, context, line, offset) do
    [_, acc | stack] = stack
    cron__722(rest, acc, stack, context, line, offset)
  end

  defp cron__726(rest, acc, stack, context, line, offset) do
    cron__728(rest, acc, [1 | stack], context, line, offset)
  end

  defp cron__728(<<x0::integer, rest::binary>>, acc, stack, context, comb__line, comb__offset)
       when x0 >= 48 and x0 <= 57 do
    cron__729(rest, [x0] ++ acc, stack, context, comb__line, comb__offset + 1)
  end

  defp cron__728(rest, acc, stack, context, line, offset) do
    cron__727(rest, acc, stack, context, line, offset)
  end

  defp cron__727(rest, acc, [_ | stack], context, line, offset) do
    cron__730(rest, acc, stack, context, line, offset)
  end

  defp cron__729(rest, acc, [1 | stack], context, line, offset) do
    cron__730(rest, acc, stack, context, line, offset)
  end

  defp cron__729(rest, acc, [count | stack], context, line, offset) do
    cron__728(rest, acc, [count - 1 | stack], context, line, offset)
  end

  defp cron__730(rest, user_acc, [acc | stack], context, line, offset) do
    _ = user_acc

    cron__731(
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

  defp cron__731(<<"-", rest::binary>>, acc, stack, context, comb__line, comb__offset) do
    cron__732(rest, [] ++ acc, stack, context, comb__line, comb__offset + 1)
  end

  defp cron__731(rest, _acc, stack, context, line, offset) do
    [acc | stack] = stack
    cron__722(rest, acc, stack, context, line, offset)
  end

  defp cron__732(rest, acc, stack, context, line, offset) do
    cron__733(rest, [], [acc | stack], context, line, offset)
  end

  defp cron__733(<<x0::integer, rest::binary>>, acc, stack, context, comb__line, comb__offset)
       when x0 >= 48 and x0 <= 57 do
    cron__734(rest, [x0 - 48] ++ acc, stack, context, comb__line, comb__offset + 1)
  end

  defp cron__733(rest, _acc, stack, context, line, offset) do
    [_, acc | stack] = stack
    cron__722(rest, acc, stack, context, line, offset)
  end

  defp cron__734(rest, acc, stack, context, line, offset) do
    cron__736(rest, acc, [1 | stack], context, line, offset)
  end

  defp cron__736(<<x0::integer, rest::binary>>, acc, stack, context, comb__line, comb__offset)
       when x0 >= 48 and x0 <= 57 do
    cron__737(rest, [x0] ++ acc, stack, context, comb__line, comb__offset + 1)
  end

  defp cron__736(rest, acc, stack, context, line, offset) do
    cron__735(rest, acc, stack, context, line, offset)
  end

  defp cron__735(rest, acc, [_ | stack], context, line, offset) do
    cron__738(rest, acc, stack, context, line, offset)
  end

  defp cron__737(rest, acc, [1 | stack], context, line, offset) do
    cron__738(rest, acc, stack, context, line, offset)
  end

  defp cron__737(rest, acc, [count | stack], context, line, offset) do
    cron__736(rest, acc, [count - 1 | stack], context, line, offset)
  end

  defp cron__738(rest, user_acc, [acc | stack], context, line, offset) do
    _ = user_acc

    cron__739(
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

  defp cron__739(rest, user_acc, [acc | stack], context, line, offset) do
    _ = user_acc
    cron__740(rest, [range: :lists.reverse(user_acc)] ++ acc, stack, context, line, offset)
  end

  defp cron__740(rest, acc, [_, previous_acc | stack], context, line, offset) do
    cron__705(rest, acc ++ previous_acc, stack, context, line, offset)
  end

  defp cron__741(_, _, [{rest, context, line, offset} | _] = stack, _, _, _) do
    cron__723(rest, [], stack, context, line, offset)
  end

  defp cron__742(rest, acc, stack, context, line, offset) do
    cron__743(rest, [], [acc | stack], context, line, offset)
  end

  defp cron__743(rest, acc, stack, context, line, offset) do
    cron__764(rest, [], [{rest, context, line, offset}, acc | stack], context, line, offset)
  end

  defp cron__745(rest, acc, stack, context, line, offset) do
    cron__746(rest, [], [acc | stack], context, line, offset)
  end

  defp cron__746(rest, acc, stack, context, line, offset) do
    cron__747(rest, [], [acc | stack], context, line, offset)
  end

  defp cron__747(<<x0::integer, rest::binary>>, acc, stack, context, comb__line, comb__offset)
       when x0 >= 48 and x0 <= 57 do
    cron__748(rest, [x0 - 48] ++ acc, stack, context, comb__line, comb__offset + 1)
  end

  defp cron__747(rest, _acc, stack, context, line, offset) do
    [_, _, _, _, acc | stack] = stack
    cron__741(rest, acc, stack, context, line, offset)
  end

  defp cron__748(rest, acc, stack, context, line, offset) do
    cron__750(rest, acc, [1 | stack], context, line, offset)
  end

  defp cron__750(<<x0::integer, rest::binary>>, acc, stack, context, comb__line, comb__offset)
       when x0 >= 48 and x0 <= 57 do
    cron__751(rest, [x0] ++ acc, stack, context, comb__line, comb__offset + 1)
  end

  defp cron__750(rest, acc, stack, context, line, offset) do
    cron__749(rest, acc, stack, context, line, offset)
  end

  defp cron__749(rest, acc, [_ | stack], context, line, offset) do
    cron__752(rest, acc, stack, context, line, offset)
  end

  defp cron__751(rest, acc, [1 | stack], context, line, offset) do
    cron__752(rest, acc, stack, context, line, offset)
  end

  defp cron__751(rest, acc, [count | stack], context, line, offset) do
    cron__750(rest, acc, [count - 1 | stack], context, line, offset)
  end

  defp cron__752(rest, user_acc, [acc | stack], context, line, offset) do
    _ = user_acc

    cron__753(
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

  defp cron__753(<<"-", rest::binary>>, acc, stack, context, comb__line, comb__offset) do
    cron__754(rest, [] ++ acc, stack, context, comb__line, comb__offset + 1)
  end

  defp cron__753(rest, _acc, stack, context, line, offset) do
    [_, _, _, acc | stack] = stack
    cron__741(rest, acc, stack, context, line, offset)
  end

  defp cron__754(rest, acc, stack, context, line, offset) do
    cron__755(rest, [], [acc | stack], context, line, offset)
  end

  defp cron__755(<<x0::integer, rest::binary>>, acc, stack, context, comb__line, comb__offset)
       when x0 >= 48 and x0 <= 57 do
    cron__756(rest, [x0 - 48] ++ acc, stack, context, comb__line, comb__offset + 1)
  end

  defp cron__755(rest, _acc, stack, context, line, offset) do
    [_, _, _, _, acc | stack] = stack
    cron__741(rest, acc, stack, context, line, offset)
  end

  defp cron__756(rest, acc, stack, context, line, offset) do
    cron__758(rest, acc, [1 | stack], context, line, offset)
  end

  defp cron__758(<<x0::integer, rest::binary>>, acc, stack, context, comb__line, comb__offset)
       when x0 >= 48 and x0 <= 57 do
    cron__759(rest, [x0] ++ acc, stack, context, comb__line, comb__offset + 1)
  end

  defp cron__758(rest, acc, stack, context, line, offset) do
    cron__757(rest, acc, stack, context, line, offset)
  end

  defp cron__757(rest, acc, [_ | stack], context, line, offset) do
    cron__760(rest, acc, stack, context, line, offset)
  end

  defp cron__759(rest, acc, [1 | stack], context, line, offset) do
    cron__760(rest, acc, stack, context, line, offset)
  end

  defp cron__759(rest, acc, [count | stack], context, line, offset) do
    cron__758(rest, acc, [count - 1 | stack], context, line, offset)
  end

  defp cron__760(rest, user_acc, [acc | stack], context, line, offset) do
    _ = user_acc

    cron__761(
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

  defp cron__761(rest, user_acc, [acc | stack], context, line, offset) do
    _ = user_acc
    cron__762(rest, [range: :lists.reverse(user_acc)] ++ acc, stack, context, line, offset)
  end

  defp cron__762(rest, acc, [_, previous_acc | stack], context, line, offset) do
    cron__744(rest, acc ++ previous_acc, stack, context, line, offset)
  end

  defp cron__763(_, _, [{rest, context, line, offset} | _] = stack, _, _, _) do
    cron__745(rest, [], stack, context, line, offset)
  end

  defp cron__764(<<"*", rest::binary>>, acc, stack, context, comb__line, comb__offset) do
    cron__765(rest, [wild: "*"] ++ acc, stack, context, comb__line, comb__offset + 1)
  end

  defp cron__764(rest, acc, stack, context, line, offset) do
    cron__763(rest, acc, stack, context, line, offset)
  end

  defp cron__765(rest, acc, [_, previous_acc | stack], context, line, offset) do
    cron__744(rest, acc ++ previous_acc, stack, context, line, offset)
  end

  defp cron__744(<<"/", rest::binary>>, acc, stack, context, comb__line, comb__offset) do
    cron__766(rest, [] ++ acc, stack, context, comb__line, comb__offset + 1)
  end

  defp cron__744(rest, _acc, stack, context, line, offset) do
    [acc | stack] = stack
    cron__741(rest, acc, stack, context, line, offset)
  end

  defp cron__766(rest, acc, stack, context, line, offset) do
    cron__767(rest, [], [acc | stack], context, line, offset)
  end

  defp cron__767(<<x0::integer, rest::binary>>, acc, stack, context, comb__line, comb__offset)
       when x0 >= 48 and x0 <= 57 do
    cron__768(rest, [x0 - 48] ++ acc, stack, context, comb__line, comb__offset + 1)
  end

  defp cron__767(rest, _acc, stack, context, line, offset) do
    [_, acc | stack] = stack
    cron__741(rest, acc, stack, context, line, offset)
  end

  defp cron__768(rest, acc, stack, context, line, offset) do
    cron__770(rest, acc, [1 | stack], context, line, offset)
  end

  defp cron__770(<<x0::integer, rest::binary>>, acc, stack, context, comb__line, comb__offset)
       when x0 >= 48 and x0 <= 57 do
    cron__771(rest, [x0] ++ acc, stack, context, comb__line, comb__offset + 1)
  end

  defp cron__770(rest, acc, stack, context, line, offset) do
    cron__769(rest, acc, stack, context, line, offset)
  end

  defp cron__769(rest, acc, [_ | stack], context, line, offset) do
    cron__772(rest, acc, stack, context, line, offset)
  end

  defp cron__771(rest, acc, [1 | stack], context, line, offset) do
    cron__772(rest, acc, stack, context, line, offset)
  end

  defp cron__771(rest, acc, [count | stack], context, line, offset) do
    cron__770(rest, acc, [count - 1 | stack], context, line, offset)
  end

  defp cron__772(rest, user_acc, [acc | stack], context, line, offset) do
    _ = user_acc

    cron__773(
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

  defp cron__773(rest, user_acc, [acc | stack], context, line, offset) do
    _ = user_acc
    cron__774(rest, [step: :lists.reverse(user_acc)] ++ acc, stack, context, line, offset)
  end

  defp cron__774(rest, acc, [_, previous_acc | stack], context, line, offset) do
    cron__705(rest, acc ++ previous_acc, stack, context, line, offset)
  end

  defp cron__705(rest, acc, [_, previous_acc | stack], context, line, offset) do
    cron__703(rest, acc ++ previous_acc, stack, context, line, offset)
  end

  defp cron__775(_, _, [{rest, context, line, offset} | _] = stack, _, _, _) do
    cron__704(rest, [], stack, context, line, offset)
  end

  defp cron__776(rest, acc, stack, context, line, offset) do
    cron__777(rest, [], [acc | stack], context, line, offset)
  end

  defp cron__777(<<"MON", rest::binary>>, acc, stack, context, comb__line, comb__offset) do
    cron__778(rest, [1] ++ acc, stack, context, comb__line, comb__offset + 3)
  end

  defp cron__777(<<"TUE", rest::binary>>, acc, stack, context, comb__line, comb__offset) do
    cron__778(rest, [2] ++ acc, stack, context, comb__line, comb__offset + 3)
  end

  defp cron__777(<<"WED", rest::binary>>, acc, stack, context, comb__line, comb__offset) do
    cron__778(rest, [3] ++ acc, stack, context, comb__line, comb__offset + 3)
  end

  defp cron__777(<<"THU", rest::binary>>, acc, stack, context, comb__line, comb__offset) do
    cron__778(rest, [4] ++ acc, stack, context, comb__line, comb__offset + 3)
  end

  defp cron__777(<<"FRI", rest::binary>>, acc, stack, context, comb__line, comb__offset) do
    cron__778(rest, [5] ++ acc, stack, context, comb__line, comb__offset + 3)
  end

  defp cron__777(<<"SAT", rest::binary>>, acc, stack, context, comb__line, comb__offset) do
    cron__778(rest, [6] ++ acc, stack, context, comb__line, comb__offset + 3)
  end

  defp cron__777(<<"SUN", rest::binary>>, acc, stack, context, comb__line, comb__offset) do
    cron__778(rest, [0] ++ acc, stack, context, comb__line, comb__offset + 3)
  end

  defp cron__777(rest, _acc, stack, context, line, offset) do
    [acc | stack] = stack
    cron__775(rest, acc, stack, context, line, offset)
  end

  defp cron__778(rest, user_acc, [acc | stack], context, line, offset) do
    _ = user_acc

    cron__779(
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

  defp cron__779(rest, acc, [_, previous_acc | stack], context, line, offset) do
    cron__703(rest, acc ++ previous_acc, stack, context, line, offset)
  end

  defp cron__701(_, _, [{rest, acc, context, line, offset} | stack], _, _, _) do
    cron__780(rest, acc, stack, context, line, offset)
  end

  defp cron__703(
         inner_rest,
         inner_acc,
         [{rest, acc, context, line, offset} | stack],
         inner_context,
         inner_line,
         inner_offset
       ) do
    _ = {rest, acc, context, line, offset}

    cron__702(
      inner_rest,
      [],
      [{inner_rest, inner_acc ++ acc, inner_context, inner_line, inner_offset} | stack],
      inner_context,
      inner_line,
      inner_offset
    )
  end

  defp cron__780(rest, user_acc, [acc | stack], context, line, offset) do
    _ = user_acc
    cron__781(rest, [weekdays: :lists.reverse(user_acc)] ++ acc, stack, context, line, offset)
  end

  defp cron__781(rest, acc, _stack, context, line, offset) do
    {:ok, acc, rest, context, line, offset}
  end
end
