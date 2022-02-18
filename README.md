# Charon

## What is this?

Charon is a module attribute that runs a validator before executing the function below.

The goal is to abstract away pre-request validation on phoenix controller functions but there
might be other use cases for it that I'm not thinking of.

## Installation

If [available in Hex](https://hex.pm/docs/publish), the package can be installed
by adding `charon` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:charon, "~> 0.1.0"}
  ]
end
```

Documentation can be generated with [ExDoc](https://github.com/elixir-lang/ex_doc)
and published on [HexDocs](https://hexdocs.pm). Once published, the docs can
be found at [https://hexdocs.pm/charon](https://hexdocs.pm/charon).

## TODO

- [ ] OpenAPI generation
- [ ] Tests generation
- [ ] Generic validation functions?
