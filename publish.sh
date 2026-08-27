#!/bin/bash

set -e

PROJECT="$HOME/gululusheep"
REPORTS="$PROJECT/reports"
INDEX="$PROJECT/index.html"

echo ""
echo "Gululu Sheep"
echo "------------"
echo ""

python3 - "$INDEX" "$REPORTS" <<'PY'
from pathlib import Path
from html import escape
import sys

index_path = Path(sys.argv[1])
reports_path = Path(sys.argv[2])

pdfs = sorted(
    reports_path.glob("*.pdf"),
    key=lambda p: p.name.lower()
)

links = []

for pdf in pdfs:
    filename = pdf.name
    href = "reports/" + filename
    links.append(
        f'        <a class="pdf-link" href="{escape(href, quote=True)}">{escape(filename)}</a>'
    )

new_section = "\n".join(links)

old = index_path.read_text(encoding="utf-8")

start = "<!-- ARTICLES START -->"
end = "<!-- ARTICLES END -->"

before = old.split(start, 1)[0]
after = old.split(end, 1)[1]

new = (
    before
    + start
    + "\n"
    + new_section
    + "\n        "
    + end
    + after
)

index_path.write_text(new, encoding="utf-8")

print(f"发现 {len(pdfs)} 个 PDF。")

for pdf in pdfs:
    print(f"  {pdf.name}")

print("")
print("Home 已更新。")
PY

echo ""
echo "正在上传 GitHub..."
echo ""

cd "$PROJECT"

git add index.html reports

if git diff --cached --quiet; then
    echo "没有新的变化。"
    exit 0
fi

git commit -m "Update PDF publications"
git push

echo ""
echo "=============================="
echo "发布完成。"
echo "=============================="
echo ""
