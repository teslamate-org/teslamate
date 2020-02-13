import "../css/app.scss";

import "phoenix_html";
import { Socket } from "phoenix";
import LiveSocket from "phoenix_live_view";

import * as hooks from "./hooks";

const csrfToken = document
  .querySelector("meta[name='csrf-token']")
  .getAttribute("content");

new LiveSocket("/live", Socket, {
  hooks,
  params: {
    _csrf_token: csrfToken,
    baseUrl: window.location.origin,
    referrer: document.referrer,
    tz: Intl && Intl.DateTimeFormat().resolvedOptions().timeZone
  }
}).connect();

import "./main";
