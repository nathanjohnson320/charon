defmodule Charon.Schema do
  @moduledoc """
  This module should be used when defining Validators it injects the necessary
  functions for Charon to validate your requests

  ## Example

      defmodule Validators.User.Create do
        use Charon.Schema

        embedded_schema do
          field :assigned_user_id, :string
          field :outbounds, {:array, :string}
        end
      end
  """
  defmacro __using__(_) do
    quote do
      use Ecto.Schema

      import Ecto.Changeset
    end
  end
end
