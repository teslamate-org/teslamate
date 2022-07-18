defmodule TeslaMate.Settings.GlobalSettings do
  use Ecto.Schema
  import Ecto.Changeset

  schema "settings" do
    field :unit_of_length, Ecto.Enum, values: [:km, :mi]
    field :unit_of_temperature, Ecto.Enum, values: [:C, :F]
    field :unit_of_pressure, Ecto.Enum, values: [:bar, :psi]

    field :preferred_range, Ecto.Enum, values: [:ideal, :rated]

    field :base_url, :string
    field :grafana_url, :string

    field :language, :string

    timestamps()
  end

  @supported_languages %{
    "Albanian" => "sq",
    "Arabic" => "ar",
    "Armenian" => "hy",
    "Azerbaijani" => "az",
    "Belarusian" => "be",
    "Bosnian" => "bs",
    "Breton" => "br",
    "Bulgarian" => "bg",
    "Catalan" => "ca",
    "Chinese" => "zh",
    "Croatian" => "hr",
    "Czech" => "cs",
    "Danish" => "da",
    "Dutch" => "nl",
    "English" => "en",
    "Estonian" => "et",
    "Finnish" => "fi",
    "French" => "fr",
    "Georgian" => "ka",
    "German" => "de",
    "Greek" => "el",
    "Hebrew" => "he",
    "Hungarian" => "hu",
    "Icelandic" => "is",
    "Irish" => "ga",
    "Italian" => "it",
    "Japanese (Kana)" => "ja_kana",
    "Japanese (Latin)" => "ja-Latn",
    "Japanese" => "ja",
    "Kannada" => "kn",
    "Kazakh" => "kk",
    "Korean (Latin)" => "ko-Latn",
    "Korean" => "ko",
    "Latin" => "la",
    "Latvian" => "lv",
    "Lithuanian" => "lt",
    "Luxembourgish" => "lb",
    "Macedonian" => "mk",
    "Maltese" => "mt",
    "Norwegian" => "no",
    "Polish" => "pl",
    "Portuguese" => "pt",
    "Romania" => "ro",
    "Romansh" => "rm",
    "Russian" => "ru",
    "Scottish Gaelic" => "gd",
    "Serbian (Cyrillic)" => "sr",
    "Serbian (Latin)" => "sr-Latn",
    "Slovak" => "sk",
    "Slovene" => "sl",
    "Spanish" => "es",
    "Swedish" => "sv",
    "Thai" => "th",
    "Turkish" => "tr",
    "Ukrainian" => "uk",
    "Welsh" => "cy",
    "Western Frisian" => "fy"
  }

  def supported_languages do
    Enum.sort(@supported_languages)
  end

  @doc false
  def changeset(units, attrs) do
    units
    |> cast(attrs, [
      :unit_of_length,
      :unit_of_temperature,
      :unit_of_pressure,
      :preferred_range,
      :base_url,
      :grafana_url,
      :language
    ])
    |> validate_required([
      :unit_of_length,
      :unit_of_temperature,
      :unit_of_pressure,
      :preferred_range,
      :language
    ])
    |> update_change(:base_url, &trim_url/1)
    |> update_change(:grafana_url, &trim_url/1)
    |> validate_url(:base_url)
    |> validate_url(:grafana_url)
    |> validate_inclusion(:language, Map.values(@supported_languages), message: "is not supported")
  end

  defp trim_url(url) do
    with str when is_binary(str) <- url,
         "" <- str |> String.trim() |> String.trim_trailing("/") do
      nil
    end
  end

  def validate_url(changeset, field) do
    validate_change(changeset, field, fn _, value ->
      case URI.parse(value) do
        %URI{scheme: nil} -> [{field, "is missing a scheme (e.g. https)"}]
        %URI{scheme: scheme} when scheme not in ["http", "https"] -> [{field, "invalid scheme"}]
        %URI{host: nil} -> [{field, "is missing a host"}]
        _valid_uri -> []
      end
    end)
  end
end
