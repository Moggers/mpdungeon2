# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build/Run/Test Commands

- Build: `cargo build`
- Run: `cargo run -- -n <username> -p <password> [server_addr]`
- Check (lint): `cargo check`
- Test: `cargo test`
- Run specific test: `cargo test <test_name>`
- Test migrations: `sql migrate revert` until there are no migrations left undo and then running `sql migrate run`.

## Code Style Guidelines

- **Imports**: Group imports by crate; standard library first, then external crates, finally internal modules
- **Formatting**: Use 4-space indentation; avoid lines over 100 characters
- **Types**: Use Rust's strong type system; prefer Option<T> over nullable types
- **Error Handling**: Use unwrap() only in prototyping; prefer Result/Option pattern matching in production code
- **Naming**: Use snake_case for functions, variables, modules; CamelCase for types/structs; SCREAMING_CASE for constants
- **SQL**: Use query_file!() macro for SQL queries, keeping SQL in dedicated .sql files
- **Documentation**: Document public interfaces with comments

Before committing, run `cargo check` to ensure code compiles without errors.
