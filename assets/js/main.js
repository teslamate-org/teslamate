document.querySelector(".navbar-burger").addEventListener("click", function() {
  const $target = document.getElementById(this.dataset.target);
  $target.classList.toggle("is-active");
  this.classList.toggle("is-active");
});

document
  .querySelector(".navbar-item.has-dropdown")
  .addEventListener("click", function() {
    if (document.querySelector(".navbar-menu.is-active")) {
      this.classList.toggle("active");
    }
  });

// Fix sticky hover on iOS
document.addEventListener("click", () => 0);

// Address dynamic viewport units on mobile
function setCustomVh() {
  let vh = window.innerHeight * 0.01;
  document.documentElement.style.setProperty("--vh", `${vh}px`);
}

window.addEventListener("resize", setCustomVh);
setCustomVh();
