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
GOLDEN_URL = "https://www.cncf.io/training/kubestronaut/?_sfm_lf_person_golden=1"

COUNTRY_SELECT_RE = re.compile(
    r'<select[^>]*name="_sft_lf-country[^"]*"[^>]*>(.*?)</select>',
    re.DOTALL,
)

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
    select_match = COUNTRY_SELECT_RE.search(page_html)
    search_html = select_match.group(1) if select_match else page_html

    entries = []
    for m in OPTION_RE.finditer(search_html):
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


def print_text(entries: list[dict], golden: bool = False) -> None:
    regions = [e for e in entries if e["depth"] == 0]
    countries = [e for e in entries if e["depth"] == 1]

    global_total = sum(r["count"] for r in regions)

    title = "Golden Kubestronauts Worldwide" if golden else "Kubestronauts Worldwide"
    print(f"{title:=^60}")
    print(f"\nTotal: {global_total}\n")

    print(f"{'By Region':->60}")
    for r in sorted(regions, key=lambda x: x["count"], reverse=True):
        print(f"  {r['label']:<40} {r['count']:>5}")

    print(f"\n{'By Country':->60}")
    for c in sorted(countries, key=lambda x: x["count"], reverse=True):
        print(f"  {c['label']:<40} {c['count']:>5}")


def print_json(entries: list[dict], golden: bool = False) -> None:
    regions = [e for e in entries if e["depth"] == 0]
    countries = [e for e in entries if e["depth"] == 1]

    global_total = sum(r["count"] for r in regions)

    output = {
        "type": "golden" if golden else "all",
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

    golden = "--golden" in sys.argv
    url = GOLDEN_URL if golden else URL

    page_html = fetch_html(url)
    entries = parse_options(page_html)

    if not entries:
        print("Error: no data found. The page structure may have changed.", file=sys.stderr)
        sys.exit(1)

    if fmt == "json":
        print_json(entries, golden=golden)
    else:
        print_text(entries, golden=golden)


if __name__ == "__main__":
    main()
