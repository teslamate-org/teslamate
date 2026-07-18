defmodule TeslaMate.LogRedactor do
  @moduledoc """
  Redacts common credential forms from text before it is persisted or displayed.

  This is a defense-in-depth allowlist of known secret shapes, not a guarantee
  that arbitrary user data is safe to publish.
  """

  @bearer_regex ~r/(?i)(\bbearer\s+)(?!\[REDACTED\])[^\s"',}\]]+/

  @authorization_regex ~r/(?i)((?<![a-z0-9_])(?:\\?["'])?authorization(?:\\?["'])?\s*+(?>=>|:|=)[ \t]*+(?:\\?["'])?)(?!\[REDACTED\])((?:(?!\\?["',}\]\r\n]).)+)(\\?["'])?/

  @key_value_regex ~r/(?i)((?<![a-z0-9_])(?:\\?["'])?(?:access|access_token|backseat_token|client_secret|database_pass|encryption_key|mqtt_password|password|pgpassword|refresh|refresh_token|secret_key_base|teslamate_operations_password|token)(?:\\?["'])?\s*+(?>=>|:|=)\s*+(?:\\?["'])?)(?!\[REDACTED(?:_JWT)?\])((?:(?!\\?["',}\]&\]\r\n]).)+)(\\?["'])?/

  @query_regex ~r/(?i)([?&](?:access_token|refresh_token|token)=)(?!\[REDACTED\])[^&#\s]+/
  @token_list_regex ~r/(?i)((?<![a-z0-9_])["']?tokens["']?\s*+(?>=>|:|=)\s*+)(?!\[REDACTED\])\[[^\]\r\n]*\]/
  @url_userinfo_regex ~r{(?i)(\b[a-z][a-z0-9+.-]*://[^/\s:@]+:)(?!\[REDACTED\]@)[^@\s/]+(@)}
  @jwt_regex ~r/\beyJ[A-Za-z0-9_-]+\.eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\b/
  @vin_regex ~r/(?i)((?<![a-z0-9_])(?:\\?["'])?vin(?:\\?["'])?\s*+(?>=>|:|=)\s*+(?:\\?["'])?)(?!\[REDACTED\])((?:(?!\\?["',}\]&\]\r\n]).)+)(\\?["'])?/

  @spec redact(binary()) :: binary()
  def redact(text) when is_binary(text) do
    text
    |> replace(@vin_regex, "\\1[REDACTED]\\3")
    |> replace(@token_list_regex, "\\1[REDACTED]")
    |> replace(@url_userinfo_regex, "\\1[REDACTED]\\2")
    |> replace(@authorization_regex, "\\1[REDACTED]\\3")
    |> replace(@bearer_regex, "\\1[REDACTED]")
    |> replace(@key_value_regex, "\\1[REDACTED]\\3")
    |> replace(@query_regex, "\\1[REDACTED]")
    |> replace(@jwt_regex, "[REDACTED_JWT]")
  end

  defp replace(text, regex, replacement), do: Regex.replace(regex, text, replacement)
end
