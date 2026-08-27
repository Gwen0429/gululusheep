#!/bin/bash

set -e

PROJECT="$HOME/gululusheep"
REPORTS="$PROJECT/reports"
INDEX="$PROJECT/index.html"
DOWNLOADS="$HOME/Downloads"

echo ""
echo "Gululu Sheep Publisher"
echo "----------------------"
echo ""

# 找到 Downloads 中最新的 HTML 文件
LATEST=$(find "$DOWNLOADS" -maxdepth 1 -type f -name "*.html" -print0 2>/dev/null \
    | xargs -0 ls -t 2>/dev/null \
    | head -1)

if [ -z "$LATEST" ]; then
    echo "没有找到 Downloads 里的文章 HTML。"
    exit 1
fi

echo "发现文章：$(basename "$LATEST")"

# 从 HTML 中读取中文标题、英文标题和日期
python3 - "$LATEST" "$REPORTS" "$INDEX" <<'PY'
from pathlib import Path
from html.parser import HTMLParser
from html import escape
import sys
import re
import shutil

source_path = Path(sys.argv[1])
reports_path = Path(sys.argv[2])
index_path = Path(sys.argv[3])

class ArticleParser(HTMLParser):
    def __init__(self):
        super().__init__()
        self.h1 = ""
        self.date = ""
        self.english_title = ""

        self.in_h1 = False
        self.in_time = False
        self.after_h1 = False
        self.in_first_p_after_h1 = False

    def handle_starttag(self, tag, attrs):
        if tag == "h1":
            self.in_h1 = True
            self.after_h1 = True
            return

        if tag == "time":
            self.in_time = True
            return

        # 发布页面的英文标题紧跟在中文 h1 后面的第一个 p
        if tag == "p" and self.after_h1 and not self.english_title:
            self.in_first_p_after_h1 = True

    def handle_endtag(self, tag):
        if tag == "h1":
            self.in_h1 = False
            return

        if tag == "time":
            self.in_time = False
            return

        if tag == "p" and self.in_first_p_after_h1:
            self.in_first_p_after_h1 = False

    def handle_data(self, data):
        text = data.strip()

        if self.in_h1:
            self.h1 += text

        if self.in_time:
            self.date += text

        if self.in_first_p_after_h1:
            self.english_title += text


# 读取文章
html = source_path.read_text(encoding="utf-8")

parser = ArticleParser()
parser.feed(html)

title_zh = parser.h1.strip()
title_en = parser.english_title.strip()
date = parser.date.strip()

if not title_zh:
    print("错误：没有找到中文标题。")
    sys.exit(1)

if not title_en:
    print("错误：没有找到英文标题。")
    sys.exit(1)

if not date:
    print("错误：没有找到日期。")
    sys.exit(1)

# 根据英文标题生成文件名
slug = title_en.lower().strip()
slug = re.sub(r"[^a-z0-9]+", "-", slug)
slug = re.sub(r"^-+|-+$", "", slug)

if not slug:
    slug = "article"

destination = reports_path / f"{slug}.html"

# 永远使用标准文件名。
# 如果以前存在同名文章，就直接覆盖，而不是生成 (1)、(2)。
shutil.copy2(source_path, destination)

print(f"中文标题：{title_zh}")
print(f"英文标题：{title_en}")
print(f"日期：{date}")
print(f"文章文件：reports/{destination.name}")
print("")

# --------------------------------------------------
# 重建首页文章列表
# --------------------------------------------------

class IndexArticleParser(HTMLParser):
    def __init__(self):
        super().__init__()
        self.title_zh = ""
        self.title_en = ""
        self.date = ""

        self.in_h1 = False
        self.in_time = False
        self.in_title_en = False

        self.found_h1 = False
        self.found_time = False

    def handle_starttag(self, tag, attrs):
        if tag == "h1" and not self.found_h1:
            self.in_h1 = True
            self.found_h1 = True

        elif tag == "time" and not self.found_time:
            self.in_time = True
            self.found_time = True

        elif tag == "p" and self.found_h1 and not self.title_en:
            self.in_title_en = True

    def handle_endtag(self, tag):
        if tag == "h1":
            self.in_h1 = False

        elif tag == "time":
            self.in_time = False

        elif tag == "p" and self.in_title_en:
            self.in_title_en = False

    def handle_data(self, data):
        text = data.strip()

        if self.in_h1:
            self.title_zh += text

        elif self.in_time:
            self.date += text

        elif self.in_title_en:
            self.title_en += text


articles = []

for file in reports_path.glob("*.html"):
    parser = IndexArticleParser()

    try:
        content = file.read_text(encoding="utf-8")
        parser.feed(content)
    except Exception as e:
        print(f"跳过无法读取的文件：{file.name}")
        print(e)
        continue

    if not parser.title_zh:
        continue

    articles.append({
        "file": file.name,
        "title_zh": parser.title_zh.strip(),
        "title_en": parser.title_en.strip(),
        "date": parser.date.strip(),
        "mtime": file.stat().st_mtime
    })


# 最新文章排前面
articles.sort(
    key=lambda article: article["mtime"],
    reverse=True
)

article_html = []

for article in articles:
    file_name = escape(article["file"], quote=True)
    title_zh = escape(article["title_zh"])
    title_en = escape(article["title_en"])
    date = escape(article["date"])

    article_html.append(f"""
        <article class="home-entry">
            <h2>
                <a href="reports/{file_name}">
                    {title_zh}
                </a>
            </h2>
            <p class="home-entry-en">
                {title_en}
            </p>
            <time>
                {date}
            </time>
        </article>
""")

new_section = (
    "<!-- ARTICLES START -->\n"
    + "\n".join(article_html)
    + "\n<!-- ARTICLES END -->"
)

old = index_path.read_text(encoding="utf-8")

start_marker = "<!-- ARTICLES START -->"
end_marker = "<!-- ARTICLES END -->"

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

print("Home 已更新。")
print("")
PY

echo "正在上传 GitHub..."

cd "$PROJECT"

git add .

git commit -m "Publish article: $(basename "$LATEST")" || true

git push

echo ""
echo "=============================="
echo "发布完成。"
echo "=============================="
echo ""
