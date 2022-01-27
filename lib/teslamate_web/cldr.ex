defmodule TeslaMateWeb.Cldr do
  use Cldr,
    gettext: TeslaMateWeb.Gettext,
    locales: [],
    otp_app: :teslamate,
    providers: [],
    generate_docs: false,
    force_locale_download: Mix.env() == :prod and System.get_env("SKIP_LOCALE_DOWNLOAD") != "true"
end
