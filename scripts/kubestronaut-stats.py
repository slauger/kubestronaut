#!/usr/bin/env python3
"""Parse Kubestronaut statistics from the CNCF website.

Extracts per-country and per-region counts from the country filter
dropdown on https://www.cncf.io/training/kubestronaut/.
"""

import html
import json
import re
import sys
import urllib.request

URL = "https://www.cncf.io/training/kubestronaut/"

OPTION_RE = re.compile(
    r'<option[^>]*'
    r'data-sf-count="(?P<count>\d+)"[^>]*'
    r'data-sf-depth="(?P<depth>\d+)"[^>]*'
    r'value="(?P<value>[^"]*)"[^>]*>'
    r'(?P<label>[^<]*)</option>'
)


def fetch_html(url: str) -> str:
    req = urllib.request.Request(url, headers={"User-Agent": "kubestronaut-stats/1.0"})
    with urllib.request.urlopen(req, timeout=30) as resp:
        return resp.read().decode("utf-8")


def parse_options(page_html: str) -> list[dict]:
    entries = []
    for m in OPTION_RE.finditer(page_html):
        label = html.unescape(m.group("label")).strip()
        # Strip leading whitespace and trailing count like "(123)" or "(1,583)"
        label = re.sub(r"\s*\([\d,]+\)\s*$", "", label).strip()
        depth = int(m.group("depth"))
        count = int(m.group("count"))
        value = m.group("value")
        if not value:  # "All Countries" placeholder
            continue
        entries.append({"label": label, "depth": depth, "count": count, "code": value})
    return entries


def print_text(entries: list[dict]) -> None:
    regions = [e for e in entries if e["depth"] == 0]
    countries = [e for e in entries if e["depth"] == 1]

    global_total = sum(r["count"] for r in regions)

    print(f"{'Kubestronauts Worldwide':=^60}")
    print(f"\nTotal: {global_total}\n")

    print(f"{'By Region':->60}")
    for r in sorted(regions, key=lambda x: x["count"], reverse=True):
        print(f"  {r['label']:<40} {r['count']:>5}")

    print(f"\n{'By Country':->60}")
    for c in sorted(countries, key=lambda x: x["count"], reverse=True):
        print(f"  {c['label']:<40} {c['count']:>5}")


def print_json(entries: list[dict]) -> None:
    regions = [e for e in entries if e["depth"] == 0]
    countries = [e for e in entries if e["depth"] == 1]

    global_total = sum(r["count"] for r in regions)

    output = {
        "total": global_total,
        "regions": {r["label"]: r["count"] for r in sorted(regions, key=lambda x: x["count"], reverse=True)},
        "countries": {c["label"]: c["count"] for c in sorted(countries, key=lambda x: x["count"], reverse=True)},
    }
    json.dump(output, sys.stdout, indent=2, ensure_ascii=False)
    print()


def main() -> None:
    fmt = "text"
    if "--json" in sys.argv:
        fmt = "json"

    page_html = fetch_html(URL)
    entries = parse_options(page_html)

    if not entries:
        print("Error: no data found. The page structure may have changed.", file=sys.stderr)
        sys.exit(1)

    if fmt == "json":
        print_json(entries)
    else:
        print_text(entries)


if __name__ == "__main__":
    main()
