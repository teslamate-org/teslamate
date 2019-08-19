import css from "../css/app.scss";

//// Import dependencies

import "phoenix_html";

//// Import local files

import LiveSocket from "phoenix_live_view";
import * as hooks from "./hooks";

const liveSocket = new LiveSocket("/live", { hooks });
liveSocket.connect();

import "./main";
