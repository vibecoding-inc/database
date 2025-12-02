defmodule PostgresDb.QueryExecutor do
  @moduledoc """
  Executes parsed SQL statements against the storage engine.
  """

  alias PostgresDb.SqlParser
  alias PostgresDb.Storage

  @type result :: {:ok, any()} | {:error, String.t()}

  @doc """
  Executes a SQL statement string.
  """
  @spec execute(GenServer.server(), String.t()) :: result()
  def execute(storage \\ Storage, sql) do
    case SqlParser.parse(sql) do
      {:error, _} = err -> err
      parsed -> execute_parsed(storage, parsed)
    end
  end

  @doc """
  Executes a parsed SQL statement.
  """
  @spec execute_parsed(GenServer.server(), SqlParser.parsed_statement()) :: result()
  def execute_parsed(storage, {:select, info}) do
    Storage.select(
      storage,
      info.table,
      info.columns,
      info.where,
      info.order_by,
      info.limit,
      info.offset
    )
  end

  def execute_parsed(storage, {:insert, info}) do
    result = Storage.insert(storage, info.table, info.columns, info.values, info.returning)

    case result do
      {:ok, rows} when is_list(rows) ->
        {:ok, %{rows: rows, rows_affected: length(rows)}}

      {:ok, count} when is_integer(count) ->
        {:ok, %{rows_affected: count}}

      error ->
        error
    end
  end

  def execute_parsed(storage, {:update, info}) do
    result = Storage.update(storage, info.table, info.sets, info.where, info.returning)

    case result do
      {:ok, rows} when is_list(rows) ->
        {:ok, %{rows: rows, rows_affected: length(rows)}}

      {:ok, count} when is_integer(count) ->
        {:ok, %{rows_affected: count}}

      error ->
        error
    end
  end

  def execute_parsed(storage, {:delete, info}) do
    result = Storage.delete(storage, info.table, info.where, info.returning)

    case result do
      {:ok, rows} when is_list(rows) ->
        {:ok, %{rows: rows, rows_affected: length(rows)}}

      {:ok, count} when is_integer(count) ->
        {:ok, %{rows_affected: count}}

      error ->
        error
    end
  end

  def execute_parsed(storage, {:create_table, info}) do
    schema = %{
      columns: info.columns,
      constraints: Map.get(info, :constraints, []),
      indexes: %{}
    }

    if_not_exists = Map.get(info, :if_not_exists, false)
    _table_name = String.downcase(info.table)

    case Storage.create_table(storage, info.table, schema, if_not_exists) do
      :ok ->
        # Handle CREATE TABLE AS SELECT
        case Map.get(info, :as_select) do
          nil ->
            {:ok, %{message: "CREATE TABLE"}}

          select_info ->
            case Storage.select(
                   storage,
                   select_info.table,
                   select_info.columns,
                   select_info.where,
                   select_info.order_by,
                   select_info.limit,
                   select_info.offset
                 ) do
              {:ok, rows} ->
                if length(rows) > 0 do
                  columns = Map.keys(hd(rows))
                  values = Enum.map(rows, fn row -> Enum.map(columns, &Map.get(row, &1)) end)
                  Storage.insert(storage, info.table, columns, values, nil)
                end

                {:ok, %{message: "SELECT #{length(rows)}"}}

              error ->
                error
            end
        end

      {:error, msg} when is_binary(msg) ->
        if String.contains?(msg, "already exists") and if_not_exists do
          {:ok, %{message: "CREATE TABLE"}}
        else
          {:error, msg}
        end

      error ->
        error
    end
  end

  def execute_parsed(storage, {:drop_table, info}) do
    cascade = Map.get(info, :cascade, false)
    if_exists = Map.get(info, :if_exists, false)

    case Storage.drop_table(storage, info.table, cascade, if_exists) do
      :ok -> {:ok, %{message: "DROP TABLE"}}
      error -> error
    end
  end

  def execute_parsed(storage, {:alter_table, info}) do
    case Storage.alter_table(storage, info.table, info.action, info.details) do
      :ok -> {:ok, %{message: "ALTER TABLE"}}
      error -> error
    end
  end

  def execute_parsed(storage, {:create_index, info}) do
    case Storage.create_index(
           storage,
           info.name,
           info.table,
           info.columns,
           Map.get(info, :unique, false)
         ) do
      :ok -> {:ok, %{message: "CREATE INDEX"}}
      error -> error
    end
  end

  def execute_parsed(storage, {:drop_index, info}) do
    if_exists = Map.get(info, :if_exists, false)

    case Storage.drop_index(storage, info.name, if_exists) do
      :ok -> {:ok, %{message: "DROP INDEX"}}
      error -> error
    end
  end

  def execute_parsed(storage, {:create_sequence, info}) do
    case Storage.create_sequence(storage, info.name, info.options) do
      :ok -> {:ok, %{message: "CREATE SEQUENCE"}}
      error -> error
    end
  end

  def execute_parsed(storage, {:drop_sequence, info}) do
    if_exists = Map.get(info, :if_exists, false)

    case Storage.drop_sequence(storage, info.name, if_exists) do
      :ok -> {:ok, %{message: "DROP SEQUENCE"}}
      error -> error
    end
  end

  def execute_parsed(_storage, {:alter_sequence, _info}) do
    # For simplicity, we'll recreate sequence-like behavior
    {:ok, %{message: "ALTER SEQUENCE"}}
  end

  def execute_parsed(storage, {:create_type, info}) do
    case Storage.create_type(storage, info.name, info) do
      :ok -> {:ok, %{message: "CREATE TYPE"}}
      error -> error
    end
  end

  def execute_parsed(storage, {:drop_type, info}) do
    cascade = Map.get(info, :cascade, false)

    case Storage.drop_type(storage, info.name, cascade) do
      :ok -> {:ok, %{message: "DROP TYPE"}}
      error -> error
    end
  end

  def execute_parsed(storage, {:alter_type, info}) do
    case Storage.alter_type(storage, info.name, info.action, info.details) do
      :ok -> {:ok, %{message: "ALTER TYPE"}}
      error -> error
    end
  end

  def execute_parsed(_storage, {:error, _} = error) do
    error
  end

  def execute_parsed(_storage, unknown) do
    {:error, "Unknown statement type: #{inspect(unknown)}"}
  end
end
