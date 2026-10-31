# /// script
# requires-python = ">=3.11"
# dependencies = ["scrapling", "curl-cffi", "playwright", "browserforge"]
# ///
"""Refresh the Seven Stories Press corpus from the official imprint listing.

The extractor is operator-run and uses Scrapling for the permitted public pages.
It paginates the official imprint listing, fetches each book detail page, and
emits the canonical real-publisher dataset shape. Existing records are preserved
by the additive refresh lane; this script only supplies the source candidate.

Usage:
    uv run scripts/catalog/extract_seven_stories_catalog.py --out-dir /tmp/refresh
    uv run scripts/catalog/extract_seven_stories_catalog.py --limit-pages 1 --out-dir /tmp/refresh
"""
from __future__ import annotations

import argparse
import html
import json
import re
import sys
import time
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from scrapling.fetchers import Fetcher

PROVIDER = "seven_stories_press_official_site"
PUBLISHER = "Seven Stories Press"
SOURCE_TYPE = "publisher_official_page"
LISTING_URL = "https://www.sevenstories.com/imprints/seven-stories-press"
BASE_URL = "https://www.sevenstories.com"
OUT_FILE = "seven_stories_press.json"
UA = (
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
    "AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36 "
    "Hiraeth-Seven-Stories-extractor/1.0"
)
RIGHTS = (
    "Operator-authorized public catalog refresh from official publisher pages/APIs; "
    "factual bibliographic metadata, official product descriptions, official cover URLs, "
    "purchase links, and source provenance preserved for each field."
)
FORMATS = {
    "paperback": "paperback",
    "softcover": "paperback",
    "hardcover": "hardcover",
    "hardback": "hardcover",
    "ebook": "ebook",
    "e-book": "ebook",
    "ebook (epub)": "ebook",
    "audiobook": "audiobook",
    "audio": "audiobook",
}
MERCH = re.compile(
    r"tote|sweatshirt|shirt|hoodie|mug|poster|sticker|notebook|\bbag\b|\bhat\b|\bcap\b|"
    r"t-shirt|zip-up|canvas|calendar|\bcard\b|journal|socks|\bpins?\b|patch|bookmark",
    re.I,
)


def clean(value: object | None) -> str | None:
    if value is None:
        return None
    text = re.sub(r"<[^>]+>", " ", html.unescape(str(value)))
    text = re.sub(r"\s+", " ", text).strip()
    return text or None


def fetch(url: str) -> Any:
    response = Fetcher.get(url, headers={"User-Agent": UA, "Accept": "text/html,*/*"})
    if getattr(response, "status", 200) >= 400:
        raise RuntimeError(f"GET {url} returned HTTP {response.status}")
    return response


def absolute(url: str | None) -> str | None:
    if not url:
        return None
    if url.startswith("http://") or url.startswith("https://"):
        return url
    return BASE_URL + ("" if url.startswith("/") else "/") + url


def isbn13(value: str | None) -> str | None:
    digits = re.sub(r"[^0-9]", "", value or "")
    if len(digits) != 13 or not digits.isdigit() or not digits.startswith(("978", "979")):
        return None
    total = sum((1 if index % 2 == 0 else 3) * int(digit) for index, digit in enumerate(digits[:12]))
    return digits if (10 - total % 10) % 10 == int(digits[-1]) else None


def iso_date(value: str | None) -> str | None:
    match = re.search(r"\d{4}-\d{2}-\d{2}", value or "")
    return match.group(0) if match else None


def normalize_format(value: str | None) -> str:
    lowered = (value or "").strip().lower()
    return FORMATS.get(lowered, "paperback")


def page_count(value: str | None) -> int | None:
    match = re.search(r"\d{2,4}", value or "")
    return int(match.group(0)) if match else None


def contributor_pairs(author_html: str | None) -> list[dict[str, str]]:
    contributors: list[dict[str, str]] = []
    for span in re.findall(r"<span\b[^>]*>(.*?)</span>", author_html or "", flags=re.I | re.S):
        text = clean(span) or ""
        role = "author"
        if re.search(r"\btranslated by\b", text, re.I):
            role = "translator"
        elif re.search(r"\bedited by\b", text, re.I):
            role = "editor"
        for name in re.findall(r"<a\b[^>]*>(.*?)</a>", span, flags=re.I | re.S):
            cleaned = clean(name)
            if cleaned and cleaned not in {"et al.", "and"}:
                contributors.append({"name": cleaned, "role": role})
    if not contributors:
        for name in re.findall(r"<a\b[^>]*>(.*?)</a>", author_html or "", flags=re.I | re.S):
            cleaned = clean(name)
            if cleaned:
                contributors.append({"name": cleaned, "role": "author"})
    return contributors or [{"name": "Unknown contributor", "role": "author"}]


def field_sources(source_uri: str, fields: list[str]) -> dict[str, Any]:
    return {
        field: {
            "provider": PROVIDER,
            "source_uri": source_uri,
            "source_type": SOURCE_TYPE,
            "rights_basis": RIGHTS,
        }
        for field in fields
    }


def edition_row(
    detail: Any,
    listing_title: str,
    contributors: list[dict[str, str]],
    cover_url: str | None,
    description: str | None,
    source_uri: str,
    index: int,
) -> dict[str, Any]:
    format_text = clean(detail.css("div.format p::text").get()) or "paperback"
    fmt = normalize_format(format_text)
    isbn = isbn13(clean(detail.css("div.isbn::text").get()))
    published_on = iso_date(clean(detail.css("div.publish-date::text").get()))
    pages = page_count(clean(detail.css("div.page-count::text").get()))

    displayed = ["title", "contributors", "publisher", "format"]
    if published_on:
        displayed.append("published_on")
    if isbn:
        displayed.append("isbn_13")
    if cover_url:
        displayed.append("cover")
    if description:
        displayed.append("description")
    displayed.append("storefront_url")

    edition: dict[str, Any] = {
        "title": listing_title,
        "subtitle": None,
        "format": fmt,
        "published_on": published_on,
        "isbn_13": isbn,
    }
    if pages:
        edition["page_count"] = pages
        displayed.append("page_count")

    slug = source_uri.rstrip("/").rsplit("/", 1)[-1]
    record: dict[str, Any] = {
        "source_uri": source_uri,
        "source_product_id": slug if index == 0 else f"{slug}-{fmt}",
        "source_sku": isbn,
        "publisher": PUBLISHER,
        "imprint": None,
        "work": {
            "title": listing_title,
            "subtitle": None,
            "original_title": None,
            "original_language_code": None,
            "publication_state": "published",
        },
        "edition": edition,
        "contributors": contributors,
        "displayed_fields": displayed,
        "curation": {
            "status": "approved",
            "notes": "Operator-authorized full-catalog refresh from official Seven Stories Press pages.",
        },
        "storefront_url": source_uri,
        "field_sources": field_sources(source_uri, displayed),
    }
    if description:
        record["description"] = description
    if cover_url:
        record["cover"] = {
            "source_url": cover_url,
            "provider": PROVIDER,
            "rights_basis": "local_cache_permitted",
            "attribution_text": "Cover via Seven Stories Press official source",
            "attribution_url": source_uri,
            "cache_policy": "cache_allowed",
        }
    missing: dict[str, str] = {}
    if not isbn:
        missing["isbn_13"] = "not present in source record"
    if not published_on:
        missing["published_on"] = "not present in source record"
    if not cover_url:
        record["no_cover_reason"] = "no usable cover image URL present in source record"
    if not description:
        missing["description"] = "not present in source record"
    if missing:
        record["missing_fields"] = missing
    return record


def extract_book(tile: Any) -> list[dict[str, Any]]:
    href = absolute(tile.css("div.cover a::attr(href)").get())
    title = clean(tile.css("h2 a::text").get())
    if not href or not title:
        return []

    detail = fetch(href)
    listing_title = clean(detail.css("h1.title::text").get()) or title
    author_html = tile.css("div.author").get() or ""
    contributors = contributor_pairs(author_html)
    cover_url = clean(detail.css('meta[property="og:image"]::attr(content)').get())
    description = clean(detail.css('meta[property="og:description"]::attr(content)').get())

    editions = detail.css("div.edition-metadata")
    if not editions:
        editions = [detail]

    records: list[dict[str, Any]] = []
    seen_isbns: set[str] = set()
    for index, edition in enumerate(editions):
        record = edition_row(
            edition,
            listing_title,
            contributors,
            cover_url,
            description,
            href,
            index,
        )
        isbn = record.get("edition", {}).get("isbn_13")
        if isbn and isbn in seen_isbns:
            continue
        if isbn:
            seen_isbns.add(isbn)
        records.append(record)

    # One canonical record per title; prefer an ISBN-bearing paperback.
    records.sort(
        key=lambda record: (
            0 if record.get("edition", {}).get("isbn_13") else 1,
            0 if record.get("edition", {}).get("format") == "paperback" else 1,
        )
    )
    return records[:1]


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out-dir", required=True, help="Directory for seven_stories_press.json.")
    parser.add_argument("--limit-pages", type=int, default=0, help="Stop after N listing pages.")
    args = parser.parse_args(argv)

    out_dir = Path(args.out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)

    records: list[dict[str, Any]] = []
    seen_urls: set[str] = set()
    seen_titles: set[str] = set()
    page_number = 1

    while True:
        url = LISTING_URL if page_number == 1 else f"{LISTING_URL}?page={page_number}"
        print(f"listing {url}", file=sys.stderr)
        page = fetch(url)
        tiles = page.css("div.book-tile")
        if not tiles:
            break
        for tile in tiles:
            href = absolute(tile.css("div.cover a::attr(href)").get())
            title = clean(tile.css("h2 a::text").get()) or ""
            normalized = re.sub(r"\s+", " ", title.lower()).strip()
            if (
                not href
                or href in seen_urls
                or normalized in seen_titles
                or MERCH.search(href)
                or MERCH.search(title)
            ):
                continue
            seen_urls.add(href)
            seen_titles.add(normalized)
            try:
                records.extend(extract_book(tile))
            except Exception as error:  # noqa: BLE001 - operator report, keep going
                print(f"warning: failed {href}: {error}", file=sys.stderr)
            time.sleep(0.35)
        if args.limit_pages and page_number >= args.limit_pages:
            break
        page_number += 1
        time.sleep(0.5)

    existing_permissions: dict[str, Any] | None = None
    existing_path = Path("priv/catalog_sources/real_publishers/seven_stories_press.json")
    if existing_path.exists():
        try:
            existing_permissions = json.loads(existing_path.read_text()).get("provider_permissions")
        except Exception:  # noqa: BLE001
            existing_permissions = None

    permissions = existing_permissions or {
        "provider": PROVIDER,
        "source_urls": [LISTING_URL],
        "source_hosts": ["www.sevenstories.com"],
        "cover_hosts": ["sevenstories-prod.s3.amazonaws.com", "covers.openlibrary.org"],
        "permission_basis": RIGHTS,
        "cover_cache_policy": "cache_allowed",
        "excluded_content": ["cart_checkout_account", "inventory_state", "prices", "user_reviews"],
        "takedown_contact": "https://www.sevenstories.com/pg/about",
        "not_legal_advice": "Operator-authorized ingestion policy and provenance metadata; not legal advice.",
    }

    records.sort(
        key=lambda record: (
            str(record.get("work", {}).get("title", "")).lower(),
            str(record.get("edition", {}).get("format", "")),
            str(record.get("edition", {}).get("isbn_13") or ""),
        )
    )

    dataset = {
        "provider": PROVIDER,
        "retrieved_at": datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z"),
        "license_note": RIGHTS,
        "provider_permissions": permissions,
        "records": records,
    }

    output = out_dir / OUT_FILE
    output.write_text(json.dumps(dataset, ensure_ascii=False, indent=2) + "\n")
    print(json.dumps({"provider": PROVIDER, "records": len(records), "output": str(output)}, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
