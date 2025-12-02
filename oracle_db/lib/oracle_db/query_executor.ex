defmodule OracleDb.QueryExecutor do
  @moduledoc """
  Executes parsed SQL statements against the storage engine.
  """

  alias OracleDb.SqlParser
  alias OracleDb.Storage

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
    Storage.select(storage, info.table, info.columns, info.where, info.order_by)
  end

  def execute_parsed(storage, {:insert, info}) do
    case Storage.insert(storage, info.table, info.columns, info.values) do
      {:ok, count} -> {:ok, %{rows_affected: count}}
      error -> error
    end
  end

  def execute_parsed(storage, {:update, info}) do
    case Storage.update(storage, info.table, info.sets, info.where) do
      {:ok, count} -> {:ok, %{rows_affected: count}}
      error -> error
    end
  end

  def execute_parsed(storage, {:delete, info}) do
    case Storage.delete(storage, info.table, info.where) do
      {:ok, count} -> {:ok, %{rows_affected: count}}
      error -> error
    end
  end

  def execute_parsed(storage, {:create_table, info}) do
    # Handle object table creation (CREATE TABLE ... OF type_name)
    schema =
      if Map.get(info, :object_table, false) do
        type_name = Map.get(info, :of_type)

        case Storage.get_type(storage, type_name) do
          {:ok, type_def} ->
            # Derive columns from object type attributes
            columns =
              Map.get(type_def, :attributes, [])
              |> Enum.map(fn {name, type_info} ->
                {to_string(name), type_info, []}
              end)

            %{
              columns: columns,
              constraints: Map.get(info, :constraints, []),
              indexes: %{},
              of_type: type_name,
              object_table: true
            }

          {:error, _} ->
            %{
              columns: info.columns,
              constraints: Map.get(info, :constraints, []),
              indexes: %{}
            }
        end
      else
        %{
          columns: info.columns,
          constraints: Map.get(info, :constraints, []),
          indexes: %{}
        }
      end

    table_name = String.upcase(info.table)

    case Storage.create_table(storage, info.table, schema) do
      :ok ->
        # Handle CREATE TABLE AS SELECT
        case Map.get(info, :as_select) do
          nil ->
            {:ok, %{message: "Table #{table_name} created"}}

          select_info ->
            # Execute the select and insert results
            case Storage.select(
                   storage,
                   select_info.table,
                   select_info.columns,
                   select_info.where,
                   select_info.order_by
                 ) do
              {:ok, rows} ->
                if length(rows) > 0 do
                  columns = Map.keys(hd(rows))
                  values = Enum.map(rows, fn row -> Enum.map(columns, &Map.get(row, &1)) end)
                  Storage.insert(storage, info.table, columns, values)
                end

                {:ok, %{message: "Table #{table_name} created"}}

              error ->
                error
            end
        end

      error ->
        error
    end
  end

  def execute_parsed(storage, {:drop_table, info}) do
    table_name = String.upcase(info.table)

    case Storage.drop_table(storage, info.table, Map.get(info, :cascade, false)) do
      :ok -> {:ok, %{message: "Table #{table_name} dropped"}}
      error -> error
    end
  end

  def execute_parsed(storage, {:alter_table, info}) do
    table_name = String.upcase(info.table)

    case Storage.alter_table(storage, info.table, info.action, info.details) do
      :ok -> {:ok, %{message: "Table #{table_name} altered"}}
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
      :ok -> {:ok, %{message: "Index #{info.name} created"}}
      error -> error
    end
  end

  def execute_parsed(storage, {:drop_index, info}) do
    case Storage.drop_index(storage, info.name) do
      :ok -> {:ok, %{message: "Index #{info.name} dropped"}}
      error -> error
    end
  end

  def execute_parsed(storage, {:create_sequence, info}) do
    seq_name = String.upcase(info.name)

    case Storage.create_sequence(storage, info.name, info.options) do
      :ok -> {:ok, %{message: "Sequence #{seq_name} created"}}
      error -> error
    end
  end

  def execute_parsed(storage, {:drop_sequence, info}) do
    seq_name = String.upcase(info.name)

    case Storage.drop_sequence(storage, info.name) do
      :ok -> {:ok, %{message: "Sequence #{seq_name} dropped"}}
      error -> error
    end
  end

  def execute_parsed(storage, {:create_type, info}) do
    type_name = String.upcase(info.name)

    case Storage.create_type(storage, info.name, info) do
      :ok -> {:ok, %{message: "Type #{type_name} created"}}
      error -> error
    end
  end

  def execute_parsed(storage, {:drop_type, info}) do
    type_name = String.upcase(info.name)
    force = Map.get(info, :force, false)

    case Storage.drop_type(storage, info.name, force) do
      :ok -> {:ok, %{message: "Type #{type_name} dropped"}}
      error -> error
    end
  end

  def execute_parsed(storage, {:alter_type, info}) do
    type_name = String.upcase(info.name)

    case Storage.alter_type(storage, info.name, info.action, info.details) do
      :ok -> {:ok, %{message: "Type #{type_name} altered"}}
      error -> error
    end
  end

  # View operations

  def execute_parsed(storage, {:create_view, info}) do
    view_name = String.upcase(info.name)

    case Storage.create_view(storage, info.name, info) do
      :ok -> {:ok, %{message: "View #{view_name} created"}}
      error -> error
    end
  end

  def execute_parsed(storage, {:drop_view, info}) do
    view_name = String.upcase(info.name)

    case Storage.drop_view(storage, info.name) do
      :ok -> {:ok, %{message: "View #{view_name} dropped"}}
      error -> error
    end
  end

  def execute_parsed(storage, {:alter_view, info}) do
    view_name = String.upcase(info.name)

    # Validate view exists before altering
    case Storage.get_view(storage, info.name) do
      {:ok, _view_def} ->
        # For ALTER VIEW COMPILE, we just validate and return success
        {:ok, %{message: "View #{view_name} altered"}}

      {:error, _} = error ->
        error
    end
  end

  def execute_parsed(storage, {:create_materialized_view, info}) do
    view_name = String.upcase(info.name)

    case Storage.create_materialized_view(storage, info.name, info) do
      :ok -> {:ok, %{message: "Materialized view #{view_name} created"}}
      error -> error
    end
  end

  def execute_parsed(storage, {:drop_materialized_view, info}) do
    view_name = String.upcase(info.name)

    case Storage.drop_materialized_view(storage, info.name) do
      :ok -> {:ok, %{message: "Materialized view #{view_name} dropped"}}
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
