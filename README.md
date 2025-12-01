# Oracle SQL-Compatible Relational Database

An in-memory relational database implemented in Elixir that is compatible with Oracle SQL syntax.

## Features

### DDL (Data Definition Language)
- `CREATE TABLE` - Create tables with columns, types, and constraints
- `DROP TABLE` - Remove tables from the database
- `ALTER TABLE` - Add, drop, or modify columns
- `CREATE INDEX` / `DROP INDEX` - Create and drop indexes
- `CREATE SEQUENCE` / `DROP SEQUENCE` - Create and drop sequences

### DML (Data Manipulation Language)
- `SELECT` - Query data with WHERE, ORDER BY, and column projections
- `INSERT` - Insert rows into tables
- `UPDATE` - Update existing rows
- `DELETE` - Delete rows from tables

### Oracle-Specific Features
- `DUAL` table - Oracle's single-row dummy table
- `ROWNUM` - Row numbering pseudo-column
- `SYSDATE` - Current system date
- Sequences with `NEXTVAL` and `CURRVAL`
- Oracle functions: `NVL`, `NVL2`, `COALESCE`, `DECODE`
- String functions: `UPPER`, `LOWER`, `SUBSTR`, `LENGTH`, `TRIM`, `LTRIM`, `RTRIM`
- Numeric functions: `ROUND`, `TRUNC`
- Type conversion: `TO_CHAR`, `TO_NUMBER`, `TO_DATE`
- XML functions: `XMLELEMENT`, `XMLFOREST`, `XMLAGG`, `XMLROOT`, `XMLPARSE`, `XMLSERIALIZE`, `XMLCONCAT`, `XMLCOMMENT`, `XMLPI`, `XMLATTRIBUTES`, `XMLCDATA`

### Supported Column Types
- `NUMBER` / `INTEGER` / `INT`
- `VARCHAR2` / `VARCHAR` / `CHAR`
- `DATE` / `TIMESTAMP`
- `CLOB` / `BLOB`
- `BOOLEAN`
- `FLOAT` / `DOUBLE` / `DECIMAL` / `NUMERIC`

## Installation

1. Make sure you have Elixir installed (1.14+)
2. Navigate to the `oracle_db` directory
3. Run `mix deps.get` to fetch dependencies
4. Run `mix compile` to compile the project

## Usage

```elixir
# Start the database
{:ok, db} = OracleDb.start_link()

# Create a table
OracleDb.execute(db, """
  CREATE TABLE users (
    id NUMBER PRIMARY KEY,
    name VARCHAR2(100) NOT NULL,
    email VARCHAR2(255),
    created_at DATE DEFAULT SYSDATE
  )
""")

# Insert data
OracleDb.execute(db, "INSERT INTO users (id, name, email) VALUES (1, 'John Doe', 'john@example.com')")
OracleDb.execute(db, "INSERT INTO users (id, name) VALUES (2, 'Jane Smith')")

# Query data
{:ok, rows} = OracleDb.execute(db, "SELECT * FROM users")
{:ok, rows} = OracleDb.execute(db, "SELECT * FROM users WHERE id = 1")
{:ok, rows} = OracleDb.execute(db, "SELECT name, email FROM users ORDER BY name")

# Use Oracle-specific features
{:ok, rows} = OracleDb.execute(db, "SELECT SYSDATE FROM DUAL")
{:ok, rows} = OracleDb.execute(db, "SELECT NVL(email, 'no email') AS email FROM users")
{:ok, rows} = OracleDb.execute(db, "SELECT UPPER(name), SUBSTR(email, 1, 5) FROM users")

# Use sequences
OracleDb.execute(db, "CREATE SEQUENCE user_seq START WITH 100 INCREMENT BY 1")
{:ok, next_id} = OracleDb.nextval(db, "user_seq")

# Update data
OracleDb.execute(db, "UPDATE users SET email = 'jane@example.com' WHERE id = 2")

# Delete data
OracleDb.execute(db, "DELETE FROM users WHERE id = 1")

# List tables
tables = OracleDb.list_tables(db)

# Check if table exists
exists = OracleDb.table_exists?(db, "users")

# Get table schema
{:ok, schema} = OracleDb.get_schema(db, "users")

# Reset database (clear all data)
OracleDb.reset(db)
```

## Running Tests

```bash
cd oracle_db
mix test
```

## Project Structure

```
oracle_db/
├── lib/
│   ├── oracle_db.ex           # Main API module
│   └── oracle_db/
│       ├── sql_parser.ex      # SQL parsing
│       ├── storage.ex         # In-memory storage engine
│       └── query_executor.ex  # Query execution
├── test/
│   ├── oracle_db_test.exs     # Integration tests
│   ├── sql_parser_test.exs    # Parser tests
│   └── test_helper.exs
└── mix.exs                    # Project configuration
```

## License

MIT