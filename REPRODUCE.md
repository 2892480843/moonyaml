# Reproducing the demo

Everything below runs from the repository root with the MoonBit toolchain
installed (`curl -fsSL https://cli.moonbitlang.com/install/unix.sh | bash`).

## 1. Run the test suite

```bash
moon test
# Total tests: 59, passed: 59, failed: 0.
```

## 2. Zero-warning type check (what CI enforces)

```bash
moon check --deny-warn
```

## 3. Convert YAML to JSON

```bash
moon run cmd/yj -- examples/deployment.yml
moon run cmd/yj -- examples/config.yml
```

Expected (deployment.yml, abridged):

```json
{
  "apiVersion": "apps/v1",
  "kind": "Deployment",
  "metadata": {
    "name": "web",
    "labels": { "app": "web", "tier": "frontend" }
  },
  "spec": {
    "replicas": 3,
    "template": {
      "spec": {
        "containers": [
          {
            "name": "web",
            "image": "nginx:1.27",
            "ports": [80, 443],
            ...
```

## 3b. Real-world compatibility

The `examples/` directory contains unmodified-style real-world YAML:
a GitHub Actions workflow (matrix/include/exclude, `${{ }}` expressions,
block-scalar `run:`), a docker-compose file, and a GitLab CI config that
uses nested merge keys (`<<: *anchor` inside `cache:`):

```bash
moon run cmd/yj -- -c examples/github-actions-workflow.yml
moon run cmd/yj -- -c examples/docker-compose.yml
moon run cmd/yj -- -c examples/gitlab-ci.yml
moon run cmd/yj -- -c examples/crlf-unicode.yml   # CRLF + CJK + emoji
moon run cmd/yj -- -c examples/generated-20000-lines.yml  # ~0.15s
```

## 4. Convert JSON back to YAML

```bash
moon run cmd/yj -- -e '{"name":"web","replicas":3,"labels":{"app":"web"}}'
```

## 5. Multi-document stream

```bash
moon run cmd/yj -- -a examples/stream.yml
# [{"name":"first","value":1},{"name":"second","value":2}]
```

## 6. Error reporting

```bash
moon run cmd/yj -- -e 'a: [1, 2'
# yj: invalid YAML
```

Inside `moon test`, the error-contract suite asserts the exact message
fragments and line numbers (`line N: ...`) for ten malformed inputs.

## 7. Round-trip property

The `roundtrip_wbtest.mbt` suite asserts `parse(emit(parse(x))) == parse(x)`
(and emission stability) for structural, scalar, block-scalar, anchor and
edge-collection inputs — run it as part of step 1.
