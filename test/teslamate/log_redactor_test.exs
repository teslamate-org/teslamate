defmodule TeslaMate.LogRedactorTest do
  use ExUnit.Case, async: true

  alias TeslaMate.LogRedactor

  test "redacts known secret shapes" do
    jwt = "eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxMjMifQ.signature"
    escaped = ~S({\"password\":\"escaped-secret\",\"vin\":\"5YJ3E1EA7JF000003\"})

    text =
      """
      Authorization: Bearer bearer-secret
      %{token: "access-secret", refresh_token: "refresh-secret"}
      {"password":"database-secret","MQTT_PASSWORD" => "mqtt-secret"}
      SECRET_KEY_BASE=phoenix-secret
      TESLAMATE_OPERATIONS_PASSWORD=operations-secret
      https://user:proxy-secret@example.com/path?token=query-secret&ok=true
      %TeslaApi.Vehicle{vin: "5YJ3E1EA7JF000001", tokens: ["token-one", "token-two"], backseat_token: "seat-secret"}
      {"vin":"LRW3E7FA0MC000002","tokens":["token-three"],"ok":true}
      #{jwt}
      """ <> escaped

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
          "5YJ3E1EA7JF000001",
          "LRW3E7FA0MC000002",
          "token-one",
          "token-two",
          "token-three",
          "seat-secret",
          "escaped-secret",
          "5YJ3E1EA7JF000003",
          jwt
        ] do
      refute redacted =~ secret
    end

    assert redacted =~ "Authorization: [REDACTED]"
    assert redacted =~ ~s(token: "[REDACTED]")
    assert redacted =~ "https://user:[REDACTED]@example.com"
    assert redacted =~ "?token=[REDACTED]&ok=true"
    assert redacted =~ ~s(vin: "[REDACTED]")
    assert redacted =~ ~s("vin":"[REDACTED]")
    assert redacted =~ "tokens: [REDACTED]"
    assert redacted =~ ~s("tokens":[REDACTED])
    assert redacted =~ ~s(backseat_token: "[REDACTED]")
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
