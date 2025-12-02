# PostgreSQL-Compatible Relational Database

An in-memory relational database implemented in Elixir that is compatible with PostgreSQL SQL syntax (Protocol Version 3).

## Features

### DDL (Data Definition Language)
- `CREATE TABLE` - Create tables with columns, types, and constraints
- `CREATE TABLE IF NOT EXISTS` - Conditional table creation
- `DROP TABLE` - Remove tables from the database
- `DROP TABLE IF EXISTS` - Conditional table removal
- `ALTER TABLE` - Add, drop, modify, or rename columns
- `CREATE INDEX` / `DROP INDEX` - Create and drop indexes
- `CREATE SEQUENCE` / `DROP SEQUENCE` - Create and drop sequences

### DML (Data Manipulation Language)
- `SELECT` - Query data with WHERE, ORDER BY, LIMIT, OFFSET
- `INSERT` - Insert rows into tables with RETURNING clause
- `UPDATE` - Update existing rows with RETURNING clause
- `DELETE` - Delete rows from tables with RETURNING clause

### PostgreSQL-Specific Features
- `SERIAL` / `BIGSERIAL` / `SMALLSERIAL` - Auto-incrementing columns
- `RETURNING` clause - Return affected rows from INSERT/UPDATE/DELETE
- `LIMIT` / `OFFSET` - Pagination support
- `ILIKE` - Case-insensitive pattern matching
- `BOOLEAN` type with `IS TRUE` / `IS FALSE` conditions
- Dollar-quoted strings (`$$text$$`)
- `TEXT`, `JSON`, `JSONB`, `UUID`, `BYTEA` types
- `NULLS FIRST` / `NULLS LAST` in ORDER BY
- PostgreSQL functions: `COALESCE`, `NULLIF`, `GREATEST`, `LEAST`
- String functions: `INITCAP`, `LEFT`, `RIGHT`, `LPAD`, `RPAD`, `BTRIM`, `SPLIT_PART`, `CONCAT_WS`
- Numeric functions: `FLOOR`, `CEIL`, `ABS`, `MOD`, `POWER`, `SQRT`
- Date functions: `NOW()`, `CURRENT_DATE`, `CURRENT_TIME`, `CURRENT_TIMESTAMP`

### Supported Column Types
- `INTEGER` / `INT` / `INT4` / `SMALLINT` / `INT2` / `BIGINT` / `INT8`
- `SERIAL` / `SERIAL4` / `BIGSERIAL` / `SERIAL8` / `SMALLSERIAL` / `SERIAL2`
- `VARCHAR` / `CHARACTER` / `TEXT`
- `NUMERIC` / `DECIMAL` / `REAL` / `FLOAT4` / `DOUBLE` / `FLOAT8`
- `BOOLEAN` / `BOOL`
- `DATE` / `TIME` / `TIMESTAMP` / `TIMESTAMPTZ` / `INTERVAL`
- `UUID`
- `JSON` / `JSONB`
- `BYTEA`

### Custom Types
- `CREATE TYPE ... AS ENUM` - Enumerated types
- `CREATE TYPE ... AS (...)` - Composite types
- `ALTER TYPE` - Modify existing types
- `DROP TYPE` - Remove types

## Installation

1. Make sure you have Elixir installed (1.14+)
2. Navigate to the `postgres_db` directory
3. Run `mix deps.get` to fetch dependencies
4. Run `mix compile` to compile the project

## Usage

```elixir
# Start the database
{:ok, db} = PostgresDb.start_link()

# Create a table with SERIAL column
PostgresDb.execute(db, """
  CREATE TABLE users (
    id SERIAL PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    email VARCHAR(255),
    active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
  )
""")

# Insert data (SERIAL column auto-increments)
PostgresDb.execute(db, "INSERT INTO users (name, email) VALUES ('John Doe', 'john@example.com')")

# Insert with RETURNING clause
{:ok, result} = PostgresDb.execute(db, "INSERT INTO users (name) VALUES ('Jane Smith') RETURNING id, name")
# result.rows contains the inserted row with id

# Query data with LIMIT/OFFSET
{:ok, rows} = PostgresDb.execute(db, "SELECT * FROM users ORDER BY id LIMIT 10 OFFSET 0")

# Case-insensitive search with ILIKE
{:ok, rows} = PostgresDb.execute(db, "SELECT * FROM users WHERE name ILIKE '%john%'")

# Use PostgreSQL-specific functions
{:ok, rows} = PostgresDb.execute(db, "SELECT COALESCE(email, 'no email') AS email FROM users")
{:ok, rows} = PostgresDb.execute(db, "SELECT INITCAP(name), LENGTH(email) FROM users")

# Boolean conditions
{:ok, rows} = PostgresDb.execute(db, "SELECT * FROM users WHERE active IS TRUE")

# Update with RETURNING
{:ok, result} = PostgresDb.execute(db, "UPDATE users SET active = FALSE WHERE id = 1 RETURNING *")

# Delete with RETURNING
{:ok, result} = PostgresDb.execute(db, "DELETE FROM users WHERE active IS FALSE RETURNING id")

# Use sequences
PostgresDb.execute(db, "CREATE SEQUENCE order_seq START 1000 INCREMENT 1")
{:ok, next_id} = PostgresDb.nextval(db, "order_seq")

# Create ENUM type
PostgresDb.execute(db, "CREATE TYPE status AS ENUM ('pending', 'active', 'completed')")

# List tables
tables = PostgresDb.list_tables(db)

# Check if table exists
exists = PostgresDb.table_exists?(db, "users")

# Get table schema
{:ok, schema} = PostgresDb.get_schema(db, "users")

# Reset database (clear all data)
PostgresDb.reset(db)
```

## Running Tests

```bash
cd postgres_db
mix test
```

## Project Structure

```
postgres_db/
├── lib/
│   ├── postgres_db.ex           # Main API module
│   └── postgres_db/
│       ├── sql_parser.ex        # SQL parsing
│       ├── storage.ex           # In-memory storage engine
│       └── query_executor.ex    # Query execution
├── test/
│   ├── postgres_db_test.exs     # Integration tests
│   └── test_helper.exs
└── mix.exs                      # Project configuration
```

## License

MIT
