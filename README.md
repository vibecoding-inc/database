# Oracle SQL-Compatible Relational Database

An in-memory relational database implemented in Elixir that is compatible with Oracle SQL syntax.

## Features

### DDL (Data Definition Language)
- `CREATE TABLE` - Create tables with columns, types, and constraints
- `DROP TABLE` - Remove tables from the database
- `ALTER TABLE` - Add, drop, or modify columns
- `CREATE INDEX` / `DROP INDEX` - Create and drop indexes
- `CREATE SEQUENCE` / `DROP SEQUENCE` - Create and drop sequences

### Object-Relational Types
- `CREATE TYPE ... AS OBJECT` - Create object types with attributes and methods
- `CREATE TYPE ... AS TABLE OF` - Create nested table types
- `CREATE TYPE ... AS VARRAY` - Create variable-size array types
- `CREATE TYPE ... UNDER` - Create subtypes with inheritance
- `DROP TYPE` - Remove user-defined types
- `ALTER TYPE` - Add, drop, or modify type attributes
- Member functions, static methods, and constructors

### Object-Relational Tables and Views
- `CREATE TABLE ... OF type_name` - Create object tables based on object types
- `CREATE VIEW` - Create views with SELECT queries
- `CREATE OR REPLACE VIEW` - Create or replace existing views
- `CREATE VIEW ... OF type_name` - Create object views based on object types
- `CREATE VIEW ... OF type_name WITH OBJECT IDENTIFIER` - Object views with OID specification
- `DROP VIEW` - Remove views
- `CREATE MATERIALIZED VIEW` - Create materialized views
- `DROP MATERIALIZED VIEW` - Remove materialized views

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
- User-defined object types

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

### Object-Relational Types

```elixir
# Create an object type
OracleDb.execute(db, """
  CREATE TYPE address_type AS OBJECT (
    street VARCHAR2(100),
    city VARCHAR2(50),
    zip_code VARCHAR2(10)
  )
""")

# Create an object type with methods
OracleDb.execute(db, """
  CREATE TYPE person_type AS OBJECT (
    first_name VARCHAR2(50),
    last_name VARCHAR2(50),
    MEMBER FUNCTION get_full_name RETURN VARCHAR2
  )
""")

# Create a nested table type
OracleDb.execute(db, "CREATE TYPE phone_list AS TABLE OF VARCHAR2(20)")

# Create a VARRAY type
OracleDb.execute(db, "CREATE TYPE color_array AS VARRAY(10) OF VARCHAR2(20)")

# Create a subtype with inheritance
OracleDb.execute(db, "CREATE TYPE employee_type UNDER person_type (emp_id NUMBER)")

# Alter a type - add attribute
OracleDb.execute(db, "ALTER TYPE person_type ADD ATTRIBUTE birth_date DATE")

# Drop a type
OracleDb.execute(db, "DROP TYPE address_type")
```

### Object-Relational Tables

```elixir
# Create an object table based on a type
OracleDb.execute(db, "CREATE TYPE person_t AS OBJECT (id NUMBER, name VARCHAR2(100))")
OracleDb.execute(db, "CREATE TABLE persons OF person_t")

# Create an object table with constraints
OracleDb.execute(db, "CREATE TABLE employees OF person_t (PRIMARY KEY (id))")
```

### Views

```elixir
# Create a simple view
OracleDb.execute(db, "CREATE VIEW active_users AS SELECT id, name FROM users WHERE status = 'active'")

# Create or replace a view
OracleDb.execute(db, "CREATE OR REPLACE VIEW user_summary AS SELECT id, name, email FROM users")

# Create a view with explicit column names
OracleDb.execute(db, "CREATE VIEW user_names (user_id, full_name) AS SELECT id, name FROM users")

# Drop a view
OracleDb.execute(db, "DROP VIEW active_users")

# Create a materialized view
OracleDb.execute(db, "CREATE MATERIALIZED VIEW user_counts AS SELECT status, COUNT(*) as cnt FROM users GROUP BY status")

# Drop a materialized view
OracleDb.execute(db, "DROP MATERIALIZED VIEW user_counts")
```

### Object-Relational Views

```elixir
# Create an object type for the view
OracleDb.execute(db, """
  CREATE TYPE employee_view_t AS OBJECT (
    emp_id NUMBER,
    emp_name VARCHAR2(100),
    emp_email VARCHAR2(200)
  )
""")

# Create an object view based on a type
OracleDb.execute(db, """
  CREATE VIEW employee_view OF employee_view_t AS
  SELECT employee_id, employee_name, employee_email FROM employees
""")

# Create an object view with OBJECT IDENTIFIER (OID)
OracleDb.execute(db, """
  CREATE VIEW employee_oid_view OF employee_view_t
  WITH OBJECT IDENTIFIER (emp_id) AS
  SELECT employee_id, employee_name, employee_email FROM employees
""")

# Create or replace an object view
OracleDb.execute(db, """
  CREATE OR REPLACE VIEW employee_view OF employee_view_t AS
  SELECT employee_id, employee_name, employee_email FROM employees WHERE active = 1
""")
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