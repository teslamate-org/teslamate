document.addEventListener("DOMContentLoaded", () => {
  for (const el of document.querySelectorAll(".navbar-burger")) {
    el.addEventListener("click", () => {
      const $target = document.getElementById(el.dataset.target);
      $target.classList.toggle("is-active");
      el.classList.toggle("is-active");
    });
  }

  for (const el of document.querySelectorAll(".convert-date")) {
    el.innerText = dateToLocal(el.innerText);

    const observer = new MutationObserver(mutationList => {
      for (const mutation of mutationList) {
        if (mutation.type === "characterData")
          el.innerText = dateToLocal(el.innerText);
      }
    });

    observer.observe(el, {
      characterData: true,
      attributes: false,
      childList: false,
      subtree: true
    });
  }

  function dateToLocal(date) {
    return new Date(date).toLocaleTimeString();
  }
});
