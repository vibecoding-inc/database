defmodule VibeDbTest do
  use ExUnit.Case
  doctest VibeDb

  setup do
    {:ok, db} = VibeDb.start_link()
    {:ok, db: db}
  end

  describe "DDL operations" do
    test "CREATE TABLE creates a new table", %{db: db} do
      result = VibeDb.execute(db, "CREATE TABLE users (id NUMBER, name VARCHAR2(100))")
      assert {:ok, %{message: "Table USERS created"}} = result
      assert VibeDb.table_exists?(db, "users")
    end

    test "CREATE TABLE with constraints", %{db: db} do
      result =
        VibeDb.execute(db, """
          CREATE TABLE orders (
            id NUMBER PRIMARY KEY,
            user_id NUMBER NOT NULL,
            amount NUMBER(10,2) DEFAULT 0,
            status VARCHAR2(20)
          )
        """)

      assert {:ok, _} = result
      assert VibeDb.table_exists?(db, "orders")
    end

    test "DROP TABLE removes a table", %{db: db} do
      VibeDb.execute(db, "CREATE TABLE temp (id NUMBER)")
      assert VibeDb.table_exists?(db, "temp")

      result = VibeDb.execute(db, "DROP TABLE temp")
      assert {:ok, %{message: "Table TEMP dropped"}} = result
      refute VibeDb.table_exists?(db, "temp")
    end

    test "ALTER TABLE ADD COLUMN", %{db: db} do
      VibeDb.execute(db, "CREATE TABLE products (id NUMBER)")
      result = VibeDb.execute(db, "ALTER TABLE products ADD name VARCHAR2(100)")
      assert {:ok, %{message: "Table PRODUCTS altered"}} = result
    end

    test "ALTER TABLE DROP COLUMN", %{db: db} do
      VibeDb.execute(db, "CREATE TABLE items (id NUMBER, name VARCHAR2(100))")
      result = VibeDb.execute(db, "ALTER TABLE items DROP COLUMN name")
      assert {:ok, _} = result
    end

    test "CREATE INDEX", %{db: db} do
      VibeDb.execute(db, "CREATE TABLE employees (id NUMBER, dept_id NUMBER)")
      result = VibeDb.execute(db, "CREATE INDEX idx_dept ON employees (dept_id)")
      assert {:ok, %{message: "Index idx_dept created"}} = result
    end

    test "CREATE SEQUENCE", %{db: db} do
      result = VibeDb.execute(db, "CREATE SEQUENCE user_seq START WITH 1 INCREMENT BY 1")
      assert {:ok, %{message: "Sequence USER_SEQ created"}} = result
    end
  end

  describe "INSERT operations" do
    setup %{db: db} do
      VibeDb.execute(
        db,
        "CREATE TABLE users (id NUMBER, name VARCHAR2(100), email VARCHAR2(255))"
      )

      :ok
    end

    test "INSERT with column names", %{db: db} do
      result =
        VibeDb.execute(
          db,
          "INSERT INTO users (id, name, email) VALUES (1, 'John', 'john@example.com')"
        )

      assert {:ok, %{rows_affected: 1}} = result
    end

    test "INSERT without column names", %{db: db} do
      result = VibeDb.execute(db, "INSERT INTO users VALUES (1, 'Jane', 'jane@example.com')")
      assert {:ok, %{rows_affected: 1}} = result
    end

    test "INSERT multiple rows and SELECT", %{db: db} do
      VibeDb.execute(db, "INSERT INTO users VALUES (1, 'Alice', 'alice@example.com')")
      VibeDb.execute(db, "INSERT INTO users VALUES (2, 'Bob', 'bob@example.com')")
      VibeDb.execute(db, "INSERT INTO users VALUES (3, 'Charlie', 'charlie@example.com')")

      {:ok, rows} = VibeDb.execute(db, "SELECT * FROM users")
      assert length(rows) == 3
    end
  end

  describe "SELECT operations" do
    setup %{db: db} do
      VibeDb.execute(
        db,
        "CREATE TABLE products (id NUMBER, name VARCHAR2(100), price NUMBER, category VARCHAR2(50))"
      )

      VibeDb.execute(db, "INSERT INTO products VALUES (1, 'Laptop', 999, 'Electronics')")
      VibeDb.execute(db, "INSERT INTO products VALUES (2, 'Mouse', 29, 'Electronics')")
      VibeDb.execute(db, "INSERT INTO products VALUES (3, 'Desk', 199, 'Furniture')")
      VibeDb.execute(db, "INSERT INTO products VALUES (4, 'Chair', 149, 'Furniture')")
      :ok
    end

    test "SELECT all columns", %{db: db} do
      {:ok, rows} = VibeDb.execute(db, "SELECT * FROM products")
      assert length(rows) == 4
    end

    test "SELECT specific columns", %{db: db} do
      {:ok, rows} = VibeDb.execute(db, "SELECT name, price FROM products")
      assert length(rows) == 4
      assert Map.has_key?(hd(rows), "name")
      assert Map.has_key?(hd(rows), "price")
    end

    test "SELECT with WHERE clause", %{db: db} do
      {:ok, rows} = VibeDb.execute(db, "SELECT * FROM products WHERE category = 'Electronics'")
      assert length(rows) == 2
    end

    test "SELECT with WHERE and comparison operators", %{db: db} do
      {:ok, rows} = VibeDb.execute(db, "SELECT * FROM products WHERE price > 100")
      assert length(rows) == 3
    end

    test "SELECT with WHERE and multiple conditions (AND)", %{db: db} do
      {:ok, rows} =
        VibeDb.execute(
          db,
          "SELECT * FROM products WHERE category = 'Furniture' AND price > 150"
        )

      assert length(rows) == 1
    end

    test "SELECT with WHERE and OR condition", %{db: db} do
      {:ok, rows} =
        VibeDb.execute(db, "SELECT * FROM products WHERE name = 'Laptop' OR name = 'Mouse'")

      assert length(rows) == 2
    end

    test "SELECT with ORDER BY", %{db: db} do
      {:ok, rows} = VibeDb.execute(db, "SELECT * FROM products ORDER BY price ASC")
      prices = Enum.map(rows, & &1["price"])
      assert prices == [29, 149, 199, 999]
    end

    test "SELECT with ORDER BY DESC", %{db: db} do
      {:ok, rows} = VibeDb.execute(db, "SELECT * FROM products ORDER BY price DESC")
      prices = Enum.map(rows, & &1["price"])
      assert prices == [999, 199, 149, 29]
    end

    test "SELECT with LIKE", %{db: db} do
      {:ok, rows} = VibeDb.execute(db, "SELECT * FROM products WHERE name LIKE 'L%'")
      assert length(rows) == 1
      assert hd(rows)["name"] == "Laptop"
    end

    test "SELECT with IN clause", %{db: db} do
      {:ok, rows} = VibeDb.execute(db, "SELECT * FROM products WHERE id IN (1, 3)")
      assert length(rows) == 2
    end

    test "SELECT with BETWEEN", %{db: db} do
      {:ok, rows} = VibeDb.execute(db, "SELECT * FROM products WHERE price BETWEEN 100 AND 500")
      assert length(rows) == 2
    end
  end

  describe "VibeDb-specific features" do
    test "SELECT FROM DUAL", %{db: db} do
      {:ok, rows} = VibeDb.execute(db, "SELECT 1 FROM DUAL")
      assert length(rows) == 1
    end

    test "SYSDATE function", %{db: db} do
      {:ok, rows} = VibeDb.execute(db, "SELECT SYSDATE() FROM DUAL")
      assert length(rows) == 1
    end

    test "sequence NEXTVAL and CURRVAL", %{db: db} do
      VibeDb.execute(db, "CREATE SEQUENCE test_seq START WITH 100 INCREMENT BY 10")

      {:ok, val1} = VibeDb.nextval(db, "test_seq")
      assert val1 == 100

      {:ok, val2} = VibeDb.nextval(db, "test_seq")
      assert val2 == 110

      {:ok, curr} = VibeDb.currval(db, "test_seq")
      assert curr == 110
    end

    test "NVL function", %{db: db} do
      VibeDb.execute(db, "CREATE TABLE test_nvl (id NUMBER, value VARCHAR2(50))")
      VibeDb.execute(db, "INSERT INTO test_nvl VALUES (1, 'hello')")
      VibeDb.execute(db, "INSERT INTO test_nvl (id) VALUES (2)")

      {:ok, rows} = VibeDb.execute(db, "SELECT id, NVL(value, 'default') FROM test_nvl")
      assert length(rows) == 2
    end

    test "UPPER and LOWER functions", %{db: db} do
      VibeDb.execute(db, "CREATE TABLE test_case (name VARCHAR2(50))")
      VibeDb.execute(db, "INSERT INTO test_case VALUES ('Hello World')")

      {:ok, rows} = VibeDb.execute(db, "SELECT UPPER(name), LOWER(name) FROM test_case")
      assert length(rows) == 1
    end

    test "SUBSTR function", %{db: db} do
      VibeDb.execute(db, "CREATE TABLE test_substr (text VARCHAR2(100))")
      VibeDb.execute(db, "INSERT INTO test_substr VALUES ('Hello World')")

      {:ok, rows} = VibeDb.execute(db, "SELECT SUBSTR(text, 1, 5) FROM test_substr")
      assert length(rows) == 1
    end
  end

  describe "XML functions" do
    setup %{db: db} do
      VibeDb.execute(
        db,
        "CREATE TABLE xml_test (id NUMBER, name VARCHAR2(50), value VARCHAR2(100))"
      )

      VibeDb.execute(db, "INSERT INTO xml_test VALUES (1, 'product', 'Widget')")
      VibeDb.execute(db, "INSERT INTO xml_test VALUES (2, 'category', 'Electronics')")
      :ok
    end

    test "XMLELEMENT creates XML element", %{db: db} do
      {:ok, rows} =
        VibeDb.execute(db, "SELECT XMLELEMENT(NAME item, name) FROM xml_test WHERE id = 1")

      assert length(rows) == 1
      # Check that we get an XML-like string
      row = hd(rows)
      assert Map.values(row) |> Enum.any?(&(is_binary(&1) and String.contains?(&1, "<item>")))
    end

    test "XMLFOREST creates multiple elements", %{db: db} do
      {:ok, rows} =
        VibeDb.execute(db, "SELECT XMLFOREST(name, value) FROM xml_test WHERE id = 1")

      assert length(rows) == 1
      row = hd(rows)
      xml_output = Map.values(row) |> List.first()
      assert is_binary(xml_output)
      assert String.contains?(xml_output, "<name>")
      assert String.contains?(xml_output, "<value>")
    end

    test "XMLCOMMENT creates XML comment", %{db: db} do
      {:ok, rows} = VibeDb.execute(db, "SELECT XMLCOMMENT(name) FROM xml_test WHERE id = 1")
      assert length(rows) == 1
      row = hd(rows)
      xml_output = Map.values(row) |> List.first()
      assert is_binary(xml_output)
      assert String.contains?(xml_output, "<!--")
      assert String.contains?(xml_output, "-->")
    end

    test "XMLCDATA creates CDATA section", %{db: db} do
      {:ok, rows} = VibeDb.execute(db, "SELECT XMLCDATA(value) FROM xml_test WHERE id = 1")
      assert length(rows) == 1
      row = hd(rows)
      xml_output = Map.values(row) |> List.first()
      assert is_binary(xml_output)
      assert String.contains?(xml_output, "<![CDATA[")
      assert String.contains?(xml_output, "]]>")
    end

    test "XMLCONCAT concatenates XML fragments", %{db: db} do
      {:ok, rows} =
        VibeDb.execute(db, "SELECT XMLCONCAT(name, value) FROM xml_test WHERE id = 1")

      assert length(rows) == 1
      row = hd(rows)
      xml_output = Map.values(row) |> List.first()
      assert is_binary(xml_output)
      assert String.contains?(xml_output, "product")
      assert String.contains?(xml_output, "Widget")
    end

    test "XMLROOT adds XML declaration", %{db: db} do
      {:ok, rows} = VibeDb.execute(db, "SELECT XMLROOT(name) FROM xml_test WHERE id = 1")
      assert length(rows) == 1
      row = hd(rows)
      xml_output = Map.values(row) |> List.first()
      assert is_binary(xml_output)
      assert String.contains?(xml_output, "<?xml version=")
    end

    test "XMLPI creates processing instruction", %{db: db} do
      {:ok, rows} = VibeDb.execute(db, "SELECT XMLPI(NAME stylesheet) FROM DUAL")
      assert length(rows) == 1
      row = hd(rows)
      xml_output = Map.values(row) |> List.first()
      assert is_binary(xml_output)
      assert String.contains?(xml_output, "<?stylesheet")
    end
  end

  describe "UPDATE operations" do
    setup %{db: db} do
      VibeDb.execute(
        db,
        "CREATE TABLE inventory (id NUMBER, quantity NUMBER, status VARCHAR2(20))"
      )

      VibeDb.execute(db, "INSERT INTO inventory VALUES (1, 100, 'active')")
      VibeDb.execute(db, "INSERT INTO inventory VALUES (2, 50, 'active')")
      VibeDb.execute(db, "INSERT INTO inventory VALUES (3, 0, 'active')")
      :ok
    end

    test "UPDATE single row", %{db: db} do
      result = VibeDb.execute(db, "UPDATE inventory SET quantity = 75 WHERE id = 2")
      assert {:ok, %{rows_affected: 1}} = result

      {:ok, rows} = VibeDb.execute(db, "SELECT * FROM inventory WHERE id = 2")
      assert hd(rows)["quantity"] == 75
    end

    test "UPDATE multiple rows", %{db: db} do
      result = VibeDb.execute(db, "UPDATE inventory SET status = 'updated' WHERE quantity > 0")
      assert {:ok, %{rows_affected: 2}} = result
    end

    test "UPDATE all rows", %{db: db} do
      result = VibeDb.execute(db, "UPDATE inventory SET status = 'checked'")
      assert {:ok, %{rows_affected: 3}} = result
    end

    test "UPDATE multiple columns", %{db: db} do
      result =
        VibeDb.execute(
          db,
          "UPDATE inventory SET quantity = 200, status = 'restocked' WHERE id = 3"
        )

      assert {:ok, %{rows_affected: 1}} = result

      {:ok, rows} = VibeDb.execute(db, "SELECT * FROM inventory WHERE id = 3")
      row = hd(rows)
      assert row["quantity"] == 200
      assert row["status"] == "restocked"
    end
  end

  describe "DELETE operations" do
    setup %{db: db} do
      VibeDb.execute(
        db,
        "CREATE TABLE logs (id NUMBER, level VARCHAR2(20), message VARCHAR2(255))"
      )

      VibeDb.execute(db, "INSERT INTO logs VALUES (1, 'INFO', 'Started')")
      VibeDb.execute(db, "INSERT INTO logs VALUES (2, 'ERROR', 'Failed')")
      VibeDb.execute(db, "INSERT INTO logs VALUES (3, 'INFO', 'Processing')")
      VibeDb.execute(db, "INSERT INTO logs VALUES (4, 'ERROR', 'Timeout')")
      :ok
    end

    test "DELETE single row", %{db: db} do
      result = VibeDb.execute(db, "DELETE FROM logs WHERE id = 1")
      assert {:ok, %{rows_affected: 1}} = result

      {:ok, rows} = VibeDb.execute(db, "SELECT * FROM logs")
      assert length(rows) == 3
    end

    test "DELETE multiple rows", %{db: db} do
      result = VibeDb.execute(db, "DELETE FROM logs WHERE level = 'ERROR'")
      assert {:ok, %{rows_affected: 2}} = result

      {:ok, rows} = VibeDb.execute(db, "SELECT * FROM logs")
      assert length(rows) == 2
    end

    test "DELETE all rows", %{db: db} do
      result = VibeDb.execute(db, "DELETE FROM logs")
      assert {:ok, %{rows_affected: 4}} = result

      {:ok, rows} = VibeDb.execute(db, "SELECT * FROM logs")
      assert length(rows) == 0
    end
  end

  describe "list_tables and get_schema" do
    test "list_tables returns all tables", %{db: db} do
      VibeDb.execute(db, "CREATE TABLE table1 (id NUMBER)")
      VibeDb.execute(db, "CREATE TABLE table2 (id NUMBER)")
      VibeDb.execute(db, "CREATE TABLE table3 (id NUMBER)")

      tables = VibeDb.list_tables(db)
      assert length(tables) == 3
      assert "TABLE1" in tables
      assert "TABLE2" in tables
      assert "TABLE3" in tables
    end

    test "get_schema returns table schema", %{db: db} do
      VibeDb.execute(
        db,
        "CREATE TABLE employees (id NUMBER, name VARCHAR2(100), salary NUMBER)"
      )

      {:ok, schema} = VibeDb.get_schema(db, "employees")
      assert is_list(schema.columns)
      assert length(schema.columns) == 3
    end
  end

  describe "reset" do
    test "reset clears all data", %{db: db} do
      VibeDb.execute(db, "CREATE TABLE data (id NUMBER)")
      VibeDb.execute(db, "INSERT INTO data VALUES (1)")

      assert VibeDb.table_exists?(db, "data")

      VibeDb.reset(db)

      refute VibeDb.table_exists?(db, "data")
      assert VibeDb.list_tables(db) == []
    end
  end

  describe "error handling" do
    test "returns error for non-existent table", %{db: db} do
      result = VibeDb.execute(db, "SELECT * FROM nonexistent")
      assert {:error, _} = result
    end

    test "returns error for invalid SQL", %{db: db} do
      result = VibeDb.execute(db, "INVALID SQL STATEMENT")
      assert {:error, _} = result
    end

    test "returns error for duplicate table creation", %{db: db} do
      VibeDb.execute(db, "CREATE TABLE dup (id NUMBER)")
      result = VibeDb.execute(db, "CREATE TABLE dup (id NUMBER)")
      assert {:error, _} = result
    end
  end

  describe "Object-Relational Types" do
    test "CREATE TYPE creates an object type", %{db: db} do
      result =
        VibeDb.execute(db, """
          CREATE TYPE address_type AS OBJECT (
            street VARCHAR2(100),
            city VARCHAR2(50),
            zip_code VARCHAR2(10)
          )
        """)

      assert {:ok, %{message: "Type ADDRESS_TYPE created"}} = result
    end

    test "CREATE TYPE with methods", %{db: db} do
      result =
        VibeDb.execute(db, """
          CREATE TYPE person_type AS OBJECT (
            first_name VARCHAR2(50),
            last_name VARCHAR2(50),
            birth_date DATE,
            MEMBER FUNCTION get_full_name RETURN VARCHAR2
          )
        """)

      assert {:ok, %{message: "Type PERSON_TYPE created"}} = result
    end

    test "CREATE OR REPLACE TYPE replaces existing type", %{db: db} do
      VibeDb.execute(db, "CREATE TYPE test_type AS OBJECT (a NUMBER)")

      result =
        VibeDb.execute(db, """
          CREATE OR REPLACE TYPE test_type AS OBJECT (
            a NUMBER,
            b VARCHAR2(50)
          )
        """)

      assert {:ok, %{message: "Type TEST_TYPE created"}} = result
    end

    test "CREATE TYPE AS TABLE (nested table)", %{db: db} do
      result = VibeDb.execute(db, "CREATE TYPE phone_list AS TABLE OF VARCHAR2(20)")
      assert {:ok, %{message: "Type PHONE_LIST created"}} = result
    end

    test "CREATE TYPE AS VARRAY", %{db: db} do
      result = VibeDb.execute(db, "CREATE TYPE color_array AS VARRAY(10) OF VARCHAR2(20)")
      assert {:ok, %{message: "Type COLOR_ARRAY created"}} = result
    end

    test "DROP TYPE removes a type", %{db: db} do
      VibeDb.execute(db, "CREATE TYPE temp_type AS OBJECT (id NUMBER)")
      result = VibeDb.execute(db, "DROP TYPE temp_type")
      assert {:ok, %{message: "Type TEMP_TYPE dropped"}} = result
    end

    test "DROP TYPE with FORCE option", %{db: db} do
      VibeDb.execute(db, "CREATE TYPE force_type AS OBJECT (id NUMBER)")
      result = VibeDb.execute(db, "DROP TYPE force_type FORCE")
      assert {:ok, %{message: "Type FORCE_TYPE dropped"}} = result
    end

    test "ALTER TYPE ADD ATTRIBUTE", %{db: db} do
      VibeDb.execute(db, "CREATE TYPE modify_type AS OBJECT (id NUMBER)")
      result = VibeDb.execute(db, "ALTER TYPE modify_type ADD ATTRIBUTE name VARCHAR2(100)")
      assert {:ok, %{message: "Type MODIFY_TYPE altered"}} = result
    end

    test "ALTER TYPE DROP ATTRIBUTE", %{db: db} do
      VibeDb.execute(db, "CREATE TYPE drop_attr_type AS OBJECT (id NUMBER, name VARCHAR2(100))")
      result = VibeDb.execute(db, "ALTER TYPE drop_attr_type DROP ATTRIBUTE name")
      assert {:ok, %{message: "Type DROP_ATTR_TYPE altered"}} = result
    end

    test "CREATE TYPE with inheritance (UNDER)", %{db: db} do
      VibeDb.execute(db, "CREATE TYPE base_type AS OBJECT (id NUMBER)")

      result =
        VibeDb.execute(db, """
          CREATE TYPE derived_type UNDER base_type (
            name VARCHAR2(100)
          )
        """)

      assert {:ok, %{message: "Type DERIVED_TYPE created"}} = result
    end

    test "CREATE TYPE with constructor", %{db: db} do
      result =
        VibeDb.execute(db, """
          CREATE TYPE employee_type AS OBJECT (
            emp_id NUMBER,
            emp_name VARCHAR2(100),
            CONSTRUCTOR FUNCTION employee_type(id NUMBER) RETURN SELF AS RESULT
          )
        """)

      assert {:ok, %{message: "Type EMPLOYEE_TYPE created"}} = result
    end

    test "CREATE TYPE with static method", %{db: db} do
      result =
        VibeDb.execute(db, """
          CREATE TYPE util_type AS OBJECT (
            value NUMBER,
            STATIC FUNCTION create_default RETURN util_type
          )
        """)

      assert {:ok, %{message: "Type UTIL_TYPE created"}} = result
    end

    test "returns error for duplicate type creation", %{db: db} do
      VibeDb.execute(db, "CREATE TYPE dup_type AS OBJECT (id NUMBER)")
      result = VibeDb.execute(db, "CREATE TYPE dup_type AS OBJECT (id NUMBER)")
      assert {:error, _} = result
    end

    test "returns error for dropping non-existent type", %{db: db} do
      result = VibeDb.execute(db, "DROP TYPE nonexistent_type")
      assert {:error, _} = result
    end
  end

  describe "Object-Relational Tables" do
    test "CREATE TABLE OF type_name creates object table", %{db: db} do
      # First create the type
      VibeDb.execute(db, "CREATE TYPE person_t AS OBJECT (id NUMBER, name VARCHAR2(100))")

      # Then create the object table
      result = VibeDb.execute(db, "CREATE TABLE persons OF person_t")
      assert {:ok, %{message: "Table PERSONS created"}} = result
      assert VibeDb.table_exists?(db, "persons")
    end

    test "CREATE TABLE OF with constraints", %{db: db} do
      VibeDb.execute(
        db,
        "CREATE TYPE emp_type AS OBJECT (emp_id NUMBER, emp_name VARCHAR2(100))"
      )

      result =
        VibeDb.execute(
          db,
          "CREATE TABLE employees OF emp_type (PRIMARY KEY (emp_id))"
        )

      assert {:ok, %{message: "Table EMPLOYEES created"}} = result
    end
  end

  describe "Views" do
    setup %{db: db} do
      VibeDb.execute(
        db,
        "CREATE TABLE base_table (id NUMBER, name VARCHAR2(100), value NUMBER)"
      )

      VibeDb.execute(db, "INSERT INTO base_table VALUES (1, 'Alice', 100)")
      VibeDb.execute(db, "INSERT INTO base_table VALUES (2, 'Bob', 200)")
      :ok
    end

    test "CREATE VIEW creates a simple view", %{db: db} do
      result = VibeDb.execute(db, "CREATE VIEW test_view AS SELECT id, name FROM base_table")
      assert {:ok, %{message: "View TEST_VIEW created"}} = result
    end

    test "CREATE OR REPLACE VIEW replaces existing view", %{db: db} do
      VibeDb.execute(db, "CREATE VIEW my_view AS SELECT id FROM base_table")

      result =
        VibeDb.execute(db, "CREATE OR REPLACE VIEW my_view AS SELECT id, name FROM base_table")

      assert {:ok, %{message: "View MY_VIEW created"}} = result
    end

    test "CREATE VIEW with column list", %{db: db} do
      result =
        VibeDb.execute(
          db,
          "CREATE VIEW named_view (col1, col2) AS SELECT id, name FROM base_table"
        )

      assert {:ok, %{message: "View NAMED_VIEW created"}} = result
    end

    test "CREATE VIEW with WHERE clause", %{db: db} do
      result =
        VibeDb.execute(
          db,
          "CREATE VIEW filtered_view AS SELECT id, name FROM base_table WHERE value > 100"
        )

      assert {:ok, %{message: "View FILTERED_VIEW created"}} = result
    end

    test "DROP VIEW removes a view", %{db: db} do
      VibeDb.execute(db, "CREATE VIEW drop_me AS SELECT id FROM base_table")
      result = VibeDb.execute(db, "DROP VIEW drop_me")
      assert {:ok, %{message: "View DROP_ME dropped"}} = result
    end

    test "returns error for duplicate view creation", %{db: db} do
      VibeDb.execute(db, "CREATE VIEW dup_view AS SELECT id FROM base_table")
      result = VibeDb.execute(db, "CREATE VIEW dup_view AS SELECT id FROM base_table")
      assert {:error, _} = result
    end

    test "returns error for dropping non-existent view", %{db: db} do
      result = VibeDb.execute(db, "DROP VIEW nonexistent_view")
      assert {:error, _} = result
    end

    test "SELECT * from view returns all rows", %{db: db} do
      VibeDb.execute(db, "CREATE VIEW select_view AS SELECT id, name FROM base_table")
      {:ok, rows} = VibeDb.execute(db, "SELECT * FROM select_view")
      assert length(rows) == 2
      assert hd(rows)["id"] == 1
      assert hd(rows)["name"] == "Alice"
    end

    test "SELECT specific columns from view", %{db: db} do
      VibeDb.execute(db, "CREATE VIEW col_view AS SELECT id, name, value FROM base_table")
      {:ok, rows} = VibeDb.execute(db, "SELECT name FROM col_view")
      assert length(rows) == 2
      assert Map.has_key?(hd(rows), "name")
      refute Map.has_key?(hd(rows), "id")
    end

    test "SELECT from view with WHERE clause in outer query", %{db: db} do
      VibeDb.execute(db, "CREATE VIEW where_view AS SELECT id, name, value FROM base_table")
      {:ok, rows} = VibeDb.execute(db, "SELECT * FROM where_view WHERE id = 1")
      assert length(rows) == 1
      assert hd(rows)["name"] == "Alice"
    end

    test "SELECT from view with WHERE clause in view definition", %{db: db} do
      VibeDb.execute(
        db,
        "CREATE VIEW inner_where_view AS SELECT id, name FROM base_table WHERE value > 100"
      )

      {:ok, rows} = VibeDb.execute(db, "SELECT * FROM inner_where_view")
      assert length(rows) == 1
      assert hd(rows)["name"] == "Bob"
    end

    test "SELECT from view with ORDER BY", %{db: db} do
      VibeDb.execute(db, "CREATE VIEW order_view AS SELECT id, name FROM base_table")
      {:ok, rows} = VibeDb.execute(db, "SELECT * FROM order_view ORDER BY name DESC")
      assert length(rows) == 2
      assert hd(rows)["name"] == "Bob"
    end

    test "SELECT from view with combined WHERE and ORDER BY", %{db: db} do
      VibeDb.execute(db, "INSERT INTO base_table VALUES (3, 'Charlie', 300)")
      VibeDb.execute(db, "CREATE VIEW combo_view AS SELECT id, name, value FROM base_table")

      {:ok, rows} =
        VibeDb.execute(db, "SELECT name FROM combo_view WHERE value > 100 ORDER BY name ASC")

      assert length(rows) == 2
      assert hd(rows)["name"] == "Bob"
      assert List.last(rows)["name"] == "Charlie"
    end

    test "SELECT from nested views", %{db: db} do
      VibeDb.execute(db, "CREATE VIEW inner_view AS SELECT id, name FROM base_table")
      VibeDb.execute(db, "CREATE VIEW outer_view AS SELECT id, name FROM inner_view")
      {:ok, rows} = VibeDb.execute(db, "SELECT * FROM outer_view")
      assert length(rows) == 2
    end
  end

  describe "Materialized Views" do
    setup %{db: db} do
      VibeDb.execute(db, "CREATE TABLE mv_source (id NUMBER, data VARCHAR2(100))")
      VibeDb.execute(db, "INSERT INTO mv_source VALUES (1, 'test1')")
      :ok
    end

    test "CREATE MATERIALIZED VIEW creates a materialized view", %{db: db} do
      result =
        VibeDb.execute(db, "CREATE MATERIALIZED VIEW mv_test AS SELECT id, data FROM mv_source")

      assert {:ok, %{message: "Materialized view MV_TEST created"}} = result
    end

    test "DROP MATERIALIZED VIEW removes a materialized view", %{db: db} do
      VibeDb.execute(db, "CREATE MATERIALIZED VIEW mv_drop AS SELECT id FROM mv_source")
      result = VibeDb.execute(db, "DROP MATERIALIZED VIEW mv_drop")
      assert {:ok, %{message: "Materialized view MV_DROP dropped"}} = result
    end

    test "returns error for duplicate materialized view creation", %{db: db} do
      VibeDb.execute(db, "CREATE MATERIALIZED VIEW mv_dup AS SELECT id FROM mv_source")
      result = VibeDb.execute(db, "CREATE MATERIALIZED VIEW mv_dup AS SELECT id FROM mv_source")
      assert {:error, _} = result
    end

    test "returns error for dropping non-existent materialized view", %{db: db} do
      result = VibeDb.execute(db, "DROP MATERIALIZED VIEW nonexistent_mv")
      assert {:error, _} = result
    end

    test "SELECT * from materialized view returns all rows", %{db: db} do
      VibeDb.execute(db, "INSERT INTO mv_source VALUES (2, 'test2')")
      VibeDb.execute(db, "CREATE MATERIALIZED VIEW mv_select AS SELECT id, data FROM mv_source")
      {:ok, rows} = VibeDb.execute(db, "SELECT * FROM mv_select")
      assert length(rows) == 2
    end

    test "SELECT specific columns from materialized view", %{db: db} do
      VibeDb.execute(db, "CREATE MATERIALIZED VIEW mv_cols AS SELECT id, data FROM mv_source")
      {:ok, rows} = VibeDb.execute(db, "SELECT data FROM mv_cols")
      assert length(rows) == 1
      assert Map.has_key?(hd(rows), "data")
      refute Map.has_key?(hd(rows), "id")
    end

    test "SELECT from materialized view with WHERE clause", %{db: db} do
      VibeDb.execute(db, "INSERT INTO mv_source VALUES (2, 'test2')")
      VibeDb.execute(db, "INSERT INTO mv_source VALUES (3, 'test3')")
      VibeDb.execute(db, "CREATE MATERIALIZED VIEW mv_where AS SELECT id, data FROM mv_source")
      {:ok, rows} = VibeDb.execute(db, "SELECT * FROM mv_where WHERE id > 1")
      assert length(rows) == 2
    end

    test "SELECT from materialized view with ORDER BY", %{db: db} do
      VibeDb.execute(db, "INSERT INTO mv_source VALUES (2, 'aaa')")
      VibeDb.execute(db, "CREATE MATERIALIZED VIEW mv_order AS SELECT id, data FROM mv_source")
      {:ok, rows} = VibeDb.execute(db, "SELECT * FROM mv_order ORDER BY data ASC")
      assert length(rows) == 2
      assert hd(rows)["data"] == "aaa"
    end

    test "SELECT from materialized view with combined WHERE and ORDER BY", %{db: db} do
      VibeDb.execute(db, "INSERT INTO mv_source VALUES (2, 'banana')")
      VibeDb.execute(db, "INSERT INTO mv_source VALUES (3, 'apple')")
      VibeDb.execute(db, "CREATE MATERIALIZED VIEW mv_combo AS SELECT id, data FROM mv_source")

      {:ok, rows} =
        VibeDb.execute(db, "SELECT data FROM mv_combo WHERE id > 1 ORDER BY data ASC")

      assert length(rows) == 2
      assert hd(rows)["data"] == "apple"
      assert List.last(rows)["data"] == "banana"
    end
  end

  describe "Object-Relational Views" do
    setup %{db: db} do
      # Create a base type for object views
      VibeDb.execute(
        db,
        "CREATE TYPE person_view_t AS OBJECT (id NUMBER, name VARCHAR2(100), email VARCHAR2(200))"
      )

      # Create a base table
      VibeDb.execute(
        db,
        "CREATE TABLE persons_base (person_id NUMBER, person_name VARCHAR2(100), person_email VARCHAR2(200))"
      )

      VibeDb.execute(db, "INSERT INTO persons_base VALUES (1, 'Alice', 'alice@test.com')")
      VibeDb.execute(db, "INSERT INTO persons_base VALUES (2, 'Bob', 'bob@test.com')")
      :ok
    end

    test "CREATE VIEW OF type_name creates object view", %{db: db} do
      result =
        VibeDb.execute(
          db,
          "CREATE VIEW person_view OF person_view_t AS SELECT person_id, person_name, person_email FROM persons_base"
        )

      assert {:ok, %{message: "View PERSON_VIEW created"}} = result
    end

    test "CREATE VIEW OF type_name WITH OBJECT IDENTIFIER", %{db: db} do
      result =
        VibeDb.execute(
          db,
          "CREATE VIEW person_oid_view OF person_view_t WITH OBJECT IDENTIFIER (id) AS SELECT person_id, person_name, person_email FROM persons_base"
        )

      assert {:ok, %{message: "View PERSON_OID_VIEW created"}} = result
    end

    test "CREATE OR REPLACE VIEW OF type_name", %{db: db} do
      VibeDb.execute(
        db,
        "CREATE VIEW replace_view OF person_view_t AS SELECT person_id, person_name, person_email FROM persons_base"
      )

      result =
        VibeDb.execute(
          db,
          "CREATE OR REPLACE VIEW replace_view OF person_view_t AS SELECT person_id, person_name, person_email FROM persons_base WHERE person_id > 0"
        )

      assert {:ok, %{message: "View REPLACE_VIEW created"}} = result
    end

    test "CREATE VIEW OF with multiple OBJECT IDENTIFIER columns", %{db: db} do
      result =
        VibeDb.execute(
          db,
          "CREATE VIEW multi_oid_view OF person_view_t WITH OBJECT IDENTIFIER (id, name) AS SELECT person_id, person_name, person_email FROM persons_base"
        )

      assert {:ok, %{message: "View MULTI_OID_VIEW created"}} = result
    end

    test "DROP object-relational VIEW", %{db: db} do
      VibeDb.execute(
        db,
        "CREATE VIEW drop_obj_view OF person_view_t AS SELECT person_id, person_name, person_email FROM persons_base"
      )

      result = VibeDb.execute(db, "DROP VIEW drop_obj_view")
      assert {:ok, %{message: "View DROP_OBJ_VIEW dropped"}} = result
    end
  end

  describe "Stored Procedures" do
    test "CREATE PROCEDURE creates a procedure", %{db: db} do
      result =
        VibeDb.execute(db, """
          CREATE PROCEDURE hello_proc (p_name IN VARCHAR2)
          IS
          BEGIN
            NULL;
          END;
        """)

      assert {:ok, %{message: "Procedure HELLO_PROC created"}} = result
    end

    test "CREATE OR REPLACE PROCEDURE replaces a procedure", %{db: db} do
      VibeDb.execute(db, """
        CREATE PROCEDURE replace_proc IS BEGIN NULL; END;
      """)

      result =
        VibeDb.execute(db, """
          CREATE OR REPLACE PROCEDURE replace_proc IS BEGIN NULL; END;
        """)

      assert {:ok, %{message: "Procedure REPLACE_PROC created"}} = result
    end

    test "DROP PROCEDURE removes a procedure", %{db: db} do
      VibeDb.execute(db, "CREATE PROCEDURE drop_me_proc IS BEGIN NULL; END;")
      result = VibeDb.execute(db, "DROP PROCEDURE drop_me_proc")
      assert {:ok, %{message: "Procedure DROP_ME_PROC dropped"}} = result
    end

    test "returns error for duplicate procedure creation", %{db: db} do
      VibeDb.execute(db, "CREATE PROCEDURE dup_proc IS BEGIN NULL; END;")
      result = VibeDb.execute(db, "CREATE PROCEDURE dup_proc IS BEGIN NULL; END;")
      assert {:error, _} = result
    end

    test "returns error for dropping non-existent procedure", %{db: db} do
      result = VibeDb.execute(db, "DROP PROCEDURE nonexistent_proc")
      assert {:error, _} = result
    end

    test "CREATE PROCEDURE with OUT parameter", %{db: db} do
      result =
        VibeDb.execute(db, """
          CREATE PROCEDURE get_value (p_id IN NUMBER, p_result OUT VARCHAR2)
          IS
          BEGIN
            p_result := 'test';
          END;
        """)

      assert {:ok, %{message: "Procedure GET_VALUE created"}} = result
    end

    test "CREATE PROCEDURE with IN OUT parameter", %{db: db} do
      result =
        VibeDb.execute(db, """
          CREATE PROCEDURE update_value (p_value IN OUT NUMBER)
          IS
          BEGIN
            p_value := p_value + 1;
          END;
        """)

      assert {:ok, %{message: "Procedure UPDATE_VALUE created"}} = result
    end
  end

  describe "Stored Functions" do
    test "CREATE FUNCTION creates a function", %{db: db} do
      result =
        VibeDb.execute(db, """
          CREATE FUNCTION get_greeting (p_name VARCHAR2)
          RETURN VARCHAR2
          IS
          BEGIN
            RETURN 'Hello ' || p_name;
          END;
        """)

      assert {:ok, %{message: "Function GET_GREETING created"}} = result
    end

    test "CREATE OR REPLACE FUNCTION replaces a function", %{db: db} do
      VibeDb.execute(db, """
        CREATE FUNCTION replace_func RETURN NUMBER IS BEGIN RETURN 1; END;
      """)

      result =
        VibeDb.execute(db, """
          CREATE OR REPLACE FUNCTION replace_func RETURN NUMBER IS BEGIN RETURN 2; END;
        """)

      assert {:ok, %{message: "Function REPLACE_FUNC created"}} = result
    end

    test "DROP FUNCTION removes a function", %{db: db} do
      VibeDb.execute(db, "CREATE FUNCTION drop_me_func RETURN NUMBER IS BEGIN RETURN 1; END;")
      result = VibeDb.execute(db, "DROP FUNCTION drop_me_func")
      assert {:ok, %{message: "Function DROP_ME_FUNC dropped"}} = result
    end

    test "returns error for duplicate function creation", %{db: db} do
      VibeDb.execute(db, "CREATE FUNCTION dup_func RETURN NUMBER IS BEGIN RETURN 1; END;")

      result =
        VibeDb.execute(db, "CREATE FUNCTION dup_func RETURN NUMBER IS BEGIN RETURN 1; END;")

      assert {:error, _} = result
    end

    test "returns error for dropping non-existent function", %{db: db} do
      result = VibeDb.execute(db, "DROP FUNCTION nonexistent_func")
      assert {:error, _} = result
    end
  end

  describe "Packages" do
    test "CREATE PACKAGE creates a package specification", %{db: db} do
      result =
        VibeDb.execute(db, """
          CREATE PACKAGE my_package
          IS
            PROCEDURE proc1;
            FUNCTION func1 RETURN NUMBER;
          END;
        """)

      assert {:ok, %{message: "Package MY_PACKAGE created"}} = result
    end

    test "CREATE PACKAGE BODY creates a package body", %{db: db} do
      VibeDb.execute(db, """
        CREATE PACKAGE body_pkg IS PROCEDURE proc1; END;
      """)

      result =
        VibeDb.execute(db, """
          CREATE PACKAGE BODY body_pkg
          IS
            PROCEDURE proc1 IS BEGIN NULL; END;
          END;
        """)

      assert {:ok, %{message: "Package body BODY_PKG created"}} = result
    end

    test "CREATE OR REPLACE PACKAGE replaces a package", %{db: db} do
      VibeDb.execute(db, """
        CREATE PACKAGE replace_pkg IS PROCEDURE proc1; END;
      """)

      result =
        VibeDb.execute(db, """
          CREATE OR REPLACE PACKAGE replace_pkg IS PROCEDURE proc2; END;
        """)

      assert {:ok, %{message: "Package REPLACE_PKG created"}} = result
    end

    test "DROP PACKAGE removes a package", %{db: db} do
      VibeDb.execute(db, "CREATE PACKAGE drop_pkg IS PROCEDURE proc1; END;")
      result = VibeDb.execute(db, "DROP PACKAGE drop_pkg")
      assert {:ok, %{message: "Package DROP_PKG dropped"}} = result
    end

    test "DROP PACKAGE BODY removes only package body", %{db: db} do
      VibeDb.execute(db, "CREATE PACKAGE body_drop_pkg IS PROCEDURE proc1; END;")

      VibeDb.execute(
        db,
        "CREATE PACKAGE BODY body_drop_pkg IS PROCEDURE proc1 IS BEGIN NULL; END; END;"
      )

      result = VibeDb.execute(db, "DROP PACKAGE BODY body_drop_pkg")
      assert {:ok, %{message: "Package body BODY_DROP_PKG dropped"}} = result
    end

    test "returns error for duplicate package creation", %{db: db} do
      VibeDb.execute(db, "CREATE PACKAGE dup_pkg IS PROCEDURE proc1; END;")
      result = VibeDb.execute(db, "CREATE PACKAGE dup_pkg IS PROCEDURE proc1; END;")
      assert {:error, _} = result
    end

    test "returns error for dropping non-existent package", %{db: db} do
      result = VibeDb.execute(db, "DROP PACKAGE nonexistent_pkg")
      assert {:error, _} = result
    end
  end

  describe "Triggers" do
    setup %{db: db} do
      VibeDb.execute(db, "CREATE TABLE trigger_test (id NUMBER, name VARCHAR2(100))")
      :ok
    end

    test "CREATE TRIGGER creates a BEFORE trigger", %{db: db} do
      result =
        VibeDb.execute(db, """
          CREATE TRIGGER before_insert_trigger
          BEFORE INSERT ON trigger_test
          FOR EACH ROW
          BEGIN
            NULL;
          END;
        """)

      assert {:ok, %{message: "Trigger BEFORE_INSERT_TRIGGER created"}} = result
    end

    test "CREATE TRIGGER creates an AFTER trigger", %{db: db} do
      result =
        VibeDb.execute(db, """
          CREATE TRIGGER after_update_trigger
          AFTER UPDATE ON trigger_test
          FOR EACH ROW
          BEGIN
            NULL;
          END;
        """)

      assert {:ok, %{message: "Trigger AFTER_UPDATE_TRIGGER created"}} = result
    end

    test "CREATE TRIGGER for multiple events", %{db: db} do
      result =
        VibeDb.execute(db, """
          CREATE TRIGGER multi_event_trigger
          BEFORE INSERT OR UPDATE OR DELETE ON trigger_test
          FOR EACH ROW
          BEGIN
            NULL;
          END;
        """)

      assert {:ok, %{message: "Trigger MULTI_EVENT_TRIGGER created"}} = result
    end

    test "CREATE TRIGGER with UPDATE OF columns", %{db: db} do
      result =
        VibeDb.execute(db, """
          CREATE TRIGGER update_col_trigger
          BEFORE UPDATE OF name ON trigger_test
          FOR EACH ROW
          BEGIN
            NULL;
          END;
        """)

      assert {:ok, %{message: "Trigger UPDATE_COL_TRIGGER created"}} = result
    end

    test "CREATE TRIGGER with WHEN clause", %{db: db} do
      result =
        VibeDb.execute(db, """
          CREATE TRIGGER when_trigger
          BEFORE INSERT ON trigger_test
          FOR EACH ROW
          WHEN (NEW.id > 0)
          BEGIN
            NULL;
          END;
        """)

      assert {:ok, %{message: "Trigger WHEN_TRIGGER created"}} = result
    end

    test "CREATE INSTEAD OF TRIGGER for views", %{db: db} do
      VibeDb.execute(db, "CREATE VIEW trigger_view AS SELECT id, name FROM trigger_test")

      result =
        VibeDb.execute(db, """
          CREATE TRIGGER instead_trigger
          INSTEAD OF INSERT ON trigger_view
          FOR EACH ROW
          BEGIN
            NULL;
          END;
        """)

      assert {:ok, %{message: "Trigger INSTEAD_TRIGGER created"}} = result
    end

    test "CREATE OR REPLACE TRIGGER replaces a trigger", %{db: db} do
      VibeDb.execute(db, """
        CREATE TRIGGER replace_trigger BEFORE INSERT ON trigger_test FOR EACH ROW BEGIN NULL; END;
      """)

      result =
        VibeDb.execute(db, """
          CREATE OR REPLACE TRIGGER replace_trigger AFTER INSERT ON trigger_test FOR EACH ROW BEGIN NULL; END;
        """)

      assert {:ok, %{message: "Trigger REPLACE_TRIGGER created"}} = result
    end

    test "DROP TRIGGER removes a trigger", %{db: db} do
      VibeDb.execute(db, """
        CREATE TRIGGER drop_trigger BEFORE INSERT ON trigger_test FOR EACH ROW BEGIN NULL; END;
      """)

      result = VibeDb.execute(db, "DROP TRIGGER drop_trigger")
      assert {:ok, %{message: "Trigger DROP_TRIGGER dropped"}} = result
    end

    test "ALTER TRIGGER ENABLE enables a trigger", %{db: db} do
      VibeDb.execute(db, """
        CREATE TRIGGER enable_trigger BEFORE INSERT ON trigger_test FOR EACH ROW BEGIN NULL; END;
      """)

      result = VibeDb.execute(db, "ALTER TRIGGER enable_trigger ENABLE")
      assert {:ok, %{message: "Trigger ENABLE_TRIGGER enabled"}} = result
    end

    test "ALTER TRIGGER DISABLE disables a trigger", %{db: db} do
      VibeDb.execute(db, """
        CREATE TRIGGER disable_trigger BEFORE INSERT ON trigger_test FOR EACH ROW BEGIN NULL; END;
      """)

      result = VibeDb.execute(db, "ALTER TRIGGER disable_trigger DISABLE")
      assert {:ok, %{message: "Trigger DISABLE_TRIGGER disabled"}} = result
    end

    test "returns error for duplicate trigger creation", %{db: db} do
      VibeDb.execute(db, """
        CREATE TRIGGER dup_trigger BEFORE INSERT ON trigger_test FOR EACH ROW BEGIN NULL; END;
      """)

      result =
        VibeDb.execute(db, """
          CREATE TRIGGER dup_trigger BEFORE INSERT ON trigger_test FOR EACH ROW BEGIN NULL; END;
        """)

      assert {:error, _} = result
    end

    test "returns error for dropping non-existent trigger", %{db: db} do
      result = VibeDb.execute(db, "DROP TRIGGER nonexistent_trigger")
      assert {:error, _} = result
    end

    test "CREATE TRIGGER for statement level", %{db: db} do
      result =
        VibeDb.execute(db, """
          CREATE TRIGGER statement_trigger
          AFTER INSERT ON trigger_test
          BEGIN
            NULL;
          END;
        """)

      assert {:ok, %{message: "Trigger STATEMENT_TRIGGER created"}} = result
    end

    # The following tests document that trigger execution is NOT currently implemented.
    # Triggers can be defined but their bodies do not execute during DML operations.

    test "trigger body does NOT execute on INSERT (limitation)", %{db: db} do
      # Create an audit log table to track trigger execution
      VibeDb.execute(db, "CREATE TABLE audit_log (action VARCHAR2(50), timestamp NUMBER)")

      # Create a trigger that would insert into audit_log when inserting into trigger_test
      VibeDb.execute(db, """
        CREATE TRIGGER audit_insert_trigger
        BEFORE INSERT ON trigger_test
        FOR EACH ROW
        BEGIN
          INSERT INTO audit_log (action, timestamp) VALUES ('INSERT', 1);
        END;
      """)

      # Insert into trigger_test
      VibeDb.execute(db, "INSERT INTO trigger_test (id, name) VALUES (1, 'Alice')")

      # Check if the trigger executed by verifying audit_log has a record
      {:ok, audit_rows} = VibeDb.execute(db, "SELECT * FROM audit_log")

      # LIMITATION: Trigger bodies do NOT execute - audit_log will be empty
      assert length(audit_rows) == 0,
             "Trigger execution is not implemented - audit_log should be empty"
    end

    test "trigger body does NOT execute on UPDATE (limitation)", %{db: db} do
      # Create an audit log table
      VibeDb.execute(db, "CREATE TABLE update_log (old_name VARCHAR2(100), new_name VARCHAR2(100))")

      # Insert initial data
      VibeDb.execute(db, "INSERT INTO trigger_test (id, name) VALUES (1, 'Alice')")

      # Create an AFTER UPDATE trigger
      VibeDb.execute(db, """
        CREATE TRIGGER audit_update_trigger
        AFTER UPDATE ON trigger_test
        FOR EACH ROW
        BEGIN
          INSERT INTO update_log (old_name, new_name) VALUES (:OLD.name, :NEW.name);
        END;
      """)

      # Update the row
      VibeDb.execute(db, "UPDATE trigger_test SET name = 'Bob' WHERE id = 1")

      # Check if the trigger executed
      {:ok, log_rows} = VibeDb.execute(db, "SELECT * FROM update_log")

      # LIMITATION: Trigger bodies do NOT execute - update_log will be empty
      assert length(log_rows) == 0,
             "Trigger execution is not implemented - update_log should be empty"
    end

    test "trigger body does NOT execute on DELETE (limitation)", %{db: db} do
      # Create a delete log table
      VibeDb.execute(db, "CREATE TABLE delete_log (deleted_id NUMBER)")

      # Insert initial data
      VibeDb.execute(db, "INSERT INTO trigger_test (id, name) VALUES (1, 'Alice')")

      # Create a BEFORE DELETE trigger
      VibeDb.execute(db, """
        CREATE TRIGGER audit_delete_trigger
        BEFORE DELETE ON trigger_test
        FOR EACH ROW
        BEGIN
          INSERT INTO delete_log (deleted_id) VALUES (:OLD.id);
        END;
      """)

      # Delete the row
      VibeDb.execute(db, "DELETE FROM trigger_test WHERE id = 1")

      # Check if the trigger executed
      {:ok, log_rows} = VibeDb.execute(db, "SELECT * FROM delete_log")

      # LIMITATION: Trigger bodies do NOT execute - delete_log will be empty
      assert length(log_rows) == 0,
             "Trigger execution is not implemented - delete_log should be empty"
    end

    test "disabled trigger does not execute (expected behavior)", %{db: db} do
      # Create an audit log table
      VibeDb.execute(db, "CREATE TABLE disabled_log (action VARCHAR2(50))")

      # Create and then disable a trigger
      VibeDb.execute(db, """
        CREATE TRIGGER disabled_trigger
        BEFORE INSERT ON trigger_test
        FOR EACH ROW
        BEGIN
          INSERT INTO disabled_log (action) VALUES ('TRIGGERED');
        END;
      """)

      VibeDb.execute(db, "ALTER TRIGGER disabled_trigger DISABLE")

      # Insert into trigger_test - disabled trigger should not fire
      VibeDb.execute(db, "INSERT INTO trigger_test (id, name) VALUES (1, 'Alice')")

      # Check that the disabled trigger did not execute
      {:ok, log_rows} = VibeDb.execute(db, "SELECT * FROM disabled_log")

      # Even though trigger execution is not implemented, this test documents
      # that disabled triggers should definitely not execute
      assert length(log_rows) == 0, "Disabled trigger should not execute"
    end
  end

  describe "JOIN operations" do
    setup %{db: db} do
      VibeDb.execute(db, "CREATE TABLE users(id NUMBER, name VARCHAR(100))")
      VibeDb.execute(db, "CREATE TABLE emp(u_id NUMBER, job_name VARCHAR(100))")

      VibeDb.execute(db, "INSERT INTO users VALUES (1, 'max')")
      VibeDb.execute(db, "INSERT INTO users VALUES (2, 'josef')")
      VibeDb.execute(db, "INSERT INTO users VALUES (3, 'anna')")

      VibeDb.execute(db, "INSERT INTO emp VALUES (1, 'chef')")
      VibeDb.execute(db, "INSERT INTO emp VALUES (2, 'hackler')")

      :ok
    end

    test "INNER JOIN returns matching rows", %{db: db} do
      {:ok, rows} = VibeDb.execute(db, "SELECT * FROM users JOIN emp ON id = u_id")

      assert length(rows) == 2

      # Should have columns from both tables
      first_row = hd(rows)
      assert Map.has_key?(first_row, "id")
      assert Map.has_key?(first_row, "name")
      assert Map.has_key?(first_row, "u_id")
      assert Map.has_key?(first_row, "job_name")
    end

    test "INNER JOIN matches correct rows", %{db: db} do
      {:ok, rows} = VibeDb.execute(db, "SELECT * FROM users JOIN emp ON id = u_id")

      # Find max's row (id=1)
      max_row = Enum.find(rows, fn r -> r["id"] == 1 end)
      assert max_row["name"] == "max"
      assert max_row["job_name"] == "chef"

      # Find josef's row (id=2)
      josef_row = Enum.find(rows, fn r -> r["id"] == 2 end)
      assert josef_row["name"] == "josef"
      assert josef_row["job_name"] == "hackler"
    end

    test "LEFT OUTER JOIN includes unmatched left rows", %{db: db} do
      {:ok, rows} = VibeDb.execute(db, "SELECT * FROM users LEFT JOIN emp ON id = u_id")

      # Should include anna (id=3) who has no emp record
      assert length(rows) == 3

      anna_row = Enum.find(rows, fn r -> r["id"] == 3 end)
      assert anna_row["name"] == "anna"
      assert anna_row["job_name"] == nil
    end

    test "CROSS JOIN returns cartesian product", %{db: db} do
      {:ok, rows} = VibeDb.execute(db, "SELECT * FROM users CROSS JOIN emp")

      # 3 users * 2 employees = 6 rows
      assert length(rows) == 6
    end

    test "JOIN with WHERE clause filters results", %{db: db} do
      {:ok, rows} = VibeDb.execute(db, "SELECT * FROM users JOIN emp ON id = u_id WHERE name = 'max'")

      assert length(rows) == 1
      assert hd(rows)["name"] == "max"
    end
  end

  describe "SET command" do
    test "SET command is accepted", %{db: db} do
      result = VibeDb.execute(db, "SET dbms_output = 'on'")
      assert {:ok, %{message: message}} = result
      assert message =~ "DBMS_OUTPUT"
    end
  end

  describe "INSERT validation" do
    test "INSERT with values in column position returns error", %{db: db} do
      VibeDb.execute(db, "CREATE TABLE test_table(id NUMBER, name VARCHAR(100))")

      result = VibeDb.execute(db, "INSERT INTO test_table(1, 'test')")
      assert {:error, message} = result
      assert message =~ "column names cannot be numeric values or string literals"
    end

    test "INSERT with VALUE instead of VALUES returns error", %{db: db} do
      VibeDb.execute(db, "CREATE TABLE test_table(id NUMBER, name VARCHAR(100))")

      result = VibeDb.execute(db, "INSERT INTO test_table VALUE (1, 'test')")
      assert {:error, message} = result
      assert message =~ "use VALUES instead of VALUE"
    end
  end
end
