defmodule SimdJson.Error do
  @moduledoc """
  A stable, redacted error returned by `SimdJson` operations.

  Callers should branch on `reason`. The message is explanatory and may evolve.
  """

  @type reason ::
          :invalid_json
          | :invalid_utf8
          | :unexpected_eof
          | :out_of_memory
          | :closed
          | :not_owner
          | :native_failure

  @enforce_keys [:reason, :message]
  defstruct [:reason, :byte_offset, :native_code, :message]

  @type t :: %__MODULE__{
          reason: reason(),
          byte_offset: non_neg_integer() | nil,
          native_code: integer() | nil,
          message: String.t()
        }
end

defimpl Inspect, for: SimdJson.Error do
  import Inspect.Algebra

  def inspect(error, options) do
    fields = [
      reason: error.reason,
      byte_offset: error.byte_offset,
      native_code: error.native_code
    ]

    concat(["#SimdJson.Error<", to_doc(fields, options), ">"])
  end
end
