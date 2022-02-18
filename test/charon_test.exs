defmodule CharonTest do
  use ExUnit.Case
  doctest Charon

  alias Test.Support.Router
  alias Test.Support.ErrorView

  setup do
    Application.put_env(:charon, :error_view, ErrorView)
    {:ok, [conn: %{}]}
  end

  test "runs all validations on attributed function", %{conn: conn} do
    attrs = %{
      "user_id" => nil,
      "list_of_ids" => ["test", "not a uuid"]
    }

    assert %{
             body: %{
               errors: %{
                 user_id: ["can't be blank"],
                 list_of_ids: ["invalid format: test, not a uuid"]
               }
             },
             status_code: 422,
             view: Test.Support.ErrorView
           } == Router.create(conn, attrs)
  end
end
