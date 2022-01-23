defmodule TeslaMate.VaultTest do
  use ExUnit.Case, async: false

  alias TeslaMate.Vault

  import Mock

  defp key_equals?(key) do
    {_cipher_module, cipher_opts} =
      Vault.Config
      |> Cloak.Vault.read_config()
      |> Access.fetch!(:ciphers)
      |> Access.fetch!(:default)

    :crypto.hash(:sha256, key) == cipher_opts[:key]
  end

  setup context do
    keys = context[:encryption_key] || %{}

    config = Application.get_env(:teslamate, TeslaMate.Vault)
    Application.put_env(:teslamate, TeslaMate.Vault, Keyword.put(config, :key, keys[:config]))
    on_exit(fn -> Application.put_env(:teslamate, TeslaMate.Vault, config) end)

    if encryption_key = keys[:tmp_dir] || keys[:import_dir] do
      tmp_dir = context[:tmp_dir] || raise "Add a :tmp_dir tag!"
      tmp_path = Path.join(tmp_dir, "tm_encryption.key")
      File.write!(tmp_path, encryption_key)
    end

    :ok
  end

  @tag encryption_key: %{config: "key_from_config"}
  test "reads the encryption key from the application config" do
    start_supervised!(Vault)

    assert key_equals?("key_from_config")
  end

  @tag encryption_key: %{tmp_dir: "key_from_tmp_dir"},
       tmp_dir: "0"
  test "falls back to reading the encryption key from the tmp dir", %{tmp_dir: tmp_dir} do
    with_mock System, [], tmp_dir: fn -> tmp_dir end do
      start_supervised!(Vault)

      assert key_equals?("key_from_tmp_dir")
      assert called(System.tmp_dir())
    end
  end

  @tag encryption_key: %{import_dir: "key_from_import_dir"},
       tmp_dir: "0"
  test "falls back to reading the encryption key from the import dir", %{tmp_dir: tmp_dir} do
    with_mock System, [],
      tmp_dir: fn -> nil end,
      get_env: fn "IMPORT_DIR", "import" -> tmp_dir end do
      start_supervised!(Vault)

      assert key_equals?("key_from_import_dir")
      assert called(System.get_env("IMPORT_DIR", "import"))
    end
  end

  @tag :capture_log
  test "generates a random key if no key could be restored" do
    start_supervised!(Vault)

    assert {:ok, ciphertext} = Vault.encrypt("plaintext")
    assert {:ok, "plaintext"} = Vault.decrypt(ciphertext)

    # Restart GenServer
    stop_supervised!(Vault)
    start_supervised!(Vault)

    # decrytping the ciphertext won't work with the new key
    assert {:ok, :error} = Vault.decrypt(ciphertext)
  end

  describe "encryption_key_provided?/0" do
    @tag encryption_key: %{config: "key"}
    test "returns true if the encryption key was provided via the application config" do
      start_supervised!(Vault)

      assert Vault.encryption_key_provided?()
    end

    @tag :capture_log
    @tag encryption_key: %{config: nil}
    test "returns false if the encryption key was not provided" do
      start_supervised!(Vault)

      refute Vault.encryption_key_provided?()
    end
  end

  describe "default_chipher/1" do
    test "uses AES in GCM mode with a 12 byte IV-length" do
      assert {Cloak.Ciphers.AES.GCM, [tag: "AES.GCM.V1", key: "$key", iv_length: 12]} ==
               Vault.default_chipher("$key")
    end
  end
end
