defmodule VibeDb.NosqlExecutor do
  @moduledoc """
  Executes parsed NoSQL statements against the storage engine.
  Provides MongoDB-like document database operations.
  """

  alias VibeDb.NosqlParser
  alias VibeDb.Storage

  @type result :: {:ok, any()} | {:error, String.t()}

  @doc """
  Executes a NoSQL command string.
  """
  @spec execute(GenServer.server(), String.t()) :: result()
  def execute(storage, command) when is_binary(command) do
    case NosqlParser.parse(command) do
      {:error, _} = err -> err
      parsed -> execute_parsed(storage, parsed)
    end
  end

  @doc """
  Executes a parsed NoSQL statement.
  """
  @spec execute_parsed(GenServer.server(), NosqlParser.parsed_statement()) :: result()
  def execute_parsed(storage, {:nosql_insert, info}) do
    collection = normalize_collection(info.collection)
    documents = info.documents

    # Ensure collection exists
    ensure_collection(storage, collection)

    # Add _id to documents if not present
    documents_with_ids =
      Enum.map(documents, fn doc ->
        if Map.has_key?(doc, "_id") or Map.has_key?(doc, :_id) do
          doc
        else
          Map.put(doc, "_id", generate_id())
        end
      end)

    # Convert document maps to column-based rows
    case insert_documents(storage, collection, documents_with_ids) do
      {:ok, count} ->
        {:ok,
         %{
           acknowledged: true,
           insertedCount: count,
           insertedIds: Enum.map(documents_with_ids, &Map.get(&1, "_id", Map.get(&1, :_id)))
         }}

      {:error, _} = err ->
        err
    end
  end

  def execute_parsed(storage, {:nosql_find, info}) do
    collection = normalize_collection(info.collection)
    query = info.query
    limit = Map.get(info, :limit)

    case find_documents(storage, collection, query, limit) do
      {:ok, documents} ->
        {:ok, documents}

      {:error, _} = err ->
        err
    end
  end

  def execute_parsed(storage, {:nosql_update, info}) do
    collection = normalize_collection(info.collection)
    query = info.query
    update = info.update
    limit = Map.get(info, :limit)

    case update_documents(storage, collection, query, update, limit) do
      {:ok, count} ->
        {:ok, %{acknowledged: true, matchedCount: count, modifiedCount: count}}

      {:error, _} = err ->
        err
    end
  end

  def execute_parsed(storage, {:nosql_delete, info}) do
    collection = normalize_collection(info.collection)
    query = info.query
    limit = Map.get(info, :limit)

    case delete_documents(storage, collection, query, limit) do
      {:ok, count} ->
        {:ok, %{acknowledged: true, deletedCount: count}}

      {:error, _} = err ->
        err
    end
  end

  def execute_parsed(storage, {:nosql_drop, info}) do
    collection = normalize_collection(info.collection)

    case Storage.drop_table(storage, collection, false) do
      :ok ->
        {:ok, %{ok: 1, dropped: collection}}

      {:error, _reason} ->
        # Collection doesn't exist - still return success like MongoDB
        {:ok, %{ok: 1, dropped: collection}}
    end
  end

  def execute_parsed(storage, {:nosql_create_collection, info}) do
    collection = normalize_collection(info.name)

    case ensure_collection(storage, collection) do
      :ok ->
        {:ok, %{ok: 1}}

      {:error, _} = err ->
        err
    end
  end

  def execute_parsed(storage, {:nosql_list_collections, _info}) do
    tables = Storage.list_tables(storage)
    collections = Enum.map(tables, &String.downcase/1)
    {:ok, collections}
  end

  def execute_parsed(storage, {:nosql_count, info}) do
    collection = normalize_collection(info.collection)
    query = info.query

    case find_documents(storage, collection, query, nil) do
      {:ok, documents} ->
        {:ok, length(documents)}

      {:error, _} = err ->
        err
    end
  end

  def execute_parsed(_storage, {:error, _} = error) do
    error
  end

  def execute_parsed(_storage, unknown) do
    {:error, "Unknown NoSQL command type: #{inspect(unknown)}"}
  end

  # Private functions

  defp normalize_collection(name) when is_binary(name) do
    String.upcase(name)
  end

  defp normalize_collection(name), do: to_string(name) |> String.upcase()

  defp generate_id do
    # Generate a simple unique ID (similar to MongoDB ObjectId but simplified)
    timestamp = System.system_time(:millisecond)
    random = :rand.uniform(0xFFFFFF)
    Base.encode16(<<timestamp::48, random::24>>, case: :lower)
  end

  defp ensure_collection(storage, collection) do
    if Storage.table_exists?(storage, collection) do
      :ok
    else
      # Create a schema-less collection (just a _doc column for the JSON document)
      schema = %{
        columns: [{"_doc", :map, []}],
        constraints: [],
        indexes: %{},
        nosql_collection: true
      }

      case Storage.create_table(storage, collection, schema) do
        :ok -> :ok
        {:error, "Table " <> _} -> :ok
        error -> error
      end
    end
  end

  defp insert_documents(storage, collection, documents) do
    # Convert each document to a row with a single _doc column
    values =
      Enum.map(documents, fn doc ->
        [doc]
      end)

    case Storage.insert(storage, collection, ["_doc"], values) do
      {:ok, count} -> {:ok, count}
      {:error, _} = err -> err
    end
  end

  defp find_documents(storage, collection, query, limit) do
    if not Storage.table_exists?(storage, collection) do
      {:ok, []}
    else
      # Build WHERE clause from query
      where = build_where_clause(query)

      case Storage.select(storage, collection, [{:all, "*"}], where, nil) do
        {:ok, rows} ->
          # Extract documents from rows and apply limit
          documents =
            rows
            |> Enum.map(&extract_document/1)
            |> maybe_limit(limit)

          {:ok, documents}

        {:error, _} = err ->
          err
      end
    end
  end

  defp update_documents(storage, collection, query, update, limit) do
    if not Storage.table_exists?(storage, collection) do
      {:ok, 0}
    else
      # First find matching documents
      where = build_where_clause(query)

      case Storage.select(storage, collection, [{:all, "*"}], where, nil) do
        {:ok, rows} ->
          rows_to_update = maybe_limit(rows, limit)

          if Enum.empty?(rows_to_update) do
            {:ok, 0}
          else
            # Apply updates to each matching document
            count = apply_updates(storage, collection, rows_to_update, update)
            {:ok, count}
          end

        {:error, _} = err ->
          err
      end
    end
  end

  defp delete_documents(storage, collection, query, limit) do
    if not Storage.table_exists?(storage, collection) do
      {:ok, 0}
    else
      # Build WHERE clause from query
      where = build_where_clause(query)

      if limit == 1 do
        # For deleteOne, we need to find the first match and delete by _id
        case Storage.select(storage, collection, [{:all, "*"}], where, nil) do
          {:ok, [first | _]} ->
            doc = extract_document(first)
            id = Map.get(doc, "_id") || Map.get(doc, :_id)

            if id do
              id_where = build_id_where(id)
              Storage.delete(storage, collection, id_where)
            else
              {:ok, 0}
            end

          {:ok, []} ->
            {:ok, 0}

          {:error, _} = err ->
            err
        end
      else
        Storage.delete(storage, collection, where)
      end
    end
  end

  defp build_where_clause(query) when query == %{} or query == nil do
    nil
  end

  defp build_where_clause(query) when is_map(query) do
    conditions =
      query
      |> Enum.map(&build_field_condition/1)
      |> Enum.reject(&is_nil/1)

    case conditions do
      [] -> nil
      [single] -> single
      multiple -> combine_conditions(multiple)
    end
  end

  defp build_field_condition({field, value}) when is_map(value) do
    # Check for operators like $eq, $gt, $lt, etc.
    operator_conditions =
      value
      |> Enum.map(fn {op, val} -> build_operator_condition(field, op, val) end)
      |> Enum.reject(&is_nil/1)

    case operator_conditions do
      [] -> {:nosql_field_match, to_string(field), value}
      [single] -> single
      multiple -> combine_conditions(multiple)
    end
  end

  defp build_field_condition({field, value}) do
    {:nosql_field_match, to_string(field), value}
  end

  defp build_operator_condition(field, "$eq", value) do
    {:nosql_field_match, to_string(field), value}
  end

  defp build_operator_condition(field, "$ne", value) do
    {:nosql_field_ne, to_string(field), value}
  end

  defp build_operator_condition(field, "$gt", value) do
    {:nosql_field_gt, to_string(field), value}
  end

  defp build_operator_condition(field, "$gte", value) do
    {:nosql_field_gte, to_string(field), value}
  end

  defp build_operator_condition(field, "$lt", value) do
    {:nosql_field_lt, to_string(field), value}
  end

  defp build_operator_condition(field, "$lte", value) do
    {:nosql_field_lte, to_string(field), value}
  end

  defp build_operator_condition(field, "$in", values) when is_list(values) do
    {:nosql_field_in, to_string(field), values}
  end

  defp build_operator_condition(field, "$nin", values) when is_list(values) do
    {:nosql_field_nin, to_string(field), values}
  end

  defp build_operator_condition(field, "$exists", true) do
    {:nosql_field_exists, to_string(field), true}
  end

  defp build_operator_condition(field, "$exists", false) do
    {:nosql_field_exists, to_string(field), false}
  end

  defp build_operator_condition(_field, op, _value) do
    IO.puts("[DEBUG] Unsupported NoSQL operator: #{op}")
    nil
  end

  defp build_id_where(id) do
    {:nosql_field_match, "_id", id}
  end

  defp combine_conditions(conditions) do
    Enum.reduce(conditions, fn cond, acc -> {:and, acc, cond} end)
  end

  defp extract_document(row) do
    case Map.get(row, "_doc") || Map.get(row, "_DOC") do
      nil ->
        # If no _doc column, treat the whole row as the document
        Map.delete(row, "__ROWNUM__")

      doc when is_map(doc) ->
        doc

      doc ->
        %{"_doc" => doc}
    end
  end

  defp maybe_limit(items, nil), do: items
  defp maybe_limit(items, limit), do: Enum.take(items, limit)

  defp apply_updates(storage, collection, rows, update) do
    Enum.reduce(rows, 0, fn row, count ->
      doc = extract_document(row)
      updated_doc = apply_update_operators(doc, update)

      # Update the row in storage
      id = Map.get(doc, "_id") || Map.get(doc, :_id)

      if id do
        where = build_id_where(id)
        sets = [{"_doc", updated_doc}]

        case Storage.update(storage, collection, sets, where) do
          {:ok, 1} -> count + 1
          {:ok, n} -> count + n
          _ -> count
        end
      else
        count
      end
    end)
  end

  defp apply_update_operators(doc, update) do
    cond do
      # Check for $set operator
      Map.has_key?(update, "$set") ->
        fields_to_set = Map.get(update, "$set")
        Map.merge(doc, fields_to_set)

      # Check for $unset operator
      Map.has_key?(update, "$unset") ->
        fields_to_unset = Map.get(update, "$unset") |> Map.keys()
        Map.drop(doc, fields_to_unset)

      # Check for $inc operator
      Map.has_key?(update, "$inc") ->
        increments = Map.get(update, "$inc")

        Enum.reduce(increments, doc, fn {field, amount}, acc ->
          current = Map.get(acc, field, 0)
          Map.put(acc, field, current + amount)
        end)

      # No operators - treat as replacement (except for _id)
      true ->
        id = Map.get(doc, "_id") || Map.get(doc, :_id)

        if id do
          Map.put(update, "_id", id)
        else
          update
        end
    end
  end
end
