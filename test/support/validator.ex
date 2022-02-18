defmodule Test.Support.Validator do
  use Charon.Schema

  alias __MODULE__

  @all_fields [:user_id, :list_of_ids]
  @required_fields [:user_id, :list_of_ids]

  embedded_schema do
    field(:user_id, :string)
    field(:list_of_ids, {:array, :string})
  end

  def validate(_conn, params) do
    %Validator{}
    |> cast(params, @all_fields)
    |> validate_required(@required_fields)
    |> validate_length(:list_of_ids, min: 1)
    |> validate_change(:list_of_ids, &validate_uuid_list/2)
  end

  defp validate_uuid_list(:list_of_ids, list_of_ids) do
    invalid =
      Enum.filter(list_of_ids, fn id ->
        not (id =~ ~r/[\w]{8}-?[\w]{4}-?[\w]{4}-?[\w]{4}-?[\w]{12}/)
      end)

    if Enum.empty?(invalid),
      do: [],
      else: [list_of_ids: "invalid format: #{Enum.join(invalid, ", ")}"]
  end
end
