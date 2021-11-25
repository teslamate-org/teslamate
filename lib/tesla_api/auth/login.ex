defmodule TeslaApi.Auth.Login do
  import TeslaApi.Auth, only: [get: 2, post: 2, post: 3]

  alias TeslaApi.Error
  alias TeslaApi.Auth.{MFA, OwnerApi, Util}

  require Logger

  @web_client_id TeslaApi.Auth.web_client_id()
  @redirect_uri TeslaApi.Auth.redirect_uri()

  defmodule Ctx do
    @derive {Inspect, except: [:password]}
    defstruct [:email, :password, :state, :code_verifier, :cookies, :base_url]

    def new(email, password) do
      %__MODULE__{
        email: email,
        password: password,
        state: Util.random_string(15),
        code_verifier: Util.random_code_verifier(),
        cookies: nil,
        base_url: nil
      }
    end
  end

  def login(email, password) do
    ctx = Ctx.new(email, password)

    case load_form(ctx) do
      {:ok, {form, nil, ctx}} ->
        authorize(form, ctx)

      {:ok, {form, captcha, ctx}} ->
        callback = fn captcha_code -> authorize(form, captcha_code, ctx) end
        {:ok, {:captcha, captcha, callback}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp authorize(form, captcha_code \\ nil, %Ctx{} = ctx) do
    form =
      form
      |> Map.replace!("identity", ctx.email)
      |> Map.replace!("credential", ctx.password)

    form =
      if Map.has_key?(form, "captcha") and is_binary(captcha_code) do
        Map.replace!(form, "captcha", captcha_code)
      else
        form
      end

    with {:ok, %Tesla.Env{} = env} <- submit_form(form, ctx),
         {:ok, {redirect_uri, code}} <- Util.parse_location_header(env, ctx.state),
         {:ok, auth} <-
           get_web_token(code, ctx.code_verifier, redirect_uri, ctx.state, base: ctx.base_url),
         {:ok, auth} <- maybe_exchange_sso_tokens(auth) do
      {:ok, auth}
    end
  rescue
    e ->
      Logger.error(Exception.format(:error, e, __STACKTRACE__))
      {:error, %Error{reason: e, message: "An unexpected error occurred"}}
  end

  defp load_form(%Ctx{} = ctx) do
    params = [
      client_id: @web_client_id,
      redirect_uri: @redirect_uri,
      response_type: "code",
      scope: "openid email offline_access",
      code_challenge: Util.challenge(ctx.code_verifier),
      code_challenge_method: "S256",
      state: ctx.state,
      login_hint: ctx.email
    ]

    case get("/oauth2/v3/authorize", query: params) do
      {:ok, %Tesla.Env{status: 200} = env} ->
        handle_form(env, ctx)

      error ->
        Error.into(error, :authorization_request_failed)
    end
  end

  defp handle_form(%Tesla.Env{status: 200} = env, %Ctx{} = ctx) do
    document = Floki.parse_document!(env.body)

    cookies =
      env.headers
      |> Enum.filter(&match?({"set-cookie", _}, &1))
      |> Enum.map(fn {_, cookie} -> cookie |> String.split(";") |> hd() end)
      |> Enum.join("; ")

    base_url =
      URI.parse(env.url)
      |> Map.put(:path, nil)
      |> Map.put(:query, nil)
      |> URI.to_string()

    ctx = %Ctx{ctx | cookies: cookies, base_url: base_url}

    form =
      document
      |> Floki.find("form input")
      |> Map.new(fn input ->
        [key] = input |> Floki.attribute("name")
        value = input |> Floki.attribute("value") |> List.first()
        {key, value}
      end)

    case get_captcha_element(document) do
      nil ->
        {:ok, {form, nil, ctx}}

      captcha ->
        [path] = Floki.attribute(captcha, "src")

        with {:ok, captcha} <- load_captcha_image(path, cookies) do
          {:ok, {form, captcha, ctx}}
        end
    end
  end

  defp get_captcha_element(document) do
    case Floki.find(document, "[data-id=captcha]") do
      [] -> nil
      [captcha] -> captcha
    end
  end

  defp load_captcha_image(path, cookies) do
    case get(path, headers: [{"Cookie", cookies}]) do
      {:ok, %Tesla.Env{status: 200, body: captcha}} ->
        case Floki.parse_fragment(captcha) do
          {:ok, [{"svg", _, _}]} ->
            {:ok, captcha}

          {:error, reason} ->
            Logger.error("Invalid captcha: #{reason}")
            {:error, %Error{reason: :invalid_captcha}}
        end

      error ->
        Error.into(error, :captcha_could_not_be_loaded)
    end
  end

  defp submit_form(form, %Ctx{} = ctx) do
    transaction_id = Map.fetch!(form, "transaction_id")
    encoded_form = URI.encode_query(form)

    headers = [
      {"Content-Type", "application/x-www-form-urlencoded"},
      {"Cookie", ctx.cookies}
    ]

    case post("#{ctx.base_url}/oauth2/v3/authorize", encoded_form, headers: headers) do
      {:ok, %Tesla.Env{status: 200, body: body} = env} ->
        document = Floki.parse_document!(body)

        cond do
          String.contains?(body, "Your account has been locked") ->
            {:error, %Error{reason: :account_locked, env: env}}

          get_captcha_element(document) != nil ->
            case handle_form(env, ctx) do
              {:ok, {form, captcha, ctx}} when captcha != nil ->
                callback = fn captcha_code -> authorize(form, captcha_code, ctx) end
                {:ok, {:captcha, captcha, callback}}

              {:error, reason} ->
                {:error, reason}
            end

          String.contains?(body, "Captcha does not match") ->
            {:error, %Error{reason: :captcha_does_not_match, env: env}}

          String.contains?(body, "Recaptcha is required") ->
            {:error, %Error{reason: :recaptcha_required, env: env}}

          String.contains?(body, "/oauth2/v3/authorize/mfa/verify") ->
            headers = [{"referer", env.url}, {"cookie", ctx.cookies}]

            with {:ok, devices} <- MFA.list_devices(transaction_id, headers) do
              callback = fn device_id, mfa_passcode ->
                try do
                  with {:ok, env} <-
                         MFA.verify_passcode(device_id, mfa_passcode, transaction_id, headers),
                       {:ok, {redirect_uri, code}} <- Util.parse_location_header(env, ctx.state),
                       {:ok, auth} <-
                         get_web_token(code, ctx.code_verifier, redirect_uri, ctx.state),
                       {:ok, auth} <- maybe_exchange_sso_tokens(auth) do
                    {:ok, auth}
                  end
                rescue
                  e ->
                    Logger.error(Exception.format(:error, e, __STACKTRACE__))
                    {:error, %Error{reason: e, message: "An unexpected error occurred"}}
                end
              end

              {:ok, {:mfa, devices, callback}}
            end

          true ->
            {:error, %Error{reason: :mfa_input_not_found, env: env}}
        end

      {:ok, %Tesla.Env{status: 302} = env} ->
        {:ok, env}

      {:ok, %Tesla.Env{status: 401} = env} ->
        message = "Invalid email address and password combination"
        {:error, %Error{reason: :invalid_credentials, message: message, env: env}}

      {:ok, %Tesla.Env{status: 403}} = error ->
        Error.into(error, :access_denied)

      error ->
        Error.into(error, :authorization_failed)
    end
  end

  defp get_web_token(code, code_verifier, redirect_uri, state, opts \\ []) do
    data = %{
      grant_type: "authorization_code",
      client_id: @web_client_id,
      code: code,
      code_verifier: code_verifier,
      redirect_uri: redirect_uri
    }

    case post("#{opts[:base]}/oauth2/v3/token", data) do
      {:ok, %Tesla.Env{status: 200, body: %{"state" => ^state} = body}} ->
        auth = %TeslaApi.Auth{
          token: body["access_token"],
          type: body["token_type"],
          expires_in: body["expires_in"],
          refresh_token: body["refresh_token"],
          created_at: body["created_at"]
        }

        {:ok, auth}

      error ->
        Error.into(error, :web_token_error)
    end
  end

  defp maybe_exchange_sso_tokens(%TeslaApi.Auth{} = auth) do
    case TeslaApi.Auth.region(auth) do
      :chinese ->
        OwnerApi.exchange_sso_token(auth)

      _other ->
        {:ok, auth}
    end
  end
end
