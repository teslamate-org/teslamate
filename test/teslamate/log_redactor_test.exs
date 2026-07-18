defmodule TeslaMate.LogRedactorTest do
  use ExUnit.Case, async: true

  alias TeslaMate.LogRedactor

  test "redacts known secret shapes" do
    jwt = "eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxMjMifQ.signature"

    text = """
    Authorization: Bearer bearer-secret
    %{token: "access-secret", refresh_token: "refresh-secret"}
    {"password":"database-secret","MQTT_PASSWORD" => "mqtt-secret"}
    SECRET_KEY_BASE=phoenix-secret
    TESLAMATE_OPERATIONS_PASSWORD=operations-secret
    https://user:proxy-secret@example.com/path?token=query-secret&ok=true
    #{jwt}
    """

    redacted = LogRedactor.redact(text)

    for secret <- [
          "bearer-secret",
          "access-secret",
          "refresh-secret",
          "database-secret",
          "mqtt-secret",
          "phoenix-secret",
          "operations-secret",
          "proxy-secret",
          "query-secret",
          jwt
        ] do
      refute redacted =~ secret
    end

    assert redacted =~ "Authorization: [REDACTED]"
    assert redacted =~ ~s(token: "[REDACTED])
    assert redacted =~ "https://user:[REDACTED]@example.com"
    assert redacted =~ "?token=[REDACTED]&ok=true"
    assert redacted =~ "[REDACTED_JWT]"
    assert LogRedactor.redact(redacted) == redacted

    spaced = LogRedactor.redact(~s(password="two word secret" next=visible))
    assert spaced == ~s(password="[REDACTED]" next=visible)
  end

  test "leaves ordinary operational messages unchanged" do
    message = "2026-07-18 car_id=3 [info] Driving / Ended / 12 km"
    assert LogRedactor.redact(message) == message
  end
end
