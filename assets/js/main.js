document.addEventListener("DOMContentLoaded", () => {
  for (const el of document.querySelectorAll(".navbar-burger")) {
    el.addEventListener("click", () => {
      const $target = document.getElementById(el.dataset.target);
      $target.classList.toggle("is-active");
      el.classList.toggle("is-active");
    });
  }
});
