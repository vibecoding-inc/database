defmodule PostgresDb.Storage do
  @moduledoc """
  In-memory storage engine for the PostgreSQL-compatible database.
  Stores tables, rows, indexes, sequences, and metadata.
  """

  use GenServer

  @type table_name :: String.t()
  @type column_name :: String.t()
  @type row :: map()
  @type table_schema :: %{
          columns: [{column_name(), atom(), list()}],
          constraints: list(),
          indexes: map()
        }

  # Client API

  @doc """
  Starts the storage server.
  """
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, %{}, name: name)
  end

  @doc """
  Creates a new table with the given schema.
  """
  @spec create_table(GenServer.server(), table_name(), table_schema(), boolean()) ::
          :ok | {:error, String.t()}
  def create_table(server \\ __MODULE__, table_name, schema, if_not_exists \\ false) do
    GenServer.call(server, {:create_table, normalize_name(table_name), schema, if_not_exists})
  end

  @doc """
  Drops a table.
  """
  @spec drop_table(GenServer.server(), table_name(), boolean(), boolean()) ::
          :ok | {:error, String.t()}
  def drop_table(server \\ __MODULE__, table_name, cascade \\ false, if_exists \\ false) do
    GenServer.call(server, {:drop_table, normalize_name(table_name), cascade, if_exists})
  end

  @doc """
  Checks if a table exists.
  """
  @spec table_exists?(GenServer.server(), table_name()) :: boolean()
  def table_exists?(server \\ __MODULE__, table_name) do
    GenServer.call(server, {:table_exists?, normalize_name(table_name)})
  end

  @doc """
  Gets the schema for a table.
  """
  @spec get_schema(GenServer.server(), table_name()) ::
          {:ok, table_schema()} | {:error, String.t()}
  def get_schema(server \\ __MODULE__, table_name) do
    GenServer.call(server, {:get_schema, normalize_name(table_name)})
  end

  @doc """
  Alters a table.
  """
  @spec alter_table(GenServer.server(), table_name(), atom(), any()) :: :ok | {:error, String.t()}
  def alter_table(server \\ __MODULE__, table_name, action, details) do
    GenServer.call(server, {:alter_table, normalize_name(table_name), action, details})
  end

  @doc """
  Inserts a row into a table.
  """
  @spec insert(GenServer.server(), table_name(), [column_name()] | nil, [any()], list() | nil) ::
          {:ok, integer()} | {:ok, [map()]} | {:error, String.t()}
  def insert(server \\ __MODULE__, table_name, columns, values, returning \\ nil) do
    GenServer.call(server, {:insert, normalize_name(table_name), columns, values, returning})
  end

  @doc """
  Selects rows from a table.
  """
  @spec select(GenServer.server(), table_name() | nil, list(), any(), any(), any(), any()) ::
          {:ok, [row()]} | {:error, String.t()}
  def select(
        server \\ __MODULE__,
        table_name,
        columns,
        where,
        order_by,
        limit \\ nil,
        offset \\ nil
      ) do
    normalized_table = if table_name, do: normalize_name(table_name), else: nil
    GenServer.call(server, {:select, normalized_table, columns, where, order_by, limit, offset})
  end

  @doc """
  Updates rows in a table.
  """
  @spec update(GenServer.server(), table_name(), [{column_name(), any()}], any(), list() | nil) ::
          {:ok, integer()} | {:ok, [map()]} | {:error, String.t()}
  def update(server \\ __MODULE__, table_name, sets, where, returning \\ nil) do
    GenServer.call(server, {:update, normalize_name(table_name), sets, where, returning})
  end

  @doc """
  Deletes rows from a table.
  """
  @spec delete(GenServer.server(), table_name(), any(), list() | nil) ::
          {:ok, integer()} | {:ok, [map()]} | {:error, String.t()}
  def delete(server \\ __MODULE__, table_name, where, returning \\ nil) do
    GenServer.call(server, {:delete, normalize_name(table_name), where, returning})
  end

  @doc """
  Creates an index on a table.
  """
  @spec create_index(GenServer.server(), String.t(), table_name(), [column_name()], boolean()) ::
          :ok | {:error, String.t()}
  def create_index(server \\ __MODULE__, index_name, table_name, columns, unique \\ false) do
    GenServer.call(
      server,
      {:create_index, index_name, normalize_name(table_name), columns, unique}
    )
  end

  @doc """
  Drops an index.
  """
  @spec drop_index(GenServer.server(), String.t(), boolean()) :: :ok | {:error, String.t()}
  def drop_index(server \\ __MODULE__, index_name, if_exists \\ false) do
    GenServer.call(server, {:drop_index, index_name, if_exists})
  end

  @doc """
  Creates a sequence.
  """
  @spec create_sequence(GenServer.server(), String.t(), map()) :: :ok | {:error, String.t()}
  def create_sequence(server \\ __MODULE__, name, options) do
    GenServer.call(server, {:create_sequence, normalize_name(name), options})
  end

  @doc """
  Gets the next value from a sequence.
  """
  @spec nextval(GenServer.server(), String.t()) :: {:ok, integer()} | {:error, String.t()}
  def nextval(server \\ __MODULE__, name) do
    GenServer.call(server, {:nextval, normalize_name(name)})
  end

  @doc """
  Gets the current value from a sequence.
  """
  @spec currval(GenServer.server(), String.t()) :: {:ok, integer()} | {:error, String.t()}
  def currval(server \\ __MODULE__, name) do
    GenServer.call(server, {:currval, normalize_name(name)})
  end

  @doc """
  Drops a sequence.
  """
  @spec drop_sequence(GenServer.server(), String.t(), boolean()) :: :ok | {:error, String.t()}
  def drop_sequence(server \\ __MODULE__, name, if_exists \\ false) do
    GenServer.call(server, {:drop_sequence, normalize_name(name), if_exists})
  end

  @doc """
  Creates a user-defined type.
  """
  @spec create_type(GenServer.server(), String.t(), map()) :: :ok | {:error, String.t()}
  def create_type(server \\ __MODULE__, name, type_def) do
    GenServer.call(server, {:create_type, normalize_name(name), type_def})
  end

  @doc """
  Drops a user-defined type.
  """
  @spec drop_type(GenServer.server(), String.t(), boolean()) :: :ok | {:error, String.t()}
  def drop_type(server \\ __MODULE__, name, cascade \\ false) do
    GenServer.call(server, {:drop_type, normalize_name(name), cascade})
  end

  @doc """
  Alters a user-defined type.
  """
  @spec alter_type(GenServer.server(), String.t(), atom(), any()) :: :ok | {:error, String.t()}
  def alter_type(server \\ __MODULE__, name, action, details) do
    GenServer.call(server, {:alter_type, normalize_name(name), action, details})
  end

  @doc """
  Gets all table names.
  """
  @spec list_tables(GenServer.server()) :: [table_name()]
  def list_tables(server \\ __MODULE__) do
    GenServer.call(server, :list_tables)
  end

  @doc """
  Resets the database (clears all data).
  """
  @spec reset(GenServer.server()) :: :ok
  def reset(server \\ __MODULE__) do
    GenServer.call(server, :reset)
  end

  # Server callbacks

  @impl true
  def init(_) do
    state = %{
      tables: %{},
      data: %{},
      sequences: %{},
      indexes: %{},
      row_counter: %{},
      types: %{}
    }

    {:ok, state}
  end

  @impl true
  def handle_call({:create_table, table_name, schema, if_not_exists}, _from, state) do
    if Map.has_key?(state.tables, table_name) do
      if if_not_exists do
        {:reply, :ok, state}
      else
        {:reply, {:error, "relation \"#{table_name}\" already exists"}, state}
      end
    else
      # Handle SERIAL columns - create sequences
      {new_state, updated_schema} = setup_serial_columns(state, table_name, schema)

      new_state = %{
        new_state
        | tables: Map.put(new_state.tables, table_name, updated_schema),
          data: Map.put(new_state.data, table_name, []),
          row_counter: Map.put(new_state.row_counter, table_name, 0)
      }

      {:reply, :ok, new_state}
    end
  end

  @impl true
  def handle_call({:drop_table, table_name, _cascade, if_exists}, _from, state) do
    if Map.has_key?(state.tables, table_name) do
      new_state = %{
        state
        | tables: Map.delete(state.tables, table_name),
          data: Map.delete(state.data, table_name),
          row_counter: Map.delete(state.row_counter, table_name)
      }

      {:reply, :ok, new_state}
    else
      if if_exists do
        {:reply, :ok, state}
      else
        {:reply, {:error, "table \"#{table_name}\" does not exist"}, state}
      end
    end
  end

  @impl true
  def handle_call({:table_exists?, table_name}, _from, state) do
    {:reply, Map.has_key?(state.tables, table_name), state}
  end

  @impl true
  def handle_call({:get_schema, table_name}, _from, state) do
    case Map.fetch(state.tables, table_name) do
      {:ok, schema} -> {:reply, {:ok, schema}, state}
      :error -> {:reply, {:error, "relation \"#{table_name}\" does not exist"}, state}
    end
  end

  @impl true
  def handle_call({:alter_table, table_name, action, details}, _from, state) do
    case Map.fetch(state.tables, table_name) do
      {:ok, schema} ->
        case apply_alter(schema, action, details) do
          {:ok, new_schema} ->
            new_state = %{state | tables: Map.put(state.tables, table_name, new_schema)}
            {:reply, :ok, new_state}

          {:error, _} = err ->
            {:reply, err, state}
        end

      :error ->
        {:reply, {:error, "relation \"#{table_name}\" does not exist"}, state}
    end
  end

  @impl true
  def handle_call({:insert, table_name, columns, values_list, returning}, _from, state) do
    case Map.fetch(state.tables, table_name) do
      {:ok, schema} ->
        case insert_rows(state, table_name, schema, columns, values_list, returning) do
          {:ok, new_state, result} -> {:reply, {:ok, result}, new_state}
          {:error, _} = err -> {:reply, err, state}
        end

      :error ->
        {:reply, {:error, "relation \"#{table_name}\" does not exist"}, state}
    end
  end

  @impl true
  def handle_call({:select, table_name, columns, where, order_by, limit, offset}, _from, state) do
    result = execute_select(state, table_name, columns, where, order_by, limit, offset)
    {:reply, result, state}
  end

  @impl true
  def handle_call({:update, table_name, sets, where, returning}, _from, state) do
    case Map.fetch(state.data, table_name) do
      {:ok, rows} ->
        {updated_rows, affected_rows, count} = apply_update(rows, sets, where)
        new_state = %{state | data: Map.put(state.data, table_name, updated_rows)}

        result =
          if returning do
            affected_rows
          else
            count
          end

        {:reply, {:ok, result}, new_state}

      :error ->
        {:reply, {:error, "relation \"#{table_name}\" does not exist"}, state}
    end
  end

  @impl true
  def handle_call({:delete, table_name, where, returning}, _from, state) do
    case Map.fetch(state.data, table_name) do
      {:ok, rows} ->
        {remaining_rows, deleted_rows, deleted_count} = apply_delete(rows, where)
        new_state = %{state | data: Map.put(state.data, table_name, remaining_rows)}

        result =
          if returning do
            Enum.map(deleted_rows, &Map.delete(&1, "__ROWNUM__"))
          else
            deleted_count
          end

        {:reply, {:ok, result}, new_state}

      :error ->
        {:reply, {:error, "relation \"#{table_name}\" does not exist"}, state}
    end
  end

  @impl true
  def handle_call({:create_index, index_name, table_name, columns, unique}, _from, state) do
    if Map.has_key?(state.tables, table_name) do
      index = %{table: table_name, columns: columns, unique: unique}
      new_state = %{state | indexes: Map.put(state.indexes, index_name, index)}
      {:reply, :ok, new_state}
    else
      {:reply, {:error, "relation \"#{table_name}\" does not exist"}, state}
    end
  end

  @impl true
  def handle_call({:drop_index, index_name, if_exists}, _from, state) do
    if Map.has_key?(state.indexes, index_name) do
      new_state = %{state | indexes: Map.delete(state.indexes, index_name)}
      {:reply, :ok, new_state}
    else
      if if_exists do
        {:reply, :ok, state}
      else
        {:reply, {:error, "index \"#{index_name}\" does not exist"}, state}
      end
    end
  end

  @impl true
  def handle_call({:create_sequence, name, options}, _from, state) do
    if Map.has_key?(state.sequences, name) do
      {:reply, {:error, "relation \"#{name}\" already exists"}, state}
    else
      sequence = %{
        current: Map.get(options, :start, 1) - Map.get(options, :increment, 1),
        increment: Map.get(options, :increment, 1),
        min_value: Map.get(options, :min_value, 1),
        max_value: Map.get(options, :max_value, 9_223_372_036_854_775_807),
        cycle: Map.get(options, :cycle, false),
        initialized: false
      }

      new_state = %{state | sequences: Map.put(state.sequences, name, sequence)}
      {:reply, :ok, new_state}
    end
  end

  @impl true
  def handle_call({:nextval, name}, _from, state) do
    case Map.fetch(state.sequences, name) do
      {:ok, seq} ->
        new_val = seq.current + seq.increment
        new_seq = %{seq | current: new_val, initialized: true}
        new_state = %{state | sequences: Map.put(state.sequences, name, new_seq)}
        {:reply, {:ok, new_val}, new_state}

      :error ->
        {:reply, {:error, "relation \"#{name}\" does not exist"}, state}
    end
  end

  @impl true
  def handle_call({:currval, name}, _from, state) do
    case Map.fetch(state.sequences, name) do
      {:ok, %{initialized: false}} ->
        {:reply, {:error, "currval of sequence \"#{name}\" is not yet defined in this session"},
         state}

      {:ok, seq} ->
        {:reply, {:ok, seq.current}, state}

      :error ->
        {:reply, {:error, "relation \"#{name}\" does not exist"}, state}
    end
  end

  @impl true
  def handle_call({:drop_sequence, name, if_exists}, _from, state) do
    if Map.has_key?(state.sequences, name) do
      new_state = %{state | sequences: Map.delete(state.sequences, name)}
      {:reply, :ok, new_state}
    else
      if if_exists do
        {:reply, :ok, state}
      else
        {:reply, {:error, "sequence \"#{name}\" does not exist"}, state}
      end
    end
  end

  @impl true
  def handle_call({:create_type, type_name, type_def}, _from, state) do
    if Map.has_key?(state.types, type_name) do
      {:reply, {:error, "type \"#{type_name}\" already exists"}, state}
    else
      new_state = %{state | types: Map.put(state.types, type_name, type_def)}
      {:reply, :ok, new_state}
    end
  end

  @impl true
  def handle_call({:drop_type, type_name, _cascade}, _from, state) do
    if Map.has_key?(state.types, type_name) do
      new_state = %{state | types: Map.delete(state.types, type_name)}
      {:reply, :ok, new_state}
    else
      {:reply, {:error, "type \"#{type_name}\" does not exist"}, state}
    end
  end

  @impl true
  def handle_call({:alter_type, type_name, action, details}, _from, state) do
    case Map.fetch(state.types, type_name) do
      {:ok, type_def} ->
        case apply_type_alter(type_def, action, details) do
          {:ok, new_type_def} ->
            new_state = %{state | types: Map.put(state.types, type_name, new_type_def)}
            {:reply, :ok, new_state}

          {:error, _} = err ->
            {:reply, err, state}
        end

      :error ->
        {:reply, {:error, "type \"#{type_name}\" does not exist"}, state}
    end
  end

  @impl true
  def handle_call(:list_tables, _from, state) do
    {:reply, Map.keys(state.tables), state}
  end

  @impl true
  def handle_call(:reset, _from, _state) do
    new_state = %{
      tables: %{},
      data: %{},
      sequences: %{},
      indexes: %{},
      row_counter: %{},
      types: %{}
    }

    {:reply, :ok, new_state}
  end

  # Private functions

  defp normalize_name(name) when is_binary(name), do: String.downcase(name)
  defp normalize_name(name), do: name

  defp setup_serial_columns(state, table_name, schema) do
    {new_state, updated_columns} =
      Enum.reduce(schema.columns, {state, []}, fn {name, type, mods}, {s, cols} ->
        case type do
          serial_type when serial_type in [:serial, :bigserial, :smallserial] ->
            seq_name = "#{table_name}_#{String.downcase(name)}_seq"

            # Create the sequence
            sequence = %{
              current: 0,
              increment: 1,
              min_value: 1,
              max_value: 9_223_372_036_854_775_807,
              cycle: false,
              initialized: false
            }

            s = %{s | sequences: Map.put(s.sequences, seq_name, sequence)}

            # Convert SERIAL to INTEGER with DEFAULT nextval
            new_type =
              case serial_type do
                :smallserial -> :smallint
                :serial -> :integer
                :bigserial -> :bigint
              end

            new_mods = [{:serial_sequence, seq_name} | mods]
            {s, [{name, new_type, new_mods} | cols]}

          _ ->
            {s, [{name, type, mods} | cols]}
        end
      end)

    updated_schema = %{schema | columns: Enum.reverse(updated_columns)}
    {new_state, updated_schema}
  end

  defp apply_type_alter(type_def, :add_value, value) do
    case type_def.kind do
      :enum ->
        new_values = type_def.values ++ [value]
        {:ok, %{type_def | values: new_values}}

      _ ->
        {:error, "ADD VALUE is only valid for enum types"}
    end
  end

  defp apply_type_alter(type_def, :add_attribute, {name, type}) do
    case type_def.kind do
      :composite ->
        new_attrs = type_def.attributes ++ [{name, type}]
        {:ok, %{type_def | attributes: new_attrs}}

      _ ->
        {:error, "ADD ATTRIBUTE is only valid for composite types"}
    end
  end

  defp apply_type_alter(type_def, :drop_attribute, attr_name) do
    case type_def.kind do
      :composite ->
        new_attrs =
          Enum.reject(type_def.attributes, fn {name, _} ->
            String.downcase(to_string(name)) == String.downcase(attr_name)
          end)

        {:ok, %{type_def | attributes: new_attrs}}

      _ ->
        {:error, "DROP ATTRIBUTE is only valid for composite types"}
    end
  end

  defp apply_type_alter(type_def, :rename_value, {old, new}) do
    case type_def.kind do
      :enum ->
        new_values = Enum.map(type_def.values, fn v -> if v == old, do: new, else: v end)
        {:ok, %{type_def | values: new_values}}

      _ ->
        {:error, "RENAME VALUE is only valid for enum types"}
    end
  end

  defp apply_type_alter(_type_def, :error, _) do
    {:error, "Invalid ALTER TYPE action"}
  end

  defp apply_alter(schema, :add_column, {name, type, modifiers}) do
    new_columns = schema.columns ++ [{name, type, modifiers}]
    {:ok, %{schema | columns: new_columns}}
  end

  defp apply_alter(schema, :drop_column, column_name) do
    new_columns =
      Enum.reject(schema.columns, fn {name, _, _} ->
        String.downcase(name) == String.downcase(column_name)
      end)

    {:ok, %{schema | columns: new_columns}}
  end

  defp apply_alter(schema, :drop_column_if_exists, column_name) do
    apply_alter(schema, :drop_column, column_name)
  end

  defp apply_alter(schema, :alter_column_type, {col_name, new_type}) do
    new_columns =
      Enum.map(schema.columns, fn {name, _type, mods} = col ->
        if String.downcase(name) == String.downcase(col_name) do
          {name, new_type, mods}
        else
          col
        end
      end)

    {:ok, %{schema | columns: new_columns}}
  end

  defp apply_alter(schema, :set_not_null, col_name) do
    new_columns =
      Enum.map(schema.columns, fn {name, type, mods} = col ->
        if String.downcase(name) == String.downcase(col_name) do
          {name, type, [:not_null | mods]}
        else
          col
        end
      end)

    {:ok, %{schema | columns: new_columns}}
  end

  defp apply_alter(schema, :drop_not_null, col_name) do
    new_columns =
      Enum.map(schema.columns, fn {name, type, mods} = col ->
        if String.downcase(name) == String.downcase(col_name) do
          {name, type, Enum.reject(mods, &(&1 == :not_null))}
        else
          col
        end
      end)

    {:ok, %{schema | columns: new_columns}}
  end

  defp apply_alter(schema, :set_default, {col_name, default}) do
    new_columns =
      Enum.map(schema.columns, fn {name, type, mods} = col ->
        if String.downcase(name) == String.downcase(col_name) do
          new_mods = [{:default, default} | Enum.reject(mods, &match?({:default, _}, &1))]
          {name, type, new_mods}
        else
          col
        end
      end)

    {:ok, %{schema | columns: new_columns}}
  end

  defp apply_alter(schema, :drop_default, col_name) do
    new_columns =
      Enum.map(schema.columns, fn {name, type, mods} = col ->
        if String.downcase(name) == String.downcase(col_name) do
          {name, type, Enum.reject(mods, &match?({:default, _}, &1))}
        else
          col
        end
      end)

    {:ok, %{schema | columns: new_columns}}
  end

  defp apply_alter(schema, :rename_column, {old_name, new_name}) do
    new_columns =
      Enum.map(schema.columns, fn {name, type, mods} ->
        if String.downcase(name) == String.downcase(old_name) do
          {new_name, type, mods}
        else
          {name, type, mods}
        end
      end)

    {:ok, %{schema | columns: new_columns}}
  end

  defp apply_alter(schema, :add_constraint, constraint) do
    new_constraints = [constraint | schema.constraints]
    {:ok, %{schema | constraints: new_constraints}}
  end

  defp apply_alter(schema, :drop_constraint, _constraint_name) do
    {:ok, schema}
  end

  defp apply_alter(schema, :drop_constraint_if_exists, _constraint_name) do
    {:ok, schema}
  end

  defp apply_alter(_schema, :error, _) do
    {:error, "Invalid ALTER TABLE action"}
  end

  defp insert_rows(state, table_name, schema, columns, values_list, returning) do
    column_names =
      if columns do
        columns
      else
        Enum.map(schema.columns, fn {name, _, _} -> name end)
      end

    {new_rows, new_state, new_counter} =
      Enum.reduce(values_list, {[], state, state.row_counter[table_name]}, fn values,
                                                                              {acc, s, counter} ->
        # Handle SERIAL columns
        {row, s} = build_row_with_serials(column_names, values, schema, s, counter + 1)
        {[row | acc], s, counter + 1}
      end)

    existing_rows = Map.get(new_state.data, table_name, [])
    inserted_rows = Enum.reverse(new_rows)

    final_state = %{
      new_state
      | data: Map.put(new_state.data, table_name, existing_rows ++ inserted_rows),
        row_counter: Map.put(new_state.row_counter, table_name, new_counter)
    }

    result =
      if returning do
        Enum.map(inserted_rows, &Map.delete(&1, "__ROWNUM__"))
      else
        length(values_list)
      end

    {:ok, final_state, result}
  end

  defp build_row_with_serials(columns, values, schema, state, rownum) do
    # First, build the basic row
    row =
      columns
      |> Enum.zip(values)
      |> Enum.into(%{})

    # Then, fill in SERIAL columns that weren't provided
    {row, state} =
      Enum.reduce(schema.columns, {row, state}, fn {col_name, _type, mods}, {r, s} ->
        case Keyword.get(mods, :serial_sequence) do
          nil ->
            {r, s}

          seq_name ->
            # Check if column was provided
            lower_col = String.downcase(col_name)

            has_value =
              Enum.any?(Map.keys(r), fn k ->
                String.downcase(to_string(k)) == lower_col
              end)

            if has_value do
              {r, s}
            else
              # Get next value from sequence
              {:ok, next_val, new_state} = get_nextval(s, seq_name)
              {Map.put(r, col_name, next_val), new_state}
            end
        end
      end)

    {Map.put(row, "__ROWNUM__", rownum), state}
  end

  defp get_nextval(state, seq_name) do
    case Map.fetch(state.sequences, seq_name) do
      {:ok, seq} ->
        new_val = seq.current + seq.increment
        new_seq = %{seq | current: new_val, initialized: true}
        new_state = %{state | sequences: Map.put(state.sequences, seq_name, new_seq)}
        {:ok, new_val, new_state}

      :error ->
        {:error, "sequence not found", state}
    end
  end

  defp execute_select(_state, nil, columns, _where, _order_by, _limit, _offset) do
    # SELECT without FROM (PostgreSQL allows this)
    row = evaluate_select_columns(%{}, columns, 1)
    {:ok, [row]}
  end

  defp execute_select(state, table_name, columns, where, order_by, limit, offset) do
    case Map.fetch(state.data, table_name) do
      {:ok, rows} ->
        # Apply WHERE filter
        filtered = filter_rows(rows, where)

        # Apply ORDER BY
        sorted = sort_rows(filtered, order_by)

        # Apply OFFSET
        offset_applied = apply_offset(sorted, offset)

        # Apply LIMIT
        limited = apply_limit(offset_applied, limit)

        # Project columns
        projected = project_columns(limited, columns)

        {:ok, projected}

      :error ->
        {:error, "relation \"#{table_name}\" does not exist"}
    end
  end

  defp filter_rows(rows, nil), do: rows

  defp filter_rows(rows, where) do
    Enum.filter(rows, fn row -> evaluate_condition(row, where) end)
  end

  defp evaluate_condition(_row, nil), do: true

  defp evaluate_condition(row, {:and, left, right}) do
    evaluate_condition(row, left) and evaluate_condition(row, right)
  end

  defp evaluate_condition(row, {:or, left, right}) do
    evaluate_condition(row, left) or evaluate_condition(row, right)
  end

  defp evaluate_condition(row, {:not, condition}) do
    not evaluate_condition(row, condition)
  end

  defp evaluate_condition(row, {:comparison, column, op, value}) do
    row_value = get_column_value(row, column)
    compare(row_value, op, value)
  end

  defp evaluate_condition(row, {:is_null, column}) do
    get_column_value(row, column) == nil
  end

  defp evaluate_condition(row, {:is_not_null, column}) do
    get_column_value(row, column) != nil
  end

  defp evaluate_condition(row, {:is_true, column}) do
    get_column_value(row, column) == true
  end

  defp evaluate_condition(row, {:is_false, column}) do
    get_column_value(row, column) == false
  end

  defp evaluate_condition(row, {:is_not_true, column}) do
    get_column_value(row, column) != true
  end

  defp evaluate_condition(row, {:is_not_false, column}) do
    get_column_value(row, column) != false
  end

  defp evaluate_condition(row, {:in, column, values}) do
    row_value = get_column_value(row, column)
    row_value in values
  end

  defp evaluate_condition(row, {:between, column, low, high}) do
    row_value = get_column_value(row, column)
    row_value >= low and row_value <= high
  end

  defp evaluate_condition(row, {:like, column, pattern}) do
    row_value = get_column_value(row, column)

    if is_binary(row_value) do
      regex_pattern =
        pattern
        |> Regex.escape()
        |> String.replace("%", ".*")
        |> String.replace("_", ".")

      Regex.match?(~r/^#{regex_pattern}$/, row_value)
    else
      false
    end
  end

  defp evaluate_condition(row, {:ilike, column, pattern}) do
    row_value = get_column_value(row, column)

    if is_binary(row_value) do
      regex_pattern =
        pattern
        |> Regex.escape()
        |> String.replace("%", ".*")
        |> String.replace("_", ".")

      Regex.match?(~r/^#{regex_pattern}$/i, row_value)
    else
      false
    end
  end

  defp evaluate_condition(row, {:similar_to, column, pattern}) do
    row_value = get_column_value(row, column)

    if is_binary(row_value) do
      # SIMILAR TO uses SQL standard regex which is similar to POSIX
      regex_pattern =
        pattern
        |> String.replace("%", ".*")
        |> String.replace("_", ".")

      Regex.match?(~r/^#{regex_pattern}$/, row_value)
    else
      false
    end
  end

  defp evaluate_condition(row, {:raw, tokens}) do
    parse_raw_condition(row, tokens)
  end

  defp evaluate_condition(_row, _), do: true

  defp parse_raw_condition(row, [col, "=", val]) do
    row_value = get_column_value(row, col)
    compare(row_value, "=", parse_token_value(val))
  end

  defp parse_raw_condition(row, [col, "<>", val]) do
    row_value = get_column_value(row, col)
    compare(row_value, "<>", parse_token_value(val))
  end

  defp parse_raw_condition(row, [col, "!=", val]) do
    row_value = get_column_value(row, col)
    compare(row_value, "!=", parse_token_value(val))
  end

  defp parse_raw_condition(row, [col, ">", val]) do
    row_value = get_column_value(row, col)
    compare(row_value, ">", parse_token_value(val))
  end

  defp parse_raw_condition(row, [col, "<", val]) do
    row_value = get_column_value(row, col)
    compare(row_value, "<", parse_token_value(val))
  end

  defp parse_raw_condition(row, [col, ">=", val]) do
    row_value = get_column_value(row, col)
    compare(row_value, ">=", parse_token_value(val))
  end

  defp parse_raw_condition(row, [col, "<=", val]) do
    row_value = get_column_value(row, col)
    compare(row_value, "<=", parse_token_value(val))
  end

  defp parse_raw_condition(_row, _), do: true

  defp parse_token_value({:string, val}), do: val

  defp parse_token_value(val) when is_binary(val) do
    cond do
      String.upcase(val) == "TRUE" -> true
      String.upcase(val) == "FALSE" -> false
      String.match?(val, ~r/^\d+$/) -> String.to_integer(val)
      String.match?(val, ~r/^\d+\.\d+$/) -> String.to_float(val)
      true -> val
    end
  end

  defp parse_token_value(val), do: val

  defp get_column_value(row, column) when is_binary(column) do
    # Try exact match first, then case-insensitive
    case Map.fetch(row, column) do
      {:ok, val} ->
        val

      :error ->
        lower_col = String.downcase(column)

        Enum.find_value(row, fn {k, v} ->
          if String.downcase(to_string(k)) == lower_col, do: v
        end)
    end
  end

  defp get_column_value(row, column), do: Map.get(row, column)

  defp compare(nil, _, _), do: false
  defp compare(_, _, nil), do: false

  defp compare(a, "=", b), do: normalize_compare(a) == normalize_compare(b)
  defp compare(a, "<>", b), do: normalize_compare(a) != normalize_compare(b)
  defp compare(a, "!=", b), do: normalize_compare(a) != normalize_compare(b)
  defp compare(a, ">", b), do: normalize_compare(a) > normalize_compare(b)
  defp compare(a, "<", b), do: normalize_compare(a) < normalize_compare(b)
  defp compare(a, ">=", b), do: normalize_compare(a) >= normalize_compare(b)
  defp compare(a, "<=", b), do: normalize_compare(a) <= normalize_compare(b)

  defp normalize_compare(val) when is_binary(val), do: String.downcase(val)
  defp normalize_compare(val), do: val

  defp sort_rows(rows, nil), do: rows
  defp sort_rows(rows, []), do: rows

  defp sort_rows(rows, order_by) do
    Enum.sort(rows, fn row_a, row_b ->
      compare_rows_for_sort(row_a, row_b, order_by)
    end)
  end

  defp compare_rows_for_sort(_row_a, _row_b, []), do: true

  defp compare_rows_for_sort(row_a, row_b, [{col, dir, nulls} | rest]) do
    val_a = get_column_value(row_a, col)
    val_b = get_column_value(row_b, col)

    case compare_values(val_a, val_b, dir, nulls) do
      :eq -> compare_rows_for_sort(row_a, row_b, rest)
      :lt -> true
      :gt -> false
    end
  end

  defp compare_values(nil, nil, _dir, _nulls), do: :eq

  defp compare_values(nil, _, _dir, :nulls_first), do: :lt
  defp compare_values(nil, _, _dir, :nulls_last), do: :gt
  defp compare_values(nil, _, :asc, _), do: :gt
  defp compare_values(nil, _, :desc, _), do: :lt

  defp compare_values(_, nil, _dir, :nulls_first), do: :gt
  defp compare_values(_, nil, _dir, :nulls_last), do: :lt
  defp compare_values(_, nil, :asc, _), do: :lt
  defp compare_values(_, nil, :desc, _), do: :gt

  defp compare_values(a, b, dir, _nulls) when is_number(a) and is_number(b) do
    cond do
      a == b -> :eq
      (dir == :asc and a < b) or (dir == :desc and a > b) -> :lt
      true -> :gt
    end
  end

  defp compare_values(a, b, dir, _nulls) when is_binary(a) and is_binary(b) do
    la = String.downcase(a)
    lb = String.downcase(b)

    cond do
      la == lb -> :eq
      (dir == :asc and la < lb) or (dir == :desc and la > lb) -> :lt
      true -> :gt
    end
  end

  defp compare_values(a, b, dir, _nulls) do
    cond do
      a == b -> :eq
      (dir == :asc and a < b) or (dir == :desc and a > b) -> :lt
      true -> :gt
    end
  end

  defp apply_offset(rows, nil), do: rows
  defp apply_offset(rows, offset) when is_integer(offset), do: Enum.drop(rows, offset)
  defp apply_offset(rows, _), do: rows

  defp apply_limit(rows, nil), do: rows
  defp apply_limit(rows, :all), do: rows
  defp apply_limit(rows, limit) when is_integer(limit), do: Enum.take(rows, limit)
  defp apply_limit(rows, _), do: rows

  defp project_columns(rows, [{:all, "*"}]) do
    Enum.map(rows, fn row ->
      Map.delete(row, "__ROWNUM__")
    end)
  end

  defp project_columns(rows, columns) do
    Enum.with_index(rows, 1)
    |> Enum.map(fn {row, rownum} ->
      Enum.reduce(columns, %{}, fn col, acc ->
        {key, value} = evaluate_column(row, col, rownum)
        Map.put(acc, key, value)
      end)
    end)
  end

  defp evaluate_select_columns(row, columns, rownum) do
    Enum.reduce(columns, %{}, fn col, acc ->
      {key, value} = evaluate_column(row, col, rownum)
      Map.put(acc, key, value)
    end)
  end

  defp evaluate_column(row, {:column, name, alias_name}, _rownum) do
    value = get_column_value(row, name)
    key = alias_name || name
    {key, value}
  end

  defp evaluate_column(row, {:function, func_name, args, alias_name}, rownum) do
    value = evaluate_function(func_name, args, row, rownum)
    key = alias_name || "#{String.downcase(func_name)}(#{args_to_string(args)})"
    {key, value}
  end

  defp evaluate_column(row, {:all, "*"}, _rownum) do
    {"*", row}
  end

  defp evaluate_column(_row, col, _rownum) when is_binary(col) do
    {col, col}
  end

  defp evaluate_column(_row, col, _rownum) do
    {inspect(col), nil}
  end

  defp args_to_string(args) do
    args
    |> Enum.map(fn
      {:string, val} -> "'#{val}'"
      other when is_binary(other) -> other
      other -> inspect(other)
    end)
    |> Enum.join(", ")
  end

  # PostgreSQL Functions

  defp evaluate_function("NOW", _, _, _), do: DateTime.utc_now()
  defp evaluate_function("CURRENT_DATE", _, _, _), do: Date.utc_today()
  defp evaluate_function("CURRENT_TIME", _, _, _), do: Time.utc_now()
  defp evaluate_function("CURRENT_TIMESTAMP", _, _, _), do: DateTime.utc_now()

  defp evaluate_function("COALESCE", args, row, _rownum) do
    Enum.find_value(args, fn arg ->
      val = get_column_value(row, arg) || parse_token_value(arg)
      if val != nil, do: val
    end)
  end

  defp evaluate_function("NULLIF", [arg1, arg2 | _], row, _rownum) do
    val1 = get_column_value(row, arg1) || parse_token_value(arg1)
    val2 = get_column_value(row, arg2) || parse_token_value(arg2)
    if val1 == val2, do: nil, else: val1
  end

  defp evaluate_function("GREATEST", args, row, _rownum) do
    args
    |> Enum.map(fn arg -> get_column_value(row, arg) || parse_token_value(arg) end)
    |> Enum.filter(&(&1 != nil))
    |> Enum.max(fn -> nil end)
  end

  defp evaluate_function("LEAST", args, row, _rownum) do
    args
    |> Enum.map(fn arg -> get_column_value(row, arg) || parse_token_value(arg) end)
    |> Enum.filter(&(&1 != nil))
    |> Enum.min(fn -> nil end)
  end

  defp evaluate_function("UPPER", [col | _], row, _rownum) do
    value = get_column_value(row, col)
    if is_binary(value), do: String.upcase(value), else: value
  end

  defp evaluate_function("LOWER", [col | _], row, _rownum) do
    value = get_column_value(row, col)
    if is_binary(value), do: String.downcase(value), else: value
  end

  defp evaluate_function("INITCAP", [col | _], row, _rownum) do
    value = get_column_value(row, col)

    if is_binary(value) do
      value
      |> String.split(~r/\s+/)
      |> Enum.map(fn word ->
        case String.graphemes(word) do
          [] -> ""
          [first | rest] -> String.upcase(first) <> String.downcase(Enum.join(rest))
        end
      end)
      |> Enum.join(" ")
    else
      value
    end
  end

  defp evaluate_function("LENGTH", [col | _], row, _rownum) do
    value = get_column_value(row, col)
    if is_binary(value), do: String.length(value), else: nil
  end

  defp evaluate_function("CHAR_LENGTH", args, row, rownum) do
    evaluate_function("LENGTH", args, row, rownum)
  end

  defp evaluate_function("SUBSTR", [col, start | rest], row, rownum) do
    evaluate_substring(col, start, rest, row, rownum)
  end

  defp evaluate_function("SUBSTRING", [col, start | rest], row, rownum) do
    evaluate_substring(col, start, rest, row, rownum)
  end

  defp evaluate_function("LEFT", [col, n | _], row, _rownum) do
    value = get_column_value(row, col)
    count = parse_token_value(n)
    if is_binary(value) and is_integer(count), do: String.slice(value, 0, count), else: nil
  end

  defp evaluate_function("RIGHT", [col, n | _], row, _rownum) do
    value = get_column_value(row, col)
    count = parse_token_value(n)
    if is_binary(value) and is_integer(count), do: String.slice(value, -count, count), else: nil
  end

  defp evaluate_function("TRIM", [col | _], row, _rownum) do
    value = get_column_value(row, col)
    if is_binary(value), do: String.trim(value), else: value
  end

  defp evaluate_function("LTRIM", [col | _], row, _rownum) do
    value = get_column_value(row, col)
    if is_binary(value), do: String.trim_leading(value), else: value
  end

  defp evaluate_function("RTRIM", [col | _], row, _rownum) do
    value = get_column_value(row, col)
    if is_binary(value), do: String.trim_trailing(value), else: value
  end

  defp evaluate_function("BTRIM", [col | rest], row, _rownum) do
    value = get_column_value(row, col)

    chars =
      case rest do
        [c | _] -> parse_token_value(c)
        [] -> " "
      end

    if is_binary(value) and is_binary(chars) do
      chars_regex = Regex.escape(chars) |> String.graphemes() |> Enum.join("|")
      value |> String.replace(~r/^[#{chars_regex}]+|[#{chars_regex}]+$/, "")
    else
      value
    end
  end

  defp evaluate_function("LPAD", [col, len | rest], row, _rownum) do
    value = get_column_value(row, col) || ""
    length = parse_token_value(len)

    fill =
      case rest do
        [f | _] -> parse_token_value(f)
        [] -> " "
      end

    if is_binary(value) and is_integer(length) do
      String.pad_leading(value, length, fill)
    else
      value
    end
  end

  defp evaluate_function("RPAD", [col, len | rest], row, _rownum) do
    value = get_column_value(row, col) || ""
    length = parse_token_value(len)

    fill =
      case rest do
        [f | _] -> parse_token_value(f)
        [] -> " "
      end

    if is_binary(value) and is_integer(length) do
      String.pad_trailing(value, length, fill)
    else
      value
    end
  end

  defp evaluate_function("REPLACE", [col, from, to | _], row, _rownum) do
    value = get_column_value(row, col)
    from_str = parse_token_value(from)
    to_str = parse_token_value(to)

    if is_binary(value) and is_binary(from_str) and is_binary(to_str) do
      String.replace(value, from_str, to_str)
    else
      value
    end
  end

  defp evaluate_function("POSITION", [substr, "IN", col | _], row, _rownum) do
    value = get_column_value(row, col)
    search = parse_token_value(substr)

    if is_binary(value) and is_binary(search) do
      case :binary.match(value, search) do
        {pos, _} -> pos + 1
        :nomatch -> 0
      end
    else
      0
    end
  end

  defp evaluate_function("CONCAT", args, row, _rownum) do
    args
    |> Enum.map(fn arg ->
      val = get_column_value(row, arg) || parse_token_value(arg)
      if val, do: to_string(val), else: ""
    end)
    |> Enum.join("")
  end

  defp evaluate_function("CONCAT_WS", [sep | args], row, _rownum) do
    separator = parse_token_value(sep)

    args
    |> Enum.map(fn arg ->
      val = get_column_value(row, arg) || parse_token_value(arg)
      if val, do: to_string(val), else: nil
    end)
    |> Enum.filter(&(&1 != nil))
    |> Enum.join(separator)
  end

  defp evaluate_function("SPLIT_PART", [col, delim, part | _], row, _rownum) do
    value = get_column_value(row, col)
    delimiter = parse_token_value(delim)
    part_num = parse_token_value(part)

    if is_binary(value) and is_binary(delimiter) and is_integer(part_num) do
      parts = String.split(value, delimiter)
      Enum.at(parts, part_num - 1) || ""
    else
      nil
    end
  end

  # Numeric functions
  defp evaluate_function("ROUND", [col | rest], row, _rownum) do
    value = get_column_value(row, col) || parse_token_value(col)

    decimals =
      case rest do
        [d | _] -> parse_token_value(d)
        [] -> 0
      end

    if is_number(value) and is_integer(decimals) do
      Float.round(value * 1.0, decimals)
    else
      value
    end
  end

  defp evaluate_function("TRUNC", [col | rest], row, _rownum) do
    value = get_column_value(row, col) || parse_token_value(col)

    decimals =
      case rest do
        [d | _] -> parse_token_value(d)
        [] -> 0
      end

    if is_number(value) and is_integer(decimals) do
      trunc(value * :math.pow(10, decimals)) / :math.pow(10, decimals)
    else
      value
    end
  end

  defp evaluate_function("FLOOR", [col | _], row, _rownum) do
    value = get_column_value(row, col) || parse_token_value(col)
    if is_number(value), do: floor(value), else: nil
  end

  defp evaluate_function("CEIL", [col | _], row, _rownum) do
    value = get_column_value(row, col) || parse_token_value(col)
    if is_number(value), do: ceil(value), else: nil
  end

  defp evaluate_function("CEILING", args, row, rownum) do
    evaluate_function("CEIL", args, row, rownum)
  end

  defp evaluate_function("ABS", [col | _], row, _rownum) do
    value = get_column_value(row, col) || parse_token_value(col)
    if is_number(value), do: abs(value), else: nil
  end

  defp evaluate_function("MOD", [a, b | _], row, _rownum) do
    val_a = get_column_value(row, a) || parse_token_value(a)
    val_b = get_column_value(row, b) || parse_token_value(b)

    if is_number(val_a) and is_number(val_b) and val_b != 0 do
      rem(trunc(val_a), trunc(val_b))
    else
      nil
    end
  end

  defp evaluate_function("POWER", [base, exp | _], row, _rownum) do
    val_base = get_column_value(row, base) || parse_token_value(base)
    val_exp = get_column_value(row, exp) || parse_token_value(exp)

    if is_number(val_base) and is_number(val_exp) do
      :math.pow(val_base, val_exp)
    else
      nil
    end
  end

  defp evaluate_function("SQRT", [col | _], row, _rownum) do
    value = get_column_value(row, col) || parse_token_value(col)
    if is_number(value) and value >= 0, do: :math.sqrt(value), else: nil
  end

  # Aggregate placeholders (actual aggregation would need query-level support)
  defp evaluate_function("COUNT", ["*"], _row, _rownum), do: 1

  defp evaluate_function("COUNT", [col | _], row, _rownum) do
    if get_column_value(row, col) != nil, do: 1, else: 0
  end

  defp evaluate_function("SUM", [col | _], row, _rownum) do
    get_column_value(row, col)
  end

  defp evaluate_function("AVG", [col | _], row, _rownum) do
    get_column_value(row, col)
  end

  defp evaluate_function("MAX", [col | _], row, _rownum) do
    get_column_value(row, col)
  end

  defp evaluate_function("MIN", [col | _], row, _rownum) do
    get_column_value(row, col)
  end

  # Type conversion
  defp evaluate_function("TO_CHAR", [col | _], row, _rownum) do
    value = get_column_value(row, col)
    to_string(value)
  end

  defp evaluate_function("TO_NUMBER", [col | _], row, _rownum) do
    value = get_column_value(row, col) || col

    case value do
      v when is_number(v) ->
        v

      v when is_binary(v) ->
        case Float.parse(v) do
          {f, _} -> f
          :error -> nil
        end

      _ ->
        nil
    end
  end

  defp evaluate_function(_, _, _, _), do: nil

  # Helper function for SUBSTR/SUBSTRING
  defp evaluate_substring(col, start, rest, row, _rownum) do
    value = get_column_value(row, col)
    start_idx = parse_token_value(start)

    length =
      case rest do
        [len | _] -> parse_token_value(len)
        [] -> nil
      end

    if is_binary(value) and is_integer(start_idx) do
      # PostgreSQL SUBSTR is 1-based
      if length do
        String.slice(value, start_idx - 1, length)
      else
        String.slice(value, start_idx - 1, String.length(value))
      end
    else
      nil
    end
  end

  defp apply_update(rows, sets, where) do
    {updated_rows, affected_rows, count} =
      Enum.reduce(rows, {[], [], 0}, fn row, {all, affected, acc} ->
        if evaluate_condition(row, where) do
          updated_row =
            Enum.reduce(sets, row, fn {col, value}, r ->
              actual_key =
                Enum.find(Map.keys(r), fn k ->
                  String.downcase(to_string(k)) == String.downcase(col)
                end) || col

              Map.put(r, actual_key, value)
            end)

          {[updated_row | all], [Map.delete(updated_row, "__ROWNUM__") | affected], acc + 1}
        else
          {[row | all], affected, acc}
        end
      end)

    {Enum.reverse(updated_rows), Enum.reverse(affected_rows), count}
  end

  defp apply_delete(rows, nil) do
    {[], rows, length(rows)}
  end

  defp apply_delete(rows, where) do
    {remaining, deleted} =
      Enum.split_with(rows, fn row ->
        not evaluate_condition(row, where)
      end)

    {remaining, deleted, length(deleted)}
  end
end
