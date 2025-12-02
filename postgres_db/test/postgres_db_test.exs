defmodule PostgresDbTest do
  use ExUnit.Case
  doctest PostgresDb

  setup do
    {:ok, db} = PostgresDb.start_link()
    {:ok, db: db}
  end

  describe "DDL operations" do
    test "CREATE TABLE creates a new table", %{db: db} do
      result = PostgresDb.execute(db, "CREATE TABLE users (id INTEGER, name VARCHAR(100))")
      assert {:ok, %{message: "CREATE TABLE"}} = result
      assert PostgresDb.table_exists?(db, "users")
    end

    test "CREATE TABLE IF NOT EXISTS", %{db: db} do
      PostgresDb.execute(db, "CREATE TABLE existing (id INTEGER)")
      result = PostgresDb.execute(db, "CREATE TABLE IF NOT EXISTS existing (id INTEGER)")
      assert {:ok, %{message: "CREATE TABLE"}} = result
    end

    test "CREATE TABLE with constraints", %{db: db} do
      result =
        PostgresDb.execute(db, """
          CREATE TABLE orders (
            id SERIAL PRIMARY KEY,
            user_id INTEGER NOT NULL,
            amount NUMERIC(10,2) DEFAULT 0,
            status VARCHAR(20)
          )
        """)

      assert {:ok, _} = result
      assert PostgresDb.table_exists?(db, "orders")
    end

    test "DROP TABLE removes a table", %{db: db} do
      PostgresDb.execute(db, "CREATE TABLE temp (id INTEGER)")
      assert PostgresDb.table_exists?(db, "temp")

      result = PostgresDb.execute(db, "DROP TABLE temp")
      assert {:ok, %{message: "DROP TABLE"}} = result
      refute PostgresDb.table_exists?(db, "temp")
    end

    test "DROP TABLE IF EXISTS", %{db: db} do
      result = PostgresDb.execute(db, "DROP TABLE IF EXISTS nonexistent")
      assert {:ok, %{message: "DROP TABLE"}} = result
    end

    test "ALTER TABLE ADD COLUMN", %{db: db} do
      PostgresDb.execute(db, "CREATE TABLE products (id INTEGER)")
      result = PostgresDb.execute(db, "ALTER TABLE products ADD COLUMN name VARCHAR(100)")
      assert {:ok, %{message: "ALTER TABLE"}} = result
    end

    test "ALTER TABLE DROP COLUMN", %{db: db} do
      PostgresDb.execute(db, "CREATE TABLE items (id INTEGER, name VARCHAR(100))")
      result = PostgresDb.execute(db, "ALTER TABLE items DROP COLUMN name")
      assert {:ok, _} = result
    end

    test "ALTER TABLE RENAME COLUMN", %{db: db} do
      PostgresDb.execute(db, "CREATE TABLE test (old_name INTEGER)")
      result = PostgresDb.execute(db, "ALTER TABLE test RENAME COLUMN old_name TO new_name")
      assert {:ok, _} = result
    end

    test "CREATE INDEX", %{db: db} do
      PostgresDb.execute(db, "CREATE TABLE employees (id INTEGER, dept_id INTEGER)")
      result = PostgresDb.execute(db, "CREATE INDEX idx_dept ON employees (dept_id)")
      assert {:ok, %{message: "CREATE INDEX"}} = result
    end

    test "CREATE UNIQUE INDEX", %{db: db} do
      PostgresDb.execute(db, "CREATE TABLE users (id INTEGER, email VARCHAR(255))")
      result = PostgresDb.execute(db, "CREATE UNIQUE INDEX idx_email ON users (email)")
      assert {:ok, %{message: "CREATE INDEX"}} = result
    end

    test "CREATE SEQUENCE", %{db: db} do
      result = PostgresDb.execute(db, "CREATE SEQUENCE user_seq START 1 INCREMENT 1")
      assert {:ok, %{message: "CREATE SEQUENCE"}} = result
    end
  end

  describe "INSERT operations" do
    setup %{db: db} do
      PostgresDb.execute(
        db,
        "CREATE TABLE users (id INTEGER, name VARCHAR(100), email VARCHAR(255))"
      )

      :ok
    end

    test "INSERT with column names", %{db: db} do
      result =
        PostgresDb.execute(
          db,
          "INSERT INTO users (id, name, email) VALUES (1, 'John', 'john@example.com')"
        )

      assert {:ok, %{rows_affected: 1}} = result
    end

    test "INSERT without column names", %{db: db} do
      result = PostgresDb.execute(db, "INSERT INTO users VALUES (1, 'Jane', 'jane@example.com')")
      assert {:ok, %{rows_affected: 1}} = result
    end

    test "INSERT multiple rows and SELECT", %{db: db} do
      PostgresDb.execute(db, "INSERT INTO users VALUES (1, 'Alice', 'alice@example.com')")
      PostgresDb.execute(db, "INSERT INTO users VALUES (2, 'Bob', 'bob@example.com')")
      PostgresDb.execute(db, "INSERT INTO users VALUES (3, 'Charlie', 'charlie@example.com')")

      {:ok, rows} = PostgresDb.execute(db, "SELECT * FROM users")
      assert length(rows) == 3
    end

    test "INSERT with RETURNING clause", %{db: db} do
      PostgresDb.execute(db, "CREATE TABLE returning_test (id SERIAL, name VARCHAR(100))")

      result =
        PostgresDb.execute(db, "INSERT INTO returning_test (name) VALUES ('Test') RETURNING id")

      assert {:ok, %{rows: rows, rows_affected: 1}} = result
      assert length(rows) == 1
      assert Map.has_key?(hd(rows), "id")
    end
  end

  describe "SERIAL columns" do
    test "SERIAL auto-increments", %{db: db} do
      PostgresDb.execute(db, "CREATE TABLE auto_test (id SERIAL, name VARCHAR(100))")
      PostgresDb.execute(db, "INSERT INTO auto_test (name) VALUES ('First')")
      PostgresDb.execute(db, "INSERT INTO auto_test (name) VALUES ('Second')")
      PostgresDb.execute(db, "INSERT INTO auto_test (name) VALUES ('Third')")

      {:ok, rows} = PostgresDb.execute(db, "SELECT * FROM auto_test ORDER BY id")
      ids = Enum.map(rows, & &1["id"])
      assert ids == [1, 2, 3]
    end

    test "BIGSERIAL works like SERIAL", %{db: db} do
      PostgresDb.execute(db, "CREATE TABLE big_test (id BIGSERIAL, data TEXT)")
      PostgresDb.execute(db, "INSERT INTO big_test (data) VALUES ('test')")

      {:ok, rows} = PostgresDb.execute(db, "SELECT * FROM big_test")
      assert hd(rows)["id"] == 1
    end
  end

  describe "SELECT operations" do
    setup %{db: db} do
      PostgresDb.execute(
        db,
        "CREATE TABLE products (id INTEGER, name VARCHAR(100), price NUMERIC, category VARCHAR(50))"
      )

      PostgresDb.execute(db, "INSERT INTO products VALUES (1, 'Laptop', 999, 'Electronics')")
      PostgresDb.execute(db, "INSERT INTO products VALUES (2, 'Mouse', 29, 'Electronics')")
      PostgresDb.execute(db, "INSERT INTO products VALUES (3, 'Desk', 199, 'Furniture')")
      PostgresDb.execute(db, "INSERT INTO products VALUES (4, 'Chair', 149, 'Furniture')")
      :ok
    end

    test "SELECT all columns", %{db: db} do
      {:ok, rows} = PostgresDb.execute(db, "SELECT * FROM products")
      assert length(rows) == 4
    end

    test "SELECT specific columns", %{db: db} do
      {:ok, rows} = PostgresDb.execute(db, "SELECT name, price FROM products")
      assert length(rows) == 4
      assert Map.has_key?(hd(rows), "name")
      assert Map.has_key?(hd(rows), "price")
    end

    test "SELECT with WHERE clause", %{db: db} do
      {:ok, rows} =
        PostgresDb.execute(db, "SELECT * FROM products WHERE category = 'Electronics'")

      assert length(rows) == 2
    end

    test "SELECT with WHERE and comparison operators", %{db: db} do
      {:ok, rows} = PostgresDb.execute(db, "SELECT * FROM products WHERE price > 100")
      assert length(rows) == 3
    end

    test "SELECT with WHERE and multiple conditions (AND)", %{db: db} do
      {:ok, rows} =
        PostgresDb.execute(
          db,
          "SELECT * FROM products WHERE category = 'Furniture' AND price > 150"
        )

      assert length(rows) == 1
    end

    test "SELECT with WHERE and OR condition", %{db: db} do
      {:ok, rows} =
        PostgresDb.execute(db, "SELECT * FROM products WHERE name = 'Laptop' OR name = 'Mouse'")

      assert length(rows) == 2
    end

    test "SELECT with ORDER BY", %{db: db} do
      {:ok, rows} = PostgresDb.execute(db, "SELECT * FROM products ORDER BY price ASC")
      prices = Enum.map(rows, & &1["price"])
      assert prices == [29, 149, 199, 999]
    end

    test "SELECT with ORDER BY DESC", %{db: db} do
      {:ok, rows} = PostgresDb.execute(db, "SELECT * FROM products ORDER BY price DESC")
      prices = Enum.map(rows, & &1["price"])
      assert prices == [999, 199, 149, 29]
    end

    test "SELECT with LIMIT", %{db: db} do
      {:ok, rows} = PostgresDb.execute(db, "SELECT * FROM products LIMIT 2")
      assert length(rows) == 2
    end

    test "SELECT with LIMIT and OFFSET", %{db: db} do
      {:ok, rows} = PostgresDb.execute(db, "SELECT * FROM products ORDER BY id LIMIT 2 OFFSET 1")
      assert length(rows) == 2
      ids = Enum.map(rows, & &1["id"])
      assert ids == [2, 3]
    end

    test "SELECT with LIKE", %{db: db} do
      {:ok, rows} = PostgresDb.execute(db, "SELECT * FROM products WHERE name LIKE 'L%'")
      assert length(rows) == 1
      assert hd(rows)["name"] == "Laptop"
    end

    test "SELECT with ILIKE (case-insensitive)", %{db: db} do
      {:ok, rows} = PostgresDb.execute(db, "SELECT * FROM products WHERE name ILIKE 'laptop'")
      assert length(rows) == 1
      assert hd(rows)["name"] == "Laptop"
    end

    test "SELECT with IN clause", %{db: db} do
      {:ok, rows} = PostgresDb.execute(db, "SELECT * FROM products WHERE id IN (1, 3)")
      assert length(rows) == 2
    end

    test "SELECT with BETWEEN", %{db: db} do
      {:ok, rows} =
        PostgresDb.execute(db, "SELECT * FROM products WHERE price BETWEEN 100 AND 500")

      assert length(rows) == 2
    end
  end

  describe "PostgreSQL-specific features" do
    test "SELECT without FROM", %{db: db} do
      {:ok, rows} = PostgresDb.execute(db, "SELECT 1")
      assert length(rows) == 1
    end

    test "BOOLEAN type", %{db: db} do
      PostgresDb.execute(db, "CREATE TABLE bool_test (id INTEGER, active BOOLEAN)")
      PostgresDb.execute(db, "INSERT INTO bool_test VALUES (1, TRUE)")
      PostgresDb.execute(db, "INSERT INTO bool_test VALUES (2, FALSE)")

      {:ok, rows} = PostgresDb.execute(db, "SELECT * FROM bool_test WHERE active = TRUE")
      assert length(rows) == 1
    end

    test "IS TRUE / IS FALSE", %{db: db} do
      PostgresDb.execute(db, "CREATE TABLE bool_test2 (id INTEGER, active BOOLEAN)")
      PostgresDb.execute(db, "INSERT INTO bool_test2 VALUES (1, TRUE)")
      PostgresDb.execute(db, "INSERT INTO bool_test2 VALUES (2, FALSE)")

      {:ok, rows} = PostgresDb.execute(db, "SELECT * FROM bool_test2 WHERE active IS TRUE")
      assert length(rows) == 1
    end

    test "sequence NEXTVAL and CURRVAL", %{db: db} do
      PostgresDb.execute(db, "CREATE SEQUENCE test_seq START 100 INCREMENT 10")

      {:ok, val1} = PostgresDb.nextval(db, "test_seq")
      assert val1 == 100

      {:ok, val2} = PostgresDb.nextval(db, "test_seq")
      assert val2 == 110

      {:ok, curr} = PostgresDb.currval(db, "test_seq")
      assert curr == 110
    end

    test "COALESCE function", %{db: db} do
      PostgresDb.execute(db, "CREATE TABLE test_coalesce (id INTEGER, value VARCHAR(50))")
      PostgresDb.execute(db, "INSERT INTO test_coalesce VALUES (1, 'hello')")
      PostgresDb.execute(db, "INSERT INTO test_coalesce (id) VALUES (2)")

      {:ok, rows} =
        PostgresDb.execute(db, "SELECT id, COALESCE(value, 'default') FROM test_coalesce")

      assert length(rows) == 2
    end

    test "NULLIF function", %{db: db} do
      PostgresDb.execute(db, "CREATE TABLE test_nullif (id INTEGER, val INTEGER)")
      PostgresDb.execute(db, "INSERT INTO test_nullif VALUES (1, 0)")

      {:ok, rows} = PostgresDb.execute(db, "SELECT NULLIF(val, 0) FROM test_nullif")
      assert length(rows) == 1
    end
  end

  describe "String functions" do
    setup %{db: db} do
      PostgresDb.execute(db, "CREATE TABLE test_strings (text VARCHAR(100))")
      PostgresDb.execute(db, "INSERT INTO test_strings VALUES ('Hello World')")
      :ok
    end

    test "UPPER and LOWER functions", %{db: db} do
      {:ok, rows} = PostgresDb.execute(db, "SELECT UPPER(text), LOWER(text) FROM test_strings")
      assert length(rows) == 1
    end

    test "INITCAP function", %{db: db} do
      {:ok, rows} = PostgresDb.execute(db, "SELECT INITCAP(text) FROM test_strings")
      assert length(rows) == 1
    end

    test "LENGTH function", %{db: db} do
      {:ok, rows} = PostgresDb.execute(db, "SELECT LENGTH(text) FROM test_strings")
      assert length(rows) == 1
    end

    test "SUBSTRING function", %{db: db} do
      {:ok, rows} = PostgresDb.execute(db, "SELECT SUBSTRING(text, 1, 5) FROM test_strings")
      assert length(rows) == 1
    end

    test "LEFT and RIGHT functions", %{db: db} do
      {:ok, rows} =
        PostgresDb.execute(db, "SELECT LEFT(text, 5), RIGHT(text, 5) FROM test_strings")

      assert length(rows) == 1
    end

    test "TRIM function", %{db: db} do
      {:ok, rows} = PostgresDb.execute(db, "SELECT TRIM(text) FROM test_strings")
      assert length(rows) == 1
    end

    test "CONCAT function", %{db: db} do
      {:ok, rows} = PostgresDb.execute(db, "SELECT CONCAT(text, '!') FROM test_strings")
      assert length(rows) == 1
    end

    test "REPLACE function", %{db: db} do
      {:ok, rows} =
        PostgresDb.execute(db, "SELECT REPLACE(text, 'World', 'PostgreSQL') FROM test_strings")

      assert length(rows) == 1
    end
  end

  describe "Numeric functions" do
    test "ROUND function", %{db: db} do
      {:ok, rows} = PostgresDb.execute(db, "SELECT ROUND(3.14159, 2)")
      assert length(rows) == 1
    end

    test "FLOOR and CEIL functions", %{db: db} do
      {:ok, rows} = PostgresDb.execute(db, "SELECT FLOOR(3.7), CEIL(3.2)")
      assert length(rows) == 1
    end

    test "ABS function", %{db: db} do
      {:ok, rows} = PostgresDb.execute(db, "SELECT ABS(-42)")
      assert length(rows) == 1
    end

    test "MOD function", %{db: db} do
      {:ok, rows} = PostgresDb.execute(db, "SELECT MOD(17, 5)")
      assert length(rows) == 1
    end

    test "SQRT function", %{db: db} do
      {:ok, rows} = PostgresDb.execute(db, "SELECT SQRT(16)")
      assert length(rows) == 1
    end

    test "POWER function", %{db: db} do
      {:ok, rows} = PostgresDb.execute(db, "SELECT POWER(2, 10)")
      assert length(rows) == 1
    end
  end

  describe "UPDATE operations" do
    setup %{db: db} do
      PostgresDb.execute(
        db,
        "CREATE TABLE inventory (id INTEGER, quantity INTEGER, status VARCHAR(20))"
      )

      PostgresDb.execute(db, "INSERT INTO inventory VALUES (1, 100, 'active')")
      PostgresDb.execute(db, "INSERT INTO inventory VALUES (2, 50, 'active')")
      PostgresDb.execute(db, "INSERT INTO inventory VALUES (3, 0, 'active')")
      :ok
    end

    test "UPDATE single row", %{db: db} do
      result = PostgresDb.execute(db, "UPDATE inventory SET quantity = 75 WHERE id = 2")
      assert {:ok, %{rows_affected: 1}} = result

      {:ok, rows} = PostgresDb.execute(db, "SELECT * FROM inventory WHERE id = 2")
      assert hd(rows)["quantity"] == 75
    end

    test "UPDATE multiple rows", %{db: db} do
      result =
        PostgresDb.execute(db, "UPDATE inventory SET status = 'updated' WHERE quantity > 0")

      assert {:ok, %{rows_affected: 2}} = result
    end

    test "UPDATE with RETURNING", %{db: db} do
      result =
        PostgresDb.execute(
          db,
          "UPDATE inventory SET quantity = 200 WHERE id = 1 RETURNING id, quantity"
        )

      assert {:ok, %{rows: rows, rows_affected: 1}} = result
      assert length(rows) == 1
    end
  end

  describe "DELETE operations" do
    setup %{db: db} do
      PostgresDb.execute(
        db,
        "CREATE TABLE logs (id INTEGER, level VARCHAR(20), message VARCHAR(255))"
      )

      PostgresDb.execute(db, "INSERT INTO logs VALUES (1, 'INFO', 'Started')")
      PostgresDb.execute(db, "INSERT INTO logs VALUES (2, 'ERROR', 'Failed')")
      PostgresDb.execute(db, "INSERT INTO logs VALUES (3, 'INFO', 'Processing')")
      PostgresDb.execute(db, "INSERT INTO logs VALUES (4, 'ERROR', 'Timeout')")
      :ok
    end

    test "DELETE single row", %{db: db} do
      result = PostgresDb.execute(db, "DELETE FROM logs WHERE id = 1")
      assert {:ok, %{rows_affected: 1}} = result

      {:ok, rows} = PostgresDb.execute(db, "SELECT * FROM logs")
      assert length(rows) == 3
    end

    test "DELETE multiple rows", %{db: db} do
      result = PostgresDb.execute(db, "DELETE FROM logs WHERE level = 'ERROR'")
      assert {:ok, %{rows_affected: 2}} = result

      {:ok, rows} = PostgresDb.execute(db, "SELECT * FROM logs")
      assert length(rows) == 2
    end

    test "DELETE with RETURNING", %{db: db} do
      result = PostgresDb.execute(db, "DELETE FROM logs WHERE id = 1 RETURNING *")
      assert {:ok, %{rows: rows, rows_affected: 1}} = result
      assert length(rows) == 1
    end
  end

  describe "CREATE TYPE" do
    test "CREATE TYPE as ENUM", %{db: db} do
      result = PostgresDb.execute(db, "CREATE TYPE mood AS ENUM ('sad', 'ok', 'happy')")
      assert {:ok, %{message: "CREATE TYPE"}} = result
    end

    test "CREATE TYPE as composite", %{db: db} do
      result =
        PostgresDb.execute(db, "CREATE TYPE address AS (street VARCHAR(100), city VARCHAR(50))")

      assert {:ok, %{message: "CREATE TYPE"}} = result
    end

    test "DROP TYPE", %{db: db} do
      PostgresDb.execute(db, "CREATE TYPE temp_type AS ENUM ('a', 'b')")
      result = PostgresDb.execute(db, "DROP TYPE temp_type")
      assert {:ok, %{message: "DROP TYPE"}} = result
    end

    test "ALTER TYPE ADD VALUE", %{db: db} do
      PostgresDb.execute(db, "CREATE TYPE colors AS ENUM ('red', 'blue')")
      result = PostgresDb.execute(db, "ALTER TYPE colors ADD VALUE 'green'")
      assert {:ok, %{message: "ALTER TYPE"}} = result
    end
  end

  describe "list_tables and get_schema" do
    test "list_tables returns all tables", %{db: db} do
      PostgresDb.execute(db, "CREATE TABLE table1 (id INTEGER)")
      PostgresDb.execute(db, "CREATE TABLE table2 (id INTEGER)")
      PostgresDb.execute(db, "CREATE TABLE table3 (id INTEGER)")

      tables = PostgresDb.list_tables(db)
      assert length(tables) == 3
      assert "table1" in tables
      assert "table2" in tables
      assert "table3" in tables
    end

    test "get_schema returns table schema", %{db: db} do
      PostgresDb.execute(
        db,
        "CREATE TABLE employees (id INTEGER, name VARCHAR(100), salary NUMERIC)"
      )

      {:ok, schema} = PostgresDb.get_schema(db, "employees")
      assert is_list(schema.columns)
      assert length(schema.columns) == 3
    end
  end

  describe "reset" do
    test "reset clears all data", %{db: db} do
      PostgresDb.execute(db, "CREATE TABLE data (id INTEGER)")
      PostgresDb.execute(db, "INSERT INTO data VALUES (1)")

      assert PostgresDb.table_exists?(db, "data")

      PostgresDb.reset(db)

      refute PostgresDb.table_exists?(db, "data")
      assert PostgresDb.list_tables(db) == []
    end
  end

  describe "error handling" do
    test "returns error for non-existent table", %{db: db} do
      result = PostgresDb.execute(db, "SELECT * FROM nonexistent")
      assert {:error, _} = result
    end

    test "returns error for invalid SQL", %{db: db} do
      result = PostgresDb.execute(db, "INVALID SQL STATEMENT")
      assert {:error, _} = result
    end

    test "returns error for duplicate table creation", %{db: db} do
      PostgresDb.execute(db, "CREATE TABLE dup (id INTEGER)")
      result = PostgresDb.execute(db, "CREATE TABLE dup (id INTEGER)")
      assert {:error, _} = result
    end
  end
end
