defmodule Test.Support.Router do
  use Charon

  @charon_validate Test.Support.Validator
  def create(conn, params) do
    conn |> send_resp(inspect(params))
  end

  def put_view(conn, module), do: Map.put(conn, :view, module)

  def render(conn, template, params) do
    params = Enum.into(params, %{})
    Map.put(conn, :body, apply(conn.view, :render, [template, params]))
  end

  def put_status(conn, status) do
    Map.put(conn, :status_code, status)
  end

  def send_resp(conn, body) do
    %{
      status_code: conn.status_code,
      body: body
    }
  end
end
