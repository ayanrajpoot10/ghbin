# ghbin

A simple command-line tool to install pre-compiled binaries from GitHub releases.

## Features

- Install binaries from GitHub releases with a single command
- Automatic architecture and OS detection
- Update installed packages to the latest version
- List and manage installed packages
- Search available releases
- Local package database tracking

## Installation

```bash
curl -sSL https://raw.githubusercontent.com/ayanrajpoot10/ghbin/main/install.sh | bash
```

## Requirements

- `curl`
- `jq`
- `bash`

## Usage

Install a package:
```bash
ghbin install owner/repo
ghbin install owner/repo@v1.2.3  # specific version
```

List installed packages:
```bash
ghbin list
```

Update a package:
```bash
ghbin update owner/repo
```

Remove a package:
```bash
ghbin remove owner/repo
```

Search releases:
```bash
ghbin search owner/repo
```

Get package info:
```bash
ghbin info owner/repo
```

## Configuration

Configuration files are stored in `~/.config/ghbin/`:
- `config` - Configuration settings
- `packages.db` - Installed packages database

Binaries are installed to `~/.local/bin` by default.

Set `GITHUB_TOKEN` environment variable for higher API rate limits.

## License

MIT License - see LICENSE file for details.
