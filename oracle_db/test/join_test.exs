defmodule OracleDb.JoinTest do
  use ExUnit.Case

  alias OracleDb

  setup do
    {:ok, db} = OracleDb.start_link()

    # Create test tables
    OracleDb.execute(db, "CREATE TABLE users (id NUMBER, name VARCHAR2(100), department_id NUMBER)")
    OracleDb.execute(db, "CREATE TABLE orders (id NUMBER, user_id NUMBER, product VARCHAR2(100), amount NUMBER)")
    OracleDb.execute(db, "CREATE TABLE departments (id NUMBER, name VARCHAR2(100))")
    OracleDb.execute(db, "CREATE TABLE products (id NUMBER, name VARCHAR2(100), price NUMBER)")

    # Insert test data into users
    OracleDb.execute(db, "INSERT INTO users (id, name, department_id) VALUES (1, 'Alice', 10)")
    OracleDb.execute(db, "INSERT INTO users (id, name, department_id) VALUES (2, 'Bob', 20)")
    OracleDb.execute(db, "INSERT INTO users (id, name, department_id) VALUES (3, 'Charlie', 10)")
    OracleDb.execute(db, "INSERT INTO users (id, name, department_id) VALUES (4, 'Diana', NULL)")

    # Insert test data into orders
    OracleDb.execute(db, "INSERT INTO orders (id, user_id, product, amount) VALUES (101, 1, 'Widget', 100)")
    OracleDb.execute(db, "INSERT INTO orders (id, user_id, product, amount) VALUES (102, 1, 'Gadget', 200)")
    OracleDb.execute(db, "INSERT INTO orders (id, user_id, product, amount) VALUES (103, 2, 'Widget', 150)")
    OracleDb.execute(db, "INSERT INTO orders (id, user_id, product, amount) VALUES (104, 5, 'Tool', 50)")

    # Insert test data into departments
    OracleDb.execute(db, "INSERT INTO departments (id, name) VALUES (10, 'Engineering')")
    OracleDb.execute(db, "INSERT INTO departments (id, name) VALUES (20, 'Sales')")
    OracleDb.execute(db, "INSERT INTO departments (id, name) VALUES (30, 'Marketing')")

    # Insert test data into products
    OracleDb.execute(db, "INSERT INTO products (id, name, price) VALUES (1, 'Widget', 10)")
    OracleDb.execute(db, "INSERT INTO products (id, name, price) VALUES (2, 'Gadget', 25)")
    OracleDb.execute(db, "INSERT INTO products (id, name, price) VALUES (3, 'Tool', 15)")

    {:ok, db: db}
  end

  describe "INNER JOIN" do
    test "basic INNER JOIN with ON", %{db: db} do
      {:ok, rows} = OracleDb.execute(db, """
        SELECT *
        FROM users
        INNER JOIN orders ON users.id = orders.user_id
      """)

      # Alice has 2 orders, Bob has 1 order, Charlie has 0 orders, Diana has 0 orders
      # Order 104 has user_id 5 which doesn't exist
      assert length(rows) == 3
    end

    test "INNER JOIN returns matching rows only", %{db: db} do
      {:ok, rows} = OracleDb.execute(db, """
        SELECT users.name, orders.product
        FROM users
        JOIN orders ON users.id = orders.user_id
      """)

      assert length(rows) == 3

      names = Enum.map(rows, &Map.get(&1, "users.name"))
      assert "Alice" in names
      assert "Bob" in names
      refute "Charlie" in names
      refute "Diana" in names
    end

    test "INNER JOIN with table aliases", %{db: db} do
      {:ok, rows} = OracleDb.execute(db, """
        SELECT u.name, o.product
        FROM users u
        INNER JOIN orders o ON u.id = o.user_id
      """)

      assert length(rows) == 3
    end

    test "INNER JOIN with WHERE clause", %{db: db} do
      {:ok, rows} = OracleDb.execute(db, """
        SELECT users.name, orders.product, orders.amount
        FROM users
        INNER JOIN orders ON users.id = orders.user_id
        WHERE orders.amount > 100
      """)

      # Only Alice's Gadget (200) and Bob's Widget (150) match
      assert length(rows) == 2
    end

    test "INNER JOIN with ORDER BY", %{db: db} do
      {:ok, rows} = OracleDb.execute(db, """
        SELECT users.name, orders.amount
        FROM users
        INNER JOIN orders ON users.id = orders.user_id
        ORDER BY orders.amount DESC
      """)

      amounts = Enum.map(rows, &Map.get(&1, "orders.amount"))
      assert amounts == [200, 150, 100]
    end

    test "multiple INNER JOINs", %{db: db} do
      {:ok, rows} = OracleDb.execute(db, """
        SELECT users.name, departments.name
        FROM users
        INNER JOIN departments ON users.department_id = departments.id
      """)

      # Alice and Charlie are in Engineering, Bob is in Sales, Diana has NULL department
      assert length(rows) == 3
    end
  end

  describe "LEFT JOIN" do
    test "LEFT JOIN includes all left rows", %{db: db} do
      {:ok, rows} = OracleDb.execute(db, """
        SELECT users.name, orders.product
        FROM users
        LEFT JOIN orders ON users.id = orders.user_id
      """)

      # All 4 users, Alice has 2 orders, Bob has 1, Charlie and Diana have none
      assert length(rows) == 5

      names = Enum.map(rows, &Map.get(&1, "users.name"))
      assert "Alice" in names
      assert "Bob" in names
      assert "Charlie" in names
      assert "Diana" in names
    end

    test "LEFT JOIN has NULL for non-matching right rows", %{db: db} do
      {:ok, rows} = OracleDb.execute(db, """
        SELECT users.name, orders.product
        FROM users
        LEFT JOIN orders ON users.id = orders.user_id
        WHERE users.name = 'Charlie'
      """)

      assert length(rows) == 1
      [row] = rows
      assert row["users.name"] == "Charlie"
      assert row["orders.product"] == nil
    end

    test "LEFT OUTER JOIN is same as LEFT JOIN", %{db: db} do
      {:ok, rows1} = OracleDb.execute(db, """
        SELECT users.name
        FROM users
        LEFT JOIN orders ON users.id = orders.user_id
      """)

      {:ok, rows2} = OracleDb.execute(db, """
        SELECT users.name
        FROM users
        LEFT OUTER JOIN orders ON users.id = orders.user_id
      """)

      assert length(rows1) == length(rows2)
    end

    test "LEFT JOIN with departments", %{db: db} do
      {:ok, rows} = OracleDb.execute(db, """
        SELECT users.name, departments.name
        FROM users
        LEFT JOIN departments ON users.department_id = departments.id
      """)

      # All 4 users should appear
      assert length(rows) == 4

      # Diana has no department
      diana_row = Enum.find(rows, fn r -> r["users.name"] == "Diana" end)
      assert diana_row["departments.name"] == nil
    end
  end

  describe "RIGHT JOIN" do
    test "RIGHT JOIN includes all right rows", %{db: db} do
      {:ok, rows} = OracleDb.execute(db, """
        SELECT users.name, orders.product
        FROM users
        RIGHT JOIN orders ON users.id = orders.user_id
      """)

      # All 4 orders, order 104 has no matching user
      assert length(rows) == 4
    end

    test "RIGHT JOIN has NULL for non-matching left rows", %{db: db} do
      {:ok, rows} = OracleDb.execute(db, """
        SELECT users.name, orders.product
        FROM users
        RIGHT JOIN orders ON users.id = orders.user_id
        WHERE orders.id = 104
      """)

      assert length(rows) == 1
      [row] = rows
      assert row["users.name"] == nil
      assert row["orders.product"] == "Tool"
    end

    test "RIGHT OUTER JOIN is same as RIGHT JOIN", %{db: db} do
      {:ok, rows1} = OracleDb.execute(db, """
        SELECT orders.product
        FROM users
        RIGHT JOIN orders ON users.id = orders.user_id
      """)

      {:ok, rows2} = OracleDb.execute(db, """
        SELECT orders.product
        FROM users
        RIGHT OUTER JOIN orders ON users.id = orders.user_id
      """)

      assert length(rows1) == length(rows2)
    end

    test "RIGHT JOIN with departments shows all departments", %{db: db} do
      {:ok, rows} = OracleDb.execute(db, """
        SELECT users.name, departments.name
        FROM users
        RIGHT JOIN departments ON users.department_id = departments.id
      """)

      # Engineering has 2, Sales has 1, Marketing has 0 users
      # So: Alice-Engineering, Charlie-Engineering, Bob-Sales, NULL-Marketing
      assert length(rows) == 4

      # Marketing should have no users
      marketing_row = Enum.find(rows, fn r -> r["departments.name"] == "Marketing" end)
      assert marketing_row != nil
      assert marketing_row["users.name"] == nil
    end
  end

  describe "FULL OUTER JOIN" do
    test "FULL JOIN includes all rows from both tables", %{db: db} do
      {:ok, rows} = OracleDb.execute(db, """
        SELECT users.name, orders.product
        FROM users
        FULL JOIN orders ON users.id = orders.user_id
      """)

      # Users: 4 (Alice, Bob, Charlie, Diana)
      # Orders: 4 (101, 102, 103, 104)
      # Matches: Alice-101, Alice-102, Bob-103
      # Unmatched left: Charlie, Diana
      # Unmatched right: 104
      # Total: 3 matches + 2 unmatched left + 1 unmatched right = 6
      assert length(rows) == 6
    end

    test "FULL OUTER JOIN is same as FULL JOIN", %{db: db} do
      {:ok, rows1} = OracleDb.execute(db, """
        SELECT users.name, orders.product
        FROM users
        FULL JOIN orders ON users.id = orders.user_id
      """)

      {:ok, rows2} = OracleDb.execute(db, """
        SELECT users.name, orders.product
        FROM users
        FULL OUTER JOIN orders ON users.id = orders.user_id
      """)

      assert length(rows1) == length(rows2)
    end

    test "FULL JOIN with departments", %{db: db} do
      {:ok, rows} = OracleDb.execute(db, """
        SELECT users.name, departments.name
        FROM users
        FULL JOIN departments ON users.department_id = departments.id
      """)

      # Engineering: Alice, Charlie (2)
      # Sales: Bob (1)
      # Marketing: no users (1 with NULL user)
      # Diana: no department (1 with NULL dept)
      # Total: 5
      assert length(rows) == 5
    end
  end

  describe "CROSS JOIN" do
    test "CROSS JOIN returns cartesian product", %{db: db} do
      # Create small tables for testing cross join
      OracleDb.execute(db, "CREATE TABLE colors (name VARCHAR2(20))")
      OracleDb.execute(db, "CREATE TABLE sizes (name VARCHAR2(20))")

      OracleDb.execute(db, "INSERT INTO colors (name) VALUES ('Red')")
      OracleDb.execute(db, "INSERT INTO colors (name) VALUES ('Blue')")

      OracleDb.execute(db, "INSERT INTO sizes (name) VALUES ('Small')")
      OracleDb.execute(db, "INSERT INTO sizes (name) VALUES ('Medium')")
      OracleDb.execute(db, "INSERT INTO sizes (name) VALUES ('Large')")

      {:ok, rows} = OracleDb.execute(db, """
        SELECT colors.name, sizes.name
        FROM colors
        CROSS JOIN sizes
      """)

      # 2 colors * 3 sizes = 6 combinations
      assert length(rows) == 6
    end

    test "comma-separated tables produce cross join", %{db: db} do
      OracleDb.execute(db, "CREATE TABLE a (x NUMBER)")
      OracleDb.execute(db, "CREATE TABLE b (y NUMBER)")

      OracleDb.execute(db, "INSERT INTO a (x) VALUES (1)")
      OracleDb.execute(db, "INSERT INTO a (x) VALUES (2)")

      OracleDb.execute(db, "INSERT INTO b (y) VALUES (10)")
      OracleDb.execute(db, "INSERT INTO b (y) VALUES (20)")

      {:ok, rows} = OracleDb.execute(db, "SELECT * FROM a, b")

      # 2 * 2 = 4
      assert length(rows) == 4
    end
  end

  describe "USING clause" do
    test "JOIN with USING on single column", %{db: db} do
      # Create tables with same column name
      OracleDb.execute(db, "CREATE TABLE employees (id NUMBER, name VARCHAR2(100), dept_id NUMBER)")
      OracleDb.execute(db, "CREATE TABLE depts (dept_id NUMBER, dept_name VARCHAR2(100))")

      OracleDb.execute(db, "INSERT INTO employees (id, name, dept_id) VALUES (1, 'John', 1)")
      OracleDb.execute(db, "INSERT INTO employees (id, name, dept_id) VALUES (2, 'Jane', 2)")
      OracleDb.execute(db, "INSERT INTO employees (id, name, dept_id) VALUES (3, 'Joe', 1)")

      OracleDb.execute(db, "INSERT INTO depts (dept_id, dept_name) VALUES (1, 'IT')")
      OracleDb.execute(db, "INSERT INTO depts (dept_id, dept_name) VALUES (2, 'HR')")

      {:ok, rows} = OracleDb.execute(db, """
        SELECT employees.name, depts.dept_name
        FROM employees
        JOIN depts USING (dept_id)
      """)

      assert length(rows) == 3
    end
  end

  describe "multiple joins" do
    test "three table join", %{db: db} do
      {:ok, rows} = OracleDb.execute(db, """
        SELECT users.name, orders.product, departments.name
        FROM users
        INNER JOIN orders ON users.id = orders.user_id
        INNER JOIN departments ON users.department_id = departments.id
      """)

      # Only users with both orders AND departments
      # Alice (Engineering) has 2 orders
      # Bob (Sales) has 1 order
      # Charlie (Engineering) has 0 orders -> not in result
      # Diana (no department) has 0 orders -> not in result
      assert length(rows) == 3
    end

    test "mixed join types", %{db: db} do
      {:ok, rows} = OracleDb.execute(db, """
        SELECT users.name, orders.product, departments.name
        FROM users
        LEFT JOIN orders ON users.id = orders.user_id
        LEFT JOIN departments ON users.department_id = departments.id
      """)

      # All users appear with their orders and departments (or NULLs)
      assert length(rows) >= 4
    end
  end

  describe "edge cases" do
    test "join on empty table", %{db: db} do
      OracleDb.execute(db, "CREATE TABLE empty_table (id NUMBER)")

      {:ok, rows} = OracleDb.execute(db, """
        SELECT users.name
        FROM users
        INNER JOIN empty_table ON users.id = empty_table.id
      """)

      assert rows == []
    end

    test "left join on empty right table", %{db: db} do
      OracleDb.execute(db, "CREATE TABLE empty_right (id NUMBER, data VARCHAR2(100))")

      {:ok, rows} = OracleDb.execute(db, """
        SELECT users.name, empty_right.data
        FROM users
        LEFT JOIN empty_right ON users.id = empty_right.id
      """)

      # All users should appear with NULL for empty_right columns
      assert length(rows) == 4
      assert Enum.all?(rows, fn r -> r["empty_right.data"] == nil end)
    end

    test "right join on empty left table", %{db: db} do
      OracleDb.execute(db, "CREATE TABLE empty_left (id NUMBER)")

      {:ok, rows} = OracleDb.execute(db, """
        SELECT empty_left.id, users.name
        FROM empty_left
        RIGHT JOIN users ON empty_left.id = users.id
      """)

      # All users should appear with NULL for empty_left columns
      assert length(rows) == 4
      assert Enum.all?(rows, fn r -> r["empty_left.id"] == nil end)
    end

    test "join with NULL values in join columns", %{db: db} do
      # Diana has NULL department_id
      {:ok, rows} = OracleDb.execute(db, """
        SELECT users.name, departments.name
        FROM users
        INNER JOIN departments ON users.department_id = departments.id
      """)

      # Diana should not be in results because NULL != any value
      names = Enum.map(rows, &Map.get(&1, "users.name"))
      refute "Diana" in names
    end

    test "self join", %{db: db} do
      # Create a table with self-reference
      OracleDb.execute(db, "CREATE TABLE employees2 (id NUMBER, name VARCHAR2(100), manager_id NUMBER)")
      OracleDb.execute(db, "INSERT INTO employees2 (id, name, manager_id) VALUES (1, 'CEO', NULL)")
      OracleDb.execute(db, "INSERT INTO employees2 (id, name, manager_id) VALUES (2, 'Manager', 1)")
      OracleDb.execute(db, "INSERT INTO employees2 (id, name, manager_id) VALUES (3, 'Worker', 2)")

      {:ok, rows} = OracleDb.execute(db, """
        SELECT e.name, m.name
        FROM employees2 e
        LEFT JOIN employees2 m ON e.manager_id = m.id
      """)

      # All 3 employees, CEO has no manager (NULL)
      assert length(rows) == 3
    end
  end

  describe "join with specific columns" do
    test "select specific columns from joined tables", %{db: db} do
      {:ok, rows} = OracleDb.execute(db, """
        SELECT users.name, users.id, orders.product, orders.amount
        FROM users
        INNER JOIN orders ON users.id = orders.user_id
      """)

      assert length(rows) == 3

      first_row = hd(rows)
      assert Map.has_key?(first_row, "users.name")
      assert Map.has_key?(first_row, "users.id")
      assert Map.has_key?(first_row, "orders.product")
      assert Map.has_key?(first_row, "orders.amount")
    end

    test "select all columns with *", %{db: db} do
      {:ok, rows} = OracleDb.execute(db, """
        SELECT *
        FROM users
        INNER JOIN orders ON users.id = orders.user_id
      """)

      assert length(rows) == 3

      first_row = hd(rows)
      # Should have columns from both tables
      keys = Map.keys(first_row) |> Enum.map(&to_string/1)
      assert Enum.any?(keys, &String.contains?(&1, "name"))
    end
  end

  describe "complex ON conditions" do
    test "join with AND in ON clause", %{db: db} do
      {:ok, rows} = OracleDb.execute(db, """
        SELECT users.name, orders.product
        FROM users
        INNER JOIN orders ON users.id = orders.user_id AND orders.amount > 100
      """)

      # Only rows where user matches AND amount > 100
      # Alice-Gadget (200), Bob-Widget (150) - Alice-Widget (100) excluded
      assert length(rows) == 2
    end
  end
end
