defmodule Cachex.Services.Locksmith.Queue do
  @moduledoc false
  # This module acts as the transaction queue that backs a cache instance.
  #
  # The Locksmith global process cannot include the queue because then caches
  # would compete with each other for resources, which is not ideal. Each one
  # will therefore have their own queue, represented in this module, and will
  # operate using the utilities provided in the main Locksmith.

  # import the Locksmith for ease
  import Cachex.Services.Locksmith

  @doc """
  Starts an Eternal ETS table to act as a global lock table.

  We start the table with no logging to make sure we don't spam a developer's
  log output. This may be configurable in future, but this table will likely
  never cause an issue in the first place (as it handles only basic interactions).
  """
  def start_link(%Cachex.State{ locksmith: locksmith } = state),
    do: GenServer.start_link(__MODULE__, state, [ name: locksmith ])

  @doc """
  Sets the current process as transactional and returns the cache as the state.
  """
  def init(state) do
    # signal transactional
    start_transaction()
    # cache is state
    { :ok, state }
  end

  @doc """
  Executes a function in a lock-free context.

  Because locks are handled sequentially inside this process, this execution can
  guarantee that there are no locks currently set on the table when it fires.
  """
  def handle_call({ :exec, func }, _ctx, state),
    do: { :reply, safe_exec(func), state }

  @doc """
  Executes a function in a transactional context.

  This will lock any required keys before carrying out any writes, and then remove
  the locks. The key here is that locks on a key will stop other processes from
  writing them, and forcing those processes to queue their writes up inside this
  process.
  """
  def handle_call({ :transaction, keys, func }, _ctx, state) do
    true = lock(state, keys)
    val  = safe_exec(func)
    true = unlock(state, keys)

    { :reply, val, state }
  end

  # Simply a wrapper around provided functions to ensure that error handling is
  # provided appropriately. Any errors which occur in the execution of the given
  # function are rescued and returned in an error Tuple.
  defp safe_exec(fun) do
    fun.()
  rescue
    e -> { :error, Exception.message(e) }
  end
end
