defmodule TeslaMateWeb.GettextPlaceholdersTest do
  use ExUnit.Case, async: true

  alias Expo.Message.{Plural, Singular}

  @po_glob Path.join(__DIR__, "../../priv/gettext/*/LC_MESSAGES/*.po")

  test "translations keep the placeholders of their msgid and use no others" do
    po_files = Path.wildcard(@po_glob)
    assert po_files != []

    violations =
      for file <- po_files,
          message <- Expo.PO.parse_file!(file).messages,
          not message.obsolete,
          violation <- violations(message) do
        [locale, "LC_MESSAGES", domain] = file |> Path.split() |> Enum.take(-3)
        "#{locale}/#{domain}: #{inspect(text(message.msgid))}: #{violation}"
      end

    assert violations == [], Enum.join(violations, "\n")
  end

  # A translated singular message uses exactly the placeholders of its msgid.
  defp violations(%Singular{msgid: msgid, msgstr: msgstr}) do
    if translated?(msgstr) do
      expected = placeholders(msgid)
      used = placeholders(msgstr)

      report("msgstr is missing", MapSet.difference(expected, used)) ++
        report("msgstr uses unknown", MapSet.difference(used, expected))
    else
      []
    end
  end

  # A single plural form may spell the number out ("one file"), and the PO file does not
  # say which placeholder carries the number. So a placeholder that both source forms
  # carry has to survive in at least one translated form, not in each of them. Every form
  # may only use placeholders of a source form or `count`, which Gettext binds itself.
  defp violations(%Plural{msgid: msgid, msgid_plural: msgid_plural, msgstr: forms}) do
    singular = placeholders(msgid)
    plural = placeholders(msgid_plural)
    allowed = singular |> MapSet.union(plural) |> MapSet.put("count")

    translated =
      for {index, msgstr} <- Enum.sort(forms), translated?(msgstr) do
        {index, placeholders(msgstr)}
      end

    used =
      Enum.reduce(translated, MapSet.new(), fn {_index, set}, acc -> MapSet.union(acc, set) end)

    required = if translated == [], do: MapSet.new(), else: MapSet.intersection(singular, plural)

    report("no msgstr form contains", MapSet.difference(required, used)) ++
      Enum.flat_map(translated, fn {index, set} ->
        report("msgstr[#{index}] uses unknown", MapSet.difference(set, allowed))
      end)
  end

  defp report(problem, placeholders) do
    case Enum.sort(placeholders) do
      [] -> []
      names -> ["#{problem} #{Enum.map_join(names, ", ", &"%{#{&1}}")}"]
    end
  end

  defp translated?(msgstr), do: text(msgstr) != ""

  defp placeholders(lines) do
    ~r/%\{([^}]+)\}/
    |> Regex.scan(text(lines), capture: :all_but_first)
    |> List.flatten()
    |> MapSet.new()
  end

  # Expo keeps every PO string as the list of its source lines.
  defp text(lines), do: IO.iodata_to_binary(lines)
end
