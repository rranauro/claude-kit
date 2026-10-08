#!/usr/bin/env python3
"""Render a Markdown file to a self-contained HTML preview beside it, then open it.

Usage: python3 -I render_html.py path/to/file.md [--no-open]

The Markdown is embedded verbatim and parsed in the browser by marked, with
highlight.js colouring diff, code and console blocks. Both are loaded from
cdnjs; the Markdown itself never leaves the machine.
"""

import html
import pathlib
import subprocess
import sys

# forced light: the github-markdown base stylesheet follows the OS dark mode while the
# highlight.js theme does not, which leaves dark code text on a dark background
PAGE = """<!doctype html>
<html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>{title}</title>
<link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/github-markdown-css/5.5.1/github-markdown-light.min.css">
<link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/highlight.js/11.9.0/styles/github.min.css">
<style>
body{{background:#fff;max-width:960px;margin:32px auto;padding:0 16px}}
.hljs-addition{{background:#e6ffec}}.hljs-deletion{{background:#ffebe9}}
</style></head>
<body class="markdown-body"><div id="out"></div>
<script id="md" type="text/markdown">{markdown}</script>
<script src="https://cdnjs.cloudflare.com/ajax/libs/marked/12.0.2/marked.min.js"></script>
<script src="https://cdnjs.cloudflare.com/ajax/libs/highlight.js/11.9.0/highlight.min.js"></script>
<script>
document.getElementById('out').innerHTML = marked.parse(document.getElementById('md').textContent);
document.querySelectorAll('pre code[class*="language-"]').forEach(function (el) {{ hljs.highlightElement(el); }});
</script>
</body></html>
"""


def main(argv):
    if len(argv) < 2:
        sys.exit("usage: render_html.py FILE.md [--no-open]")
    source = pathlib.Path(argv[1]).resolve()
    markdown = source.read_text(encoding="utf-8")
    # the only sequence that can end the embedding <script> early
    markdown = markdown.replace("</script", "<\\/script")
    target = source.with_suffix(".html")
    target.write_text(PAGE.format(title=html.escape(source.stem), markdown=markdown), encoding="utf-8")
    print(target)
    if "--no-open" not in argv and sys.platform == "darwin":
        subprocess.run(["open", str(target)], check=False)


if __name__ == "__main__":
    main(sys.argv)
