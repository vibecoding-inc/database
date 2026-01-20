defmodule VibeDb.NosqlParser do
  @moduledoc """
  NoSQL Parser for VibeDb.
  Parses MongoDB-style document commands.

  Supports the following command patterns:
  - db.<collection>.insert(<document>)
  - db.<collection>.insertOne(<document>)
  - db.<collection>.insertMany([<documents>])
  - db.<collection>.find(<query>)
  - db.<collection>.findOne(<query>)
  - db.<collection>.update(<query>, <update>)
  - db.<collection>.updateOne(<query>, <update>)
  - db.<collection>.updateMany(<query>, <update>)
  - db.<collection>.delete(<query>)
  - db.<collection>.deleteOne(<query>)
  - db.<collection>.deleteMany(<query>)
  - db.<collection>.drop()
  - db.createCollection(<name>)
  - db.getCollectionNames()
  """

  @type parsed_statement ::
          {:nosql_insert, map()}
          | {:nosql_find, map()}
          | {:nosql_update, map()}
          | {:nosql_delete, map()}
          | {:nosql_drop, map()}
          | {:nosql_create_collection, map()}
          | {:nosql_list_collections, map()}
          | {:error, String.t()}

  @doc """
  Parses a NoSQL command string into a structured representation.
  """
  @spec parse(String.t()) :: parsed_statement()
  def parse(command) when is_binary(command) do
    command
    |> String.trim()
    |> do_parse()
  end

  defp do_parse("db.getCollectionNames()") do
    {:nosql_list_collections, %{}}
  end

  defp do_parse("db.getCollectionNames" <> _) do
    {:nosql_list_collections, %{}}
  end

  defp do_parse("db.createCollection(" <> rest) do
    case parse_args(rest) do
      {:ok, [name | _]} when is_binary(name) ->
        {:nosql_create_collection, %{name: name}}

      _ ->
        {:error, "Invalid createCollection syntax"}
    end
  end

  defp do_parse("db." <> rest) do
    case parse_collection_command(rest) do
      {:ok, result} -> result
      {:error, reason} -> {:error, reason}
    end
  end

  defp do_parse(command) do
    {:error, "Invalid NoSQL command: #{command}. Commands must start with 'db.'"}
  end

  defp parse_collection_command(rest) do
    case String.split(rest, ".", parts: 2) do
      [collection, method_and_args] ->
        parse_method(collection, method_and_args)

      _ ->
        {:error, "Invalid collection command syntax"}
    end
  end

  defp parse_method(collection, "insert(" <> rest) do
    parse_insert(collection, rest, :insert)
  end

  defp parse_method(collection, "insertOne(" <> rest) do
    parse_insert(collection, rest, :insert_one)
  end

  defp parse_method(collection, "insertMany(" <> rest) do
    parse_insert_many(collection, rest)
  end

  defp parse_method(collection, "find(" <> rest) do
    parse_find(collection, rest, :find)
  end

  defp parse_method(collection, "find()") do
    {:ok, {:nosql_find, %{collection: collection, query: %{}}}}
  end

  defp parse_method(collection, "findOne(" <> rest) do
    parse_find(collection, rest, :find_one)
  end

  defp parse_method(collection, "findOne()") do
    {:ok, {:nosql_find, %{collection: collection, query: %{}, limit: 1}}}
  end

  defp parse_method(collection, "update(" <> rest) do
    parse_update(collection, rest, :update)
  end

  defp parse_method(collection, "updateOne(" <> rest) do
    parse_update(collection, rest, :update_one)
  end

  defp parse_method(collection, "updateMany(" <> rest) do
    parse_update(collection, rest, :update_many)
  end

  defp parse_method(collection, "delete(" <> rest) do
    parse_delete(collection, rest, :delete)
  end

  defp parse_method(collection, "deleteOne(" <> rest) do
    parse_delete(collection, rest, :delete_one)
  end

  defp parse_method(collection, "deleteMany(" <> rest) do
    parse_delete(collection, rest, :delete_many)
  end

  defp parse_method(collection, "drop()") do
    {:ok, {:nosql_drop, %{collection: collection}}}
  end

  defp parse_method(collection, "drop(" <> _) do
    {:ok, {:nosql_drop, %{collection: collection}}}
  end

  defp parse_method(collection, "count()") do
    {:ok, {:nosql_count, %{collection: collection, query: %{}}}}
  end

  defp parse_method(collection, "count(" <> rest) do
    case parse_json_arg(rest) do
      {:ok, query, _} ->
        {:ok, {:nosql_count, %{collection: collection, query: query}}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp parse_method(_collection, method) do
    {:error, "Unknown NoSQL method: #{method}"}
  end

  defp parse_insert(collection, rest, type) do
    case parse_json_arg(rest) do
      {:ok, document, _} when is_map(document) ->
        limit = if type == :insert_one, do: 1, else: nil
        {:ok, {:nosql_insert, %{collection: collection, documents: [document], limit: limit}}}

      {:ok, documents, _} when is_list(documents) ->
        {:ok, {:nosql_insert, %{collection: collection, documents: documents}}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp parse_insert_many(collection, rest) do
    case parse_json_arg(rest) do
      {:ok, documents, _} when is_list(documents) ->
        {:ok, {:nosql_insert, %{collection: collection, documents: documents}}}

      {:ok, document, _} when is_map(document) ->
        {:ok, {:nosql_insert, %{collection: collection, documents: [document]}}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp parse_find(collection, rest, type) do
    case parse_json_arg(rest) do
      {:ok, query, _} when is_map(query) ->
        limit = if type == :find_one, do: 1, else: nil
        {:ok, {:nosql_find, %{collection: collection, query: query, limit: limit}}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp parse_update(collection, rest, type) do
    case parse_two_json_args(rest) do
      {:ok, query, update} when is_map(query) and is_map(update) ->
        multi = type == :update_many
        limit = if type == :update_one, do: 1, else: nil

        {:ok,
         {:nosql_update,
          %{collection: collection, query: query, update: update, multi: multi, limit: limit}}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp parse_delete(collection, rest, type) do
    case parse_json_arg(rest) do
      {:ok, query, _} when is_map(query) ->
        multi = type == :delete_many
        limit = if type == :delete_one, do: 1, else: nil

        {:ok,
         {:nosql_delete, %{collection: collection, query: query, multi: multi, limit: limit}}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Parse a JSON-like argument from the command string.
  Handles both simple JSON objects and nested structures.
  """
  @spec parse_json_arg(String.t()) :: {:ok, map() | list(), String.t()} | {:error, String.t()}
  def parse_json_arg(str) do
    str = String.trim(str)

    cond do
      String.starts_with?(str, "{") ->
        parse_json_object(str)

      String.starts_with?(str, "[") ->
        parse_json_array(str)

      String.starts_with?(str, ")") ->
        {:ok, %{}, String.slice(str, 1..-1//1)}

      true ->
        {:error, "Expected JSON object or array, got: #{String.slice(str, 0, 20)}..."}
    end
  end

  defp parse_args(str) do
    str = String.trim(str)
    str = String.trim_trailing(str, ")")

    case parse_string_or_value(str) do
      {:ok, value, _} -> {:ok, [value]}
      {:error, reason} -> {:error, reason}
    end
  end

  defp parse_two_json_args(str) do
    str = String.trim(str)

    case parse_json_arg(str) do
      {:ok, first, rest} ->
        rest = String.trim(rest)

        rest =
          if String.starts_with?(rest, ",") do
            String.slice(rest, 1..-1//1) |> String.trim()
          else
            rest
          end

        case parse_json_arg(rest) do
          {:ok, second, _} -> {:ok, first, second}
          {:error, reason} -> {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp parse_json_object(str) do
    # Find matching closing brace
    case find_matching_brace(str, 0, 0, ?{, ?}) do
      {:ok, end_idx} ->
        json_str = String.slice(str, 0, end_idx + 1)
        rest = String.slice(str, (end_idx + 1)..-1//1)

        case decode_json(json_str) do
          {:ok, map} -> {:ok, map, rest}
          {:error, reason} -> {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp parse_json_array(str) do
    case find_matching_brace(str, 0, 0, ?[, ?]) do
      {:ok, end_idx} ->
        json_str = String.slice(str, 0, end_idx + 1)
        rest = String.slice(str, (end_idx + 1)..-1//1)

        case decode_json(json_str) do
          {:ok, list} -> {:ok, list, rest}
          {:error, reason} -> {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp find_matching_brace(str, idx, depth, open_char, close_char) do
    chars = String.to_charlist(str)
    find_matching_brace_impl(chars, idx, depth, open_char, close_char, false)
  end

  defp find_matching_brace_impl([], _idx, _depth, _open, _close, _in_string) do
    {:error, "Unmatched brace"}
  end

  defp find_matching_brace_impl([?" | rest], idx, depth, open, close, false) do
    # Entering a string
    find_matching_brace_impl(rest, idx + 1, depth, open, close, true)
  end

  defp find_matching_brace_impl([?\\ | [_ | rest]], idx, depth, open, close, true) do
    # Escaped character in string
    find_matching_brace_impl(rest, idx + 2, depth, open, close, true)
  end

  defp find_matching_brace_impl([?" | rest], idx, depth, open, close, true) do
    # Exiting a string
    find_matching_brace_impl(rest, idx + 1, depth, open, close, false)
  end

  defp find_matching_brace_impl([c | rest], idx, depth, open, close, false) when c == open do
    find_matching_brace_impl(rest, idx + 1, depth + 1, open, close, false)
  end

  defp find_matching_brace_impl([c | _rest], idx, 1, _open, close, false) when c == close do
    {:ok, idx}
  end

  defp find_matching_brace_impl([c | rest], idx, depth, open, close, false) when c == close do
    find_matching_brace_impl(rest, idx + 1, depth - 1, open, close, false)
  end

  defp find_matching_brace_impl([_ | rest], idx, depth, open, close, in_string) do
    find_matching_brace_impl(rest, idx + 1, depth, open, close, in_string)
  end

  defp parse_string_or_value(str) do
    str = String.trim(str)

    cond do
      String.starts_with?(str, "\"") or String.starts_with?(str, "'") ->
        parse_quoted_string(str)

      String.starts_with?(str, "{") ->
        parse_json_object(str)

      String.starts_with?(str, "[") ->
        parse_json_array(str)

      true ->
        # Try to parse as unquoted identifier or value
        parse_unquoted_value(str)
    end
  end

  defp parse_quoted_string(str) do
    quote_char = String.at(str, 0)
    rest = String.slice(str, 1..-1//1)

    case find_closing_quote(rest, quote_char, 0) do
      {:ok, end_idx} ->
        value = String.slice(rest, 0, end_idx)
        remaining = String.slice(rest, (end_idx + 1)..-1//1)
        {:ok, value, remaining}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp find_closing_quote(str, quote_char, idx) do
    chars = String.graphemes(str)
    find_closing_quote_impl(chars, quote_char, idx)
  end

  defp find_closing_quote_impl([], _quote_char, _idx) do
    {:error, "Unterminated string"}
  end

  defp find_closing_quote_impl(["\\", _ | rest], quote_char, idx) do
    find_closing_quote_impl(rest, quote_char, idx + 2)
  end

  defp find_closing_quote_impl([char | _rest], quote_char, idx) when char == quote_char do
    {:ok, idx}
  end

  defp find_closing_quote_impl([_ | rest], quote_char, idx) do
    find_closing_quote_impl(rest, quote_char, idx + 1)
  end

  defp parse_unquoted_value(str) do
    # Parse until we hit a delimiter
    case Regex.run(~r/^([a-zA-Z_][a-zA-Z0-9_]*|[0-9]+(?:\.[0-9]+)?|true|false|null)/, str) do
      [match | _] ->
        rest = String.slice(str, String.length(match)..-1//1)
        value = parse_primitive(match)
        {:ok, value, rest}

      nil ->
        {:error, "Could not parse value: #{String.slice(str, 0, 20)}..."}
    end
  end

  defp parse_primitive("true"), do: true
  defp parse_primitive("false"), do: false
  defp parse_primitive("null"), do: nil

  defp parse_primitive(str) do
    cond do
      String.match?(str, ~r/^\d+$/) ->
        String.to_integer(str)

      String.match?(str, ~r/^\d+\.\d+$/) ->
        String.to_float(str)

      true ->
        str
    end
  end

  @doc """
  Decode a JSON string into an Elixir term.
  Uses a simple recursive descent parser.
  All map keys are converted to strings for consistency.
  """
  @spec decode_json(String.t()) :: {:ok, any()} | {:error, String.t()}
  def decode_json(str) do
    str = String.trim(str)
    # Simple JSON parsing - convert to Elixir-compatible format

    # Replace single quotes with double quotes for consistency
    # Handle field names without quotes (MongoDB style)
    normalized = normalize_json(str)

    try do
      # Use Code.eval_string with proper escaping
      {result, _} =
        normalized
        |> convert_json_to_elixir()
        |> Code.eval_string()

      # Normalize all map keys to strings
      {:ok, stringify_keys(result)}
    rescue
      e ->
        {:error, "JSON parse error: #{Exception.message(e)}"}
    end
  end

  # Recursively convert all map keys to strings
  defp stringify_keys(map) when is_map(map) do
    Map.new(map, fn {k, v} ->
      {to_string(k), stringify_keys(v)}
    end)
  end

  defp stringify_keys(list) when is_list(list) do
    Enum.map(list, &stringify_keys/1)
  end

  defp stringify_keys(value), do: value

  defp normalize_json(str) do
    str
    # Replace unquoted field names with quoted ones
    |> String.replace(~r/([{,]\s*)([a-zA-Z_][a-zA-Z0-9_]*)(\s*:)/, "\\1\"\\2\"\\3")
    # Handle $operators in field names
    |> String.replace(~r/([{,]\s*)(\$[a-zA-Z_][a-zA-Z0-9_]*)(\s*:)/, "\\1\"\\2\"\\3")
  end

  defp convert_json_to_elixir(str) do
    str
    # Convert JSON null to Elixir nil
    |> String.replace(~r/\bnull\b/, "nil")
    # Convert JSON true/false (already valid in Elixir)
    # Convert JSON objects to Elixir maps
    |> String.replace("{", "%{")
    # Keep arrays as-is (they work the same)
    # Handle double-quoted strings (already valid in Elixir)
    # Convert single-quoted strings to double-quoted
    |> convert_single_to_double_quotes()
  end

  defp convert_single_to_double_quotes(str) do
    # Simple conversion - doesn't handle all edge cases
    str
    |> String.replace(~r/'([^']*)'/, "\"\\1\"")
  end
end
