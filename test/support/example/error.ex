defmodule Test.Support.Example.Error do
  use Charon.Schema

  embedded_schema do
    field(:message, :string)
  end
end
