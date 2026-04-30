---
name: cicd-deployment
description: 'Reference and apply CI/CD pipeline and deployment strategy guidelines. Use when: setting up CI/CD pipelines, automated testing, deployment strategies, release management, rollback procedures.'
argument-hint: 'CI/CD or deployment item to review or apply (optional)'
---

# CI/CD & Deployment Guidelines

## Overview

This skill defines conventions for CI/CD pipelines and deployment strategies.
It provides practical guidelines for achieving automation, quality gates, and safe releases.

---

## 1. Branch Strategy

### Recommended: GitHub Flow (Simple)

```
main           — Directly tied to production. Always kept in a deployable state
feature/*      — Feature development branches. Fork from main and merge via PR
hotfix/*       — Production incident response. Fork directly from main
```

### Large-Scale Projects: Git Flow

```
main           — Code already released to production
develop        — Integration branch for the next release
feature/*      — Feature development (fork from develop)
release/*      — Release preparation (fork from develop → merge to main)
hotfix/*       — Production incident response (fork from main)
```

### Branch Protection Rules (main)

- **Prohibit direct pushes**
- **Require PR + review approval** (at least 1 reviewer)
- **Require CI to pass**
- **Require up-to-date branches before merge** (Require branches to be up to date)

---

## 2. CI Pipeline Configuration

### Basic Stages

```yaml
# .github/workflows/ci.yml (example)
name: CI

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

jobs:
  quality:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Install dependencies
        run: pnpm install --frozen-lockfile
      - name: Lint
        run: pnpm lint
      - name: Type check
        run: pnpm typecheck
      - name: Unit tests
        run: pnpm test --coverage
      - name: Build
        run: pnpm build
```

### Quality Gates (Required)

| Check | Description |
|---------|------|
| **Lint** | Code style and static analysis |
| **Type check** | No compilation errors |
| **Unit tests** | Coverage must not fall below threshold |
| **Build** | Build completes without errors |
| **Security scan** | Check known vulnerabilities in dependencies |

### Test Coverage Goals

| Type | Goal |
|------|------|
| Statements | 80% or above |
| Branches | 70% or above |
| Functions | 80% or above |
| Lines | 80% or above |

---

## 3. Platform-Specific CI/CD

### iOS / macOS (Xcode Cloud or GitHub Actions)

```yaml
# GitHub Actions example
jobs:
  ios-build:
    runs-on: macos-latest
    steps:
      - uses: actions/checkout@v4
      - name: Install dependencies
        run: bundle install  # Fastlane
      - name: Run tests
        run: bundle exec fastlane test
      - name: Build & Archive
        run: bundle exec fastlane build
      - name: Upload to TestFlight
        run: bundle exec fastlane beta
        env:
          APP_STORE_CONNECT_API_KEY: ${{ secrets.ASC_API_KEY }}
```

**Recommended Fastlane lanes:**
- `test` — Run unit tests and UI tests
- `beta` — Upload to TestFlight
- `release` — Submit to App Store

### Android (GitHub Actions)

```yaml
jobs:
  android-build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Setup JDK
        uses: actions/setup-java@v4
        with:
          java-version: '17'
          distribution: 'temurin'
      - name: Run tests
        run: ./gradlew test
      - name: Build release APK/AAB
        run: ./gradlew bundleRelease
        env:
          KEYSTORE_PASSWORD: ${{ secrets.KEYSTORE_PASSWORD }}
      - name: Upload to Google Play
        uses: r0adkll/upload-google-play@v1
```

### Web (Vercel / Cloudflare Pages / AWS)

```yaml
jobs:
  web-deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Install & Build
        run: pnpm install && pnpm build
      - name: E2E tests
        run: pnpm playwright test
      - name: Deploy to production
        run: vercel --prod
        env:
          VERCEL_TOKEN: ${{ secrets.VERCEL_TOKEN }}
```

---

## 4. Environment Management

### Environment Definitions

| Environment | Purpose | Branch | Auto Deploy |
|------|------|---------|------------|
| **development** | Local development | feature/* | — |
| **staging** | Quality verification / review | develop / PR | ✅ |
| **production** | Production | main | ✅ (after approval) |

### Environment Variable Management

- Manage secrets using GitHub Actions Secrets or a dedicated Secrets Manager (AWS Secrets Manager / GCP Secret Manager)
- Manage values that differ per environment using `Environment`
- Include `.env.example` in the repository and document all required variables

---

## 5. Deployment Strategies

### Canary Release (Web)

Roll out new features gradually rather than deploying to all users at once.

```
Release to 5% of users → Check metrics → 25% → 50% → 100%
Roll back immediately if issues arise
```

### Feature Flags

- Control feature ON/OFF via **configuration, not code**
- Use for gradual rollout, A/B testing, and emergency shutoff
- Tool examples: LaunchDarkly / Unleash / custom implementation

### Blue-Green Deployment

```
Deploy new version (Green) while keeping current production (Blue) live
↓
Confirm Green is healthy
↓
Switch traffic to Green
↓
Roll back to Blue immediately if issues arise
```

---

## 6. Rollback Procedures

### Preparation

- **Always tag releases** — Tag every production release in `v1.2.3` format
- **Database migrations** must be forward-compatible (must work with old code)

### Executing a Rollback

```bash
# Revert to a tag with Git
git checkout v1.2.2

# Or re-deploy a previous version's artifact from GitHub Releases
```

### iOS / Android

- Redistribute a previous version from TestFlight / Firebase App Distribution
- Stop or revert the rollout on App Store / Google Play

---

## 7. Monitoring and Alerts

### Required Metrics

| Metric | Tool Examples |
|---------|---------|
| Error rate / Crash rate | Sentry / Crashlytics / Firebase Crashlytics |
| Response time / Latency | Datadog / New Relic / CloudWatch |
| Core Web Vitals | Google Search Console / Vercel Analytics |
| App ratings / Reviews | App Store Connect / Google Play Console |

### Alert Configuration

- Fire an alert when the error rate exceeds **2× the normal baseline**
- Fire an alert when P95 latency exceeds the threshold
- Notify critical alerts to **Slack / PagerDuty**

---

## 8. Security Scanning

### Dependency Vulnerability Check

```yaml
# Enable GitHub Dependabot (.github/dependabot.yml)
version: 2
updates:
  - package-ecosystem: "npm"
    directory: "/"
    schedule:
      interval: "weekly"
    reviewers:
      - "security-team"
```

### Secret Scanning

- Enable **GitHub Secret Scanning** (free)
- Run `truffleHog` or `gitleaks` in CI

---

## 9. Checklist

- [ ] Direct push protection rule is configured on the main branch
- [ ] PRs require CI pass + review approval
- [ ] Production deployments require an approval flow (manual approval)
- [ ] Secrets are managed in Secrets Manager and not present in code
- [ ] Test coverage thresholds are configured
- [ ] Rollback procedures are documented
- [ ] Dependabot (or equivalent tool) is enabled
- [ ] Error monitoring and alerts are configured
