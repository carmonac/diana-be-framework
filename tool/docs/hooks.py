"""MkDocs hook: point links that escape docs/ at GitHub.

The Markdown under docs/ links to examples and packages with relative paths
(`../../examples/todo_api`) so it reads correctly when browsed on GitHub.
Those targets aren't part of the site, so rewrite them to repository URLs
at build time instead of changing the sources.
"""

import posixpath
import re

_REPO = "https://github.com/carmonac/diana-be-framework"
_LINK = re.compile(r"\]\((\.\./[^)\s]*)\)")


def on_page_markdown(markdown, page, config, files):
    page_dir = posixpath.dirname(page.file.src_uri)

    def rewrite(match):
        target, _, anchor = match.group(1).partition("#")
        resolved = posixpath.normpath(posixpath.join("docs", page_dir, target))
        if resolved.startswith("docs/") or resolved.startswith(".."):
            return match.group(0)
        # Directories are browsed with tree/, files with blob/.
        kind = "blob" if posixpath.splitext(resolved)[1] else "tree"
        url = f"{_REPO}/{kind}/main/{resolved}"
        return f"]({url}#{anchor})" if anchor else f"]({url})"

    return _LINK.sub(rewrite, markdown)
