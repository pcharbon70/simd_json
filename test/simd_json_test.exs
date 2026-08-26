defmodule SimdJsonTest do
  use ExUnit.Case, async: true

  doctest SimdJson

  test "defines the library's root module" do
    assert Code.ensure_loaded?(SimdJson)
  end
end
