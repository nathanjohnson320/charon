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

  @charon_validate Validators.NewThing.Create
  def create(conn, params) do
  end
  ```

  This will wrap your create module in a function that calls Validators.NewThing.Create.validate/2

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

  If at any point you want to remove this validation layer all you have to do is drop the @charon_validate tag
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
    * example: `config :charon_validate, error_view: MyAppWeb.ChangesetView`
  * :error_code
    * The http status code to return when the validation fails. Defaults to 422
    * example: `config :charon_validate, error_code: 400`
  """
  defmacro __using__(_args) do
    quote do
      require Charon
      require Charon.Validator
      # Ensure list of charon functions is accumulated at compile time
      Module.register_attribute(__MODULE__, :charon_functions, accumulate: true)
      # Do not accumulate the last function checked
      Module.register_attribute(__MODULE__, :charon_last, accumulate: false)
      @before_compile Charon.Validator
      @on_definition Charon.Validator
    end
  end
end
