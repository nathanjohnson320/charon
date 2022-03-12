defmodule Test.Support.Example.Response do
  use Charon.Response

  @summary "Sends a sample response"

  response :ok do
    embedded_schema do
      field(:name, :string)
      field(:email, :string)
    end
  end

  response :not_found do
    @description "A test description"
    @example "Not found"
    @content_type "application/json"

    embedded_schema do
      field(:message, :string)
    end
  end

  response 422 do
    embedded_schema do
      embeds_many(:errors, Test.Support.Example.Error)
    end
  end
end
