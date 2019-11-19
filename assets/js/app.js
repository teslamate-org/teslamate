import css from "../css/app.scss";

//// Import dependencies

import "phoenix_html";

//// Import local files

import { Socket } from "phoenix";
import LiveSocket from "phoenix_live_view";
import * as hooks from "./hooks";

const liveSocket = new LiveSocket("/live", Socket, {
  hooks,
  params: {
    baseUrl: window.location.origin,
    referrer: document.referrer
  }
});
liveSocket.connect();

import "./main";
