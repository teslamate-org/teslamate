import css from "../css/app.scss";

//// Import dependencies

import "phoenix_html";

//// Import local files

import LiveSocket from "phoenix_live_view";

const liveSocket = new LiveSocket("/live");
liveSocket.connect();

import "./main";
