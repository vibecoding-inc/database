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
  def drop_type(server \\ __MODULE__, name, force \\ false) do
    GenServer.call(server, {:drop_type, normalize_name(name), force})
  end

  @doc """
  Alters a user-defined type.
  """
  @spec alter_type(GenServer.server(), String.t(), atom(), any()) :: :ok | {:error, String.t()}
  def alter_type(server \\ __MODULE__, name, action, details) do
    GenServer.call(server, {:alter_type, normalize_name(name), action, details})
  end

  @doc """
  Gets a type definition.
  """
  @spec get_type(GenServer.server(), String.t()) :: {:ok, map()} | {:error, String.t()}
  def get_type(server \\ __MODULE__, name) do
    GenServer.call(server, {:get_type, normalize_name(name)})
  end

  @doc """
  Lists all user-defined types.
  """
  @spec list_types(GenServer.server()) :: [String.t()]
  def list_types(server \\ __MODULE__) do
    GenServer.call(server, :list_types)
  end

  @doc """
  Creates an object instance.
  """
  @spec create_object(GenServer.server(), String.t(), map()) ::
          {:ok, map()} | {:error, String.t()}
  def create_object(server \\ __MODULE__, type_name, values) do
    GenServer.call(server, {:create_object, normalize_name(type_name), values})
  end

  @doc """
  Creates a view.
  """
  @spec create_view(GenServer.server(), String.t(), map()) :: :ok | {:error, String.t()}
  def create_view(server \\ __MODULE__, name, view_def) do
    GenServer.call(server, {:create_view, normalize_name(name), view_def})
  end

  @doc """
  Drops a view.
  """
  @spec drop_view(GenServer.server(), String.t()) :: :ok | {:error, String.t()}
  def drop_view(server \\ __MODULE__, name) do
    GenServer.call(server, {:drop_view, normalize_name(name)})
  end

  @doc """
  Gets a view definition.
  """
  @spec get_view(GenServer.server(), String.t()) :: {:ok, map()} | {:error, String.t()}
  def get_view(server \\ __MODULE__, name) do
    GenServer.call(server, {:get_view, normalize_name(name)})
  end

  @doc """
  Lists all views.
  """
  @spec list_views(GenServer.server()) :: [String.t()]
  def list_views(server \\ __MODULE__) do
    GenServer.call(server, :list_views)
  end

  @doc """
  Creates a materialized view.
  """
  @spec create_materialized_view(GenServer.server(), String.t(), map()) ::
          :ok | {:error, String.t()}
  def create_materialized_view(server \\ __MODULE__, name, view_def) do
    GenServer.call(server, {:create_materialized_view, normalize_name(name), view_def})
  end

  @doc """
  Drops a materialized view.
  """
  @spec drop_materialized_view(GenServer.server(), String.t()) :: :ok | {:error, String.t()}
  def drop_materialized_view(server \\ __MODULE__, name) do
    GenServer.call(server, {:drop_materialized_view, normalize_name(name)})
  end

  @doc """
  Refreshes a materialized view.
  """
  @spec refresh_materialized_view(GenServer.server(), String.t()) :: :ok | {:error, String.t()}
  def refresh_materialized_view(server \\ __MODULE__, name) do
    GenServer.call(server, {:refresh_materialized_view, normalize_name(name)})
  end

  # Stored Procedures and Functions

  @doc """
  Creates a stored procedure.
  """
  @spec create_procedure(GenServer.server(), String.t(), map()) :: :ok | {:error, String.t()}
  def create_procedure(server \\ __MODULE__, name, procedure_def) do
    GenServer.call(server, {:create_procedure, normalize_name(name), procedure_def})
  end

  @doc """
  Drops a stored procedure.
  """
  @spec drop_procedure(GenServer.server(), String.t()) :: :ok | {:error, String.t()}
  def drop_procedure(server \\ __MODULE__, name) do
    GenServer.call(server, {:drop_procedure, normalize_name(name)})
  end

  @doc """
  Gets a stored procedure definition.
  """
  @spec get_procedure(GenServer.server(), String.t()) :: {:ok, map()} | {:error, String.t()}
  def get_procedure(server \\ __MODULE__, name) do
    GenServer.call(server, {:get_procedure, normalize_name(name)})
  end

  @doc """
  Lists all stored procedures.
  """
  @spec list_procedures(GenServer.server()) :: [String.t()]
  def list_procedures(server \\ __MODULE__) do
    GenServer.call(server, :list_procedures)
  end

  @doc """
  Creates a stored function.
  """
  @spec create_function(GenServer.server(), String.t(), map()) :: :ok | {:error, String.t()}
  def create_function(server \\ __MODULE__, name, function_def) do
    GenServer.call(server, {:create_function, normalize_name(name), function_def})
  end

  @doc """
  Drops a stored function.
  """
  @spec drop_function(GenServer.server(), String.t()) :: :ok | {:error, String.t()}
  def drop_function(server \\ __MODULE__, name) do
    GenServer.call(server, {:drop_function, normalize_name(name)})
  end

  @doc """
  Gets a stored function definition.
  """
  @spec get_function(GenServer.server(), String.t()) :: {:ok, map()} | {:error, String.t()}
  def get_function(server \\ __MODULE__, name) do
    GenServer.call(server, {:get_function, normalize_name(name)})
  end

  @doc """
  Lists all stored functions.
  """
  @spec list_functions(GenServer.server()) :: [String.t()]
  def list_functions(server \\ __MODULE__) do
    GenServer.call(server, :list_functions)
  end

  @doc """
  Creates a package.
  """
  @spec create_package(GenServer.server(), String.t(), map()) :: :ok | {:error, String.t()}
  def create_package(server \\ __MODULE__, name, package_def) do
    GenServer.call(server, {:create_package, normalize_name(name), package_def})
  end

  @doc """
  Creates a package body.
  """
  @spec create_package_body(GenServer.server(), String.t(), map()) :: :ok | {:error, String.t()}
  def create_package_body(server \\ __MODULE__, name, body_def) do
    GenServer.call(server, {:create_package_body, normalize_name(name), body_def})
  end

  @doc """
  Drops a package.
  """
  @spec drop_package(GenServer.server(), String.t(), boolean()) :: :ok | {:error, String.t()}
  def drop_package(server \\ __MODULE__, name, body_only \\ false) do
    GenServer.call(server, {:drop_package, normalize_name(name), body_only})
  end

  @doc """
  Gets a package definition.
  """
  @spec get_package(GenServer.server(), String.t()) :: {:ok, map()} | {:error, String.t()}
  def get_package(server \\ __MODULE__, name) do
    GenServer.call(server, {:get_package, normalize_name(name)})
  end

  @doc """
  Lists all packages.
  """
  @spec list_packages(GenServer.server()) :: [String.t()]
  def list_packages(server \\ __MODULE__) do
    GenServer.call(server, :list_packages)
  end

  # Triggers

  @doc """
  Creates a trigger.
  """
  @spec create_trigger(GenServer.server(), String.t(), map()) :: :ok | {:error, String.t()}
  def create_trigger(server \\ __MODULE__, name, trigger_def) do
    GenServer.call(server, {:create_trigger, normalize_name(name), trigger_def})
  end

  @doc """
  Drops a trigger.
  """
  @spec drop_trigger(GenServer.server(), String.t()) :: :ok | {:error, String.t()}
  def drop_trigger(server \\ __MODULE__, name) do
    GenServer.call(server, {:drop_trigger, normalize_name(name)})
  end

  @doc """
  Enables a trigger.
  """
  @spec enable_trigger(GenServer.server(), String.t()) :: :ok | {:error, String.t()}
  def enable_trigger(server \\ __MODULE__, name) do
    GenServer.call(server, {:enable_trigger, normalize_name(name)})
  end

  @doc """
  Disables a trigger.
  """
  @spec disable_trigger(GenServer.server(), String.t()) :: :ok | {:error, String.t()}
  def disable_trigger(server \\ __MODULE__, name) do
    GenServer.call(server, {:disable_trigger, normalize_name(name)})
  end

  @doc """
  Gets a trigger definition.
  """
  @spec get_trigger(GenServer.server(), String.t()) :: {:ok, map()} | {:error, String.t()}
  def get_trigger(server \\ __MODULE__, name) do
    GenServer.call(server, {:get_trigger, normalize_name(name)})
  end

  @doc """
  Lists all triggers.
  """
  @spec list_triggers(GenServer.server()) :: [String.t()]
  def list_triggers(server \\ __MODULE__) do
    GenServer.call(server, :list_triggers)
  end

  @doc """
  Gets triggers for a specific table.
  """
  @spec get_table_triggers(GenServer.server(), String.t()) :: [map()]
  def get_table_triggers(server \\ __MODULE__, table_name) do
    GenServer.call(server, {:get_table_triggers, normalize_name(table_name)})
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
      types: %{},
      views: %{},
      materialized_views: %{},
      procedures: %{},
      functions: %{},
      packages: %{},
      triggers: %{}
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
      row_counter: %{},
      types: %{},
      views: %{},
      materialized_views: %{}
    }

    {:reply, :ok, new_state}
  end

  # Type management callbacks

  @impl true
  def handle_call({:create_type, type_name, type_def}, _from, state) do
    if Map.has_key?(state.types, type_name) and not Map.get(type_def, :replace, false) do
      {:reply, {:error, "Type #{type_name} already exists"}, state}
    else
      new_state = %{state | types: Map.put(state.types, type_name, type_def)}
      {:reply, :ok, new_state}
    end
  end

  @impl true
  def handle_call({:drop_type, type_name, _force}, _from, state) do
    if Map.has_key?(state.types, type_name) do
      new_state = %{state | types: Map.delete(state.types, type_name)}
      {:reply, :ok, new_state}
    else
      {:reply, {:error, "Type #{type_name} does not exist"}, state}
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
        {:reply, {:error, "Type #{type_name} does not exist"}, state}
    end
  end

  @impl true
  def handle_call({:get_type, type_name}, _from, state) do
    case Map.fetch(state.types, type_name) do
      {:ok, type_def} -> {:reply, {:ok, type_def}, state}
      :error -> {:reply, {:error, "Type #{type_name} does not exist"}, state}
    end
  end

  @impl true
  def handle_call(:list_types, _from, state) do
    {:reply, Map.keys(state.types), state}
  end

  @impl true
  def handle_call({:create_object, type_name, values}, _from, state) do
    case Map.fetch(state.types, type_name) do
      {:ok, type_def} ->
        object = create_object_instance(type_name, type_def, values)
        {:reply, {:ok, object}, state}

      :error ->
        {:reply, {:error, "Type #{type_name} does not exist"}, state}
    end
  end

  # View management callbacks

  @impl true
  def handle_call({:create_view, view_name, view_def}, _from, state) do
    if Map.has_key?(state.views, view_name) and not Map.get(view_def, :replace, false) do
      {:reply, {:error, "View #{view_name} already exists"}, state}
    else
      new_state = %{state | views: Map.put(state.views, view_name, view_def)}
      {:reply, :ok, new_state}
    end
  end

  @impl true
  def handle_call({:drop_view, view_name}, _from, state) do
    if Map.has_key?(state.views, view_name) do
      new_state = %{state | views: Map.delete(state.views, view_name)}
      {:reply, :ok, new_state}
    else
      {:reply, {:error, "View #{view_name} does not exist"}, state}
    end
  end

  @impl true
  def handle_call({:get_view, view_name}, _from, state) do
    case Map.fetch(state.views, view_name) do
      {:ok, view_def} -> {:reply, {:ok, view_def}, state}
      :error -> {:reply, {:error, "View #{view_name} does not exist"}, state}
    end
  end

  @impl true
  def handle_call(:list_views, _from, state) do
    {:reply, Map.keys(state.views), state}
  end

  @impl true
  def handle_call({:create_materialized_view, view_name, view_def}, _from, state) do
    if Map.has_key?(state.materialized_views, view_name) do
      {:reply, {:error, "Materialized view #{view_name} already exists"}, state}
    else
      # Execute the underlying query to populate initial data
      query = Map.get(view_def, :query, %{})
      initial_data = execute_materialized_view_query(state, query)

      new_state = %{
        state
        | materialized_views: Map.put(state.materialized_views, view_name, view_def),
          data: Map.put(state.data, view_name, initial_data)
      }

      {:reply, :ok, new_state}
    end
  end

  @impl true
  def handle_call({:drop_materialized_view, view_name}, _from, state) do
    if Map.has_key?(state.materialized_views, view_name) do
      new_state = %{
        state
        | materialized_views: Map.delete(state.materialized_views, view_name),
          data: Map.delete(state.data, view_name)
      }

      {:reply, :ok, new_state}
    else
      {:reply, {:error, "Materialized view #{view_name} does not exist"}, state}
    end
  end

  @impl true
  def handle_call({:refresh_materialized_view, view_name}, _from, state) do
    case Map.fetch(state.materialized_views, view_name) do
      {:ok, view_def} ->
        # Re-execute the underlying query and update the cached data
        query = Map.get(view_def, :query, %{})
        refreshed_data = execute_materialized_view_query(state, query)

        new_state = %{state | data: Map.put(state.data, view_name, refreshed_data)}
        {:reply, :ok, new_state}

      :error ->
        {:reply, {:error, "Materialized view #{view_name} does not exist"}, state}
    end
  end

  # Stored Procedures

  @impl true
  def handle_call({:create_procedure, proc_name, proc_def}, _from, state) do
    replace = Map.get(proc_def, :replace, false)

    if Map.has_key?(state.procedures, proc_name) and not replace do
      {:reply, {:error, "Procedure #{proc_name} already exists"}, state}
    else
      new_state = %{state | procedures: Map.put(state.procedures, proc_name, proc_def)}
      {:reply, :ok, new_state}
    end
  end

  @impl true
  def handle_call({:drop_procedure, proc_name}, _from, state) do
    if Map.has_key?(state.procedures, proc_name) do
      new_state = %{state | procedures: Map.delete(state.procedures, proc_name)}
      {:reply, :ok, new_state}
    else
      {:reply, {:error, "Procedure #{proc_name} does not exist"}, state}
    end
  end

  @impl true
  def handle_call({:get_procedure, proc_name}, _from, state) do
    case Map.fetch(state.procedures, proc_name) do
      {:ok, proc_def} -> {:reply, {:ok, proc_def}, state}
      :error -> {:reply, {:error, "Procedure #{proc_name} does not exist"}, state}
    end
  end

  @impl true
  def handle_call(:list_procedures, _from, state) do
    {:reply, Map.keys(state.procedures), state}
  end

  # Stored Functions

  @impl true
  def handle_call({:create_function, func_name, func_def}, _from, state) do
    replace = Map.get(func_def, :replace, false)

    if Map.has_key?(state.functions, func_name) and not replace do
      {:reply, {:error, "Function #{func_name} already exists"}, state}
    else
      new_state = %{state | functions: Map.put(state.functions, func_name, func_def)}
      {:reply, :ok, new_state}
    end
  end

  @impl true
  def handle_call({:drop_function, func_name}, _from, state) do
    if Map.has_key?(state.functions, func_name) do
      new_state = %{state | functions: Map.delete(state.functions, func_name)}
      {:reply, :ok, new_state}
    else
      {:reply, {:error, "Function #{func_name} does not exist"}, state}
    end
  end

  @impl true
  def handle_call({:get_function, func_name}, _from, state) do
    case Map.fetch(state.functions, func_name) do
      {:ok, func_def} -> {:reply, {:ok, func_def}, state}
      :error -> {:reply, {:error, "Function #{func_name} does not exist"}, state}
    end
  end

  @impl true
  def handle_call(:list_functions, _from, state) do
    {:reply, Map.keys(state.functions), state}
  end

  # Packages

  @impl true
  def handle_call({:create_package, pkg_name, pkg_def}, _from, state) do
    replace = Map.get(pkg_def, :replace, false)

    if Map.has_key?(state.packages, pkg_name) and not replace do
      {:reply, {:error, "Package #{pkg_name} already exists"}, state}
    else
      # When replacing, start fresh with new specification
      # When new, initialize with just the specification
      new_pkg =
        if replace do
          %{spec: pkg_def}
        else
          %{spec: pkg_def}
        end

      new_state = %{state | packages: Map.put(state.packages, pkg_name, new_pkg)}
      {:reply, :ok, new_state}
    end
  end

  @impl true
  def handle_call({:create_package_body, pkg_name, body_def}, _from, state) do
    case Map.fetch(state.packages, pkg_name) do
      {:ok, pkg} ->
        new_pkg = Map.put(pkg, :body, body_def)
        new_state = %{state | packages: Map.put(state.packages, pkg_name, new_pkg)}
        {:reply, :ok, new_state}

      :error ->
        {:reply, {:error, "Package #{pkg_name} does not exist"}, state}
    end
  end

  @impl true
  def handle_call({:drop_package, pkg_name, body_only}, _from, state) do
    case Map.fetch(state.packages, pkg_name) do
      {:ok, pkg} ->
        if body_only do
          new_pkg = Map.delete(pkg, :body)
          new_state = %{state | packages: Map.put(state.packages, pkg_name, new_pkg)}
          {:reply, :ok, new_state}
        else
          new_state = %{state | packages: Map.delete(state.packages, pkg_name)}
          {:reply, :ok, new_state}
        end

      :error ->
        {:reply, {:error, "Package #{pkg_name} does not exist"}, state}
    end
  end

  @impl true
  def handle_call({:get_package, pkg_name}, _from, state) do
    case Map.fetch(state.packages, pkg_name) do
      {:ok, pkg_def} -> {:reply, {:ok, pkg_def}, state}
      :error -> {:reply, {:error, "Package #{pkg_name} does not exist"}, state}
    end
  end

  @impl true
  def handle_call(:list_packages, _from, state) do
    {:reply, Map.keys(state.packages), state}
  end

  # Triggers

  @impl true
  def handle_call({:create_trigger, trigger_name, trigger_def}, _from, state) do
    replace = Map.get(trigger_def, :replace, false)

    if Map.has_key?(state.triggers, trigger_name) and not replace do
      {:reply, {:error, "Trigger #{trigger_name} already exists"}, state}
    else
      # Triggers are enabled by default
      trigger_with_status = Map.put_new(trigger_def, :enabled, true)
      new_state = %{state | triggers: Map.put(state.triggers, trigger_name, trigger_with_status)}
      {:reply, :ok, new_state}
    end
  end

  @impl true
  def handle_call({:drop_trigger, trigger_name}, _from, state) do
    if Map.has_key?(state.triggers, trigger_name) do
      new_state = %{state | triggers: Map.delete(state.triggers, trigger_name)}
      {:reply, :ok, new_state}
    else
      {:reply, {:error, "Trigger #{trigger_name} does not exist"}, state}
    end
  end

  @impl true
  def handle_call({:enable_trigger, trigger_name}, _from, state) do
    case Map.fetch(state.triggers, trigger_name) do
      {:ok, trigger_def} ->
        new_trigger = Map.put(trigger_def, :enabled, true)
        new_state = %{state | triggers: Map.put(state.triggers, trigger_name, new_trigger)}
        {:reply, :ok, new_state}

      :error ->
        {:reply, {:error, "Trigger #{trigger_name} does not exist"}, state}
    end
  end

  @impl true
  def handle_call({:disable_trigger, trigger_name}, _from, state) do
    case Map.fetch(state.triggers, trigger_name) do
      {:ok, trigger_def} ->
        new_trigger = Map.put(trigger_def, :enabled, false)
        new_state = %{state | triggers: Map.put(state.triggers, trigger_name, new_trigger)}
        {:reply, :ok, new_state}

      :error ->
        {:reply, {:error, "Trigger #{trigger_name} does not exist"}, state}
    end
  end

  @impl true
  def handle_call({:get_trigger, trigger_name}, _from, state) do
    case Map.fetch(state.triggers, trigger_name) do
      {:ok, trigger_def} -> {:reply, {:ok, trigger_def}, state}
      :error -> {:reply, {:error, "Trigger #{trigger_name} does not exist"}, state}
    end
  end

  @impl true
  def handle_call(:list_triggers, _from, state) do
    {:reply, Map.keys(state.triggers), state}
  end

  @impl true
  def handle_call({:get_table_triggers, table_name}, _from, state) do
    normalized_table = String.upcase(table_name)

    triggers =
      state.triggers
      |> Enum.filter(fn {_name, trigger_def} ->
        String.upcase(to_string(Map.get(trigger_def, :table, ""))) == normalized_table
      end)
      |> Enum.map(fn {name, def} -> Map.put(def, :name, name) end)

    {:reply, triggers, state}
  end

  # Private functions

  defp normalize_name(name) when is_binary(name), do: String.upcase(name)
  defp normalize_name(name), do: name

  defp apply_type_alter(type_def, :add_attribute, {name, type_info}) do
    new_attrs = type_def.attributes ++ [{name, type_info}]
    {:ok, %{type_def | attributes: new_attrs}}
  end

  defp apply_type_alter(type_def, :drop_attribute, attr_name) do
    new_attrs =
      Enum.reject(type_def.attributes, fn {name, _} ->
        String.upcase(to_string(name)) == String.upcase(attr_name)
      end)

    {:ok, %{type_def | attributes: new_attrs}}
  end

  defp apply_type_alter(type_def, :modify_attribute, {name, type_info}) do
    new_attrs =
      Enum.map(type_def.attributes, fn {attr_name, _} = attr ->
        if String.upcase(to_string(attr_name)) == String.upcase(name) do
          {name, type_info}
        else
          attr
        end
      end)

    {:ok, %{type_def | attributes: new_attrs}}
  end

  defp apply_type_alter(type_def, :add_method, method) do
    new_methods = [method | Map.get(type_def, :methods, [])]
    {:ok, Map.put(type_def, :methods, new_methods)}
  end

  defp apply_type_alter(_type_def, :error, _) do
    {:error, "Invalid ALTER TYPE action"}
  end

  defp create_object_instance(type_name, type_def, values) do
    # Create an object instance with the given values
    attrs = Map.get(type_def, :attributes, [])

    object =
      attrs
      |> Enum.map(fn {name, _type_info} ->
        {String.upcase(to_string(name)),
         Map.get(values, name) || Map.get(values, String.upcase(to_string(name)))}
      end)
      |> Enum.into(%{})

    Map.put(object, "__TYPE__", type_name)
  end

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
    cond do
      # Check if it's a regular table or materialized view (both have data in state.data)
      Map.has_key?(state.data, table_name) ->
        rows = Map.get(state.data, table_name)
        # Apply WHERE filter
        filtered = filter_rows(rows, where)

        # Apply ORDER BY
        sorted = sort_rows(filtered, order_by)

        # Project columns
        projected = project_columns(sorted, columns)

        {:ok, projected}

      # Check if it's a view - execute the underlying query
      Map.has_key?(state.views, table_name) ->
        view_def = Map.get(state.views, table_name)
        execute_view_query(state, view_def, columns, where, order_by)

      # Not found
      true ->
        {:error, "Table #{table_name} does not exist"}
    end
  end

  # Execute a view's underlying query and apply additional filters/projections
  defp execute_view_query(state, view_def, columns, where, order_by) do
    query = Map.get(view_def, :query)

    if query == nil do
      {:error, "View has no underlying query defined"}
    else
      # Execute the view's underlying query
      view_table = Map.get(query, :table)
      # Normalize table name to uppercase for case-insensitive lookup
      normalized_table = if view_table, do: normalize_name(view_table), else: nil
      view_columns = Map.get(query, :columns)
      view_where = Map.get(query, :where)
      view_order_by = Map.get(query, :order_by)

      # First, get the rows from the underlying table
      case execute_select(state, normalized_table, view_columns, view_where, view_order_by) do
        {:ok, view_rows} ->
          # Now apply the outer query's filters and projections
          # Apply additional WHERE filter from outer query
          filtered = filter_rows(view_rows, where)

          # Apply additional ORDER BY from outer query (overrides view's order if specified)
          sorted = if order_by, do: sort_rows(filtered, order_by), else: filtered

          # Project columns from outer query
          # If columns is [{:all, "*"}], return all columns from the view result
          projected = project_view_columns(sorted, columns, view_def)

          {:ok, projected}

        {:error, _} = error ->
          error
      end
    end
  end

  # Project columns from a view query result
  defp project_view_columns(rows, [{:all, "*"}], _view_def) do
    # Return all columns as-is (already projected by view query)
    rows
  end

  defp project_view_columns(rows, columns, view_def) do
    # Map view column aliases to actual column names if defined
    column_aliases = get_view_column_aliases(view_def)

    Enum.with_index(rows, 1)
    |> Enum.map(fn {row, rownum} ->
      Enum.reduce(columns, %{}, fn col, acc ->
        {key, value} = evaluate_view_column(row, col, rownum, column_aliases)
        Map.put(acc, key, value)
      end)
    end)
  end

  # Get the column alias mapping from view definition
  defp get_view_column_aliases(view_def) do
    case Map.get(view_def, :columns) do
      nil -> %{}
      cols when is_list(cols) ->
        # Map explicit view column names to query result columns
        query = Map.get(view_def, :query, %{})
        query_cols = Map.get(query, :columns, [])

        Enum.zip(cols, query_cols)
        |> Enum.reduce(%{}, fn {alias_name, query_col}, acc ->
          col_name = case query_col do
            {:column, name, _} -> name
            {:function, _, _, alias_n} -> alias_n
            _ -> nil
          end
          if col_name, do: Map.put(acc, String.upcase(alias_name), col_name), else: acc
        end)
    end
  end

  defp evaluate_view_column(row, {:column, name, alias_name}, _rownum, column_aliases) do
    # Check if name is a view column alias
    actual_name = Map.get(column_aliases, String.upcase(name), name)
    value = get_column_value(row, actual_name)
    key = alias_name || name
    {key, value}
  end

  defp evaluate_view_column(row, col, rownum, _column_aliases) do
    evaluate_column(row, col, rownum)
  end

  # Execute a materialized view's underlying query to populate data
  defp execute_materialized_view_query(state, query) do
    table = Map.get(query, :table)
    # Normalize table name to uppercase for case-insensitive lookup
    normalized_table = if table, do: normalize_name(table), else: nil
    columns = Map.get(query, :columns)
    where = Map.get(query, :where)
    order_by = Map.get(query, :order_by)

    case execute_select(state, normalized_table, columns, where, order_by) do
      {:ok, rows} -> rows
      {:error, _} -> []
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

  # XML Functions

  # XMLELEMENT creates an XML element with specified name and content.
  # Usage: XMLELEMENT(NAME tag_name, content) or XMLELEMENT(NAME tag_name, XMLATTRIBUTES(...), content)
  defp evaluate_function("XMLELEMENT", args, row, _rownum) do
    case args do
      ["NAME", tag_name | rest] ->
        {attrs, content} = parse_xml_element_args(rest, row)
        build_xml_element(tag_name, attrs, content)

      [tag_name | rest] ->
        {attrs, content} = parse_xml_element_args(rest, row)
        build_xml_element(tag_name, attrs, content)

      _ ->
        nil
    end
  end

  # XMLFOREST creates a forest of XML elements from column values.
  # Usage: XMLFOREST(col1 AS name1, col2 AS name2, ...)
  defp evaluate_function("XMLFOREST", args, row, _rownum) do
    elements =
      args
      |> parse_forest_args()
      |> Enum.map(fn {col, name} ->
        value = get_column_value(row, col) || parse_token_value(col)
        safe_name = sanitize_xml_name(name)
        if value != nil, do: "<#{safe_name}>#{escape_xml(value)}</#{safe_name}>", else: ""
      end)
      |> Enum.filter(&(&1 != ""))
      |> Enum.join("")

    elements
  end

  # XMLAGG aggregates XML fragments into a single XML document.
  # Note: In Oracle, XMLAGG is typically used with GROUP BY to aggregate across rows.
  # In this single-row evaluation context, it returns the column value as-is.
  # Full aggregate behavior would require query-level aggregation support.
  defp evaluate_function("XMLAGG", args, row, _rownum) do
    case args do
      [col | _] ->
        value = get_column_value(row, col)
        if is_binary(value), do: value, else: to_string(value)

      _ ->
        nil
    end
  end

  # XMLROOT adds an XML declaration to an XML document.
  # Usage: XMLROOT(xml_value, VERSION version_string)
  defp evaluate_function("XMLROOT", args, row, _rownum) do
    case args do
      [xml_col, "VERSION", version | _] ->
        xml_content = get_column_value(row, xml_col) || parse_token_value(xml_col)
        version_str = parse_token_value(version)
        ~s(<?xml version="#{version_str}"?>#{xml_content})

      [xml_col | _] ->
        xml_content = get_column_value(row, xml_col) || parse_token_value(xml_col)
        ~s(<?xml version="1.0"?>#{xml_content})

      _ ->
        nil
    end
  end

  # XMLPARSE parses a string as XML content.
  # Usage: XMLPARSE(CONTENT string_value) or XMLPARSE(DOCUMENT string_value)
  defp evaluate_function("XMLPARSE", args, row, _rownum) do
    case args do
      ["CONTENT", value | _] ->
        get_column_value(row, value) || parse_token_value(value)

      ["DOCUMENT", value | _] ->
        content = get_column_value(row, value) || parse_token_value(value)
        ~s(<?xml version="1.0"?>#{content})

      [value | _] ->
        get_column_value(row, value) || parse_token_value(value)

      _ ->
        nil
    end
  end

  # XMLSERIALIZE converts XML to a string with optional formatting.
  # Usage: XMLSERIALIZE(CONTENT xml_value AS datatype)
  defp evaluate_function("XMLSERIALIZE", args, row, _rownum) do
    case args do
      ["CONTENT", value | _] ->
        result = get_column_value(row, value) || parse_token_value(value)
        to_string(result)

      ["DOCUMENT", value | _] ->
        result = get_column_value(row, value) || parse_token_value(value)
        to_string(result)

      [value | _] ->
        result = get_column_value(row, value) || parse_token_value(value)
        to_string(result)

      _ ->
        nil
    end
  end

  # XMLCONCAT concatenates multiple XML fragments.
  # Usage: XMLCONCAT(xml1, xml2, ...)
  defp evaluate_function("XMLCONCAT", args, row, _rownum) do
    args
    |> Enum.map(fn arg ->
      value = get_column_value(row, arg) || parse_token_value(arg)
      if value != nil, do: to_string(value), else: ""
    end)
    |> Enum.join("")
  end

  # XMLCOMMENT creates an XML comment.
  # Usage: XMLCOMMENT(string_value)
  defp evaluate_function("XMLCOMMENT", args, row, _rownum) do
    case args do
      [value | _] ->
        content = get_column_value(row, value) || parse_token_value(value)
        "<!--#{content}-->"

      _ ->
        nil
    end
  end

  # XMLPI creates an XML processing instruction.
  # Usage: XMLPI(NAME target, string_value)
  defp evaluate_function("XMLPI", args, row, _rownum) do
    case args do
      ["NAME", target, value | _] ->
        content = get_column_value(row, value) || parse_token_value(value)
        "<?#{target} #{content}?>"

      ["NAME", target | _] ->
        "<?#{target}?>"

      [target, value | _] ->
        content = get_column_value(row, value) || parse_token_value(value)
        "<?#{target} #{content}?>"

      [target | _] ->
        "<?#{target}?>"

      _ ->
        nil
    end
  end

  # XMLATTRIBUTES creates attributes for an XML element.
  # This is typically used within XMLELEMENT.
  # Usage: XMLATTRIBUTES(col1 AS attr1, col2 AS attr2, ...)
  defp evaluate_function("XMLATTRIBUTES", args, row, _rownum) do
    attrs =
      args
      |> parse_forest_args()
      |> Enum.map(fn {col, name} ->
        value = get_column_value(row, col) || parse_token_value(col)
        safe_name = sanitize_xml_name(name)
        if value != nil, do: ~s(#{safe_name}="#{escape_xml_attr(value)}"), else: ""
      end)
      |> Enum.filter(&(&1 != ""))
      |> Enum.join(" ")

    attrs
  end

  # XMLCDATA creates a CDATA section.
  # Usage: XMLCDATA(string_value)
  defp evaluate_function("XMLCDATA", args, row, _rownum) do
    case args do
      [value | _] ->
        content = get_column_value(row, value) || parse_token_value(value)
        "<![CDATA[#{content}]]>"

      _ ->
        nil
    end
  end

  defp evaluate_function(_, _, _, _), do: nil

  # XML Helper Functions

  defp parse_xml_element_args(args, row) do
    # Look for XMLATTRIBUTES in args
    case Enum.find_index(args, &(&1 == "XMLATTRIBUTES" or &1 == "(")) do
      nil ->
        # No attributes, all args are content
        content =
          args
          |> Enum.map(fn arg ->
            case arg do
              {:string, val} -> val
              _ -> get_column_value(row, arg) || parse_token_value(arg)
            end
          end)
          |> Enum.filter(&(&1 != nil))
          |> Enum.map(&to_string/1)
          |> Enum.join("")

        {"", content}

      _ ->
        # Has nested content, parse it
        content =
          args
          |> Enum.map(fn arg ->
            case arg do
              {:string, val} -> val
              "(" -> nil
              ")" -> nil
              "," -> nil
              _ -> get_column_value(row, arg) || parse_token_value(arg)
            end
          end)
          |> Enum.filter(&(&1 != nil))
          |> Enum.map(&to_string/1)
          |> Enum.join("")

        {"", content}
    end
  end

  defp build_xml_element(tag_name, "", content) when content == "" or is_nil(content) do
    safe_tag = sanitize_xml_name(tag_name)
    "<#{safe_tag}/>"
  end

  defp build_xml_element(tag_name, "", content) do
    safe_tag = sanitize_xml_name(tag_name)
    "<#{safe_tag}>#{escape_xml(content)}</#{safe_tag}>"
  end

  defp build_xml_element(tag_name, attrs, content) when content == "" or is_nil(content) do
    safe_tag = sanitize_xml_name(tag_name)
    "<#{safe_tag} #{attrs}/>"
  end

  defp build_xml_element(tag_name, attrs, content) do
    safe_tag = sanitize_xml_name(tag_name)
    "<#{safe_tag} #{attrs}>#{escape_xml(content)}</#{safe_tag}>"
  end

  # Sanitize XML element/attribute names to prevent injection
  # XML names must start with a letter or underscore and can only contain
  # letters, digits, hyphens, underscores, and periods
  defp sanitize_xml_name(name) when is_binary(name) do
    name
    |> String.replace(~r/[^a-zA-Z0-9_\-\.]/, "_")
    |> ensure_valid_xml_start()
  end

  defp sanitize_xml_name(name), do: sanitize_xml_name(to_string(name))

  defp ensure_valid_xml_start(name) do
    if String.match?(name, ~r/^[a-zA-Z_]/) do
      name
    else
      "_" <> name
    end
  end

  defp parse_forest_args(args) do
    # Parse col AS name pairs from args
    parse_forest_args(args, [])
  end

  defp parse_forest_args([], acc), do: Enum.reverse(acc)

  defp parse_forest_args([col, "AS", name | rest], acc) do
    parse_forest_args(rest, [{col, name} | acc])
  end

  defp parse_forest_args(["," | rest], acc) do
    parse_forest_args(rest, acc)
  end

  defp parse_forest_args([col | rest], acc) do
    # No AS clause, use column name as element name
    parse_forest_args(rest, [{col, col} | acc])
  end

  defp escape_xml(value) when is_binary(value) do
    value
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
  end

  defp escape_xml(value), do: to_string(value)

  defp escape_xml_attr(value) when is_binary(value) do
    value
    |> escape_xml()
    |> String.replace("\"", "&quot;")
    |> String.replace("'", "&apos;")
  end

  defp escape_xml_attr(value), do: escape_xml(to_string(value))

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
