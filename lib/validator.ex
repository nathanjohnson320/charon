defmodule Charon.Validator do
  @moduledoc ~S"""
  Compile time macro that adds support for the `@charon`

  You shouldn't have to interact with this module directly it is auto included with `use Charon`
  """

  require Logger

  def __on_definition__(_env, _access, _name, _args, _guards, nil), do: nil
  def __on_definition__(_env, _access, _name, _args, _guards, []), do: nil

  # When functions are defined that have @charon transform add them to the :charon_functions accumulator
  def __on_definition__(%{module: module}, access, name, args, guards, do: body) do
    if info = charon_function?(module, name, length(args)) do
      Module.put_attribute(module, :charon_functions, %{
        module: module,
        access: access,
        function: name,
        args: args,
        guards: guards,
        body: body,
        charon_info: info
      })

      Module.put_attribute(module, :charon_last, {name, length(args)})
      Module.delete_attribute(module, :charon)
    end
  end

  # Take no action if there are other function-level clauses
  def __on_definition__(%{module: module}, _access, name, args, _guards, clauses) do
    if charon_function?(module, name, length(args)) do
      found =
        clauses
        |> Keyword.drop([:do])
        |> Keyword.keys()
        |> Enum.map(&"`#{&1}`")
        |> Enum.join(", ")

      Logger.warn(
        "[Charon] Unable to wrap `#{inspect(module)}.#{name}/#{length(args)}` " <>
          "due to additional function-level clauses: #{found} -- please remove @charon"
      )

      Module.delete_attribute(module, :charon)
    end
  end

  # Before compile take all the charon functions and make them overridable
  defmacro __before_compile__(%{module: module}) do
    Module.delete_attribute(module, :charon_last)
    Module.make_overridable(module, function_specs(module))

    quote do
      (unquote_splicing(function_definitions(module)))
    end
  end

  # Return list of functions that we need to mark as overridable
  def function_specs(module),
    do:
      module
      |> Module.get_attribute(:charon_functions)
      |> Enum.map(fn %{function: function, args: args} -> {function, length(args)} end)
      |> Enum.uniq()

  # Function to loop over :charon_function tagged functions and wrap them with the auto validate
  def function_definitions(module),
    do:
      module
      |> Module.get_attribute(:charon_functions)
      |> Enum.map(&wrapped_function_definition/1)
      |> Enum.reverse()

  # Clause for def with no guards
  def wrapped_function_definition(%{
        module: module,
        access: :def,
        function: function,
        args: args,
        body: body,
        guards: [],
        charon_info: charon_info
      }) do
    quote do
      def unquote(function)(unquote_splicing(args)) do
        unquote(wrapped_function_body(body, module, function, args, charon_info))
      end
    end
  end

  # Clause for def with guards
  def wrapped_function_definition(%{
        module: module,
        access: :def,
        function: function,
        args: args,
        body: body,
        guards: guards,
        charon_info: charon_info
      }) do
    quote do
      def unquote(function)(unquote_splicing(args))
          when unquote_splicing(guards) do
        unquote(wrapped_function_body(body, module, function, args, charon_info))
      end
    end
  end

  # Clause for defp with no guards
  def wrapped_function_definition(%{
        module: module,
        access: :defp,
        function: function,
        args: args,
        body: body,
        guards: [],
        charon_info: charon_info
      }) do
    quote do
      defp unquote(function)(unquote_splicing(args)) do
        unquote(wrapped_function_body(body, module, function, args, charon_info))
      end
    end
  end

  # Clause for defp with guards
  def wrapped_function_definition(%{
        module: module,
        access: :defp,
        function: function,
        args: args,
        body: body,
        guards: guards,
        charon_info: charon_info
      }) do
    quote do
      defp unquote(function)(unquote_splicing(args))
           when unquote_splicing(guards) do
        unquote(wrapped_function_body(body, module, function, args, charon_info))
      end
    end
  end

  @doc ~S"""
  Provided a given controller function and a validator module this function wraps the function below it
  with `ValidatorModule.validate(conn, params)` and renders the errors based on charon: :error_view and
  status code from charon: :error_code

  For example if you have

  ```
  @charon Validator.Create
  def create(conn, params) do
    <internals>
  end
  ```

  that is roughly equivalent to

  ```
  def create(conn, params) do
    case apply(Validator.Create, :validate, [conn, params]) do
      %{valid? true} -> <internals>
      %{errors: _errors} = changeset ->
        error_view = Application.get_env(:charon, :error_view)
        error_code = Application.get_env(:charon, :error_code, 422)
        conn |> put_status(error_code) |> put_view(error_view) |> render("error.json", changeset: changeset)
    end
  end
  ```
  """
  def wrapped_function_body(body, _module, _function, [conn | _rest] = args, validator) do
    quote do
      case apply(unquote(validator), :validate, [unquote_splicing(args)]) do
        %{valid?: true} ->
          unquote(body)

        %{errors: _errors} = changeset ->
          # Normally this is the changeset error view module, the thing you use to render changeset errors
          error_view = Application.get_env(:charon, :error_view)

          # The http code you want to return on errors. Might be a way to let the validator module export this too
          error_code = Application.get_env(:charon, :error_code, 422)

          unquote(conn)
          |> put_status(error_code)
          |> put_view(error_view)
          |> render("error.json", changeset: changeset)
      end
    end
  end

  def charon_function?(module, name, arity),
    do:
      charon_function?(:via_annotation, module) ||
        charon_function?(:via_multiple_heads, module, name, arity)

  def charon_function?(:via_annotation, module), do: Module.get_attribute(module, :charon)

  def charon_function?(:via_multiple_heads, module, name, arity) do
    case Module.get_attribute(module, :charon_last) do
      {^name, ^arity, info} -> info
      _ -> false
    end
  end
end
