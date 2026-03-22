# 🌐 Noosphere Browser

> Semantic-native browser for AI agents. Built for Raspberry Pi.

**Multi-platform**: Linux (x86_64, ARM), macOS (Intel, Apple Silicon), Windows

[![License](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](https://www.apache.org/licenses/LICENSE-2.0)
[![Platform](https://img.shields.io/badge/platform-Linux%20%7C%20macOS%20%7C%20Windows%20%7C%20Raspberry%20Pi-yellow.svg)](https://github.com/developerfred/noosphere-browser-v1)

## 🔮 What is Noosphere?

Noosphere transforms the web from visual pages into a **knowledge graph**. Instead of rendering HTML to pixels, it extracts:

- **Entities** (persons, organizations, locations, URLs, dates, numbers)
- **Relations** (subject-predicate-object triples)
- **Content** (clean Markdown)

## ✨ Features

### Core
- 🌐 HTTP fetching with URL validation
- 📄 HTML to Markdown conversion
- 🧠 Entity extraction (PERSON, ORG, LOCATION, URL, DATE, QUANTITY)
- 🔗 Relation detection
- 💾 Local JSON storage
- 🔒 Rate limiting & access control

### Research (v1.1)
- 📚 **ArXiv integration** - Search and fetch research papers
- 📊 **Table extraction** - HTML tables to CSV/JSON/Markdown
- 📝 **Citation graph** - Build academic citation networks
- 🗺️ **Sitemap discovery** - Find all pages on a domain
- 📡 **RSS/Atom feeds** - Parse content feeds

### RAG (v1.2)
- 📦 **Text chunking** - Semantic, fixed, sentence-based
- 🔍 **API discovery** - Find hidden REST/GraphQL APIs
- 🗄️ **Archive access** - Wayback Machine fallback

## 🚀 Quick Start

### Pre-built Binaries (Recommended)

Download from [Releases](https://github.com/developerfred/noosphere-browser-v1/releases):

| Platform | Binary |
|----------|--------|
| Linux x86_64 | `noosphere-x86_64-linux` |
| Linux ARM64 (Pi 4) | `noosphere-aarch64-linux` |
| macOS Intel | `noosphere-x86_64-macos` |
| macOS Apple Silicon | `noosphere-aarch64-macos` |
| Windows | `noosphere-x86_64-windows.exe` |

```bash
# Download and run
curl -L -o noosphere https://github.com/developerfred/noosphere-browser-v1/releases/latest/download/noosphere-ARCH
chmod +x noosphere
./noosphere --help
```

### Build from Source (Zig)

**Requirements:**
- [Zig 0.13+](https://ziglang.org/download/)

```bash
# Clone
git clone https://github.com/developerfred/noosphere-browser-v1.git
cd noosphere-browser-v1

# Build for current platform
make build

# Build for Raspberry Pi
make build-linux-arm64

# Build ALL platforms
make build-all
```

### Build from Source (C Fallback)

If Zig is not available, the C fallback can be compiled with gcc/clang:

```bash
# Clone
git clone https://github.com/developerfred/noosphere-browser-v1.git
cd noosphere-browser-v1

# Compile C fallback
gcc -O2 -o noosphere_c c/main.c

# Run
./noosphere_c --help
```

The C version includes:
- ✅ URL validation (blocks javascript:, data:, file:, ftp:)
- ✅ Rate limiting (10/s, 100/m, 1000/h)
- ✅ Entity extraction
- ✅ HTML to text conversion
- ✅ JSON storage ready

### Usage

```bash
# Show help
noosphere --help

# Fetch and store a page
noosphere --fetch https://example.com

# Query the knowledge graph
noosphere --query "Albert Einstein"

# Show knowledge graph
noosphere --graph

# Interactive mode
noosphere
```

## 📦 Pre-built Binaries

Coming soon! For now, [build from source](#build-from-source).

### Supported Platforms

| Platform | Architecture | Build Command |
|----------|--------------|---------------|
| Linux | x86_64 | `make build-linux-x86` |
| Linux | ARM64 (Pi 4) | `make build-linux-arm64` |
| Linux | ARMv7 (Pi 3) | `make build-linux-armv7` |
| macOS | Intel | `make build-macos-intel` |
| macOS | Apple Silicon | `make build-macos-apple` |
| Windows | x86_64 | `make build-windows` |

## 🤖 For AI Agents

See [AGENTS.md](./AGENTS.md) for complete agent integration guide.

**Quick agent install:**
```bash
curl -fsSL https://git.io/noosphere-install | bash
```

**Agent usage:**
```bash
# Fetch page → extract knowledge
noosphere --fetch <url>

# Query stored knowledge
noosphere --query <search-term>
```

**Output format:**
```json
{
  "title": "Albert Einstein",
  "entities": [
    {"type": "PERSON", "text": "Albert Einstein", "count": 5}
  ],
  "relations": [
    {"type": "born_in", "from": "Albert Einstein", "to": "Ulm"}
  ]
}
```

## 🏗️ Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                         NOOSPHERE                             │
│                                                              │
│   ┌──────────┐   ┌───────────┐   ┌────────────────────┐    │
│   │   ZIG    │   │  Parser   │   │   Semantic Engine  │    │
│   │  HTTP/   │──▶│  HTML→MD  │──▶│  Entities+Relations│    │
│   │  Client  │   │           │   │                    │    │
│   └──────────┘   └───────────┘   └────────────────────┘    │
│         │               │                    │               │
│         └───────────────┴────────────────────┘               │
│                         │                                    │
│              ┌──────────┴──────────┐                        │
│              │   Knowledge Graph     │                        │
│              │   (JSON/SQLite)      │                        │
│              └──────────────────────┘                        │
└─────────────────────────────────────────────────────────────┘
```

## 📁 Project Structure

```
noosphere-browser/
├── src/
│   ├── main.zig      # CLI entry point
│   ├── http.zig      # HTTP client
│   ├── parser.zig    # HTML → Markdown + entities
│   └── store.zig     # Knowledge graph storage
├── Makefile          # Build system
├── install.sh         # Installer script
├── AGENTS.md         # AI agent documentation
├── README.md         # This file
└── LICENSE
```

## Security

| Feature | Status |
|---------|--------|
| URL Validation | ✅ Blocked: javascript:, data:, file:, ftp: |
| URL Length Limits | ✅ Host: 253, Path: 2048 |
| HTTPS Enforcement | ✅ HTTP warns for non-localhost |
| Rate Limiting | ✅ Configurable per second/minute/hour |
| Access Control | ✅ ACL-based read/write/admin |
| HTML Sanitization | ✅ Extension escapes all extracted content |
| XSS Prevention | ✅ Extension sanitizes URLs and text |
| No Shell Execution | ✅ Zig stdlib only |

See [SECURITY.md](./SECURITY.md) for full security policy.

## 🔌 Related Projects

| Project | GitHub | Description |
|---------|--------|-------------|
| **Extension** | [noosphere-extension-v1](https://github.com/developerfred/noosphere-extension-v1) | Chrome/Firefox extension |
| **Landing** | [noosphere-landing](https://github.com/developerfred/noosphere-landing) | Landing page |

## 📄 License

Apache 2.0 - see [LICENSE](LICENSE)

---

**The web is knowledge. Let's treat it that way.**

🌐 [GitHub](https://github.com/developerfred/noosphere-browser-v1) | 
📖 [Docs](https://github.com/developerfred/noosphere-browser-v1/blob/master/README.md) |
🤖 [For Agents](https://github.com/developerfred/noosphere-browser-v1/blob/master/AGENTS.md)
