defmodule Charon do
  @moduledoc ~S"""
  Charon adds support for abstracting your validation functions from controllers/handlers into external modules.

  ## Example
  Quick example, let's say we have the below controller function

  ```
  def create(conn, params) do
    with {:ok, %NewThing{} = new_thing} <- MyContext.create_new_thing(params) do
      conn
      |> put_status(201)
      |> render("show.json", new_thing: new_thing)
    end
  end
  ```

  Currently there are a lot of ways you can validate the `params` field of this. You can add it to your context
  function, add in some validation function before calling context in the with, or something else. With Charon
  you create an embedded schema that is used to validate the input params.

  So in our above controller function we can add aboce the create definition

  ```
  use Charon

  @charon Validators.NewThing.Create
  def create(conn, params) do
  end
  ```

  This will wrap your create module in a function that calls Validators.NewThing.Create.Request.validate/2.
  If you need to use a different request module name for some reason you can pass it directly

  ```
  @charon [request: Validators.NewThing.SomeSpecificModule, response: Response.SomeSpecificModule]
  def create(conn, params) do
  ```

  Your validator can be anything that returns an ecto changeset result or really anything that returns
  `%{valid?: boolean, errors: []}`

  Example validator for the NewThing.Create

  ```
  defmodule Validators.NewThing.Create do
    use Charon.Schema

    alias __MODULE__

    @all_fields [:user_id, :list_of_ids]
    @required_fields [:list_of_ids]

    embedded_schema do
      field :user_id, :string
      field :list_of_ids, {:array, :string}
    end

    def validate(_conn, params) do
      %Create{}
      |> cast(params, @all_fields)
      |> validate_required(@required_fields)
      |> validate_length(:list_of_ids, min: 1)
      |> validate_change(:list_of_ids, &validate_uuid_list/2)
    end

    defp validate_uuid_list(:list_of_ids, list_of_ids) do
      invalid = Enum.filter(list_of_ids, fn id ->
        not (id =~ ~r/[\w]{8}-?[\w]{4}-?[\w]{4}-?[\w]{4}-?[\w]{12}/)
      end)

      if Enum.empty?(invalid),
        do: [],
        else: [list_of_ids: "invalid format: #{Enum.join(invalid, ", ")}"]
    end
  end
  ```

  Now when we hit our endpoint before it runs the function body we provide, it will run the `Validators.NewThing.Create.validate/2`
  function along with our conn and params as arguments. If we provide invalid input it will short circuit and return a validation
  error up front before it hits the inner function body.

  If at any point you want to remove this validation layer all you have to do is drop the @charon tag
  from your functions, recompile, and it will no longer have that validation.

  ## Sample Test case
  ```
  test "it returns an error if list_of_ids are malformed", %{conn: conn} do
    attrs = %{
      "user_id" => "abc123",
      "list_of_ids" => ["test", "not a uuid"]
    }

    conn = post(conn, Routes.new_thing_path(conn, :create), attrs)

    assert %{
      "errors" => [
        %{
          "message" => "invalid format: test, not a uuid",
          "name" => "list_of_ids"
        }
      ]
    } = json_response(conn, 422)
  end
  ```
  ## Configuration

  Currently Charon supports two app level configuration values

  * :error_view
    * This is the view module used to render errors. It should be the equivalen MyAppWeb.ChangesetView or compatible renderer.
    * example: `config :charon, error_view: MyAppWeb.ChangesetView`
  * :error_code
    * The http status code to return when the validation fails. Defaults to 422
    * example: `config :charon, error_code: 400`
  """

  require Charon.Request

  defmacro __using__(_args) do
    quote do
      require Charon

      # Ensure list of charon functions is accumulated at compile time
      Module.register_attribute(__MODULE__, :charon_functions, accumulate: true)
      # Do not accumulate the last function checked
      Module.register_attribute(__MODULE__, :charon_last, accumulate: false)
      # Keep track of request status codes
      Module.register_attribute(__MODULE__, :status_code, accumulate: true)
      @before_compile Charon
      @on_definition Charon
    end
  end

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
  with `RequestModule.validate(conn, params)` and renders the errors based on charon: :error_view and
  status code from charon: :error_code

  For example if you have

  ```
  @charon Request.Create
  def create(conn, params) do
    <internals>
  end
  ```

  that is roughly equivalent to

  ```
  def create(conn, params) do
    case apply(Request.Create.Request, :validate, [conn, params]) do
      %{valid? true} -> <internals>
      %{errors: _errors} = changeset ->
        error_view = Application.get_env(:charon, :error_view)
        error_code = Application.get_env(:charon, :error_code, 422)
        conn |> put_status(error_code) |> put_view(error_view) |> render("error.json", changeset: changeset)
    end
  end
  ```
  """
  def wrapped_function_body(body, module, function, args, charon_module)
      when is_atom(charon_module) do
    request = Module.concat(charon_module, Request)
    response = Module.concat(charon_module, Response)
    wrapped_function_body(body, module, function, args, request: request, response: response)
  end

  def wrapped_function_body(body, _module, _function, [conn | _rest] = args,
        request: request,
        response: _response
      ) do
    Charon.Request.validate(%{module: request, conn: conn}, args, body)
  end

  def charon_function?(module, name, arity),
    do:
      charon_function?(:via_annotation, module) ||
        charon_function?(:via_multiple_heads, module, name, arity)

  def charon_function?(:via_annotation, module),
    do: Module.get_attribute(module, :charon)

  def charon_function?(:via_multiple_heads, module, name, arity) do
    case Module.get_attribute(module, :charon_last) do
      {^name, ^arity, info} -> info
      _ -> false
    end
  end
end
