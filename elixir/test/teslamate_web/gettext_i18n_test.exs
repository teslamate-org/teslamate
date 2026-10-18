defmodule TeslaMateWeb.GettextI18nTest do
  use ExUnit.Case, async: true

  @italian_catalog Path.expand("../../priv/gettext/it/LC_MESSAGES/default.po", __DIR__)

  test "Italian gettext catalog has no empty active translations" do
    missing =
      @italian_catalog
      |> File.read!()
      |> String.split(~r/\n{2,}/)
      |> Enum.reject(&obsolete?/1)
      |> Enum.flat_map(&missing_translations/1)

    assert missing == [],
           "Missing Italian gettext translations:\n" <>
             Enum.map_join(missing, "\n", &"  - #{inspect(&1)}")
  end

  defp obsolete?(block) do
    block
    |> String.trim_leading()
    |> String.starts_with?("#~")
  end

  defp missing_translations(block) do
    lines = String.split(block, "\n")
    msgid = po_field(lines, "msgid")

    cond do
      is_nil(msgid) or msgid == "" ->
        []

      true ->
        translations = po_translations(lines)

        required_forms =
          if po_field(lines, "msgid_plural") do
            ["msgstr[0]", "msgstr[1]"]
          else
            ["msgstr"]
          end

        if Enum.any?(required_forms, &(Map.get(translations, &1) in [nil, ""])) do
          [msgid]
        else
          []
        end
    end
  end

  defp po_field(lines, prefix) do
    case Enum.find_index(lines, &String.starts_with?(&1, prefix <> " ")) do
      nil ->
        nil

      index ->
        lines
        |> po_value_at(index, prefix)
    end
  end

  defp po_translations(lines) do
    lines
    |> Enum.with_index()
    |> Enum.filter(fn {line, _index} -> Regex.match?(~r/^msgstr(?:\[\d+\])?\s+/, line) end)
    |> Map.new(fn {line, index} ->
      prefix = line |> String.split(" ", parts: 2) |> hd()
      {prefix, po_value_at(lines, index, prefix)}
    end)
  end

  defp po_value_at(lines, index, prefix) do
    [first | rest] = Enum.drop(lines, index)
    first = String.replace_prefix(first, prefix <> " ", "")
    continuation = Enum.take_while(rest, &String.starts_with?(&1, "\""))

    [first | continuation]
    |> Enum.map(&Jason.decode!/1)
    |> Enum.join()
  end
end
