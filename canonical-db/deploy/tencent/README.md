# Tencent deployment package

This package deploys the tested empty PostgreSQL 16 Canonical database. The default database name is `phoenix_canonical_dev` and must be confirmed before installation. It publishes no PostgreSQL host port. The pinned Linux/AMD64 image digest is the same PostgreSQL 16 image tested locally; Tencent Cloud's mirror is used only as the registry endpoint and the digest remains locked.

Upload the complete `canonical-db` directory, copy `.env.example` to `.env`, replace every password with an independent 64-character lowercase hexadecimal secret, run `chmod 600 .env` and `chmod 700 *.sh`, then run `./install.sh`. The script applies all migrations with checksum verification and provisions separate migrator, application, reader and context-binder logins.

Run `health.sh` after installation and `backup.sh` for a unique custom-format backup plus SHA-256 manifest. These scripts use container-local TCP plus 0600 pgpass files and non-superuser runtime roles; they do not put a bootstrap password in a command-line environment. Do not add a `ports:` mapping for 5432. An application container must explicitly join `phoenix_canonical_private`.

The deployment contains no customer data and does not import legacy databases, Founder OS, D1, Feishu or object bytes.
