defmodule OracleDb.SqlParserTest do
  use ExUnit.Case

  alias OracleDb.SqlParser

  describe "SELECT parsing" do
    test "parses simple SELECT *" do
      {:select, result} = SqlParser.parse("SELECT * FROM users")
      assert result.table == "users"
      assert [{:all, "*"}] = result.columns
    end

    test "parses SELECT with specific columns" do
      {:select, result} = SqlParser.parse("SELECT id, name, email FROM users")
      assert result.table == "users"
      assert length(result.columns) == 3
    end

    test "parses SELECT with WHERE clause" do
      {:select, result} = SqlParser.parse("SELECT * FROM users WHERE id = 1")
      assert result.table == "users"
      assert result.where != nil
    end

    test "parses SELECT with multiple WHERE conditions" do
      {:select, result} =
        SqlParser.parse("SELECT * FROM users WHERE status = 'active' AND age > 18")

      assert result.table == "users"
      assert {:and, _, _} = result.where
    end

    test "parses SELECT with OR condition" do
      {:select, result} =
        SqlParser.parse("SELECT * FROM users WHERE role = 'admin' OR role = 'moderator'")

      assert {:or, _, _} = result.where
    end

    test "parses SELECT with ORDER BY" do
      {:select, result} = SqlParser.parse("SELECT * FROM users ORDER BY name ASC")
      assert result.order_by != nil
      assert [{"name", :asc}] = result.order_by
    end

    test "parses SELECT with ORDER BY DESC" do
      {:select, result} = SqlParser.parse("SELECT * FROM products ORDER BY price DESC")
      assert [{"price", :desc}] = result.order_by
    end

    test "parses SELECT with LIKE" do
      {:select, result} = SqlParser.parse("SELECT * FROM users WHERE name LIKE 'J%'")
      assert {:like, _, _} = result.where
    end

    test "parses SELECT with IN clause" do
      {:select, result} = SqlParser.parse("SELECT * FROM users WHERE id IN (1, 2, 3)")
      assert {:in, _, _} = result.where
    end

    test "parses SELECT with BETWEEN" do
      {:select, result} = SqlParser.parse("SELECT * FROM products WHERE price BETWEEN 10 AND 100")
      assert {:between, _, _, _} = result.where
    end

    test "parses SELECT with IS NULL" do
      {:select, result} = SqlParser.parse("SELECT * FROM users WHERE email IS NULL")
      assert {:is_null, _} = result.where
    end

    test "parses SELECT with IS NOT NULL" do
      {:select, result} = SqlParser.parse("SELECT * FROM users WHERE email IS NOT NULL")
      assert {:is_not_null, _} = result.where
    end

    test "parses SELECT FROM DUAL" do
      {:select, result} = SqlParser.parse("SELECT 1 FROM DUAL")
      assert result.table == "DUAL"
    end

    test "parses SELECT with function" do
      {:select, result} = SqlParser.parse("SELECT COUNT(*) FROM users")
      assert [{:function, "COUNT", _, _}] = result.columns
    end

    test "parses SELECT with NVL function" do
      {:select, result} = SqlParser.parse("SELECT NVL(name, 'Unknown') FROM users")
      assert [{:function, "NVL", _, _}] = result.columns
    end

    test "parses SELECT with column alias" do
      {:select, result} = SqlParser.parse("SELECT name AS user_name FROM users")
      assert [{:column, "name", "user_name"}] = result.columns
    end
  end

  describe "INSERT parsing" do
    test "parses INSERT with column names" do
      {:insert, result} = SqlParser.parse("INSERT INTO users (id, name) VALUES (1, 'John')")
      assert result.table == "users"
      assert result.columns == ["id", "name"]
      assert result.values == [[1, "John"]]
    end

    test "parses INSERT without column names" do
      {:insert, result} =
        SqlParser.parse("INSERT INTO users VALUES (1, 'John', 'john@example.com')")

      assert result.table == "users"
      assert result.columns == nil
      assert length(hd(result.values)) == 3
    end

    test "parses INSERT with NULL value" do
      {:insert, result} = SqlParser.parse("INSERT INTO users VALUES (1, 'John', NULL)")
      assert List.last(hd(result.values)) == nil
    end
  end

  describe "UPDATE parsing" do
    test "parses simple UPDATE" do
      {:update, result} = SqlParser.parse("UPDATE users SET name = 'Jane' WHERE id = 1")
      assert result.table == "users"
      assert result.sets == [{"name", "Jane"}]
      assert result.where != nil
    end

    test "parses UPDATE with multiple SET clauses" do
      {:update, result} =
        SqlParser.parse("UPDATE users SET name = 'Jane', email = 'jane@example.com' WHERE id = 1")

      assert length(result.sets) == 2
    end

    test "parses UPDATE with numeric value" do
      {:update, result} = SqlParser.parse("UPDATE products SET price = 99 WHERE id = 1")
      assert result.sets == [{"price", 99}]
    end
  end

  describe "DELETE parsing" do
    test "parses DELETE with WHERE" do
      {:delete, result} = SqlParser.parse("DELETE FROM users WHERE id = 1")
      assert result.table == "users"
      assert result.where != nil
    end

    test "parses DELETE without WHERE" do
      {:delete, result} = SqlParser.parse("DELETE FROM users")
      assert result.table == "users"
      assert result.where == nil
    end
  end

  describe "CREATE TABLE parsing" do
    test "parses simple CREATE TABLE" do
      {:create_table, result} =
        SqlParser.parse("CREATE TABLE users (id NUMBER, name VARCHAR2(100))")

      assert result.table == "users"
      assert length(result.columns) == 2
    end

    test "parses CREATE TABLE with NOT NULL constraint" do
      {:create_table, result} =
        SqlParser.parse("CREATE TABLE users (id NUMBER NOT NULL, name VARCHAR2(100))")

      {_, _, modifiers} = hd(result.columns)
      assert :not_null in modifiers
    end

    test "parses CREATE TABLE with PRIMARY KEY" do
      {:create_table, result} =
        SqlParser.parse("CREATE TABLE users (id NUMBER PRIMARY KEY, name VARCHAR2(100))")

      {_, _, modifiers} = hd(result.columns)
      assert :primary_key in modifiers
    end

    test "parses CREATE TABLE with DEFAULT" do
      {:create_table, result} =
        SqlParser.parse("CREATE TABLE users (id NUMBER, status VARCHAR2(20) DEFAULT 'active')")

      {_, _, modifiers} = List.last(result.columns)
      assert {:default, "active"} in modifiers
    end

    test "parses various column types" do
      {:create_table, result} =
        SqlParser.parse("""
          CREATE TABLE test (
            a NUMBER,
            b VARCHAR2(100),
            c DATE,
            d TIMESTAMP,
            e CLOB,
            f BLOB
          )
        """)

      assert length(result.columns) == 6
    end
  end

  describe "DROP TABLE parsing" do
    test "parses simple DROP TABLE" do
      {:drop_table, result} = SqlParser.parse("DROP TABLE users")
      assert result.table == "users"
      assert result.cascade == false
    end

    test "parses DROP TABLE CASCADE" do
      {:drop_table, result} = SqlParser.parse("DROP TABLE users CASCADE")
      assert result.cascade == true
    end
  end

  describe "ALTER TABLE parsing" do
    test "parses ALTER TABLE ADD COLUMN" do
      {:alter_table, result} = SqlParser.parse("ALTER TABLE users ADD email VARCHAR2(255)")
      assert result.table == "users"
      assert result.action == :add_column
    end

    test "parses ALTER TABLE DROP COLUMN" do
      {:alter_table, result} = SqlParser.parse("ALTER TABLE users DROP COLUMN email")
      assert result.action == :drop_column
    end

    test "parses ALTER TABLE MODIFY" do
      {:alter_table, result} = SqlParser.parse("ALTER TABLE users MODIFY name VARCHAR2(200)")
      assert result.action == :modify_column
    end

    test "parses ALTER TABLE RENAME COLUMN" do
      {:alter_table, result} =
        SqlParser.parse("ALTER TABLE users RENAME COLUMN name TO full_name")

      assert result.action == :rename_column
      assert result.details == {"name", "full_name"}
    end
  end

  describe "CREATE INDEX parsing" do
    test "parses CREATE INDEX" do
      {:create_index, result} = SqlParser.parse("CREATE INDEX idx_name ON users (name)")
      assert result.name == "idx_name"
      assert result.table == "users"
      assert result.columns == ["name"]
    end

    test "parses CREATE UNIQUE INDEX" do
      {:create_index, result} = SqlParser.parse("CREATE UNIQUE INDEX idx_email ON users (email)")
      assert result.unique == true
    end
  end

  describe "CREATE SEQUENCE parsing" do
    test "parses simple CREATE SEQUENCE" do
      {:create_sequence, result} = SqlParser.parse("CREATE SEQUENCE user_seq")
      assert result.name == "user_seq"
    end

    test "parses CREATE SEQUENCE with options" do
      {:create_sequence, result} =
        SqlParser.parse("CREATE SEQUENCE user_seq START WITH 100 INCREMENT BY 10")

      assert result.options[:start] == 100
      assert result.options[:increment] == 10
    end

    test "parses CREATE SEQUENCE with MINVALUE and MAXVALUE" do
      {:create_sequence, result} =
        SqlParser.parse("CREATE SEQUENCE user_seq MINVALUE 1 MAXVALUE 1000")

      assert result.options[:min_value] == 1
      assert result.options[:max_value] == 1000
    end
  end

  describe "error handling" do
    test "returns error for empty SQL" do
      assert {:error, "Empty SQL statement"} = SqlParser.parse("")
    end

    test "returns error for unknown command" do
      assert {:error, "Unknown SQL command: UNKNOWN"} = SqlParser.parse("UNKNOWN command")
    end
  end

  describe "PL/SQL syntax validation" do
    test "returns error for incomplete procedure (missing END)" do
      sql = """
      CREATE PROCEDURE hello_proc (p_name IN VARCHAR2)
      IS
      BEGIN
      DBMS_OUTPUT.PUT_LINE('Hello ' || p_name);
      """

      assert {:error, "PL/SQL block not properly terminated with END;"} = SqlParser.parse(sql)
    end

    test "returns error for procedure with unbalanced BEGIN/END" do
      sql = """
      CREATE PROCEDURE test_proc
      IS
      BEGIN
        BEGIN
          NULL;
        END;
      """

      assert {:error, _} = SqlParser.parse(sql)
    end

    test "accepts complete procedure with END;" do
      sql = """
      CREATE PROCEDURE hello_proc (p_name IN VARCHAR2)
      IS
      BEGIN
        DBMS_OUTPUT.PUT_LINE('Hello ' || p_name);
      END;
      """

      assert {:create_procedure, %{name: "hello_proc"}} = SqlParser.parse(sql)
    end

    test "accepts complete procedure with END name;" do
      sql = """
      CREATE PROCEDURE hello_proc
      IS
      BEGIN
        NULL;
      END hello_proc;
      """

      assert {:create_procedure, %{name: "hello_proc"}} = SqlParser.parse(sql)
    end

    test "returns error for incomplete function (missing END)" do
      sql = """
      CREATE FUNCTION add_numbers (p_a NUMBER, p_b NUMBER)
      RETURN NUMBER
      IS
      BEGIN
        RETURN p_a + p_b;
      """

      assert {:error, "PL/SQL block not properly terminated with END;"} = SqlParser.parse(sql)
    end

    test "accepts complete function" do
      sql = """
      CREATE FUNCTION add_numbers (p_a NUMBER, p_b NUMBER)
      RETURN NUMBER
      IS
      BEGIN
        RETURN p_a + p_b;
      END;
      """

      assert {:create_function, %{name: "add_numbers"}} = SqlParser.parse(sql)
    end

    test "returns error for incomplete anonymous block" do
      sql = """
      BEGIN
        DBMS_OUTPUT.PUT_LINE('Hello');
      """

      assert {:error, "PL/SQL block not properly terminated with END;"} = SqlParser.parse(sql)
    end

    test "accepts complete anonymous block" do
      sql = """
      BEGIN
        DBMS_OUTPUT.PUT_LINE('Hello');
      END;
      """

      assert {:anonymous_block, _} = SqlParser.parse(sql)
    end

    test "returns error for incomplete DECLARE block" do
      sql = """
      DECLARE
        v_name VARCHAR2(100);
      BEGIN
        v_name := 'Test';
      """

      assert {:error, "PL/SQL block not properly terminated with END;"} = SqlParser.parse(sql)
    end

    test "accepts complete DECLARE block" do
      sql = """
      DECLARE
        v_name VARCHAR2(100);
      BEGIN
        v_name := 'Test';
      END;
      """

      assert {:anonymous_block, _} = SqlParser.parse(sql)
    end

    test "handles nested BEGIN/END properly" do
      sql = """
      CREATE PROCEDURE nested_proc
      IS
      BEGIN
        IF TRUE THEN
          BEGIN
            NULL;
          END;
        END IF;
      END;
      """

      assert {:create_procedure, _} = SqlParser.parse(sql)
    end
  end

  describe "tokenization" do
    test "tokenizes simple statement" do
      tokens = SqlParser.tokenize("SELECT * FROM users")
      assert tokens == ["SELECT", "*", "FROM", "users"]
    end

    test "preserves string literals" do
      tokens = SqlParser.tokenize("SELECT * FROM users WHERE name = 'John Doe'")
      assert {:string, "John Doe"} in tokens
    end

    test "handles parentheses" do
      tokens = SqlParser.tokenize("INSERT INTO users (id, name) VALUES (1, 'test')")
      assert "(" in tokens
      assert ")" in tokens
    end

    test "handles comparison operators" do
      tokens = SqlParser.tokenize("SELECT * FROM users WHERE age >= 18 AND status <> 'inactive'")
      assert ">=" in tokens
      assert "<>" in tokens
    end
  end
end
