# Database

A collection of SQL-compatible in-memory relational databases implemented in Elixir.

## Available Databases

### PostgreSQL-Compatible Database (postgres_db)

An in-memory database that supports PostgreSQL SQL syntax, including:
- SERIAL/BIGSERIAL auto-incrementing columns
- RETURNING clause for INSERT/UPDATE/DELETE
- LIMIT/OFFSET pagination
- ILIKE case-insensitive pattern matching
- PostgreSQL-specific functions and types

See [postgres_db/README.md](postgres_db/README.md) for details.

## Quick Start

```elixir
# PostgreSQL-compatible database
{:ok, db} = PostgresDb.start_link()

PostgresDb.execute(db, "CREATE TABLE users (id SERIAL PRIMARY KEY, name VARCHAR(100))")
PostgresDb.execute(db, "INSERT INTO users (name) VALUES ('John') RETURNING id")
{:ok, rows} = PostgresDb.execute(db, "SELECT * FROM users LIMIT 10")
```

## Running Tests

```bash
# PostgreSQL database tests
cd postgres_db
mix test
```

## License

MIT