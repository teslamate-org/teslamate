defmodule TeslaMate.Vault do
  use Cloak.Vault,
    otp_app: :teslamate

  defmodule Encrypted.Binary do
    use Cloak.Ecto.Binary, vault: TeslaMate.Vault
  end

  require Logger

  # With AES.GCM, 12-byte IV length is necessary for interoperability reasons.
  # See https://github.com/danielberkompas/cloak/issues/93
  @iv_length 12

  @doc """
  The default cipher used to encrypt values is AES-265 in GCM mode.

  A random IV is generated for every encryption, and prepends the key tag, IV,
  and ciphertag to the beginning of the ciphertext:

  +----------------------------------------------------------+----------------------+
  |                          HEADER                          |         BODY         |
  +-------------------+---------------+----------------------+----------------------+
  | Key Tag (n bytes) | IV (12 bytes) | Ciphertag (16 bytes) | Ciphertext (n bytes) |
  +-------------------+---------------+----------------------+----------------------+
            |_________________________________
                                              |
  +---------------+-----------------+-------------------+
  | Type (1 byte) | Length (1 byte) | Key Tag (n bytes) |
  +---------------+-----------------+-------------------+

  The `Key Tag` component of the header consists of a `Type`, `Length`, and
  `Value` triplet for easy decoding.

  For more information see `Cloak.Ciphers.AES.GCM`.
  """
  def default_chipher(key) do
    {Cloak.Ciphers.AES.GCM, tag: "AES.GCM.V1", key: key, iv_length: @iv_length}
  end

  def encryption_key_provided? do
    case get_encryption_key_from_config() do
      {:ok, _key} -> true
      :error -> false
    end
  end

  @impl GenServer
  def init(config) do
    encryption_key =
      with :error <- get_encryption_key_from_config(),
           :error <- get_encryption_key_from(System.tmp_dir()),
           :error <- get_encryption_key_from(import_dir()) do
        key_length = 48 + :rand.uniform(16)
        random_key = generate_random_key(key_length)

        Logger.warning("""
        \n------------------------------------------------------------------------------
        No ENCRYPTION_KEY was found to encrypt and securly store your API tokens.

        Therefore, the following randomly generated key will be used instead for this
        session:


        #{pad(random_key, 80)}


        Create an environment variable named "ENCRYPTION_KEY" with the value set to
        the key above (or choose your own) and pass it to the application from now on.

        OTHERWISE, A LOGIN WITH YOUR API TOKENS WILL BE REQUIRED AFTER EVERY RESTART!
        ------------------------------------------------------------------------------
        """)

        random_key
      else
        {:ok, key} -> key
      end

    config =
      Keyword.put(config, :ciphers,
        default: default_chipher(:crypto.hash(:sha256, encryption_key))
      )

    {:ok, config}
  end

  defp pad(string, width) do
    case String.length(string) do
      len when len < width ->
        string
        |> String.pad_leading(div(width - len, 2) + len)
        |> String.pad_trailing(width)

      _ ->
        string
    end
  end

  defp get_encryption_key_from_config do
    Application.get_env(:teslamate, TeslaMate.Vault)
    |> Access.fetch!(:key)
    |> case do
      key when is_binary(key) and byte_size(key) > 0 -> {:ok, key}
      _ -> :error
    end
  end

  # the database migration writes the generated key into a tmp dir and a local
  # 'import' dir if possible. The latter is likely a persistent volume for a
  # lot of users of the Docker image.
  # see priv/migrations/20220123131732_encrypt_api_tokens.exs
  defp get_encryption_key_from(dir) do
    with dir when is_binary(dir) <- dir,
         path = Path.join(dir, "tm_encryption.key"),
         {:ok, encryption_key} <- File.read(path) do
      Logger.info("""
      Restored encryption key from #{path}:

      #{encryption_key}
      """)

      {:ok, encryption_key}
    else
      _ -> :error
    end
  end

  defp import_dir do
    path =
      System.get_env("IMPORT_DIR", "import")
      |> Path.absname()

    if File.exists?(path), do: path
  end

  defp generate_random_key(length) when length > 31 do
    :crypto.strong_rand_bytes(length) |> Base.encode64(padding: false) |> binary_part(0, length)
  end
end
