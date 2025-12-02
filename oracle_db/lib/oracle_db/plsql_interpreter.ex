defmodule OracleDb.PlsqlInterpreter do
  @moduledoc """
  PL/SQL Interpreter for executing PL/SQL code blocks, procedures, and functions.

  Supports:
  - Variable declarations and assignments
  - IF/THEN/ELSE/ELSIF statements
  - LOOP/FOR/WHILE loops
  - SELECT INTO statements
  - INSERT/UPDATE/DELETE statements
  - RETURN statements
  - Exception handling
  - DBMS_OUTPUT.PUT_LINE
  """

  alias OracleDb.Storage

  @type exec_result :: {:ok, map()} | {:error, String.t()}
  @type context :: %{
          storage: GenServer.server(),
          variables: map(),
          out_params: map(),
          output: list(),
          return_value: any()
        }

  @doc """
  Executes a PL/SQL block with the given storage server.

  ## Parameters
  - storage: The storage GenServer
  - body: The PL/SQL body text
  - params: A map of input parameter values (optional)
  - param_defs: List of parameter definitions from procedure/function (optional)

  ## Returns
  - {:ok, %{output: [...], out_params: %{}, return_value: value}}
  - {:error, error_message}
  """
  @spec execute(GenServer.server(), String.t(), map(), list()) :: exec_result()
  def execute(storage, body, params \\ %{}, param_defs \\ []) do
    # Initialize context with variables from IN parameters
    initial_vars = initialize_parameters(params, param_defs)

    context = %{
      storage: storage,
      variables: initial_vars,
      out_params: %{},
      output: [],
      return_value: nil
    }

    # Parse and execute the body
    case parse_plsql_body(body) do
      {:ok, statements} ->
        case execute_statements(statements, context) do
          {:ok, final_context} ->
            {:ok,
             %{
               output: Enum.reverse(final_context.output),
               out_params: build_out_params(final_context, param_defs),
               return_value: final_context.return_value
             }}

          {:return, final_context} ->
            {:ok,
             %{
               output: Enum.reverse(final_context.output),
               out_params: build_out_params(final_context, param_defs),
               return_value: final_context.return_value
             }}

          {:error, _} = err ->
            err
        end

      {:error, _} = err ->
        err
    end
  end

  @doc """
  Executes a stored procedure by name with the given arguments.
  """
  @spec execute_procedure(GenServer.server(), String.t(), list()) :: exec_result()
  def execute_procedure(storage, proc_name, args \\ []) do
    case Storage.get_procedure(storage, proc_name) do
      {:ok, proc_def} ->
        params = build_params_from_args(proc_def.parameters, args)
        execute(storage, proc_def.body, params, proc_def.parameters)

      {:error, _} = err ->
        err
    end
  end

  @doc """
  Executes a stored function by name with the given arguments and returns the result.
  """
  @spec execute_function(GenServer.server(), String.t(), list()) ::
          {:ok, any()} | {:error, String.t()}
  def execute_function(storage, func_name, args \\ []) do
    case Storage.get_function(storage, func_name) do
      {:ok, func_def} ->
        params = build_params_from_args(func_def.parameters, args)

        case execute(storage, func_def.body, params, func_def.parameters) do
          {:ok, result} ->
            {:ok, result.return_value}

          {:error, _} = err ->
            err
        end

      {:error, _} = err ->
        err
    end
  end

  # Initialize variables from input parameters
  defp initialize_parameters(params, param_defs) do
    Enum.reduce(param_defs, %{}, fn param, acc ->
      param_name = normalize_var_name(param.name)

      case param.mode do
        :in ->
          Map.put(acc, param_name, Map.get(params, param_name) || Map.get(params, param.name))

        :in_out ->
          Map.put(acc, param_name, Map.get(params, param_name) || Map.get(params, param.name))

        :out ->
          Map.put(acc, param_name, nil)
      end
    end)
  end

  # Build OUT parameter values from final context
  defp build_out_params(context, param_defs) do
    Enum.reduce(param_defs, %{}, fn param, acc ->
      case param.mode do
        mode when mode in [:out, :in_out] ->
          param_name = normalize_var_name(param.name)
          Map.put(acc, param.name, Map.get(context.variables, param_name))

        _ ->
          acc
      end
    end)
  end

  # Build params map from positional arguments
  defp build_params_from_args(param_defs, args) do
    param_defs
    |> Enum.zip(args)
    |> Enum.reduce(%{}, fn {param, value}, acc ->
      Map.put(acc, normalize_var_name(param.name), value)
    end)
  end

  # Normalize variable/parameter names to uppercase
  defp normalize_var_name(name) when is_binary(name) do
    String.upcase(name)
  end

  defp normalize_var_name(name), do: to_string(name) |> normalize_var_name()

  # Parse PL/SQL body into a list of statements
  defp parse_plsql_body(body) when is_binary(body) do
    body = String.trim(body)

    # Handle different PL/SQL block formats
    {declarations, executable} = extract_sections(body)

    declaration_stmts = parse_declarations(declarations)
    executable_stmts = parse_executable_section(executable)

    {:ok, declaration_stmts ++ executable_stmts}
  end

  defp parse_plsql_body(body) do
    IO.puts("[DEBUG plsql_interpreter.ex:parse_plsql_body] Unable to parse PL/SQL body: #{inspect(body)}")
    {:ok, []}
  end

  # Extract DECLARE and BEGIN sections
  defp extract_sections(body) do
    body_upper = String.upcase(body)

    cond do
      # Has explicit DECLARE section
      String.contains?(body_upper, "DECLARE") ->
        case Regex.run(~r/DECLARE\s+(.*?)\s+BEGIN/is, body) do
          [_, decl] ->
            exec = Regex.replace(~r/.*BEGIN/is, body, "", global: false) |> String.trim()
            {decl, exec}

          nil ->
            {"", body}
        end

      # Starts with BEGIN
      String.starts_with?(body_upper, "BEGIN") ->
        exec = String.slice(body, 5..-1//1) |> String.trim()
        {"", exec}

      # Just executable statements
      true ->
        {"", body}
    end
  end

  # Parse DECLARE section
  defp parse_declarations(declarations) when is_binary(declarations) do
    declarations
    |> String.trim()
    |> String.split(";")
    |> Enum.map(&String.trim/1)
    |> Enum.filter(&(&1 != ""))
    |> Enum.map(&parse_declaration/1)
    |> Enum.filter(&(&1 != nil))
  end

  defp parse_declaration(decl) do
    # Variable declaration: var_name type [:= default_value]
    case Regex.run(~r/^(\w+)\s+(\w+)(?:\([^)]*\))?\s*(?::=\s*(.+))?$/is, decl) do
      [_, var_name, _type, default_value] ->
        {:declare, String.upcase(var_name), parse_value(String.trim(default_value))}

      [_, var_name, _type] ->
        {:declare, String.upcase(var_name), nil}

      nil ->
        nil
    end
  end

  # Parse executable section into statements
  defp parse_executable_section(body) when is_binary(body) do
    # Remove trailing END keyword
    body = Regex.replace(~r/\s*END\s*;?\s*$/is, body, "")

    # Handle exception section
    {main_body, exception_handlers} = extract_exception_section(body)

    statements = parse_statements(main_body)

    if exception_handlers != "" do
      [{:try, statements, parse_exception_handlers(exception_handlers)}]
    else
      statements
    end
  end

  defp extract_exception_section(body) do
    case Regex.run(~r/(.*)EXCEPTION\s+(.*)/is, body) do
      [_, main, handlers] -> {String.trim(main), String.trim(handlers)}
      nil -> {body, ""}
    end
  end

  defp parse_exception_handlers(handlers) do
    # Parse WHEN clauses
    handlers
    |> String.split(~r/\bWHEN\b/i)
    |> Enum.map(&String.trim/1)
    |> Enum.filter(&(&1 != ""))
    |> Enum.map(&parse_exception_handler/1)
  end

  defp parse_exception_handler(handler) do
    case Regex.run(~r/^(\w+)\s+THEN\s+(.+)$/is, handler) do
      [_, exception_name, handler_body] ->
        {String.upcase(exception_name), parse_statements(handler_body)}

      nil ->
        {:others, parse_statements(handler)}
    end
  end

  # Parse a block of statements
  defp parse_statements(body) when is_binary(body) do
    body
    |> split_statements()
    |> Enum.map(&parse_statement/1)
    |> Enum.filter(&(&1 != nil))
  end

  # Split body into individual statements, respecting nested blocks
  defp split_statements(body) do
    # Simple split by semicolon - this handles most cases
    # For complex nested blocks, we need more sophisticated parsing

    # First, replace string literals with placeholders to avoid splitting on semicolons inside strings
    {processed, literals} = replace_string_literals(body)

    # Group statements respecting block structure
    statements =
      processed
      |> group_statements()
      |> Enum.map(&String.trim/1)
      |> Enum.filter(&(&1 != ""))

    # Restore string literals in each statement
    Enum.map(statements, fn stmt -> restore_string_literals(stmt, literals) end)
  end

  defp replace_string_literals(body) do
    # Replace string literals with placeholders
    {result, literals} =
      Regex.scan(~r/'[^']*'/, body)
      |> Enum.with_index()
      |> Enum.reduce({body, %{}}, fn {[match], idx}, {text, lits} ->
        placeholder = "~STRLIT#{idx}~"

        {String.replace(text, match, placeholder, global: false),
         Map.put(lits, placeholder, match)}
      end)

    {result, literals}
  end

  defp restore_string_literals(text, literals) do
    Enum.reduce(literals, text, fn {placeholder, original}, acc ->
      String.replace(acc, placeholder, original)
    end)
  end

  defp group_statements(body) do
    # Handle nested IF/LOOP/CASE blocks
    {statements, _depth, current} =
      body
      |> String.split(";")
      |> Enum.reduce({[], 0, ""}, fn part, {stmts, depth, current} ->
        part_upper = String.upcase(part)

        # Count block starters and enders
        start_count = count_block_starters(part_upper)
        end_count = count_block_enders(part_upper)

        new_depth = depth + start_count - end_count

        cond do
          new_depth <= 0 and depth > 0 ->
            # End of a block - reset depth to 0
            {stmts ++ [current <> ";" <> part], 0, ""}

          new_depth > 0 ->
            # Starting or inside a block
            {stmts, new_depth, current <> if(current == "", do: "", else: ";") <> part}

          depth > 0 ->
            # Still accumulating within a block (even if new_depth went negative temporarily)
            {stmts, depth, current <> if(current == "", do: "", else: ";") <> part}

          true ->
            # Regular statement at top level
            {stmts ++ [part], 0, ""}
        end
      end)

    # Add any remaining statement
    if current != "", do: statements ++ [current], else: statements
  end

  defp count_block_starters(text) do
    # Count IF (but not END IF), LOOP (but not END LOOP), CASE (but not END CASE), BEGIN (but not END)
    # We need to be careful not to count LOOP in "END LOOP" as a starter
    # Only count IF when followed by space (to avoid IF within END IF)
    if_count = length(Regex.scan(~r/\bIF\s+/, text)) - length(Regex.scan(~r/\bEND\s+IF\b/, text))

    loop_count =
      length(Regex.scan(~r/\bLOOP\b/, text)) - length(Regex.scan(~r/\bEND\s+LOOP\b/, text))

    case_count =
      length(Regex.scan(~r/\bCASE\b/, text)) - length(Regex.scan(~r/\bEND\s+CASE\b/, text))

    begin_count = length(Regex.scan(~r/\bBEGIN\b/, text))
    max(0, if_count) + max(0, loop_count) + max(0, case_count) + max(0, begin_count)
  end

  defp count_block_enders(text) do
    length(Regex.scan(~r/\bEND\s*(IF|LOOP|CASE)?\b/i, text))
  end

  # Parse individual statement
  defp parse_statement(stmt) when is_binary(stmt) do
    stmt = String.trim(stmt)
    stmt_upper = String.upcase(stmt)

    cond do
      stmt == "" or stmt == "NULL" or stmt_upper == "NULL" ->
        {:null}

      String.starts_with?(stmt_upper, "IF ") ->
        parse_if_statement(stmt)

      String.starts_with?(stmt_upper, "LOOP") ->
        parse_loop_statement(stmt)

      String.starts_with?(stmt_upper, "WHILE ") ->
        parse_while_statement(stmt)

      String.starts_with?(stmt_upper, "FOR ") ->
        parse_for_statement(stmt)

      String.starts_with?(stmt_upper, "RETURN") ->
        parse_return_statement(stmt)

      String.starts_with?(stmt_upper, "SELECT ") ->
        parse_select_into_statement(stmt)

      String.starts_with?(stmt_upper, "INSERT ") ->
        parse_dml_statement(stmt, :insert)

      String.starts_with?(stmt_upper, "UPDATE ") ->
        parse_dml_statement(stmt, :update)

      String.starts_with?(stmt_upper, "DELETE ") ->
        parse_dml_statement(stmt, :delete)

      String.starts_with?(stmt_upper, "DBMS_OUTPUT.PUT_LINE") ->
        parse_dbms_output(stmt)

      String.starts_with?(stmt_upper, "RAISE") ->
        parse_raise_statement(stmt)

      String.contains?(stmt, ":=") ->
        parse_assignment(stmt)

      true ->
        # Unknown statement, try to execute as-is
        {:unknown, stmt}
    end
  end

  defp parse_statement(stmt) do
    IO.puts("[DEBUG plsql_interpreter.ex:parse_statement] Unable to parse statement: #{inspect(stmt)}")
    nil
  end

  # Parse assignment statement: var := expression
  defp parse_assignment(stmt) do
    case String.split(stmt, ":=", parts: 2) do
      [var, expr] ->
        {:assign, String.upcase(String.trim(var)), parse_expression(String.trim(expr))}

      _ ->
        {:unknown, stmt}
    end
  end

  # Parse expression (simplified for common cases)
  defp parse_expression(expr) do
    expr = String.trim(expr)

    cond do
      # String literal
      String.starts_with?(expr, "'") and String.ends_with?(expr, "'") ->
        {:literal, String.slice(expr, 1..-2//1)}

      # Numeric literal
      Regex.match?(~r/^-?\d+(\.\d+)?$/, expr) ->
        {:literal, parse_number(expr)}

      # NULL
      String.upcase(expr) == "NULL" ->
        {:literal, nil}

      # Boolean literals
      String.upcase(expr) == "TRUE" ->
        {:literal, true}

      String.upcase(expr) == "FALSE" ->
        {:literal, false}

      # Function call
      Regex.match?(~r/^\w+\s*\(.*\)$/s, expr) ->
        parse_function_call(expr)

      # String concatenation with ||
      String.contains?(expr, "||") ->
        {:concat, String.split(expr, "||") |> Enum.map(&parse_expression(String.trim(&1)))}

      # Arithmetic expression
      Regex.match?(~r/[\+\-\*\/]/, expr) ->
        parse_arithmetic_expression(expr)

      # Variable reference (might include :OLD. or :NEW. prefixes for triggers)
      String.starts_with?(String.upcase(expr), ":OLD.") ->
        {:old_value, String.slice(expr, 5..-1//1) |> String.upcase()}

      String.starts_with?(String.upcase(expr), ":NEW.") ->
        {:new_value, String.slice(expr, 5..-1//1) |> String.upcase()}

      # Simple variable reference
      true ->
        {:var, String.upcase(expr)}
    end
  end

  defp parse_number(str) do
    if String.contains?(str, ".") do
      String.to_float(str)
    else
      String.to_integer(str)
    end
  end

  defp parse_function_call(expr) do
    case Regex.run(~r/^(\w+)\s*\((.*)\)$/s, expr) do
      [_, func_name, args_str] ->
        args = parse_function_args(args_str)
        {:function_call, String.upcase(func_name), args}

      _ ->
        {:var, String.upcase(expr)}
    end
  end

  defp parse_function_args(args_str) do
    args_str
    |> String.split(",")
    |> Enum.map(&String.trim/1)
    |> Enum.filter(&(&1 != ""))
    |> Enum.map(&parse_expression/1)
  end

  defp parse_arithmetic_expression(expr) do
    # Simple parsing - handles basic arithmetic
    cond do
      String.contains?(expr, "+") ->
        [left, right] = String.split(expr, "+", parts: 2)
        {:add, parse_expression(left), parse_expression(right)}

      String.contains?(expr, "-") and not String.starts_with?(expr, "-") ->
        [left, right] = String.split(expr, "-", parts: 2)
        {:subtract, parse_expression(left), parse_expression(right)}

      String.contains?(expr, "*") ->
        [left, right] = String.split(expr, "*", parts: 2)
        {:multiply, parse_expression(left), parse_expression(right)}

      String.contains?(expr, "/") ->
        [left, right] = String.split(expr, "/", parts: 2)
        {:divide, parse_expression(left), parse_expression(right)}

      true ->
        {:var, String.upcase(expr)}
    end
  end

  # Parse IF statement
  defp parse_if_statement(stmt) do
    # Extract condition and blocks
    case Regex.run(~r/IF\s+(.+?)\s+THEN\s+(.+?)(?:\s+ELSE\s+(.+?))?\s*END\s+IF/is, stmt) do
      [_, condition, then_block, else_block] ->
        {:if, parse_condition(condition), parse_statements(then_block),
         parse_statements(else_block)}

      [_, condition, then_block] ->
        # Check for ELSIF
        case Regex.run(~r/IF\s+(.+?)\s+THEN\s+(.+?)\s+ELSIF\s+(.+)/is, stmt) do
          [_, cond, then_block2, elsif_rest] ->
            {:if, parse_condition(cond), parse_statements(then_block2),
             [parse_if_statement("IF " <> elsif_rest <> " END IF")]}

          nil ->
            {:if, parse_condition(condition), parse_statements(then_block), []}
        end

      nil ->
        {:unknown, stmt}
    end
  end

  defp parse_condition(condition) do
    condition = String.trim(condition)

    cond do
      # AND condition
      Regex.match?(~r/\bAND\b/i, condition) ->
        [left, right] = String.split(condition, ~r/\bAND\b/i, parts: 2)
        {:and, parse_condition(left), parse_condition(right)}

      # OR condition
      Regex.match?(~r/\bOR\b/i, condition) ->
        [left, right] = String.split(condition, ~r/\bOR\b/i, parts: 2)
        {:or, parse_condition(left), parse_condition(right)}

      # NOT condition
      String.upcase(condition) |> String.starts_with?("NOT ") ->
        {:not, parse_condition(String.slice(condition, 4..-1//1))}

      # IS NULL
      Regex.match?(~r/\bIS\s+NULL\b/i, condition) ->
        [var | _] = String.split(condition, ~r/\bIS\s+NULL\b/i)
        {:is_null, parse_expression(String.trim(var))}

      # IS NOT NULL
      Regex.match?(~r/\bIS\s+NOT\s+NULL\b/i, condition) ->
        [var | _] = String.split(condition, ~r/\bIS\s+NOT\s+NULL\b/i)
        {:is_not_null, parse_expression(String.trim(var))}

      # Comparison operators
      Regex.match?(~r/>=|<=|<>|!=|>|<|=/, condition) ->
        parse_comparison_condition(condition)

      # Boolean expression
      true ->
        parse_expression(condition)
    end
  end

  defp parse_comparison_condition(condition) do
    cond do
      String.contains?(condition, ">=") ->
        [left, right] = String.split(condition, ">=", parts: 2)
        {:comparison, :gte, parse_expression(left), parse_expression(right)}

      String.contains?(condition, "<=") ->
        [left, right] = String.split(condition, "<=", parts: 2)
        {:comparison, :lte, parse_expression(left), parse_expression(right)}

      String.contains?(condition, "<>") ->
        [left, right] = String.split(condition, "<>", parts: 2)
        {:comparison, :neq, parse_expression(left), parse_expression(right)}

      String.contains?(condition, "!=") ->
        [left, right] = String.split(condition, "!=", parts: 2)
        {:comparison, :neq, parse_expression(left), parse_expression(right)}

      String.contains?(condition, ">") ->
        [left, right] = String.split(condition, ">", parts: 2)
        {:comparison, :gt, parse_expression(left), parse_expression(right)}

      String.contains?(condition, "<") ->
        [left, right] = String.split(condition, "<", parts: 2)
        {:comparison, :lt, parse_expression(left), parse_expression(right)}

      String.contains?(condition, "=") ->
        [left, right] = String.split(condition, "=", parts: 2)
        {:comparison, :eq, parse_expression(left), parse_expression(right)}

      true ->
        parse_expression(condition)
    end
  end

  # Parse LOOP statement
  defp parse_loop_statement(stmt) do
    case Regex.run(~r/LOOP\s+(.+?)\s+END\s+LOOP/is, stmt) do
      [_, body] ->
        {:loop, parse_statements(body)}

      nil ->
        {:unknown, stmt}
    end
  end

  # Parse WHILE statement
  defp parse_while_statement(stmt) do
    case Regex.run(~r/WHILE\s+(.+?)\s+LOOP\s+(.+?)\s+END\s+LOOP/is, stmt) do
      [_, condition, body] ->
        {:while, parse_condition(condition), parse_statements(body)}

      nil ->
        {:unknown, stmt}
    end
  end

  # Parse FOR statement
  defp parse_for_statement(stmt) do
    case Regex.run(
           ~r/FOR\s+(\w+)\s+IN\s+(\d+)\s*\.\.\s*(\d+)\s+LOOP\s+(.+?)\s+END\s+LOOP/is,
           stmt
         ) do
      [_, var, start_val, end_val, body] ->
        {:for, String.upcase(var), String.to_integer(start_val), String.to_integer(end_val),
         parse_statements(body)}

      nil ->
        # Try parsing FOR with REVERSE
        case Regex.run(
               ~r/FOR\s+(\w+)\s+IN\s+REVERSE\s+(\d+)\s*\.\.\s*(\d+)\s+LOOP\s+(.+?)\s+END\s+LOOP/is,
               stmt
             ) do
          [_, var, start_val, end_val, body] ->
            {:for_reverse, String.upcase(var), String.to_integer(start_val),
             String.to_integer(end_val), parse_statements(body)}

          nil ->
            {:unknown, stmt}
        end
    end
  end

  # Parse RETURN statement
  defp parse_return_statement(stmt) do
    case Regex.run(~r/RETURN\s*(.*)/is, stmt) do
      [_, ""] ->
        {:return, nil}

      [_, expr] ->
        {:return, parse_expression(String.trim(expr))}

      nil ->
        {:return, nil}
    end
  end

  # Parse SELECT INTO statement
  defp parse_select_into_statement(stmt) do
    case Regex.run(~r/SELECT\s+(.+?)\s+INTO\s+(.+?)\s+FROM\s+(.+)/is, stmt) do
      [_, columns, vars, rest] ->
        column_list = String.split(columns, ",") |> Enum.map(&String.trim/1)
        var_list = String.split(vars, ",") |> Enum.map(&(String.trim(&1) |> String.upcase()))
        {:select_into, column_list, var_list, "SELECT " <> columns <> " FROM " <> rest}

      nil ->
        {:unknown, stmt}
    end
  end

  # Parse DML statements
  defp parse_dml_statement(stmt, type) do
    {:dml, type, stmt}
  end

  # Parse DBMS_OUTPUT.PUT_LINE
  defp parse_dbms_output(stmt) do
    case Regex.run(~r/DBMS_OUTPUT\.PUT_LINE\s*\(\s*(.+)\s*\)/is, stmt) do
      [_, arg] ->
        {:dbms_output_put_line, parse_expression(arg)}

      nil ->
        {:unknown, stmt}
    end
  end

  # Parse RAISE statement
  defp parse_raise_statement(stmt) do
    case Regex.run(~r/RAISE\s+(\w+)/i, stmt) do
      [_, exception_name] ->
        {:raise, String.upcase(exception_name)}

      nil ->
        {:raise, "PROGRAM_ERROR"}
    end
  end

  # Parse a value
  defp parse_value(nil), do: nil
  defp parse_value(""), do: nil

  defp parse_value(value) when is_binary(value) do
    value = String.trim(value)

    cond do
      String.starts_with?(value, "'") and String.ends_with?(value, "'") ->
        String.slice(value, 1..-2//1)

      Regex.match?(~r/^\d+$/, value) ->
        String.to_integer(value)

      Regex.match?(~r/^\d+\.\d+$/, value) ->
        String.to_float(value)

      String.upcase(value) == "NULL" ->
        nil

      String.upcase(value) == "TRUE" ->
        true

      String.upcase(value) == "FALSE" ->
        false

      true ->
        value
    end
  end

  # Execute a list of statements
  defp execute_statements([], context), do: {:ok, context}

  defp execute_statements([stmt | rest], context) do
    case execute_statement(stmt, context) do
      {:ok, new_context} ->
        execute_statements(rest, new_context)

      {:return, _} = ret ->
        ret

      {:exit_loop, new_context} ->
        {:ok, new_context}

      {:continue_loop, new_context} ->
        {:ok, new_context}

      {:error, _} = err ->
        err
    end
  end

  # Execute a single statement
  defp execute_statement({:null}, context) do
    {:ok, context}
  end

  defp execute_statement({:declare, var_name, default_value}, context) do
    new_vars = Map.put(context.variables, var_name, default_value)
    {:ok, %{context | variables: new_vars}}
  end

  defp execute_statement({:assign, var_name, expr}, context) do
    case evaluate_expression(expr, context) do
      {:ok, value} ->
        new_vars = Map.put(context.variables, var_name, value)
        {:ok, %{context | variables: new_vars}}

      {:error, _} = err ->
        err
    end
  end

  defp execute_statement({:if, condition, then_stmts, else_stmts}, context) do
    case evaluate_condition(condition, context) do
      {:ok, true} ->
        execute_statements(then_stmts, context)

      {:ok, false} ->
        execute_statements(else_stmts, context)

      {:error, _} = err ->
        err
    end
  end

  defp execute_statement({:loop, body}, context) do
    execute_loop(body, context, :infinite)
  end

  defp execute_statement({:while, condition, body}, context) do
    execute_while_loop(condition, body, context)
  end

  defp execute_statement({:for, var, start_val, end_val, body}, context) do
    execute_for_loop(var, start_val, end_val, body, context, :forward)
  end

  defp execute_statement({:for_reverse, var, start_val, end_val, body}, context) do
    execute_for_loop(var, start_val, end_val, body, context, :reverse)
  end

  defp execute_statement({:return, nil}, context) do
    {:return, context}
  end

  defp execute_statement({:return, expr}, context) do
    case evaluate_expression(expr, context) do
      {:ok, value} ->
        {:return, %{context | return_value: value}}

      {:error, _} = err ->
        err
    end
  end

  defp execute_statement({:select_into, columns, vars, sql}, context) do
    case execute_sql_query(sql, context) do
      {:ok, [row | _]} ->
        # Assign values to variables
        new_vars =
          Enum.zip(vars, columns)
          |> Enum.reduce(context.variables, fn {var, col}, acc ->
            # Handle column value extraction
            value = get_row_value(row, col)
            Map.put(acc, var, value)
          end)

        {:ok, %{context | variables: new_vars}}

      {:ok, []} ->
        # No data found - would raise NO_DATA_FOUND in Oracle
        {:error, "NO_DATA_FOUND"}

      {:error, _} = err ->
        err
    end
  end

  defp execute_statement({:dml, _type, sql}, context) do
    # Execute DML statement using the query executor
    case substitute_variables(sql, context) do
      {:ok, substituted_sql} ->
        case OracleDb.QueryExecutor.execute(context.storage, substituted_sql) do
          {:ok, _} -> {:ok, context}
          {:error, _} = err -> err
        end

      {:error, _} = err ->
        err
    end
  end

  defp execute_statement({:dbms_output_put_line, expr}, context) do
    case evaluate_expression(expr, context) do
      {:ok, value} ->
        output_line = to_string(value)
        {:ok, %{context | output: [output_line | context.output]}}

      {:error, _} = err ->
        err
    end
  end

  defp execute_statement({:raise, exception_name}, _context) do
    {:error, exception_name}
  end

  defp execute_statement({:try, statements, handlers}, context) do
    case execute_statements(statements, context) do
      {:ok, _} = result ->
        result

      {:return, _} = result ->
        result

      {:error, error_name} ->
        # Find matching handler
        handler =
          Enum.find(handlers, fn {name, _} ->
            name == error_name or name == :others or String.upcase(to_string(name)) == "OTHERS"
          end)

        case handler do
          {_, handler_stmts} -> execute_statements(handler_stmts, context)
          nil -> {:error, error_name}
        end
    end
  end

  defp execute_statement({:unknown, _stmt}, context) do
    # Skip unknown statements
    {:ok, context}
  end

  defp execute_statement(_, context) do
    {:ok, context}
  end

  # Execute SQL query and return results
  defp execute_sql_query(sql, context) do
    case substitute_variables(sql, context) do
      {:ok, substituted_sql} ->
        OracleDb.QueryExecutor.execute(context.storage, substituted_sql)

      {:error, _} = err ->
        err
    end
  end

  # Substitute PL/SQL variables in SQL
  defp substitute_variables(sql, context) do
    # Replace :variable_name with actual values
    result =
      Regex.replace(~r/:(\w+)/, sql, fn _, var_name ->
        key = String.upcase(var_name)

        case Map.fetch(context.variables, key) do
          {:ok, value} -> format_sql_value(value)
          :error -> ":#{var_name}"
        end
      end)

    {:ok, result}
  end

  defp format_sql_value(nil), do: "NULL"
  defp format_sql_value(value) when is_binary(value), do: "'#{value}'"
  defp format_sql_value(value) when is_number(value), do: to_string(value)
  defp format_sql_value(true), do: "1"
  defp format_sql_value(false), do: "0"
  defp format_sql_value(value), do: "'#{value}'"

  # Get value from row (handles case-insensitive column names)
  defp get_row_value(row, col) when is_map(row) do
    col_upper = String.upcase(col)

    Enum.find_value(row, fn {k, v} ->
      if String.upcase(to_string(k)) == col_upper, do: v
    end)
  end

  # Evaluate expression
  defp evaluate_expression({:literal, value}, _context), do: {:ok, value}

  defp evaluate_expression({:var, var_name}, context) do
    case Map.fetch(context.variables, var_name) do
      {:ok, value} -> {:ok, value}
      # Undefined variable returns NULL
      :error -> {:ok, nil}
    end
  end

  defp evaluate_expression({:concat, exprs}, context) do
    results =
      Enum.map(exprs, fn expr ->
        case evaluate_expression(expr, context) do
          {:ok, nil} -> ""
          {:ok, value} -> to_string(value)
          {:error, _} -> ""
        end
      end)

    {:ok, Enum.join(results)}
  end

  defp evaluate_expression({:add, left, right}, context) do
    with {:ok, left_val} <- evaluate_expression(left, context),
         {:ok, right_val} <- evaluate_expression(right, context) do
      {:ok, (left_val || 0) + (right_val || 0)}
    end
  end

  defp evaluate_expression({:subtract, left, right}, context) do
    with {:ok, left_val} <- evaluate_expression(left, context),
         {:ok, right_val} <- evaluate_expression(right, context) do
      {:ok, (left_val || 0) - (right_val || 0)}
    end
  end

  defp evaluate_expression({:multiply, left, right}, context) do
    with {:ok, left_val} <- evaluate_expression(left, context),
         {:ok, right_val} <- evaluate_expression(right, context) do
      {:ok, (left_val || 0) * (right_val || 0)}
    end
  end

  defp evaluate_expression({:divide, left, right}, context) do
    with {:ok, left_val} <- evaluate_expression(left, context),
         {:ok, right_val} <- evaluate_expression(right, context) do
      if right_val == 0 or right_val == nil do
        {:error, "ZERO_DIVIDE"}
      else
        {:ok, (left_val || 0) / right_val}
      end
    end
  end

  defp evaluate_expression({:function_call, func_name, args}, context) do
    evaluated_args =
      Enum.map(args, fn arg ->
        case evaluate_expression(arg, context) do
          {:ok, value} -> value
          {:error, _} -> nil
        end
      end)

    result = evaluate_function(func_name, evaluated_args, context)
    {:ok, result}
  end

  defp evaluate_expression({:old_value, col_name}, context) do
    # For triggers - get :OLD value
    case Map.fetch(context.variables, "__OLD__") do
      {:ok, old_row} -> {:ok, get_row_value(old_row, col_name)}
      :error -> {:ok, nil}
    end
  end

  defp evaluate_expression({:new_value, col_name}, context) do
    # For triggers - get :NEW value
    case Map.fetch(context.variables, "__NEW__") do
      {:ok, new_row} -> {:ok, get_row_value(new_row, col_name)}
      :error -> {:ok, nil}
    end
  end

  defp evaluate_expression(_, _context), do: {:ok, nil}

  # Evaluate built-in functions
  defp evaluate_function("UPPER", [arg | _], _context) when is_binary(arg) do
    String.upcase(arg)
  end

  defp evaluate_function("LOWER", [arg | _], _context) when is_binary(arg) do
    String.downcase(arg)
  end

  defp evaluate_function("LENGTH", [arg | _], _context) when is_binary(arg) do
    String.length(arg)
  end

  defp evaluate_function("SUBSTR", [str, start | rest], _context) when is_binary(str) do
    start_idx = (start || 1) - 1

    length =
      case rest do
        [len | _] -> len
        [] -> String.length(str) - start_idx
      end

    String.slice(str, start_idx, length || String.length(str))
  end

  defp evaluate_function("TRIM", [arg | _], _context) when is_binary(arg) do
    String.trim(arg)
  end

  defp evaluate_function("LTRIM", [arg | _], _context) when is_binary(arg) do
    String.trim_leading(arg)
  end

  defp evaluate_function("RTRIM", [arg | _], _context) when is_binary(arg) do
    String.trim_trailing(arg)
  end

  defp evaluate_function("NVL", [val, default | _], _context) do
    if val == nil, do: default, else: val
  end

  defp evaluate_function("NVL2", [val, not_null_val, null_val | _], _context) do
    if val == nil, do: null_val, else: not_null_val
  end

  defp evaluate_function("COALESCE", args, _context) do
    Enum.find(args, &(&1 != nil))
  end

  defp evaluate_function("TO_CHAR", [arg | _], _context) do
    to_string(arg)
  end

  defp evaluate_function("TO_NUMBER", [arg | _], _context) when is_binary(arg) do
    case Float.parse(arg) do
      {f, _} ->
        f

      :error ->
        case Integer.parse(arg) do
          {i, _} -> i
          :error -> nil
        end
    end
  end

  defp evaluate_function("TO_NUMBER", [arg | _], _context) when is_number(arg), do: arg

  defp evaluate_function("ROUND", [num | rest], _context) when is_number(num) do
    decimals =
      case rest do
        [d | _] when is_integer(d) -> d
        _ -> 0
      end

    Float.round(num * 1.0, decimals)
  end

  defp evaluate_function("TRUNC", [num | rest], _context) when is_number(num) do
    decimals =
      case rest do
        [d | _] when is_integer(d) -> d
        _ -> 0
      end

    trunc(num * :math.pow(10, decimals)) / :math.pow(10, decimals)
  end

  defp evaluate_function("ABS", [num | _], _context) when is_number(num), do: abs(num)

  defp evaluate_function("MOD", [num, divisor | _], _context)
       when is_number(num) and is_number(divisor) do
    rem(num, divisor)
  end

  defp evaluate_function("SYSDATE", _, _context), do: Date.utc_today()

  defp evaluate_function(func_name, args, _context) do
    IO.puts("[DEBUG plsql_interpreter.ex:evaluate_function] Unhandled function: #{inspect(func_name)} with args: #{inspect(args)}")
    nil
  end

  # Evaluate condition
  defp evaluate_condition({:comparison, op, left, right}, context) do
    with {:ok, left_val} <- evaluate_expression(left, context),
         {:ok, right_val} <- evaluate_expression(right, context) do
      result =
        case op do
          :eq -> compare_values(left_val, right_val) == :eq
          :neq -> compare_values(left_val, right_val) != :eq
          :gt -> compare_values(left_val, right_val) == :gt
          :lt -> compare_values(left_val, right_val) == :lt
          :gte -> compare_values(left_val, right_val) in [:gt, :eq]
          :lte -> compare_values(left_val, right_val) in [:lt, :eq]
        end

      {:ok, result}
    end
  end

  defp evaluate_condition({:and, left, right}, context) do
    with {:ok, left_val} <- evaluate_condition(left, context),
         {:ok, right_val} <- evaluate_condition(right, context) do
      {:ok, left_val and right_val}
    end
  end

  defp evaluate_condition({:or, left, right}, context) do
    with {:ok, left_val} <- evaluate_condition(left, context),
         {:ok, right_val} <- evaluate_condition(right, context) do
      {:ok, left_val or right_val}
    end
  end

  defp evaluate_condition({:not, condition}, context) do
    case evaluate_condition(condition, context) do
      {:ok, value} -> {:ok, not value}
      error -> error
    end
  end

  defp evaluate_condition({:is_null, expr}, context) do
    case evaluate_expression(expr, context) do
      {:ok, nil} -> {:ok, true}
      {:ok, _} -> {:ok, false}
      error -> error
    end
  end

  defp evaluate_condition({:is_not_null, expr}, context) do
    case evaluate_expression(expr, context) do
      {:ok, nil} -> {:ok, false}
      {:ok, _} -> {:ok, true}
      error -> error
    end
  end

  defp evaluate_condition({:literal, value}, _context) do
    {:ok, value == true or (value != 0 and value != nil and value != "")}
  end

  defp evaluate_condition({:var, var_name}, context) do
    case Map.fetch(context.variables, var_name) do
      {:ok, value} -> {:ok, value == true or (is_number(value) and value != 0)}
      :error -> {:ok, false}
    end
  end

  defp evaluate_condition(_, _context), do: {:ok, false}

  defp compare_values(nil, nil), do: :eq
  defp compare_values(nil, _), do: :lt
  defp compare_values(_, nil), do: :gt

  defp compare_values(a, b) when is_binary(a) and is_binary(b) do
    ua = String.upcase(a)
    ub = String.upcase(b)

    cond do
      ua == ub -> :eq
      ua < ub -> :lt
      true -> :gt
    end
  end

  defp compare_values(a, b) when is_number(a) and is_number(b) do
    cond do
      a == b -> :eq
      a < b -> :lt
      true -> :gt
    end
  end

  defp compare_values(a, b) do
    cond do
      a == b -> :eq
      a < b -> :lt
      true -> :gt
    end
  end

  # Execute infinite loop
  defp execute_loop(body, context, :infinite) do
    case execute_statements(body, context) do
      {:ok, new_context} ->
        execute_loop(body, new_context, :infinite)

      {:exit_loop, new_context} ->
        {:ok, new_context}

      {:return, _} = ret ->
        ret

      {:error, _} = err ->
        err
    end
  end

  # Execute WHILE loop
  defp execute_while_loop(condition, body, context) do
    case evaluate_condition(condition, context) do
      {:ok, true} ->
        case execute_statements(body, context) do
          {:ok, new_context} ->
            execute_while_loop(condition, body, new_context)

          {:exit_loop, new_context} ->
            {:ok, new_context}

          {:continue_loop, new_context} ->
            execute_while_loop(condition, body, new_context)

          {:return, _} = ret ->
            ret

          {:error, _} = err ->
            err
        end

      {:ok, false} ->
        {:ok, context}

      {:error, _} = err ->
        err
    end
  end

  # Execute FOR loop
  defp execute_for_loop(var, start_val, end_val, body, context, direction) do
    range =
      case direction do
        :forward -> start_val..end_val
        :reverse -> end_val..start_val//-1
      end

    execute_for_loop_iter(var, Enum.to_list(range), body, context)
  end

  defp execute_for_loop_iter(_var, [], _body, context), do: {:ok, context}

  defp execute_for_loop_iter(var, [i | rest], body, context) do
    new_vars = Map.put(context.variables, var, i)
    new_context = %{context | variables: new_vars}

    case execute_statements(body, new_context) do
      {:ok, updated_context} ->
        execute_for_loop_iter(var, rest, body, updated_context)

      {:exit_loop, updated_context} ->
        {:ok, updated_context}

      {:continue_loop, updated_context} ->
        execute_for_loop_iter(var, rest, body, updated_context)

      {:return, _} = ret ->
        ret

      {:error, _} = err ->
        err
    end
  end
end
