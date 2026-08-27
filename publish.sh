#!/bin/bash

set -e

PROJECT="$HOME/gululusheep"
REPORTS="$PROJECT/reports"
INDEX="$PROJECT/index.html"

echo ""
echo "Gululu Sheep Publisher"
echo "----------------------"
echo ""

LATEST=$(ls -t "$HOME"/Downloads/*.html 2>/dev/null | head -1)

if [ -z "$LATEST" ]; then
    echo "没有找到 Downloads 里的文章 HTML。"
    exit 1
fi

FILENAME=$(basename "$LATEST")

echo "发现文章：$FILENAME"

cp "$LATEST" "$REPORTS/$FILENAME"

echo "已复制到 reports/"

python3 - "$INDEX" "$REPORTS" <<'PY'

from pathlib import Path
from html.parser import HTMLParser
import sys
import re

index_path = Path(sys.argv[1])
reports_path = Path(sys.argv[2])

class ArticleParser(HTMLParser):

    def __init__(self):
        super().__init__()
        self.title = ""
        self.date = ""
        self.h1 = False
        self.time = False

    def handle_starttag(self, tag, attrs):

        if tag == "h1":
            self.h1 = True

        if tag == "time":
            self.time = True

    def handle_endtag(self, tag):

        if tag == "h1":
            self.h1 = False

        if tag == "time":
            self.time = False

    def handle_data(self, data):

        if self.h1:
            self.title += data.strip()

        if self.time:
            self.date += data.strip()


articles = []

for file in sorted(
    reports_path.glob("*.html"),
    key=lambda x: x.stat().st_mtime,
    reverse=True
):

    parser = ArticleParser()

    parser.feed(
        file.read_text(encoding="utf-8")
    )

    if parser.title:

        articles.append({
            "file": file.name,
            "title": parser.title,
            "date": parser.date
        })


old = index_path.read_text(
    encoding="utf-8"
)

start_marker = "<!-- ARTICLES START -->"
end_marker = "<!-- ARTICLES END -->"

article_html = []

for article in articles:

    article_html.append(
        f"""
        <article class="home-entry">

            <h2>
                <a href="reports/{article['file']}">
                    {article['title']}
                </a>
            </h2>

            <time>
                {article['date']}
            </time>

        </article>
        """
    )

new_section = (
    start_marker
    + "\n"
    + "\n".join(article_html)
    + "\n"
    + end_marker
)

if start_marker in old and end_marker in old:

    pattern = (
        re.escape(start_marker)
        + r".*?"
        + re.escape(end_marker)
    )

    new = re.sub(
        pattern,
        new_section,
        old,
        flags=re.S
    )

else:

    new = old.replace(
        "</main>",
        new_section + "\n</main>"
    )

index_path.write_text(
    new,
    encoding="utf-8"
)

print("")
print("Home 已更新。")
print("")

PY

echo "正在上传 GitHub..."

cd "$PROJECT"

git add .

git commit -m "Publish article: $FILENAME" || true

git push

echo ""
echo "=============================="
echo "发布完成。"
echo "=============================="
echo ""
