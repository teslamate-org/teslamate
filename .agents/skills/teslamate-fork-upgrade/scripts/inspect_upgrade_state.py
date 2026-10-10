#!/usr/bin/env python3
"""Inspect the local TeslaMate fork and Ansible deployment without mutating them."""

from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
from pathlib import Path
from typing import Any

SEMVER_RE = re.compile(r"^v?(\d+)\.(\d+)\.(\d+)$")

APP_IMAGE = "oci:ghcr.io/rewse/teslamate"
GRAFANA_IMAGE = "oci:ghcr.io/rewse/teslamate/grafana"
COMPOSE_DIR = "/etc/compose/teslamate"
RESOLVE_TASK = "container | Resolve fork images"
PREPULL_TASK = "container | Pre-pull deployment images"
COMPOSE_FILE_TASK = "container | Deploy compose file"
COMPOSE_UPDATE_TASK = "container | Pull and update containers"
PREPULL_LOOP = [
    "{{ __teslamate_image.ref | regex_replace(':[^:@/]+@', '@') }}",
    "{{ __teslamate_grafana_image.ref | regex_replace(':[^:@/]+@', '@') }}",
]


def run(command: list[str], cwd: Path, check: bool = True, stdin: bytes | None = None) -> str:
    result = subprocess.run(
        command,
        cwd=cwd,
        input=stdin,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
    )
    if check and result.returncode != 0:
        message = result.stderr.decode("utf-8", errors="replace").strip()
        raise RuntimeError(f"{' '.join(command)} failed in {cwd}: {message}")
    return result.stdout.decode("utf-8", errors="replace").strip()


def git(repo: Path, *args: str, check: bool = True) -> str:
    return run(["git", *args], repo, check=check)


def require_repo(path: Path, label: str) -> None:
    if not path.is_dir() or git(path, "rev-parse", "--is-inside-work-tree", check=False) != "true":
        raise RuntimeError(f"{label} is not a git worktree: {path}")


def resolve_commit(repo: Path, ref: str) -> str | None:
    value = git(repo, "rev-parse", "--verify", "--quiet", f"{ref}^{{commit}}", check=False)
    return value if re.fullmatch(r"[0-9a-f]{40}", value) else None


def ref_exists(repo: Path, ref: str) -> bool:
    return resolve_commit(repo, ref) is not None


def show_file(repo: Path, ref: str, file_path: str) -> str | None:
    value = git(repo, "show", f"{ref}:{file_path}", check=False)
    return value or None


def latest_stable_tag(repo: Path) -> str | None:
    parsed: list[tuple[tuple[int, ...], str]] = []
    for tag in git(repo, "tag", "--list").splitlines():
        match = SEMVER_RE.match(tag)
        if match:
            parsed.append((tuple(int(part) for part in match.groups()), tag))
    return max(parsed, default=(None, None))[1]


def remote_names(repo: Path) -> list[str]:
    return sorted(git(repo, "remote").splitlines())


def patch_id(repo: Path, commit: str) -> str | None:
    patch = run(["git", "show", "--pretty=format:", "--binary", commit], repo).encode()
    if not patch.strip():
        return None
    output = run(["git", "patch-id", "--stable"], repo, stdin=patch)
    return output.split()[0] if output else None


def discarded_parents(repo: Path, base: str) -> list[str]:
    """Return merge parents whose changes the merge result discards.

    A previous upgrade records the old fork history with an `-s ours` merge, so
    the merge tree equals one parent and the other parent's commits are
    superseded by their reapplied versions. Those commits are not live deltas.
    """
    discarded: list[str] = []
    for line in git(repo, "rev-list", "--merges", "--parents", f"{base}..origin/main").splitlines():
        merge, *parents = line.split()
        tree = git(repo, "rev-parse", f"{merge}^{{tree}}")
        kept = [p for p in parents if git(repo, "rev-parse", f"{p}^{{tree}}") == tree]
        if kept:
            discarded += [p for p in parents if p not in kept]
    return discarded


def custom_commits(repo: Path, base: str) -> list[dict[str, Any]]:
    """List live fork-only non-merge commits on origin/main that base does not contain."""
    if not ref_exists(repo, base) or not ref_exists(repo, "origin/main"):
        return []
    excluded = [f"^{parent}" for parent in discarded_parents(repo, base)]
    commits = git(
        repo, "rev-list", "--reverse", "--no-merges", f"{base}..origin/main", *excluded
    ).splitlines()
    return [
        {
            "sha": commit,
            "subject": git(repo, "show", "-s", "--format=%s", commit),
            "patch_id": patch_id(repo, commit),
        }
        for commit in commits
    ]


def inspect_target(repo: Path, target_tag: str) -> dict[str, Any]:
    match = SEMVER_RE.fullmatch(target_tag)
    tag_ref = f"refs/tags/{target_tag}"
    commit = resolve_commit(repo, tag_ref) if match else None
    version = show_file(repo, tag_ref, "VERSION") if commit else None
    expected = ".".join(match.groups()) if match else None
    if commit is None or (version or "").strip() != expected:
        raise RuntimeError(f"target must be an exact stable semver tag whose VERSION matches: {target_tag}")
    tag_object = git(repo, "rev-parse", tag_ref)
    tag_type = git(repo, "cat-file", "-t", tag_object)
    signed = False
    if tag_type == "tag":
        signed = "-----BEGIN" in git(repo, "cat-file", "tag", tag_object)
    return {
        "commit": commit,
        "tag_object": tag_object if tag_type == "tag" else None,
        "tag_signed": signed,
        "version": version.strip() if version else None,
    }


def inspect_teslamate(repo: Path, target_tag: str | None) -> dict[str, Any]:
    refs: dict[str, dict[str, str | None]] = {}
    for ref in ("origin/main", "upstream/main"):
        version = show_file(repo, ref, "VERSION") if ref_exists(repo, ref) else None
        refs[ref] = {"sha": resolve_commit(repo, ref), "version": version.strip() if version else None}
    target = inspect_target(repo, target_tag) if target_tag else None
    base = f"refs/tags/{target_tag}" if target_tag else "upstream/main"
    return {
        "path": str(repo),
        "branch": git(repo, "branch", "--show-current") or None,
        "head": git(repo, "rev-parse", "HEAD"),
        "dirty_paths": git(repo, "status", "--porcelain", "--untracked-files=no").splitlines(),
        "remotes": remote_names(repo),
        "latest_local_stable_tag": latest_stable_tag(repo),
        "refs": refs,
        "target": target,
        "custom_commits_base": target_tag or "upstream/main",
        "custom_non_merge_commits": custom_commits(repo, base),
    }


def ansible_python(repo: Path) -> str:
    override = os.environ.get("ANSIBLE_PYTHON")
    if override:
        return override
    version = run(["ansible-playbook", "--version"], repo)
    for line in version.splitlines():
        if "python version =" not in line:
            continue
        match = re.search(r"\((/[^()]*)\)\s*$", line)
        if match:
            return match.group(1)
    raise RuntimeError("cannot resolve Ansible Python; set ANSIBLE_PYTHON")


def load_yaml(repo: Path, path: Path) -> Any:
    code = (
        "import json, pathlib, sys, yaml; "
        "data = yaml.safe_load(pathlib.Path(sys.argv[1]).read_text(encoding='utf-8')); "
        "print(json.dumps(data))"
    )
    return json.loads(run([ansible_python(repo), "-c", code, str(path)], repo))


def unique_task(tasks: list[Any], name: str) -> tuple[int, dict[str, Any]] | None:
    matches = [
        (index, task)
        for index, task in enumerate(tasks)
        if isinstance(task, dict) and task.get("name") == name
    ]
    return matches[0] if len(matches) == 1 else None


def has_condition(task: dict[str, Any], expected: str) -> bool:
    conditions = task.get("when", [])
    if isinstance(conditions, str):
        conditions = [conditions]
    return isinstance(conditions, list) and expected in conditions


def follows_main(expression: Any, image: str) -> bool:
    text = expression if isinstance(expression, str) else ""
    return f"'{image}'" in text and "pattern='^main$'" in text and "aged_release" in text


def inspect_ansible(repo: Path) -> dict[str, Any]:
    role = repo / "roles/teslamate"
    tasks_path = role / "tasks/container.yml"
    template_path = role / "templates/compose.yaml.j2"
    template = template_path.read_text(encoding="utf-8") if template_path.exists() else ""
    loaded = load_yaml(repo, tasks_path) if tasks_path.exists() else None
    tasks = loaded if isinstance(loaded, list) else []

    resolve = unique_task(tasks, RESOLVE_TASK)
    prepull = unique_task(tasks, PREPULL_TASK)
    compose_file = unique_task(tasks, COMPOSE_FILE_TASK)
    compose_update = unique_task(tasks, COMPOSE_UPDATE_TASK)

    facts = (resolve[1] if resolve else {}).get("ansible.builtin.set_fact") or {}
    prepull_task = prepull[1] if prepull else {}
    update_task = compose_update[1] if compose_update else {}
    update_module = update_task.get("community.docker.docker_compose_v2") or {}
    ordered = bool(
        resolve and prepull and compose_file and compose_update
        and resolve[0] < prepull[0] < compose_file[0] < compose_update[0]
    )

    return {
        "path": str(repo),
        "branch": git(repo, "branch", "--show-current") or None,
        "head": git(repo, "rev-parse", "HEAD"),
        "origin_main": resolve_commit(repo, "origin/main"),
        "dirty_paths": git(repo, "status", "--porcelain", "--untracked-files=no").splitlines(),
        "remotes": remote_names(repo),
        "contract": {
            "compose_pull_never": update_module.get("pull") == "never",
            "compose_project_dir": update_module.get("project_src") == COMPOSE_DIR,
            "compose_skips_check_mode": has_condition(update_task, "not ansible_check_mode"),
            "compose_uses_resolved_refs": (
                "{{ __teslamate_image.ref }}" in template
                and "{{ __teslamate_grafana_image.ref }}" in template
            ),
            "dashboard_bind_mounts_present": "grafana-dashboards" in template,
            "images_follow_fork_main": (
                follows_main(facts.get("__teslamate_image"), APP_IMAGE)
                and follows_main(facts.get("__teslamate_grafana_image"), GRAFANA_IMAGE)
            ),
            "prepull_before_compose": ordered,
            "prepull_both_images_by_digest": (
                prepull_task.get("community.docker.docker_image") == {"name": "{{ item }}", "source": "pull"}
                and prepull_task.get("loop") == PREPULL_LOOP
            ),
            "prepull_skips_check_mode": has_condition(prepull_task, "not ansible_check_mode"),
        },
    }


REQUIRED_CONTRACT = {
    "compose_project_dir": True,
    "compose_pull_never": True,
    "compose_skips_check_mode": True,
    "compose_uses_resolved_refs": True,
    "dashboard_bind_mounts_present": False,
    "images_follow_fork_main": True,
    "prepull_before_compose": True,
    "prepull_both_images_by_digest": True,
    "prepull_skips_check_mode": True,
}


def build_warnings(data: dict[str, Any]) -> list[str]:
    warnings: list[str] = []
    teslamate = data["teslamate"]
    ansible = data["ansible"]
    if teslamate["dirty_paths"]:
        warnings.append("TeslaMate worktree has uncommitted changes; use a clean isolated worktree.")
    if ansible["dirty_paths"]:
        warnings.append("Ansible worktree has uncommitted changes; use a clean isolated worktree.")
    for remote in ("origin", "upstream"):
        if remote not in teslamate["remotes"]:
            warnings.append(f"TeslaMate remote is missing: {remote}")
    target = teslamate["target"]
    if target and not target["tag_signed"]:
        warnings.append("Target tag carries no signature; an alternate trust basis needs explicit approval.")
    for key, expected in REQUIRED_CONTRACT.items():
        if ansible["contract"][key] is not expected:
            warnings.append(f"Ansible deployment contract mismatch: {key} must be {expected}.")
    return warnings


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--teslamate-repo",
        type=Path,
        default=Path(os.environ.get("TESLAMATE_REPO", Path.cwd())),
    )
    parser.add_argument(
        "--ansible-repo",
        type=Path,
        default=(Path(value) if (value := os.environ.get("ANSIBLE_PLAYBOOKS_REPO")) else None),
    )
    parser.add_argument("--target-tag", help="Target release tag, already fetched locally")
    parser.add_argument("--strict", action="store_true", help="Exit 2 when warnings are present")
    parser.add_argument("--compact", action="store_true", help="Emit compact JSON")
    args = parser.parse_args()
    if args.ansible_repo is None:
        parser.error("set ANSIBLE_PLAYBOOKS_REPO or pass --ansible-repo")

    try:
        require_repo(args.teslamate_repo, "TeslaMate repository")
        require_repo(args.ansible_repo, "Ansible repository")
        data: dict[str, Any] = {
            "teslamate": inspect_teslamate(args.teslamate_repo, args.target_tag),
            "ansible": inspect_ansible(args.ansible_repo),
        }
        data["warnings"] = build_warnings(data)
        print(json.dumps(data, ensure_ascii=False, indent=None if args.compact else 2, sort_keys=True))
        return 2 if args.strict and data["warnings"] else 0
    except Exception as error:  # noqa: BLE001 - CLI should return one concise diagnostic.
        print(json.dumps({"error": str(error)}, ensure_ascii=False), file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
