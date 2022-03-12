defmodule Charon.Response do
  @moduledoc """
  This module should be used when defining Validators it injects the necessary
  functions for Charon to validate your requests
  """
  defmacro __using__(_) do
    quote do
      use Charon.Schema

      require Charon.Response

      import Charon.Response, only: [response: 2]

      @before_compile Charon.Response
    end
  end

  defmacro __before_compile__(%{module: module}) do
    summary = Module.get_attribute(module, :summary) || "Response definitions for #{module}"

    quote do
      def summary(), do: unquote(summary)
    end
  end

  @doc ~S"""
  Defines a response for a specific status code. You can use either the
  numeric or atom represenatation of a HTTP status code.

  These responses are used to auto generate tests and swagger API docs.

  Status code atoms are defined in plug: https://hexdocs.pm/plug/Plug.Conn.Status.html#code/1
  """
  defmacro response(status, block) do
    {status, code} =
      cond do
        is_atom(status) -> {status, Plug.Conn.Status.code(status)}
        is_integer(status) -> {Plug.Conn.Status.reason_atom(status), status}
      end

    status = Atom.to_string(status)
    sub_module = Module.concat(__CALLER__.module, Macro.camelize(status))

    {block, description} = find_and_remove_attribute(:description, block)
    {block, content_type} = find_and_remove_attribute(:content_type, block)
    {block, example} = find_and_remove_attribute(:example, block)

    quote do
      defmodule unquote(sub_module) do
        use Charon.Schema

        unquote(block)

        def __description__(), do: unquote(description)
        def __content_type__(), do: unquote(content_type)
        def __example__(), do: unquote(example)
        def __status__(), do: unquote(code)
      end
    end
  end

  defp find_and_remove_attribute(attribute, block) do
    Macro.postwalk(block, nil, fn
      {:@, _, [{^attribute, _, [attribute]}]}, _acc ->
        {[], attribute}

      block, acc ->
        {block, acc}
    end)
  end
end
