defmodule OauthAzureActivedirectory.Client do
  alias OAuth2.Client
  alias OAuth2.Strategy.AuthCode
  alias OauthAzureActivedirectory.Error
  alias OauthAzureActivedirectory.Response

  @moduledoc """
  Documentation for OauthAzureActivedirectory.Client
  """
  @moduledoc since: "1.0.0"

  @doc """
  Return logout URL and set optional logout redirect URL

  """
  def logout_url do
    client = configset()[:client_id]
    tenant = configset()[:tenant]
    logout_url = "https://login.microsoftonline.com/#{tenant}/oauth2/v2.0/logout"
    logout_redirect_url = configset()[:logout_redirect_url] || configset()[:redirect_uri]

    "#{logout_url}?client_id=#{client}&post_logout_redirect_uri=#{logout_redirect_url}"
  end

  @doc """
  Return authorize URL

  """

  def authorize_url!(state) do
    code_verifier = :crypto.strong_rand_bytes(64) |> Base.url_encode64
    code_challenge = :crypto.hash(:sha256, code_verifier)  |> Base.url_encode64(padding: false)

    params = %{
      response_mode: "form_post",
      response_type: "code id_token",
      scope: configset()[:scope] || "openid email",
      code_challenge: code_challenge,
      code_challenge_method: "S256",
      code_verifier: code_verifier,
      nonce: SecureRandom.uuid
    }
    params = case state do
      nil -> params
      _ -> params |> Map.put(:state, state)
    end

    params = Map.to_list(params)

    Client.authorize_url!(client(), params)
  end

  def authorize_url(client, params) do
    params = Map.new(params)
    AuthCode.authorize_url(client, params)
  end

  def client do
  	Client.new([
      strategy: __MODULE__,
      client_id: configset()[:client_id],
      client_secret: configset()[:client_secret],
      redirect_uri: configset()[:redirect_uri],
      logout_redirect_url: configset()[:logout_redirect_url],
      authorize_url: "https://login.microsoftonline.com/#{configset()[:tenant]}/oauth2/v2.0/authorize",
      token_url: "https://login.microsoftonline.com/#{configset()[:tenant]}/oauth2/v2.0/token"
    ])
  end

  @doc """
  Validate token and return payload attributes in JWT

  """
  def callback_params(%{params: %{"id_token" => id_token, "code" => code}}) do
    claims = id_token |> String.split(".")

    header = Enum.at(claims, 0) |> Base.url_decode64!(padding: false) |> JSON.decode!
    payload = Enum.at(claims, 1) |> Base.url_decode64!(padding: false) |> JSON.decode!
    signature = Enum.at(claims, 2) |> Base.url_decode64!(padding: false)

    message = Enum.join([Enum.at(claims, 0), Enum.at(claims, 1)], ".")

    kid = Map.get(header, "kid")
    chash = Map.get(payload, "c_hash")

    valid_code? = Response.verify_code(chash, code)
    valid_client? = Response.verify_client(payload)
    valid_signature? = Response.verify_signature(message, signature, kid)

    cond do
      !valid_code? -> {:error, Error.wrap(__MODULE__, :invalid_code)}
      !valid_client? -> {:error, Error.wrap(__MODULE__, :invalid_client)}
      !valid_signature? -> {:error, Error.wrap(__MODULE__, :invalid_signature)}
      valid_code? && valid_client? && valid_signature? -> {:ok, payload}
    end
  end

  defdelegate process_callback!(params), to: __MODULE__, as: :callback_params

  defp configset() do
    OauthAzureActivedirectory.config
  end
end
