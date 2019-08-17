document.addEventListener("DOMContentLoaded", () => {
  for (const el of document.querySelectorAll(".navbar-burger")) {
    el.addEventListener("click", () => {
      const $target = document.getElementById(el.dataset.target);
      $target.classList.toggle("is-active");
      el.classList.toggle("is-active");
    });
  }

  for (const el of document.querySelectorAll(".convert-time")) {
    el.innerText = dateToLocalTime(el.innerText);

    const observer = new MutationObserver(mutationList => {
      for (const mutation of mutationList) {
        if (mutation.type === "characterData")
          el.innerText = dateToLocalTime(el.innerText);
      }
    });

    observer.observe(el, {
      characterData: true,
      attributes: false,
      childList: false,
      subtree: true
    });
  }

  function dateToLocalTime(date) {
    return new Date(date).toLocaleTimeString();
  }
});
