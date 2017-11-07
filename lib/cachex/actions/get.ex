defmodule Cachex.Actions.Get do
  @moduledoc false
  # This module provides the implementation for the Get action, which is in charge
  # of retrieving values from the cache by key. If the record has expired, it is
  # purged on read. If the record is missing, we allow the use of fallback functions
  # to populate a new value in the cache.

  # we need our imports
  use Cachex.Actions

  # add some aliases
  alias Cachex.Actions
  alias Cachex.State

  @doc """
  Retrieves a value from inside the cache.

  This action supports the use of default fallbacks set on a cache state for the
  ability to fallback to another cache, or to compute any missing values. If the
  value does not exist in the cache, fallbacks can be used to set the value in
  the cache for next time. Note that `nil` values inside the cache are treated
  as missing values.
  """
  defaction get(%State{ } = state, key, options) do
    case Actions.read(state, key) do
      { ^key, _touched, _ttl, value } ->
        { :ok, value }
      _missing ->
        { :missing, nil }
    end
  end
end
