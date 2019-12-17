import css from "../css/app.scss";

import "phoenix_html";
import { Socket } from "phoenix";
import LiveSocket from "phoenix_live_view";

import * as hooks from "./hooks";

new LiveSocket("/live", Socket, {
  hooks,
  params: {
    baseUrl: window.location.origin,
    referrer: document.referrer
  }
}).connect();

import "./main";
