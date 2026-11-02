// Global search window: a native dialog over the current page. Results come
// from the read-only /api/v1 projections; the form itself submits to /search,
// so the control still works without this module.

const BOOK_LIMIT = 6;
const RECENT_LIMIT = 5;
const SIDE_LIMIT = 3;
const DEBOUNCE_MS = 180;
const EXTRAS_RETRY_MS = 30000;

let dialog = null;
let input = null;
let results = null;
let allLink = null;
let opener = null;
let controller = null;
let debounceTimer = 0;
let querySeq = 0;
let extras = { presses: [], series: [] };
let extrasLoaded = false;
let extrasPromise = null;
let extrasRetryAt = 0;

function $(selector, root) {
  return (root || document).querySelector(selector);
}

function element(tag, className, text) {
  const node = document.createElement(tag);
  if (className) node.className = className;
  if (text) node.textContent = text;
  return node;
}

function normalize(value) {
  return String(value || "")
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .toLowerCase()
    .replace(/\s+/g, " ")
    .trim();
}

function formatCount(value) {
  return Number.isFinite(value) ? new Intl.NumberFormat("en-US").format(value) : "";
}

function bookHref(slug) {
  return "/books/" + encodeURIComponent(slug);
}

function pressHref(slug) {
  return "/publishers/" + encodeURIComponent(slug);
}

function seriesHref(slug) {
  return "/series/" + encodeURIComponent(slug);
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

async function fetchJSON(url, signal) {
  const response = await fetch(url, {
    headers: { Accept: "application/json" },
    signal,
  });
  if (!response.ok) throw new Error("HTTP " + response.status);
  return response.json();
}

function loadExtras() {
  if (extrasLoaded) return Promise.resolve(extras);
  if (extrasPromise) return extrasPromise;
  if (Date.now() < extrasRetryAt) return Promise.resolve(null);

  extrasPromise = Promise.all([
    fetchJSON("/api/v1/publishers?page_size=100"),
    fetchJSON("/api/v1/series?page_size=100"),
  ])
    .then(([publishers, series]) => {
      extras = {
        presses: Array.isArray(publishers.data) ? publishers.data : [],
        series: Array.isArray(series.data) ? series.data : [],
      };
      extrasLoaded = true;
      return extras;
    })
    .catch(() => {
      extrasRetryAt = Date.now() + EXTRAS_RETRY_MS;
      return null;
    })
    .finally(() => {
      extrasPromise = null;
    });

  return extrasPromise;
}

function coverNode(book, title) {
  const wrap = element("span", "sb-result__thumb");
  const cover = safeCover(book.cover && book.cover.thumbnail_url);

  if (cover) {
    const image = document.createElement("img");
    image.src = cover;
    image.alt = "Cover for " + title;
    image.loading = "lazy";
    image.decoding = "async";
    wrap.append(image);
  } else {
    const fallback = element("span", "sb-fallback");
    fallback.setAttribute("aria-hidden", "true");
    fallback.append(element("span", "sb-fallback__title", title));
    wrap.append(fallback);
  }

  return wrap;
}

function bookRow(book) {
  const title = String(book.title || "").trim();
  const meta = [book.author, book.publisher].filter(Boolean).join(" · ");

  const row = element("a", "sb-result");
  row.href = bookHref(book.slug);
  row.append(coverNode(book, title));

  const body = element("span");
  body.append(element("b", null, title));
  if (meta) body.append(element("span", null, meta));
  row.append(body);

  return row;
}

function simpleRow(href, title, label, meta) {
  const row = element("a", "sb-result sb-result--simple");
  row.href = href;

  const body = element("span");
  body.append(element("b", null, title));
  body.append(element("span", null, [label, meta].filter(Boolean).join(" · ")));
  row.append(body);

  return row;
}

function group(label, rows) {
  const wrap = element("div", "sb-result-group");
  wrap.append(element("p", null, label));
  rows.forEach((row) => wrap.append(row));
  return wrap;
}

function emptyState(query, pending) {
  if (pending) return element("p", "sb-results__empty", "Searching the catalogue…");

  const message = element("p", "sb-results__empty");
  message.append("No books, presses, or collections match “" + query + "”.");
  return message;
}

function failureState() {
  const message = element("p", "sb-results__empty");
  message.append("Search is unavailable right now. ");

  const link = element("a", "sb-link", "Open the search page →");
  link.href = "/search";
  message.append(link);

  return message;
}

function matchingPresses(query) {
  const needle = normalize(query);
  return extras.presses
    .filter((press) => normalize(press.name).includes(needle))
    .slice(0, SIDE_LIMIT);
}

function matchingSeries(query) {
  const needle = normalize(query);
  return extras.series
    .filter((item) =>
      normalize([item.title, item.publisher].filter(Boolean).join(" ")).includes(needle)
    )
    .slice(0, SIDE_LIMIT);
}

function renderResults(query, books, side) {
  const fragment = document.createDocumentFragment();

  if (!query) {
    if (books.length) {
      fragment.append(group("Recently added", books.map(bookRow)));
    } else {
      fragment.append(
        element("p", "sb-results__empty", "No books are available in the catalogue yet.")
      );
    }
  } else {
    if (books.length) fragment.append(group("Books", books.map(bookRow)));

    if (side) {
      const presses = matchingPresses(query);
      if (presses.length) {
        fragment.append(
          group(
            "Presses",
            presses.map((press) => {
              const count = formatCount(press.editions_count);
              return simpleRow(
                pressHref(press.slug),
                press.name,
                "Press",
                count ? count + " volumes" : ""
              );
            })
          )
        );
      }

      const series = matchingSeries(query);
      if (series.length) {
        fragment.append(
          group(
            "Collections",
            series.map((item) =>
              simpleRow(seriesHref(item.slug), item.title, "Collection", item.publisher || "")
            )
          )
        );
      }
    }

    if (fragment.childElementCount === 0) {
      fragment.append(emptyState(query, side === null));
    }
  }

  results.replaceChildren(fragment);
}

function updateAllLink(query) {
  if (!allLink) return;

  if (query) {
    allLink.href = "/search?q=" + encodeURIComponent(query);
    allLink.textContent = "All results →";
  } else {
    allLink.href = "/search";
    allLink.textContent = "All books →";
  }
}

async function runSearch(value) {
  const query = String(value || "").trim();
  const seq = ++querySeq;

  if (controller) controller.abort();
  controller = new AbortController();
  const signal = controller.signal;

  updateAllLink(query);

  const params = new URLSearchParams({
    page_size: String(query ? BOOK_LIMIT : RECENT_LIMIT),
  });
  if (query) {
    params.set("q", query);
  } else {
    params.set("sort", "recently_added");
  }

  try {
    const page = await fetchJSON("/api/v1/books?" + params.toString(), signal);
    if (seq !== querySeq) return;

    const books = Array.isArray(page.data) ? page.data : [];

    if (!query) {
      renderResults("", books, null);
      return;
    }

    renderResults(query, books, extrasLoaded ? extras : undefined);

    const side = await loadExtras();
    if (seq !== querySeq) return;
    renderResults(query, books, side || null);
  } catch (error) {
    if (error.name === "AbortError" || seq !== querySeq) return;
    results.replaceChildren(failureState());
  }
}

function closeShelfDialog() {
  const shelf = $("#shelf-dialog");
  if (shelf && shelf.open && typeof shelf.close === "function") shelf.close();
}

function afterClose() {
  document.body.removeAttribute("data-dialog-open");
  if (opener && document.contains(opener)) opener.focus();
  opener = null;
}

function openSearch(trigger) {
  if (!dialog) return;
  if (dialog.open) {
    input.focus();
    return;
  }

  opener = trigger || document.activeElement;
  closeShelfDialog();

  input.value = "";
  results.replaceChildren();
  if (typeof dialog.showModal === "function") {
    dialog.showModal();
  } else {
    dialog.setAttribute("open", "");
  }
  document.body.dataset.dialogOpen = "true";
  dialog.scrollTop = 0;

  runSearch("");
  loadExtras();

  window.setTimeout(() => {
    if (dialog.open) input.focus();
  }, 30);
}

function closeSearch() {
  if (!dialog) return;

  querySeq += 1;
  window.clearTimeout(debounceTimer);
  if (controller) {
    controller.abort();
    controller = null;
  }

  if (dialog.open && typeof dialog.close === "function") {
    dialog.close();
  } else {
    dialog.removeAttribute("open");
    afterClose();
  }
}

function onDocumentClick(event) {
  const target = event.target;
  if (!target || typeof target.closest !== "function") return;

  if (target.closest("[data-search-close]")) {
    event.preventDefault();
    closeSearch();
    return;
  }

  if (target.closest("[data-shelf-open]")) {
    if (dialog && dialog.open) closeSearch();
    return;
  }

  const trigger = target.closest("[data-search-open]");
  if (!trigger) return;
  if (
    event.defaultPrevented ||
    event.button !== 0 ||
    event.metaKey ||
    event.ctrlKey ||
    event.shiftKey ||
    event.altKey
  ) {
    return;
  }

  event.preventDefault();
  openSearch(trigger);
}

function onInput() {
  const value = input.value;
  window.clearTimeout(debounceTimer);
  debounceTimer = window.setTimeout(() => runSearch(value), DEBOUNCE_MS);
}

export function initSearch() {
  dialog = document.querySelector("[data-search-dialog]");
  if (!dialog || dialog.dataset.searchBound === "true") return;

  input = $("[data-search-input]", dialog);
  results = $("[data-search-results]", dialog);
  allLink = $("[data-search-all]", dialog);
  if (!input || !results) return;

  dialog.dataset.searchBound = "true";

  document.addEventListener("click", onDocumentClick);
  input.addEventListener("input", onInput);
  input.addEventListener("search", onInput);
  dialog.addEventListener("keydown", (event) => {
    if (event.key !== "Escape") return;
    event.preventDefault();
    closeSearch();
  });
  dialog.addEventListener("click", (event) => {
    if (event.target === dialog) closeSearch();
  });
  dialog.addEventListener("close", afterClose);
}
