defmodule TeslaMate.Characterization.JsonNumber do
  @moduledoc """
  A number of a JSON MQTT payload, kept as its token: the notation is part of
  the payload ("-5.38e-4" is not "-0.000538" to a consumer that reads plain
  decimals), so the golden pins the token, not the decoded value. Encoding
  writes the token back verbatim, so a recorded golden holds it as a JSON
  number.
  """

  @enforce_keys [:token]
  defstruct [:token]

  @type t :: %__MODULE__{token: String.t()}

  @doc """
  Decodes JSON like `Jason.decode/1`, with every number as its token.
  """
  @spec decode(String.t()) :: {:ok, term()} | {:error, Jason.DecodeError.t()}
  def decode(json) do
    # Jason validates the document and yields the values in document order;
    # the tokens are then read from the text in the same order.
    with {:ok, decoded} <- Jason.decode(json, objects: :ordered_objects) do
      {value, []} = put_tokens(decoded, tokens(json, []))
      {:ok, value}
    end
  end

  defp put_tokens(%Jason.OrderedObject{values: values}, tokens) do
    {values, tokens} =
      Enum.map_reduce(values, tokens, fn {key, value}, tokens ->
        {value, tokens} = put_tokens(value, tokens)
        {{key, value}, tokens}
      end)

    {Map.new(values), tokens}
  end

  defp put_tokens(list, tokens) when is_list(list),
    do: Enum.map_reduce(list, tokens, &put_tokens/2)

  defp put_tokens(number, [token | tokens]) when is_number(number),
    do: {%__MODULE__{token: token}, tokens}

  defp put_tokens(value, tokens), do: {value, tokens}

  # The number tokens of a valid JSON text in document order: outside strings
  # only numbers start with a minus or a digit.
  defp tokens(<<?", rest::binary>>, acc), do: rest |> skip_string() |> tokens(acc)

  defp tokens(<<char, _::binary>> = json, acc) when char == ?- or char in ?0..?9 do
    [token] = Regex.run(~r/\A-?\d+(?:\.\d+)?(?:[eE][-+]?\d+)?/, json)
    size = byte_size(token)
    tokens(binary_part(json, size, byte_size(json) - size), [token | acc])
  end

  defp tokens(<<_char, rest::binary>>, acc), do: tokens(rest, acc)
  defp tokens(<<>>, acc), do: Enum.reverse(acc)

  defp skip_string(<<?\\, _escaped, rest::binary>>), do: skip_string(rest)
  defp skip_string(<<?", rest::binary>>), do: rest
  defp skip_string(<<_char, rest::binary>>), do: skip_string(rest)

  defimpl Jason.Encoder do
    def encode(%{token: token}, _opts), do: token
  end

  defimpl Inspect do
    def inspect(%{token: token}, _opts), do: "#JsonNumber<" <> token <> ">"
  end
end
