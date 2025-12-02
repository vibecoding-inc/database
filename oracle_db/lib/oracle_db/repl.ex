defmodule OracleDb.Repl do
  @moduledoc """
  Interactive REPL (Read-Eval-Print Loop) for OracleDb.

  Provides a command-line interface for executing SQL statements against
  an in-memory Oracle-compatible database.

  ## Commands

  - `.help` - Show available commands
  - `.tables` - List all tables
  - `.schema <table>` - Show table schema
  - `.types` - List all user-defined types
  - `.views` - List all views
  - `.sequences` - List all sequences (coming soon)
  - `.clear` - Clear the screen
  - `.exit` or `.quit` - Exit the REPL
  - Any SQL statement - Execute against the database

  ## Examples

      $ oracle_db
      OracleDb REPL v0.1.0
      Type .help for available commands, .exit to quit.

      oracle> CREATE TABLE users (id NUMBER, name VARCHAR2(100));
      OK: Table USERS created

      oracle> INSERT INTO users VALUES (1, 'Alice');
      OK: 1 row(s) inserted

      oracle> SELECT * FROM users;
      +----+-------+
      | ID | NAME  |
      +----+-------+
      | 1  | Alice |
      +----+-------+
      1 row(s) returned

  """

  @version Mix.Project.config()[:version] || "0.1.0"
  @prompt "oracle> "

  @doc """
  Main entry point for the escript.
  """
  def main(_args \\ []) do
    IO.puts("OracleDb REPL v#{@version}")
    IO.puts("Type .help for available commands, .exit to quit.")
    IO.puts("")

    {:ok, db} = OracleDb.start_link()
    loop(db)
  end

  @doc """
  Starts the REPL with an existing database connection.
  """
  def start(db) do
    IO.puts("OracleDb REPL v#{@version}")
    IO.puts("Type .help for available commands, .exit to quit.")
    IO.puts("")
    loop(db)
  end

  defp loop(db) do
    case IO.gets(@prompt) do
      :eof ->
        IO.puts("\nGoodbye!")
        :ok

      {:error, reason} ->
        IO.puts("Error reading input: #{inspect(reason)}")
        :ok

      input when is_binary(input) ->
        input = String.trim(input)

        case process_input(db, input) do
          :exit ->
            IO.puts("Goodbye!")
            :ok

          :continue ->
            loop(db)
        end
    end
  end

  defp process_input(_db, ""), do: :continue

  defp process_input(_db, ".exit"), do: :exit
  defp process_input(_db, ".quit"), do: :exit

  defp process_input(_db, ".help") do
    print_help()
    :continue
  end

  defp process_input(_db, ".clear") do
    IO.write(IO.ANSI.clear() <> IO.ANSI.home())
    :continue
  end

  defp process_input(db, ".tables") do
    tables = OracleDb.list_tables(db)

    if length(tables) == 0 do
      IO.puts("No tables.")
    else
      IO.puts("Tables:")
      Enum.each(tables, fn table -> IO.puts("  #{table}") end)
    end

    :continue
  end

  defp process_input(db, ".schema " <> table_name) do
    table_name = String.trim(table_name)

    case OracleDb.get_schema(db, table_name) do
      {:ok, schema} ->
        IO.puts("Table: #{String.upcase(table_name)}")
        IO.puts("Columns:")

        Enum.each(schema.columns, fn {name, type, modifiers} ->
          type_str = format_type_with_size(type, modifiers)
          mods = format_modifiers(modifiers)
          IO.puts("  #{name} #{type_str}#{mods}")
        end)

        if length(schema.constraints) > 0 do
          IO.puts("Constraints:")

          Enum.each(schema.constraints, fn constraint ->
            IO.puts("  #{inspect(constraint)}")
          end)
        end

      {:error, reason} ->
        IO.puts("Error: #{reason}")
    end

    :continue
  end

  defp process_input(db, ".types") do
    types = OracleDb.list_types(db)

    if length(types) == 0 do
      IO.puts("No types.")
    else
      IO.puts("Types:")
      Enum.each(types, fn type -> IO.puts("  #{type}") end)
    end

    :continue
  end

  defp process_input(db, ".views") do
    views = OracleDb.list_views(db)

    if length(views) == 0 do
      IO.puts("No views.")
    else
      IO.puts("Views:")
      Enum.each(views, fn view -> IO.puts("  #{view}") end)
    end

    :continue
  end

  defp process_input(_db, "." <> cmd) do
    IO.puts("Unknown command: .#{cmd}")
    IO.puts("Type .help for available commands.")
    :continue
  end

  defp process_input(db, sql) do
    # Collect multi-line SQL until we get a semicolon
    sql = collect_multiline_sql(sql)
    sql = String.trim_trailing(sql, ";")

    execute_sql(db, sql)
    :continue
  end

  defp collect_multiline_sql(sql) do
    trimmed = String.trim(sql)

    cond do
      sql == "" ->
        sql

      # Check if we're in a PL/SQL block that needs to continue until END;
      is_plsql_block?(trimmed) and not plsql_block_complete?(trimmed) ->
        # Continue collecting input until the PL/SQL block is complete
        case IO.gets("     > ") do
          :eof ->
            sql

          {:error, _} ->
            sql

          more when is_binary(more) ->
            collect_multiline_sql(sql <> "\n" <> String.trim(more))
        end

      # Regular SQL - stop at first semicolon
      String.ends_with?(trimmed, ";") ->
        sql

      # No semicolon yet, continue collecting
      true ->
        case IO.gets("     > ") do
          :eof ->
            sql

          {:error, _} ->
            sql

          more when is_binary(more) ->
            collect_multiline_sql(sql <> "\n" <> String.trim(more))
        end
    end
  end

  # Detect if the SQL is a PL/SQL block that contains multiple semicolons
  defp is_plsql_block?(sql) do
    sql_upper = String.upcase(sql)

    # Check for PL/SQL constructs that contain multiple statements
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

  # Check if a PL/SQL block is complete by looking for matching BEGIN/END
  defp plsql_block_complete?(sql) do
    sql_upper = String.upcase(sql)

    # The block is complete when it ends with "END;" or "END <name>;"
    # and the BEGIN/END blocks are balanced
    ends_with_end_semicolon?(sql_upper) and begin_end_balanced?(sql_upper)
  end

  defp ends_with_end_semicolon?(sql) do
    # Match END; or END <identifier>;
    Regex.match?(~r/END\s*;?\s*$/i, sql) or
      Regex.match?(~r/END\s+\w+\s*;?\s*$/i, sql)
  end

  defp begin_end_balanced?(sql) do
    # Count BEGIN and END keywords (excluding END IF, END LOOP, etc.)
    # Note: We need to handle string literals to avoid false matches
    sql_without_strings = Regex.replace(~r/'[^']*'/, sql, "")

    begin_count = length(Regex.scan(~r/\bBEGIN\b/i, sql_without_strings))

    # Count END that are not followed by IF, LOOP, CASE (those are block terminators within PL/SQL)
    # We want to count standalone END or END <procedure_name>
    end_count =
      length(Regex.scan(~r/\bEND\s*;/i, sql_without_strings)) +
        length(Regex.scan(~r/\bEND\s+(?!IF\b|LOOP\b|CASE\b)\w+\s*;/i, sql_without_strings))

    begin_count > 0 and end_count >= begin_count
  end

  defp execute_sql(db, sql) do
    case OracleDb.execute(db, sql) do
      {:ok, rows} when is_list(rows) ->
        print_results(rows)

      {:ok, %{rows_affected: count}} ->
        IO.puts("OK: #{count} row(s) affected")

      {:ok, %{message: message}} ->
        IO.puts("OK: #{message}")

      {:ok, other} ->
        IO.puts("OK: #{inspect(other)}")

      {:error, reason} ->
        IO.puts("Error: #{reason}")
    end
  end

  defp print_results([]) do
    IO.puts("0 row(s) returned")
  end

  defp print_results(rows) do
    # Get column names from first row
    columns = rows |> hd() |> Map.keys() |> Enum.sort()

    # Calculate column widths
    widths =
      Enum.map(columns, fn col ->
        max_width =
          rows
          |> Enum.map(fn row -> format_value(Map.get(row, col)) |> String.length() end)
          |> Enum.max()

        max(String.length(to_string(col)), max_width)
      end)

    # Print header
    header =
      columns
      |> Enum.zip(widths)
      |> Enum.map(fn {col, width} -> String.pad_trailing(to_string(col), width) end)
      |> Enum.join(" | ")

    separator =
      widths
      |> Enum.map(fn width -> String.duplicate("-", width) end)
      |> Enum.join("-+-")

    IO.puts("| #{header} |")
    IO.puts("+-#{separator}-+")

    # Print rows
    Enum.each(rows, fn row ->
      values =
        columns
        |> Enum.zip(widths)
        |> Enum.map(fn {col, width} ->
          value = Map.get(row, col) |> format_value()
          String.pad_trailing(value, width)
        end)
        |> Enum.join(" | ")

      IO.puts("| #{values} |")
    end)

    IO.puts("#{length(rows)} row(s) returned")
  end

  defp format_value(nil), do: "NULL"
  defp format_value(%Date{} = date), do: Date.to_string(date)
  defp format_value(%DateTime{} = dt), do: DateTime.to_string(dt)
  defp format_value(value) when is_binary(value), do: value
  defp format_value(value), do: inspect(value)

  defp format_type(type) when is_atom(type), do: Atom.to_string(type) |> String.upcase()
  defp format_type({type, size}) when is_integer(size), do: "#{format_type(type)}(#{size})"
  defp format_type({type, size}) when is_binary(size), do: "#{format_type(type)}(#{size})"
  defp format_type({type, precision, scale}), do: "#{format_type(type)}(#{precision}, #{scale})"
  defp format_type(type), do: inspect(type)

  defp format_type_with_size(type, modifiers) do
    base_type = format_type(type)

    case Keyword.get(modifiers, :size) do
      nil -> base_type
      size -> "#{base_type}(#{size})"
    end
  end

  defp format_modifiers([]), do: ""

  defp format_modifiers(modifiers) do
    mods =
      modifiers
      |> Enum.reject(fn
        {:size, _} -> true
        _ -> false
      end)
      |> Enum.map(fn
        :primary_key -> "PRIMARY KEY"
        :not_null -> "NOT NULL"
        :null -> nil
        {:default, val} -> "DEFAULT #{inspect(val)}"
        other -> inspect(other)
      end)
      |> Enum.reject(&is_nil/1)

    case mods do
      [] -> ""
      _ -> " " <> Enum.join(mods, " ")
    end
  end

  defp print_help do
    IO.puts("""
    Available commands:
      .help              Show this help message
      .tables            List all tables
      .schema <table>    Show table schema
      .types             List all user-defined types
      .views             List all views
      .clear             Clear the screen
      .exit, .quit       Exit the REPL

    SQL commands:
      Any valid Oracle SQL statement (end with semicolon for multi-line)

    Examples:
      CREATE TABLE users (id NUMBER, name VARCHAR2(100));
      INSERT INTO users VALUES (1, 'Alice');
      SELECT * FROM users;
      SELECT SYSDATE FROM DUAL;
    """)
  end
end
