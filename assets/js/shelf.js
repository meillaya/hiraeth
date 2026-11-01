const STORAGE_KEY = "hiraeth-shelf-v1";
const MAX_ITEMS = 200;
const MAX_TEXT = 300;

let memoryShelf = [];
let memoryOnly = false;
let bound = false;

function $(selector, root) {
  return (root || document).querySelector(selector);
}

function $$(selector, root) {
  return Array.prototype.slice.call((root || document).querySelectorAll(selector));
}

function element(tag, className) {
  const node = document.createElement(tag);
  if (className) node.className = className;
  return node;
}

function cleanText(value, limit) {
  if (typeof value !== "string") return "";
  return value
    .replace(/[\u0000-\u001f\u007f]/g, " ")
    .replace(/\s+/g, " ")
    .trim()
    .slice(0, limit || MAX_TEXT);
}

function safeCover(value) {
  if (typeof value !== "string" || !value) return "";
  try {
    const url = new URL(value, window.location.origin);
    if (url.origin !== window.location.origin) return "";
    if (!url.pathname.startsWith("/covers/cache/")) return "";
    return url.pathname + url.search;
  } catch (error) {
    return "";
  }
}

function normalizeRecord(value) {
  if (!value || typeof value !== "object") return null;

  const slug = cleanText(value.slug, 180);
  const title = cleanText(value.title, MAX_TEXT);
  if (!slug || !title) return null;

  const formats = Array.isArray(value.formats)
    ? value.formats
        .map((format) => cleanText(format, 40))
        .filter(Boolean)
        .slice(0, 6)
    : [];

  const year = /^\d{4}$/.test(String(value.year || "")) ? String(value.year) : "";

  return {
    slug,
    title,
    author: cleanText(value.author, MAX_TEXT),
    publisher: cleanText(value.publisher, MAX_TEXT),
    publisherSlug: cleanText(value.publisherSlug, 180),
    year,
    cover: safeCover(value.cover),
    formats,
    isbn: cleanText(value.isbn, 40),
    savedAt: typeof value.savedAt === "string" ? cleanText(value.savedAt, 40) : "",
  };
}

function readShelf() {
  if (memoryOnly) return memoryShelf.slice();

  let raw;
  try {
    raw = window.localStorage.getItem(STORAGE_KEY);
  } catch (error) {
    memoryOnly = true;
    return memoryShelf.slice();
  }

  if (raw === null) {
    memoryShelf = [];
    return [];
  }

  let parsed;
  try {
    parsed = JSON.parse(raw);
  } catch (error) {
    memoryShelf = [];
    return [];
  }

  if (!Array.isArray(parsed)) {
    memoryShelf = [];
    return [];
  }

  const seen = new Set();
  const items = [];

  for (const entry of parsed) {
    const record = normalizeRecord(entry);
    if (!record || seen.has(record.slug)) continue;
    seen.add(record.slug);
    items.push(record);
    if (items.length >= MAX_ITEMS) break;
  }

  memoryShelf = items.slice();
  return items;
}

function writeShelf(items) {
  const bounded = items.slice(0, MAX_ITEMS);
  memoryShelf = bounded.slice();

  try {
    window.localStorage.setItem(STORAGE_KEY, JSON.stringify(bounded));
  } catch (error) {
    memoryOnly = true;
  }
}

function bookHref(slug) {
  return "/books/" + encodeURIComponent(slug);
}

function pressHref(slug) {
  return "/publishers/" + encodeURIComponent(slug);
}

function absoluteBookUrl(slug) {
  return window.location.origin + bookHref(slug);
}

function announce(message) {
  const live = $("#shelf-live");
  if (!live) return;
  live.textContent = "";
  window.requestAnimationFrame(() => {
    live.textContent = message;
  });
}

function coverNode(record) {
  if (record.cover) {
    const image = document.createElement("img");
    image.src = record.cover;
    image.alt = "Cover for " + record.title;
    image.loading = "lazy";
    image.decoding = "async";
    return image;
  }

  const fallback = element("span", "sb-fallback");
  const press = element("span", "sb-fallback__press");
  press.textContent = record.publisher || "Publisher unknown";
  const title = element("span", "sb-fallback__title");
  title.textContent = record.title;
  const author = element("span", "sb-fallback__author");
  author.textContent = record.author || "";
  fallback.append(press, title, author);
  return fallback;
}

function updateCounts(items) {
  const count = items.length;

  $$("[data-shelf-count]").forEach((node) => {
    node.textContent = String(count);
  });

}

function renderDialog(items) {
  const list = $("[data-shelf-list]");
  if (!list) return;

  list.replaceChildren();

  if (items.length === 0) {
    const empty = element("div", "sb-shelf-empty");
    const message = element("p");
    message.textContent = "Nothing saved yet. Open a record and choose Save to shelf.";
    const browse = element("a");
    browse.href = "/browse";
    browse.textContent = "Browse the catalogue →";
    empty.append(message, browse);
    list.append(empty);
    return;
  }

  items.forEach((record) => {
    const row = element("div", "sb-shelf-item");

    const thumb = element("span", "sb-shelf-item__thumb");
    thumb.append(coverNode(record));

    const body = element("span");
    const bold = document.createElement("b");
    const titleLink = element("a");
    titleLink.href = bookHref(record.slug);
    titleLink.textContent = record.title;
    bold.append(titleLink);
    const meta = element("span");
    meta.textContent = [record.author, record.publisher].filter(Boolean).join(" · ");
    body.append(bold, meta);

    const remove = element("button", "sb-shelf-item__remove");
    remove.type = "button";
    remove.dataset.removeShelf = record.slug;
    remove.setAttribute("aria-label", "Remove " + record.title + " from shelf");
    remove.textContent = "Remove";

    row.append(thumb, body, remove);
    list.append(row);
  });
}

function pad(value) {
  return String(value).padStart(2, "0");
}

function renderShelfPage(items) {
  const page = $("[data-shelf-page]");
  if (!page) return;

  const list = $("#shelf-page-list");
  const listbar = $("#shelf-listbar");
  const empty = $("[data-shelf-empty]");
  const exportButton = $("[data-shelf-export]");
  const total = $("[data-shelf-total]");
  const totalLabel = $("[data-shelf-total-label]");

  if (total) total.textContent = String(items.length);
  if (totalLabel) totalLabel.textContent = items.length === 1 ? "book" : "books";
  if (exportButton) exportButton.hidden = items.length === 0;

  if (!list) return;

  list.replaceChildren();

  if (items.length === 0) {
    list.hidden = true;
    if (listbar) listbar.hidden = true;
    if (empty) empty.hidden = false;
    return;
  }

  list.hidden = false;
  if (listbar) listbar.hidden = false;
  if (empty) empty.hidden = true;

  items.forEach((record, index) => {
    const row = element("article", "sb-shelf-row");

    const number = element("span", "sb-shelf-row__no");
    number.textContent = pad(index + 1);

    const coverLink = element("a", "sb-shelf-row__cover");
    coverLink.href = bookHref(record.slug);
    coverLink.tabIndex = -1;
    coverLink.setAttribute("aria-hidden", "true");
    coverLink.append(coverNode(record));

    const body = element("div", "sb-shelf-row__body");
    const heading = document.createElement("h3");
    const titleLink = element("a");
    titleLink.href = bookHref(record.slug);
    titleLink.textContent = record.title;
    heading.append(titleLink);
    body.append(heading);

    if (record.author) {
      const author = element("p", "sb-shelf-row__author");
      author.textContent = record.author;
      body.append(author);
    }

    const meta = element("p", "sb-shelf-row__meta");
    if (record.publisher) {
      if (record.publisherSlug) {
        const press = element("a");
        press.href = pressHref(record.publisherSlug);
        press.textContent = record.publisher;
        meta.append(press);
      } else {
        const press = element("span");
        press.textContent = record.publisher;
        meta.append(press);
      }
    }

    if (record.year) {
      if (meta.childElementCount > 0) {
        const separator = element("span");
        separator.setAttribute("aria-hidden", "true");
        separator.textContent = "/";
        meta.append(separator);
      }
      const year = element("span");
      year.textContent = record.year;
      meta.append(year);
    }

    if (record.formats.length > 0) {
      if (meta.childElementCount > 0) {
        const separator = element("span", "sb-shelf-row__sep--formats");
        separator.setAttribute("aria-hidden", "true");
        separator.textContent = "/";
        meta.append(separator);
      }
      const formats = element("span", "sb-shelf-row__formats");
      formats.textContent = record.formats.join(", ");
      meta.append(formats);
    }

    if (meta.childElementCount > 0) body.append(meta);

    const actions = element("div", "sb-shelf-row__actions");
    const open = element("a", "sb-link");
    open.href = bookHref(record.slug);
    open.textContent = "Open record →";
    const remove = element("button");
    remove.type = "button";
    remove.dataset.removeShelf = record.slug;
    remove.setAttribute("aria-label", "Remove " + record.title + " from shelf");
    remove.textContent = "Remove";
    actions.append(open, remove);

    row.append(number, coverLink, body, actions);
    list.append(row);
  });
}

function refreshSaveButtons(items) {
  const saved = new Set(items.map((item) => item.slug));

  $$("[data-save]").forEach((button) => {
    const slug = button.dataset.saveSlug;
    if (!slug) return;

    const isSaved = saved.has(slug);
    const label = $("[data-save-label]", button);
    const title = button.dataset.saveTitle || "this book";

    button.setAttribute("aria-pressed", String(isSaved));
    button.setAttribute(
      "aria-label",
      isSaved ? "Saved: " + title + ". Remove from shelf." : "Save to shelf: " + title
    );
    if (label) label.textContent = isSaved ? "Saved" : "Save to shelf";
  });
}

function renderAll() {
  const items = readShelf();
  bindDialog();
  updateCounts(items);
  renderDialog(items);
  renderShelfPage(items);
  refreshSaveButtons(items);
  markCurrentShelfNav();
}

function markCurrentShelfNav() {
  const onShelf = window.location.pathname === "/shelf";

  $$('a[href="/shelf"]').forEach((link) => {
    if (onShelf) {
      link.setAttribute("aria-current", "page");
    } else {
      link.removeAttribute("aria-current");
    }
  });
}

function currentRecordCover() {
  const image = $("#book-detail-shell .sb-record__cover img");
  if (!image) return "";
  return image.currentSrc || image.src || "";
}

function recordFromButton(button) {
  const data = button.dataset;
  return normalizeRecord({
    slug: data.saveSlug,
    title: data.saveTitle,
    author: data.saveAuthor,
    publisher: data.savePublisher,
    publisherSlug: data.savePublisherSlug,
    year: data.saveYear,
    formats: (data.saveFormats || "")
      .split(",")
      .map((format) => format.trim())
      .filter(Boolean),
    isbn: data.saveIsbn,
    cover: currentRecordCover(),
    savedAt: new Date().toISOString(),
  });
}

function toggleSave(record) {
  if (!record) return;

  const items = readShelf();
  const index = items.findIndex((item) => item.slug === record.slug);
  const removing = index !== -1;

  if (removing) {
    items.splice(index, 1);
  } else {
    items.unshift(record);
  }

  writeShelf(items);
  renderAll();
  announce(
    removing
      ? "Removed " + record.title + " from your shelf."
      : "Saved " + record.title + " to your shelf."
  );
}

function toggleBySlug(slug) {
  const items = readShelf();
  const record = items.find((item) => item.slug === slug);
  if (record) toggleSave(record);
}

function closeOpenMenu() {
  const menu = $(".sb-menu[open]");
  if (menu) menu.open = false;
}

function openShelf() {
  renderAll();

  const dialog = $("[data-shelf-dialog]");
  if (!dialog || dialog.open) return;

  closeOpenMenu();

  try {
    if (typeof dialog.showModal === "function") {
      dialog.showModal();
    } else {
      dialog.setAttribute("open", "");
    }
    document.body.dataset.dialogOpen = "true";
  } catch (error) {
    dialog.setAttribute("open", "");
    document.body.dataset.dialogOpen = "true";
  }
}

function closeShelf() {
  const dialog = $("[data-shelf-dialog]");
  if (!dialog) return;

  if (dialog.open && typeof dialog.close === "function") {
    dialog.close();
  } else {
    dialog.removeAttribute("open");
    document.body.removeAttribute("data-dialog-open");
  }
}

function longDate(date) {
  return date.toLocaleDateString("en-GB", {
    day: "numeric",
    month: "long",
    year: "numeric",
  });
}

function isoDate(date) {
  const month = pad(date.getMonth() + 1);
  const day = pad(date.getDate());
  return date.getFullYear() + "-" + month + "-" + day;
}

function exportShelf() {
  const items = readShelf();
  if (items.length === 0) return;

  const now = new Date();
  const lines = [
    "Hiraeth — reading list",
    "Exported " + longDate(now),
    items.length + (items.length === 1 ? " book" : " books"),
    "",
  ];

  items.forEach((record, index) => {
    lines.push(index + 1 + ". " + record.title);
    if (record.author) lines.push("   " + record.author);
    const imprint = [record.publisher, record.year].filter(Boolean).join(" · ");
    if (imprint) lines.push("   " + imprint);
    if (record.isbn) lines.push("   ISBN " + record.isbn);
    lines.push("   " + absoluteBookUrl(record.slug));
    lines.push("");
  });

  lines.push("Collected from Hiraeth.");

  const blob = new Blob([lines.join("\n")], { type: "text/plain;charset=utf-8" });
  const url = URL.createObjectURL(blob);
  const link = document.createElement("a");
  link.href = url;
  link.download = "hiraeth-reading-list-" + isoDate(now) + ".txt";
  document.body.append(link);
  link.click();
  link.remove();
  window.setTimeout(() => URL.revokeObjectURL(url), 1000);
}

function onDocumentClick(event) {
  const target = event.target;
  if (!target || typeof target.closest !== "function") return;

  const opener = target.closest("[data-shelf-open]");
  if (opener) {
    event.preventDefault();
    openShelf();
    return;
  }

  const closer = target.closest("[data-shelf-close]");
  if (closer) {
    event.preventDefault();
    closeShelf();
    return;
  }

  const save = target.closest("[data-save]");
  if (save) {
    event.preventDefault();
    toggleSave(recordFromButton(save));
    return;
  }

  const remove = target.closest("[data-remove-shelf]");
  if (remove) {
    event.preventDefault();
    toggleBySlug(remove.dataset.removeShelf);
    return;
  }

  const exportButton = target.closest("[data-shelf-export]");
  if (exportButton) {
    event.preventDefault();
    exportShelf();
  }
}

function bindDialog() {
  const dialog = $("[data-shelf-dialog]");
  if (!dialog || dialog.dataset.shelfDialogBound === "true") return;

  dialog.dataset.shelfDialogBound = "true";

  dialog.addEventListener("click", (event) => {
    if (event.target === dialog) closeShelf();
  });

  dialog.addEventListener("close", () => {
    document.body.removeAttribute("data-dialog-open");
  });

  dialog.addEventListener("cancel", () => {
    document.body.removeAttribute("data-dialog-open");
  });
}

export function initShelf() {
  if (bound) return;
  bound = true;

  document.addEventListener("click", onDocumentClick);
  bindDialog();

  window.addEventListener("storage", (event) => {
    if (event.key === null || event.key === STORAGE_KEY) renderAll();
  });

  window.addEventListener("pageshow", renderAll);
  window.addEventListener("phx:page-loading-stop", renderAll);

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", renderAll, { once: true });
  } else {
    renderAll();
  }
}
