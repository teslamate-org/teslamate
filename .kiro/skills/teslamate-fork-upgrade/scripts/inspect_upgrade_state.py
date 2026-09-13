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
IMAGE_REF_RE = re.compile(
    r"^(?P<name>[^\s:@]+(?:/[^\s:@]+)*):(?P<tag>[^\s@]+)@(?P<digest>sha256:[0-9a-f]{64})$"
)


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


def ref_exists(repo: Path, ref: str) -> bool:
    return resolve_commit(repo, ref) is not None


def resolve_commit(repo: Path, ref: str) -> str | None:
    value = git(repo, "rev-parse", "--verify", "--quiet", f"{ref}^{{commit}}", check=False)
    return value if re.fullmatch(r"[0-9a-f]{40}", value) else None


def show_file(repo: Path, ref: str, file_path: str) -> str | None:
    value = git(repo, "show", f"{ref}:{file_path}", check=False)
    return value or None


def latest_stable_tag(repo: Path) -> str | None:
    tags = git(repo, "tag", "--list").splitlines()
    parsed: list[tuple[tuple[int, int, int], str]] = []
    for tag in tags:
        match = SEMVER_RE.match(tag)
        if match:
            parsed.append((tuple(int(part) for part in match.groups()), tag))
    return max(parsed, default=(None, None))[1]


def remote_names(repo: Path) -> list[str]:
    return sorted(git(repo, "remote").splitlines())


def patch_id(repo: Path, commit: str) -> str | None:
    patch = run(
        ["git", "show", "--pretty=format:", "--binary", commit],
        repo,
        check=True,
    ).encode()
    if not patch.strip():
        return None
    output = run(["git", "patch-id", "--stable"], repo, check=True, stdin=patch)
    return output.split()[0] if output else None


def custom_commits(repo: Path) -> list[dict[str, Any]]:
    if not ref_exists(repo, "upstream/main") or not ref_exists(repo, "origin/main"):
        return []
    commits = git(
        repo,
        "rev-list",
        "--reverse",
        "--no-merges",
        "upstream/main..origin/main",
    ).splitlines()
    result: list[dict[str, Any]] = []
    for commit in commits:
        result.append(
            {
                "sha": commit,
                "subject": git(repo, "show", "-s", "--format=%s", commit),
                "patch_id": patch_id(repo, commit),
            }
        )
    return result


def inspect_teslamate(repo: Path, target_tag: str | None) -> dict[str, Any]:
    branch = git(repo, "branch", "--show-current") or None
    refs: dict[str, dict[str, str | None]] = {}
    for ref in ("origin/main", "upstream/main"):
        refs[ref] = {
            "sha": resolve_commit(repo, ref),
            "version": show_file(repo, ref, "VERSION") if ref_exists(repo, ref) else None,
        }
    if target_tag:
        match = SEMVER_RE.fullmatch(target_tag)
        tag_ref = f"refs/tags/{target_tag}"
        target_sha = resolve_commit(repo, tag_ref) if match else None
        target_version = show_file(repo, tag_ref, "VERSION") if target_sha else None
        expected_version = ".".join(match.groups()) if match else None
        if target_sha is None or target_version != expected_version:
            raise RuntimeError(
                f"target must be an exact stable semver tag whose VERSION matches: {target_tag}"
            )
        refs[target_tag] = {"sha": target_sha, "version": target_version}
    return {
        "path": str(repo),
        "branch": branch,
        "head": git(repo, "rev-parse", "HEAD"),
        "dirty_paths": git(repo, "status", "--porcelain").splitlines(),
        "remotes": remote_names(repo),
        "latest_local_stable_tag": latest_stable_tag(repo),
        "refs": refs,
        "custom_non_merge_commits": custom_commits(repo),
    }


def parse_role_vars(content: str) -> dict[str, str | None]:
    values: dict[str, str | None] = {}
    for key in ("teslamate_image_ref", "teslamate_grafana_image_ref"):
        match = re.search(rf"(?m)^{re.escape(key)}:\s*[\"']?([^\s\"']+)", content)
        values[key] = match.group(1) if match else None
    return values


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
    output = run([ansible_python(repo), "-c", code, str(path)], repo)
    return json.loads(output)


def unique_task(tasks: list[Any], name: str) -> tuple[int, dict[str, Any]] | None:
    matches = [
        (index, task)
        for index, task in enumerate(tasks)
        if isinstance(task, dict) and task.get("name") == name
    ]
    if len(matches) != 1:
        return None
    return matches[0]


def has_condition(task: dict[str, Any], expected: str) -> bool:
    conditions = task.get("when", [])
    if isinstance(conditions, str):
        conditions = [conditions]
    return isinstance(conditions, list) and expected in conditions


def inspect_ansible(repo: Path) -> dict[str, Any]:
    vars_path = repo / "roles/teslamate/vars/main.yml"
    tasks_path = repo / "roles/teslamate/tasks/main.yml"
    template_path = repo / "roles/teslamate/templates/compose.yml.j2"
    vars_content = vars_path.read_text(encoding="utf-8") if vars_path.exists() else ""
    template_content = template_path.read_text(encoding="utf-8") if template_path.exists() else ""
    image_refs = parse_role_vars(vars_content)
    parsed_refs: dict[str, dict[str, str] | None] = {}
    for key, value in image_refs.items():
        match = IMAGE_REF_RE.match(value or "")
        parsed_refs[key] = match.groupdict() if match else None
    patch_files = [
        "roles/teslamate/files/patch_vampire_drain_dashboard.py",
        "roles/teslamate/files/patch_visited_dashboard.py",
    ]

    loaded_tasks = load_yaml(repo, tasks_path) if tasks_path.exists() else None
    tasks = loaded_tasks if isinstance(loaded_tasks, list) else []
    prepull = unique_task(tasks, "teslamate : Pre-pull deployment images")
    compose_file = unique_task(tasks, "teslamate : Add services to compose")
    compose_update = unique_task(tasks, "teslamate : Pull and update containers")
    cleanup = unique_task(tasks, "teslamate : Remove legacy dashboard patch assets")

    required_images = [
        "{{ teslamate_image_ref }}",
        "{{ teslamate_grafana_image_ref }}",
    ]
    required_services = ["teslamate", "teslamate-grafana"]
    required_cleanup_paths = [
        "{{ teslamate_data_dir }}/patch_vampire_drain_dashboard.py",
        "{{ teslamate_data_dir }}/patch_visited_dashboard.py",
        "{{ teslamate_data_dir }}/grafana-dashboards",
    ]
    required_compose_file = {
        "path": "/etc/compose.yml",
        "marker": "# {mark} ANSIBLE MANAGED BLOCK teslamate",
        "block": "{{ lookup('template', 'compose.yml.j2') }}",
    }
    required_compose_update = {
        "project_src": "/etc",
        "pull": "never",
        "services": required_services,
        "state": "present",
    }
    prepull_task = prepull[1] if prepull else {}
    compose_file_task = compose_file[1] if compose_file else {}
    compose_update_task = compose_update[1] if compose_update else {}
    cleanup_task = cleanup[1] if cleanup else {}
    prepull_module = prepull_task.get("community.docker.docker_image")
    compose_file_module = compose_file_task.get("ansible.builtin.blockinfile")
    compose_update_module = compose_update_task.get("community.docker.docker_compose_v2")
    cleanup_module = cleanup_task.get("ansible.builtin.file")
    ordered = bool(
        prepull
        and compose_file
        and compose_update
        and cleanup
        and prepull[0] < compose_file[0] < compose_update[0] < cleanup[0]
    )
    prepull_module_valid = prepull_module == {"name": "{{ item }}", "source": "pull"}
    compose_file_valid = compose_file_module == required_compose_file
    compose_update_valid = compose_update_module == required_compose_update
    cleanup_valid = bool(
        cleanup_module == {"path": "{{ item }}", "state": "absent"}
        and cleanup_task.get("loop") == required_cleanup_paths
    )

    return {
        "path": str(repo),
        "branch": git(repo, "branch", "--show-current") or None,
        "head": git(repo, "rev-parse", "HEAD"),
        "origin_main": resolve_commit(repo, "origin/main"),
        "dirty_paths": git(repo, "status", "--porcelain").splitlines(),
        "remotes": remote_names(repo),
        "image_refs": image_refs,
        "parsed_image_refs": parsed_refs,
        "runtime_patch_files_present": [path for path in patch_files if (repo / path).exists()],
        "contract": {
            "compose_pull_never": bool(
                compose_update_valid and compose_update_module.get("pull") == "never"
            ),
            "compose_skips_check_mode": bool(
                compose_update_valid and has_condition(compose_update_task, "not ansible_check_mode")
            ),
            "compose_updates_both_services": bool(
                compose_update_valid
                and compose_update_module.get("services") == required_services
            ),
            "dashboard_bind_mounts_present": "grafana-dashboards" in template_content,
            "legacy_cleanup_after_compose": bool(
                cleanup_valid and compose_update_valid and ordered
            ),
            "prepull_before_compose": bool(
                prepull_module_valid and compose_file_valid and ordered
            ),
            "prepull_both_images": bool(
                prepull_module_valid and prepull_task.get("loop") == required_images
            ),
            "prepull_skips_check_mode": bool(
                prepull_module_valid and has_condition(prepull_task, "not ansible_check_mode")
            ),
        },
    }

def build_warnings(data: dict[str, Any]) -> list[str]:
    warnings: list[str] = []
    teslamate = data["teslamate"]
    ansible = data["ansible"]
    if teslamate["dirty_paths"]:
        warnings.append("TeslaMate worktree is dirty; create or select a clean isolated worktree.")
    if ansible["dirty_paths"]:
        warnings.append("Ansible worktree is dirty; create or select a clean isolated worktree.")
    for remote in ("origin", "upstream"):
        if remote not in teslamate["remotes"]:
            warnings.append(f"TeslaMate remote is missing: {remote}")
    for key, parsed in ansible["parsed_image_refs"].items():
        if parsed is None:
            warnings.append(f"Ansible image ref is missing or not tag@sha256 pinned: {key}")
    if ansible["runtime_patch_files_present"]:
        warnings.append("Legacy runtime dashboard patch files are present and need explicit upgrade handling.")
    required_contract = {
        "compose_pull_never": True,
        "compose_skips_check_mode": True,
        "compose_updates_both_services": True,
        "dashboard_bind_mounts_present": False,
        "legacy_cleanup_after_compose": True,
        "prepull_before_compose": True,
        "prepull_both_images": True,
        "prepull_skips_check_mode": True,
    }
    for key, expected in required_contract.items():
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
    parser.add_argument("--target-tag", help="Optional target release tag already fetched locally")
    parser.add_argument("--strict", action="store_true", help="Exit non-zero when warnings are present")
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
        if args.strict and data["warnings"]:
            return 2
        return 0
    except Exception as error:  # noqa: BLE001 - CLI should return one concise diagnostic.
        print(json.dumps({"error": str(error)}, ensure_ascii=False), file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
