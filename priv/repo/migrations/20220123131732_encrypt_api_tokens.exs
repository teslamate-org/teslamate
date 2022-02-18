defmodule TeslaMate.Repo.Migrations.EncryptApiTokens do
  use Ecto.Migration

  Code.ensure_loaded!(TeslaMate.Vault)

  defmodule Encrypted.Binary do
    use Cloak.Ecto.Binary, vault: TeslaMate.Vault
  end

  defmodule Tokens do
    use Ecto.Schema

    schema "tokens" do
      field(:refresh, :string)
      field(:access, :string)

      field(:encrypted_refresh, Encrypted.Binary)
      field(:encrypted_access, Encrypted.Binary)
    end
  end

  defmodule Encryption do
    def setup do
      {type, key} =
        case System.get_env("ENCRYPTION_KEY") do
          key when is_binary(key) and byte_size(key) > 0 -> {:existing, key}
          _ -> {:generated, generate_key(64)}
        end

      setup_vault(key)

      {type, key}
    end

    defp generate_key(length) when length > 31 do
      :crypto.strong_rand_bytes(length) |> Base.encode64(padding: false) |> binary_part(0, length)
    end

    defp setup_vault(key) do
      Cloak.Vault.save_config(TeslaMate.Vault.Config,
        ciphers: [
          default: TeslaMate.Vault.default_chipher(:crypto.hash(:sha256, key))
        ]
      )
    end
  end

  defmodule Cache do
    require Logger

    def store(encryption_key) do
      Enum.each([System.tmp_dir(), import_dir()], fn dir ->
        with dir when is_binary(dir) <- dir,
             path = Path.join(dir, "tm_encryption.key"),
             :ok <- File.write(path, encryption_key) do
          Logger.info("Wrote encryption key to #{path}")
        end
      end)
    end

    defp import_dir do
      path =
        System.get_env("IMPORT_DIR", "import")
        |> Path.absname()

      if File.exists?(path), do: path
    end
  end

  alias TeslaMate.Repo

  def change do
    alter table(:tokens) do
      add :encrypted_refresh, :binary
      add :encrypted_access, :binary
    end

    flush()

    with [_ | _] = tokens <- Repo.all(Tokens) do
      with {:generated, encryption_key} <- Encryption.setup() do
        require Logger

        Logger.warning("""
        \n------------------------------------------------------------------------------
        No ENCRYPTION_KEY was found to encrypt and securly store your API tokens.

        Therefore, the following randomly generated key will be used instead:


                #{encryption_key}


        IMPORTANT: Create an environment variable named "ENCRYPTION_KEY" with the value
        set to the key above and pass it to the application from now on.

        If you choose to use a different key, a new login with your API tokens will be
        required once after starting the application.
        ------------------------------------------------------------------------------
        """)

        Cache.store(encryption_key)
      end

      Enum.each(tokens, fn %Tokens{} = tokens ->
        tokens
        |> Ecto.Changeset.change(%{
          encrypted_access: tokens.access,
          encrypted_refresh: tokens.refresh
        })
        |> Repo.update!()
      end)
    end

    alter table(:tokens) do
      remove :access
      remove :refresh
    end

    rename table(:tokens), :encrypted_access, to: :access
    rename table(:tokens), :encrypted_refresh, to: :refresh
  end
end
