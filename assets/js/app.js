import "../css/app.scss";

import "phoenix_html";
import { Socket } from "phoenix";
import { LiveSocket } from "phoenix_live_view";

import * as hooks from "./hooks";
import "./main";
import Darkmode from "darkmode-js";

const csrfToken = document
  .querySelector("meta[name='csrf-token']")
  .getAttribute("content");

const liveSocket = new LiveSocket("/live", Socket, {
  hooks,
  params: {
    _csrf_token: csrfToken,
    baseUrl: window.location.origin,
    referrer: document.referrer,
    tz: Intl && Intl.DateTimeFormat().resolvedOptions().timeZone,
  },
});

liveSocket.connect();

// liveSocket.enableDebug();
// liveSocket.enableLatencySim(1000);
// window.liveSocket = liveSocket;


const defaultDark = window.matchMedia('(prefers-color-scheme: dark)').matches;
localStorage.setItem('theme', defaultDark ? 'dark' : 'light');

window.onload = function toggleDarkMode(_state) {
    const darkmode = new Darkmode();

    if (localStorage.getItem("theme") === "light" && darkmode.isActivated()) {
        darkmode.toggle();
        window.location.reload()
    } else if(localStorage.getItem("theme") === "dark" && !darkmode.isActivated()){
        darkmode.toggle();
        window.location.reload()
    }
}
let element = window.matchMedia('(prefers-color-scheme: dark)');
if (element) {
    element.addEventListener("change", evt => {
        const darkmode = new Darkmode();
        if (evt.matches && !darkmode.isActivated()) {
            darkmode.toggle()
            window.location.reload()
        } else {
          darkmode.toggle();
          window.location.reload()
        }
    })
}
