defmodule WeGoNext.Accounts.SecretBox do
  @moduledoc """
  Encrypts local settings secrets before they are stored.
  """

  alias Plug.Crypto.{KeyGenerator, MessageEncryptor}

  @salt "we_go_next local settings secret box"
  @aad "we_go_next"

  def encrypt(value) when is_binary(value) do
    {:ok, MessageEncryptor.encrypt(value, secret(), @aad)}
  end

  def decrypt(value) when is_binary(value) do
    MessageEncryptor.decrypt(value, secret(), @aad)
  end

  def decrypt(_value), do: :error

  defp secret do
    :we_go_next
    |> Application.fetch_env!(WeGoNextWeb.Endpoint)
    |> Keyword.fetch!(:secret_key_base)
    |> KeyGenerator.generate(@salt)
  end
end
