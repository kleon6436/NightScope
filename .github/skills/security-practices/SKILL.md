---
name: security-practices
description: 'Reference and apply security best practices. Use when: implementing authentication, securing API keys, input validation, encryption, OWASP Top 10 compliance, platform-specific security.'
argument-hint: 'Security topic to check or apply (optional)'
---

# Security Best Practices

## Overview

This skill defines security implementation guidelines for applications.
It covers cross-platform security measures based on the OWASP Top 10.

---

## 1. Authentication and Authorization

### Principles

- **Principle of Least Privilege** — Grant users only the minimum permissions they need
- **Separate Authentication from Authorization** — Implement "who are you" and "what can you do" independently
- **Session Management** — Session IDs must have sufficient randomness and be invalidated after logout

### Token Management

```ts
// ✅ Good: Store token in HttpOnly Cookie (Web)
// → Not accessible from JavaScript → XSS-resistant
res.cookie('accessToken', token, {
  httpOnly: true,
  secure: true,
  sameSite: 'strict',
  maxAge: 15 * 60 * 1000, // 15 minutes
});

// ❌ Bad: Store token in localStorage (stolen by XSS)
localStorage.setItem('accessToken', token);
```

### JWT Handling

- Do not include sensitive information (passwords, credit card numbers, etc.) in the payload
- Set a short expiry (`exp`) and use refresh tokens to renew
- Use `RS256` (RSA) or `ES256` (ECDSA) for the signing algorithm. Use `HS256` with caution as it requires shared secret management

---

## 2. Input Validation

### Principles

- **Always validate server-side** — Client-side validation is only a UX aid
- **Whitelist approach** — Define allowed formats and reject everything else
- **Use a validation library** — Hand-rolled parsing implementations are a source of bugs

```ts
// ✅ Good: Schema validation with Zod (TypeScript / Web)
import { z } from 'zod';

const UserSchema = z.object({
  email: z.string().email(),
  age: z.number().int().min(0).max(150),
  name: z.string().min(1).max(100),
});

const parsed = UserSchema.safeParse(req.body);
if (!parsed.success) {
  return res.status(400).json({ errors: parsed.error.flatten() });
}
```

### SQL Injection Prevention

```ts
// ✅ Good: Prepared statements
const user = await db.query(
  'SELECT * FROM users WHERE email = $1',
  [email]
);

// ❌ Bad: String concatenation
const user = await db.query(
  `SELECT * FROM users WHERE email = '${email}'`
);
```

### XSS Prevention

```ts
// ✅ Good: React auto-escapes
<p>{userInput}</p>

// ❌ Bad: dangerouslySetInnerHTML (sanitize with DOMPurify if unavoidable)
<div dangerouslySetInnerHTML={{ __html: userInput }} />

// When using DOMPurify
import DOMPurify from 'dompurify';
<div dangerouslySetInnerHTML={{ __html: DOMPurify.sanitize(userInput) }} />
```

---

## 3. Secrets and API Key Management

### Principles

- **Do not hardcode secrets in code**
- **Do not commit secrets to the repository** (add `.env` to `.gitignore`)
- **Minimum-scope secrets** — Grant only the required access

### Web / Server-side

```bash
# .env file (not included in the repository)
DATABASE_URL=postgresql://...
STRIPE_SECRET_KEY=sk_live_...
JWT_SECRET=...
```

```ts
// ✅ Good: Read from environment variables
const apiKey = process.env.STRIPE_SECRET_KEY;
if (!apiKey) throw new Error('STRIPE_SECRET_KEY is not set');
```

### iOS / macOS (Swift)

```swift
// ✅ Good: Save to Keychain
import Security

func saveToKeychain(key: String, value: String) {
    let data = value.data(using: .utf8)!
    let query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrAccount as String: key,
        kSecValueData as String: data,
    ]
    SecItemAdd(query as CFDictionary, nil)
}

// ❌ Bad: Save sensitive data in UserDefaults
UserDefaults.standard.set(apiKey, forKey: "apiKey")
```

### Android (Kotlin)

```kotlin
// ✅ Good: Save in EncryptedSharedPreferences
val masterKey = MasterKey.Builder(context)
    .setKeyScheme(MasterKey.KeyScheme.AES256_GCM)
    .build()

val prefs = EncryptedSharedPreferences.create(
    context, "secret_prefs", masterKey,
    EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV,
    EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM
)
```

---

## 4. Encryption

### Encryption at Rest

| Platform | Recommended Approach |
|--------------|---------|
| iOS / macOS | Keychain (secrets) · `CryptoKit` (data encryption) |
| Android | `EncryptedSharedPreferences` / `EncryptedFile` / Keystore |
| Web (browser) | Web Crypto API (recommended to manage sensitive data server-side) |
| Server | AES-256-GCM, argon2id (password hashing) |

### Encryption in Transit

- Use **HTTPS (TLS 1.2 or higher)** for all communication
- Forbid fallback to HTTP (HSTS configuration recommended)
- Validate certificate validity and do not use self-signed certificates in production

---

## 5. OWASP Top 10 Compliance Checklist

| # | Risk | Countermeasure |
|---|--------|------|
| A01 | Broken Access Control | Principle of least privilege · server-side authorization checks |
| A02 | Cryptographic Failures | TLS · AES-256 · argon2id · Keychain/Keystore |
| A03 | Injection | Prepared statements · input validation |
| A04 | Insecure Design | Threat modeling · define security requirements |
| A05 | Security Misconfiguration | Review default settings · close unnecessary ports |
| A06 | Vulnerable and Outdated Components | Regular dependency updates · configure Dependabot |
| A07 | Identification and Authentication Failures | MFA · brute-force protection · session management |
| A08 | Software and Data Integrity Failures | Signature verification in CI/CD pipelines |
| A09 | Security Logging and Monitoring Failures | Log authentication failures · anomaly detection alerts |
| A10 | Server-Side Request Forgery (SSRF) | Whitelist validation for external request URLs |

---

## 6. Platform-Specific Notes

### iOS / macOS

- Do not disable App Transport Security (ATS)
- Always apply whitelist validation when handling deep link URLs
- Exclude sensitive data from iCloud / backup (`isExcludedFromBackup`)

### Android

- Set `android:exported="true"` only on necessary Activities
- When using `WebView.setJavaScriptEnabled(true)`, allow only trusted URLs
- Enable `StrictMode` in development environments to inspect network and disk access

### Web

- Set `Content-Security-Policy` (CSP) headers
- Prevent clickjacking with `X-Frame-Options: DENY`
- Set `HttpOnly`, `Secure`, and `SameSite=Strict` on cookies

---

## 7. Security Review Process

After implementation, conduct a security review using `agents/security-reviewer.agent.md`.

### Review Points

- [ ] No secrets or API keys hardcoded in the code
- [ ] All inputs validated server-side
- [ ] Authentication and authorization checks performed server-side
- [ ] Data storage and communication properly encrypted
- [ ] Checked for known vulnerabilities in dependencies
- [ ] Error messages do not expose internal information (stack traces, etc.)
- [ ] Logs do not output sensitive information (passwords, tokens, etc.)
