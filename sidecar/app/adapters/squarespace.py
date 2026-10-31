import asyncio
import re
import unicodedata
from typing import Any
from urllib.parse import parse_qs, urlencode, urlsplit, urlunsplit

import httpx

from app.adapters.squarespace_images import absolute_url, listing_cover_urls, usable_cover_url

_EXCLUDED_CATEGORIES = {"bundles", "gift cards", "gift card", "merch", "sideline"}
_EXCLUDED_KEYWORDS = ("bundle", "subscription", "subscriber", "gift card")
_HEADERS = {"user-agent": "Mozilla/5.0 HiraethSidecar/1.0"}
_EBOOK_TITLE_SUFFIX = re.compile(
    r"\s*(?:\((?:e-?book)\)|(?:[-–—]\s*)?e-?book(?:\s*\([^)]*\))?)\s*$",
    re.IGNORECASE,
)


def _build_field_sources(provider: str, source_uri: str) -> dict[str, Any]:
    basis = (
        "Operator-authorized public catalog refresh from official publisher pages/APIs; "
        "factual bibliographic metadata, official product descriptions, official cover URLs, "
        "purchase links, and source provenance preserved for each field."
    )
    return {
        "title": {
            "provider": provider,
            "source_uri": source_uri,
            "source_type": "publisher_dataset",
            "rights_basis": basis,
        },
        "contributors": {
            "provider": provider,
            "source_uri": source_uri,
            "source_type": "publisher_dataset",
            "rights_basis": basis,
        },
        "publisher": {
            "provider": provider,
            "source_uri": source_uri,
            "source_type": "publisher_dataset",
            "rights_basis": basis,
        },
        "format": {
            "provider": provider,
            "source_uri": source_uri,
            "source_type": "publisher_dataset",
            "rights_basis": basis,
        },
        "published_on": {
            "provider": provider,
            "source_uri": source_uri,
            "source_type": "publisher_dataset",
            "rights_basis": basis,
        },
        "isbn_13": {
            "provider": provider,
            "source_uri": source_uri,
            "source_type": "publisher_dataset",
            "rights_basis": basis,
        },
        "cover": {
            "provider": provider,
            "source_uri": source_uri,
            "source_type": "publisher_dataset",
            "rights_basis": basis,
        },
        "description": {
            "provider": provider,
            "source_uri": source_uri,
            "source_type": "publisher_dataset",
            "rights_basis": basis,
        },
        "storefront_url": {
            "provider": provider,
            "source_uri": source_uri,
            "source_type": "publisher_dataset",
            "rights_basis": basis,
        },
        "subjects": {
            "provider": provider,
            "source_uri": source_uri,
            "source_type": "publisher_dataset",
            "rights_basis": basis,
        },
    }


def _first_isbn_from_variants(item: dict[str, Any]) -> str:
    structured_content = item.get("structuredContent", {})
    variants = (
        structured_content.get("variants", []) if isinstance(structured_content, dict) else []
    )
    for variant in variants:
        if not isinstance(variant, dict):
            continue
        sku = str(variant.get("sku") or "").replace("-", "").strip()
        if len(sku) == 13 and sku.isdigit():
            return sku
    return ""


def _primary_variant_id(item: dict[str, Any]) -> str:
    structured_content = item.get("structuredContent", {})
    variants = (
        structured_content.get("variants", []) if isinstance(structured_content, dict) else []
    )
    for variant in variants:
        if isinstance(variant, dict):
            variant_id = str(variant.get("id") or "").strip()
            if variant_id:
                return variant_id
    return ""


def _is_book_item(item: dict[str, Any]) -> bool:
    categories = [str(category).strip().lower() for category in item.get("categories") or []]
    if any(category in _EXCLUDED_CATEGORIES for category in categories):
        return False

    haystack = " ".join(
        [
            str(item.get("title") or "").lower(),
            str(item.get("urlId") or "").lower(),
            " ".join(categories),
        ]
    )
    if any(keyword in haystack for keyword in _EXCLUDED_KEYWORDS):
        return False

    return True


def _cover_url(item: dict[str, Any], listing_cover_urls: dict[str, str] | None = None) -> str:
    item_id = str(item.get("id") or "")
    if listing_cover_urls and item_id in listing_cover_urls:
        return listing_cover_urls[item_id]

    assets = item.get("assets", [])
    for asset in assets or []:
        if isinstance(asset, dict) and asset.get("mediaType", "").startswith("image"):
            cover = asset.get("absoluteUrl", "") or asset.get("assetUrl", "")
            if usable_cover_url(cover):
                return str(cover)

    asset_url = item.get("assetUrl")
    if usable_cover_url(asset_url):
        return str(asset_url)

    structured_content = item.get("structuredContent", {})
    main_image = (
        structured_content.get("mainImage", {}) if isinstance(structured_content, dict) else {}
    )
    if isinstance(main_image, dict):
        cover = main_image.get("absoluteUrl", "") or main_image.get("assetUrl", "")
        if usable_cover_url(cover):
            return str(cover)

    return ""


def _author_from_excerpt(excerpt: str) -> str:
    match = re.search(r"<h[1-6][^>]*>(.*?)</h[1-6]>", excerpt, flags=re.IGNORECASE | re.DOTALL)
    if match:
        text = re.sub(r"<[^>]+>", " ", match.group(1))
        return re.sub(r"\s+", " ", text).strip()

    for paragraph in re.findall(r"<p\b[^>]*>(.*?)</p>", excerpt, flags=re.I | re.S):
        text = _strip_html(paragraph) or ""
        byline = re.match(
            r"^(?:by|edited by|translated by)\s+"
            r"(.+?)(?:\s*,\s*translated\b|\s*,\s*edited\b|\s*,\s*by\b|$)",
            text,
            flags=re.I,
        )
        if byline:
            return byline.group(1).strip()

    text = _strip_html(excerpt) or ""
    byline = re.search(
        r"\bby\b\s+([A-ZÀ-Ž][\wÀ-ž.'-]+(?:\s+[A-ZÀ-Ž][\wÀ-ž.'-]+){0,4})",
        text,
        flags=re.I,
    )
    return byline.group(1).strip() if byline else ""


_AUTHOR_BYLINE_RE = re.compile(
    r"\b(?:translated|edited|introduction|foreword|afterword|chapbook|anthology)\b",
    re.IGNORECASE,
)
_AUTHOR_MAX_LENGTH = 120


def _clean_author(value: str) -> str:
    """Reject excerpt text that the byline regex mistook for a person's name."""
    text = re.sub(r"\s+", " ", str(value or "")).strip(" ,;:-")
    if not text or len(text) > _AUTHOR_MAX_LENGTH or _AUTHOR_BYLINE_RE.search(text):
        return ""
    return text


def _isbn_from_text(value: str | None) -> str:
    for match in re.finditer(r"(?<!\d)(97[89](?:[\s-]?\d){10})(?!\d)", value or ""):
        digits = re.sub(r"[^0-9]", "", match.group(1))
        if len(digits) == 13:
            return digits
    return ""


def _strip_html(raw_html: str | None) -> str | None:
    if not raw_html:
        return None
    text = re.sub(r"<[^>]+>", " ", raw_html)
    text = re.sub(r"\s+", " ", text).strip()
    return text if text else None


def _canonical_title(title: str) -> str:
    return _EBOOK_TITLE_SUFFIX.sub("", title).strip()


_EDITION_SUFFIX_RE = re.compile(
    r"\s*(?:"
    r"[\(\[][^)\]]*\b(?:paperback|hardcover|print|e-?book|ebook|epub|pdf|chapbook|digital)\b[^)\]]*[\)\]]"
    r"|[-–—]\s*(?:e-?book|ebook|epub|pdf|print|digital)\b(?:\s*\([^)]*\))?"
    r")\s*$",
    re.IGNORECASE,
)


def _strip_edition_suffixes(value: str) -> str:
    previous = None
    while previous != value:
        previous = value
        value = _EDITION_SUFFIX_RE.sub("", value)
        value = re.sub(r"\s*[-–—]\s*out of print\s*$", "", value, flags=re.IGNORECASE)
    return value


def _clean_display_title(value: str) -> str:
    text = re.sub(r"\s+", " ", str(value or "")).strip(" ,;:-")
    return re.sub(r"\s+:\s*", ": ", text)


def _work_title(title: str) -> str:
    """Display title for a work: no format decoration, no doubled spacing."""
    return _clean_display_title(_strip_edition_suffixes(str(title or "")))


def _title_key(title: str) -> str:
    value = unicodedata.normalize("NFKC", _work_title(title))
    value = value.replace("\u2019", "'").replace("\u2018", "'")
    value = re.split(r"\s*:\s+", value, maxsplit=1)[0]
    return re.sub(r"[^0-9a-z]+", " ", value.lower()).strip()


def _match_print_entry(
    index: dict[str, tuple[str, str, str]], title: str
) -> tuple[str, str, str] | None:
    key = _title_key(title)
    if not key:
        return None

    if key in index:
        return index[key]

    candidates = [
        candidate
        for candidate in index
        if candidate.startswith(key + " ") or key.startswith(candidate + " ")
    ]
    if len(candidates) == 1:
        return index[candidates[0]]

    return None


def _with_json_format(endpoint: str) -> str:
    parsed = urlsplit(endpoint)
    query = parse_qs(parsed.query)
    query["format"] = ["json"]
    return urlunsplit(
        (parsed.scheme, parsed.netloc, parsed.path, urlencode(query, doseq=True), parsed.fragment)
    )


def _item_source_uri(item: dict[str, Any], endpoint: str) -> str:
    full_url = item.get("fullUrl", "")
    if full_url:
        return absolute_url(endpoint, str(full_url))
    return f"{endpoint}/{item.get('id', '')}"


async def _print_cover_index(
    client: httpx.AsyncClient,
    cover_source: dict[str, Any],
    max_bytes: int,
) -> dict[str, tuple[str, str, str]]:
    """Build title -> (work title, cover URL, product page) from a print listing.

    The manifest names one print category per provider (for example Tilted Axis
    `/shop?category=print`). That listing is the canonical cover source; ebook
    products inherit the print cover instead of advertising their own image.
    Any failure is a miss: the adapter then keeps the record's own cover.
    """
    cover_endpoint = str(cover_source.get("endpoint") or "").strip()
    if not cover_endpoint:
        return {}

    try:
        response = await client.get(_with_json_format(cover_endpoint), headers=_HEADERS)
        if response.status_code >= 400 or len(response.content) > max_bytes:
            return {}

        listing_response = await client.get(cover_endpoint, headers=_HEADERS)
        html_cover_urls = (
            listing_cover_urls(listing_response.text, cover_endpoint)
            if listing_response.status_code < 400 and len(listing_response.content) <= max_bytes
            else {}
        )

        data = response.json()
        collection = data.get("collection", {})
        if isinstance(collection, dict) and collection.get("items"):
            items = collection["items"]
        else:
            items = data.get("items", [])

        index: dict[str, tuple[str, str, str]] = {}
        for item in items:
            if not _is_book_item(item):
                continue

            cover_url = _cover_url(item, html_cover_urls)
            key = _title_key(str(item.get("title") or ""))
            if cover_url and key:
                index.setdefault(
                    key,
                    (
                        _work_title(str(item.get("title") or "")),
                        cover_url,
                        _item_source_uri(item, cover_endpoint),
                    ),
                )

        return index
    except Exception:
        return {}


_PRINT_FORMATS = {"paperback", "hardcover"}


def _align_print_metadata(record: dict[str, Any], index: dict[str, tuple[str, str, str]]) -> None:
    """Make the print listing canonical for its work's title and print cover.

    Format products on the same shop often decorate titles differently
    ("Capitalists Must Starve" vs "Capitalists Must Starve: A Novel" vs
    "... (paperback)"). Grouping by the decorated title would split one book
    into several works. The declared print listing supplies the work title and
    the print cover; non-print records keep their own cover only so a
    digital-only work still has one, and the read policy always prefers the
    print edition when the work has one.
    """
    match = _match_print_entry(index, str(record["work"].get("title") or ""))
    if match is None:
        return

    print_title, cover_url, source_uri = match
    record["work"]["title"] = print_title

    if record["edition"]["format"] not in _PRINT_FORMATS:
        return

    record["cover"]["source_url"] = cover_url
    record["cover"]["attribution_url"] = source_uri
    record["field_sources"]["cover"]["source_uri"] = source_uri
    record.pop("no_cover_reason", None)

    if "cover" not in record["displayed_fields"]:
        record["displayed_fields"].append("cover")


def _format_from_item(item: dict[str, Any], custom_format: Any) -> str:
    if custom_format:
        return str(custom_format).strip().lower()

    categories = {str(category).strip().lower() for category in item.get("categories") or []}
    if "digital" in categories:
        return "ebook"
    if "print" in categories:
        return "paperback"

    structured_content = item.get("structuredContent", {})
    if isinstance(structured_content, dict) and structured_content.get("productType") == 2:
        return "ebook"

    return "paperback"


def _item_to_record(
    item: dict[str, Any],
    provider: str,
    endpoint: str,
    publisher_name: str | None = None,
    listing_cover_urls: dict[str, str] | None = None,
) -> dict[str, Any]:
    full_url = item.get("fullUrl", "")
    source_uri = (
        absolute_url(endpoint, full_url) if full_url else f"{endpoint}/{item.get('id', '')}"
    )
    title = _work_title(str(item.get("title", "")))
    body = item.get("body", "") or item.get("excerpt", "")
    description = _strip_html(body)
    custom_content = item.get("customContent", {})
    custom_isbn = custom_content.get("isbn", "") if isinstance(custom_content, dict) else ""
    isbn = (
        str(custom_isbn).replace("-", "").strip()
        or _first_isbn_from_variants(item)
        or _isbn_from_text(_strip_html(body))
    )
    author = custom_content.get("author", "") if isinstance(custom_content, dict) else ""
    if not author and isinstance(body, str):
        author = _author_from_excerpt(body)
    author = _clean_author(author)
    custom_format = custom_content.get("format", "") if isinstance(custom_content, dict) else ""
    fmt = _format_from_item(item, custom_format)
    published_on = custom_content.get("publishedOn", "") if isinstance(custom_content, dict) else ""
    if published_on and isinstance(published_on, str):
        published_on = published_on[:10]

    cover_url = _cover_url(item, listing_cover_urls)
    variant_id = _primary_variant_id(item)

    contributors = []
    if author:
        contributors.append({"name": author, "role": "author"})

    record: dict[str, Any] = {
        "provider": provider,
        "source_uri": source_uri,
        "source_product_id": f"{item.get('id', '')}-{variant_id or 'default'}",
        "source_sku": isbn,
        "publisher": publisher_name or provider,
        "imprint": None,
        "work": {
            "title": title,
            "subtitle": None,
            "original_title": None,
            "publication_state": "published",
        },
        "edition": {
            "title": title,
            "subtitle": None,
            "format": fmt,
            "published_on": published_on or None,
            "isbn_13": isbn if isbn and len(isbn.replace("-", "")) == 13 else None,
        },
        "contributors": contributors,
        "displayed_fields": _displayed_fields(published_on, isbn, cover_url, description),
        "curation": {
            "status": "approved",
            "notes": (
                "Operator-authorized full-catalog refresh from public source; generated "
                "deterministically with field provenance."
            ),
        },
        "storefront_url": source_uri,
        "field_sources": _build_field_sources(provider, source_uri),
        "cover": {
            "source_url": cover_url,
            "provider": provider,
            "rights_basis": "local_cache_permitted",
            "attribution_text": "Cover via official source",
            "attribution_url": source_uri,
            "cache_policy": "cache_allowed",
        },
        "description": description,
    }

    if not cover_url:
        record["no_cover_reason"] = "no usable cover image URL present in source record"

    if not record["edition"]["isbn_13"]:
        record["missing_fields"] = {"isbn_13": "not present in source record"}
        record["displayed_fields"] = [f for f in record["displayed_fields"] if f != "isbn_13"]

    tags = item.get("tags", [])
    if tags:
        record["work"]["subjects"] = [str(t) for t in tags]
        if "subjects" not in record["displayed_fields"]:
            record["displayed_fields"].append("subjects")

    return record


def _displayed_fields(
    published_on: str | None,
    isbn: str | None,
    cover_url: str | None,
    description: str | None,
) -> list[str]:
    fields = ["title", "contributors", "publisher", "format", "storefront_url"]
    fields += [
        field
        for field, value in (
            ("published_on", published_on),
            ("isbn_13", isbn),
            ("cover", cover_url),
            ("description", description),
        )
        if value
    ]
    return fields


async def fetch(config: dict[str, Any]) -> list[dict[str, Any]]:
    endpoint = config["api"]["endpoint"].rstrip("/")
    provider = config.get("provider", "unknown")
    publisher_name = config.get("publisher_name")
    rate_limit = config.get("rate_limit", {})
    min_delay_ms = rate_limit.get("min_delay_ms", 0)
    max_bytes = rate_limit.get("max_bytes", 10 * 1024 * 1024)

    async with httpx.AsyncClient() as client:
        url = _with_json_format(endpoint)
        response = await client.get(url, headers=_HEADERS)
        response.raise_for_status()

        if len(response.content) > max_bytes:
            return []

        data = response.json()

        listing_response = await client.get(endpoint, headers=_HEADERS)
        html_cover_urls = (
            listing_cover_urls(listing_response.text, endpoint)
            if listing_response.status_code < 400 and len(listing_response.content) <= max_bytes
            else {}
        )
        collection = data.get("collection", {})
        if isinstance(collection, dict) and collection.get("items"):
            items = collection["items"]
        else:
            items = data.get("items", [])

        cover_source = config.get("cover_source")
        print_covers = (
            await _print_cover_index(client, cover_source, max_bytes)
            if isinstance(cover_source, dict)
            else {}
        )

        records: list[dict[str, Any]] = []
        for item in items:
            if not _is_book_item(item):
                continue
            record = _item_to_record(item, provider, endpoint, publisher_name, html_cover_urls)
            if print_covers:
                _align_print_metadata(record, print_covers)
            if record["contributors"]:
                records.append(record)

        if min_delay_ms:
            await asyncio.sleep(min_delay_ms / 1000)

    return records
