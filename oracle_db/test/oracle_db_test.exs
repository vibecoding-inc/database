defmodule OracleDbTest do
  use ExUnit.Case
  doctest OracleDb

  setup do
    {:ok, db} = OracleDb.start_link()
    {:ok, db: db}
  end

  describe "DDL operations" do
    test "CREATE TABLE creates a new table", %{db: db} do
      result = OracleDb.execute(db, "CREATE TABLE users (id NUMBER, name VARCHAR2(100))")
      assert {:ok, %{message: "Table USERS created"}} = result
      assert OracleDb.table_exists?(db, "users")
    end

    test "CREATE TABLE with constraints", %{db: db} do
      result =
        OracleDb.execute(db, """
          CREATE TABLE orders (
            id NUMBER PRIMARY KEY,
            user_id NUMBER NOT NULL,
            amount NUMBER(10,2) DEFAULT 0,
            status VARCHAR2(20)
          )
        """)

      assert {:ok, _} = result
      assert OracleDb.table_exists?(db, "orders")
    end

    test "DROP TABLE removes a table", %{db: db} do
      OracleDb.execute(db, "CREATE TABLE temp (id NUMBER)")
      assert OracleDb.table_exists?(db, "temp")

      result = OracleDb.execute(db, "DROP TABLE temp")
      assert {:ok, %{message: "Table TEMP dropped"}} = result
      refute OracleDb.table_exists?(db, "temp")
    end

    test "ALTER TABLE ADD COLUMN", %{db: db} do
      OracleDb.execute(db, "CREATE TABLE products (id NUMBER)")
      result = OracleDb.execute(db, "ALTER TABLE products ADD name VARCHAR2(100)")
      assert {:ok, %{message: "Table PRODUCTS altered"}} = result
    end

    test "ALTER TABLE DROP COLUMN", %{db: db} do
      OracleDb.execute(db, "CREATE TABLE items (id NUMBER, name VARCHAR2(100))")
      result = OracleDb.execute(db, "ALTER TABLE items DROP COLUMN name")
      assert {:ok, _} = result
    end

    test "CREATE INDEX", %{db: db} do
      OracleDb.execute(db, "CREATE TABLE employees (id NUMBER, dept_id NUMBER)")
      result = OracleDb.execute(db, "CREATE INDEX idx_dept ON employees (dept_id)")
      assert {:ok, %{message: "Index idx_dept created"}} = result
    end

    test "CREATE SEQUENCE", %{db: db} do
      result = OracleDb.execute(db, "CREATE SEQUENCE user_seq START WITH 1 INCREMENT BY 1")
      assert {:ok, %{message: "Sequence USER_SEQ created"}} = result
    end
  end

  describe "INSERT operations" do
    setup %{db: db} do
      OracleDb.execute(
        db,
        "CREATE TABLE users (id NUMBER, name VARCHAR2(100), email VARCHAR2(255))"
      )

      :ok
    end

    test "INSERT with column names", %{db: db} do
      result =
        OracleDb.execute(
          db,
          "INSERT INTO users (id, name, email) VALUES (1, 'John', 'john@example.com')"
        )

      assert {:ok, %{rows_affected: 1}} = result
    end

    test "INSERT without column names", %{db: db} do
      result = OracleDb.execute(db, "INSERT INTO users VALUES (1, 'Jane', 'jane@example.com')")
      assert {:ok, %{rows_affected: 1}} = result
    end

    test "INSERT multiple rows and SELECT", %{db: db} do
      OracleDb.execute(db, "INSERT INTO users VALUES (1, 'Alice', 'alice@example.com')")
      OracleDb.execute(db, "INSERT INTO users VALUES (2, 'Bob', 'bob@example.com')")
      OracleDb.execute(db, "INSERT INTO users VALUES (3, 'Charlie', 'charlie@example.com')")

      {:ok, rows} = OracleDb.execute(db, "SELECT * FROM users")
      assert length(rows) == 3
    end
  end

  describe "SELECT operations" do
    setup %{db: db} do
      OracleDb.execute(
        db,
        "CREATE TABLE products (id NUMBER, name VARCHAR2(100), price NUMBER, category VARCHAR2(50))"
      )

      OracleDb.execute(db, "INSERT INTO products VALUES (1, 'Laptop', 999, 'Electronics')")
      OracleDb.execute(db, "INSERT INTO products VALUES (2, 'Mouse', 29, 'Electronics')")
      OracleDb.execute(db, "INSERT INTO products VALUES (3, 'Desk', 199, 'Furniture')")
      OracleDb.execute(db, "INSERT INTO products VALUES (4, 'Chair', 149, 'Furniture')")
      :ok
    end

    test "SELECT all columns", %{db: db} do
      {:ok, rows} = OracleDb.execute(db, "SELECT * FROM products")
      assert length(rows) == 4
    end

    test "SELECT specific columns", %{db: db} do
      {:ok, rows} = OracleDb.execute(db, "SELECT name, price FROM products")
      assert length(rows) == 4
      assert Map.has_key?(hd(rows), "name")
      assert Map.has_key?(hd(rows), "price")
    end

    test "SELECT with WHERE clause", %{db: db} do
      {:ok, rows} = OracleDb.execute(db, "SELECT * FROM products WHERE category = 'Electronics'")
      assert length(rows) == 2
    end

    test "SELECT with WHERE and comparison operators", %{db: db} do
      {:ok, rows} = OracleDb.execute(db, "SELECT * FROM products WHERE price > 100")
      assert length(rows) == 3
    end

    test "SELECT with WHERE and multiple conditions (AND)", %{db: db} do
      {:ok, rows} =
        OracleDb.execute(
          db,
          "SELECT * FROM products WHERE category = 'Furniture' AND price > 150"
        )

      assert length(rows) == 1
    end

    test "SELECT with WHERE and OR condition", %{db: db} do
      {:ok, rows} =
        OracleDb.execute(db, "SELECT * FROM products WHERE name = 'Laptop' OR name = 'Mouse'")

      assert length(rows) == 2
    end

    test "SELECT with ORDER BY", %{db: db} do
      {:ok, rows} = OracleDb.execute(db, "SELECT * FROM products ORDER BY price ASC")
      prices = Enum.map(rows, & &1["price"])
      assert prices == [29, 149, 199, 999]
    end

    test "SELECT with ORDER BY DESC", %{db: db} do
      {:ok, rows} = OracleDb.execute(db, "SELECT * FROM products ORDER BY price DESC")
      prices = Enum.map(rows, & &1["price"])
      assert prices == [999, 199, 149, 29]
    end

    test "SELECT with LIKE", %{db: db} do
      {:ok, rows} = OracleDb.execute(db, "SELECT * FROM products WHERE name LIKE 'L%'")
      assert length(rows) == 1
      assert hd(rows)["name"] == "Laptop"
    end

    test "SELECT with IN clause", %{db: db} do
      {:ok, rows} = OracleDb.execute(db, "SELECT * FROM products WHERE id IN (1, 3)")
      assert length(rows) == 2
    end

    test "SELECT with BETWEEN", %{db: db} do
      {:ok, rows} = OracleDb.execute(db, "SELECT * FROM products WHERE price BETWEEN 100 AND 500")
      assert length(rows) == 2
    end
  end

  describe "Oracle-specific features" do
    test "SELECT FROM DUAL", %{db: db} do
      {:ok, rows} = OracleDb.execute(db, "SELECT 1 FROM DUAL")
      assert length(rows) == 1
    end

    test "SYSDATE function", %{db: db} do
      {:ok, rows} = OracleDb.execute(db, "SELECT SYSDATE() FROM DUAL")
      assert length(rows) == 1
    end

    test "sequence NEXTVAL and CURRVAL", %{db: db} do
      OracleDb.execute(db, "CREATE SEQUENCE test_seq START WITH 100 INCREMENT BY 10")

      {:ok, val1} = OracleDb.nextval(db, "test_seq")
      assert val1 == 100

      {:ok, val2} = OracleDb.nextval(db, "test_seq")
      assert val2 == 110

      {:ok, curr} = OracleDb.currval(db, "test_seq")
      assert curr == 110
    end

    test "NVL function", %{db: db} do
      OracleDb.execute(db, "CREATE TABLE test_nvl (id NUMBER, value VARCHAR2(50))")
      OracleDb.execute(db, "INSERT INTO test_nvl VALUES (1, 'hello')")
      OracleDb.execute(db, "INSERT INTO test_nvl (id) VALUES (2)")

      {:ok, rows} = OracleDb.execute(db, "SELECT id, NVL(value, 'default') FROM test_nvl")
      assert length(rows) == 2
    end

    test "UPPER and LOWER functions", %{db: db} do
      OracleDb.execute(db, "CREATE TABLE test_case (name VARCHAR2(50))")
      OracleDb.execute(db, "INSERT INTO test_case VALUES ('Hello World')")

      {:ok, rows} = OracleDb.execute(db, "SELECT UPPER(name), LOWER(name) FROM test_case")
      assert length(rows) == 1
    end

    test "SUBSTR function", %{db: db} do
      OracleDb.execute(db, "CREATE TABLE test_substr (text VARCHAR2(100))")
      OracleDb.execute(db, "INSERT INTO test_substr VALUES ('Hello World')")

      {:ok, rows} = OracleDb.execute(db, "SELECT SUBSTR(text, 1, 5) FROM test_substr")
      assert length(rows) == 1
    end
  end

  describe "UPDATE operations" do
    setup %{db: db} do
      OracleDb.execute(
        db,
        "CREATE TABLE inventory (id NUMBER, quantity NUMBER, status VARCHAR2(20))"
      )

      OracleDb.execute(db, "INSERT INTO inventory VALUES (1, 100, 'active')")
      OracleDb.execute(db, "INSERT INTO inventory VALUES (2, 50, 'active')")
      OracleDb.execute(db, "INSERT INTO inventory VALUES (3, 0, 'active')")
      :ok
    end

    test "UPDATE single row", %{db: db} do
      result = OracleDb.execute(db, "UPDATE inventory SET quantity = 75 WHERE id = 2")
      assert {:ok, %{rows_affected: 1}} = result

      {:ok, rows} = OracleDb.execute(db, "SELECT * FROM inventory WHERE id = 2")
      assert hd(rows)["quantity"] == 75
    end

    test "UPDATE multiple rows", %{db: db} do
      result = OracleDb.execute(db, "UPDATE inventory SET status = 'updated' WHERE quantity > 0")
      assert {:ok, %{rows_affected: 2}} = result
    end

    test "UPDATE all rows", %{db: db} do
      result = OracleDb.execute(db, "UPDATE inventory SET status = 'checked'")
      assert {:ok, %{rows_affected: 3}} = result
    end

    test "UPDATE multiple columns", %{db: db} do
      result =
        OracleDb.execute(
          db,
          "UPDATE inventory SET quantity = 200, status = 'restocked' WHERE id = 3"
        )

      assert {:ok, %{rows_affected: 1}} = result

      {:ok, rows} = OracleDb.execute(db, "SELECT * FROM inventory WHERE id = 3")
      row = hd(rows)
      assert row["quantity"] == 200
      assert row["status"] == "restocked"
    end
  end

  describe "DELETE operations" do
    setup %{db: db} do
      OracleDb.execute(
        db,
        "CREATE TABLE logs (id NUMBER, level VARCHAR2(20), message VARCHAR2(255))"
      )

      OracleDb.execute(db, "INSERT INTO logs VALUES (1, 'INFO', 'Started')")
      OracleDb.execute(db, "INSERT INTO logs VALUES (2, 'ERROR', 'Failed')")
      OracleDb.execute(db, "INSERT INTO logs VALUES (3, 'INFO', 'Processing')")
      OracleDb.execute(db, "INSERT INTO logs VALUES (4, 'ERROR', 'Timeout')")
      :ok
    end

    test "DELETE single row", %{db: db} do
      result = OracleDb.execute(db, "DELETE FROM logs WHERE id = 1")
      assert {:ok, %{rows_affected: 1}} = result

      {:ok, rows} = OracleDb.execute(db, "SELECT * FROM logs")
      assert length(rows) == 3
    end

    test "DELETE multiple rows", %{db: db} do
      result = OracleDb.execute(db, "DELETE FROM logs WHERE level = 'ERROR'")
      assert {:ok, %{rows_affected: 2}} = result

      {:ok, rows} = OracleDb.execute(db, "SELECT * FROM logs")
      assert length(rows) == 2
    end

    test "DELETE all rows", %{db: db} do
      result = OracleDb.execute(db, "DELETE FROM logs")
      assert {:ok, %{rows_affected: 4}} = result

      {:ok, rows} = OracleDb.execute(db, "SELECT * FROM logs")
      assert length(rows) == 0
    end
  end

  describe "list_tables and get_schema" do
    test "list_tables returns all tables", %{db: db} do
      OracleDb.execute(db, "CREATE TABLE table1 (id NUMBER)")
      OracleDb.execute(db, "CREATE TABLE table2 (id NUMBER)")
      OracleDb.execute(db, "CREATE TABLE table3 (id NUMBER)")

      tables = OracleDb.list_tables(db)
      assert length(tables) == 3
      assert "TABLE1" in tables
      assert "TABLE2" in tables
      assert "TABLE3" in tables
    end

    test "get_schema returns table schema", %{db: db} do
      OracleDb.execute(
        db,
        "CREATE TABLE employees (id NUMBER, name VARCHAR2(100), salary NUMBER)"
      )

      {:ok, schema} = OracleDb.get_schema(db, "employees")
      assert is_list(schema.columns)
      assert length(schema.columns) == 3
    end
  end

  describe "reset" do
    test "reset clears all data", %{db: db} do
      OracleDb.execute(db, "CREATE TABLE data (id NUMBER)")
      OracleDb.execute(db, "INSERT INTO data VALUES (1)")

      assert OracleDb.table_exists?(db, "data")

      OracleDb.reset(db)

      refute OracleDb.table_exists?(db, "data")
      assert OracleDb.list_tables(db) == []
    end
  end

  describe "error handling" do
    test "returns error for non-existent table", %{db: db} do
      result = OracleDb.execute(db, "SELECT * FROM nonexistent")
      assert {:error, _} = result
    end

    test "returns error for invalid SQL", %{db: db} do
      result = OracleDb.execute(db, "INVALID SQL STATEMENT")
      assert {:error, _} = result
    end

    test "returns error for duplicate table creation", %{db: db} do
      OracleDb.execute(db, "CREATE TABLE dup (id NUMBER)")
      result = OracleDb.execute(db, "CREATE TABLE dup (id NUMBER)")
      assert {:error, _} = result
    end
  end
end
