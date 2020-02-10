from recommonmark.parser import CommonMarkParser

extensions = ["sphinx_markdown_tables"]
source_parsers = {".md": CommonMarkParser}

source_suffix = [".rst", ".md"]

master_doc = "index"
project = "TeslaMate"

html_theme = "press"

github_url = "https://github.com"
github_repo_org = "adriankumpf"
github_repo_name = "teslamate"
github_repo_slug = f"{github_repo_org}/{github_repo_name}"
github_repo_url = f"{github_url}/{github_repo_slug}"

# For if in the future we wish to link to specific issues or PRs
extlinks = {
    "issue": (f"{github_repo_url}/issues/%s", "#"),
    "pr": (f"{github_repo_url}/pull/%s", "PR #"),
    "commit": (f"{github_repo_url}/commit/%s", ""),
    "gh": (f"{github_url}/%s", "GitHub: "),
}
