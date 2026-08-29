defmodule SimdJson.Projection do
  @moduledoc false

  @typedoc false
  @type output_key :: atom() | binary()

  @typedoc false
  @type object_segment :: binary()

  @typedoc false
  @type array_segment :: 0..18_446_744_073_709_551_615

  @typedoc false
  @type segment :: object_segment() | array_segment()

  @typedoc false
  @type path :: nonempty_list(segment())

  @typedoc false
  @type output_slot :: non_neg_integer()

  @typedoc false
  @type path_slot :: non_neg_integer()

  @typedoc false
  @type normalized_entry :: {output_slot(), output_key(), path_slot()}

  @typedoc false
  @type normalized_path :: {path_slot(), path()}

  @typedoc false
  @opaque t ::
            {:simd_json_projection_v1, nonempty_list(normalized_entry()),
             nonempty_list(normalized_path())}
end
