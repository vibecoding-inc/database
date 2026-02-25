# VibeDb SQL-Compatible Relational Database

An in-memory relational database implemented in Elixir that is compatible with VibeDb SQL syntax.

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

### PL/SQL Stored Procedures and Functions
- `CREATE PROCEDURE` / `CREATE OR REPLACE PROCEDURE` - Create stored procedures
- `DROP PROCEDURE` - Remove stored procedures
- `CREATE FUNCTION` / `CREATE OR REPLACE FUNCTION` - Create stored functions
- `DROP FUNCTION` - Remove stored functions
- Support for IN, OUT, and IN OUT parameters

### PL/SQL Packages
- `CREATE PACKAGE` / `CREATE OR REPLACE PACKAGE` - Create package specifications
- `CREATE PACKAGE BODY` / `CREATE OR REPLACE PACKAGE BODY` - Create package bodies
- `DROP PACKAGE` / `DROP PACKAGE BODY` - Remove packages or package bodies
- Package procedures and functions

### Triggers
- `CREATE TRIGGER` / `CREATE OR REPLACE TRIGGER` - Create database triggers
- `DROP TRIGGER` - Remove triggers
- `ALTER TRIGGER ... ENABLE/DISABLE` - Enable or disable triggers
- BEFORE/AFTER/INSTEAD OF triggers
- Row-level and statement-level triggers
- Support for INSERT, UPDATE, DELETE events
- UPDATE OF column triggers
- WHEN clause conditions
- `:OLD` and `:NEW` row references for accessing row data in triggers

### DML (Data Manipulation Language)
- `SELECT` - Query data with WHERE, ORDER BY, and column projections
- `INSERT` - Insert rows into tables
- `UPDATE` - Update existing rows
- `DELETE` - Delete rows from tables

### VibeDb-Specific Features
- `DUAL` table - VibeDb's single-row dummy table
- `ROWNUM` - Row numbering pseudo-column
- `SYSDATE` - Current system date
- Sequences with `NEXTVAL` and `CURRVAL`
- VibeDb functions: `NVL`, `NVL2`, `COALESCE`, `DECODE`
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

### Using Nix (Recommended)

If you have Nix with flakes enabled, you can run the database REPL directly:

```bash
nix run github:vibecoding-inc/database
```

Or enter a development shell:

```bash
nix develop
cd vibe_db
mix deps.get
mix compile
mix escript.build
./vibe_db
```

### Manual Installation

1. Make sure you have Elixir installed (1.14+)
2. Navigate to the `vibe_db` directory
3. Run `mix deps.get` to fetch dependencies
4. Run `mix compile` to compile the project
5. Run `mix escript.build` to build the REPL binary
6. Run `./vibe_db` to start the REPL

## Interactive REPL

The database includes an interactive REPL (Read-Eval-Print Loop):

```bash
$ ./vibe_db
VibeDb REPL v0.1.0
Type .help for available commands, .exit to quit.

vibedb> CREATE TABLE users (id NUMBER, name VARCHAR2(100));
OK: Table USERS created

vibedb> INSERT INTO users VALUES (1, 'Alice');
OK: 1 row(s) affected

vibedb> SELECT * FROM users;
| ID | NAME  |
+----+-------+
| 1  | Alice |
1 row(s) returned

vibedb> .tables
Tables:
  USERS

vibedb> .save mydb.xml
Database saved to mydb.xml

vibedb> .exit
Goodbye!
```

### REPL Commands

- `.help` - Show available commands
- `.tables` - List all tables
- `.schema <table>` - Show table schema
- `.types` - List all user-defined types
- `.views` - List all views
- `.sequences` - List all sequences
- `.procedures` - List all stored procedures
- `.functions` - List all stored functions
- `.packages` - List all packages
- `.triggers` - List all triggers
- `.status` - Show database status (counts of tables, rows, etc.)
- `.save [filename]` - Save database to XML file (default: database.xml)
- `.load [filename]` - Load database from XML file (default: database.xml)
- `.clear` - Clear the screen
- `.exit` or `.quit` - Exit the REPL

### XML Persistence

The database supports saving and loading the complete database state to/from XML files. This includes:

- Tables (schema and data)
- Sequences
- Indexes
- User-defined types (object types, nested tables, VARRAYs)
- Views and materialized views
- Stored procedures and functions
- Packages
- Triggers

Example XML storage usage:
```bash
vibedb> CREATE TABLE users (id NUMBER, name VARCHAR2(100));
OK: Table USERS created

vibedb> INSERT INTO users VALUES (1, 'Alice');
OK: 1 row(s) affected

vibedb> .save
Database saved to database.xml

vibedb> .exit
Goodbye!

# Later, restart the REPL and load the database:
vibedb> .load
Database loaded from database.xml

vibedb> SELECT * FROM users;
| ID | NAME  |
+----+-------+
| 1  | Alice |
1 row(s) returned
```

## Programmatic Usage

```elixir
# Start the database
{:ok, db} = VibeDb.start_link()

# Create a table
VibeDb.execute(db, """
  CREATE TABLE users (
    id NUMBER PRIMARY KEY,
    name VARCHAR2(100) NOT NULL,
    email VARCHAR2(255),
    created_at DATE DEFAULT SYSDATE
  )
""")

# Insert data
VibeDb.execute(db, "INSERT INTO users (id, name, email) VALUES (1, 'John Doe', 'john@example.com')")
VibeDb.execute(db, "INSERT INTO users (id, name) VALUES (2, 'Jane Smith')")

# Query data
{:ok, rows} = VibeDb.execute(db, "SELECT * FROM users")
{:ok, rows} = VibeDb.execute(db, "SELECT * FROM users WHERE id = 1")
{:ok, rows} = VibeDb.execute(db, "SELECT name, email FROM users ORDER BY name")

# Use VibeDb-specific features
{:ok, rows} = VibeDb.execute(db, "SELECT SYSDATE FROM DUAL")
{:ok, rows} = VibeDb.execute(db, "SELECT NVL(email, 'no email') AS email FROM users")
{:ok, rows} = VibeDb.execute(db, "SELECT UPPER(name), SUBSTR(email, 1, 5) FROM users")

# Use sequences
VibeDb.execute(db, "CREATE SEQUENCE user_seq START WITH 100 INCREMENT BY 1")
{:ok, next_id} = VibeDb.nextval(db, "user_seq")

# Update data
VibeDb.execute(db, "UPDATE users SET email = 'jane@example.com' WHERE id = 2")

# Delete data
VibeDb.execute(db, "DELETE FROM users WHERE id = 1")

# List tables
tables = VibeDb.list_tables(db)

# Check if table exists
exists = VibeDb.table_exists?(db, "users")

# Get table schema
{:ok, schema} = VibeDb.get_schema(db, "users")

# Reset database (clear all data)
VibeDb.reset(db)
```

### Object-Relational Types

```elixir
# Create an object type
VibeDb.execute(db, """
  CREATE TYPE address_type AS OBJECT (
    street VARCHAR2(100),
    city VARCHAR2(50),
    zip_code VARCHAR2(10)
  )
""")

# Create an object type with methods
VibeDb.execute(db, """
  CREATE TYPE person_type AS OBJECT (
    first_name VARCHAR2(50),
    last_name VARCHAR2(50),
    MEMBER FUNCTION get_full_name RETURN VARCHAR2
  )
""")

# Create a nested table type
VibeDb.execute(db, "CREATE TYPE phone_list AS TABLE OF VARCHAR2(20)")

# Create a VARRAY type
VibeDb.execute(db, "CREATE TYPE color_array AS VARRAY(10) OF VARCHAR2(20)")

# Create a subtype with inheritance
VibeDb.execute(db, "CREATE TYPE employee_type UNDER person_type (emp_id NUMBER)")

# Alter a type - add attribute
VibeDb.execute(db, "ALTER TYPE person_type ADD ATTRIBUTE birth_date DATE")

# Drop a type
VibeDb.execute(db, "DROP TYPE address_type")
```

### Object-Relational Tables

```elixir
# Create an object table based on a type
VibeDb.execute(db, "CREATE TYPE person_t AS OBJECT (id NUMBER, name VARCHAR2(100))")
VibeDb.execute(db, "CREATE TABLE persons OF person_t")

# Create an object table with constraints
VibeDb.execute(db, "CREATE TABLE employees OF person_t (PRIMARY KEY (id))")
```

### Views

```elixir
# Create a simple view
VibeDb.execute(db, "CREATE VIEW active_users AS SELECT id, name FROM users WHERE status = 'active'")

# Create or replace a view
VibeDb.execute(db, "CREATE OR REPLACE VIEW user_summary AS SELECT id, name, email FROM users")

# Create a view with explicit column names
VibeDb.execute(db, "CREATE VIEW user_names (user_id, full_name) AS SELECT id, name FROM users")

# Drop a view
VibeDb.execute(db, "DROP VIEW active_users")

# Create a materialized view
VibeDb.execute(db, "CREATE MATERIALIZED VIEW user_counts AS SELECT status, COUNT(*) as cnt FROM users GROUP BY status")

# Drop a materialized view
VibeDb.execute(db, "DROP MATERIALIZED VIEW user_counts")
```

### Object-Relational Views

```elixir
# Create an object type for the view
VibeDb.execute(db, """
  CREATE TYPE employee_view_t AS OBJECT (
    emp_id NUMBER,
    emp_name VARCHAR2(100),
    emp_email VARCHAR2(200)
  )
""")

# Create an object view based on a type
VibeDb.execute(db, """
  CREATE VIEW employee_view OF employee_view_t AS
  SELECT employee_id, employee_name, employee_email FROM employees
""")

# Create an object view with OBJECT IDENTIFIER (OID)
VibeDb.execute(db, """
  CREATE VIEW employee_oid_view OF employee_view_t
  WITH OBJECT IDENTIFIER (emp_id) AS
  SELECT employee_id, employee_name, employee_email FROM employees
""")

# Create or replace an object view
VibeDb.execute(db, """
  CREATE OR REPLACE VIEW employee_view OF employee_view_t AS
  SELECT employee_id, employee_name, employee_email FROM employees WHERE active = 1
""")
```

### Stored Procedures

```elixir
# Create a simple stored procedure
VibeDb.execute(db, """
  CREATE PROCEDURE hello_proc (p_name IN VARCHAR2)
  IS
  BEGIN
    DBMS_OUTPUT.PUT_LINE('Hello ' || p_name);
  END;
""")

# Create a procedure with OUT parameter
VibeDb.execute(db, """
  CREATE PROCEDURE get_user (p_id IN NUMBER, p_name OUT VARCHAR2)
  IS
  BEGIN
    SELECT name INTO p_name FROM users WHERE id = p_id;
  END;
""")

# Create a procedure with IN OUT parameter
VibeDb.execute(db, """
  CREATE PROCEDURE increment_value (p_value IN OUT NUMBER)
  IS
  BEGIN
    p_value := p_value + 1;
  END;
""")

# Replace an existing procedure
VibeDb.execute(db, """
  CREATE OR REPLACE PROCEDURE hello_proc (p_name IN VARCHAR2, p_greeting OUT VARCHAR2)
  IS
  BEGIN
    p_greeting := 'Hello ' || p_name;
  END;
""")

# Drop a procedure
VibeDb.execute(db, "DROP PROCEDURE hello_proc")
```

### Stored Functions

```elixir
# Create a stored function
VibeDb.execute(db, """
  CREATE FUNCTION get_greeting (p_name VARCHAR2)
  RETURN VARCHAR2
  IS
  BEGIN
    RETURN 'Hello ' || p_name;
  END;
""")

# Create a function with multiple parameters
VibeDb.execute(db, """
  CREATE FUNCTION calculate_tax (p_amount NUMBER, p_rate NUMBER)
  RETURN NUMBER
  IS
  BEGIN
    RETURN p_amount * p_rate / 100;
  END;
""")

# Replace an existing function
VibeDb.execute(db, "CREATE OR REPLACE FUNCTION get_greeting (p_name VARCHAR2) RETURN VARCHAR2 IS BEGIN RETURN 'Hi ' || p_name; END;")

# Drop a function
VibeDb.execute(db, "DROP FUNCTION get_greeting")
```

### Packages

```elixir
# Create a package specification
VibeDb.execute(db, """
  CREATE PACKAGE user_pkg
  IS
    PROCEDURE add_user (p_name VARCHAR2);
    FUNCTION get_user_count RETURN NUMBER;
  END;
""")

# Create a package body
VibeDb.execute(db, """
  CREATE PACKAGE BODY user_pkg
  IS
    PROCEDURE add_user (p_name VARCHAR2)
    IS
    BEGIN
      INSERT INTO users (name) VALUES (p_name);
    END;
    
    FUNCTION get_user_count RETURN NUMBER
    IS
      v_count NUMBER;
    BEGIN
      SELECT COUNT(*) INTO v_count FROM users;
      RETURN v_count;
    END;
  END;
""")

# Replace a package
VibeDb.execute(db, "CREATE OR REPLACE PACKAGE user_pkg IS PROCEDURE add_user (p_name VARCHAR2); END;")

# Drop a package body only
VibeDb.execute(db, "DROP PACKAGE BODY user_pkg")

# Drop an entire package
VibeDb.execute(db, "DROP PACKAGE user_pkg")
```

### Triggers

```elixir
# Create a BEFORE INSERT trigger - executes before each INSERT
VibeDb.execute(db, """
  CREATE TRIGGER audit_insert
  BEFORE INSERT ON users
  FOR EACH ROW
  BEGIN
    INSERT INTO audit_log (action, table_name, timestamp)
    VALUES ('INSERT', 'users', 1);
  END;
""")

# Create an AFTER UPDATE trigger with :OLD and :NEW row references
VibeDb.execute(db, """
  CREATE TRIGGER audit_update
  AFTER UPDATE ON users
  FOR EACH ROW
  BEGIN
    INSERT INTO audit_log (action, old_value, new_value)
    VALUES ('UPDATE', :OLD.name, :NEW.name);
  END;
""")

# Create a trigger for multiple events
VibeDb.execute(db, """
  CREATE TRIGGER audit_changes
  BEFORE INSERT OR UPDATE OR DELETE ON users
  FOR EACH ROW
  BEGIN
    INSERT INTO change_log (event) VALUES ('CHANGE');
  END;
""")

# Create a trigger with UPDATE OF specific columns
VibeDb.execute(db, """
  CREATE TRIGGER track_salary_changes
  BEFORE UPDATE OF salary ON employees
  FOR EACH ROW
  BEGIN
    INSERT INTO salary_history (old_salary, new_salary) VALUES (:OLD.salary, :NEW.salary);
  END;
""")

# Create a trigger with WHEN clause
VibeDb.execute(db, """
  CREATE TRIGGER check_salary
  BEFORE INSERT ON employees
  FOR EACH ROW
  WHEN (NEW.salary > 100000)
  BEGIN
    INSERT INTO high_salary_log (salary) VALUES (:NEW.salary);
  END;
""")

# Create INSTEAD OF trigger for views
VibeDb.execute(db, """
  CREATE TRIGGER instead_insert
  INSTEAD OF INSERT ON user_view
  FOR EACH ROW
  BEGIN
    INSERT INTO users (id, name) VALUES (:NEW.id, :NEW.name);
  END;
""")

# Enable/disable a trigger
VibeDb.execute(db, "ALTER TRIGGER audit_insert ENABLE")
VibeDb.execute(db, "ALTER TRIGGER audit_insert DISABLE")

# Drop a trigger
VibeDb.execute(db, "DROP TRIGGER audit_insert")
```

## Running Tests

```bash
cd vibe_db
mix test
```


## Project Structure

```
vibe_db/
├── lib/
│   ├── vibe_db.ex           # Main API module
│   └── vibe_db/
│       ├── sql_parser.ex      # SQL parsing
│       ├── storage.ex         # In-memory storage engine
│       └── query_executor.ex  # Query execution
├── test/
│   ├── vibe_db_test.exs     # Integration tests
│   ├── sql_parser_test.exs    # Parser tests
│   └── test_helper.exs
└── mix.exs                    # Project configuration
```

## License

MIT