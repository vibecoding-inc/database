defmodule VibeDb.PlsqlInterpreterTest do
  use ExUnit.Case

  alias VibeDb.PlsqlInterpreter

  setup do
    {:ok, db} = VibeDb.start_link()
    {:ok, db: db}
  end

  describe "execute/2 - basic blocks" do
    test "executes empty block", %{db: db} do
      {:ok, storage} = get_storage(db)
      result = PlsqlInterpreter.execute(storage, "BEGIN NULL; END;")
      assert {:ok, %{output: [], return_value: nil}} = result
    end

    test "executes block with variable assignment", %{db: db} do
      {:ok, storage} = get_storage(db)

      body = """
      DECLARE
        v_name VARCHAR2(100) := 'Hello';
      BEGIN
        DBMS_OUTPUT.PUT_LINE(v_name);
      END;
      """

      result = PlsqlInterpreter.execute(storage, body)
      assert {:ok, %{output: ["Hello"]}} = result
    end

    test "executes block with arithmetic", %{db: db} do
      {:ok, storage} = get_storage(db)

      body = """
      DECLARE
        v_num NUMBER := 10;
        v_result NUMBER;
      BEGIN
        v_result := v_num + 5;
        DBMS_OUTPUT.PUT_LINE(v_result);
      END;
      """

      result = PlsqlInterpreter.execute(storage, body)
      assert {:ok, %{output: ["15"]}} = result
    end

    test "executes block with string concatenation", %{db: db} do
      {:ok, storage} = get_storage(db)

      body = """
      DECLARE
        v_first VARCHAR2(50) := 'Hello';
        v_last VARCHAR2(50) := 'World';
      BEGIN
        DBMS_OUTPUT.PUT_LINE(v_first || ' ' || v_last);
      END;
      """

      result = PlsqlInterpreter.execute(storage, body)
      assert {:ok, %{output: ["Hello World"]}} = result
    end
  end

  describe "execute/2 - control flow" do
    test "executes IF/THEN/ELSE", %{db: db} do
      {:ok, storage} = get_storage(db)

      body = """
      DECLARE
        v_num NUMBER := 10;
      BEGIN
        IF v_num > 5 THEN
          DBMS_OUTPUT.PUT_LINE('Greater');
        ELSE
          DBMS_OUTPUT.PUT_LINE('Less or equal');
        END IF;
      END;
      """

      result = PlsqlInterpreter.execute(storage, body)
      assert {:ok, %{output: ["Greater"]}} = result
    end

    test "executes FOR loop", %{db: db} do
      {:ok, storage} = get_storage(db)

      body = """
      DECLARE
        v_total NUMBER := 0;
      BEGIN
        FOR i IN 1..3 LOOP
          v_total := v_total + i;
        END LOOP;
        DBMS_OUTPUT.PUT_LINE(v_total);
      END;
      """

      result = PlsqlInterpreter.execute(storage, body)
      assert {:ok, %{output: ["6"]}} = result
    end

    test "executes WHILE loop", %{db: db} do
      {:ok, storage} = get_storage(db)

      body = """
      DECLARE
        v_counter NUMBER := 1;
        v_total NUMBER := 0;
      BEGIN
        WHILE v_counter <= 3 LOOP
          v_total := v_total + v_counter;
          v_counter := v_counter + 1;
        END LOOP;
        DBMS_OUTPUT.PUT_LINE(v_total);
      END;
      """

      result = PlsqlInterpreter.execute(storage, body)
      assert {:ok, %{output: ["6"]}} = result
    end
  end

  describe "execute/2 - functions" do
    test "executes built-in UPPER function", %{db: db} do
      {:ok, storage} = get_storage(db)

      body = """
      DECLARE
        v_result VARCHAR2(100);
      BEGIN
        v_result := UPPER('hello');
        DBMS_OUTPUT.PUT_LINE(v_result);
      END;
      """

      result = PlsqlInterpreter.execute(storage, body)
      assert {:ok, %{output: ["HELLO"]}} = result
    end

    test "executes built-in LOWER function", %{db: db} do
      {:ok, storage} = get_storage(db)

      body = """
      DECLARE
        v_result VARCHAR2(100);
      BEGIN
        v_result := LOWER('HELLO');
        DBMS_OUTPUT.PUT_LINE(v_result);
      END;
      """

      result = PlsqlInterpreter.execute(storage, body)
      assert {:ok, %{output: ["hello"]}} = result
    end

    test "executes built-in LENGTH function", %{db: db} do
      {:ok, storage} = get_storage(db)

      body = """
      DECLARE
        v_result NUMBER;
      BEGIN
        v_result := LENGTH('Hello');
        DBMS_OUTPUT.PUT_LINE(v_result);
      END;
      """

      result = PlsqlInterpreter.execute(storage, body)
      assert {:ok, %{output: ["5"]}} = result
    end

    test "executes NVL function", %{db: db} do
      {:ok, storage} = get_storage(db)

      body = """
      DECLARE
        v_null VARCHAR2(100);
        v_result VARCHAR2(100);
      BEGIN
        v_result := NVL(v_null, 'default');
        DBMS_OUTPUT.PUT_LINE(v_result);
      END;
      """

      result = PlsqlInterpreter.execute(storage, body)
      assert {:ok, %{output: ["default"]}} = result
    end
  end

  describe "execute/2 - RETURN statement" do
    test "executes RETURN with value", %{db: db} do
      {:ok, storage} = get_storage(db)

      body = """
      BEGIN
        RETURN 42;
      END;
      """

      result = PlsqlInterpreter.execute(storage, body)
      assert {:ok, %{return_value: 42}} = result
    end

    test "executes RETURN with expression", %{db: db} do
      {:ok, storage} = get_storage(db)

      body = """
      DECLARE
        v_num NUMBER := 10;
      BEGIN
        RETURN v_num + 5;
      END;
      """

      result = PlsqlInterpreter.execute(storage, body)
      assert {:ok, %{return_value: 15}} = result
    end
  end

  describe "execute_procedure/3" do
    test "executes stored procedure", %{db: db} do
      # Create a procedure
      VibeDb.execute(db, """
        CREATE PROCEDURE say_hello (p_name IN VARCHAR2)
        IS
        BEGIN
          DBMS_OUTPUT.PUT_LINE('Hello ' || p_name);
        END;
      """)

      {:ok, storage} = get_storage(db)
      result = PlsqlInterpreter.execute_procedure(storage, "SAY_HELLO", ["World"])

      assert {:ok, %{output: output}} = result
      assert "Hello World" in output
    end

    test "returns error for non-existent procedure", %{db: db} do
      {:ok, storage} = get_storage(db)
      result = PlsqlInterpreter.execute_procedure(storage, "NONEXISTENT", [])
      assert {:error, _} = result
    end
  end

  describe "execute_function/3" do
    test "executes stored function", %{db: db} do
      # Create a function
      VibeDb.execute(db, """
        CREATE FUNCTION add_numbers (p_a NUMBER, p_b NUMBER)
        RETURN NUMBER
        IS
        BEGIN
          RETURN p_a + p_b;
        END;
      """)

      {:ok, storage} = get_storage(db)
      result = PlsqlInterpreter.execute_function(storage, "ADD_NUMBERS", [5, 3])

      assert {:ok, 8} = result
    end

    test "executes string function", %{db: db} do
      # Create a function that returns a string
      VibeDb.execute(db, """
        CREATE FUNCTION get_greeting (p_name VARCHAR2)
        RETURN VARCHAR2
        IS
        BEGIN
          RETURN 'Hello ' || p_name;
        END;
      """)

      {:ok, storage} = get_storage(db)
      result = PlsqlInterpreter.execute_function(storage, "GET_GREETING", ["World"])

      assert {:ok, "Hello World"} = result
    end

    test "returns error for non-existent function", %{db: db} do
      {:ok, storage} = get_storage(db)
      result = PlsqlInterpreter.execute_function(storage, "NONEXISTENT", [])
      assert {:error, _} = result
    end
  end

  describe "CALL statement integration" do
    test "CALL executes procedure", %{db: db} do
      # Create a simple procedure
      VibeDb.execute(db, """
        CREATE PROCEDURE greet_user (p_name IN VARCHAR2)
        IS
        BEGIN
          DBMS_OUTPUT.PUT_LINE('Greetings, ' || p_name);
        END;
      """)

      result = VibeDb.execute(db, "CALL greet_user('Alice')")

      assert {:ok, %{message: message}} = result
      assert message =~ "GREET_USER"
    end

    test "EXEC executes procedure", %{db: db} do
      VibeDb.execute(db, """
        CREATE PROCEDURE simple_proc
        IS
        BEGIN
          NULL;
        END;
      """)

      result = VibeDb.execute(db, "EXEC simple_proc")

      assert {:ok, %{message: message}} = result
      assert message =~ "SIMPLE_PROC"
    end
  end

  describe "anonymous block execution" do
    test "executes BEGIN/END block", %{db: db} do
      result =
        VibeDb.execute(db, """
          BEGIN
            NULL;
          END;
        """)

      assert {:ok, %{message: "PL/SQL block executed"}} = result
    end

    test "executes DECLARE block", %{db: db} do
      result =
        VibeDb.execute(db, """
          DECLARE
            v_test NUMBER := 1;
          BEGIN
            NULL;
          END;
        """)

      assert {:ok, %{message: "PL/SQL block executed"}} = result
    end
  end

  describe "SELECT INTO statement" do
    test "executes SELECT INTO with single row", %{db: db} do
      # Create a table with data
      VibeDb.execute(db, "CREATE TABLE test_select_into (id NUMBER, name VARCHAR2(100))")
      VibeDb.execute(db, "INSERT INTO test_select_into VALUES (1, 'Alice')")

      {:ok, storage} = get_storage(db)

      body = """
      DECLARE
        v_name VARCHAR2(100);
      BEGIN
        SELECT name INTO v_name FROM test_select_into WHERE id = 1;
        DBMS_OUTPUT.PUT_LINE(v_name);
      END;
      """

      result = PlsqlInterpreter.execute(storage, body)
      assert {:ok, %{output: ["Alice"]}} = result
    end
  end

  describe "DML statements in PL/SQL" do
    test "executes INSERT statement", %{db: db} do
      VibeDb.execute(db, "CREATE TABLE test_dml (id NUMBER, name VARCHAR2(100))")

      {:ok, storage} = get_storage(db)

      body = """
      BEGIN
        INSERT INTO test_dml VALUES (1, 'Test');
      END;
      """

      result = PlsqlInterpreter.execute(storage, body)
      assert {:ok, _} = result

      # Verify the insert worked
      {:ok, rows} = VibeDb.execute(db, "SELECT * FROM test_dml")
      assert length(rows) == 1
    end

    test "executes UPDATE statement", %{db: db} do
      VibeDb.execute(db, "CREATE TABLE test_update (id NUMBER, name VARCHAR2(100))")
      VibeDb.execute(db, "INSERT INTO test_update VALUES (1, 'Original')")

      {:ok, storage} = get_storage(db)

      body = """
      BEGIN
        UPDATE test_update SET name = 'Updated' WHERE id = 1;
      END;
      """

      result = PlsqlInterpreter.execute(storage, body)
      assert {:ok, _} = result

      # Verify the update worked
      {:ok, [row]} = VibeDb.execute(db, "SELECT * FROM test_update WHERE id = 1")
      assert row["name"] == "Updated"
    end

    test "executes DELETE statement", %{db: db} do
      VibeDb.execute(db, "CREATE TABLE test_delete (id NUMBER)")
      VibeDb.execute(db, "INSERT INTO test_delete VALUES (1)")
      VibeDb.execute(db, "INSERT INTO test_delete VALUES (2)")

      {:ok, storage} = get_storage(db)

      body = """
      BEGIN
        DELETE FROM test_delete WHERE id = 1;
      END;
      """

      result = PlsqlInterpreter.execute(storage, body)
      assert {:ok, _} = result

      # Verify the delete worked
      {:ok, rows} = VibeDb.execute(db, "SELECT * FROM test_delete")
      assert length(rows) == 1
    end
  end

  # Helper function to get the storage process from the db
  # Note: Using :sys.get_state is acceptable in tests for accessing internal state.
  # In production code, consider adding a proper API function to VibeDb if needed.
  defp get_storage(db) do
    state = :sys.get_state(db)
    {:ok, state.storage}
  end
end
