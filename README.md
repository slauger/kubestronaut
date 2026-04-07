# Golden Kubestronaut Study Guide

Study guide and exam simulator for the [CNCF Golden Kubestronaut](https://www.cncf.io/training/kubestronaut/) certification path — all 16 CNCF certifications.

**Live Site:** [slauger.github.io/kubestronaut](https://slauger.github.io/kubestronaut/)

## Certifications

### Kubestronaut (Core 5)

| Certification | Type | Duration | Passing Score |
|---|---|---|---|
| KCNA | Multiple Choice | 90 min | 75% |
| KCSA | Multiple Choice | 90 min | 75% |
| CKA | Performance-based | 2 hours | 66% |
| CKAD | Performance-based | 2 hours | 66% |
| CKS | Performance-based | 2 hours | 67% |

### Additional Certifications (11)

| Certification | Type | Duration | Passing Score |
|---|---|---|---|
| PCA (Prometheus) | Multiple Choice | 90 min | 75% |
| ICA (Istio) | Performance-based | 2 hours | 68% |
| CCA (Cilium) | Multiple Choice | 90 min | 75% |
| CAPA (Argo) | Multiple Choice | 90 min | 75% |
| CGOA (GitOps) | Multiple Choice | 90 min | 75% |
| CBA (Backstage) | Multiple Choice | 90 min | 75% |
| OTCA (OpenTelemetry) | Multiple Choice | 90 min | 75% |
| KCA (Kyverno) | Multiple Choice | 90 min | 75% |
| CNPA (Platform) | Multiple Choice | 120 min | 75% |
| CNPE (Platform Eng.) | Performance-based | 2 hours | 64% |
| LFCS (Linux Sysadmin) | Performance-based | 2 hours | 67% |

## Features

- Study guides for all 16 certifications with exam domain breakdowns
- Practice questions with explanations and documentation references
- Exam simulator with timer and pass/fail scoring
- Progress tracking (localStorage)
- Dark/light mode, full-text search
- GitHub Pages deployment via GitHub Actions

## Local Development

```bash
make serve
```

Opens the site at [http://127.0.0.1:8000](http://127.0.0.1:8000).

Other targets:

```bash
make build    # Build static site
make install  # Install dependencies only
make clean    # Remove site/ and .venv/
```

## Tech Stack

- [MkDocs Material](https://squidfunk.github.io/mkdocs-material/) for the documentation site
- Vanilla HTML/CSS/JS for the exam simulator
- JSON question files per certification
- GitHub Actions for CI/CD

## License

MIT
