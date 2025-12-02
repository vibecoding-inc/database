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

  describe "is_plsql_block?/1" do
    test "returns true for CREATE PROCEDURE" do
      assert SqlParser.is_plsql_block?("CREATE PROCEDURE test IS BEGIN NULL; END;")
    end

    test "returns true for CREATE OR REPLACE PROCEDURE" do
      assert SqlParser.is_plsql_block?("CREATE OR REPLACE PROCEDURE test IS BEGIN NULL; END;")
    end

    test "returns true for CREATE FUNCTION" do
      assert SqlParser.is_plsql_block?(
               "CREATE FUNCTION test RETURN NUMBER IS BEGIN RETURN 1; END;"
             )
    end

    test "returns true for BEGIN" do
      assert SqlParser.is_plsql_block?("BEGIN NULL; END;")
    end

    test "returns true for DECLARE" do
      assert SqlParser.is_plsql_block?("DECLARE v_test NUMBER; BEGIN NULL; END;")
    end

    test "returns false for SELECT" do
      refute SqlParser.is_plsql_block?("SELECT * FROM users")
    end

    test "returns false for INSERT" do
      refute SqlParser.is_plsql_block?("INSERT INTO users VALUES (1, 'test')")
    end

    test "returns false for CREATE TABLE" do
      refute SqlParser.is_plsql_block?("CREATE TABLE users (id NUMBER)")
    end
  end

  describe "plsql_block_complete?/1" do
    test "returns true for complete procedure with END;" do
      assert SqlParser.plsql_block_complete?("""
               CREATE PROCEDURE test IS
               BEGIN
                 NULL;
               END;
             """)
    end

    test "returns true for complete procedure with END name;" do
      assert SqlParser.plsql_block_complete?("""
               CREATE PROCEDURE test IS
               BEGIN
                 NULL;
               END test;
             """)
    end

    test "returns false for incomplete procedure (no END)" do
      refute SqlParser.plsql_block_complete?("""
               CREATE PROCEDURE test IS
               BEGIN
                 NULL;
             """)
    end

    test "returns false when BEGIN/END unbalanced" do
      refute SqlParser.plsql_block_complete?("""
               CREATE PROCEDURE test IS
               BEGIN
                 BEGIN
                   NULL;
                 END;
             """)
    end

    test "returns true for nested BEGIN/END when balanced" do
      assert SqlParser.plsql_block_complete?("""
               CREATE PROCEDURE test IS
               BEGIN
                 BEGIN
                   NULL;
                 END;
               END;
             """)
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

  describe "PL/SQL anonymous blocks" do
    test "parses simple BEGIN/END block" do
      sql = "BEGIN END;"
      assert {:anonymous_block, %{body: _}} = SqlParser.parse(sql)
    end

    test "parses BEGIN/END block with newlines" do
      sql = "BEGIN\nEND;"
      assert {:anonymous_block, %{body: _}} = SqlParser.parse(sql)
    end

    test "parses BEGIN/END block with NULL statement" do
      sql = "BEGIN\n  NULL;\nEND;"
      assert {:anonymous_block, %{body: body}} = SqlParser.parse(sql)
      assert body =~ "NULL"
    end

    test "parses BEGIN/END block with DBMS_OUTPUT" do
      sql = """
      BEGIN
        DBMS_OUTPUT.PUT_LINE('Hello World');
      END;
      """
      assert {:anonymous_block, %{body: body}} = SqlParser.parse(sql)
      assert body =~ "DBMS_OUTPUT"
    end

    test "parses DECLARE block with variable" do
      sql = """
      DECLARE
        v_count NUMBER := 0;
      BEGIN
        v_count := v_count + 1;
      END;
      """
      assert {:anonymous_block, _} = SqlParser.parse(sql)
    end

    test "parses DECLARE block with multiple variables" do
      sql = """
      DECLARE
        v_name VARCHAR2(100) := 'Test';
        v_age NUMBER;
        v_active BOOLEAN := TRUE;
      BEGIN
        NULL;
      END;
      """
      assert {:anonymous_block, _} = SqlParser.parse(sql)
    end

    test "parses block with nested BEGIN/END" do
      sql = """
      BEGIN
        BEGIN
          NULL;
        END;
      END;
      """
      assert {:anonymous_block, _} = SqlParser.parse(sql)
    end

    test "parses block with multiple nested BEGIN/END" do
      sql = """
      BEGIN
        BEGIN
          NULL;
        END;
        BEGIN
          NULL;
        END;
      END;
      """
      assert {:anonymous_block, _} = SqlParser.parse(sql)
    end

    test "parses block with deeply nested BEGIN/END" do
      sql = """
      BEGIN
        BEGIN
          BEGIN
            NULL;
          END;
        END;
      END;
      """
      assert {:anonymous_block, _} = SqlParser.parse(sql)
    end
  end

  describe "PL/SQL procedures - parsing" do
    test "parses simple procedure without parameters" do
      sql = """
      CREATE PROCEDURE simple_proc
      IS
      BEGIN
        NULL;
      END;
      """
      {:create_procedure, info} = SqlParser.parse(sql)
      assert info.name == "simple_proc"
      assert info.parameters == []
      assert info.replace == false
    end

    test "parses procedure with IN parameter" do
      sql = """
      CREATE PROCEDURE proc_with_in (p_name IN VARCHAR2)
      IS
      BEGIN
        NULL;
      END;
      """
      {:create_procedure, info} = SqlParser.parse(sql)
      assert info.name == "proc_with_in"
      assert length(info.parameters) > 0
    end

    test "parses procedure with OUT parameter" do
      sql = """
      CREATE PROCEDURE proc_with_out (p_result OUT NUMBER)
      IS
      BEGIN
        p_result := 42;
      END;
      """
      {:create_procedure, info} = SqlParser.parse(sql)
      assert info.name == "proc_with_out"
    end

    test "parses procedure with IN OUT parameter" do
      sql = """
      CREATE PROCEDURE proc_with_inout (p_value IN OUT NUMBER)
      IS
      BEGIN
        p_value := p_value + 1;
      END;
      """
      {:create_procedure, info} = SqlParser.parse(sql)
      assert info.name == "proc_with_inout"
    end

    test "parses procedure with multiple parameters" do
      sql = """
      CREATE PROCEDURE multi_param_proc (
        p_id IN NUMBER,
        p_name IN VARCHAR2,
        p_result OUT NUMBER
      )
      IS
      BEGIN
        NULL;
      END;
      """
      {:create_procedure, info} = SqlParser.parse(sql)
      assert info.name == "multi_param_proc"
    end

    test "parses CREATE OR REPLACE PROCEDURE" do
      sql = """
      CREATE OR REPLACE PROCEDURE replace_proc
      IS
      BEGIN
        NULL;
      END;
      """
      {:create_procedure, info} = SqlParser.parse(sql)
      assert info.name == "replace_proc"
      assert info.replace == true
    end

    test "parses procedure with AS instead of IS" do
      sql = """
      CREATE PROCEDURE as_proc
      AS
      BEGIN
        NULL;
      END;
      """
      {:create_procedure, info} = SqlParser.parse(sql)
      assert info.name == "as_proc"
    end

    test "parses procedure with local variable declarations" do
      sql = """
      CREATE PROCEDURE local_vars_proc
      IS
        v_count NUMBER := 0;
        v_name VARCHAR2(100);
      BEGIN
        v_name := 'Test';
        v_count := v_count + 1;
      END;
      """
      {:create_procedure, info} = SqlParser.parse(sql)
      assert info.name == "local_vars_proc"
    end

    test "parses procedure with END proc_name;" do
      sql = """
      CREATE PROCEDURE named_end_proc
      IS
      BEGIN
        NULL;
      END named_end_proc;
      """
      {:create_procedure, info} = SqlParser.parse(sql)
      assert info.name == "named_end_proc"
    end
  end

  describe "PL/SQL functions - parsing" do
    test "parses simple function" do
      sql = """
      CREATE FUNCTION simple_func
      RETURN NUMBER
      IS
      BEGIN
        RETURN 42;
      END;
      """
      {:create_function, info} = SqlParser.parse(sql)
      assert info.name == "simple_func"
      assert info.return_type == "NUMBER"
      assert info.replace == false
    end

    test "parses function with parameters" do
      sql = """
      CREATE FUNCTION add_func (p_a NUMBER, p_b NUMBER)
      RETURN NUMBER
      IS
      BEGIN
        RETURN p_a + p_b;
      END;
      """
      {:create_function, info} = SqlParser.parse(sql)
      assert info.name == "add_func"
      assert info.return_type == "NUMBER"
    end

    test "parses function returning VARCHAR2" do
      sql = """
      CREATE FUNCTION string_func (p_name VARCHAR2)
      RETURN VARCHAR2
      IS
      BEGIN
        RETURN 'Hello ' || p_name;
      END;
      """
      {:create_function, info} = SqlParser.parse(sql)
      assert info.name == "string_func"
      assert info.return_type == "VARCHAR2"
    end

    test "parses CREATE OR REPLACE FUNCTION" do
      sql = """
      CREATE OR REPLACE FUNCTION replace_func
      RETURN NUMBER
      IS
      BEGIN
        RETURN 0;
      END;
      """
      {:create_function, info} = SqlParser.parse(sql)
      assert info.name == "replace_func"
      assert info.replace == true
    end

    test "parses function with local variables" do
      sql = """
      CREATE FUNCTION compute_func (p_x NUMBER)
      RETURN NUMBER
      IS
        v_result NUMBER;
      BEGIN
        v_result := p_x * 2;
        RETURN v_result;
      END;
      """
      {:create_function, info} = SqlParser.parse(sql)
      assert info.name == "compute_func"
    end
  end

  describe "PL/SQL triggers - parsing" do
    test "parses BEFORE INSERT trigger" do
      sql = """
      CREATE TRIGGER before_insert_trig
      BEFORE INSERT ON test_table
      FOR EACH ROW
      BEGIN
        NULL;
      END;
      """
      {:create_trigger, info} = SqlParser.parse(sql)
      assert info.name == "before_insert_trig"
      assert info.timing == :before
      assert info.table == "test_table"
      assert info.for_each == :row
    end

    test "parses AFTER UPDATE trigger" do
      sql = """
      CREATE TRIGGER after_update_trig
      AFTER UPDATE ON test_table
      FOR EACH ROW
      BEGIN
        NULL;
      END;
      """
      {:create_trigger, info} = SqlParser.parse(sql)
      assert info.name == "after_update_trig"
      assert info.timing == :after
    end

    test "parses INSTEAD OF trigger" do
      sql = """
      CREATE TRIGGER instead_of_trig
      INSTEAD OF INSERT ON test_view
      FOR EACH ROW
      BEGIN
        NULL;
      END;
      """
      {:create_trigger, info} = SqlParser.parse(sql)
      assert info.name == "instead_of_trig"
      assert info.timing == :instead_of
    end

    test "parses trigger with multiple events" do
      sql = """
      CREATE TRIGGER multi_event_trig
      BEFORE INSERT OR UPDATE OR DELETE ON test_table
      FOR EACH ROW
      BEGIN
        NULL;
      END;
      """
      {:create_trigger, info} = SqlParser.parse(sql)
      assert info.name == "multi_event_trig"
      assert length(info.events) == 3
    end

    test "parses CREATE OR REPLACE TRIGGER" do
      sql = """
      CREATE OR REPLACE TRIGGER replace_trig
      BEFORE INSERT ON test_table
      FOR EACH ROW
      BEGIN
        NULL;
      END;
      """
      {:create_trigger, info} = SqlParser.parse(sql)
      assert info.replace == true
    end

    test "parses trigger with WHEN clause" do
      sql = """
      CREATE TRIGGER when_trig
      BEFORE INSERT ON test_table
      FOR EACH ROW
      WHEN (NEW.id > 0)
      BEGIN
        NULL;
      END;
      """
      {:create_trigger, info} = SqlParser.parse(sql)
      assert info.when_clause != nil
    end
  end

  describe "PL/SQL packages - parsing" do
    test "parses package specification" do
      sql = """
      CREATE PACKAGE test_pkg
      IS
        PROCEDURE proc1;
        FUNCTION func1 RETURN NUMBER;
      END;
      """
      {:create_package, info} = SqlParser.parse(sql)
      assert info.name == "test_pkg"
      assert info.replace == false
    end

    test "parses CREATE OR REPLACE PACKAGE" do
      sql = """
      CREATE OR REPLACE PACKAGE replace_pkg
      IS
        PROCEDURE proc1;
      END;
      """
      {:create_package, info} = SqlParser.parse(sql)
      assert info.replace == true
    end

    test "parses package body" do
      sql = """
      CREATE PACKAGE BODY test_pkg
      IS
        PROCEDURE proc1
        IS
        BEGIN
          NULL;
        END;
      END;
      """
      {:create_package_body, info} = SqlParser.parse(sql)
      assert info.name == "test_pkg"
    end
  end

  describe "PL/SQL block completeness detection" do
    test "incomplete: BEGIN without END" do
      assert not SqlParser.plsql_block_complete?("BEGIN")
    end

    test "incomplete: BEGIN NULL; without END" do
      assert not SqlParser.plsql_block_complete?("BEGIN NULL;")
    end

    test "complete: BEGIN END;" do
      assert SqlParser.plsql_block_complete?("BEGIN END;")
    end

    test "complete: BEGIN with newline END;" do
      assert SqlParser.plsql_block_complete?("BEGIN\nEND;")
    end

    test "incomplete: nested BEGIN without matching END" do
      assert not SqlParser.plsql_block_complete?("BEGIN BEGIN END; ")
    end

    test "complete: nested BEGIN with matching END" do
      assert SqlParser.plsql_block_complete?("BEGIN BEGIN END; END;")
    end

    test "incomplete: DECLARE without END" do
      assert not SqlParser.plsql_block_complete?("DECLARE v NUMBER; BEGIN")
    end

    test "complete: DECLARE with BEGIN and END" do
      assert SqlParser.plsql_block_complete?("DECLARE v NUMBER; BEGIN END;")
    end

    test "incomplete: CREATE PROCEDURE without END" do
      assert not SqlParser.plsql_block_complete?("CREATE PROCEDURE p IS BEGIN")
    end

    test "complete: CREATE PROCEDURE with END" do
      assert SqlParser.plsql_block_complete?("CREATE PROCEDURE p IS BEGIN END;")
    end

    test "complete: END with procedure name" do
      assert SqlParser.plsql_block_complete?("CREATE PROCEDURE p IS BEGIN END p;")
    end
  end

  describe "PL/SQL is_plsql_block? detection" do
    test "BEGIN is PL/SQL block" do
      assert SqlParser.is_plsql_block?("BEGIN NULL; END;")
    end

    test "DECLARE is PL/SQL block" do
      assert SqlParser.is_plsql_block?("DECLARE v NUMBER; BEGIN END;")
    end

    test "CREATE PROCEDURE is PL/SQL block" do
      assert SqlParser.is_plsql_block?("CREATE PROCEDURE p IS BEGIN END;")
    end

    test "CREATE OR REPLACE PROCEDURE is PL/SQL block" do
      assert SqlParser.is_plsql_block?("CREATE OR REPLACE PROCEDURE p IS BEGIN END;")
    end

    test "CREATE FUNCTION is PL/SQL block" do
      assert SqlParser.is_plsql_block?("CREATE FUNCTION f RETURN NUMBER IS BEGIN RETURN 1; END;")
    end

    test "CREATE TRIGGER is PL/SQL block" do
      assert SqlParser.is_plsql_block?("CREATE TRIGGER t BEFORE INSERT ON tbl BEGIN END;")
    end

    test "CREATE PACKAGE is PL/SQL block" do
      assert SqlParser.is_plsql_block?("CREATE PACKAGE pkg IS END;")
    end

    test "SELECT is not PL/SQL block" do
      assert not SqlParser.is_plsql_block?("SELECT * FROM dual")
    end

    test "INSERT is not PL/SQL block" do
      assert not SqlParser.is_plsql_block?("INSERT INTO t VALUES (1)")
    end

    test "UPDATE is not PL/SQL block" do
      assert not SqlParser.is_plsql_block?("UPDATE t SET x = 1")
    end

    test "DELETE is not PL/SQL block" do
      assert not SqlParser.is_plsql_block?("DELETE FROM t")
    end

    test "CREATE TABLE is not PL/SQL block" do
      assert not SqlParser.is_plsql_block?("CREATE TABLE t (id NUMBER)")
    end

    test "CREATE VIEW is not PL/SQL block" do
      assert not SqlParser.is_plsql_block?("CREATE VIEW v AS SELECT * FROM t")
    end
  end

  describe "PL/SQL error messages" do
    test "incomplete procedure gives clear error" do
      sql = "CREATE PROCEDURE p IS BEGIN"
      {:error, msg} = SqlParser.parse(sql)
      assert msg =~ "END"
    end

    test "incomplete function gives clear error" do
      sql = "CREATE FUNCTION f RETURN NUMBER IS BEGIN"
      {:error, msg} = SqlParser.parse(sql)
      assert msg =~ "END"
    end

    test "incomplete anonymous block gives clear error" do
      sql = "BEGIN NULL;"
      {:error, msg} = SqlParser.parse(sql)
      assert msg =~ "END"
    end

    test "unbalanced nested blocks gives clear error" do
      sql = "BEGIN BEGIN END;"
      {:error, msg} = SqlParser.parse(sql)
      assert msg =~ "END" or msg =~ "Unbalanced"
    end
  end

  describe "PL/SQL with string literals" do
    test "string literal does not confuse BEGIN detection" do
      sql = """
      BEGIN
        DBMS_OUTPUT.PUT_LINE('BEGIN is just a string');
      END;
      """
      assert {:anonymous_block, _} = SqlParser.parse(sql)
    end

    test "string literal does not confuse END detection" do
      sql = """
      BEGIN
        DBMS_OUTPUT.PUT_LINE('This is not the END');
      END;
      """
      assert {:anonymous_block, _} = SqlParser.parse(sql)
    end

    test "multiple string literals handled correctly" do
      sql = """
      BEGIN
        DBMS_OUTPUT.PUT_LINE('First');
        DBMS_OUTPUT.PUT_LINE('Second');
        DBMS_OUTPUT.PUT_LINE('Third');
      END;
      """
      assert {:anonymous_block, _} = SqlParser.parse(sql)
    end
  end

  describe "JOIN parsing" do
    test "parses simple INNER JOIN with ON" do
      {:select, result} =
        SqlParser.parse("SELECT * FROM users INNER JOIN orders ON users.id = orders.user_id")

      assert result.table == "users"
      assert length(result.joins) == 1
      [join] = result.joins
      assert join.type == :inner
      assert elem(join.table, 0) == "orders"
      assert {:on, _} = join.condition
    end

    test "parses simple JOIN without INNER keyword" do
      {:select, result} =
        SqlParser.parse("SELECT * FROM users JOIN orders ON users.id = orders.user_id")

      assert result.table == "users"
      assert length(result.joins) == 1
      [join] = result.joins
      assert join.type == :inner
    end

    test "parses LEFT JOIN" do
      {:select, result} =
        SqlParser.parse("SELECT * FROM users LEFT JOIN orders ON users.id = orders.user_id")

      assert result.table == "users"
      assert length(result.joins) == 1
      [join] = result.joins
      assert join.type == {:outer, :left}
    end

    test "parses LEFT OUTER JOIN" do
      {:select, result} =
        SqlParser.parse("SELECT * FROM users LEFT OUTER JOIN orders ON users.id = orders.user_id")

      assert result.table == "users"
      assert length(result.joins) == 1
      [join] = result.joins
      assert join.type == {:outer, :left}
    end

    test "parses RIGHT JOIN" do
      {:select, result} =
        SqlParser.parse("SELECT * FROM users RIGHT JOIN orders ON users.id = orders.user_id")

      assert result.table == "users"
      assert length(result.joins) == 1
      [join] = result.joins
      assert join.type == {:outer, :right}
    end

    test "parses RIGHT OUTER JOIN" do
      {:select, result} =
        SqlParser.parse("SELECT * FROM users RIGHT OUTER JOIN orders ON users.id = orders.user_id")

      assert result.table == "users"
      assert length(result.joins) == 1
      [join] = result.joins
      assert join.type == {:outer, :right}
    end

    test "parses FULL JOIN" do
      {:select, result} =
        SqlParser.parse("SELECT * FROM users FULL JOIN orders ON users.id = orders.user_id")

      assert result.table == "users"
      assert length(result.joins) == 1
      [join] = result.joins
      assert join.type == {:outer, :full}
    end

    test "parses FULL OUTER JOIN" do
      {:select, result} =
        SqlParser.parse("SELECT * FROM users FULL OUTER JOIN orders ON users.id = orders.user_id")

      assert result.table == "users"
      assert length(result.joins) == 1
      [join] = result.joins
      assert join.type == {:outer, :full}
    end

    test "parses CROSS JOIN" do
      {:select, result} =
        SqlParser.parse("SELECT * FROM users CROSS JOIN orders")

      assert result.table == "users"
      assert length(result.joins) == 1
      [join] = result.joins
      assert join.type == :cross
      assert join.condition == nil
    end

    test "parses NATURAL JOIN" do
      {:select, result} =
        SqlParser.parse("SELECT * FROM users NATURAL JOIN orders")

      assert result.table == "users"
      assert length(result.joins) == 1
      [join] = result.joins
      assert join.type == :natural
      assert {:natural, nil} = join.condition
    end

    test "parses JOIN with USING clause" do
      {:select, result} =
        SqlParser.parse("SELECT * FROM users JOIN orders USING (user_id)")

      assert length(result.joins) == 1
      [join] = result.joins
      assert {:using, ["USER_ID"]} = join.condition
    end

    test "parses JOIN with USING clause with multiple columns" do
      {:select, result} =
        SqlParser.parse("SELECT * FROM users JOIN orders USING (user_id, date)")

      assert length(result.joins) == 1
      [join] = result.joins
      assert {:using, columns} = join.condition
      assert "USER_ID" in columns
      assert "DATE" in columns
    end

    test "parses multiple JOINs" do
      {:select, result} =
        SqlParser.parse("""
          SELECT *
          FROM users
          INNER JOIN orders ON users.id = orders.user_id
          LEFT JOIN products ON orders.product_id = products.id
        """)

      assert result.table == "users"
      assert length(result.joins) == 2

      [join1, join2] = result.joins
      assert join1.type == :inner
      assert elem(join1.table, 0) == "orders"

      assert join2.type == {:outer, :left}
      assert elem(join2.table, 0) == "products"
    end

    test "parses JOIN with table alias" do
      {:select, result} =
        SqlParser.parse("SELECT * FROM users u JOIN orders o ON u.id = o.user_id")

      assert result.table == "users"
      assert result.table_info == {"users", "u"}
      assert length(result.joins) == 1
      [join] = result.joins
      assert join.table == {"orders", "o"}
    end

    test "parses JOIN with AS table alias" do
      {:select, result} =
        SqlParser.parse("SELECT * FROM users AS u JOIN orders AS o ON u.id = o.user_id")

      assert result.table_info == {"users", "u"}
      [join] = result.joins
      assert join.table == {"orders", "o"}
    end

    test "parses JOIN with WHERE clause" do
      {:select, result} =
        SqlParser.parse("""
          SELECT *
          FROM users
          JOIN orders ON users.id = orders.user_id
          WHERE orders.status = 'active'
        """)

      assert length(result.joins) == 1
      assert result.where != nil
    end

    test "parses JOIN with ORDER BY" do
      {:select, result} =
        SqlParser.parse("""
          SELECT *
          FROM users
          JOIN orders ON users.id = orders.user_id
          ORDER BY users.name
        """)

      assert length(result.joins) == 1
      assert result.order_by != nil
    end

    test "parses comma-separated tables as implicit cross join" do
      {:select, result} =
        SqlParser.parse("SELECT * FROM users, orders")

      assert result.table == "users"
      assert length(result.joins) == 1
      [join] = result.joins
      assert join.type == :cross
    end

    test "parses JOIN with complex ON condition" do
      {:select, result} =
        SqlParser.parse("""
          SELECT *
          FROM users
          JOIN orders ON users.id = orders.user_id AND orders.status = 'active'
        """)

      [join] = result.joins
      {:on, condition} = join.condition
      assert {:and, _, _} = condition
    end
  end
end
