defmodule VibeDb.XmlStorageTest do
  use ExUnit.Case

  @test_filename "/tmp/test_database.xml"

  setup do
    # Clean up test file if it exists
    File.rm(@test_filename)
    {:ok, db} = VibeDb.start_link()
    on_exit(fn -> File.rm(@test_filename) end)
    {:ok, db: db}
  end

  describe "save and load" do
    test "saves and loads an empty database", %{db: db} do
      assert :ok = VibeDb.save(db, @test_filename)
      assert File.exists?(@test_filename)
      assert :ok = VibeDb.load(db, @test_filename)
    end

    test "saves and loads a database with tables and data", %{db: db} do
      # Create table and insert data
      VibeDb.execute(db, "CREATE TABLE users (id NUMBER, name VARCHAR2(100), active NUMBER)")
      VibeDb.execute(db, "INSERT INTO users VALUES (1, 'Alice', 1)")
      VibeDb.execute(db, "INSERT INTO users VALUES (2, 'Bob', 0)")

      # Save database
      assert :ok = VibeDb.save(db, @test_filename)

      # Reset database
      VibeDb.reset(db)
      assert [] = VibeDb.list_tables(db)

      # Load database
      assert :ok = VibeDb.load(db, @test_filename)

      # Verify data
      assert ["USERS"] = VibeDb.list_tables(db)
      {:ok, rows} = VibeDb.execute(db, "SELECT * FROM users ORDER BY id")
      assert length(rows) == 2
      assert hd(rows)["name"] == "Alice"
    end

    test "saves and loads sequences", %{db: db} do
      # Create sequence and use it
      VibeDb.execute(db, "CREATE SEQUENCE user_seq START WITH 100 INCREMENT BY 10")
      {:ok, _} = VibeDb.nextval(db, "user_seq")
      {:ok, _} = VibeDb.nextval(db, "user_seq")

      # Save database
      assert :ok = VibeDb.save(db, @test_filename)

      # Reset and load
      VibeDb.reset(db)
      assert :ok = VibeDb.load(db, @test_filename)

      # Verify sequence state
      {:ok, val} = VibeDb.currval(db, "USER_SEQ")
      assert val == 110
    end

    test "saves and loads indexes", %{db: db} do
      VibeDb.execute(db, "CREATE TABLE products (id NUMBER, name VARCHAR2(100))")
      VibeDb.execute(db, "CREATE INDEX idx_products ON products (name)")

      assert :ok = VibeDb.save(db, @test_filename)
      VibeDb.reset(db)
      assert :ok = VibeDb.load(db, @test_filename)

      # Table should be loadable
      assert ["PRODUCTS"] = VibeDb.list_tables(db)
    end

    test "saves and loads types", %{db: db} do
      VibeDb.execute(db, "CREATE TYPE address_type AS OBJECT (street VARCHAR2(100), city VARCHAR2(50))")

      assert :ok = VibeDb.save(db, @test_filename)
      VibeDb.reset(db)
      assert :ok = VibeDb.load(db, @test_filename)

      assert ["ADDRESS_TYPE"] = VibeDb.list_types(db)
    end

    test "saves and loads views", %{db: db} do
      VibeDb.execute(db, "CREATE TABLE base_table (id NUMBER, name VARCHAR2(100))")
      VibeDb.execute(db, "CREATE VIEW my_view AS SELECT id, name FROM base_table")

      assert :ok = VibeDb.save(db, @test_filename)
      VibeDb.reset(db)
      assert :ok = VibeDb.load(db, @test_filename)

      assert ["MY_VIEW"] = VibeDb.list_views(db)
    end

    test "saves and loads stored procedures", %{db: db} do
      VibeDb.execute(db, """
        CREATE PROCEDURE test_proc (p_name IN VARCHAR2)
        IS
        BEGIN
          NULL;
        END;
      """)

      assert :ok = VibeDb.save(db, @test_filename)
      VibeDb.reset(db)
      assert :ok = VibeDb.load(db, @test_filename)

      assert ["TEST_PROC"] = VibeDb.list_procedures(db)
    end

    test "saves and loads stored functions", %{db: db} do
      VibeDb.execute(db, """
        CREATE FUNCTION test_func RETURN NUMBER
        IS
        BEGIN
          RETURN 42;
        END;
      """)

      assert :ok = VibeDb.save(db, @test_filename)
      VibeDb.reset(db)
      assert :ok = VibeDb.load(db, @test_filename)

      assert ["TEST_FUNC"] = VibeDb.list_functions(db)
    end

    test "saves and loads packages", %{db: db} do
      VibeDb.execute(db, """
        CREATE PACKAGE test_pkg
        IS
          PROCEDURE proc1;
        END;
      """)

      assert :ok = VibeDb.save(db, @test_filename)
      VibeDb.reset(db)
      assert :ok = VibeDb.load(db, @test_filename)

      assert ["TEST_PKG"] = VibeDb.list_packages(db)
    end

    test "saves and loads triggers", %{db: db} do
      VibeDb.execute(db, "CREATE TABLE trigger_test (id NUMBER)")
      VibeDb.execute(db, """
        CREATE TRIGGER test_trigger
        BEFORE INSERT ON trigger_test
        FOR EACH ROW
        BEGIN
          NULL;
        END;
      """)

      assert :ok = VibeDb.save(db, @test_filename)
      VibeDb.reset(db)
      assert :ok = VibeDb.load(db, @test_filename)

      assert ["TEST_TRIGGER"] = VibeDb.list_triggers(db)
    end

    test "preserves various data types", %{db: db} do
      VibeDb.execute(db, "CREATE TABLE datatypes (int_col NUMBER, str_col VARCHAR2(100))")
      VibeDb.execute(db, "INSERT INTO datatypes VALUES (42, 'hello')")
      VibeDb.execute(db, "INSERT INTO datatypes VALUES (100, 'world')")

      assert :ok = VibeDb.save(db, @test_filename)
      VibeDb.reset(db)
      assert :ok = VibeDb.load(db, @test_filename)

      {:ok, rows} = VibeDb.execute(db, "SELECT * FROM datatypes")
      assert length(rows) == 2
      
      # Check that both values are present
      int_values = Enum.map(rows, & &1["int_col"]) |> Enum.sort()
      str_values = Enum.map(rows, & &1["str_col"]) |> Enum.sort()
      
      assert int_values == [42, 100]
      assert str_values == ["hello", "world"]
    end

    test "handles special characters in strings", %{db: db} do
      VibeDb.execute(db, "CREATE TABLE special (text VARCHAR2(500))")
      VibeDb.execute(db, "INSERT INTO special VALUES ('Hello <world> & \"friends\"')")

      assert :ok = VibeDb.save(db, @test_filename)
      VibeDb.reset(db)
      assert :ok = VibeDb.load(db, @test_filename)

      {:ok, rows} = VibeDb.execute(db, "SELECT * FROM special")
      assert hd(rows)["text"] == "Hello <world> & \"friends\""
    end
  end

  describe "error handling" do
    test "returns error when loading non-existent file", %{db: db} do
      result = VibeDb.load(db, "/nonexistent/path/file.xml")
      assert {:error, _} = result
    end
  end

  describe "status" do
    test "returns database status", %{db: db} do
      VibeDb.execute(db, "CREATE TABLE t1 (id NUMBER)")
      VibeDb.execute(db, "CREATE TABLE t2 (id NUMBER)")
      VibeDb.execute(db, "INSERT INTO t1 VALUES (1)")
      VibeDb.execute(db, "INSERT INTO t1 VALUES (2)")
      VibeDb.execute(db, "INSERT INTO t2 VALUES (1)")
      VibeDb.execute(db, "CREATE SEQUENCE seq1 START WITH 1")

      status = VibeDb.status(db)

      assert status.tables == 2
      assert status.total_rows == 3
      assert status.sequences == 1
    end
  end
end
