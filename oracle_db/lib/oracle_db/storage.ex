defmodule OracleDb.Storage do
  @moduledoc """
  In-memory storage engine for the Oracle-compatible database.
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
  @spec create_table(GenServer.server(), table_name(), table_schema()) ::
          :ok | {:error, String.t()}
  def create_table(server \\ __MODULE__, table_name, schema) do
    GenServer.call(server, {:create_table, normalize_name(table_name), schema})
  end

  @doc """
  Drops a table.
  """
  @spec drop_table(GenServer.server(), table_name(), boolean()) :: :ok | {:error, String.t()}
  def drop_table(server \\ __MODULE__, table_name, cascade \\ false) do
    GenServer.call(server, {:drop_table, normalize_name(table_name), cascade})
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
  @spec insert(GenServer.server(), table_name(), [column_name()] | nil, [any()]) ::
          {:ok, integer()} | {:error, String.t()}
  def insert(server \\ __MODULE__, table_name, columns, values) do
    GenServer.call(server, {:insert, normalize_name(table_name), columns, values})
  end

  @doc """
  Selects rows from a table.
  """
  @spec select(GenServer.server(), table_name() | nil, list(), any(), any()) ::
          {:ok, [row()]} | {:error, String.t()}
  def select(server \\ __MODULE__, table_name, columns, where, order_by) do
    normalized_table = if table_name, do: normalize_name(table_name), else: nil
    GenServer.call(server, {:select, normalized_table, columns, where, order_by})
  end

  @doc """
  Updates rows in a table.
  """
  @spec update(GenServer.server(), table_name(), [{column_name(), any()}], any()) ::
          {:ok, integer()} | {:error, String.t()}
  def update(server \\ __MODULE__, table_name, sets, where) do
    GenServer.call(server, {:update, normalize_name(table_name), sets, where})
  end

  @doc """
  Deletes rows from a table.
  """
  @spec delete(GenServer.server(), table_name(), any()) :: {:ok, integer()} | {:error, String.t()}
  def delete(server \\ __MODULE__, table_name, where) do
    GenServer.call(server, {:delete, normalize_name(table_name), where})
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
  @spec drop_index(GenServer.server(), String.t()) :: :ok | {:error, String.t()}
  def drop_index(server \\ __MODULE__, index_name) do
    GenServer.call(server, {:drop_index, index_name})
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
  @spec drop_sequence(GenServer.server(), String.t()) :: :ok | {:error, String.t()}
  def drop_sequence(server \\ __MODULE__, name) do
    GenServer.call(server, {:drop_sequence, normalize_name(name)})
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
      row_counter: %{}
    }

    {:ok, state}
  end

  @impl true
  def handle_call({:create_table, table_name, schema}, _from, state) do
    if Map.has_key?(state.tables, table_name) do
      {:reply, {:error, "Table #{table_name} already exists"}, state}
    else
      new_state = %{
        state
        | tables: Map.put(state.tables, table_name, schema),
          data: Map.put(state.data, table_name, []),
          row_counter: Map.put(state.row_counter, table_name, 0)
      }

      {:reply, :ok, new_state}
    end
  end

  @impl true
  def handle_call({:drop_table, table_name, _cascade}, _from, state) do
    if Map.has_key?(state.tables, table_name) do
      new_state = %{
        state
        | tables: Map.delete(state.tables, table_name),
          data: Map.delete(state.data, table_name),
          row_counter: Map.delete(state.row_counter, table_name)
      }

      {:reply, :ok, new_state}
    else
      {:reply, {:error, "Table #{table_name} does not exist"}, state}
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
      :error -> {:reply, {:error, "Table #{table_name} does not exist"}, state}
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
        {:reply, {:error, "Table #{table_name} does not exist"}, state}
    end
  end

  @impl true
  def handle_call({:insert, table_name, columns, values_list}, _from, state) do
    case Map.fetch(state.tables, table_name) do
      {:ok, schema} ->
        case insert_rows(state, table_name, schema, columns, values_list) do
          {:ok, new_state, count} -> {:reply, {:ok, count}, new_state}
          {:error, _} = err -> {:reply, err, state}
        end

      :error ->
        {:reply, {:error, "Table #{table_name} does not exist"}, state}
    end
  end

  @impl true
  def handle_call({:select, table_name, columns, where, order_by}, _from, state) do
    result = execute_select(state, table_name, columns, where, order_by)
    {:reply, result, state}
  end

  @impl true
  def handle_call({:update, table_name, sets, where}, _from, state) do
    case Map.fetch(state.data, table_name) do
      {:ok, rows} ->
        {updated_rows, count} = apply_update(rows, sets, where)
        new_state = %{state | data: Map.put(state.data, table_name, updated_rows)}
        {:reply, {:ok, count}, new_state}

      :error ->
        {:reply, {:error, "Table #{table_name} does not exist"}, state}
    end
  end

  @impl true
  def handle_call({:delete, table_name, where}, _from, state) do
    case Map.fetch(state.data, table_name) do
      {:ok, rows} ->
        {remaining_rows, deleted_count} = apply_delete(rows, where)
        new_state = %{state | data: Map.put(state.data, table_name, remaining_rows)}
        {:reply, {:ok, deleted_count}, new_state}

      :error ->
        {:reply, {:error, "Table #{table_name} does not exist"}, state}
    end
  end

  @impl true
  def handle_call({:create_index, index_name, table_name, columns, unique}, _from, state) do
    if Map.has_key?(state.tables, table_name) do
      index = %{table: table_name, columns: columns, unique: unique}
      new_state = %{state | indexes: Map.put(state.indexes, index_name, index)}
      {:reply, :ok, new_state}
    else
      {:reply, {:error, "Table #{table_name} does not exist"}, state}
    end
  end

  @impl true
  def handle_call({:drop_index, index_name}, _from, state) do
    if Map.has_key?(state.indexes, index_name) do
      new_state = %{state | indexes: Map.delete(state.indexes, index_name)}
      {:reply, :ok, new_state}
    else
      {:reply, {:error, "Index #{index_name} does not exist"}, state}
    end
  end

  @impl true
  def handle_call({:create_sequence, name, options}, _from, state) do
    if Map.has_key?(state.sequences, name) do
      {:reply, {:error, "Sequence #{name} already exists"}, state}
    else
      sequence = %{
        current: Map.get(options, :start, 1) - Map.get(options, :increment, 1),
        increment: Map.get(options, :increment, 1),
        min_value: Map.get(options, :min_value, 1),
        max_value: Map.get(options, :max_value, 999_999_999_999_999_999),
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
        {:reply, {:error, "Sequence #{name} does not exist"}, state}
    end
  end

  @impl true
  def handle_call({:currval, name}, _from, state) do
    case Map.fetch(state.sequences, name) do
      {:ok, %{initialized: false}} ->
        {:reply, {:error, "CURRVAL is not yet defined for sequence #{name}"}, state}

      {:ok, seq} ->
        {:reply, {:ok, seq.current}, state}

      :error ->
        {:reply, {:error, "Sequence #{name} does not exist"}, state}
    end
  end

  @impl true
  def handle_call({:drop_sequence, name}, _from, state) do
    if Map.has_key?(state.sequences, name) do
      new_state = %{state | sequences: Map.delete(state.sequences, name)}
      {:reply, :ok, new_state}
    else
      {:reply, {:error, "Sequence #{name} does not exist"}, state}
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
      row_counter: %{}
    }

    {:reply, :ok, new_state}
  end

  # Private functions

  defp normalize_name(name) when is_binary(name), do: String.upcase(name)
  defp normalize_name(name), do: name

  defp apply_alter(schema, :add_column, {name, type, modifiers}) do
    new_columns = schema.columns ++ [{name, type, modifiers}]
    {:ok, %{schema | columns: new_columns}}
  end

  defp apply_alter(schema, :drop_column, column_name) do
    new_columns =
      Enum.reject(schema.columns, fn {name, _, _} ->
        String.upcase(name) == String.upcase(column_name)
      end)

    {:ok, %{schema | columns: new_columns}}
  end

  defp apply_alter(schema, :modify_column, {name, type, modifiers}) do
    new_columns =
      Enum.map(schema.columns, fn {col_name, _, _} = col ->
        if String.upcase(col_name) == String.upcase(name) do
          {name, type, modifiers}
        else
          col
        end
      end)

    {:ok, %{schema | columns: new_columns}}
  end

  defp apply_alter(schema, :rename_column, {old_name, new_name}) do
    new_columns =
      Enum.map(schema.columns, fn {col_name, type, mods} ->
        if String.upcase(col_name) == String.upcase(old_name) do
          {new_name, type, mods}
        else
          {col_name, type, mods}
        end
      end)

    {:ok, %{schema | columns: new_columns}}
  end

  defp apply_alter(schema, :add_constraint, constraint) do
    new_constraints = [constraint | schema.constraints]
    {:ok, %{schema | constraints: new_constraints}}
  end

  defp apply_alter(schema, :drop_constraint, _constraint_name) do
    # For simplicity, just return unchanged schema
    {:ok, schema}
  end

  defp apply_alter(_schema, :error, _) do
    {:error, "Invalid ALTER TABLE action"}
  end

  defp insert_rows(state, table_name, schema, columns, values_list) do
    column_names =
      if columns do
        columns
      else
        Enum.map(schema.columns, fn {name, _, _} -> name end)
      end

    {new_rows, new_counter} =
      Enum.reduce(values_list, {[], state.row_counter[table_name]}, fn values, {acc, counter} ->
        row = build_row(column_names, values, counter + 1)
        {[row | acc], counter + 1}
      end)

    existing_rows = Map.get(state.data, table_name, [])

    new_state = %{
      state
      | data: Map.put(state.data, table_name, existing_rows ++ Enum.reverse(new_rows)),
        row_counter: Map.put(state.row_counter, table_name, new_counter)
    }

    {:ok, new_state, length(values_list)}
  end

  defp build_row(columns, values, rownum) do
    row =
      columns
      |> Enum.zip(values)
      |> Enum.into(%{})

    Map.put(row, "__ROWNUM__", rownum)
  end

  defp execute_select(_state, nil, columns, _where, _order_by) do
    # SELECT from DUAL or no table (Oracle allows SELECT 1 FROM DUAL)
    row = evaluate_select_columns(%{}, columns, 1)
    {:ok, [row]}
  end

  defp execute_select(_state, "DUAL", columns, _where, _order_by) do
    # Oracle's DUAL table
    row = evaluate_select_columns(%{}, columns, 1)
    {:ok, [row]}
  end

  defp execute_select(state, table_name, columns, where, order_by) do
    case Map.fetch(state.data, table_name) do
      {:ok, rows} ->
        # Apply WHERE filter
        filtered = filter_rows(rows, where)

        # Apply ORDER BY
        sorted = sort_rows(filtered, order_by)

        # Project columns
        projected = project_columns(sorted, columns)

        {:ok, projected}

      :error ->
        {:error, "Table #{table_name} does not exist"}
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

      Regex.match?(~r/^#{regex_pattern}$/i, row_value)
    else
      false
    end
  end

  defp evaluate_condition(row, {:raw, tokens}) do
    # Try to parse simple comparisons from raw tokens
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
        upcase_col = String.upcase(column)

        Enum.find_value(row, fn {k, v} ->
          if String.upcase(to_string(k)) == upcase_col, do: v
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

  defp normalize_compare(val) when is_binary(val), do: String.upcase(val)
  defp normalize_compare(val), do: val

  defp sort_rows(rows, nil), do: rows
  defp sort_rows(rows, []), do: rows

  defp sort_rows(rows, order_by) do
    Enum.sort(rows, fn row_a, row_b ->
      compare_rows_for_sort(row_a, row_b, order_by)
    end)
  end

  defp compare_rows_for_sort(_row_a, _row_b, []), do: true

  defp compare_rows_for_sort(row_a, row_b, [{col, dir} | rest]) do
    val_a = get_column_value(row_a, col)
    val_b = get_column_value(row_b, col)

    case compare_values(val_a, val_b, dir) do
      :eq -> compare_rows_for_sort(row_a, row_b, rest)
      :lt -> true
      :gt -> false
    end
  end

  defp compare_values(nil, nil, _dir), do: :eq
  defp compare_values(nil, _, :asc), do: :lt
  defp compare_values(nil, _, :desc), do: :gt
  defp compare_values(_, nil, :asc), do: :gt
  defp compare_values(_, nil, :desc), do: :lt

  defp compare_values(a, b, dir) when is_number(a) and is_number(b) do
    cond do
      a == b -> :eq
      (dir == :asc and a < b) or (dir == :desc and a > b) -> :lt
      true -> :gt
    end
  end

  defp compare_values(a, b, dir) when is_binary(a) and is_binary(b) do
    ua = String.upcase(a)
    ub = String.upcase(b)

    cond do
      ua == ub -> :eq
      (dir == :asc and ua < ub) or (dir == :desc and ua > ub) -> :lt
      true -> :gt
    end
  end

  defp compare_values(a, b, dir) do
    # Fallback comparison
    cond do
      a == b -> :eq
      (dir == :asc and a < b) or (dir == :desc and a > b) -> :lt
      true -> :gt
    end
  end

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
    key = alias_name || "#{func_name}(#{args_to_string(args)})"
    {key, value}
  end

  defp evaluate_column(row, {:all, "*"}, _rownum) do
    {"*", row}
  end

  defp evaluate_column(_row, col, _rownum) when is_binary(col) do
    # Direct column reference
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

  defp evaluate_function("SYSDATE", _, _, _), do: Date.utc_today()
  defp evaluate_function("ROWNUM", _, _, rownum), do: rownum

  defp evaluate_function("NVL", [col, default | _], row, _rownum) do
    value = get_column_value(row, col)
    if value == nil, do: parse_token_value(default), else: value
  end

  defp evaluate_function("NVL2", [col, not_null_val, null_val | _], row, _rownum) do
    value = get_column_value(row, col)
    if value == nil, do: parse_token_value(null_val), else: parse_token_value(not_null_val)
  end

  defp evaluate_function("COALESCE", args, row, _rownum) do
    Enum.find_value(args, fn arg ->
      val = get_column_value(row, arg)
      if val != nil, do: val
    end)
  end

  defp evaluate_function("UPPER", [col | _], row, _rownum) do
    value = get_column_value(row, col)
    if is_binary(value), do: String.upcase(value), else: value
  end

  defp evaluate_function("LOWER", [col | _], row, _rownum) do
    value = get_column_value(row, col)
    if is_binary(value), do: String.downcase(value), else: value
  end

  defp evaluate_function("LENGTH", [col | _], row, _rownum) do
    value = get_column_value(row, col)
    if is_binary(value), do: String.length(value), else: nil
  end

  defp evaluate_function("SUBSTR", [col, start | rest], row, _rownum) do
    value = get_column_value(row, col)
    start_idx = parse_token_value(start)

    length =
      case rest do
        [len | _] -> parse_token_value(len)
        [] -> nil
      end

    if is_binary(value) and is_integer(start_idx) do
      # Oracle SUBSTR is 1-based
      if length do
        String.slice(value, start_idx - 1, length)
      else
        String.slice(value, start_idx - 1, String.length(value))
      end
    else
      nil
    end
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
          {f, _} ->
            f

          :error ->
            case Integer.parse(v) do
              {i, _} -> i
              :error -> nil
            end
        end

      _ ->
        nil
    end
  end

  defp evaluate_function("COUNT", ["*"], _row, _rownum), do: 1

  defp evaluate_function("COUNT", [col | _], row, _rownum) do
    if get_column_value(row, col) != nil, do: 1, else: 0
  end

  defp evaluate_function(_, _, _, _), do: nil

  defp apply_update(rows, sets, where) do
    {updated, count} =
      Enum.map_reduce(rows, 0, fn row, acc ->
        if evaluate_condition(row, where) do
          updated_row =
            Enum.reduce(sets, row, fn {col, value}, r ->
              # Find the actual key in the row (case-insensitive)
              actual_key =
                Enum.find(Map.keys(r), fn k ->
                  String.upcase(to_string(k)) == String.upcase(col)
                end) || col

              Map.put(r, actual_key, value)
            end)

          {updated_row, acc + 1}
        else
          {row, acc}
        end
      end)

    {updated, count}
  end

  defp apply_delete(rows, nil) do
    {[], length(rows)}
  end

  defp apply_delete(rows, where) do
    {remaining, deleted} =
      Enum.split_with(rows, fn row ->
        not evaluate_condition(row, where)
      end)

    {remaining, length(deleted)}
  end
end
