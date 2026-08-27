---
title: Verifying published container images
sidebar_label: Verifying images
---

All TeslaMate images published to Docker Hub (`teslamate/teslamate`,
`teslamate/grafana`) and GitHub Container Registry
(`ghcr.io/teslamate-org/teslamate`, `ghcr.io/teslamate-org/teslamate/grafana`)
carry signed **SLSA build provenance**, generated keylessly via Sigstore using
the `teslamate-org/teslamate` GitHub Actions OIDC identity. The provenance
proves an image was built by that workflow, from a specific commit, with no
shared keys to manage.

`teslamate/teslamate` additionally carries an **SPDX SBOM** (software bill of
materials) attached to each per-platform image digest. `teslamate/grafana` is
built as a single multi-arch image and carries provenance only.

## Verify with `gh`

```sh
gh attestation verify \
  oci://docker.io/teslamate/teslamate:latest \
  --repo teslamate-org/teslamate
```

Use `oci://ghcr.io/teslamate-org/teslamate:latest` for the GHCR image, and the
`grafana` variants similarly. The `gh` CLI resolves the tag to the multi-arch
manifest digest and verifies the provenance attached to it.

## Verifying per-platform SBOMs

SBOMs for `teslamate/teslamate` are attached to each per-platform image digest
(their natural scope — filesystem contents differ per architecture). To inspect,
resolve the platform digest first:

```sh
docker buildx imagetools inspect docker.io/teslamate/teslamate:latest \
  --format '{{ range .Manifest.Manifests }}{{ .Platform.Architecture }} {{ .Digest }}{{ "\n" }}{{ end }}'

gh attestation verify \
  oci://docker.io/teslamate/teslamate@sha256:<platform-digest> \
  --repo teslamate-org/teslamate \
  --predicate-type https://spdx.dev/Document
```
