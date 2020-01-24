document.querySelector(".navbar-burger").addEventListener("click", function() {
  const $target = document.getElementById(this.dataset.target);
  $target.classList.toggle("is-active");
  this.classList.toggle("is-active");
});

// Fix sticky hover on iOS
document.addEventListener("click", () => 0);
