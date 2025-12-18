defmodule VibeDb.QueryExecutor do
  @moduledoc """
  Executes parsed SQL statements against the storage engine.
  """

  alias VibeDb.SqlParser
  alias VibeDb.Storage
  alias VibeDb.PlsqlInterpreter

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
              columns: Map.get(info, :columns, []),
              constraints: Map.get(info, :constraints, []),
              indexes: %{}
            }
        end
      else
        %{
          columns: Map.get(info, :columns, []),
          constraints: Map.get(info, :constraints, []),
          indexes: %{}
        }
      end

    table_name = String.upcase(info.table)

    case Map.get(info, :as_select) do
      nil ->
        case Storage.create_table(storage, info.table, schema) do
          :ok -> {:ok, %{message: "Table #{table_name} created"}}
          error -> error
        end

      select_info ->
        case Storage.select(
               storage,
               select_info.table,
               select_info.columns,
               select_info.where,
               select_info.order_by
             ) do
          {:ok, rows} ->
            case Storage.create_table(storage, info.table, schema) do
              :ok ->
                insert_result =
                  if length(rows) > 0 do
                    columns = Map.keys(hd(rows))
                    values = Enum.map(rows, fn row -> Enum.map(columns, &Map.get(row, &1)) end)
                    Storage.insert(storage, info.table, columns, values)
                  else
                    {:ok, 0}
                  end

                case insert_result do
                  {:ok, _} ->
                    {:ok, %{message: "Table #{table_name} created"}}

                  {:error, _} = error ->
                    case Storage.drop_table(storage, info.table) do
                      :ok -> :ok
                      {:error, _} -> :ok
                    end

                    error
                end

              error ->
                error
            end

          {:error, _} = error ->
            error
        end
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

  # Stored Procedures

  def execute_parsed(storage, {:create_procedure, info}) do
    proc_name = String.upcase(info.name)

    case Storage.create_procedure(storage, info.name, info) do
      :ok -> {:ok, %{message: "Procedure #{proc_name} created"}}
      error -> error
    end
  end

  def execute_parsed(storage, {:drop_procedure, info}) do
    proc_name = String.upcase(info.name)

    case Storage.drop_procedure(storage, info.name) do
      :ok -> {:ok, %{message: "Procedure #{proc_name} dropped"}}
      error -> error
    end
  end

  def execute_parsed(storage, {:alter_procedure, info}) do
    proc_name = String.upcase(info.name)

    case Storage.get_procedure(storage, info.name) do
      {:ok, _} -> {:ok, %{message: "Procedure #{proc_name} compiled"}}
      {:error, _} = error -> error
    end
  end

  # Stored Functions

  def execute_parsed(storage, {:create_function, info}) do
    func_name = String.upcase(info.name)

    case Storage.create_function(storage, info.name, info) do
      :ok -> {:ok, %{message: "Function #{func_name} created"}}
      error -> error
    end
  end

  def execute_parsed(storage, {:drop_function, info}) do
    func_name = String.upcase(info.name)

    case Storage.drop_function(storage, info.name) do
      :ok -> {:ok, %{message: "Function #{func_name} dropped"}}
      error -> error
    end
  end

  def execute_parsed(storage, {:alter_function, info}) do
    func_name = String.upcase(info.name)

    case Storage.get_function(storage, info.name) do
      {:ok, _} -> {:ok, %{message: "Function #{func_name} compiled"}}
      {:error, _} = error -> error
    end
  end

  # Packages

  def execute_parsed(storage, {:create_package, info}) do
    pkg_name = String.upcase(info.name)

    case Storage.create_package(storage, info.name, info) do
      :ok -> {:ok, %{message: "Package #{pkg_name} created"}}
      error -> error
    end
  end

  def execute_parsed(storage, {:create_package_body, info}) do
    pkg_name = String.upcase(info.name)

    case Storage.create_package_body(storage, info.name, info) do
      :ok -> {:ok, %{message: "Package body #{pkg_name} created"}}
      error -> error
    end
  end

  def execute_parsed(storage, {:drop_package, info}) do
    pkg_name = String.upcase(info.name)

    case Storage.drop_package(storage, info.name, false) do
      :ok -> {:ok, %{message: "Package #{pkg_name} dropped"}}
      error -> error
    end
  end

  def execute_parsed(storage, {:drop_package_body, info}) do
    pkg_name = String.upcase(info.name)

    case Storage.drop_package(storage, info.name, true) do
      :ok -> {:ok, %{message: "Package body #{pkg_name} dropped"}}
      error -> error
    end
  end

  def execute_parsed(storage, {:alter_package, info}) do
    pkg_name = String.upcase(info.name)

    case Storage.get_package(storage, info.name) do
      {:ok, _} ->
        action_msg = if info.action == :compile_body, do: "body compiled", else: "compiled"
        {:ok, %{message: "Package #{pkg_name} #{action_msg}"}}

      {:error, _} = error ->
        error
    end
  end

  # Triggers

  def execute_parsed(storage, {:create_trigger, info}) do
    trigger_name = String.upcase(info.name)

    case Storage.create_trigger(storage, info.name, info) do
      :ok -> {:ok, %{message: "Trigger #{trigger_name} created"}}
      error -> error
    end
  end

  def execute_parsed(storage, {:drop_trigger, info}) do
    trigger_name = String.upcase(info.name)

    case Storage.drop_trigger(storage, info.name) do
      :ok -> {:ok, %{message: "Trigger #{trigger_name} dropped"}}
      error -> error
    end
  end

  def execute_parsed(storage, {:alter_trigger, info}) do
    trigger_name = String.upcase(info.name)

    case info.action do
      :enable ->
        case Storage.enable_trigger(storage, info.name) do
          :ok -> {:ok, %{message: "Trigger #{trigger_name} enabled"}}
          error -> error
        end

      :disable ->
        case Storage.disable_trigger(storage, info.name) do
          :ok -> {:ok, %{message: "Trigger #{trigger_name} disabled"}}
          error -> error
        end

      :compile ->
        case Storage.get_trigger(storage, info.name) do
          {:ok, _} -> {:ok, %{message: "Trigger #{trigger_name} compiled"}}
          {:error, _} = error -> error
        end
    end
  end

  # CALL statement - execute a stored procedure
  def execute_parsed(storage, {:call, info}) do
    proc_name = String.upcase(info.name)
    args = resolve_call_arguments(info.arguments)

    case PlsqlInterpreter.execute_procedure(storage, proc_name, args) do
      {:ok, result} ->
        {:ok,
         %{
           message: "Procedure #{proc_name} executed",
           output: result.output,
           out_params: result.out_params
         }}

      {:error, _} = err ->
        err
    end
  end

  # EXECUTE/EXEC statement - execute a stored procedure or function
  def execute_parsed(storage, {:execute, info}) do
    name = String.upcase(info.name)
    args = resolve_call_arguments(info.arguments)

    # Try procedure first, then function
    case PlsqlInterpreter.execute_procedure(storage, name, args) do
      {:ok, result} ->
        {:ok,
         %{
           message: "Procedure #{name} executed",
           output: result.output,
           out_params: result.out_params
         }}

      {:error, "Procedure " <> _} ->
        # Try as function
        case PlsqlInterpreter.execute_function(storage, name, args) do
          {:ok, return_value} ->
            {:ok,
             %{
               message: "Function #{name} executed",
               return_value: return_value
             }}

          {:error, _} = err ->
            err
        end

      {:error, _} = err ->
        err
    end
  end

  # Anonymous PL/SQL block
  def execute_parsed(storage, {:anonymous_block, info}) do
    case PlsqlInterpreter.execute(storage, info.body) do
      {:ok, result} ->
        {:ok,
         %{
           message: "PL/SQL block executed",
           output: result.output,
           return_value: result.return_value
         }}

      {:error, _} = err ->
        err
    end
  end

  # SET statement handler
  def execute_parsed(_storage, {:set, info}) do
    var_name = String.upcase(to_string(info.variable))
    value = info.value

    # For now, just acknowledge the SET command
    # In a full implementation, this would store session variables
    {:ok, %{message: "Variable #{var_name} set to #{inspect(value)}"}}
  end

  def execute_parsed(_storage, {:error, _} = error) do
    error
  end

  def execute_parsed(_storage, unknown) do
    {:error, "Unknown statement type: #{inspect(unknown)}"}
  end

  # Resolve call arguments to actual values
  defp resolve_call_arguments(args) do
    Enum.map(args, fn
      {:literal, value} -> value
      # Identifiers would need context to resolve
      {:identifier, name} ->
        IO.puts("[DEBUG query_executor.ex:resolve_call_arguments] Unable to resolve identifier: #{inspect(name)}")
        nil
      # Bind variables would need context to resolve
      {:bind_var, name} ->
        IO.puts("[DEBUG query_executor.ex:resolve_call_arguments] Unable to resolve bind variable: #{inspect(name)}")
        nil
      other -> other
    end)
  end
end
