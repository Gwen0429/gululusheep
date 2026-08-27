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
import html

index_path = Path(sys.argv[1])
reports_path = Path(sys.argv[2])


class ArticleParser(HTMLParser):

    def __init__(self):
        super().__init__()

        self.title_zh = ""
        self.title_en = ""
        self.date = ""

        self.in_h1 = False
        self.in_h2 = False
        self.in_time = False

    def handle_starttag(self, tag, attrs):

        if tag == "h1":
            self.in_h1 = True

        elif tag == "h2":
            classes = dict(attrs).get("class", "")
            if "article-title-en" in classes:
                self.in_h2 = True

        elif tag == "time":
            self.in_time = True

    def handle_endtag(self, tag):

        if tag == "h1":
            self.in_h1 = False

        elif tag == "h2":
            self.in_h2 = False

        elif tag == "time":
            self.in_time = False

    def handle_data(self, data):

        if self.in_h1:
            self.title_zh += data.strip()

        if self.in_h2:
            self.title_en += data.strip()

        if self.in_time:
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

    if parser.title_zh:

        articles.append({
            "file": file.name,
            "title_zh": parser.title_zh,
            "title_en": parser.title_en,
            "date": parser.date
        })


old = index_path.read_text(
    encoding="utf-8"
)

start_marker = "<!-- ARTICLES START -->"
end_marker = "<!-- ARTICLES END -->"

article_html = []

for article in articles:

    title_en_html = ""

    if article["title_en"]:
        title_en_html = f"""
            <div class="home-title-en">
                {html.escape(article["title_en"])}
            </div>
        """

    article_html.append(
        f"""
        <article class="home-entry">

            <h2>
                <a href="reports/{html.escape(article["file"])}">
                    {html.escape(article["title_zh"])}
                </a>
            </h2>

            {title_en_html}

            <time>
                {html.escape(article["date"])}
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

git commit -m "Fix bilingual publishing and clean article index" || true

git push

echo ""

echo "=============================="
echo "发布完成。"
echo "=============================="
echo ""
