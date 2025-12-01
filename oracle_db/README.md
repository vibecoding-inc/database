# OracleDb

An Oracle SQL-compatible in-memory relational database implemented in Elixir.

## Installation

If [available in Hex](https://hex.pm/docs/publish), the package can be installed
by adding `oracle_db` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:oracle_db, "~> 0.1.0"}
  ]
end
```

## Quick Start

```elixir
# Start the database
{:ok, db} = OracleDb.start_link()

# Create a table
OracleDb.execute(db, "CREATE TABLE users (id NUMBER, name VARCHAR2(100))")

# Insert data
OracleDb.execute(db, "INSERT INTO users VALUES (1, 'John')")

# Query data
{:ok, rows} = OracleDb.execute(db, "SELECT * FROM users")
```

## Features

- Oracle SQL syntax support (DDL and DML)
- In-memory storage with GenServer
- Oracle-specific functions (NVL, SYSDATE, ROWNUM, etc.)
- Sequences for auto-incrementing values
- DUAL table support

See the [main README](../README.md) for detailed documentation.

