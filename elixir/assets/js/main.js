document.querySelector(".navbar-burger").addEventListener("click", function () {
  const $target = document.getElementById(this.dataset.target);
  $target.classList.toggle("is-active");
  this.classList.toggle("is-active");
});

for (const navDropdown of document.querySelectorAll(
  ".navbar-item.has-dropdown",
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

// Theme handling
function applyTheme() {
  const themeMode = document.documentElement.getAttribute("data-theme-mode");
  let actualTheme = themeMode;

  // If theme mode is "system", check system preference
  if (themeMode === "system") {
    actualTheme = window.matchMedia("(prefers-color-scheme: dark)").matches
      ? "dark"
      : "light";
  }

  // Apply the theme
  document.documentElement.setAttribute("data-theme", actualTheme);

  // Trigger a custom event for components that need to react to theme changes
  window.dispatchEvent(
    new CustomEvent("themechange", { detail: { theme: actualTheme } }),
  );
}

// Apply theme on load
applyTheme();

// Listen for system theme changes when in system mode
if (window.matchMedia) {
  window
    .matchMedia("(prefers-color-scheme: dark)")
    .addEventListener("change", () => {
      const themeMode =
        document.documentElement.getAttribute("data-theme-mode");
      if (themeMode === "system") {
        applyTheme();
      }
    });
}
