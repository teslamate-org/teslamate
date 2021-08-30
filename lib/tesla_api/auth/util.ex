defmodule TeslaApi.Auth.Util do
  def parse_location_header(%Tesla.Env{status: 302} = env, state) do
    {query, uri} =
      env
      |> Tesla.get_header("location")
      |> URI.parse()
      |> Map.get_and_update!(:query, &{&1, nil})

    %{"code" => code, "state" => ^state} = URI.decode_query(query)

    {:ok, {URI.to_string(uri), code}}
  end

  def random_code_verifier do
    random_string(86) |> base64_url_encode()
  end

  def challenge(value) do
    value
    |> (&:crypto.hash(:sha256, &1)).()
    |> base64_url_encode()
  end

  def random_string(length) do
    :crypto.strong_rand_bytes(length)
    |> base64_url_encode()
    |> binary_part(0, length)
  end

  defp base64_url_encode(data) do
    data
    |> Base.encode64(padding: false)
    |> String.replace("+", "-")
    |> String.replace("/", "_")
  end
end
