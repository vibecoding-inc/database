defmodule OracleDb.XmlStorageTest do
  use ExUnit.Case

  @test_filename "/tmp/test_database.xml"

  setup do
    # Clean up test file if it exists
    File.rm(@test_filename)
    {:ok, db} = OracleDb.start_link()
    on_exit(fn -> File.rm(@test_filename) end)
    {:ok, db: db}
  end

  describe "save and load" do
    test "saves and loads an empty database", %{db: db} do
      assert :ok = OracleDb.save(db, @test_filename)
      assert File.exists?(@test_filename)
      assert :ok = OracleDb.load(db, @test_filename)
    end

    test "saves and loads a database with tables and data", %{db: db} do
      # Create table and insert data
      OracleDb.execute(db, "CREATE TABLE users (id NUMBER, name VARCHAR2(100), active NUMBER)")
      OracleDb.execute(db, "INSERT INTO users VALUES (1, 'Alice', 1)")
      OracleDb.execute(db, "INSERT INTO users VALUES (2, 'Bob', 0)")

      # Save database
      assert :ok = OracleDb.save(db, @test_filename)

      # Reset database
      OracleDb.reset(db)
      assert [] = OracleDb.list_tables(db)

      # Load database
      assert :ok = OracleDb.load(db, @test_filename)

      # Verify data
      assert ["USERS"] = OracleDb.list_tables(db)
      {:ok, rows} = OracleDb.execute(db, "SELECT * FROM users ORDER BY id")
      assert length(rows) == 2
      assert hd(rows)["name"] == "Alice"
    end

    test "saves and loads sequences", %{db: db} do
      # Create sequence and use it
      OracleDb.execute(db, "CREATE SEQUENCE user_seq START WITH 100 INCREMENT BY 10")
      {:ok, _} = OracleDb.nextval(db, "user_seq")
      {:ok, _} = OracleDb.nextval(db, "user_seq")

      # Save database
      assert :ok = OracleDb.save(db, @test_filename)

      # Reset and load
      OracleDb.reset(db)
      assert :ok = OracleDb.load(db, @test_filename)

      # Verify sequence state
      {:ok, val} = OracleDb.currval(db, "USER_SEQ")
      assert val == 110
    end

    test "saves and loads indexes", %{db: db} do
      OracleDb.execute(db, "CREATE TABLE products (id NUMBER, name VARCHAR2(100))")
      OracleDb.execute(db, "CREATE INDEX idx_products ON products (name)")

      assert :ok = OracleDb.save(db, @test_filename)
      OracleDb.reset(db)
      assert :ok = OracleDb.load(db, @test_filename)

      # Table should be loadable
      assert ["PRODUCTS"] = OracleDb.list_tables(db)
    end

    test "saves and loads types", %{db: db} do
      OracleDb.execute(db, "CREATE TYPE address_type AS OBJECT (street VARCHAR2(100), city VARCHAR2(50))")

      assert :ok = OracleDb.save(db, @test_filename)
      OracleDb.reset(db)
      assert :ok = OracleDb.load(db, @test_filename)

      assert ["ADDRESS_TYPE"] = OracleDb.list_types(db)
    end

    test "saves and loads views", %{db: db} do
      OracleDb.execute(db, "CREATE TABLE base_table (id NUMBER, name VARCHAR2(100))")
      OracleDb.execute(db, "CREATE VIEW my_view AS SELECT id, name FROM base_table")

      assert :ok = OracleDb.save(db, @test_filename)
      OracleDb.reset(db)
      assert :ok = OracleDb.load(db, @test_filename)

      assert ["MY_VIEW"] = OracleDb.list_views(db)
    end

    test "saves and loads stored procedures", %{db: db} do
      OracleDb.execute(db, """
        CREATE PROCEDURE test_proc (p_name IN VARCHAR2)
        IS
        BEGIN
          NULL;
        END;
      """)

      assert :ok = OracleDb.save(db, @test_filename)
      OracleDb.reset(db)
      assert :ok = OracleDb.load(db, @test_filename)

      assert ["TEST_PROC"] = OracleDb.list_procedures(db)
    end

    test "saves and loads stored functions", %{db: db} do
      OracleDb.execute(db, """
        CREATE FUNCTION test_func RETURN NUMBER
        IS
        BEGIN
          RETURN 42;
        END;
      """)

      assert :ok = OracleDb.save(db, @test_filename)
      OracleDb.reset(db)
      assert :ok = OracleDb.load(db, @test_filename)

      assert ["TEST_FUNC"] = OracleDb.list_functions(db)
    end

    test "saves and loads packages", %{db: db} do
      OracleDb.execute(db, """
        CREATE PACKAGE test_pkg
        IS
          PROCEDURE proc1;
        END;
      """)

      assert :ok = OracleDb.save(db, @test_filename)
      OracleDb.reset(db)
      assert :ok = OracleDb.load(db, @test_filename)

      assert ["TEST_PKG"] = OracleDb.list_packages(db)
    end

    test "saves and loads triggers", %{db: db} do
      OracleDb.execute(db, "CREATE TABLE trigger_test (id NUMBER)")
      OracleDb.execute(db, """
        CREATE TRIGGER test_trigger
        BEFORE INSERT ON trigger_test
        FOR EACH ROW
        BEGIN
          NULL;
        END;
      """)

      assert :ok = OracleDb.save(db, @test_filename)
      OracleDb.reset(db)
      assert :ok = OracleDb.load(db, @test_filename)

      assert ["TEST_TRIGGER"] = OracleDb.list_triggers(db)
    end

    test "preserves various data types", %{db: db} do
      OracleDb.execute(db, "CREATE TABLE datatypes (int_col NUMBER, str_col VARCHAR2(100))")
      OracleDb.execute(db, "INSERT INTO datatypes VALUES (42, 'hello')")
      OracleDb.execute(db, "INSERT INTO datatypes VALUES (100, 'world')")

      assert :ok = OracleDb.save(db, @test_filename)
      OracleDb.reset(db)
      assert :ok = OracleDb.load(db, @test_filename)

      {:ok, rows} = OracleDb.execute(db, "SELECT * FROM datatypes")
      assert length(rows) == 2
      
      # Check that both values are present
      int_values = Enum.map(rows, & &1["int_col"]) |> Enum.sort()
      str_values = Enum.map(rows, & &1["str_col"]) |> Enum.sort()
      
      assert int_values == [42, 100]
      assert str_values == ["hello", "world"]
    end

    test "handles special characters in strings", %{db: db} do
      OracleDb.execute(db, "CREATE TABLE special (text VARCHAR2(500))")
      OracleDb.execute(db, "INSERT INTO special VALUES ('Hello <world> & \"friends\"')")

      assert :ok = OracleDb.save(db, @test_filename)
      OracleDb.reset(db)
      assert :ok = OracleDb.load(db, @test_filename)

      {:ok, rows} = OracleDb.execute(db, "SELECT * FROM special")
      assert hd(rows)["text"] == "Hello <world> & \"friends\""
    end
  end

  describe "error handling" do
    test "returns error when loading non-existent file", %{db: db} do
      result = OracleDb.load(db, "/nonexistent/path/file.xml")
      assert {:error, _} = result
    end
  end

  describe "status" do
    test "returns database status", %{db: db} do
      OracleDb.execute(db, "CREATE TABLE t1 (id NUMBER)")
      OracleDb.execute(db, "CREATE TABLE t2 (id NUMBER)")
      OracleDb.execute(db, "INSERT INTO t1 VALUES (1)")
      OracleDb.execute(db, "INSERT INTO t1 VALUES (2)")
      OracleDb.execute(db, "INSERT INTO t2 VALUES (1)")
      OracleDb.execute(db, "CREATE SEQUENCE seq1 START WITH 1")

      status = OracleDb.status(db)

      assert status.tables == 2
      assert status.total_rows == 3
      assert status.sequences == 1
    end
  end
end
