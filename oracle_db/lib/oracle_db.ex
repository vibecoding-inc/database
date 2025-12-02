defmodule OracleDb do
  @moduledoc """
  An Oracle SQL-compatible relational database implemented in Elixir.

  This module provides a simple in-memory database that supports Oracle SQL syntax
  including:

  - DDL: CREATE TABLE, DROP TABLE, ALTER TABLE, CREATE INDEX, CREATE SEQUENCE
  - DML: SELECT, INSERT, UPDATE, DELETE
  - Oracle-specific features: DUAL table, ROWNUM, NVL, NVL2, DECODE, SYSDATE, sequences

  ## Examples

      # Start the database
      {:ok, db} = OracleDb.start_link()

      # Create a table
      OracleDb.execute(db, "CREATE TABLE users (id NUMBER PRIMARY KEY, name VARCHAR2(100), email VARCHAR2(255))")

      # Insert data
      OracleDb.execute(db, "INSERT INTO users (id, name, email) VALUES (1, 'John Doe', 'john@example.com')")

      # Query data
      OracleDb.execute(db, "SELECT * FROM users WHERE id = 1")

      # Use Oracle-specific features
      OracleDb.execute(db, "SELECT SYSDATE FROM DUAL")
      OracleDb.execute(db, "SELECT NVL(email, 'no email') FROM users")

  """

  use GenServer

  alias OracleDb.Storage
  alias OracleDb.QueryExecutor

  @type server :: GenServer.server()
  @type result :: {:ok, any()} | {:error, String.t()}

  # Client API

  @doc """
  Starts the OracleDb database server.

  ## Options

    * `:name` - Optional name for the server process

  ## Examples

      {:ok, db} = OracleDb.start_link()
      {:ok, db} = OracleDb.start_link(name: :my_database)

  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Executes an SQL statement.

  Supports Oracle SQL syntax including:
  - SELECT, INSERT, UPDATE, DELETE
  - CREATE TABLE, DROP TABLE, ALTER TABLE
  - CREATE INDEX, DROP INDEX
  - CREATE SEQUENCE, DROP SEQUENCE
  - Oracle functions: NVL, NVL2, DECODE, SYSDATE, ROWNUM, etc.

  ## Examples

      OracleDb.execute(db, "CREATE TABLE test (id NUMBER, name VARCHAR2(50))")
      OracleDb.execute(db, "INSERT INTO test VALUES (1, 'hello')")
      {:ok, rows} = OracleDb.execute(db, "SELECT * FROM test")

  """
  @spec execute(server(), String.t()) :: result()
  def execute(server, sql) when is_binary(sql) do
    GenServer.call(server, {:execute, sql})
  end

  @doc """
  Lists all tables in the database.

  ## Examples

      tables = OracleDb.list_tables(db)

  """
  @spec list_tables(server()) :: [String.t()]
  def list_tables(server) do
    GenServer.call(server, :list_tables)
  end

  @doc """
  Gets the schema for a table.

  ## Examples

      {:ok, schema} = OracleDb.get_schema(db, "users")

  """
  @spec get_schema(server(), String.t()) :: {:ok, map()} | {:error, String.t()}
  def get_schema(server, table_name) do
    GenServer.call(server, {:get_schema, table_name})
  end

  @doc """
  Checks if a table exists.

  ## Examples

      true = OracleDb.table_exists?(db, "users")

  """
  @spec table_exists?(server(), String.t()) :: boolean()
  def table_exists?(server, table_name) do
    GenServer.call(server, {:table_exists?, table_name})
  end

  @doc """
  Gets the next value from a sequence.

  ## Examples

      {:ok, _} = OracleDb.execute(db, "CREATE SEQUENCE my_seq START WITH 1")
      {:ok, 1} = OracleDb.nextval(db, "my_seq")
      {:ok, 2} = OracleDb.nextval(db, "my_seq")

  """
  @spec nextval(server(), String.t()) :: {:ok, integer()} | {:error, String.t()}
  def nextval(server, sequence_name) do
    GenServer.call(server, {:nextval, sequence_name})
  end

  @doc """
  Gets the current value from a sequence (must call nextval first).

  ## Examples

      {:ok, 1} = OracleDb.nextval(db, "my_seq")
      {:ok, 1} = OracleDb.currval(db, "my_seq")

  """
  @spec currval(server(), String.t()) :: {:ok, integer()} | {:error, String.t()}
  def currval(server, sequence_name) do
    GenServer.call(server, {:currval, sequence_name})
  end

  @doc """
  Resets the database, clearing all tables and data.

  ## Examples

      :ok = OracleDb.reset(db)

  """
  @spec reset(server()) :: :ok
  def reset(server) do
    GenServer.call(server, :reset)
  end

  @doc """
  Lists all user-defined types in the database.

  ## Examples

      types = OracleDb.list_types(db)

  """
  @spec list_types(server()) :: [String.t()]
  def list_types(server) do
    GenServer.call(server, :list_types)
  end

  @doc """
  Lists all views in the database.

  ## Examples

      views = OracleDb.list_views(db)

  """
  @spec list_views(server()) :: [String.t()]
  def list_views(server) do
    GenServer.call(server, :list_views)
  end

  # Server Callbacks

  @impl true
  def init(opts) do
    storage_name = :"#{inspect(self())}_storage"
    {:ok, storage_pid} = Storage.start_link(name: storage_name)

    state = %{
      storage: storage_pid,
      opts: opts
    }

    {:ok, state}
  end

  @impl true
  def handle_call({:execute, sql}, _from, state) do
    result = QueryExecutor.execute(state.storage, sql)
    {:reply, result, state}
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
end
