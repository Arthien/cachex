defmodule CachexTest do
  use CachexCase

  # Ensures that we're able to start a cache and link it to the current process.
  # We verify the link by spawning a cache from inside another thread and making
  # sure that the cache dies once the spawned process does.
  test "cache start with a link" do
    # fetch some names
    name1 = Helper.create_name()
    name2 = Helper.create_name()

    # cleanup on exit
    Helper.delete_on_exit(name1)
    Helper.delete_on_exit(name2)

    # this process should live
    { :ok, pid1 } = Cachex.start_link(name1)

    # check valid pid
    assert(is_pid(pid1))
    assert(Process.alive?(pid1))

    # this process should die
    spawn(fn ->
      { :ok, pid } = Cachex.start_link(name2)
      assert(is_pid(pid))
    end)

    # wait for spawn to end
    :timer.sleep(15)

    # process should've died
    assert(Process.whereis(name2) == nil)
  end

  # Ensures that we're able to start a cache without a link to the current process.
  # This is similar to the previous test, except a cache started in a spawned
  # process should stay alive after the process terminates.
  test "cache start without a link" do
    # fetch some names
    name1 = Helper.create_name()
    name2 = Helper.create_name()

    # cleanup on exit
    Helper.delete_on_exit(name1)
    Helper.delete_on_exit(name2)

    # this process should live
    { :ok, pid1 } = Cachex.start(name1)

    # check valid pid
    assert(is_pid(pid1))
    assert(Process.alive?(pid1))

    # this process should die
    spawn(fn ->
      { :ok, pid } = Cachex.start(name2)
      assert(is_pid(pid))
    end)

    # wait for spawn to end
    :timer.sleep(5)

    # process should've lived
    refute(Process.whereis(name2) == nil)
  end

  # Ensures that trying to start a cache when the application has not been started
  # causes an error to be returned. The application must be started because of our
  # global ETS table which stores cache states in the background.
  test "cache start when application not started" do
    # fetch a name
    name = Helper.create_name()

    # cleanup on exit (just in case)
    Helper.delete_on_exit(name)

    # ensure that we start the app on exit
    on_exit(fn -> Application.ensure_all_started(:cachex) end)

    # capture the log to avoid bloating test output
    ExUnit.CaptureLog.capture_log(fn ->
      # here we kill the application
      Application.stop(:cachex)
    end)

    # try to start the cache with our cache name
    { :error, reason } = Cachex.start_link(name)

    # we should receive a prompt to start our application properly
    assert(reason == :not_started)
  end

  # This test does a simple check that a cache must be started with a valid atom
  # cache name, otherwise an error is raised (an ArgumentError). The error should
  # be a shorthand atom which can be used to debug what the issue was.
  test "cache start with invalid cache name" do
    # try to start the cache with an invalid name
    { :error, reason } = Cachex.start_link("fake_name")

    # we should've received an atom warning
    assert(reason == :invalid_name)
  end

  # This test makes sure that we can pass ETS options through to the table sitting
  # behind Cachex. This allows for customization of things such as compression. To
  # check this, we just start a cache with custom options and call ETS directly
  # in order to see the configuration being used.
  test "cache start with custom ETS options" do
    # fetch a name
    name = Helper.create_name()

    # cleanup on exit
    Helper.delete_on_exit(name)

    # start up a cache
    { :ok, pid } = Cachex.start_link(name, [ ets_opts: [ :compressed ] ])

    # check valid pid
    assert(is_pid(pid))
    assert(Process.alive?(pid))

    # ensure compression is enabled
    assert(:ets.info(name, :compressed))
  end

  # This test ensures that we handle invalid ETS options gracefully. ETS would
  # usually throw an ArgumentError, but that's a bit too extreme in our case, as
  # we'd rather just return a short atom error message to hint what the issue is.
  test "cache start with invalid ETS options" do
    # fetch a name
    name = Helper.create_name()

    # cleanup on exit (just in case)
    Helper.delete_on_exit(name)

    # try to start a cache with invalid ETS options
    { :error, reason } = Cachex.start_link(name, [ ets_opts: [ :marco_yolo ] ])

    # we should've received an atom warning
    assert(reason == :invalid_option)
  end

  # This test ensures that we handle option parsing errors gracefully. If anything
  # goes wrong when parsing options, we exit early before starting the cache to
  # avoid bloating the Supervision tree.
  test "cache start with invalid options" do
    # fetch a name
    name = Helper.create_name()

    # cleanup on exit (just in case)
    Helper.delete_on_exit(name)

    # try to start a cache with invalid hook definitions
    { :error, reason } = Cachex.start_link(name, [ hooks: %Cachex.Hook{ module: Missing } ])

    # we should've received an atom warning
    assert(reason == :invalid_hook)
  end

  # Naturally starting a cache when a cache already exists with the same name will
  # cause an issue, so this test is just ensuring that we handle it gracefully
  # by returning a small atom error saying that the cache name already exists.
  test "cache start with existing cache name" do
    # fetch a name
    name = Helper.create_name()

    # cleanup on exit (just in case)
    Helper.delete_on_exit(name)

    # this cache should start successfully
    { :ok, pid } = Cachex.start_link(name)

    # check valid pid
    assert(is_pid(pid))
    assert(Process.alive?(pid))

    # try to start a cache with the same name
    { :error, reason1 } = Cachex.start_link(name)
    { :error, reason2 } = Cachex.start(name)

    # match the reason to be more granular
    assert(reason1 == { :already_started, pid })
    assert(reason2 == { :already_started, pid })
  end

  # We also need to make sure that a cache function executed against an invalid
  # cache name does not execute properly and returns an atom error which can be
  # used to debug further, rather than a generic error. We make sure to check
  # both execution with valid and invalid names to make sure we catch both.
  test "cache execution with an invalid name" do
    # fetch a name
    name = Helper.create_name()

    # try to execute a cache action against a missing cache and an invalid name
    { :error, reason1 } = Cachex.execute(name, &(&1))
    { :error, reason2 } = Cachex.execute("na", &(&1))

    # match the reason to be more granular
    assert(reason1 == :no_cache)
    assert(reason2 == :no_cache)
  end

end
