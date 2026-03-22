# 🌐 Noosphere Browser

> Semantic-native browser for agents. Built for Raspberry Pi.

## Vision

Noosphere transforms the web from a collection of visual pages into a **knowledge graph**. Every page becomes structured data, every link becomes a relation, every fact becomes queryable.

Built to run on edge devices — **$35 Raspberry Pi** included.

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

## Quick Start (Raspberry Pi)

```bash
# Install on Pi 4/5
curl -fsSL https://noosphere.dev/install.sh | bash

# Start the node
noosphere start --port 8080 --storage 10GB

# Access dashboard
open http://localhost:8080
```

## Tech Stack

- **Zig** — HTTP engine, HTML parser, memory-safe, < 1MB binary
- **Elixir** — Phoenix channels for P2P, event processing
- **SQLite** — Embedded hypergraph storage (WAL mode)
- **Nanomsg** — Gossip protocol for Pi-to-Pi mesh
- **Apache Arrow** — Efficient data transfer between nodes

## Features

- [ ] **Semantic Parser** — HTML → Markdown + triples
- [ ] **Knowledge Graph** — Query with SPARQL-like syntax
- [ ] **P2P Sync** — Share knowledge with other nodes
- [ ] **Vector Search** — Find semantically similar content
- [ ] **Edge Deployment** — Runs on 512MB RAM
- [ ] **Offline Mode** — Full knowledge graph offline

## Performance Targets

| Metric | Target | Hardware |
|--------|--------|----------|
| Memory | < 512MB | Pi 4 (1-8GB) |
| Binary size | < 5MB | - |
| Page parse | < 100ms | Pi 4 |
| Cold start | < 2s | Pi 4 |
| Power | 3-8W | - |

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
