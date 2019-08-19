function dateToLocalTime(dateStr) {
  const date = new Date(dateStr);

  return date instanceof Date && !isNaN(date.valueOf())
    ? date.toLocaleTimeString()
    : "–";
}

export const LocalTime = {
  mounted() {
    this.el.innerText = dateToLocalTime(this.el.dataset.date);
  },

  updated() {
    this.el.innerText = dateToLocalTime(this.el.dataset.date);
  }
};
