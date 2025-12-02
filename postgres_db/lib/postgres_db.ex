defmodule PostgresDb do
  @moduledoc """
  A PostgreSQL-compatible relational database implemented in Elixir.

  This module provides a simple in-memory database that supports PostgreSQL SQL syntax
  including:

  - DDL: CREATE TABLE, DROP TABLE, ALTER TABLE, CREATE INDEX, CREATE SEQUENCE
  - DML: SELECT, INSERT, UPDATE, DELETE
  - PostgreSQL-specific features: SERIAL/BIGSERIAL, RETURNING clause, LIMIT/OFFSET,
    dollar-quoted strings, ARRAY types, JSON/JSONB types, string functions

  ## Examples

      # Start the database
      {:ok, db} = PostgresDb.start_link()

      # Create a table
      {:ok, _} = PostgresDb.execute(db, "CREATE TABLE users (id SERIAL PRIMARY KEY, name VARCHAR(100), email VARCHAR(255))")

      # Insert data
      {:ok, _} = PostgresDb.execute(db, "INSERT INTO users (name, email) VALUES ('John Doe', 'john@example.com')")

      # Query data
      {:ok, rows} = PostgresDb.execute(db, "SELECT * FROM users WHERE id = 1")

      # Use PostgreSQL-specific features
      {:ok, rows} = PostgresDb.execute(db, "SELECT * FROM users LIMIT 10 OFFSET 0")
      {:ok, rows} = PostgresDb.execute(db, "SELECT COALESCE(email, 'no email') FROM users")

  """

  use GenServer

  alias PostgresDb.Storage
  alias PostgresDb.QueryExecutor

  @type server :: GenServer.server()
  @type result :: {:ok, any()} | {:error, String.t()}

  # Client API

  @doc """
  Starts the PostgresDb database server.

  ## Options

    * `:name` - Optional name for the server process

  ## Examples

      {:ok, db} = PostgresDb.start_link()
      {:ok, db} = PostgresDb.start_link(name: :my_database)

  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Executes an SQL statement.

  Supports PostgreSQL SQL syntax including:
  - SELECT, INSERT, UPDATE, DELETE
  - CREATE TABLE, DROP TABLE, ALTER TABLE
  - CREATE INDEX, DROP INDEX
  - CREATE SEQUENCE, DROP SEQUENCE
  - PostgreSQL functions: COALESCE, NULLIF, GREATEST, LEAST, etc.
  - SERIAL/BIGSERIAL for auto-incrementing columns
  - RETURNING clause for INSERT/UPDATE/DELETE
  - LIMIT/OFFSET for pagination

  ## Examples

      PostgresDb.execute(db, "CREATE TABLE test (id SERIAL, name VARCHAR(50))")
      PostgresDb.execute(db, "INSERT INTO test (name) VALUES ('hello') RETURNING id")
      {:ok, rows} = PostgresDb.execute(db, "SELECT * FROM test LIMIT 10")

  """
  @spec execute(server(), String.t()) :: result()
  def execute(server, sql) when is_binary(sql) do
    GenServer.call(server, {:execute, sql})
  end

  @doc """
  Lists all tables in the database.

  ## Examples

      tables = PostgresDb.list_tables(db)

  """
  @spec list_tables(server()) :: [String.t()]
  def list_tables(server) do
    GenServer.call(server, :list_tables)
  end

  @doc """
  Gets the schema for a table.

  ## Examples

      {:ok, schema} = PostgresDb.get_schema(db, "users")

  """
  @spec get_schema(server(), String.t()) :: {:ok, map()} | {:error, String.t()}
  def get_schema(server, table_name) do
    GenServer.call(server, {:get_schema, table_name})
  end

  @doc """
  Checks if a table exists.

  ## Examples

      true = PostgresDb.table_exists?(db, "users")

  """
  @spec table_exists?(server(), String.t()) :: boolean()
  def table_exists?(server, table_name) do
    GenServer.call(server, {:table_exists?, table_name})
  end

  @doc """
  Gets the next value from a sequence.

  ## Examples

      {:ok, _} = PostgresDb.execute(db, "CREATE SEQUENCE my_seq")
      {:ok, 1} = PostgresDb.nextval(db, "my_seq")
      {:ok, 2} = PostgresDb.nextval(db, "my_seq")

  """
  @spec nextval(server(), String.t()) :: {:ok, integer()} | {:error, String.t()}
  def nextval(server, sequence_name) do
    GenServer.call(server, {:nextval, sequence_name})
  end

  @doc """
  Gets the current value from a sequence (must call nextval first).

  ## Examples

      {:ok, 1} = PostgresDb.nextval(db, "my_seq")
      {:ok, 1} = PostgresDb.currval(db, "my_seq")

  """
  @spec currval(server(), String.t()) :: {:ok, integer()} | {:error, String.t()}
  def currval(server, sequence_name) do
    GenServer.call(server, {:currval, sequence_name})
  end

  @doc """
  Resets the database, clearing all tables and data.

  ## Examples

      :ok = PostgresDb.reset(db)

  """
  @spec reset(server()) :: :ok
  def reset(server) do
    GenServer.call(server, :reset)
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
end
