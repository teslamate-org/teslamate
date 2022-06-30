import Darkmode from "darkmode-js";

document.querySelector(".navbar-burger").addEventListener("click", function () {
  const $target = document.getElementById(this.dataset.target);
  $target.classList.toggle("is-active");
  this.classList.toggle("is-active");
});

const defaultDark = window.matchMedia('(prefers-color-scheme: dark)').matches;
localStorage.setItem('theme', defaultDark ? 'dark' : 'light');

window.onload = function toggleDarkMode(_state) {
  const darkmode = new Darkmode();

  if (localStorage.getItem("theme") === "light" && darkmode.isActivated()) {
    darkmode.toggle();
  } else {
    darkmode.toggle();
  }
}
let element = window.matchMedia('(prefers-color-scheme: dark)');
if (element) {
  element.addEventListener("change", evt => {
    const darkmode = new Darkmode();
    if (evt.matches && !darkmode.isActivated()) {
      darkmode.toggle()
    } else {
      darkmode.toggle();
    }
  })
}

for (const navDropdown of document.querySelectorAll(
  ".navbar-item.has-dropdown"
)) {
  navDropdown.addEventListener("click", function () {
    if (document.querySelector(".navbar-menu.is-active")) {
      this.classList.toggle("active");
    }
  });
}

// Open Statistics dashboard with the browser time zone
const statistics = document.querySelector("a[data-uid='1EZnXszMk']");
const tz = Intl && Intl.DateTimeFormat().resolvedOptions().timeZone;

if (statistics && tz)
  statistics.href = `${statistics.href}?var-timezone=${decodeURIComponent(tz)}`;

// Fix sticky hover on iOS
document.addEventListener("click", () => 0);

// Address dynamic viewport units on mobile
function setCustomVh() {
  let vh = window.innerHeight * 0.01;
  document.documentElement.style.setProperty("--vh", `${vh}px`);
}

window.addEventListener("resize", setCustomVh);
setCustomVh();
