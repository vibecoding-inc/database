defmodule PostgresDb.SqlParser do
  @moduledoc """
  SQL Parser for PostgreSQL-compatible statements.
  Parses SQL statements into structured AST representations.
  """

  @type parsed_statement ::
          {:select, map()}
          | {:insert, map()}
          | {:update, map()}
          | {:delete, map()}
          | {:create_table, map()}
          | {:drop_table, map()}
          | {:alter_table, map()}
          | {:error, String.t()}

  @doc """
  Parses an SQL statement string into a structured representation.
  """
  @spec parse(String.t()) :: parsed_statement()
  def parse(sql) when is_binary(sql) do
    sql
    |> String.trim()
    |> String.trim_trailing(";")
    |> String.trim()
    |> tokenize()
    |> parse_tokens()
  end

  @doc """
  Tokenizes SQL string into a list of tokens.
  """
  @spec tokenize(String.t()) :: [String.t()]
  def tokenize(sql) do
    sql
    |> handle_dollar_quotes()
    |> handle_string_literals()
    |> String.replace(~r/\s+/, " ")
    |> String.replace(~r/\(\s*/, " ( ")
    |> String.replace(~r/\s*\)/, " ) ")
    |> String.replace(",", " , ")
    |> String.replace("::", " :: ")
    |> String.replace(">=", " >= ")
    |> String.replace("<=", " <= ")
    |> String.replace("<>", " <> ")
    |> String.replace("!=", " != ")
    |> String.replace(~r/(?<![<>])=(?![<>])/, " = ")
    |> String.replace(~r/(?<![<>=])>(?!=)/, " > ")
    |> String.replace(~r/(?<![<>=])<(?![>=])/, " < ")
    |> String.replace("*", " * ")
    |> String.replace("+", " + ")
    |> String.replace("-", " - ")
    |> String.replace("/", " / ")
    |> String.split()
    |> Enum.map(&restore_string_literal/1)
  end

  # Handle PostgreSQL dollar-quoted strings (e.g., $$text$$ or $tag$text$tag$)
  defp handle_dollar_quotes(sql) do
    Regex.replace(~r/\$([a-zA-Z_]*)\$(.*?)\$\1\$/s, sql, fn _, tag, content ->
      hex = Base.encode16("$#{tag}$#{content}$#{tag}$", case: :lower)
      "~DOLLARQ~#{hex}~DOLLARQ~"
    end)
  end

  # Handle string literals by replacing spaces with placeholder using hex encoding
  defp handle_string_literals(sql) do
    Regex.replace(~r/'([^']*)'/, sql, fn _, content ->
      hex = Base.encode16(content, case: :lower)
      "~STRLIT~#{hex}~STRLIT~"
    end)
  end

  defp restore_string_literal(token) do
    cond do
      String.contains?(token, "~STRLIT~") ->
        case Regex.run(~r/~STRLIT~([0-9a-f]*)~STRLIT~/i, token) do
          [_, hex] ->
            {:ok, decoded} = Base.decode16(hex, case: :mixed)
            {:string, decoded}

          nil ->
            token
        end

      String.contains?(token, "~DOLLARQ~") ->
        case Regex.run(~r/~DOLLARQ~([0-9a-f]*)~DOLLARQ~/i, token) do
          [_, hex] ->
            {:ok, decoded} = Base.decode16(hex, case: :mixed)
            {:string, decoded}

          nil ->
            token
        end

      true ->
        token
    end
  end

  defp parse_tokens([]) do
    {:error, "Empty SQL statement"}
  end

  defp parse_tokens(tokens) do
    case String.upcase(hd(tokens)) do
      "SELECT" -> parse_select(tokens)
      "INSERT" -> parse_insert(tokens)
      "UPDATE" -> parse_update(tokens)
      "DELETE" -> parse_delete(tokens)
      "CREATE" -> parse_create(tokens)
      "DROP" -> parse_drop(tokens)
      "ALTER" -> parse_alter(tokens)
      _ -> {:error, "Unknown SQL command: #{hd(tokens)}"}
    end
  end

  # Parse SELECT statement
  defp parse_select(tokens) do
    # Remove SELECT keyword
    tokens = tl(tokens)

    # Check for DISTINCT
    {distinct, tokens} =
      case tokens do
        [d | rest] when is_binary(d) ->
          if String.upcase(d) == "DISTINCT" do
            {true, rest}
          else
            {false, [d | rest]}
          end

        _ ->
          {false, tokens}
      end

    # Parse columns
    {columns, rest} = parse_columns(tokens)

    # Parse FROM clause
    {table, rest} = parse_from(rest)

    # Parse WHERE clause (optional)
    {where, rest} = parse_where(rest)

    # Parse GROUP BY clause (optional)
    {group_by, rest} = parse_group_by(rest)

    # Parse HAVING clause (optional)
    {having, rest} = parse_having(rest)

    # Parse ORDER BY clause (optional)
    {order_by, rest} = parse_order_by(rest)

    # Parse LIMIT/OFFSET (PostgreSQL style)
    {limit, rest} = parse_limit(rest)
    {offset, _rest} = parse_offset(rest)

    {:select,
     %{
       distinct: distinct,
       columns: columns,
       table: table,
       where: where,
       group_by: group_by,
       having: having,
       order_by: order_by,
       limit: limit,
       offset: offset
     }}
  end

  defp parse_columns(tokens) do
    parse_columns(tokens, [])
  end

  defp parse_columns(["*" | rest], acc) do
    {Enum.reverse([{:all, "*"} | acc]), rest}
  end

  defp parse_columns([token | rest], acc) when is_binary(token) do
    case String.upcase(token) do
      "FROM" ->
        {Enum.reverse(acc), [token | rest]}

      "," ->
        parse_columns(rest, acc)

      _ ->
        # Check for function or alias
        {col, remaining} = parse_column_expr([token | rest])
        parse_columns(remaining, [col | acc])
    end
  end

  defp parse_columns([{:string, _} = token | rest], acc) do
    {col, remaining} = parse_column_expr([token | rest])
    parse_columns(remaining, [col | acc])
  end

  defp parse_columns([], acc) do
    {Enum.reverse(acc), []}
  end

  defp parse_column_expr([token | rest]) do
    cond do
      is_function?(token) ->
        {args, remaining} = parse_function_args(rest)
        # Check for alias
        {alias_name, final_rest} = check_for_alias(remaining)
        {{:function, String.upcase(token), args, alias_name}, final_rest}

      true ->
        # Check for type cast (::)
        {typed_token, remaining} = check_for_type_cast([token | rest])
        # Check for alias
        {alias_name, final_rest} = check_for_alias(remaining)
        {{:column, normalize_token(typed_token), alias_name}, final_rest}
    end
  end

  defp check_for_type_cast([token, "::", type | rest]) do
    {{:cast, token, type}, rest}
  end

  defp check_for_type_cast([token | rest]) do
    {token, rest}
  end

  defp is_function?(token) when is_binary(token) do
    String.upcase(token) in [
      "COUNT",
      "SUM",
      "AVG",
      "MAX",
      "MIN",
      "COALESCE",
      "NULLIF",
      "GREATEST",
      "LEAST",
      "UPPER",
      "LOWER",
      "SUBSTR",
      "SUBSTRING",
      "LENGTH",
      "CHAR_LENGTH",
      "TRIM",
      "LTRIM",
      "RTRIM",
      "BTRIM",
      "ROUND",
      "TRUNC",
      "FLOOR",
      "CEIL",
      "CEILING",
      "ABS",
      "MOD",
      "POWER",
      "SQRT",
      "NOW",
      "CURRENT_DATE",
      "CURRENT_TIME",
      "CURRENT_TIMESTAMP",
      "EXTRACT",
      "DATE_PART",
      "TO_CHAR",
      "TO_DATE",
      "TO_NUMBER",
      "TO_TIMESTAMP",
      "CONCAT",
      "CONCAT_WS",
      "STRING_AGG",
      "ARRAY_AGG",
      "JSON_AGG",
      "JSONB_AGG",
      "ROW_NUMBER",
      "RANK",
      "DENSE_RANK",
      "LAG",
      "LEAD",
      "FIRST_VALUE",
      "LAST_VALUE",
      "INITCAP",
      "LEFT",
      "RIGHT",
      "LPAD",
      "RPAD",
      "REPLACE",
      "POSITION",
      "SPLIT_PART",
      "REGEXP_REPLACE",
      "REGEXP_MATCH"
    ]
  end

  defp is_function?(_), do: false

  defp parse_function_args(["(" | rest]) do
    parse_function_args(rest, [], 0)
  end

  defp parse_function_args(rest), do: {[], rest}

  defp parse_function_args([")" | rest], acc, 0) do
    {Enum.reverse(acc), rest}
  end

  defp parse_function_args(["(" | rest], acc, depth) do
    parse_function_args(rest, ["(" | acc], depth + 1)
  end

  defp parse_function_args([")" | rest], acc, depth) do
    parse_function_args(rest, [")" | acc], depth - 1)
  end

  defp parse_function_args(["," | rest], acc, depth) when depth == 0 do
    parse_function_args(rest, acc, depth)
  end

  defp parse_function_args([token | rest], acc, depth) do
    parse_function_args(rest, [token | acc], depth)
  end

  defp parse_function_args([], acc, _) do
    {Enum.reverse(acc), []}
  end

  defp check_for_alias([token | rest]) when is_binary(token) do
    case String.upcase(token) do
      "AS" ->
        [alias_name | remaining] = rest
        {normalize_token(alias_name), remaining}

      kw when kw in ["FROM", "WHERE", "ORDER", "GROUP", "HAVING", "LIMIT", "OFFSET", ",", ")"] ->
        {nil, [token | rest]}

      _ ->
        # Could be implicit alias
        if is_identifier?(token) do
          {normalize_token(token), rest}
        else
          {nil, [token | rest]}
        end
    end
  end

  defp check_for_alias(rest), do: {nil, rest}

  defp is_identifier?(token) when is_binary(token) do
    String.upcase(token) not in [
      "FROM",
      "WHERE",
      "AND",
      "OR",
      "ORDER",
      "BY",
      "GROUP",
      "HAVING",
      "LIMIT",
      "OFFSET",
      ",",
      "(",
      ")",
      "AS"
    ]
  end

  defp is_identifier?(_), do: false

  defp normalize_token({:string, val}), do: val
  defp normalize_token({:cast, val, _type}), do: val
  defp normalize_token(token) when is_binary(token), do: token

  defp parse_from(tokens) do
    case find_keyword(tokens, "FROM") do
      nil ->
        {nil, tokens}

      {_before, rest} ->
        case rest do
          [table | remaining] ->
            {normalize_token(table), remaining}

          [] ->
            {nil, []}
        end
    end
  end

  defp parse_where(tokens) do
    case find_keyword(tokens, "WHERE") do
      nil ->
        {nil, tokens}

      {_before, rest} ->
        {conditions, remaining} = parse_conditions(rest)
        {conditions, remaining}
    end
  end

  defp parse_conditions(tokens) do
    parse_conditions(tokens, [])
  end

  defp parse_conditions([], acc) do
    {build_condition_tree(Enum.reverse(acc)), []}
  end

  defp parse_conditions([token | rest], acc) when is_binary(token) do
    case String.upcase(token) do
      kw when kw in ["ORDER", "GROUP", "HAVING", "LIMIT", "OFFSET", "RETURNING"] ->
        {build_condition_tree(Enum.reverse(acc)), [token | rest]}

      "AND" ->
        parse_conditions(rest, [:and | acc])

      "OR" ->
        parse_conditions(rest, [:or | acc])

      "NOT" ->
        parse_conditions(rest, [:not | acc])

      "(" ->
        {nested, remaining} = parse_nested_conditions(rest)
        parse_conditions(remaining, [{:nested, nested} | acc])

      "IS" ->
        # Handle IS NULL / IS NOT NULL / IS TRUE / IS FALSE
        {is_cond, remaining} = parse_is_condition(rest, acc)
        parse_conditions(remaining, is_cond)

      "IN" ->
        # Handle IN clause
        {in_cond, remaining} = parse_in_condition(rest, acc)
        parse_conditions(remaining, in_cond)

      "BETWEEN" ->
        {between_cond, remaining} = parse_between_condition(rest, acc)
        parse_conditions(remaining, between_cond)

      "LIKE" ->
        {like_cond, remaining} = parse_like_condition(rest, acc)
        parse_conditions(remaining, like_cond)

      "ILIKE" ->
        # PostgreSQL case-insensitive LIKE
        {like_cond, remaining} = parse_ilike_condition(rest, acc)
        parse_conditions(remaining, like_cond)

      "SIMILAR" ->
        {similar_cond, remaining} = parse_similar_condition(rest, acc)
        parse_conditions(remaining, similar_cond)

      op when op in ["=", "<>", "!=", ">", "<", ">=", "<="] ->
        {comp, remaining} = parse_comparison(rest, acc, op)
        parse_conditions(remaining, comp)

      _ ->
        # Regular token (column name or value)
        parse_conditions(rest, [token | acc])
    end
  end

  defp parse_conditions([token | rest], acc) do
    parse_conditions(rest, [token | acc])
  end

  defp parse_nested_conditions(tokens) do
    parse_nested_conditions(tokens, [], 1)
  end

  defp parse_nested_conditions(["(" | rest], acc, depth) do
    parse_nested_conditions(rest, ["(" | acc], depth + 1)
  end

  defp parse_nested_conditions([")" | rest], acc, 1) do
    {conditions, _} = parse_conditions(Enum.reverse(acc))
    {conditions, rest}
  end

  defp parse_nested_conditions([")" | rest], acc, depth) do
    parse_nested_conditions(rest, [")" | acc], depth - 1)
  end

  defp parse_nested_conditions([token | rest], acc, depth) do
    parse_nested_conditions(rest, [token | acc], depth)
  end

  defp parse_nested_conditions([], acc, _) do
    {conditions, _} = parse_conditions(Enum.reverse(acc))
    {conditions, []}
  end

  defp parse_is_condition(["NOT", "NULL" | rest], [col | acc]) do
    {[{:is_not_null, col} | acc], rest}
  end

  defp parse_is_condition(["NULL" | rest], [col | acc]) do
    {[{:is_null, col} | acc], rest}
  end

  defp parse_is_condition(["TRUE" | rest], [col | acc]) do
    {[{:is_true, col} | acc], rest}
  end

  defp parse_is_condition(["FALSE" | rest], [col | acc]) do
    {[{:is_false, col} | acc], rest}
  end

  defp parse_is_condition(["NOT", "TRUE" | rest], [col | acc]) do
    {[{:is_not_true, col} | acc], rest}
  end

  defp parse_is_condition(["NOT", "FALSE" | rest], [col | acc]) do
    {[{:is_not_false, col} | acc], rest}
  end

  defp parse_is_condition(rest, acc), do: {acc, rest}

  defp parse_in_condition(["(" | rest], [col | acc]) do
    {values, remaining} = parse_in_values(rest)
    {[{:in, col, values} | acc], remaining}
  end

  defp parse_in_condition(rest, acc), do: {acc, rest}

  defp parse_in_values(tokens) do
    parse_in_values(tokens, [])
  end

  defp parse_in_values([")" | rest], acc) do
    {Enum.reverse(acc), rest}
  end

  defp parse_in_values(["," | rest], acc) do
    parse_in_values(rest, acc)
  end

  defp parse_in_values([{:string, val} | rest], acc) do
    parse_in_values(rest, [val | acc])
  end

  defp parse_in_values([token | rest], acc) do
    parse_in_values(rest, [parse_value(token) | acc])
  end

  defp parse_in_values([], acc), do: {Enum.reverse(acc), []}

  defp parse_between_condition([val1, "AND", val2 | rest], [col | acc]) do
    {[{:between, col, parse_value(val1), parse_value(val2)} | acc], rest}
  end

  defp parse_between_condition(rest, acc), do: {acc, rest}

  defp parse_like_condition([pattern | rest], [col | acc]) do
    {[{:like, col, normalize_token(pattern)} | acc], rest}
  end

  defp parse_like_condition(rest, acc), do: {acc, rest}

  defp parse_ilike_condition([pattern | rest], [col | acc]) do
    {[{:ilike, col, normalize_token(pattern)} | acc], rest}
  end

  defp parse_ilike_condition(rest, acc), do: {acc, rest}

  defp parse_similar_condition(["TO", pattern | rest], [col | acc]) do
    {[{:similar_to, col, normalize_token(pattern)} | acc], rest}
  end

  defp parse_similar_condition(rest, acc), do: {acc, rest}

  defp parse_comparison([value | rest], [col | acc], op) do
    {[{:comparison, col, op, parse_value(value)} | acc], rest}
  end

  defp parse_comparison(rest, acc, _op), do: {acc, rest}

  defp parse_value({:string, val}), do: val

  defp parse_value(token) when is_binary(token) do
    cond do
      String.upcase(token) == "NULL" -> nil
      String.upcase(token) == "TRUE" -> true
      String.upcase(token) == "FALSE" -> false
      String.match?(token, ~r/^\d+$/) -> String.to_integer(token)
      String.match?(token, ~r/^\d+\.\d+$/) -> String.to_float(token)
      true -> token
    end
  end

  defp parse_value(val), do: val

  defp build_condition_tree([]), do: nil
  defp build_condition_tree([single]), do: normalize_condition(single)

  defp build_condition_tree(tokens) do
    # Handle OR first (lower precedence)
    case split_on(tokens, :or) do
      {left, right} when left != [] and right != [] ->
        {:or, build_condition_tree(left), build_condition_tree(right)}

      _ ->
        # Then handle AND
        case split_on(tokens, :and) do
          {left, right} when left != [] and right != [] ->
            {:and, build_condition_tree(left), build_condition_tree(right)}

          _ ->
            # Handle NOT
            case tokens do
              [:not | rest] -> {:not, build_condition_tree(rest)}
              [single] -> normalize_condition(single)
              _ -> {:raw, tokens}
            end
        end
    end
  end

  defp normalize_condition({:nested, cond}), do: cond
  defp normalize_condition(cond), do: cond

  defp split_on(tokens, delimiter) do
    case Enum.find_index(tokens, &(&1 == delimiter)) do
      nil -> {tokens, []}
      idx -> {Enum.take(tokens, idx), Enum.drop(tokens, idx + 1)}
    end
  end

  defp parse_group_by(tokens) do
    case find_keyword(tokens, "GROUP") do
      nil ->
        {nil, tokens}

      {_before, ["BY" | rest]} ->
        {columns, remaining} = parse_group_columns(rest)
        {columns, remaining}

      {_before, rest} ->
        {nil, rest}
    end
  end

  defp parse_group_columns(tokens) do
    parse_group_columns(tokens, [])
  end

  defp parse_group_columns([], acc), do: {Enum.reverse(acc), []}

  defp parse_group_columns([col | rest], acc) do
    case String.upcase(col) do
      kw when kw in ["HAVING", "ORDER", "LIMIT", "OFFSET"] ->
        {Enum.reverse(acc), [col | rest]}

      "," ->
        parse_group_columns(rest, acc)

      _ ->
        parse_group_columns(rest, [col | acc])
    end
  end

  defp parse_having(tokens) do
    case find_keyword(tokens, "HAVING") do
      nil ->
        {nil, tokens}

      {_before, rest} ->
        {conditions, remaining} = parse_conditions(rest)
        {conditions, remaining}
    end
  end

  defp parse_order_by(tokens) do
    case find_keyword(tokens, "ORDER") do
      nil ->
        {nil, tokens}

      {_before, ["BY" | rest]} ->
        {orders, remaining} = parse_order_columns(rest)
        {orders, remaining}

      {_before, rest} ->
        {nil, rest}
    end
  end

  defp parse_order_columns(tokens) do
    parse_order_columns(tokens, [])
  end

  defp parse_order_columns([], acc), do: {Enum.reverse(acc), []}

  defp parse_order_columns([col | rest], acc) do
    case String.upcase(col) do
      kw when kw in ["LIMIT", "OFFSET", "RETURNING"] ->
        {Enum.reverse(acc), [col | rest]}

      "," ->
        parse_order_columns(rest, acc)

      _ ->
        {dir, nulls, remaining} = parse_order_modifiers(rest)
        parse_order_columns(remaining, [{col, dir, nulls} | acc])
    end
  end

  defp parse_order_modifiers(rest) do
    {dir, rest} =
      case rest do
        [d | r] when is_binary(d) ->
          case String.upcase(d) do
            "ASC" -> {:asc, r}
            "DESC" -> {:desc, r}
            _ -> {:asc, [d | r]}
          end

        _ ->
          {:asc, rest}
      end

    # Check for NULLS FIRST/LAST
    {nulls, remaining} =
      case rest do
        ["NULLS", pos | r] when is_binary(pos) ->
          case String.upcase(pos) do
            "FIRST" -> {:nulls_first, r}
            "LAST" -> {:nulls_last, r}
            _ -> {nil, [pos | r]}
          end

        _ ->
          {nil, rest}
      end

    {dir, nulls, remaining}
  end

  defp parse_limit(tokens) do
    case find_keyword(tokens, "LIMIT") do
      nil ->
        {nil, tokens}

      {_before, [value | rest]} ->
        case String.upcase(value) do
          "ALL" -> {:all, rest}
          _ -> {parse_value(value), rest}
        end
    end
  end

  defp parse_offset(tokens) do
    case find_keyword(tokens, "OFFSET") do
      nil ->
        {nil, tokens}

      {_before, [value | rest]} ->
        {parse_value(value), rest}
    end
  end

  # Parse INSERT statement
  defp parse_insert(tokens) do
    # Remove INSERT
    tokens = tl(tokens)

    case tokens do
      ["INTO" | rest] -> parse_insert_into(rest)
      _ -> {:error, "Invalid INSERT syntax, expected INTO"}
    end
  end

  defp parse_insert_into([table | rest]) do
    {columns, rest} = parse_insert_columns(rest)
    {values, rest} = parse_insert_values(rest)
    {returning, _rest} = parse_returning(rest)

    {:insert,
     %{
       table: table,
       columns: columns,
       values: values,
       returning: returning
     }}
  end

  defp parse_insert_columns(["(" | rest]) do
    parse_insert_columns(rest, [])
  end

  defp parse_insert_columns(rest) do
    {nil, rest}
  end

  defp parse_insert_columns([")" | rest], acc) do
    {Enum.reverse(acc), rest}
  end

  defp parse_insert_columns(["," | rest], acc) do
    parse_insert_columns(rest, acc)
  end

  defp parse_insert_columns([col | rest], acc) do
    parse_insert_columns(rest, [col | acc])
  end

  defp parse_insert_values(tokens) do
    case find_keyword(tokens, "VALUES") do
      nil ->
        # Check for DEFAULT VALUES
        case find_keyword(tokens, "DEFAULT") do
          {_before, ["VALUES" | rest]} -> {:default, rest}
          _ -> {[], tokens}
        end

      {_before, rest} ->
        parse_values_list(rest)
    end
  end

  defp parse_values_list(["(" | rest]) do
    parse_values_list(rest, [[]], 0)
  end

  defp parse_values_list(rest), do: {[], rest}

  defp parse_values_list([")" | rest], [current | acc], 0) do
    values = Enum.reverse(current)
    all_values = Enum.reverse([values | acc])
    # Check for more value sets
    case rest do
      ["," | ["(" | more]] ->
        parse_values_list(more, [[] | all_values], 0)

      _ ->
        {all_values, rest}
    end
  end

  defp parse_values_list(["(" | rest], acc, depth) do
    parse_values_list(rest, acc, depth + 1)
  end

  defp parse_values_list([")" | rest], acc, depth) do
    parse_values_list(rest, acc, depth - 1)
  end

  defp parse_values_list(["," | rest], acc, depth) when depth == 0 do
    parse_values_list(rest, acc, depth)
  end

  defp parse_values_list([token | rest], [current | acc], depth) do
    value = parse_value(token)
    parse_values_list(rest, [[value | current] | acc], depth)
  end

  defp parse_values_list([], [current | acc], _) do
    values = Enum.reverse(current)
    {Enum.reverse([values | acc]), []}
  end

  defp parse_returning(tokens) do
    case find_keyword(tokens, "RETURNING") do
      nil ->
        {nil, tokens}

      {_before, rest} ->
        {columns, remaining} = parse_returning_columns(rest)
        {columns, remaining}
    end
  end

  defp parse_returning_columns(tokens) do
    parse_returning_columns(tokens, [])
  end

  defp parse_returning_columns([], acc), do: {Enum.reverse(acc), []}

  defp parse_returning_columns(["*" | rest], _acc) do
    {[:all], rest}
  end

  defp parse_returning_columns([col | rest], acc) do
    case String.upcase(col) do
      "," -> parse_returning_columns(rest, acc)
      _ -> parse_returning_columns(rest, [col | acc])
    end
  end

  # Parse UPDATE statement
  defp parse_update(tokens) do
    # Remove UPDATE
    tokens = tl(tokens)

    case tokens do
      [table | rest] ->
        {sets, rest} = parse_set_clause(rest)
        {where, rest} = parse_where(rest)
        {returning, _rest} = parse_returning(rest)

        {:update,
         %{
           table: table,
           sets: sets,
           where: where,
           returning: returning
         }}

      _ ->
        {:error, "Invalid UPDATE syntax"}
    end
  end

  defp parse_set_clause(tokens) do
    case find_keyword(tokens, "SET") do
      nil -> {[], tokens}
      {_before, rest} -> parse_set_pairs(rest)
    end
  end

  defp parse_set_pairs(tokens) do
    parse_set_pairs(tokens, [])
  end

  defp parse_set_pairs([], acc), do: {Enum.reverse(acc), []}

  defp parse_set_pairs([col, "=", value | rest], acc) do
    pair = {col, parse_value(value)}

    case rest do
      ["," | more] ->
        parse_set_pairs(more, [pair | acc])

      [kw | _] when is_binary(kw) ->
        if String.upcase(kw) in ["WHERE", "RETURNING"] do
          {Enum.reverse([pair | acc]), rest}
        else
          parse_set_pairs(rest, [pair | acc])
        end

      _ ->
        {Enum.reverse([pair | acc]), rest}
    end
  end

  defp parse_set_pairs(rest, acc), do: {Enum.reverse(acc), rest}

  # Parse DELETE statement
  defp parse_delete(tokens) do
    # Remove DELETE
    tokens = tl(tokens)

    case tokens do
      ["FROM", table | rest] ->
        {where, rest} = parse_where(rest)
        {returning, _rest} = parse_returning(rest)
        {:delete, %{table: table, where: where, returning: returning}}

      [table | rest] ->
        {where, rest} = parse_where(rest)
        {returning, _rest} = parse_returning(rest)
        {:delete, %{table: table, where: where, returning: returning}}

      _ ->
        {:error, "Invalid DELETE syntax"}
    end
  end

  # Parse CREATE statement
  defp parse_create(tokens) do
    case tl(tokens) do
      ["TABLE", "IF", "NOT", "EXISTS" | rest] -> parse_create_table(rest, true)
      ["TABLE" | rest] -> parse_create_table(rest, false)
      ["UNIQUE", "INDEX" | rest] -> parse_create_index(rest, true)
      ["INDEX" | rest] -> parse_create_index(rest)
      ["SEQUENCE" | rest] -> parse_create_sequence(rest)
      ["TYPE" | rest] -> parse_create_type(rest)
      _ -> {:error, "Unknown CREATE command"}
    end
  end

  defp parse_create_table([table, "(" | rest], if_not_exists) do
    {columns, constraints} = parse_column_definitions(rest)

    {:create_table,
     %{table: table, columns: columns, constraints: constraints, if_not_exists: if_not_exists}}
  end

  defp parse_create_table([table | rest], if_not_exists) do
    # CREATE TABLE AS SELECT ...
    case rest do
      ["AS" | select_rest] ->
        case parse_select(["SELECT" | select_rest]) do
          {:select, select_info} ->
            {:create_table, %{table: table, as_select: select_info, if_not_exists: if_not_exists}}

          error ->
            error
        end

      _ ->
        {:error, "Invalid CREATE TABLE syntax"}
    end
  end

  defp parse_column_definitions(tokens) do
    parse_column_definitions(tokens, [], [])
  end

  defp parse_column_definitions([")" | _], cols, constraints) do
    {Enum.reverse(cols), Enum.reverse(constraints)}
  end

  defp parse_column_definitions([], cols, constraints) do
    {Enum.reverse(cols), Enum.reverse(constraints)}
  end

  defp parse_column_definitions(["," | rest], cols, constraints) do
    parse_column_definitions(rest, cols, constraints)
  end

  defp parse_column_definitions([token | rest], cols, constraints) when is_binary(token) do
    case String.upcase(token) do
      "PRIMARY" ->
        {constraint, remaining} = parse_primary_key_constraint(rest)
        parse_column_definitions(remaining, cols, [constraint | constraints])

      "FOREIGN" ->
        {constraint, remaining} = parse_foreign_key_constraint(rest)
        parse_column_definitions(remaining, cols, [constraint | constraints])

      "UNIQUE" ->
        {constraint, remaining} = parse_unique_constraint(rest)
        parse_column_definitions(remaining, cols, [constraint | constraints])

      "CHECK" ->
        {constraint, remaining} = parse_check_constraint(rest)
        parse_column_definitions(remaining, cols, [constraint | constraints])

      "CONSTRAINT" ->
        {constraint, remaining} = parse_named_constraint(rest)
        parse_column_definitions(remaining, cols, [constraint | constraints])

      _ ->
        {col_def, remaining} = parse_column_def([token | rest])
        parse_column_definitions(remaining, [col_def | cols], constraints)
    end
  end

  defp parse_column_def([name, type | rest]) do
    {modifiers, remaining} = parse_column_modifiers(rest)
    {{name, parse_column_type(type), modifiers}, remaining}
  end

  defp parse_column_type(type) when is_binary(type) do
    case String.upcase(type) do
      "VARCHAR" -> :varchar
      "CHARACTER" -> :varchar
      "TEXT" -> :text
      "INTEGER" -> :integer
      "INT" -> :integer
      "INT4" -> :integer
      "SMALLINT" -> :smallint
      "INT2" -> :smallint
      "BIGINT" -> :bigint
      "INT8" -> :bigint
      "SERIAL" -> :serial
      "SERIAL4" -> :serial
      "BIGSERIAL" -> :bigserial
      "SERIAL8" -> :bigserial
      "SMALLSERIAL" -> :smallserial
      "SERIAL2" -> :smallserial
      "NUMERIC" -> :numeric
      "DECIMAL" -> :decimal
      "REAL" -> :real
      "FLOAT4" -> :real
      "DOUBLE" -> :double
      "FLOAT8" -> :double
      "BOOLEAN" -> :boolean
      "BOOL" -> :boolean
      "DATE" -> :date
      "TIME" -> :time
      "TIMESTAMP" -> :timestamp
      "TIMESTAMPTZ" -> :timestamptz
      "INTERVAL" -> :interval
      "UUID" -> :uuid
      "JSON" -> :json
      "JSONB" -> :jsonb
      "BYTEA" -> :bytea
      "ARRAY" -> :array
      _ -> {:unknown, type}
    end
  end

  defp parse_column_modifiers(tokens) do
    parse_column_modifiers(tokens, [])
  end

  defp parse_column_modifiers([], acc), do: {Enum.reverse(acc), []}

  defp parse_column_modifiers(["(" | rest], acc) do
    {size, remaining} = parse_type_size(rest)
    parse_column_modifiers(remaining, [{:size, size} | acc])
  end

  defp parse_column_modifiers(["[", "]" | rest], acc) do
    # Array type
    parse_column_modifiers(rest, [:array | acc])
  end

  defp parse_column_modifiers([token | rest], acc) when is_binary(token) do
    case String.upcase(token) do
      "NOT" ->
        case rest do
          ["NULL" | remaining] ->
            parse_column_modifiers(remaining, [:not_null | acc])

          _ ->
            {Enum.reverse(acc), [token | rest]}
        end

      "NULL" ->
        parse_column_modifiers(rest, [:null | acc])

      "PRIMARY" ->
        case rest do
          ["KEY" | remaining] ->
            parse_column_modifiers(remaining, [:primary_key | acc])

          _ ->
            {Enum.reverse(acc), [token | rest]}
        end

      "UNIQUE" ->
        parse_column_modifiers(rest, [:unique | acc])

      "DEFAULT" ->
        [value | remaining] = rest
        parse_column_modifiers(remaining, [{:default, parse_value(value)} | acc])

      "REFERENCES" ->
        {ref, remaining} = parse_references(rest)
        parse_column_modifiers(remaining, [{:references, ref} | acc])

      "CHECK" ->
        {check, remaining} = parse_inline_check(rest)
        parse_column_modifiers(remaining, [{:check, check} | acc])

      "GENERATED" ->
        {gen, remaining} = parse_generated(rest)
        parse_column_modifiers(remaining, [{:generated, gen} | acc])

      "," ->
        {Enum.reverse(acc), rest}

      ")" ->
        {Enum.reverse(acc), [token | rest]}

      _ ->
        {Enum.reverse(acc), [token | rest]}
    end
  end

  defp parse_column_modifiers(tokens, acc), do: {Enum.reverse(acc), tokens}

  defp parse_generated(["ALWAYS", "AS", "IDENTITY" | rest]) do
    {:always_identity, rest}
  end

  defp parse_generated(["BY", "DEFAULT", "AS", "IDENTITY" | rest]) do
    {:by_default_identity, rest}
  end

  defp parse_generated(rest), do: {nil, rest}

  defp parse_type_size(tokens) do
    parse_type_size(tokens, [])
  end

  defp parse_type_size([")" | rest], acc) do
    size = acc |> Enum.reverse() |> Enum.join(",")
    {size, rest}
  end

  defp parse_type_size(["," | rest], acc) do
    parse_type_size(rest, acc)
  end

  defp parse_type_size([token | rest], acc) do
    parse_type_size(rest, [token | acc])
  end

  defp parse_type_size([], acc) do
    size = acc |> Enum.reverse() |> Enum.join(",")
    {size, []}
  end

  defp parse_references([table | rest]) do
    case rest do
      ["(" | more] ->
        {cols, remaining} = parse_paren_list(more)
        {{table, cols}, remaining}

      _ ->
        {{table, []}, rest}
    end
  end

  defp parse_inline_check(["(" | rest]) do
    {tokens, remaining} = parse_paren_list(rest)
    {tokens, remaining}
  end

  defp parse_inline_check(rest), do: {nil, rest}

  defp parse_paren_list(tokens) do
    parse_paren_list(tokens, [], 1)
  end

  defp parse_paren_list(["(" | rest], acc, depth) do
    parse_paren_list(rest, ["(" | acc], depth + 1)
  end

  defp parse_paren_list([")" | rest], acc, 1) do
    {Enum.reverse(acc) |> Enum.filter(&(&1 != ",")), rest}
  end

  defp parse_paren_list([")" | rest], acc, depth) do
    parse_paren_list(rest, [")" | acc], depth - 1)
  end

  defp parse_paren_list([token | rest], acc, depth) do
    parse_paren_list(rest, [token | acc], depth)
  end

  defp parse_paren_list([], acc, _) do
    {Enum.reverse(acc) |> Enum.filter(&(&1 != ",")), []}
  end

  defp parse_primary_key_constraint(["KEY", "(" | rest]) do
    {cols, remaining} = parse_paren_list(rest)
    {{:primary_key, cols}, remaining}
  end

  defp parse_primary_key_constraint(rest), do: {nil, rest}

  defp parse_foreign_key_constraint(["KEY", "(" | rest]) do
    {cols, remaining} = parse_paren_list(rest)
    {ref, final} = parse_references_clause(remaining)
    {{:foreign_key, cols, ref}, final}
  end

  defp parse_foreign_key_constraint(rest), do: {nil, rest}

  defp parse_references_clause(["REFERENCES" | rest]) do
    parse_references(rest)
  end

  defp parse_references_clause(rest), do: {nil, rest}

  defp parse_unique_constraint(["(" | rest]) do
    {cols, remaining} = parse_paren_list(rest)
    {{:unique, cols}, remaining}
  end

  defp parse_unique_constraint(rest), do: {nil, rest}

  defp parse_check_constraint(["(" | rest]) do
    {expr, remaining} = parse_paren_list(rest)
    {{:check, expr}, remaining}
  end

  defp parse_check_constraint(rest), do: {nil, rest}

  defp parse_named_constraint([name | rest]) do
    parse_column_definitions(rest, [], [])
    |> case do
      {_, [constraint | _]} -> {{:named, name, constraint}, []}
      _ -> {nil, rest}
    end
  end

  defp parse_create_index(tokens, unique \\ false)

  defp parse_create_index([name, "ON", table, "(" | rest], unique) do
    {cols, _remaining} = parse_paren_list(rest)
    {:create_index, %{name: name, table: table, columns: cols, unique: unique}}
  end

  defp parse_create_index(_, _), do: {:error, "Invalid CREATE INDEX syntax"}

  defp parse_create_sequence([name | rest]) do
    options = parse_sequence_options(rest)
    {:create_sequence, %{name: name, options: options}}
  end

  defp parse_sequence_options(tokens) do
    parse_sequence_options(tokens, %{})
  end

  defp parse_sequence_options([], acc), do: acc

  defp parse_sequence_options([token | rest], acc) when is_binary(token) do
    case String.upcase(token) do
      "START" ->
        case rest do
          ["WITH", value | remaining] ->
            parse_sequence_options(remaining, Map.put(acc, :start, parse_value(value)))

          [value | remaining] ->
            parse_sequence_options(remaining, Map.put(acc, :start, parse_value(value)))
        end

      "INCREMENT" ->
        case rest do
          ["BY", value | remaining] ->
            parse_sequence_options(remaining, Map.put(acc, :increment, parse_value(value)))

          [value | remaining] ->
            parse_sequence_options(remaining, Map.put(acc, :increment, parse_value(value)))
        end

      "MINVALUE" ->
        [value | remaining] = rest
        parse_sequence_options(remaining, Map.put(acc, :min_value, parse_value(value)))

      "NO" ->
        case rest do
          ["MINVALUE" | remaining] ->
            parse_sequence_options(remaining, Map.put(acc, :no_minvalue, true))

          ["MAXVALUE" | remaining] ->
            parse_sequence_options(remaining, Map.put(acc, :no_maxvalue, true))

          ["CYCLE" | remaining] ->
            parse_sequence_options(remaining, Map.put(acc, :cycle, false))

          _ ->
            parse_sequence_options(rest, acc)
        end

      "MAXVALUE" ->
        [value | remaining] = rest
        parse_sequence_options(remaining, Map.put(acc, :max_value, parse_value(value)))

      "CYCLE" ->
        parse_sequence_options(rest, Map.put(acc, :cycle, true))

      "CACHE" ->
        [value | remaining] = rest
        parse_sequence_options(remaining, Map.put(acc, :cache, parse_value(value)))

      "OWNED" ->
        case rest do
          ["BY", owner | remaining] ->
            parse_sequence_options(remaining, Map.put(acc, :owned_by, owner))

          _ ->
            parse_sequence_options(rest, acc)
        end

      _ ->
        parse_sequence_options(rest, acc)
    end
  end

  defp parse_sequence_options([_ | rest], acc) do
    parse_sequence_options(rest, acc)
  end

  # Parse CREATE TYPE for PostgreSQL composite types
  defp parse_create_type([type_name, "AS", "(" | rest]) do
    {attributes, _} = parse_type_attributes(rest)
    {:create_type, %{name: type_name, kind: :composite, attributes: attributes}}
  end

  defp parse_create_type([type_name, "AS", "ENUM", "(" | rest]) do
    {values, _} = parse_enum_values(rest)
    {:create_type, %{name: type_name, kind: :enum, values: values}}
  end

  defp parse_create_type([type_name, "AS", "RANGE", "(" | rest]) do
    {options, _} = parse_range_options(rest)
    {:create_type, %{name: type_name, kind: :range, options: options}}
  end

  defp parse_create_type(_), do: {:error, "Invalid CREATE TYPE syntax"}

  defp parse_type_attributes(tokens), do: parse_type_attributes(tokens, [])

  defp parse_type_attributes([")" | _], acc), do: {Enum.reverse(acc), []}
  defp parse_type_attributes([], acc), do: {Enum.reverse(acc), []}
  defp parse_type_attributes(["," | rest], acc), do: parse_type_attributes(rest, acc)

  defp parse_type_attributes([name, type | rest], acc) do
    parse_type_attributes(rest, [{name, type} | acc])
  end

  defp parse_enum_values(tokens), do: parse_enum_values(tokens, [])

  defp parse_enum_values([")" | _], acc), do: {Enum.reverse(acc), []}
  defp parse_enum_values([], acc), do: {Enum.reverse(acc), []}
  defp parse_enum_values(["," | rest], acc), do: parse_enum_values(rest, acc)

  defp parse_enum_values([{:string, val} | rest], acc) do
    parse_enum_values(rest, [val | acc])
  end

  defp parse_enum_values([val | rest], acc) do
    parse_enum_values(rest, [val | acc])
  end

  defp parse_range_options(tokens), do: {[], tokens}

  # Parse DROP statement
  defp parse_drop(tokens) do
    case tl(tokens) do
      ["TABLE", "IF", "EXISTS", table | rest] ->
        cascade = "CASCADE" in Enum.map(rest, &String.upcase/1)
        {:drop_table, %{table: table, cascade: cascade, if_exists: true}}

      ["TABLE", table | rest] ->
        cascade = "CASCADE" in Enum.map(rest, &String.upcase/1)
        {:drop_table, %{table: table, cascade: cascade, if_exists: false}}

      ["INDEX", "IF", "EXISTS", name | _] ->
        {:drop_index, %{name: name, if_exists: true}}

      ["INDEX", name | _] ->
        {:drop_index, %{name: name, if_exists: false}}

      ["SEQUENCE", "IF", "EXISTS", name | _] ->
        {:drop_sequence, %{name: name, if_exists: true}}

      ["SEQUENCE", name | _] ->
        {:drop_sequence, %{name: name, if_exists: false}}

      ["TYPE", name | rest] ->
        cascade = "CASCADE" in Enum.map(rest, &String.upcase/1)
        {:drop_type, %{name: name, cascade: cascade}}

      _ ->
        {:error, "Unknown DROP command"}
    end
  end

  # Parse ALTER statement
  defp parse_alter(tokens) do
    case tl(tokens) do
      ["TABLE" | rest] -> parse_alter_table(rest)
      ["SEQUENCE" | rest] -> parse_alter_sequence(rest)
      ["TYPE" | rest] -> parse_alter_type(rest)
      _ -> {:error, "Unknown ALTER command"}
    end
  end

  defp parse_alter_table([table | rest]) do
    {action, details} = parse_alter_action(rest)
    {:alter_table, %{table: table, action: action, details: details}}
  end

  defp parse_alter_action(["ADD" | rest]) do
    case rest do
      ["COLUMN" | col_rest] ->
        {col_def, _} = parse_column_def(col_rest)
        {:add_column, col_def}

      ["CONSTRAINT" | constraint_rest] ->
        {constraint, _} = parse_named_constraint(constraint_rest)
        {:add_constraint, constraint}

      _ ->
        {col_def, _} = parse_column_def(rest)
        {:add_column, col_def}
    end
  end

  defp parse_alter_action(["DROP" | rest]) do
    case rest do
      ["COLUMN", "IF", "EXISTS", col | _] -> {:drop_column_if_exists, col}
      ["COLUMN", col | _] -> {:drop_column, col}
      ["CONSTRAINT", "IF", "EXISTS", name | _] -> {:drop_constraint_if_exists, name}
      ["CONSTRAINT", name | _] -> {:drop_constraint, name}
      [col | _] -> {:drop_column, col}
    end
  end

  defp parse_alter_action(["ALTER" | rest]) do
    case rest do
      ["COLUMN", col_name, "TYPE", new_type | _] ->
        {:alter_column_type, {col_name, new_type}}

      ["COLUMN", col_name, "SET", "NOT", "NULL" | _] ->
        {:set_not_null, col_name}

      ["COLUMN", col_name, "DROP", "NOT", "NULL" | _] ->
        {:drop_not_null, col_name}

      ["COLUMN", col_name, "SET", "DEFAULT", value | _] ->
        {:set_default, {col_name, value}}

      ["COLUMN", col_name, "DROP", "DEFAULT" | _] ->
        {:drop_default, col_name}

      _ ->
        {:error, nil}
    end
  end

  defp parse_alter_action(["RENAME" | rest]) do
    case rest do
      ["COLUMN", old_name, "TO", new_name | _] ->
        {:rename_column, {old_name, new_name}}

      ["TO", new_name | _] ->
        {:rename_table, new_name}

      _ ->
        {:error, nil}
    end
  end

  defp parse_alter_action(_), do: {:error, nil}

  defp parse_alter_sequence([seq_name | rest]) do
    options = parse_sequence_options(rest)
    {:alter_sequence, %{name: seq_name, options: options}}
  end

  defp parse_alter_type([type_name | rest]) do
    {action, details} = parse_alter_type_action(rest)
    {:alter_type, %{name: type_name, action: action, details: details}}
  end

  defp parse_alter_type_action(["ADD" | rest]) do
    case rest do
      ["VALUE", {:string, val} | _] -> {:add_value, val}
      ["VALUE", val | _] -> {:add_value, val}
      ["ATTRIBUTE", name, type | _] -> {:add_attribute, {name, type}}
      _ -> {:error, nil}
    end
  end

  defp parse_alter_type_action(["DROP" | rest]) do
    case rest do
      ["ATTRIBUTE", name | _] -> {:drop_attribute, name}
      _ -> {:error, nil}
    end
  end

  defp parse_alter_type_action(["RENAME" | rest]) do
    case rest do
      ["VALUE", old, "TO", new | _] -> {:rename_value, {old, new}}
      ["ATTRIBUTE", old, "TO", new | _] -> {:rename_attribute, {old, new}}
      _ -> {:error, nil}
    end
  end

  defp parse_alter_type_action(_), do: {:error, nil}

  # Helper function to find a keyword in tokens
  defp find_keyword(tokens, keyword) do
    upcase_kw = String.upcase(keyword)

    case Enum.find_index(tokens, fn
           t when is_binary(t) -> String.upcase(t) == upcase_kw
           _ -> false
         end) do
      nil -> nil
      idx -> {Enum.take(tokens, idx), Enum.drop(tokens, idx + 1)}
    end
  end
end
