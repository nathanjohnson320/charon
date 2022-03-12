defmodule CharonResponseTest do
  use ExUnit.Case

  test "generates response for integers" do
    assert Test.Support.Example.Response.UnprocessableEntity.__status__() == 422
  end

  test "generates response for atoms" do
    assert Test.Support.Example.Response.Ok.__status__() == 200
  end

  test "generates descriptions from attributes" do
    assert Test.Support.Example.Response.NotFound.__description__() == "A test description"
  end

  test "generates content type from attributes" do
    assert Test.Support.Example.Response.NotFound.__content_type__() == "application/json"
  end

  test "generates example from attributes" do
    assert Test.Support.Example.Response.NotFound.__example__() == "Not found"
  end
end
