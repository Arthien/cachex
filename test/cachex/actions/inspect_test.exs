defmodule Cachex.Actions.InspectTest do
  use CachexCase

  # This test ensures that we can correctly inspect various things related to
  # expired keys inside the cache. We need to make sure that the check both the
  # count of expired keys, as well as retrieving a list of expired keys.
  test "inspecting expired keys" do
    # create a test cache
    cache = Helper.create_cache()

    # set several values in the cache
    for x <- 1..3 do
      { :ok, true } = Cachex.set(cache, "key#{x}", "value#{x}", ttl: 1)
    end

    # make sure they expire
    :timer.sleep(2)

    # check both the expired count and the keyset
    expired1 = Cachex.inspect(cache, { :expired, :count })
    expired2 = Cachex.inspect(cache, { :expired,  :keys })

    # the first should contain the count of expired keys
    assert(expired1 == { :ok, 3 })

    # break down the expired2 value
    { :ok, keys } = expired2

    # so we just check if they're in the list
    assert("key1" in keys)
    assert("key2" in keys)
    assert("key3" in keys)

    # grab the length of the expired keys
    length1 = length(keys)

    # finally we make sure there are no bonus keys
    assert(length1 == 3)
  end

  # This test ensures that we can see the results of the last time a Janitor
  # process ran. This inspection will simply call the Janitor process to retrieve
  # the last metadata - we don't have to validate what exactly is inside here
  # beyond the fact that it returns successfully. We should also test that an
  # error is returned if there is no Janitor process started for the cache.
  test "inspecting janitor metadata" do
    # create a cache with no janitor and one with
    cache1 = Helper.create_cache([ ttl_interval: -1 ])
    cache2 = Helper.create_cache([ ttl_interval:  1 ])

    # let the janitor run
    :timer.sleep(2)

    # retrieve Janitor metadata for both states
    result1 = Cachex.inspect(cache1, { :janitor, :last })
    result2 = Cachex.inspect(cache2, { :janitor, :last })

    # the first cache should have an error
    assert(result1 == { :error, :janitor_disabled })

    # break down the second result
    { :ok, meta } = result2

    # check the metadata matches the patterns
    assert(is_integer(meta.count))
    assert(is_integer(meta.duration))
    assert(is_integer(meta.started))
  end

  # This test verifies that we can return stats about the memory being used by a
  # cache. This inspection can be coupled with a flag which returns the results
  # as either a binary or a number of bytes.
  test "inspecting cache memory" do
    # create a test cache
    cache = Helper.create_cache()

    # retrieve the memory usage
    { :ok, result1 } = Cachex.inspect(cache, { :memory, :bytes })
    { :ok, result2 } = Cachex.inspect(cache, { :memory, :binary })
    { :ok, result3 } = Cachex.inspect(cache, { :memory, :words })

    # the first result should be a number of bytes
    assert_in_delta(result1, 10624, 1000)

    # the second result should be a human readable representation
    assert(result2 =~ ~r/10.3\d KiB/)

    # fetch the system word size
    wsize = :erlang.system_info(:wordsize)

    # verify the words in the byte result
    words = div(result1, wsize)

    # the third should be a number of words
    assert(result3 == words)
  end

  # This test verifies that we can retrieve a raw cache record without doing any
  # extra work such as checking TTLs. We check that a missing record returns a
  # nil, and that an existing record returns the record.
  test "inspecting cache records" do
    # create a test cache
    cache = Helper.create_cache()

    # get the current time
    ctime = now()

    # set a cache record
    { :ok, true } = Cachex.set(cache, 1, "one", ttl: 1000)

    # fetch some records
    record1 = Cachex.inspect(cache, { :record, 1 })
    record2 = Cachex.inspect(cache, { :record, 2 })

    # break down the first record
    { :ok, { :entry, key, touched, ttl, value } } = record1

    # verify the first record
    assert(key == 1)
    assert_in_delta(touched, ctime, 2)
    assert(ttl == 1000)
    assert(value == "one")

    # the second should be nil
    assert(record2 == { :ok, nil })
  end

  # This test simply ensures that inspecting the cache state will return you the
  # cache state. This should always match the latest copy of the state, rather
  # than using the state passed in. This is the only thing to verify.
  test "inspecting cache state" do
    # create a test cache
    cache = Helper.create_cache()

    # retrieve the cache state
    state1 = Services.Overseer.get(cache)

    # update the state to have a different setting
    state2 = Services.Overseer.update(cache, fn(state) ->
      %Cachex.Cache{ state | transactions: true }
    end)

    # retrieve the state via inspection
    result = Cachex.inspect(state1, :state)

    # ensure the states don't match
    assert(result != { :ok, state1 })

    # the result should be using the latest state
    assert(result == { :ok, state2 })
  end

  # This test just verifies that we return an invalid option error when the value
  # is unrecognised. There's nothing else to validate beyond the error.
  test "inspecting invalid options" do
    # create a test cache
    cache = Helper.create_cache()

    # retrieve an invalid option
    result = Cachex.inspect(cache, :invalid)

    # check the result is an error
    assert(result == { :error, :invalid_option })
  end

end
