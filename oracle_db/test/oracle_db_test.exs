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

  describe "XML functions" do
    setup %{db: db} do
      OracleDb.execute(
        db,
        "CREATE TABLE xml_test (id NUMBER, name VARCHAR2(50), value VARCHAR2(100))"
      )

      OracleDb.execute(db, "INSERT INTO xml_test VALUES (1, 'product', 'Widget')")
      OracleDb.execute(db, "INSERT INTO xml_test VALUES (2, 'category', 'Electronics')")
      :ok
    end

    test "XMLELEMENT creates XML element", %{db: db} do
      {:ok, rows} =
        OracleDb.execute(db, "SELECT XMLELEMENT(NAME item, name) FROM xml_test WHERE id = 1")

      assert length(rows) == 1
      # Check that we get an XML-like string
      row = hd(rows)
      assert Map.values(row) |> Enum.any?(&(is_binary(&1) and String.contains?(&1, "<item>")))
    end

    test "XMLFOREST creates multiple elements", %{db: db} do
      {:ok, rows} =
        OracleDb.execute(db, "SELECT XMLFOREST(name, value) FROM xml_test WHERE id = 1")

      assert length(rows) == 1
      row = hd(rows)
      xml_output = Map.values(row) |> List.first()
      assert is_binary(xml_output)
      assert String.contains?(xml_output, "<name>")
      assert String.contains?(xml_output, "<value>")
    end

    test "XMLCOMMENT creates XML comment", %{db: db} do
      {:ok, rows} = OracleDb.execute(db, "SELECT XMLCOMMENT(name) FROM xml_test WHERE id = 1")
      assert length(rows) == 1
      row = hd(rows)
      xml_output = Map.values(row) |> List.first()
      assert is_binary(xml_output)
      assert String.contains?(xml_output, "<!--")
      assert String.contains?(xml_output, "-->")
    end

    test "XMLCDATA creates CDATA section", %{db: db} do
      {:ok, rows} = OracleDb.execute(db, "SELECT XMLCDATA(value) FROM xml_test WHERE id = 1")
      assert length(rows) == 1
      row = hd(rows)
      xml_output = Map.values(row) |> List.first()
      assert is_binary(xml_output)
      assert String.contains?(xml_output, "<![CDATA[")
      assert String.contains?(xml_output, "]]>")
    end

    test "XMLCONCAT concatenates XML fragments", %{db: db} do
      {:ok, rows} =
        OracleDb.execute(db, "SELECT XMLCONCAT(name, value) FROM xml_test WHERE id = 1")

      assert length(rows) == 1
      row = hd(rows)
      xml_output = Map.values(row) |> List.first()
      assert is_binary(xml_output)
      assert String.contains?(xml_output, "product")
      assert String.contains?(xml_output, "Widget")
    end

    test "XMLROOT adds XML declaration", %{db: db} do
      {:ok, rows} = OracleDb.execute(db, "SELECT XMLROOT(name) FROM xml_test WHERE id = 1")
      assert length(rows) == 1
      row = hd(rows)
      xml_output = Map.values(row) |> List.first()
      assert is_binary(xml_output)
      assert String.contains?(xml_output, "<?xml version=")
    end

    test "XMLPI creates processing instruction", %{db: db} do
      {:ok, rows} = OracleDb.execute(db, "SELECT XMLPI(NAME stylesheet) FROM DUAL")
      assert length(rows) == 1
      row = hd(rows)
      xml_output = Map.values(row) |> List.first()
      assert is_binary(xml_output)
      assert String.contains?(xml_output, "<?stylesheet")
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

  describe "Object-Relational Types" do
    test "CREATE TYPE creates an object type", %{db: db} do
      result =
        OracleDb.execute(db, """
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
        OracleDb.execute(db, """
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
      OracleDb.execute(db, "CREATE TYPE test_type AS OBJECT (a NUMBER)")

      result =
        OracleDb.execute(db, """
          CREATE OR REPLACE TYPE test_type AS OBJECT (
            a NUMBER,
            b VARCHAR2(50)
          )
        """)

      assert {:ok, %{message: "Type TEST_TYPE created"}} = result
    end

    test "CREATE TYPE AS TABLE (nested table)", %{db: db} do
      result = OracleDb.execute(db, "CREATE TYPE phone_list AS TABLE OF VARCHAR2(20)")
      assert {:ok, %{message: "Type PHONE_LIST created"}} = result
    end

    test "CREATE TYPE AS VARRAY", %{db: db} do
      result = OracleDb.execute(db, "CREATE TYPE color_array AS VARRAY(10) OF VARCHAR2(20)")
      assert {:ok, %{message: "Type COLOR_ARRAY created"}} = result
    end

    test "DROP TYPE removes a type", %{db: db} do
      OracleDb.execute(db, "CREATE TYPE temp_type AS OBJECT (id NUMBER)")
      result = OracleDb.execute(db, "DROP TYPE temp_type")
      assert {:ok, %{message: "Type TEMP_TYPE dropped"}} = result
    end

    test "DROP TYPE with FORCE option", %{db: db} do
      OracleDb.execute(db, "CREATE TYPE force_type AS OBJECT (id NUMBER)")
      result = OracleDb.execute(db, "DROP TYPE force_type FORCE")
      assert {:ok, %{message: "Type FORCE_TYPE dropped"}} = result
    end

    test "ALTER TYPE ADD ATTRIBUTE", %{db: db} do
      OracleDb.execute(db, "CREATE TYPE modify_type AS OBJECT (id NUMBER)")
      result = OracleDb.execute(db, "ALTER TYPE modify_type ADD ATTRIBUTE name VARCHAR2(100)")
      assert {:ok, %{message: "Type MODIFY_TYPE altered"}} = result
    end

    test "ALTER TYPE DROP ATTRIBUTE", %{db: db} do
      OracleDb.execute(db, "CREATE TYPE drop_attr_type AS OBJECT (id NUMBER, name VARCHAR2(100))")
      result = OracleDb.execute(db, "ALTER TYPE drop_attr_type DROP ATTRIBUTE name")
      assert {:ok, %{message: "Type DROP_ATTR_TYPE altered"}} = result
    end

    test "CREATE TYPE with inheritance (UNDER)", %{db: db} do
      OracleDb.execute(db, "CREATE TYPE base_type AS OBJECT (id NUMBER)")

      result =
        OracleDb.execute(db, """
          CREATE TYPE derived_type UNDER base_type (
            name VARCHAR2(100)
          )
        """)

      assert {:ok, %{message: "Type DERIVED_TYPE created"}} = result
    end

    test "CREATE TYPE with constructor", %{db: db} do
      result =
        OracleDb.execute(db, """
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
        OracleDb.execute(db, """
          CREATE TYPE util_type AS OBJECT (
            value NUMBER,
            STATIC FUNCTION create_default RETURN util_type
          )
        """)

      assert {:ok, %{message: "Type UTIL_TYPE created"}} = result
    end

    test "returns error for duplicate type creation", %{db: db} do
      OracleDb.execute(db, "CREATE TYPE dup_type AS OBJECT (id NUMBER)")
      result = OracleDb.execute(db, "CREATE TYPE dup_type AS OBJECT (id NUMBER)")
      assert {:error, _} = result
    end

    test "returns error for dropping non-existent type", %{db: db} do
      result = OracleDb.execute(db, "DROP TYPE nonexistent_type")
      assert {:error, _} = result
    end
  end

  describe "Object-Relational Tables" do
    test "CREATE TABLE OF type_name creates object table", %{db: db} do
      # First create the type
      OracleDb.execute(db, "CREATE TYPE person_t AS OBJECT (id NUMBER, name VARCHAR2(100))")

      # Then create the object table
      result = OracleDb.execute(db, "CREATE TABLE persons OF person_t")
      assert {:ok, %{message: "Table PERSONS created"}} = result
      assert OracleDb.table_exists?(db, "persons")
    end

    test "CREATE TABLE OF with constraints", %{db: db} do
      OracleDb.execute(
        db,
        "CREATE TYPE emp_type AS OBJECT (emp_id NUMBER, emp_name VARCHAR2(100))"
      )

      result =
        OracleDb.execute(
          db,
          "CREATE TABLE employees OF emp_type (PRIMARY KEY (emp_id))"
        )

      assert {:ok, %{message: "Table EMPLOYEES created"}} = result
    end
  end

  describe "Views" do
    setup %{db: db} do
      OracleDb.execute(
        db,
        "CREATE TABLE base_table (id NUMBER, name VARCHAR2(100), value NUMBER)"
      )

      OracleDb.execute(db, "INSERT INTO base_table VALUES (1, 'Alice', 100)")
      OracleDb.execute(db, "INSERT INTO base_table VALUES (2, 'Bob', 200)")
      :ok
    end

    test "CREATE VIEW creates a simple view", %{db: db} do
      result = OracleDb.execute(db, "CREATE VIEW test_view AS SELECT id, name FROM base_table")
      assert {:ok, %{message: "View TEST_VIEW created"}} = result
    end

    test "CREATE OR REPLACE VIEW replaces existing view", %{db: db} do
      OracleDb.execute(db, "CREATE VIEW my_view AS SELECT id FROM base_table")

      result =
        OracleDb.execute(db, "CREATE OR REPLACE VIEW my_view AS SELECT id, name FROM base_table")

      assert {:ok, %{message: "View MY_VIEW created"}} = result
    end

    test "CREATE VIEW with column list", %{db: db} do
      result =
        OracleDb.execute(
          db,
          "CREATE VIEW named_view (col1, col2) AS SELECT id, name FROM base_table"
        )

      assert {:ok, %{message: "View NAMED_VIEW created"}} = result
    end

    test "CREATE VIEW with WHERE clause", %{db: db} do
      result =
        OracleDb.execute(
          db,
          "CREATE VIEW filtered_view AS SELECT id, name FROM base_table WHERE value > 100"
        )

      assert {:ok, %{message: "View FILTERED_VIEW created"}} = result
    end

    test "DROP VIEW removes a view", %{db: db} do
      OracleDb.execute(db, "CREATE VIEW drop_me AS SELECT id FROM base_table")
      result = OracleDb.execute(db, "DROP VIEW drop_me")
      assert {:ok, %{message: "View DROP_ME dropped"}} = result
    end

    test "returns error for duplicate view creation", %{db: db} do
      OracleDb.execute(db, "CREATE VIEW dup_view AS SELECT id FROM base_table")
      result = OracleDb.execute(db, "CREATE VIEW dup_view AS SELECT id FROM base_table")
      assert {:error, _} = result
    end

    test "returns error for dropping non-existent view", %{db: db} do
      result = OracleDb.execute(db, "DROP VIEW nonexistent_view")
      assert {:error, _} = result
    end
  end

  describe "Materialized Views" do
    setup %{db: db} do
      OracleDb.execute(db, "CREATE TABLE mv_source (id NUMBER, data VARCHAR2(100))")
      OracleDb.execute(db, "INSERT INTO mv_source VALUES (1, 'test1')")
      :ok
    end

    test "CREATE MATERIALIZED VIEW creates a materialized view", %{db: db} do
      result =
        OracleDb.execute(db, "CREATE MATERIALIZED VIEW mv_test AS SELECT id, data FROM mv_source")

      assert {:ok, %{message: "Materialized view MV_TEST created"}} = result
    end

    test "DROP MATERIALIZED VIEW removes a materialized view", %{db: db} do
      OracleDb.execute(db, "CREATE MATERIALIZED VIEW mv_drop AS SELECT id FROM mv_source")
      result = OracleDb.execute(db, "DROP MATERIALIZED VIEW mv_drop")
      assert {:ok, %{message: "Materialized view MV_DROP dropped"}} = result
    end

    test "returns error for duplicate materialized view creation", %{db: db} do
      OracleDb.execute(db, "CREATE MATERIALIZED VIEW mv_dup AS SELECT id FROM mv_source")
      result = OracleDb.execute(db, "CREATE MATERIALIZED VIEW mv_dup AS SELECT id FROM mv_source")
      assert {:error, _} = result
    end

    test "returns error for dropping non-existent materialized view", %{db: db} do
      result = OracleDb.execute(db, "DROP MATERIALIZED VIEW nonexistent_mv")
      assert {:error, _} = result
    end
  end
end
