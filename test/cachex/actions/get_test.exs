defmodule Cachex.Actions.GetTest do
  use CachexCase

  # This test verifies that we can retrieve keys from the cache.
  # If a key has expired, the value is not returned and the hooks
  # are updated with an eviction. If the key is missing, we return
  # a message stating as such.
  test "retrieving keys from a cache" do
    # create a forwarding hook
    hook = ForwardHook.create(%{ results: true })

    # create a test cache
    cache1 = Helper.create_cache([ hooks: [ hook ] ])
    cache2 = Helper.create_cache([
      hooks: [ hook ],
      fallback: [
        state: "val",
        action: &String.reverse("#{&1}_#{&2}")
      ]
    ])
    cache3 = Helper.create_cache([
      hooks: [ hook ],
      fallback: &({ :ignore, &1 })
    ])

    # set some keys in the cache
    { :ok, true } = Cachex.set(cache1, 1, 1)
    { :ok, true } = Cachex.set(cache1, 2, 2, ttl: 1)

    # wait for the TTL to pass
    :timer.sleep(2)

    # flush all existing messages
    Helper.flush()

    # take the first and second key
    result1 = Cachex.get(cache1, 1)
    result2 = Cachex.get(cache1, 2)

    # take a missing key with no fallback
    result3 = Cachex.get(cache1, 3)

    # define the fallback options
    fb_opts1 = [ fallback: false ]

    # take keys with a fallback
    result4 = Cachex.get(cache2, "key1")
    result5 = Cachex.get(cache3, "key2")
    result6 = Cachex.get(cache3, "key3", fb_opts1)

    # verify the first key is retrieved
    assert(result1 == { :ok, 1 })

    # verify the second and third keys are missing
    assert(result2 == { :missing, nil })
    assert(result3 == { :missing, nil })

    # verify the fourth and fifth keys use the default fallbacks
    assert(result4 == { :commit, "lav_1yek" })
    assert(result5 == { :ignore, "key2" })

    # verify the sixth with the disabled fallback
    assert(result6 == { :missing, nil })

    # assert we receive valid notifications
    assert_receive({ { :get, [ 1, [ ] ] }, ^result1 })
    assert_receive({ { :get, [ 2, [ ] ] }, ^result2 })
    assert_receive({ { :get, [ 3, [ ] ] }, ^result3 })
    assert_receive({ { :get, [ "key1", [ ] ] }, ^result4 })
    assert_receive({ { :get, [ "key2", [ ] ] }, ^result5 })
    assert_receive({ { :get, [ "key3", ^fb_opts1 ] }, ^result6 })

    # check we received valid purge actions for the TTL
    assert_receive({ { :purge, [[]] }, { :ok, 1 } })

    # check if the expired key has gone
    exists1 = Cachex.exists?(cache1, 2)

    # it shouldn't exist
    assert(exists1 == { :ok, false })

    # retrieve the fallback keys
    value1 = Cachex.get(cache2, "key1")
    value2 = Cachex.get(cache3, "key2")

    # the first should now exist
    assert(value1 == { :ok, "lav_1yek" })

    # the other shouldn't be committed
    assert(value2 == { :ignore, "key2" })

    # check if the ignored was never there
    exists2 = Cachex.exists?(cache3, "key3")

    # it shouldn't exist
    assert(exists2 == { :ok, false })
  end
end
