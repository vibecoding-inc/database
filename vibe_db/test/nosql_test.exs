defmodule VibeDb.NosqlTest do
  use ExUnit.Case

  setup do
    {:ok, db} = VibeDb.start_link()
    {:ok, db: db}
  end

  describe "mode switching" do
    test "default mode is SQL", %{db: db} do
      assert VibeDb.get_mode(db) == :sql
    end

    test "can switch to NoSQL mode", %{db: db} do
      assert :ok = VibeDb.set_mode(db, :nosql)
      assert VibeDb.get_mode(db) == :nosql
    end

    test "can switch back to SQL mode", %{db: db} do
      VibeDb.set_mode(db, :nosql)
      assert :ok = VibeDb.set_mode(db, :sql)
      assert VibeDb.get_mode(db) == :sql
    end

    test "invalid mode returns error", %{db: db} do
      assert {:error, _} = VibeDb.set_mode(db, :invalid)
    end
  end

  describe "NoSQL insert operations" do
    test "insert creates collection and document", %{db: db} do
      VibeDb.set_mode(db, :nosql)

      {:ok, result} = VibeDb.execute(db, "db.users.insert({name: \"Alice\", age: 30})")

      assert result.acknowledged == true
      assert result.insertedCount == 1
      assert length(result.insertedIds) == 1
    end

    test "insertOne creates a single document", %{db: db} do
      VibeDb.set_mode(db, :nosql)

      {:ok, result} = VibeDb.execute(db, "db.products.insertOne({name: \"Widget\", price: 9.99})")

      assert result.acknowledged == true
      assert result.insertedCount == 1
    end

    test "insertMany creates multiple documents", %{db: db} do
      VibeDb.set_mode(db, :nosql)

      {:ok, result} =
        VibeDb.execute(
          db,
          "db.items.insertMany([{name: \"Item1\"}, {name: \"Item2\"}, {name: \"Item3\"}])"
        )

      assert result.acknowledged == true
      assert result.insertedCount == 3
      assert length(result.insertedIds) == 3
    end

    test "documents get auto-generated _id", %{db: db} do
      VibeDb.set_mode(db, :nosql)

      VibeDb.execute(db, "db.test.insert({value: \"hello\"})")
      {:ok, docs} = VibeDb.execute(db, "db.test.find({})")

      assert length(docs) == 1
      doc = hd(docs)
      assert Map.has_key?(doc, "_id")
      assert is_binary(doc["_id"])
    end
  end

  describe "NoSQL find operations" do
    setup %{db: db} do
      VibeDb.set_mode(db, :nosql)

      VibeDb.execute(db, "db.users.insert({name: \"Alice\", age: 30, city: \"NYC\"})")
      VibeDb.execute(db, "db.users.insert({name: \"Bob\", age: 25, city: \"LA\"})")
      VibeDb.execute(db, "db.users.insert({name: \"Charlie\", age: 35, city: \"NYC\"})")

      :ok
    end

    test "find with empty query returns all documents", %{db: db} do
      {:ok, docs} = VibeDb.execute(db, "db.users.find({})")
      assert length(docs) == 3
    end

    test "find with no args returns all documents", %{db: db} do
      {:ok, docs} = VibeDb.execute(db, "db.users.find()")
      assert length(docs) == 3
    end

    test "find with field match filter", %{db: db} do
      {:ok, docs} = VibeDb.execute(db, "db.users.find({name: \"Alice\"})")
      assert length(docs) == 1
      assert hd(docs)["name"] == "Alice"
    end

    test "find with multiple field match", %{db: db} do
      {:ok, docs} = VibeDb.execute(db, "db.users.find({city: \"NYC\"})")
      assert length(docs) == 2
    end

    test "findOne returns single document", %{db: db} do
      {:ok, docs} = VibeDb.execute(db, "db.users.findOne({})")
      assert length(docs) == 1
    end

    test "find on non-existent collection returns empty", %{db: db} do
      {:ok, docs} = VibeDb.execute(db, "db.nonexistent.find({})")
      assert docs == []
    end
  end

  describe "NoSQL update operations" do
    setup %{db: db} do
      VibeDb.set_mode(db, :nosql)

      VibeDb.execute(db, "db.users.insert({name: \"Alice\", age: 30})")
      VibeDb.execute(db, "db.users.insert({name: \"Bob\", age: 25})")

      :ok
    end

    test "update with $set modifies document", %{db: db} do
      {:ok, result} =
        VibeDb.execute(db, "db.users.update({name: \"Alice\"}, {\"$set\": {age: 31}})")

      assert result.acknowledged == true
      assert result.modifiedCount == 1

      {:ok, docs} = VibeDb.execute(db, "db.users.find({name: \"Alice\"})")
      assert hd(docs)["age"] == 31
    end

    test "updateOne updates single document", %{db: db} do
      # Add another Alice
      VibeDb.execute(db, "db.users.insert({name: \"Alice\", age: 40})")

      {:ok, result} =
        VibeDb.execute(db, "db.users.updateOne({name: \"Alice\"}, {\"$set\": {age: 99}})")

      assert result.modifiedCount == 1

      # Only one Alice should have age 99
      {:ok, docs} = VibeDb.execute(db, "db.users.find({age: 99})")
      assert length(docs) == 1
    end

    test "updateMany updates all matching documents", %{db: db} do
      VibeDb.execute(db, "db.users.insert({name: \"Alice\", age: 40})")

      {:ok, result} =
        VibeDb.execute(db, "db.users.updateMany({name: \"Alice\"}, {\"$set\": {status: \"updated\"}})")

      assert result.modifiedCount == 2

      {:ok, docs} = VibeDb.execute(db, "db.users.find({status: \"updated\"})")
      assert length(docs) == 2
    end
  end

  describe "NoSQL delete operations" do
    setup %{db: db} do
      VibeDb.set_mode(db, :nosql)

      VibeDb.execute(db, "db.users.insert({name: \"Alice\", age: 30})")
      VibeDb.execute(db, "db.users.insert({name: \"Bob\", age: 25})")
      VibeDb.execute(db, "db.users.insert({name: \"Charlie\", age: 35})")

      :ok
    end

    test "delete removes matching documents", %{db: db} do
      {:ok, result} = VibeDb.execute(db, "db.users.delete({name: \"Alice\"})")

      assert result.acknowledged == true
      assert result.deletedCount == 1

      {:ok, docs} = VibeDb.execute(db, "db.users.find({})")
      assert length(docs) == 2
    end

    test "deleteOne removes single document", %{db: db} do
      # Add another matching document
      VibeDb.execute(db, "db.users.insert({name: \"Alice\", age: 40})")

      {:ok, result} = VibeDb.execute(db, "db.users.deleteOne({name: \"Alice\"})")

      assert result.deletedCount == 1

      {:ok, docs} = VibeDb.execute(db, "db.users.find({name: \"Alice\"})")
      # One Alice should remain
      assert length(docs) == 1
    end

    test "deleteMany removes all matching documents", %{db: db} do
      {:ok, result} = VibeDb.execute(db, "db.users.deleteMany({})")

      assert result.deletedCount == 3

      {:ok, docs} = VibeDb.execute(db, "db.users.find({})")
      assert docs == []
    end
  end

  describe "NoSQL collection operations" do
    test "drop removes collection", %{db: db} do
      VibeDb.set_mode(db, :nosql)

      VibeDb.execute(db, "db.test.insert({value: 1})")
      {:ok, result} = VibeDb.execute(db, "db.test.drop()")

      assert result.ok == 1
    end

    test "createCollection creates empty collection", %{db: db} do
      VibeDb.set_mode(db, :nosql)

      {:ok, result} = VibeDb.execute(db, "db.createCollection(\"newcoll\")")

      assert result.ok == 1
    end

    test "getCollectionNames lists collections", %{db: db} do
      VibeDb.set_mode(db, :nosql)

      VibeDb.execute(db, "db.coll1.insert({a: 1})")
      VibeDb.execute(db, "db.coll2.insert({b: 2})")

      {:ok, collections} = VibeDb.execute(db, "db.getCollectionNames()")

      assert is_list(collections)
      assert "coll1" in collections
      assert "coll2" in collections
    end
  end

  describe "NoSQL and SQL interoperability" do
    test "collections can be queried as tables in SQL mode", %{db: db} do
      # Insert in NoSQL mode
      VibeDb.set_mode(db, :nosql)
      VibeDb.execute(db, "db.mixed.insert({name: \"Test\", value: 42})")

      # Query in SQL mode
      VibeDb.set_mode(db, :sql)
      {:ok, rows} = VibeDb.execute(db, "SELECT * FROM mixed")

      assert length(rows) == 1
    end

    test "tables can be queried as collections in NoSQL mode", %{db: db} do
      # Create table in SQL mode
      VibeDb.set_mode(db, :sql)
      VibeDb.execute(db, "CREATE TABLE hybrid (id NUMBER, name VARCHAR2(100))")
      VibeDb.execute(db, "INSERT INTO hybrid VALUES (1, 'Test')")

      # Query in NoSQL mode
      VibeDb.set_mode(db, :nosql)
      {:ok, docs} = VibeDb.execute(db, "db.hybrid.find({})")

      assert length(docs) == 1
    end

    test "can use execute_nosql in SQL mode", %{db: db} do
      # Stay in SQL mode (default)
      assert VibeDb.get_mode(db) == :sql

      # Use explicit NoSQL execution
      {:ok, result} =
        VibeDb.execute_nosql(db, "db.nosql_direct.insert({message: \"Hello from NoSQL\"})")

      assert result.acknowledged == true
      assert result.insertedCount == 1
    end
  end

  describe "NoSQL parser" do
    test "parses insert with JSON object", %{db: db} do
      VibeDb.set_mode(db, :nosql)

      {:ok, _} =
        VibeDb.execute(db, "db.test.insert({\"key\": \"value\", \"number\": 42, \"bool\": true})")

      {:ok, docs} = VibeDb.execute(db, "db.test.find({})")
      doc = hd(docs)
      assert doc["key"] == "value"
      assert doc["number"] == 42
      assert doc["bool"] == true
    end

    test "parses find with comparison operators", %{db: db} do
      VibeDb.set_mode(db, :nosql)

      VibeDb.execute(db, "db.nums.insert({value: 10})")
      VibeDb.execute(db, "db.nums.insert({value: 20})")
      VibeDb.execute(db, "db.nums.insert({value: 30})")

      {:ok, docs} = VibeDb.execute(db, "db.nums.find({\"value\": {\"$gt\": 15}})")
      assert length(docs) == 2
    end

    test "parses find with $in operator", %{db: db} do
      VibeDb.set_mode(db, :nosql)

      VibeDb.execute(db, "db.items.insert({type: \"A\"})")
      VibeDb.execute(db, "db.items.insert({type: \"B\"})")
      VibeDb.execute(db, "db.items.insert({type: \"C\"})")

      {:ok, docs} = VibeDb.execute(db, "db.items.find({\"type\": {\"$in\": [\"A\", \"C\"]}})")
      assert length(docs) == 2
    end
  end
end
