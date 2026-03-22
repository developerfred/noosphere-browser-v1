# Security Policy - Noosphere

## Supported Versions

| Version | Status | Security Updates |
|---------|--------|------------------|
| v1.0.x | Alpha | ✅ Supported |

## Reporting a Vulnerability

If you discover a security vulnerability, please report it to:

1. Open an issue with the label `security`
2. Or email: security@noosphere.dev

**Please do NOT disclose security issues publicly until we have a fix.**

## Security Features

### Browser (Zig)

✅ **URL Validation**
- Blocked schemes: `javascript:`, `data:`, `file:`, `ftp:`
- Host length limit: 253 characters
- Path length limit: 2048 characters
- HTTP warning for non-localhost connections

✅ **Memory Safety**
- Zig language provides memory safety
- No manual memory management
- No buffer overflow risks

✅ **No Shell Execution**
- No `system()` or `exec()` calls
- All I/O through safe Zig stdlib

### Extension (Chrome/Firefox)

✅ **Content Script Security**
- All extracted content is sanitized
- HTML entities escaped in extracted text
- URL scheme blocking (no `javascript:` URLs)
- DOM cloning to prevent XSS

✅ **Permission Model**
- Minimal permissions: `activeTab`, `storage`, `contextMenus`
- `host_permissions: <all_urls>` required for content script
- No access to browser tabs without user action

✅ **Input Validation**
- Request validation in message handler
- Output sanitization for all extracted data
- Entity/relation limits to prevent DoS

## Known Security Considerations

### Extension `<all_urls>` Permission

Required for the content script to work on all websites. The extension only:
- Reads page content when user clicks the icon
- Stores data locally in IndexedDB
- Does NOT send data to any server

### P2P Communication (Future)

When P2P sync is implemented:
- All peer-to-peer traffic will be encrypted
- TLS/certificates for authentication
- No plaintext communication

## Security Checklist

- [x] URL scheme validation
- [x] URL length limits
- [x] HTML sanitization
- [x] XSS prevention
- [x] Input validation
- [x] Output sanitization
- [x] Entity/Relation limits
- [x] No shell execution
- [x] No hardcoded credentials
- [x] Rate limiting (src/ratelimit.zig)
- [x] Access control (src/access.zig, src/secure_store.zig)
- [ ] TLS certificate validation (future)
- [ ] P2P encryption (future)
