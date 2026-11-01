function openMenu() {
  return document.querySelector(".sb-menu[open]");
}

function closeMenu(restoreFocus) {
  const menu = openMenu();
  if (!menu) return;

  menu.open = false;

  if (restoreFocus) {
    const summary = menu.querySelector("summary");
    if (summary) summary.focus();
  }
}

export function initChrome() {
  document.addEventListener("click", (event) => {
    const target = event.target;
    if (!target || typeof target.closest !== "function") return;

    const menu = target.closest(".sb-menu");

    if (menu) {
      if (target.closest("a")) closeMenu(false);
      return;
    }

    if (openMenu()) closeMenu(false);
  });

  document.addEventListener("keydown", (event) => {
    if (event.key !== "Escape") return;
    if (openMenu()) closeMenu(true);
  });
}
