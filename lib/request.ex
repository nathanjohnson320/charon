defmodule Charon.Request do
  @moduledoc ~S"""
  Module that adds some simple logic to keep track of request information.
  """

  defmacro __using__(_args) do
    quote do
      use Charon.Schema

      # Keep track of request status codes
      Module.register_attribute(__MODULE__, :status_code, persist: true, accumulate: false)
    end
  end

  def validate(%{module: module, conn: conn}, function_args, body) do
    function_args = Enum.filter(function_args, &unused_args/1)

    status_code =
      :attributes
      |> module.__info__()
      |> Keyword.get(:status_code)
      |> List.first()

    quote do
      case apply(unquote(module), :validate, [
             unquote_splicing(function_args)
           ]) do
        %{valid?: true} ->
          unquote(body)

        %{errors: _errors} = changeset ->
          # Normally this is the changeset error view module, the thing you use to render changeset errors
          error_view = Application.get_env(:charon, :error_view)

          unquote(conn)
          |> put_status(unquote(status_code))
          |> put_view(error_view)
          |> render("error.json", changeset: changeset)
      end
    end
  end

  defp unused_args({arg, _, _}) do
    arg = to_string(arg)

    case arg do
      <<"_", _rest::binary>> -> false
      _ -> true
    end
  end
end
