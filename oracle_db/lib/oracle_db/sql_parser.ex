defmodule OracleDb.SqlParser do
  @moduledoc """
  SQL Parser for Oracle SQL-compatible statements.
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
    trimmed_sql = sql |> String.trim()

    # For PL/SQL blocks, validate syntax before parsing
    case validate_plsql_syntax(trimmed_sql) do
      {:error, _} = err ->
        err

      :ok ->
        trimmed_sql
        |> String.trim_trailing(";")
        |> String.trim()
        |> tokenize()
        |> parse_tokens()
    end
  end

  @doc """
  Validates PL/SQL syntax to ensure blocks are properly terminated.
  Returns :ok if valid, {:error, reason} if invalid.
  """
  @spec validate_plsql_syntax(String.t()) :: :ok | {:error, String.t()}
  def validate_plsql_syntax(sql) do
    sql_upper = String.upcase(sql)

    cond do
      # Check if this is a PL/SQL block that needs validation
      is_plsql_statement?(sql_upper) ->
        validate_plsql_block_structure(sql_upper)

      # Not a PL/SQL block, no special validation needed
      true ->
        :ok
    end
  end

  defp is_plsql_statement?(sql_upper) do
    String.starts_with?(sql_upper, "CREATE PROCEDURE") or
      String.starts_with?(sql_upper, "CREATE OR REPLACE PROCEDURE") or
      String.starts_with?(sql_upper, "CREATE FUNCTION") or
      String.starts_with?(sql_upper, "CREATE OR REPLACE FUNCTION") or
      String.starts_with?(sql_upper, "CREATE TRIGGER") or
      String.starts_with?(sql_upper, "CREATE OR REPLACE TRIGGER") or
      String.starts_with?(sql_upper, "CREATE PACKAGE") or
      String.starts_with?(sql_upper, "CREATE OR REPLACE PACKAGE") or
      String.starts_with?(sql_upper, "BEGIN") or
      String.starts_with?(sql_upper, "DECLARE")
  end

  defp validate_plsql_block_structure(sql) do
    # Remove string literals to avoid false matches
    sql_without_strings = Regex.replace(~r/'[^']*'/, sql, "''")

    # Check for required BEGIN keyword (for procedures, functions, triggers)
    has_begin = Regex.match?(~r/\bBEGIN\b/, sql_without_strings)

    # Check for proper termination
    has_end =
      Regex.match?(~r/\bEND\s*;?\s*$/, sql_without_strings) or
        Regex.match?(~r/\bEND\s+\w+\s*;?\s*$/, sql_without_strings)

    # Count BEGIN and END blocks
    begin_count = length(Regex.scan(~r/\bBEGIN\b/, sql_without_strings))

    # Count only terminal END statements (END; or END name;)
    # Excluding END IF, END LOOP, END CASE which are internal block terminators
    terminal_end_count = count_terminal_ends(sql_without_strings)

    cond do
      # Anonymous blocks must have BEGIN
      (String.starts_with?(sql, "BEGIN") or String.starts_with?(sql, "DECLARE")) and not has_begin ->
        {:error, "PL/SQL block must contain BEGIN"}

      # Procedures/functions/triggers need IS/AS and BEGIN
      is_stored_program?(sql) and not has_begin ->
        {:error, "Stored program must contain BEGIN...END block"}

      # Must have proper END termination
      has_begin and not has_end ->
        {:error, "PL/SQL block not properly terminated with END;"}

      # BEGIN/END must be balanced
      has_begin and terminal_end_count < begin_count ->
        {:error, "Unbalanced BEGIN/END blocks - missing END;"}

      true ->
        :ok
    end
  end

  defp is_stored_program?(sql) do
    String.starts_with?(sql, "CREATE PROCEDURE") or
      String.starts_with?(sql, "CREATE OR REPLACE PROCEDURE") or
      String.starts_with?(sql, "CREATE FUNCTION") or
      String.starts_with?(sql, "CREATE OR REPLACE FUNCTION") or
      String.starts_with?(sql, "CREATE TRIGGER") or
      String.starts_with?(sql, "CREATE OR REPLACE TRIGGER")
  end

  defp count_terminal_ends(sql) do
    # Count END; (terminal END with optional semicolon)
    end_semicolon = length(Regex.scan(~r/\bEND\s*;/, sql))

    # Count END <name>; where name is not IF, LOOP, or CASE
    end_name = length(Regex.scan(~r/\bEND\s+(?!IF\b|LOOP\b|CASE\b)\w+\s*;/, sql))

    end_semicolon + end_name
  end

  @doc """
  Tokenizes SQL string into a list of tokens.
  """
  @spec tokenize(String.t()) :: [String.t()]
  def tokenize(sql) do
    sql
    |> handle_string_literals()
    |> String.replace(~r/\s+/, " ")
    |> String.replace(~r/\(\s*/, " ( ")
    |> String.replace(~r/\s*\)/, " ) ")
    |> String.replace(",", " , ")
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

  # Handle string literals by replacing spaces with placeholder using hex encoding
  defp handle_string_literals(sql) do
    Regex.replace(~r/'([^']*)'/, sql, fn _, content ->
      hex = Base.encode16(content, case: :lower)
      "~STRLIT~#{hex}~STRLIT~"
    end)
  end

  defp restore_string_literal(token) do
    case Regex.run(~r/~STRLIT~([0-9a-f]*)~STRLIT~/i, token) do
      [_, hex] ->
        {:ok, decoded} = Base.decode16(hex, case: :mixed)
        {:string, decoded}

      nil ->
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
      "CALL" -> parse_call(tokens)
      "EXECUTE" -> parse_execute(tokens)
      "EXEC" -> parse_execute(tokens)
      "BEGIN" -> parse_anonymous_block(tokens)
      "DECLARE" -> parse_anonymous_block(tokens)
      _ -> {:error, "Unknown SQL command: #{hd(tokens)}"}
    end
  end

  # Parse SELECT statement
  defp parse_select(tokens) do
    # Remove SELECT keyword
    tokens = tl(tokens)

    # Parse columns
    {columns, rest} = parse_columns(tokens)

    # Parse FROM clause
    {table, rest} = parse_from(rest)

    # Parse WHERE clause (optional)
    {where, rest} = parse_where(rest)

    # Parse ORDER BY clause (optional)
    {order_by, rest} = parse_order_by(rest)

    # Parse ROWNUM (Oracle-specific, in WHERE clause usually)
    {rownum, _rest} = parse_rownum(rest)

    {:select,
     %{
       columns: columns,
       table: table,
       where: where,
       order_by: order_by,
       rownum: rownum
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
        # Check for alias
        {alias_name, remaining} = check_for_alias(rest)
        {{:column, normalize_token(token), alias_name}, remaining}
    end
  end

  defp is_function?(token) when is_binary(token) do
    String.upcase(token) in [
      "COUNT",
      "SUM",
      "AVG",
      "MAX",
      "MIN",
      "NVL",
      "NVL2",
      "COALESCE",
      "DECODE",
      "TO_CHAR",
      "TO_DATE",
      "TO_NUMBER",
      "UPPER",
      "LOWER",
      "SUBSTR",
      "LENGTH",
      "TRIM",
      "LTRIM",
      "RTRIM",
      "ROUND",
      "TRUNC",
      "SYSDATE",
      "ROWNUM",
      # XML functions
      "XMLELEMENT",
      "XMLFOREST",
      "XMLAGG",
      "XMLROOT",
      "XMLPARSE",
      "XMLSERIALIZE",
      "XMLCONCAT",
      "XMLCOMMENT",
      "XMLPI",
      "XMLATTRIBUTES",
      "XMLCDATA"
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

      kw when kw in ["FROM", "WHERE", "ORDER", "GROUP", "HAVING", ",", ")"] ->
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
      ",",
      "(",
      ")",
      "AS"
    ]
  end

  defp is_identifier?(_), do: false

  defp normalize_token({:string, val}), do: val
  defp normalize_token(token) when is_binary(token), do: token

  defp parse_from(tokens) do
    case find_keyword(tokens, "FROM") do
      nil ->
        # Check for DUAL (Oracle allows SELECT without FROM when using DUAL implicitly)
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
      kw when kw in ["ORDER", "GROUP", "HAVING", "LIMIT"] ->
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
        # Handle IS NULL / IS NOT NULL
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

  defp parse_comparison([value | rest], [col | acc], op) do
    {[{:comparison, col, op, parse_value(value)} | acc], rest}
  end

  defp parse_comparison(rest, acc, _op), do: {acc, rest}

  defp parse_value({:string, val}), do: val

  defp parse_value(token) when is_binary(token) do
    cond do
      String.upcase(token) == "NULL" -> nil
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
    {dir, remaining} =
      case rest do
        [d | r] when is_binary(d) ->
          case String.upcase(d) do
            "ASC" -> {:asc, r}
            "DESC" -> {:desc, r}
            "," -> {:asc, r}
            _ -> {:asc, [d | r]}
          end

        _ ->
          {:asc, rest}
      end

    remaining =
      case remaining do
        ["," | r] -> r
        r -> r
      end

    case String.upcase(col) do
      kw when kw in ["LIMIT", "OFFSET", "GROUP", "HAVING"] ->
        {Enum.reverse(acc), [col | rest]}

      _ ->
        parse_order_columns(remaining, [{col, dir} | acc])
    end
  end

  defp parse_rownum(tokens) do
    # ROWNUM is typically in WHERE clause, but check for limit-style usage
    {nil, tokens}
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
    {values, _rest} = parse_insert_values(rest)

    {:insert,
     %{
       table: table,
       columns: columns,
       values: values
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
      nil -> {[], tokens}
      {_before, rest} -> parse_values_list(rest)
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

  # Parse UPDATE statement
  defp parse_update(tokens) do
    # Remove UPDATE
    tokens = tl(tokens)

    case tokens do
      [table | rest] ->
        {sets, rest} = parse_set_clause(rest)
        {where, _rest} = parse_where(rest)

        {:update,
         %{
           table: table,
           sets: sets,
           where: where
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
        if String.upcase(kw) == "WHERE" do
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
        {where, _rest} = parse_where(rest)
        {:delete, %{table: table, where: where}}

      [table | rest] ->
        {where, _rest} = parse_where(rest)
        {:delete, %{table: table, where: where}}

      _ ->
        {:error, "Invalid DELETE syntax"}
    end
  end

  # Parse CREATE statement
  defp parse_create(tokens) do
    case tl(tokens) do
      ["TABLE" | rest] -> parse_create_table(rest)
      ["INDEX" | rest] -> parse_create_index(rest)
      ["UNIQUE", "INDEX" | rest] -> parse_create_index(rest, true)
      ["SEQUENCE" | rest] -> parse_create_sequence(rest)
      ["TYPE" | rest] -> parse_create_type(rest)
      ["OR", "REPLACE", "TYPE" | rest] -> parse_create_type(rest, true)
      ["VIEW" | rest] -> parse_create_view(rest)
      ["OR", "REPLACE", "VIEW" | rest] -> parse_create_view(rest, true)
      ["MATERIALIZED", "VIEW" | rest] -> parse_create_materialized_view(rest)
      ["PROCEDURE" | rest] -> parse_create_procedure(rest)
      ["OR", "REPLACE", "PROCEDURE" | rest] -> parse_create_procedure(rest, true)
      ["FUNCTION" | rest] -> parse_create_function(rest)
      ["OR", "REPLACE", "FUNCTION" | rest] -> parse_create_function(rest, true)
      ["TRIGGER" | rest] -> parse_create_trigger(rest)
      ["OR", "REPLACE", "TRIGGER" | rest] -> parse_create_trigger(rest, true)
      ["PACKAGE" | rest] -> parse_create_package(rest)
      ["OR", "REPLACE", "PACKAGE" | rest] -> parse_create_package(rest, true)
      _ -> {:error, "Unknown CREATE command"}
    end
  end

  # Parse CREATE VIEW statement
  defp parse_create_view(tokens, replace \\ false) do
    case tokens do
      # Object-relational view: CREATE VIEW name OF type_name WITH OBJECT IDENTIFIER (cols) AS SELECT ...
      [view_name, "OF", type_name, "WITH", "OBJECT", "IDENTIFIER", "(" | rest] ->
        {oid_columns, remaining} = parse_view_column_list(rest)

        case remaining do
          ["AS" | select_rest] ->
            # select_rest starts with "SELECT", pass directly
            case parse_select(select_rest) do
              {:select, select_info} ->
                {:create_view,
                 %{
                   name: view_name,
                   of_type: type_name,
                   object_identifier: oid_columns,
                   query: select_info,
                   replace: replace,
                   object_view: true
                 }}

              error ->
                error
            end

          _ ->
            {:error, "Invalid CREATE VIEW OF syntax - expected AS after WITH OBJECT IDENTIFIER"}
        end

      # Object-relational view without WITH OBJECT IDENTIFIER: CREATE VIEW name OF type_name AS SELECT ...
      [view_name, "OF", type_name, "AS" | rest] ->
        # rest starts with "SELECT", pass directly
        case parse_select(rest) do
          {:select, select_info} ->
            {:create_view,
             %{
               name: view_name,
               of_type: type_name,
               query: select_info,
               replace: replace,
               object_view: true
             }}

          error ->
            error
        end

      [view_name, "AS" | rest] ->
        # Parse the SELECT statement that defines the view
        # rest should start with "SELECT" already, so pass it directly
        case parse_select(rest) do
          {:select, select_info} ->
            {:create_view,
             %{
               name: view_name,
               query: select_info,
               replace: replace
             }}

          error ->
            error
        end

      [view_name, "(" | rest] ->
        # View with explicit column names
        {column_list, remaining} = parse_view_column_list(rest)

        case remaining do
          ["AS" | select_rest] ->
            # select_rest starts with "SELECT", pass directly
            case parse_select(select_rest) do
              {:select, select_info} ->
                {:create_view,
                 %{
                   name: view_name,
                   columns: column_list,
                   query: select_info,
                   replace: replace
                 }}

              error ->
                error
            end

          _ ->
            {:error, "Invalid CREATE VIEW syntax - expected AS"}
        end

      _ ->
        {:error, "Invalid CREATE VIEW syntax"}
    end
  end

  defp parse_view_column_list(tokens) do
    parse_view_column_list(tokens, [])
  end

  defp parse_view_column_list([")" | rest], acc) do
    {Enum.reverse(acc), rest}
  end

  defp parse_view_column_list(["," | rest], acc) do
    parse_view_column_list(rest, acc)
  end

  defp parse_view_column_list([col | rest], acc) do
    parse_view_column_list(rest, [col | acc])
  end

  defp parse_view_column_list([], acc) do
    {Enum.reverse(acc), []}
  end

  # Parse CREATE MATERIALIZED VIEW statement
  defp parse_create_materialized_view(tokens) do
    case tokens do
      [view_name, "AS" | rest] ->
        # rest starts with "SELECT", pass directly
        case parse_select(rest) do
          {:select, select_info} ->
            {:create_materialized_view,
             %{
               name: view_name,
               query: select_info
             }}

          error ->
            error
        end

      _ ->
        {:error, "Invalid CREATE MATERIALIZED VIEW syntax"}
    end
  end

  # Parse CREATE TYPE statement for object-relational types
  defp parse_create_type(tokens, replace \\ false) do
    case tokens do
      [type_name, "AS", "OBJECT", "(" | rest] ->
        {attributes, methods} = parse_type_attributes(rest)

        {:create_type,
         %{
           name: type_name,
           kind: :object,
           attributes: attributes,
           methods: methods,
           replace: replace
         }}

      [type_name, "AS", "TABLE", "OF" | rest] ->
        {element_type, _remaining} = parse_element_type(rest)

        {:create_type,
         %{
           name: type_name,
           kind: :nested_table,
           element_type: element_type,
           replace: replace
         }}

      [type_name, "AS", "VARRAY", "(" | rest] ->
        {size, element_type} = parse_varray_def(rest)

        {:create_type,
         %{
           name: type_name,
           kind: :varray,
           max_size: size,
           element_type: element_type,
           replace: replace
         }}

      [type_name, "UNDER", parent_type, "(" | rest] ->
        {attributes, methods} = parse_type_attributes(rest)

        {:create_type,
         %{
           name: type_name,
           kind: :object,
           parent: parent_type,
           attributes: attributes,
           methods: methods,
           replace: replace
         }}

      _ ->
        {:error, "Invalid CREATE TYPE syntax"}
    end
  end

  defp parse_type_attributes(tokens) do
    parse_type_attributes(tokens, [], [])
  end

  defp parse_type_attributes([")" | _], attrs, methods) do
    {Enum.reverse(attrs), Enum.reverse(methods)}
  end

  defp parse_type_attributes([], attrs, methods) do
    {Enum.reverse(attrs), Enum.reverse(methods)}
  end

  defp parse_type_attributes(["," | rest], attrs, methods) do
    parse_type_attributes(rest, attrs, methods)
  end

  defp parse_type_attributes([token | rest], attrs, methods) when is_binary(token) do
    case String.upcase(token) do
      "MEMBER" ->
        {method, remaining} = parse_type_method(rest)
        parse_type_attributes(remaining, attrs, [method | methods])

      "CONSTRUCTOR" ->
        {method, remaining} = parse_constructor_method(rest)
        parse_type_attributes(remaining, attrs, [method | methods])

      "STATIC" ->
        {method, remaining} = parse_static_method(rest)
        parse_type_attributes(remaining, attrs, [method | methods])

      "MAP" ->
        {method, remaining} = parse_map_method(rest)
        parse_type_attributes(remaining, attrs, [method | methods])

      "ORDER" ->
        {method, remaining} = parse_order_method(rest)
        parse_type_attributes(remaining, attrs, [method | methods])

      _ ->
        # Parse attribute: name type
        {attr, remaining} = parse_type_attribute([token | rest])
        parse_type_attributes(remaining, [attr | attrs], methods)
    end
  end

  defp parse_type_attributes([_ | rest], attrs, methods) do
    parse_type_attributes(rest, attrs, methods)
  end

  defp parse_type_attribute([name, type | rest]) do
    {type_info, remaining} = parse_attribute_type([type | rest])
    {{name, type_info}, remaining}
  end

  defp parse_type_attribute([name | rest]) do
    {{name, :unknown}, rest}
  end

  defp parse_attribute_type([type | rest]) do
    case String.upcase(type) do
      t when t in ["VARCHAR2", "VARCHAR", "CHAR", "NVARCHAR2", "NCHAR"] ->
        case rest do
          ["(" | more] ->
            {size, remaining} = parse_type_size_spec(more)
            {{:string, t, size}, remaining}

          _ ->
            {{:string, t, nil}, rest}
        end

      t
      when t in [
             "NUMBER",
             "NUMERIC",
             "DECIMAL",
             "INTEGER",
             "INT",
             "SMALLINT",
             "FLOAT",
             "REAL",
             "DOUBLE"
           ] ->
        case rest do
          ["(" | more] ->
            {precision, remaining} = parse_type_size_spec(more)
            {{:number, t, precision}, remaining}

          _ ->
            {{:number, t, nil}, rest}
        end

      t when t in ["DATE", "TIMESTAMP", "INTERVAL"] ->
        {{:datetime, t}, rest}

      t when t in ["CLOB", "BLOB", "NCLOB", "BFILE"] ->
        {{:lob, t}, rest}

      t when t in ["REF"] ->
        case rest do
          [ref_type | remaining] ->
            {{:ref, ref_type}, remaining}

          _ ->
            {{:ref, nil}, rest}
        end

      _ ->
        # Could be a user-defined type
        {{:user_type, type}, rest}
    end
  end

  defp parse_type_size_spec(tokens) do
    parse_type_size_spec(tokens, [])
  end

  defp parse_type_size_spec([")" | rest], acc) do
    {Enum.reverse(acc) |> Enum.join(","), rest}
  end

  defp parse_type_size_spec(["," | rest], acc) do
    parse_type_size_spec(rest, acc)
  end

  defp parse_type_size_spec([token | rest], acc) do
    parse_type_size_spec(rest, [token | acc])
  end

  defp parse_type_size_spec([], acc) do
    {Enum.reverse(acc) |> Enum.join(","), []}
  end

  defp parse_type_method(["FUNCTION", name, "(" | rest]) do
    {params, remaining} = parse_method_params(rest)

    case remaining do
      ["RETURN", return_type | final] ->
        {{:member_function, name, params, return_type}, skip_to_next_member(final)}

      _ ->
        {{:member_function, name, params, nil}, skip_to_next_member(remaining)}
    end
  end

  defp parse_type_method(["PROCEDURE", name, "(" | rest]) do
    {params, remaining} = parse_method_params(rest)
    {{:member_procedure, name, params}, skip_to_next_member(remaining)}
  end

  defp parse_type_method(["FUNCTION", name | rest]) do
    case rest do
      ["RETURN", return_type | final] ->
        {{:member_function, name, [], return_type}, skip_to_next_member(final)}

      _ ->
        {{:member_function, name, [], nil}, skip_to_next_member(rest)}
    end
  end

  defp parse_type_method(["PROCEDURE", name | rest]) do
    {{:member_procedure, name, []}, skip_to_next_member(rest)}
  end

  defp parse_type_method(rest), do: {nil, rest}

  defp parse_constructor_method(["FUNCTION", name, "(" | rest]) do
    {params, remaining} = parse_method_params(rest)

    case remaining do
      ["RETURN", "SELF", "AS", "RESULT" | final] ->
        {{:constructor, name, params}, skip_to_next_member(final)}

      ["RETURN", return_type | final] ->
        {{:constructor, name, params, return_type}, skip_to_next_member(final)}

      _ ->
        {{:constructor, name, params}, skip_to_next_member(remaining)}
    end
  end

  defp parse_constructor_method(rest), do: {nil, rest}

  defp parse_static_method(["FUNCTION", name, "(" | rest]) do
    {params, remaining} = parse_method_params(rest)

    case remaining do
      ["RETURN", return_type | final] ->
        {{:static_function, name, params, return_type}, skip_to_next_member(final)}

      _ ->
        {{:static_function, name, params, nil}, skip_to_next_member(remaining)}
    end
  end

  defp parse_static_method(["PROCEDURE", name, "(" | rest]) do
    {params, remaining} = parse_method_params(rest)
    {{:static_procedure, name, params}, skip_to_next_member(remaining)}
  end

  defp parse_static_method(rest), do: {nil, rest}

  defp parse_map_method(["MEMBER", "FUNCTION", name | rest]) do
    case rest do
      ["RETURN", return_type | final] ->
        {{:map_method, name, return_type}, skip_to_next_member(final)}

      _ ->
        {{:map_method, name, nil}, skip_to_next_member(rest)}
    end
  end

  defp parse_map_method(rest), do: {nil, rest}

  defp parse_order_method(["MEMBER", "FUNCTION", name, "(" | rest]) do
    {params, remaining} = parse_method_params(rest)

    case remaining do
      ["RETURN", return_type | final] ->
        {{:order_method, name, params, return_type}, skip_to_next_member(final)}

      _ ->
        {{:order_method, name, params, nil}, skip_to_next_member(remaining)}
    end
  end

  defp parse_order_method(rest), do: {nil, rest}

  defp parse_method_params(tokens) do
    parse_method_params(tokens, [])
  end

  defp parse_method_params([")" | rest], acc) do
    {Enum.reverse(acc), rest}
  end

  defp parse_method_params(["," | rest], acc) do
    parse_method_params(rest, acc)
  end

  defp parse_method_params([name, type | rest], acc) do
    case String.upcase(name) do
      kw when kw in ["IN", "OUT", "IN OUT"] ->
        parse_method_params([type | rest], acc)

      _ ->
        parse_method_params(rest, [{name, type} | acc])
    end
  end

  defp parse_method_params([_ | rest], acc) do
    parse_method_params(rest, acc)
  end

  defp parse_method_params([], acc) do
    {Enum.reverse(acc), []}
  end

  defp skip_to_next_member(tokens) do
    # Skip until we find a comma or closing paren
    case tokens do
      ["," | rest] -> rest
      [")" | _] = rest -> rest
      [_ | rest] -> skip_to_next_member(rest)
      [] -> []
    end
  end

  # Parse CREATE PROCEDURE statement
  defp parse_create_procedure(tokens, replace \\ false) do
    case tokens do
      [proc_name | rest] ->
        {params, remaining} = parse_procedure_params(rest)
        {body, _final} = parse_plsql_body(remaining)

        {:create_procedure,
         %{
           name: proc_name,
           parameters: params,
           body: body,
           replace: replace
         }}

      _ ->
        {:error, "Invalid CREATE PROCEDURE syntax"}
    end
  end

  defp parse_procedure_params(["(" | rest]) do
    parse_proc_params_list(rest, [])
  end

  defp parse_procedure_params(rest) do
    {[], rest}
  end

  defp parse_proc_params_list([")" | rest], acc) do
    {Enum.reverse(acc), rest}
  end

  defp parse_proc_params_list(["," | rest], acc) do
    parse_proc_params_list(rest, acc)
  end

  defp parse_proc_params_list([name | rest], acc) when is_binary(name) do
    case String.upcase(name) do
      "IN" ->
        # IN mode or IN OUT mode
        case rest do
          ["OUT", param_name | r] ->
            # IN OUT mode - param_name is next after "OUT"
            parse_proc_param_type(r, param_name, :in_out, acc)

          [param_name | r] ->
            # Just IN mode
            parse_proc_param_type(r, param_name, :in, acc)

          _ ->
            {Enum.reverse(acc), rest}
        end

      "OUT" ->
        # OUT mode
        case rest do
          [param_name | r] ->
            parse_proc_param_type(r, param_name, :out, acc)

          _ ->
            {Enum.reverse(acc), rest}
        end

      _ ->
        # Parameter name without mode (default IN)
        parse_proc_param_type(rest, name, :in, acc)
    end
  end

  defp parse_proc_params_list(rest, acc) do
    {Enum.reverse(acc), rest}
  end

  defp parse_proc_param_type([], name, mode, acc) do
    # No type specified, use default
    param = %{name: name, type: "ANY", mode: mode}
    {Enum.reverse([param | acc]), []}
  end

  defp parse_proc_param_type([")" | rest], name, mode, acc) do
    # Closing paren reached before type
    param = %{name: name, type: "ANY", mode: mode}
    {Enum.reverse([param | acc]), rest}
  end

  defp parse_proc_param_type([type | rest], name, mode, acc) do
    # Check for type modifiers
    {full_type, remaining} =
      case rest do
        ["(" | r] ->
          # Type with size, e.g., VARCHAR2(100)
          {size_tokens, r2} = collect_until_paren(r, [])
          {type <> "(" <> Enum.join(size_tokens, ",") <> ")", r2}

        _ ->
          {type, rest}
      end

    param = %{name: name, type: full_type, mode: mode}
    parse_proc_params_list(remaining, [param | acc])
  end

  defp collect_until_paren([")" | rest], acc) do
    {Enum.reverse(acc), rest}
  end

  defp collect_until_paren([t | rest], acc) do
    collect_until_paren(rest, [t | acc])
  end

  defp collect_until_paren([], acc) do
    {Enum.reverse(acc), []}
  end

  defp parse_plsql_body(tokens) do
    # Find IS or AS keyword which starts the PL/SQL block
    case find_plsql_start(tokens) do
      {_before, body_tokens} ->
        # Collect everything until END; as the body
        {body_text, remaining} = collect_plsql_body(body_tokens, [], 0)
        {body_text, remaining}

      nil ->
        {"", tokens}
    end
  end

  defp find_plsql_start(tokens) do
    find_plsql_start(tokens, [])
  end

  defp find_plsql_start([], _acc), do: nil

  defp find_plsql_start([token | rest], acc) when is_binary(token) do
    case String.upcase(token) do
      kw when kw in ["IS", "AS"] -> {Enum.reverse(acc), rest}
      _ -> find_plsql_start(rest, [token | acc])
    end
  end

  defp find_plsql_start([token | rest], acc) do
    find_plsql_start(rest, [token | acc])
  end

  defp collect_plsql_body([], acc, _depth) do
    {Enum.reverse(acc) |> Enum.join(" "), []}
  end

  defp collect_plsql_body([token | rest], acc, depth) when is_binary(token) do
    case String.upcase(token) do
      "BEGIN" ->
        collect_plsql_body(rest, [token | acc], depth + 1)

      "END" ->
        # End the block if we're at the outermost level (depth == 1 after seeing at least one BEGIN)
        # or if we haven't seen any BEGIN yet (depth == 0)
        if depth <= 1 do
          # Check for semicolon or procedure name after END
          remaining =
            case rest do
              [next | r] when is_binary(next) ->
                if String.upcase(next) == ";" or String.ends_with?(next, ";") do
                  r
                else
                  # Skip procedure name after END
                  case r do
                    [";" | r2] -> r2
                    _ -> r
                  end
                end

              _ ->
                rest
            end

          {Enum.reverse([token | acc]) |> Enum.join(" "), remaining}
        else
          collect_plsql_body(rest, [token | acc], depth - 1)
        end

      _ ->
        collect_plsql_body(rest, [token | acc], depth)
    end
  end

  defp collect_plsql_body([{:string, s} | rest], acc, depth) do
    collect_plsql_body(rest, ["'#{s}'" | acc], depth)
  end

  defp collect_plsql_body([token | rest], acc, depth) do
    collect_plsql_body(rest, [inspect(token) | acc], depth)
  end

  # Parse CREATE FUNCTION statement
  defp parse_create_function(tokens, replace \\ false) do
    case tokens do
      [func_name | rest] ->
        {params, remaining} = parse_procedure_params(rest)
        {return_type, remaining2} = parse_function_return(remaining)
        {body, _final} = parse_plsql_body(remaining2)

        {:create_function,
         %{
           name: func_name,
           parameters: params,
           return_type: return_type,
           body: body,
           replace: replace
         }}

      _ ->
        {:error, "Invalid CREATE FUNCTION syntax"}
    end
  end

  defp parse_function_return(["RETURN" | [type | rest]]) do
    {type, rest}
  end

  defp parse_function_return(rest) do
    {nil, rest}
  end

  # Parse CREATE TRIGGER statement
  defp parse_create_trigger(tokens, replace \\ false) do
    case tokens do
      [trigger_name | rest] ->
        {timing, remaining} = parse_trigger_timing(rest)
        {events, remaining2} = parse_trigger_events(remaining)
        {table, remaining3} = parse_trigger_table(remaining2)
        {for_each, remaining4} = parse_trigger_for_each(remaining3)
        {when_clause, remaining5} = parse_trigger_when(remaining4)
        {body, _final} = parse_plsql_body(remaining5)

        {:create_trigger,
         %{
           name: trigger_name,
           timing: timing,
           events: events,
           table: table,
           for_each: for_each,
           when_clause: when_clause,
           body: body,
           replace: replace
         }}

      _ ->
        {:error, "Invalid CREATE TRIGGER syntax"}
    end
  end

  defp parse_trigger_timing([timing | rest]) when is_binary(timing) do
    case String.upcase(timing) do
      "BEFORE" -> {:before, rest}
      "AFTER" -> {:after, rest}
      "INSTEAD" -> parse_instead_of(rest)
      _ -> {:unknown, [timing | rest]}
    end
  end

  defp parse_trigger_timing(rest), do: {:unknown, rest}

  defp parse_instead_of(["OF" | rest]) do
    {:instead_of, rest}
  end

  defp parse_instead_of(rest), do: {:instead_of, rest}

  defp parse_trigger_events(tokens) do
    parse_trigger_events(tokens, [])
  end

  defp parse_trigger_events([event | rest], acc) when is_binary(event) do
    case String.upcase(event) do
      ev when ev in ["INSERT", "UPDATE", "DELETE"] ->
        # Check for UPDATE OF columns
        {event_detail, remaining} =
          if ev == "UPDATE" do
            case rest do
              ["OF" | cols_rest] ->
                {cols, r} = collect_update_columns(cols_rest, [])
                {{:update, cols}, r}

              _ ->
                {:update, rest}
            end
          else
            {String.to_atom(String.downcase(ev)), rest}
          end

        # Check for OR to chain more events
        case remaining do
          ["OR" | more] ->
            parse_trigger_events(more, [event_detail | acc])

          _ ->
            {Enum.reverse([event_detail | acc]), remaining}
        end

      "ON" ->
        {Enum.reverse(acc), [event | rest]}

      _ ->
        {Enum.reverse(acc), [event | rest]}
    end
  end

  defp parse_trigger_events(rest, acc) do
    {Enum.reverse(acc), rest}
  end

  defp collect_update_columns([col | rest], acc) when is_binary(col) do
    case String.upcase(col) do
      kw when kw in ["OR", "ON"] ->
        {Enum.reverse(acc), [col | rest]}

      "," ->
        collect_update_columns(rest, acc)

      _ ->
        collect_update_columns(rest, [col | acc])
    end
  end

  defp collect_update_columns(rest, acc) do
    {Enum.reverse(acc), rest}
  end

  defp parse_trigger_table(["ON", table | rest]) do
    {table, rest}
  end

  defp parse_trigger_table(rest) do
    {nil, rest}
  end

  defp parse_trigger_for_each(["FOR", "EACH", scope | rest]) when is_binary(scope) do
    case String.upcase(scope) do
      "ROW" -> {:row, rest}
      "STATEMENT" -> {:statement, rest}
      _ -> {:statement, [scope | rest]}
    end
  end

  defp parse_trigger_for_each(rest) do
    {:statement, rest}
  end

  defp parse_trigger_when(["WHEN", "(" | rest]) do
    {condition, remaining} = collect_until_paren(rest, [])
    {Enum.join(condition, " "), remaining}
  end

  defp parse_trigger_when(rest) do
    {nil, rest}
  end

  # Parse CREATE PACKAGE statement
  defp parse_create_package(tokens, replace \\ false) do
    case tokens do
      ["BODY", pkg_name | rest] ->
        # Package body
        {body, _final} = parse_plsql_body(rest)

        {:create_package_body,
         %{
           name: pkg_name,
           body: body,
           replace: replace
         }}

      [pkg_name | rest] ->
        # Package specification
        {declarations, _final} = parse_package_spec(rest)

        {:create_package,
         %{
           name: pkg_name,
           declarations: declarations,
           replace: replace
         }}

      _ ->
        {:error, "Invalid CREATE PACKAGE syntax"}
    end
  end

  defp parse_package_spec(tokens) do
    # Find IS or AS keyword
    case find_plsql_start(tokens) do
      {_before, body_tokens} ->
        # Parse package declarations until END
        parse_package_declarations(body_tokens, [])

      nil ->
        {[], tokens}
    end
  end

  defp parse_package_declarations([], acc) do
    {Enum.reverse(acc), []}
  end

  defp parse_package_declarations([token | rest], acc) when is_binary(token) do
    case String.upcase(token) do
      "END" ->
        {Enum.reverse(acc), rest}

      "PROCEDURE" ->
        {proc_decl, remaining} = parse_package_procedure_decl(rest)
        parse_package_declarations(remaining, [proc_decl | acc])

      "FUNCTION" ->
        {func_decl, remaining} = parse_package_function_decl(rest)
        parse_package_declarations(remaining, [func_decl | acc])

      "TYPE" ->
        {type_decl, remaining} = parse_package_type_decl(rest)
        parse_package_declarations(remaining, [type_decl | acc])

      _ ->
        # Skip other declarations/tokens
        parse_package_declarations(rest, acc)
    end
  end

  defp parse_package_declarations([_ | rest], acc) do
    parse_package_declarations(rest, acc)
  end

  defp parse_package_procedure_decl([proc_name | rest]) do
    {params, remaining} = parse_procedure_params(rest)

    # Skip to semicolon
    remaining =
      case skip_to_semicolon(remaining) do
        {:ok, r} -> r
        :not_found -> remaining
      end

    {{:procedure, proc_name, params}, remaining}
  end

  defp parse_package_function_decl([func_name | rest]) do
    {params, remaining} = parse_procedure_params(rest)
    {return_type, remaining2} = parse_function_return(remaining)

    # Skip to semicolon
    remaining3 =
      case skip_to_semicolon(remaining2) do
        {:ok, r} -> r
        :not_found -> remaining2
      end

    {{:function, func_name, params, return_type}, remaining3}
  end

  defp parse_package_type_decl([type_name | rest]) do
    # Skip to semicolon for simple type declarations
    remaining =
      case skip_to_semicolon(rest) do
        {:ok, r} -> r
        :not_found -> rest
      end

    {{:type, type_name}, remaining}
  end

  defp skip_to_semicolon([]) do
    :not_found
  end

  defp skip_to_semicolon([";" | rest]) do
    {:ok, rest}
  end

  defp skip_to_semicolon([token | rest]) when is_binary(token) do
    if String.ends_with?(token, ";") do
      {:ok, rest}
    else
      skip_to_semicolon(rest)
    end
  end

  defp skip_to_semicolon([_ | rest]) do
    skip_to_semicolon(rest)
  end

  defp parse_element_type([type | rest]) do
    {type_info, _} = parse_attribute_type([type | rest])
    {type_info, rest}
  end

  defp parse_element_type([]) do
    {:unknown, []}
  end

  defp parse_varray_def(tokens) do
    case tokens do
      [size, ")", "OF" | rest] ->
        {element_type, _} = parse_element_type(rest)

        parsed_size =
          case Integer.parse(size) do
            {num, _} -> num
            :error -> 0
          end

        {parsed_size, element_type}

      _ ->
        {0, :unknown}
    end
  end

  defp parse_create_table([table, "(" | rest]) do
    {columns, constraints} = parse_column_definitions(rest)
    {:create_table, %{table: table, columns: columns, constraints: constraints}}
  end

  defp parse_create_table([table, "OF", type_name | rest]) do
    # CREATE TABLE ... OF type_name (object table)
    # Optional constraints can follow
    constraints =
      case rest do
        ["(" | constraint_rest] ->
          {_, constraints} = parse_column_definitions(constraint_rest)
          constraints

        _ ->
          []
      end

    {:create_table,
     %{
       table: table,
       of_type: type_name,
       columns: [],
       constraints: constraints,
       object_table: true
     }}
  end

  defp parse_create_table([table | rest]) do
    # CREATE TABLE AS SELECT ...
    case rest do
      ["AS" | select_rest] ->
        case parse_select(["SELECT" | select_rest]) do
          {:select, select_info} ->
            {:create_table, %{table: table, as_select: select_info}}

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
      "VARCHAR2" -> :varchar2
      "VARCHAR" -> :varchar
      "NUMBER" -> :number
      "INTEGER" -> :integer
      "INT" -> :integer
      "DATE" -> :date
      "TIMESTAMP" -> :timestamp
      "CLOB" -> :clob
      "BLOB" -> :blob
      "CHAR" -> :char
      "BOOLEAN" -> :boolean
      "FLOAT" -> :float
      "DOUBLE" -> :double
      "DECIMAL" -> :decimal
      "NUMERIC" -> :numeric
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

      "," ->
        {Enum.reverse(acc), rest}

      ")" ->
        {Enum.reverse(acc), [token | rest]}

      _ ->
        {Enum.reverse(acc), [token | rest]}
    end
  end

  defp parse_column_modifiers(tokens, acc), do: {Enum.reverse(acc), tokens}

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
    # Parse what kind of constraint
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
        ["WITH", value | remaining] = rest
        parse_sequence_options(remaining, Map.put(acc, :start, parse_value(value)))

      "INCREMENT" ->
        ["BY", value | remaining] = rest
        parse_sequence_options(remaining, Map.put(acc, :increment, parse_value(value)))

      "MINVALUE" ->
        [value | remaining] = rest
        parse_sequence_options(remaining, Map.put(acc, :min_value, parse_value(value)))

      "MAXVALUE" ->
        [value | remaining] = rest
        parse_sequence_options(remaining, Map.put(acc, :max_value, parse_value(value)))

      "NOCYCLE" ->
        parse_sequence_options(rest, Map.put(acc, :cycle, false))

      "CYCLE" ->
        parse_sequence_options(rest, Map.put(acc, :cycle, true))

      "NOCACHE" ->
        parse_sequence_options(rest, Map.put(acc, :cache, false))

      "CACHE" ->
        [value | remaining] = rest
        parse_sequence_options(remaining, Map.put(acc, :cache, parse_value(value)))

      _ ->
        parse_sequence_options(rest, acc)
    end
  end

  defp parse_sequence_options([_ | rest], acc) do
    parse_sequence_options(rest, acc)
  end

  # Parse DROP statement
  defp parse_drop(tokens) do
    case tl(tokens) do
      ["TABLE", table | rest] ->
        cascade = "CASCADE" in Enum.map(rest, &String.upcase/1)
        {:drop_table, %{table: table, cascade: cascade}}

      ["INDEX", name | _] ->
        {:drop_index, %{name: name}}

      ["SEQUENCE", name | _] ->
        {:drop_sequence, %{name: name}}

      ["TYPE", name | rest] ->
        force = "FORCE" in Enum.map(rest, &String.upcase/1)
        {:drop_type, %{name: name, force: force}}

      ["VIEW", name | _] ->
        {:drop_view, %{name: name}}

      ["MATERIALIZED", "VIEW", name | _] ->
        {:drop_materialized_view, %{name: name}}

      ["PROCEDURE", name | _] ->
        {:drop_procedure, %{name: name}}

      ["FUNCTION", name | _] ->
        {:drop_function, %{name: name}}

      ["TRIGGER", name | _] ->
        {:drop_trigger, %{name: name}}

      ["PACKAGE", "BODY", name | _] ->
        {:drop_package_body, %{name: name}}

      ["PACKAGE", name | _] ->
        {:drop_package, %{name: name}}

      _ ->
        {:error, "Unknown DROP command"}
    end
  end

  # Parse ALTER statement
  defp parse_alter(tokens) do
    case tl(tokens) do
      ["TABLE" | rest] -> parse_alter_table(rest)
      ["TYPE" | rest] -> parse_alter_type(rest)
      ["VIEW" | rest] -> parse_alter_view(rest)
      ["TRIGGER", name, "ENABLE" | _] -> {:alter_trigger, %{name: name, action: :enable}}
      ["TRIGGER", name, "DISABLE" | _] -> {:alter_trigger, %{name: name, action: :disable}}
      ["TRIGGER", name, "COMPILE" | _] -> {:alter_trigger, %{name: name, action: :compile}}
      ["PROCEDURE", name, "COMPILE" | _] -> {:alter_procedure, %{name: name, action: :compile}}
      ["FUNCTION", name, "COMPILE" | _] -> {:alter_function, %{name: name, action: :compile}}
      ["PACKAGE", name, "COMPILE" | rest] -> parse_alter_package(name, rest)
      _ -> {:error, "Unknown ALTER command"}
    end
  end

  defp parse_alter_package(name, ["BODY" | _]) do
    {:alter_package, %{name: name, action: :compile_body}}
  end

  defp parse_alter_package(name, _rest) do
    {:alter_package, %{name: name, action: :compile}}
  end

  defp parse_alter_view([view_name | rest]) do
    case rest do
      ["COMPILE" | _] ->
        {:alter_view, %{name: view_name, action: :compile}}

      ["ADD", "CONSTRAINT" | constraint_rest] ->
        {:alter_view, %{name: view_name, action: :add_constraint, details: constraint_rest}}

      _ ->
        {:error, "Invalid ALTER VIEW syntax"}
    end
  end

  defp parse_alter_type([type_name | rest]) do
    {action, details} = parse_alter_type_action(rest)
    {:alter_type, %{name: type_name, action: action, details: details}}
  end

  defp parse_alter_type_action(["ADD" | rest]) do
    case rest do
      ["ATTRIBUTE", attr_name, attr_type | remaining] ->
        {type_info, _} = parse_attribute_type([attr_type | remaining])
        {:add_attribute, {attr_name, type_info}}

      ["MEMBER" | method_rest] ->
        {method, _} = parse_type_method(method_rest)
        {:add_method, method}

      _ ->
        {:error, nil}
    end
  end

  defp parse_alter_type_action(["DROP" | rest]) do
    case rest do
      ["ATTRIBUTE", attr_name | _] ->
        {:drop_attribute, attr_name}

      _ ->
        {:error, nil}
    end
  end

  defp parse_alter_type_action(["MODIFY" | rest]) do
    case rest do
      ["ATTRIBUTE", attr_name, attr_type | remaining] ->
        {type_info, _} = parse_attribute_type([attr_type | remaining])
        {:modify_attribute, {attr_name, type_info}}

      _ ->
        {:error, nil}
    end
  end

  defp parse_alter_type_action(_), do: {:error, nil}

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

      ["(" | col_rest] ->
        {col_def, _} = parse_column_def(col_rest)
        {:add_column, col_def}

      _ ->
        {col_def, _} = parse_column_def(rest)
        {:add_column, col_def}
    end
  end

  defp parse_alter_action(["DROP" | rest]) do
    case rest do
      ["COLUMN", col | _] -> {:drop_column, col}
      ["CONSTRAINT", name | _] -> {:drop_constraint, name}
      [col | _] -> {:drop_column, col}
    end
  end

  defp parse_alter_action(["MODIFY" | rest]) do
    case rest do
      ["COLUMN" | col_rest] ->
        {col_def, _} = parse_column_def(col_rest)
        {:modify_column, col_def}

      ["(" | col_rest] ->
        {col_def, _} = parse_column_def(col_rest)
        {:modify_column, col_def}

      _ ->
        {col_def, _} = parse_column_def(rest)
        {:modify_column, col_def}
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

  # Parse CALL statement - CALL procedure_name(arg1, arg2, ...)
  defp parse_call(["CALL" | rest]) do
    parse_call(rest)
  end

  defp parse_call([proc_name | rest]) do
    {args, _remaining} = parse_call_arguments(rest)

    {:call,
     %{
       name: proc_name,
       arguments: args
     }}
  end

  defp parse_call([]) do
    {:error, "Invalid CALL syntax - missing procedure name"}
  end

  # Parse EXECUTE/EXEC statement
  defp parse_execute(["EXECUTE" | rest]) do
    parse_execute_rest(rest)
  end

  defp parse_execute(["EXEC" | rest]) do
    parse_execute_rest(rest)
  end

  defp parse_execute_rest([proc_name | rest]) do
    # Check for function vs procedure
    {args, _remaining} = parse_call_arguments(rest)

    {:execute,
     %{
       name: proc_name,
       arguments: args
     }}
  end

  defp parse_execute_rest([]) do
    {:error, "Invalid EXECUTE syntax - missing procedure/function name"}
  end

  # Parse call arguments (arg1, arg2, ...)
  defp parse_call_arguments(["(" | rest]) do
    parse_call_args_list(rest, [])
  end

  defp parse_call_arguments(_rest) do
    {[], []}
  end

  defp parse_call_args_list([")" | rest], acc) do
    {Enum.reverse(acc), rest}
  end

  defp parse_call_args_list(["," | rest], acc) do
    parse_call_args_list(rest, acc)
  end

  defp parse_call_args_list([{:string, val} | rest], acc) do
    parse_call_args_list(rest, [{:literal, val} | acc])
  end

  defp parse_call_args_list([token | rest], acc) when is_binary(token) do
    value =
      cond do
        String.upcase(token) == "NULL" ->
          {:literal, nil}

        String.match?(token, ~r/^\d+$/) ->
          {:literal, String.to_integer(token)}

        String.match?(token, ~r/^\d+\.\d+$/) ->
          {:literal, String.to_float(token)}

        String.upcase(token) == "TRUE" ->
          {:literal, true}

        String.upcase(token) == "FALSE" ->
          {:literal, false}

        String.starts_with?(token, ":") ->
          # Bind variable reference
          {:bind_var, String.slice(token, 1..-1//1)}

        true ->
          # Could be identifier/variable
          {:identifier, token}
      end

    parse_call_args_list(rest, [value | acc])
  end

  defp parse_call_args_list([], acc) do
    {Enum.reverse(acc), []}
  end

  # Parse anonymous PL/SQL block - BEGIN ... END or DECLARE ... BEGIN ... END
  defp parse_anonymous_block(tokens) do
    # Reconstruct the original text with proper spacing
    body =
      tokens
      |> Enum.map(fn
        {:string, val} -> "'#{val}'"
        token -> token
      end)
      |> Enum.join(" ")

    {:anonymous_block,
     %{
       body: body
     }}
  end
end
