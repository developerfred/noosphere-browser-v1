# 🌐 Noosphere Browser

> Semantic-native browser for agents. Built for Raspberry Pi.

**Multi-platform**: Linux (x86_64, ARM), macOS (Intel, Apple Silicon), Windows

## Vision

Noosphere transforms the web from visual pages into a **knowledge graph**. Every page becomes structured data, every link becomes a relation, every fact becomes queryable.

Built to run on edge devices — **$35 Raspberry Pi** included.

## Quick Start

### Download Pre-built Binary

```bash
# Linux/macOS
curl -fsSL https://raw.githubusercontent.com/developerfred/noosphere-browser-v1/master/install.sh | bash

# Or manually download from Releases:
# https://github.com/developerfred/noosphere-browser-v1/releases
```

### Build from Source

**Requirements:**
- Zig 0.13+ ([Install](https://ziglang.org/download/))

```bash
# Clone
git clone https://github.com/developerfred/noosphere-browser-v1.git
cd noosphere-browser-v1

# Build for current platform
make build

# Or build for specific platform
make build-linux-x86      # Linux x86_64
make build-linux-arm64    # Linux ARM64 (Raspberry Pi 4)
make build-linux-armv7    # Linux ARMv7 (Raspberry Pi 3)
make build-macos-intel    # macOS Intel
make build-macos-apple    # macOS Apple Silicon
make build-windows        # Windows

# Build ALL platforms
make build-all
```

### Installation

```bash
# System-wide (requires sudo)
sudo make install

# User-local (adds to ~/.local/bin)
mkdir -p ~/.local/bin
cp zig-out/bin/noosphere ~/.local/bin/
export PATH=$PATH:$HOME/.local/bin
```

## Usage

```bash
# Show help
noosphere --help

# Fetch and store a page
noosphere --fetch https://example.com

# Start interactive mode
noosphere

# Query the knowledge graph
noosphere --query "Albert Einstein"

# Show knowledge graph
noosphere --graph

# Server mode (coming soon)
noosphere --server
```

## Supported Platforms

| Platform | Architecture | Status |
|----------|--------------|--------|
| **Linux** | x86_64 | ✅ Built |
| **Linux** | aarch64 (Pi 4) | ✅ Built |
| **Linux** | armv7 (Pi 3) | ✅ Built |
| **macOS** | Intel | ✅ Built |
| **macOS** | Apple Silicon | ✅ Built |
| **Windows** | x86_64 | ✅ Built |

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                         NOOSPHERE                             │
│                                                              │
│   ┌──────────┐   ┌───────────┐   ┌────────────────────┐    │
│   │   ZIG    │   │   ELIXIR  │   │   SEMANTIC ENGINE  │    │
│   │  HTTP/   │──▶│  Phoenix  │──▶│  HTML → Triples    │    │
│   │  HTML    │   │  Channels │   │  Knowledge Graph   │    │
│   └──────────┘   └───────────┘   └────────────────────┘    │
│         │               │                    │               │
│         └───────────────┴────────────────────┘               │
│                         │                                    │
│              ┌──────────┴──────────┐                        │
│              │   HYPERGRAPH STORE   │                        │
│              │   (embedded SQLite) │                        │
│              └─────────────────────┘                        │
│                                                              │
│   💾 Embedded   ⚡ Fast   🔗 P2P-ready                     │
└─────────────────────────────────────────────────────────────┘
```

## Key Concepts

### Semantic Snapshots
Every page is parsed into **semantic triples**:
```
(subject) ──[predicate]──▶ (object)
```

Example:
```
Wikipedia:Albert_Einstein ──[born_in]──▶ Ulm
Wikipedia:Albert_Einstein ──[occupation]──▶ physicist
Wikipedia:Albert_Einstein ──[worked_with]──▶ Wikipedia:Niels_Bohr
```

### Hypergraph vs DOM
| DOM (Traditional) | Hypergraph (Noosphere) |
|-------------------|------------------------|
| Tree structure | Graph (any-to-any) |
| Render to pixels | Extract knowledge |
| Humans read | Agents query |
| Cache HTML | Cache semantics |

## Tech Stack

- **Zig** — HTTP engine, HTML parser, memory-safe, < 5MB binary
- **Elixir** — Phoenix channels for P2P (future)
- **SQLite** — Embedded hypergraph storage (WAL mode)
- **Nanomsg** — Gossip protocol for Pi-to-Pi mesh (future)

## Performance Targets

| Metric | Target | Hardware |
|--------|--------|----------|
| Memory | < 512MB | Pi 4 (1-8GB) |
| Binary size | < 5MB | - |
| Page parse | < 100ms | Pi 4 |
| Cold start | < 2s | Pi 4 |
| Power | 3-8W | - |

## Features

- [x] **HTTP Client** — Pure Zig, no libcurl
- [x] **HTML Parser** — HTML → Markdown + triples
- [x] **Entity Extraction** — Persons, organizations, URLs, dates
- [x] **JSON Storage** — Embedded, no server
- [ ] **SQLite Storage** — Full-text search
- [ ] **P2P Sync** — Share knowledge with other nodes
- [ ] **Vector Search** — Find semantically similar content
- [ ] **Phoenix Server** — HTTP API + WebSocket
- [ ] **Cross-compile** — Pre-built binaries for all platforms

## Contributing

1. Fork the repo
2. Create your feature branch (`git checkout -b feature/amazing`)
3. Commit your changes (`git commit -am 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing`)
5. Open a Pull Request

## License

Apache 2.0 — see [LICENSE](LICENSE)

---

**The web is knowledge. Let's treat it that way.**

🔗 [GitHub](https://github.com/developerfred/noosphere-browser-v1) | 
🔗 [Codeberg](https://codeberg.org/codingsh/noosphere-browser) | 
🔗 [Extension](https://github.com/developerfred/noosphere-extension-v1)
