defmodule VibeDb do
  @moduledoc """
  A VibeDb SQL-compatible relational database implemented in Elixir.

  This module provides a simple in-memory database that supports VibeDb SQL syntax
  including:

  - DDL: CREATE TABLE, DROP TABLE, ALTER TABLE, CREATE INDEX, CREATE SEQUENCE
  - DML: SELECT, INSERT, UPDATE, DELETE
  - VibeDb-specific features: DUAL table, ROWNUM, NVL, NVL2, DECODE, SYSDATE, sequences

  ## Examples

      # Start the database
      {:ok, db} = VibeDb.start_link()

      # Create a table
      VibeDb.execute(db, "CREATE TABLE users (id NUMBER PRIMARY KEY, name VARCHAR2(100), email VARCHAR2(255))")

      # Insert data
      VibeDb.execute(db, "INSERT INTO users (id, name, email) VALUES (1, 'John Doe', 'john@example.com')")

      # Query data
      VibeDb.execute(db, "SELECT * FROM users WHERE id = 1")

      # Use VibeDb-specific features
      VibeDb.execute(db, "SELECT SYSDATE FROM DUAL")
      VibeDb.execute(db, "SELECT NVL(email, 'no email') FROM users")

  """

  use GenServer

  alias VibeDb.Storage
  alias VibeDb.QueryExecutor

  @type server :: GenServer.server()
  @type result :: {:ok, any()} | {:error, String.t()}

  # Client API

  @doc """
  Starts the VibeDb database server.

  ## Options

    * `:name` - Optional name for the server process

  ## Examples

      {:ok, db} = VibeDb.start_link()
      {:ok, db} = VibeDb.start_link(name: :my_database)

  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Executes an SQL statement.

  Supports VibeDb SQL syntax including:
  - SELECT, INSERT, UPDATE, DELETE
  - CREATE TABLE, DROP TABLE, ALTER TABLE
  - CREATE INDEX, DROP INDEX
  - CREATE SEQUENCE, DROP SEQUENCE
  - VibeDb functions: NVL, NVL2, DECODE, SYSDATE, ROWNUM, etc.

  ## Examples

      VibeDb.execute(db, "CREATE TABLE test (id NUMBER, name VARCHAR2(50))")
      VibeDb.execute(db, "INSERT INTO test VALUES (1, 'hello')")
      {:ok, rows} = VibeDb.execute(db, "SELECT * FROM test")

  """
  @spec execute(server(), String.t()) :: result()
  def execute(server, sql) when is_binary(sql) do
    GenServer.call(server, {:execute, sql})
  end

  @doc """
  Lists all tables in the database.

  ## Examples

      tables = VibeDb.list_tables(db)

  """
  @spec list_tables(server()) :: [String.t()]
  def list_tables(server) do
    GenServer.call(server, :list_tables)
  end

  @doc """
  Gets the schema for a table.

  ## Examples

      {:ok, schema} = VibeDb.get_schema(db, "users")

  """
  @spec get_schema(server(), String.t()) :: {:ok, map()} | {:error, String.t()}
  def get_schema(server, table_name) do
    GenServer.call(server, {:get_schema, table_name})
  end

  @doc """
  Checks if a table exists.

  ## Examples

      true = VibeDb.table_exists?(db, "users")

  """
  @spec table_exists?(server(), String.t()) :: boolean()
  def table_exists?(server, table_name) do
    GenServer.call(server, {:table_exists?, table_name})
  end

  @doc """
  Gets the next value from a sequence.

  ## Examples

      {:ok, _} = VibeDb.execute(db, "CREATE SEQUENCE my_seq START WITH 1")
      {:ok, 1} = VibeDb.nextval(db, "my_seq")
      {:ok, 2} = VibeDb.nextval(db, "my_seq")

  """
  @spec nextval(server(), String.t()) :: {:ok, integer()} | {:error, String.t()}
  def nextval(server, sequence_name) do
    GenServer.call(server, {:nextval, sequence_name})
  end

  @doc """
  Gets the current value from a sequence (must call nextval first).

  ## Examples

      {:ok, 1} = VibeDb.nextval(db, "my_seq")
      {:ok, 1} = VibeDb.currval(db, "my_seq")

  """
  @spec currval(server(), String.t()) :: {:ok, integer()} | {:error, String.t()}
  def currval(server, sequence_name) do
    GenServer.call(server, {:currval, sequence_name})
  end

  @doc """
  Resets the database, clearing all tables and data.

  ## Examples

      :ok = VibeDb.reset(db)

  """
  @spec reset(server()) :: :ok
  def reset(server) do
    GenServer.call(server, :reset)
  end

  @doc """
  Lists all user-defined types in the database.

  ## Examples

      types = VibeDb.list_types(db)

  """
  @spec list_types(server()) :: [String.t()]
  def list_types(server) do
    GenServer.call(server, :list_types)
  end

  @doc """
  Lists all views in the database.

  ## Examples

      views = VibeDb.list_views(db)

  """
  @spec list_views(server()) :: [String.t()]
  def list_views(server) do
    GenServer.call(server, :list_views)
  end

  @doc """
  Lists all sequences in the database.

  ## Examples

      sequences = VibeDb.list_sequences(db)

  """
  @spec list_sequences(server()) :: [String.t()]
  def list_sequences(server) do
    GenServer.call(server, :list_sequences)
  end

  @doc """
  Lists all stored procedures in the database.

  ## Examples

      procedures = VibeDb.list_procedures(db)

  """
  @spec list_procedures(server()) :: [String.t()]
  def list_procedures(server) do
    GenServer.call(server, :list_procedures)
  end

  @doc """
  Lists all stored functions in the database.

  ## Examples

      functions = VibeDb.list_functions(db)

  """
  @spec list_functions(server()) :: [String.t()]
  def list_functions(server) do
    GenServer.call(server, :list_functions)
  end

  @doc """
  Lists all packages in the database.

  ## Examples

      packages = VibeDb.list_packages(db)

  """
  @spec list_packages(server()) :: [String.t()]
  def list_packages(server) do
    GenServer.call(server, :list_packages)
  end

  @doc """
  Lists all triggers in the database.

  ## Examples

      triggers = VibeDb.list_triggers(db)

  """
  @spec list_triggers(server()) :: [String.t()]
  def list_triggers(server) do
    GenServer.call(server, :list_triggers)
  end

  @doc """
  Saves the database state to an XML file.

  ## Examples

      :ok = VibeDb.save(db)
      :ok = VibeDb.save(db, "mydb.xml")

  """
  @spec save(server(), String.t()) :: :ok | {:error, String.t()}
  def save(server, filename \\ VibeDb.XmlStorage.default_filename()) do
    GenServer.call(server, {:save, filename})
  end

  @doc """
  Loads the database state from an XML file.

  ## Examples

      :ok = VibeDb.load(db)
      :ok = VibeDb.load(db, "mydb.xml")

  """
  @spec load(server(), String.t()) :: :ok | {:error, String.t()}
  def load(server, filename \\ VibeDb.XmlStorage.default_filename()) do
    GenServer.call(server, {:load, filename})
  end

  @doc """
  Gets the database status information.

  ## Examples

      status = VibeDb.status(db)

  """
  @spec status(server()) :: map()
  def status(server) do
    GenServer.call(server, :status)
  end

  @doc """
  Gets the current database mode (:sql or :nosql).

  ## Examples

      mode = VibeDb.get_mode(db)

  """
  @spec get_mode(server()) :: :sql | :nosql
  def get_mode(server) do
    GenServer.call(server, :get_mode)
  end

  @doc """
  Sets the database mode (:sql or :nosql).
  This allows runtime switching between SQL and NoSQL modes.

  ## Examples

      :ok = VibeDb.set_mode(db, :nosql)
      :ok = VibeDb.set_mode(db, :sql)

  """
  @spec set_mode(server(), :sql | :nosql) :: :ok | {:error, String.t()}
  def set_mode(server, mode) when mode in [:sql, :nosql] do
    GenServer.call(server, {:set_mode, mode})
  end

  def set_mode(_server, mode) do
    {:error, "Invalid mode: #{inspect(mode)}. Must be :sql or :nosql"}
  end

  @doc """
  Executes a NoSQL command directly, regardless of current mode.

  ## Examples

      {:ok, result} = VibeDb.execute_nosql(db, "db.users.insert({name: 'Alice'})")

  """
  @spec execute_nosql(server(), String.t()) :: result()
  def execute_nosql(server, command) when is_binary(command) do
    GenServer.call(server, {:execute_nosql, command})
  end

  # Server Callbacks

  @impl true
  def init(opts) do
    storage_name = :"#{inspect(self())}_storage"
    {:ok, storage_pid} = Storage.start_link(name: storage_name)

    # Default mode is SQL for backward compatibility
    initial_mode = Keyword.get(opts, :mode, :sql)

    state = %{
      storage: storage_pid,
      opts: opts,
      mode: initial_mode
    }

    {:ok, state}
  end

  @impl true
  def handle_call({:execute, command}, _from, state) do
    result =
      case state.mode do
        :sql ->
          QueryExecutor.execute(state.storage, command)

        :nosql ->
          VibeDb.NosqlExecutor.execute(state.storage, command)
      end

    {:reply, result, state}
  end

  @impl true
  def handle_call({:execute_nosql, command}, _from, state) do
    result = VibeDb.NosqlExecutor.execute(state.storage, command)
    {:reply, result, state}
  end

  @impl true
  def handle_call(:get_mode, _from, state) do
    {:reply, state.mode, state}
  end

  @impl true
  def handle_call({:set_mode, mode}, _from, state) do
    {:reply, :ok, %{state | mode: mode}}
  end

  @impl true
  def handle_call(:list_tables, _from, state) do
    tables = Storage.list_tables(state.storage)
    {:reply, tables, state}
  end

  @impl true
  def handle_call({:get_schema, table_name}, _from, state) do
    result = Storage.get_schema(state.storage, table_name)
    {:reply, result, state}
  end

  @impl true
  def handle_call({:table_exists?, table_name}, _from, state) do
    result = Storage.table_exists?(state.storage, table_name)
    {:reply, result, state}
  end

  @impl true
  def handle_call({:nextval, sequence_name}, _from, state) do
    result = Storage.nextval(state.storage, sequence_name)
    {:reply, result, state}
  end

  @impl true
  def handle_call({:currval, sequence_name}, _from, state) do
    result = Storage.currval(state.storage, sequence_name)
    {:reply, result, state}
  end

  @impl true
  def handle_call(:reset, _from, state) do
    result = Storage.reset(state.storage)
    {:reply, result, state}
  end

  @impl true
  def handle_call(:list_types, _from, state) do
    types = Storage.list_types(state.storage)
    {:reply, types, state}
  end

  @impl true
  def handle_call(:list_views, _from, state) do
    views = Storage.list_views(state.storage)
    {:reply, views, state}
  end

  @impl true
  def handle_call(:list_sequences, _from, state) do
    sequences = Storage.list_sequences(state.storage)
    {:reply, sequences, state}
  end

  @impl true
  def handle_call(:list_procedures, _from, state) do
    procedures = Storage.list_procedures(state.storage)
    {:reply, procedures, state}
  end

  @impl true
  def handle_call(:list_functions, _from, state) do
    functions = Storage.list_functions(state.storage)
    {:reply, functions, state}
  end

  @impl true
  def handle_call(:list_packages, _from, state) do
    packages = Storage.list_packages(state.storage)
    {:reply, packages, state}
  end

  @impl true
  def handle_call(:list_triggers, _from, state) do
    triggers = Storage.list_triggers(state.storage)
    {:reply, triggers, state}
  end

  @impl true
  def handle_call({:save, filename}, _from, state) do
    db_state = Storage.get_state(state.storage)
    result = VibeDb.XmlStorage.save(db_state, filename)
    {:reply, result, state}
  end

  @impl true
  def handle_call({:load, filename}, _from, state) do
    case VibeDb.XmlStorage.load(filename) do
      {:ok, new_db_state} ->
        Storage.set_state(state.storage, new_db_state)
        {:reply, :ok, state}

      {:error, _} = error ->
        {:reply, error, state}
    end
  end

  @impl true
  def handle_call(:status, _from, state) do
    db_state = Storage.get_state(state.storage)

    status = %{
      tables: length(Map.keys(db_state.tables)),
      sequences: length(Map.keys(db_state.sequences)),
      indexes: length(Map.keys(db_state.indexes)),
      types: length(Map.keys(db_state.types)),
      views: length(Map.keys(db_state.views)),
      materialized_views: length(Map.keys(db_state.materialized_views)),
      procedures: length(Map.keys(db_state.procedures)),
      functions: length(Map.keys(db_state.functions)),
      packages: length(Map.keys(db_state.packages)),
      triggers: length(Map.keys(db_state.triggers)),
      total_rows:
        db_state.data
        |> Enum.map(fn {_, rows} -> length(rows) end)
        |> Enum.sum()
    }

    {:reply, status, state}
  end
end
