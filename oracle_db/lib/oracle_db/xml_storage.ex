defmodule OracleDb.XmlStorage do
  @moduledoc """
  XML persistence layer for the Oracle-compatible database.
  Handles serializing and deserializing the complete database state to/from XML files.
  """

  @default_filename "database.xml"

  @doc """
  Saves the complete database state to an XML file.
  """
  @spec save(map(), String.t()) :: :ok | {:error, String.t()}
  def save(state, filename \\ @default_filename) do
    xml = serialize_state(state)

    case File.write(filename, xml) do
      :ok -> :ok
      {:error, reason} -> {:error, "Failed to save database: #{inspect(reason)}"}
    end
  end

  @doc """
  Loads the database state from an XML file.
  """
  @spec load(String.t()) :: {:ok, map()} | {:error, String.t()}
  def load(filename \\ @default_filename) do
    case File.read(filename) do
      {:ok, content} ->
        case deserialize_state(content) do
          {:ok, state} -> {:ok, state}
          {:error, reason} -> {:error, reason}
        end

      {:error, :enoent} ->
        {:error, "File not found: #{filename}"}

      {:error, reason} ->
        {:error, "Failed to load database: #{inspect(reason)}"}
    end
  end

  @doc """
  Returns the default filename for the database.
  """
  @spec default_filename() :: String.t()
  def default_filename, do: @default_filename

  # Serialization functions

  defp serialize_state(state) do
    """
    <?xml version="1.0" encoding="UTF-8"?>
    <database version="1.0">
    #{serialize_tables(state.tables, state.data)}
    #{serialize_sequences(state.sequences)}
    #{serialize_indexes(state.indexes)}
    #{serialize_types(state.types)}
    #{serialize_views(state.views)}
    #{serialize_materialized_views(state.materialized_views)}
    #{serialize_procedures(state.procedures)}
    #{serialize_functions(state.functions)}
    #{serialize_packages(state.packages)}
    #{serialize_triggers(state.triggers)}
    #{serialize_row_counters(state.row_counter)}
    </database>
    """
    |> String.trim()
  end

  defp serialize_tables(tables, data) do
    tables_xml =
      tables
      |> Enum.map(fn {name, schema} ->
        rows = Map.get(data, name, [])
        serialize_table(name, schema, rows)
      end)
      |> Enum.join("\n")

    "<tables>\n#{tables_xml}\n</tables>"
  end

  defp serialize_table(name, schema, rows) do
    columns_xml = serialize_columns(schema.columns)
    constraints_xml = serialize_constraints(schema.constraints)
    rows_xml = serialize_rows(rows)

    object_table_attr =
      if Map.get(schema, :object_table, false) do
        ~s( object_table="true" of_type="#{escape_xml(Map.get(schema, :of_type, ""))}")
      else
        ""
      end

    """
      <table name="#{escape_xml(name)}"#{object_table_attr}>
        <columns>
    #{columns_xml}
        </columns>
        <constraints>
    #{constraints_xml}
        </constraints>
        <rows>
    #{rows_xml}
        </rows>
      </table>
    """
  end

  defp serialize_columns(columns) do
    columns
    |> Enum.map(fn {name, type, modifiers} ->
      type_str = serialize_type(type)
      mods_str = serialize_modifiers(modifiers)
      ~s(        <column name="#{escape_xml(name)}" type="#{type_str}"#{mods_str}/>)
    end)
    |> Enum.join("\n")
  end

  defp serialize_type(type) when is_atom(type), do: Atom.to_string(type)
  defp serialize_type({type, size}) when is_atom(type) and is_integer(size), do: "#{type}(#{size})"

  defp serialize_type({type, precision, scale}) when is_atom(type),
    do: "#{type}(#{precision},#{scale})"

  defp serialize_type(type), do: inspect(type)

  defp serialize_modifiers([]), do: ""

  defp serialize_modifiers(modifiers) do
    mods =
      Enum.map(modifiers, fn
        {:size, size} -> ~s(size="#{size}")
        :primary_key -> ~s(primary_key="true")
        :not_null -> ~s(not_null="true")
        :null -> ""
        {:default, val} -> ~s(default="#{escape_xml(inspect(val))}")
        _ -> ""
      end)
      |> Enum.filter(&(&1 != ""))
      |> Enum.join(" ")

    if mods == "", do: "", else: " " <> mods
  end

  defp serialize_constraints(constraints) do
    constraints
    |> Enum.map(fn constraint ->
      ~s(        <constraint>#{escape_xml(inspect(constraint))}</constraint>)
    end)
    |> Enum.join("\n")
  end

  defp serialize_rows(rows) do
    rows
    |> Enum.map(&serialize_row/1)
    |> Enum.join("\n")
  end

  defp serialize_row(row) do
    fields =
      row
      |> Enum.map(fn {key, value} ->
        ~s(            <field name="#{escape_xml(to_string(key))}">#{serialize_value(value)}</field>)
      end)
      |> Enum.join("\n")

    """
          <row>
    #{fields}
          </row>
    """
    |> String.trim_trailing()
  end

  defp serialize_value(nil), do: "<null/>"
  defp serialize_value(%Date{} = date), do: ~s(<date>#{Date.to_iso8601(date)}</date>)

  defp serialize_value(%DateTime{} = dt),
    do: ~s(<datetime>#{DateTime.to_iso8601(dt)}</datetime>)

  defp serialize_value(value) when is_binary(value), do: ~s(<string>#{escape_xml(value)}</string>)
  defp serialize_value(value) when is_integer(value), do: ~s(<integer>#{value}</integer>)
  defp serialize_value(value) when is_float(value), do: ~s(<float>#{value}</float>)
  defp serialize_value(value) when is_boolean(value), do: ~s(<boolean>#{value}</boolean>)
  defp serialize_value(value) when is_list(value), do: ~s(<list>#{escape_xml(inspect(value))}</list>)

  defp serialize_value(value) when is_map(value),
    do: ~s(<map>#{escape_xml(inspect(value))}</map>)

  defp serialize_value(value), do: ~s(<raw>#{escape_xml(inspect(value))}</raw>)

  defp serialize_sequences(sequences) do
    seqs_xml =
      sequences
      |> Enum.map(fn {name, seq} ->
        ~s(    <sequence name="#{escape_xml(name)}" current="#{seq.current}" increment="#{seq.increment}" min_value="#{seq.min_value}" max_value="#{seq.max_value}" cycle="#{seq.cycle}" initialized="#{seq.initialized}"/>)
      end)
      |> Enum.join("\n")

    "<sequences>\n#{seqs_xml}\n</sequences>"
  end

  defp serialize_indexes(indexes) do
    idxs_xml =
      indexes
      |> Enum.map(fn {name, idx} ->
        cols = Enum.join(idx.columns, ",")

        ~s(    <index name="#{escape_xml(name)}" table="#{escape_xml(idx.table)}" columns="#{escape_xml(cols)}" unique="#{idx.unique}"/>)
      end)
      |> Enum.join("\n")

    "<indexes>\n#{idxs_xml}\n</indexes>"
  end

  defp serialize_types(types) do
    types_xml =
      types
      |> Enum.map(fn {name, type_def} ->
        serialize_type_def(name, type_def)
      end)
      |> Enum.join("\n")

    "<types>\n#{types_xml}\n</types>"
  end

  defp serialize_type_def(name, type_def) do
    kind = Map.get(type_def, :kind, :object)
    attrs = serialize_type_attributes(Map.get(type_def, :attributes, []))
    methods = serialize_type_methods(Map.get(type_def, :methods, []))
    parent = Map.get(type_def, :parent)

    parent_attr = if parent, do: ~s( parent="#{escape_xml(parent)}"), else: ""

    # For collection types
    element_type = Map.get(type_def, :element_type)
    max_size = Map.get(type_def, :max_size)

    element_attr =
      if element_type, do: ~s( element_type="#{serialize_type(element_type)}"), else: ""

    size_attr = if max_size, do: ~s( max_size="#{max_size}"), else: ""

    """
        <type name="#{escape_xml(name)}" kind="#{kind}"#{parent_attr}#{element_attr}#{size_attr}>
          <attributes>
    #{attrs}
          </attributes>
          <methods>
    #{methods}
          </methods>
        </type>
    """
    |> String.trim_trailing()
  end

  defp serialize_type_attributes(attrs) do
    attrs
    |> Enum.map(fn {name, type_info} ->
      ~s(        <attribute name="#{escape_xml(to_string(name))}" type="#{serialize_type(type_info)}"/>)
    end)
    |> Enum.join("\n")
  end

  defp serialize_type_methods(methods) do
    methods
    |> Enum.map(fn method ->
      ~s(        <method>#{escape_xml(inspect(method))}</method>)
    end)
    |> Enum.join("\n")
  end

  defp serialize_views(views) do
    views_xml =
      views
      |> Enum.map(fn {name, view_def} ->
        serialize_view_def(name, view_def)
      end)
      |> Enum.join("\n")

    "<views>\n#{views_xml}\n</views>"
  end

  defp serialize_view_def(name, view_def) do
    query = Map.get(view_def, :query, %{})
    columns = Map.get(view_def, :columns, [])
    of_type = Map.get(view_def, :of_type)
    oid = Map.get(view_def, :object_identifier)

    of_type_attr = if of_type, do: ~s( of_type="#{escape_xml(of_type)}"), else: ""
    oid_attr = if oid, do: ~s( object_identifier="#{escape_xml(inspect(oid))}"), else: ""

    """
        <view name="#{escape_xml(name)}"#{of_type_attr}#{oid_attr}>
          <columns>#{escape_xml(inspect(columns))}</columns>
          <query>#{escape_xml(inspect(query))}</query>
        </view>
    """
    |> String.trim_trailing()
  end

  defp serialize_materialized_views(mvs) do
    mvs_xml =
      mvs
      |> Enum.map(fn {name, mv_def} ->
        query = Map.get(mv_def, :query, %{})

        """
            <materialized_view name="#{escape_xml(name)}">
              <query>#{escape_xml(inspect(query))}</query>
            </materialized_view>
        """
        |> String.trim_trailing()
      end)
      |> Enum.join("\n")

    "<materialized_views>\n#{mvs_xml}\n</materialized_views>"
  end

  defp serialize_procedures(procedures) do
    procs_xml =
      procedures
      |> Enum.map(fn {name, proc_def} ->
        params = Map.get(proc_def, :parameters, [])
        body = Map.get(proc_def, :body, "")

        """
            <procedure name="#{escape_xml(name)}">
              <parameters>#{escape_xml(inspect(params))}</parameters>
              <body><![CDATA[#{body}]]></body>
            </procedure>
        """
        |> String.trim_trailing()
      end)
      |> Enum.join("\n")

    "<procedures>\n#{procs_xml}\n</procedures>"
  end

  defp serialize_functions(functions) do
    funcs_xml =
      functions
      |> Enum.map(fn {name, func_def} ->
        params = Map.get(func_def, :parameters, [])
        return_type = Map.get(func_def, :return_type, "")
        body = Map.get(func_def, :body, "")

        """
            <function name="#{escape_xml(name)}" return_type="#{escape_xml(inspect(return_type))}">
              <parameters>#{escape_xml(inspect(params))}</parameters>
              <body><![CDATA[#{body}]]></body>
            </function>
        """
        |> String.trim_trailing()
      end)
      |> Enum.join("\n")

    "<functions>\n#{funcs_xml}\n</functions>"
  end

  defp serialize_packages(packages) do
    pkgs_xml =
      packages
      |> Enum.map(fn {name, pkg_def} ->
        spec = Map.get(pkg_def, :spec, %{})
        body = Map.get(pkg_def, :body)

        body_xml = if body, do: ~s(<body>#{escape_xml(inspect(body))}</body>), else: ""

        """
            <package name="#{escape_xml(name)}">
              <spec>#{escape_xml(inspect(spec))}</spec>
              #{body_xml}
            </package>
        """
        |> String.trim_trailing()
      end)
      |> Enum.join("\n")

    "<packages>\n#{pkgs_xml}\n</packages>"
  end

  defp serialize_triggers(triggers) do
    trigs_xml =
      triggers
      |> Enum.map(fn {name, trigger_def} ->
        timing = Map.get(trigger_def, :timing, "")
        events = Map.get(trigger_def, :events, [])
        table = Map.get(trigger_def, :table, "")
        level = Map.get(trigger_def, :level, "")
        body = Map.get(trigger_def, :body, "")
        enabled = Map.get(trigger_def, :enabled, true)
        when_clause = Map.get(trigger_def, :when)

        when_xml =
          if when_clause, do: ~s(<when>#{escape_xml(inspect(when_clause))}</when>), else: ""

        """
            <trigger name="#{escape_xml(name)}" timing="#{escape_xml(to_string(timing))}" table="#{escape_xml(to_string(table))}" level="#{escape_xml(to_string(level))}" enabled="#{enabled}">
              <events>#{escape_xml(inspect(events))}</events>
              #{when_xml}
              <body><![CDATA[#{body}]]></body>
            </trigger>
        """
        |> String.trim_trailing()
      end)
      |> Enum.join("\n")

    "<triggers>\n#{trigs_xml}\n</triggers>"
  end

  defp serialize_row_counters(counters) do
    counters_xml =
      counters
      |> Enum.map(fn {name, count} ->
        ~s(    <counter table="#{escape_xml(name)}" value="#{count}"/>)
      end)
      |> Enum.join("\n")

    "<row_counters>\n#{counters_xml}\n</row_counters>"
  end

  # Deserialization functions

  defp deserialize_state(xml) do
    try do
      state = %{
        tables: %{},
        data: %{},
        sequences: %{},
        indexes: %{},
        row_counter: %{},
        types: %{},
        views: %{},
        materialized_views: %{},
        procedures: %{},
        functions: %{},
        packages: %{},
        triggers: %{}
      }

      state = parse_tables(xml, state)
      state = parse_sequences(xml, state)
      state = parse_indexes(xml, state)
      state = parse_types(xml, state)
      state = parse_views(xml, state)
      state = parse_materialized_views(xml, state)
      state = parse_procedures(xml, state)
      state = parse_functions(xml, state)
      state = parse_packages(xml, state)
      state = parse_triggers(xml, state)
      state = parse_row_counters(xml, state)

      {:ok, state}
    rescue
      e -> {:error, "Failed to parse XML: #{Exception.message(e)}"}
    end
  end

  defp parse_tables(xml, state) do
    # Extract table definitions using regex
    table_regex = ~r/<table name="([^"]*)"([^>]*)>(.*?)<\/table>/s
    column_regex = ~r/<column name="([^"]*)" type="([^"]*)"([^\/]*)\/>/
    row_regex = ~r/<row>(.*?)<\/row>/s
    field_regex = ~r/<field name="([^"]*)">(.*?)<\/field>/s

    Regex.scan(table_regex, xml)
    |> Enum.reduce(state, fn [_full, name, attrs, content], acc ->
      # Parse attributes (object_table, of_type)
      object_table = String.contains?(attrs, ~s(object_table="true"))
      of_type_match = Regex.run(~r/of_type="([^"]*)"/, attrs)
      of_type = if of_type_match, do: Enum.at(of_type_match, 1)

      # Parse columns
      columns =
        Regex.scan(column_regex, content)
        |> Enum.map(fn [_full, col_name, type_str, mods_str] ->
          type = parse_column_type(type_str)
          mods = parse_column_modifiers(mods_str)
          {col_name, type, mods}
        end)

      # Parse rows
      rows =
        Regex.scan(row_regex, content)
        |> Enum.map(fn [_full, row_content] ->
          Regex.scan(field_regex, row_content)
          |> Enum.map(fn [_full, field_name, value_xml] ->
            {field_name, parse_value(value_xml)}
          end)
          |> Enum.into(%{})
        end)

      schema =
        %{
          columns: columns,
          constraints: [],
          indexes: %{}
        }
        |> maybe_add_object_table(object_table, of_type)

      %{
        acc
        | tables: Map.put(acc.tables, name, schema),
          data: Map.put(acc.data, name, rows)
      }
    end)
  end

  defp maybe_add_object_table(schema, false, _), do: schema

  defp maybe_add_object_table(schema, true, of_type) do
    schema
    |> Map.put(:object_table, true)
    |> Map.put(:of_type, of_type)
  end

  defp parse_column_type(type_str) do
    cond do
      String.match?(type_str, ~r/^\w+\(\d+,\d+\)$/) ->
        [_, base, prec, scale] = Regex.run(~r/^(\w+)\((\d+),(\d+)\)$/, type_str)
        {String.to_atom(base), String.to_integer(prec), String.to_integer(scale)}

      String.match?(type_str, ~r/^\w+\(\d+\)$/) ->
        [_, base, size] = Regex.run(~r/^(\w+)\((\d+)\)$/, type_str)
        {String.to_atom(base), String.to_integer(size)}

      true ->
        String.to_atom(type_str)
    end
  end

  defp parse_column_modifiers(mods_str) do
    mods = []

    mods =
      if String.contains?(mods_str, ~s(primary_key="true")),
        do: [:primary_key | mods],
        else: mods

    mods =
      if String.contains?(mods_str, ~s(not_null="true")),
        do: [:not_null | mods],
        else: mods

    size_match = Regex.run(~r/size="(\d+)"/, mods_str)

    mods =
      if size_match do
        [{:size, String.to_integer(Enum.at(size_match, 1))} | mods]
      else
        mods
      end

    default_match = Regex.run(~r/default="([^"]*)"/, mods_str)

    mods =
      if default_match do
        [{:default, unescape_xml(Enum.at(default_match, 1))} | mods]
      else
        mods
      end

    mods
  end

  defp parse_value(xml) do
    cond do
      String.contains?(xml, "<null/>") ->
        nil

      String.match?(xml, ~r/<string>(.*)<\/string>/s) ->
        [_, val] = Regex.run(~r/<string>(.*)<\/string>/s, xml)
        unescape_xml(val)

      String.match?(xml, ~r/<integer>(-?\d+)<\/integer>/) ->
        [_, val] = Regex.run(~r/<integer>(-?\d+)<\/integer>/, xml)
        String.to_integer(val)

      String.match?(xml, ~r/<float>(-?[\d\.]+)<\/float>/) ->
        [_, val] = Regex.run(~r/<float>(-?[\d\.]+)<\/float>/, xml)
        String.to_float(val)

      String.match?(xml, ~r/<boolean>(true|false)<\/boolean>/) ->
        [_, val] = Regex.run(~r/<boolean>(true|false)<\/boolean>/, xml)
        val == "true"

      String.match?(xml, ~r/<date>(\d{4}-\d{2}-\d{2})<\/date>/) ->
        [_, val] = Regex.run(~r/<date>(\d{4}-\d{2}-\d{2})<\/date>/, xml)
        Date.from_iso8601!(val)

      String.match?(xml, ~r/<datetime>([^<]+)<\/datetime>/) ->
        [_, val] = Regex.run(~r/<datetime>([^<]+)<\/datetime>/, xml)
        {:ok, dt, _} = DateTime.from_iso8601(val)
        dt

      true ->
        # Try to parse as inspected term
        case Regex.run(~r/<(?:list|map|raw)>(.*)<\/(?:list|map|raw)>/s, xml) do
          [_, val] ->
            try do
              {term, _} = Code.eval_string(unescape_xml(val))
              term
            rescue
              _ -> unescape_xml(val)
            end

          nil ->
            nil
        end
    end
  end

  defp parse_sequences(xml, state) do
    seq_regex =
      ~r/<sequence name="([^"]*)" current="([^"]*)" increment="([^"]*)" min_value="([^"]*)" max_value="([^"]*)" cycle="([^"]*)" initialized="([^"]*)"/

    sequences =
      Regex.scan(seq_regex, xml)
      |> Enum.map(fn [_, name, current, increment, min_val, max_val, cycle, initialized] ->
        {name,
         %{
           current: String.to_integer(current),
           increment: String.to_integer(increment),
           min_value: String.to_integer(min_val),
           max_value: String.to_integer(max_val),
           cycle: cycle == "true",
           initialized: initialized == "true"
         }}
      end)
      |> Enum.into(%{})

    %{state | sequences: sequences}
  end

  defp parse_indexes(xml, state) do
    idx_regex = ~r/<index name="([^"]*)" table="([^"]*)" columns="([^"]*)" unique="([^"]*)"/

    indexes =
      Regex.scan(idx_regex, xml)
      |> Enum.map(fn [_, name, table, cols_str, unique] ->
        {name,
         %{
           table: table,
           columns: String.split(cols_str, ","),
           unique: unique == "true"
         }}
      end)
      |> Enum.into(%{})

    %{state | indexes: indexes}
  end

  defp parse_types(xml, state) do
    type_regex = ~r/<type name="([^"]*)" kind="([^"]*)"([^>]*)>(.*?)<\/type>/s
    attr_regex = ~r/<attribute name="([^"]*)" type="([^"]*)"/

    types =
      Regex.scan(type_regex, xml)
      |> Enum.map(fn [_, name, kind, attrs_str, content] ->
        parent_match = Regex.run(~r/parent="([^"]*)"/, attrs_str)
        parent = if parent_match, do: Enum.at(parent_match, 1)

        element_type_match = Regex.run(~r/element_type="([^"]*)"/, attrs_str)
        element_type = if element_type_match, do: parse_column_type(Enum.at(element_type_match, 1))

        max_size_match = Regex.run(~r/max_size="(\d+)"/, attrs_str)
        max_size = if max_size_match, do: String.to_integer(Enum.at(max_size_match, 1))

        attributes =
          Regex.scan(attr_regex, content)
          |> Enum.map(fn [_, attr_name, type_str] ->
            {attr_name, parse_column_type(type_str)}
          end)

        type_def =
          %{
            kind: String.to_atom(kind),
            attributes: attributes,
            methods: []
          }
          |> maybe_add_parent(parent)
          |> maybe_add_element_type(element_type)
          |> maybe_add_max_size(max_size)

        {name, type_def}
      end)
      |> Enum.into(%{})

    %{state | types: types}
  end

  defp maybe_add_parent(type_def, nil), do: type_def
  defp maybe_add_parent(type_def, parent), do: Map.put(type_def, :parent, parent)

  defp maybe_add_element_type(type_def, nil), do: type_def

  defp maybe_add_element_type(type_def, element_type),
    do: Map.put(type_def, :element_type, element_type)

  defp maybe_add_max_size(type_def, nil), do: type_def
  defp maybe_add_max_size(type_def, max_size), do: Map.put(type_def, :max_size, max_size)

  defp parse_views(xml, state) do
    view_regex = ~r/<view name="([^"]*)"([^>]*)>(.*?)<\/view>/s

    views =
      Regex.scan(view_regex, xml)
      |> Enum.map(fn [_, name, attrs, content] ->
        of_type_match = Regex.run(~r/of_type="([^"]*)"/, attrs)
        of_type = if of_type_match, do: Enum.at(of_type_match, 1)

        oid_match = Regex.run(~r/object_identifier="([^"]*)"/, attrs)

        oid =
          if oid_match do
            try do
              {term, _} = Code.eval_string(unescape_xml(Enum.at(oid_match, 1)))
              term
            rescue
              _ -> nil
            end
          end

        columns_match = Regex.run(~r/<columns>([^<]*)<\/columns>/, content)

        columns =
          if columns_match do
            try do
              {term, _} = Code.eval_string(unescape_xml(Enum.at(columns_match, 1)))
              term
            rescue
              _ -> []
            end
          else
            []
          end

        query_match = Regex.run(~r/<query>([^<]*)<\/query>/, content)

        query =
          if query_match do
            try do
              {term, _} = Code.eval_string(unescape_xml(Enum.at(query_match, 1)))
              term
            rescue
              _ -> %{}
            end
          else
            %{}
          end

        view_def =
          %{
            columns: columns,
            query: query
          }
          |> maybe_add_of_type(of_type)
          |> maybe_add_oid(oid)

        {name, view_def}
      end)
      |> Enum.into(%{})

    %{state | views: views}
  end

  defp maybe_add_of_type(view_def, nil), do: view_def
  defp maybe_add_of_type(view_def, of_type), do: Map.put(view_def, :of_type, of_type)

  defp maybe_add_oid(view_def, nil), do: view_def
  defp maybe_add_oid(view_def, oid), do: Map.put(view_def, :object_identifier, oid)

  defp parse_materialized_views(xml, state) do
    mv_regex = ~r/<materialized_view name="([^"]*)">(.*?)<\/materialized_view>/s

    mvs =
      Regex.scan(mv_regex, xml)
      |> Enum.map(fn [_, name, content] ->
        query_match = Regex.run(~r/<query>([^<]*)<\/query>/, content)

        query =
          if query_match do
            try do
              {term, _} = Code.eval_string(unescape_xml(Enum.at(query_match, 1)))
              term
            rescue
              _ -> %{}
            end
          else
            %{}
          end

        {name, %{query: query}}
      end)
      |> Enum.into(%{})

    %{state | materialized_views: mvs}
  end

  defp parse_procedures(xml, state) do
    proc_regex = ~r/<procedure name="([^"]*)">(.*?)<\/procedure>/s

    procedures =
      Regex.scan(proc_regex, xml)
      |> Enum.map(fn [_, name, content] ->
        params_match = Regex.run(~r/<parameters>([^<]*)<\/parameters>/, content)

        params =
          if params_match do
            try do
              {term, _} = Code.eval_string(unescape_xml(Enum.at(params_match, 1)))
              term
            rescue
              _ -> []
            end
          else
            []
          end

        body_match = Regex.run(~r/<body><!\[CDATA\[(.*?)\]\]><\/body>/s, content)
        body = if body_match, do: Enum.at(body_match, 1), else: ""

        {name, %{parameters: params, body: body, name: name}}
      end)
      |> Enum.into(%{})

    %{state | procedures: procedures}
  end

  defp parse_functions(xml, state) do
    func_regex = ~r/<function name="([^"]*)" return_type="([^"]*)">(.*?)<\/function>/s

    functions =
      Regex.scan(func_regex, xml)
      |> Enum.map(fn [_, name, return_type_str, content] ->
        return_type =
          try do
            {term, _} = Code.eval_string(unescape_xml(return_type_str))
            term
          rescue
            _ -> return_type_str
          end

        params_match = Regex.run(~r/<parameters>([^<]*)<\/parameters>/, content)

        params =
          if params_match do
            try do
              {term, _} = Code.eval_string(unescape_xml(Enum.at(params_match, 1)))
              term
            rescue
              _ -> []
            end
          else
            []
          end

        body_match = Regex.run(~r/<body><!\[CDATA\[(.*?)\]\]><\/body>/s, content)
        body = if body_match, do: Enum.at(body_match, 1), else: ""

        {name, %{parameters: params, body: body, return_type: return_type, name: name}}
      end)
      |> Enum.into(%{})

    %{state | functions: functions}
  end

  defp parse_packages(xml, state) do
    pkg_regex = ~r/<package name="([^"]*)">(.*?)<\/package>/s

    packages =
      Regex.scan(pkg_regex, xml)
      |> Enum.map(fn [_, name, content] ->
        spec_match = Regex.run(~r/<spec>([^<]*)<\/spec>/, content)

        spec =
          if spec_match do
            try do
              {term, _} = Code.eval_string(unescape_xml(Enum.at(spec_match, 1)))
              term
            rescue
              _ -> %{}
            end
          else
            %{}
          end

        body_match = Regex.run(~r/<body>([^<]*)<\/body>/, content)

        body =
          if body_match do
            try do
              {term, _} = Code.eval_string(unescape_xml(Enum.at(body_match, 1)))
              term
            rescue
              _ -> nil
            end
          else
            nil
          end

        pkg_def = %{spec: spec}
        pkg_def = if body, do: Map.put(pkg_def, :body, body), else: pkg_def

        {name, pkg_def}
      end)
      |> Enum.into(%{})

    %{state | packages: packages}
  end

  defp parse_triggers(xml, state) do
    trig_regex =
      ~r/<trigger name="([^"]*)" timing="([^"]*)" table="([^"]*)" level="([^"]*)" enabled="([^"]*)">(.*?)<\/trigger>/s

    triggers =
      Regex.scan(trig_regex, xml)
      |> Enum.map(fn [_, name, timing, table, level, enabled, content] ->
        events_match = Regex.run(~r/<events>([^<]*)<\/events>/, content)

        events =
          if events_match do
            try do
              {term, _} = Code.eval_string(unescape_xml(Enum.at(events_match, 1)))
              term
            rescue
              _ -> []
            end
          else
            []
          end

        when_match = Regex.run(~r/<when>([^<]*)<\/when>/, content)

        when_clause =
          if when_match do
            try do
              {term, _} = Code.eval_string(unescape_xml(Enum.at(when_match, 1)))
              term
            rescue
              _ -> nil
            end
          else
            nil
          end

        body_match = Regex.run(~r/<body><!\[CDATA\[(.*?)\]\]><\/body>/s, content)
        body = if body_match, do: Enum.at(body_match, 1), else: ""

        trigger_def =
          %{
            timing: parse_atom_or_string(timing),
            table: table,
            level: parse_atom_or_string(level),
            events: events,
            body: body,
            enabled: enabled == "true",
            name: name
          }

        trigger_def =
          if when_clause, do: Map.put(trigger_def, :when, when_clause), else: trigger_def

        {name, trigger_def}
      end)
      |> Enum.into(%{})

    %{state | triggers: triggers}
  end

  defp parse_atom_or_string(""), do: nil

  defp parse_atom_or_string(str) do
    try do
      String.to_existing_atom(str)
    rescue
      _ -> str
    end
  end

  defp parse_row_counters(xml, state) do
    counter_regex = ~r/<counter table="([^"]*)" value="(\d+)"\/>/

    counters =
      Regex.scan(counter_regex, xml)
      |> Enum.map(fn [_, table, value] ->
        {table, String.to_integer(value)}
      end)
      |> Enum.into(%{})

    %{state | row_counter: counters}
  end

  # XML escaping/unescaping

  defp escape_xml(str) when is_binary(str) do
    str
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
    |> String.replace("\"", "&quot;")
    |> String.replace("'", "&apos;")
  end

  defp escape_xml(other), do: escape_xml(to_string(other))

  defp unescape_xml(str) when is_binary(str) do
    str
    |> String.replace("&amp;", "&")
    |> String.replace("&lt;", "<")
    |> String.replace("&gt;", ">")
    |> String.replace("&quot;", "\"")
    |> String.replace("&apos;", "'")
  end

  defp unescape_xml(other), do: unescape_xml(to_string(other))
end
