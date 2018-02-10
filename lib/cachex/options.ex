defmodule Cachex.Options do
  @moduledoc """
  Binding module to parse options into a cache record.

  This interim module is required to normalize the options passed to a
  cache at startup into a well formed record instance, allowing the rest
  of the codebase to make assumptions about what types of data are being
  dealt with.
  """
  import Cachex.Spec
  import Cachex.Errors

  # add some aliases
  alias Cachex.Spec
  alias Spec.Validator

  ##############
  # Public API #
  ##############

  @doc """
  Retrieves a conditional option from a Keyword List.

  If the value satisfies the condition provided, it will be returned. Otherwise
  the default value provided is returned instead. Used for basic validations.
  """
  @spec get(Keyword.t, atom, (any -> boolean), any) :: any
  def get(options, key, condition, default \\ nil) do
    transform(options, key, fn(val) ->
      try do
        condition.(val) && val || default
      rescue
        _ -> default
      end
    end)
  end

  @doc """
  Parses a list of cache options into a cache record.

  This will validate any options and error on anything we don't understand. The
  advantage of binding into a cache instance is that we can blindly use it in
  other areas of the library without needing to validate. As such, this code can
  easily become a little messy - but that's ok!
  """
  @spec parse(atom, Keyword.t) :: { :ok, Spec.cache } | { :error, atom }
  def parse(name, options) when is_list(options) do
    # complex parsing statements which can fail out early
    with { :ok,      limit } <- setup_limit(name, options),
         { :ok,      hooks } <- setup_hooks(name, options, limit),
         { :ok,   commands } <- setup_commands(name, options),
         { :ok,   fallback } <- setup_fallbacks(name, options),
         { :ok, expiration } <- setup_expiration(name, options),
         { :ok,    warmers } <- setup_warmers(name, options),

         # basic parsing which doesn't have the opportunity to fail
         transactional = get(options, :transactional, &is_boolean/1, false)
      do
        { :ok, cache([
          name: name,
          commands: commands,
          expiration: expiration,
          fallback: fallback,
          hooks: hooks,
          limit: limit,
          transactional: transactional,
          warmers: warmers
        ]) }
      end
  end

  @doc """
  Transforms and returns an option inside a Keyword List.
  """
  @spec transform(Keyword.t, atom, (any -> any)) :: any
  def transform(options, key, transformer) do
    options
    |> Keyword.get(key)
    |> transformer.()
  end

  ###############
  # Private API #
  ###############

  # Parses out any custom commands to be used for custom invocations.
  #
  # We delegate most of the parsing to the Commands module; here we just check
  # that we have a Keyword List to work with, and that there are not duplicate
  # command entries (we want to keep the first to match a typical Keyword behaviour).
  defp setup_commands(_name, options) do
    commands =
      transform(options, :commands, fn
        # map parsing is allowed
        (map) when is_map(map) -> map

        # keyword list parsing is allowed
        (list) when is_list(list) -> list

        # missing is fine
        (nil) -> []

        # anything else, nope!
        (_invalid) -> nil
      end)

    case commands do
      nil  -> error(:invalid_command)
      cmds ->
        validated =
          Enum.all?(cmds, fn
            ({ _name, command }) ->
              Validator.valid?(:command, command)
            (_invalid_elements) ->
              false
          end)

      case validated do
        false -> error(:invalid_command)
        true  ->
          cmds
          |> Enum.reverse
          |> Enum.into(%{})
          |> wrap(:ok)
      end
    end
  end

  # Configures an expiration options record for a cache.
  #
  # We don't allow any shorthands here because there's no logical
  # default to use. Therefore an expiration must be provided, otherwise
  # it'll fail validation and return an error to the caller.
  defp setup_expiration(_name, options) do
    expiration =
      transform(options, :expiration, fn
        # provided expiration, woohoo!
        (expiration() = expiration) ->
          expiration

        # unset so default
        (nil) ->
          expiration()

        # anything else, no thanks!
        (_invalid) ->
          nil
      end)

    # validate using the spec validator
    case Validator.valid?(:expiration, expiration) do
      false -> error(:invalid_expiration)
      true  -> { :ok, expiration }
    end
  end

  # Sets up any cache-wide fallback behaviour.
  #
  # This will allow the shorthanding of a function to act as a default
  # fallback implementation; otherwise the provided value must be a
  # fallback record which is run through the specification validation.
  defp setup_fallbacks(_name, options) do
    fallback =
      transform(options, :fallback, fn
        # provided fallback is great!
        (fallback() = fallback) ->
          fallback

        # allow shorthand of a function
        (fun) when is_function(fun) ->
          fallback(default: fun)

        # unset so default
        (nil) ->
          fallback()

        # anything else, no thanks!
        (_invalid) ->
          nil
      end)

    # validate using the spec validator
    case Validator.valid?(:fallback, fallback) do
      false -> error(:invalid_fallback)
      true  -> { :ok, fallback }
    end
  end

  # Configures any hooks to be enabled for the cache.
  #
  # In addition to the hooks already provided, this will also deal with the
  # notion of statistics hooks and limits, as they can both define hooks.
  defp setup_hooks(name, options, limit) do
    hooks = Enum.concat([
      # stats hook generation
      case !!options[:stats] do
        false -> []
        true  -> [ hook(
          module: Cachex.Stats,
          name: name(name, :stats)
        ) ]
      end,

      # limit hook generation
      case limit do
        limit(size: nil) ->
          []
        limit(policy: policy) ->
          apply(policy, :hooks, [ limit ])
      end,

      # provided hooks lists
      options
      |> Keyword.get(:hooks, [])
      |> List.wrap
    ])

    # validation and division into a hooks record
    case validated?(hooks, :hook) do
      false ->
        error(:invalid_hook)
      true  ->
        type = Enum.group_by(hooks, &hook(&1, :module).type())

        pre  = Map.get(type,  :pre, [])
        post = Map.get(type, :post, [])

        { :ok, hooks(pre: pre, post: post) }
    end
  end

  # Sets up any provided limit structures.
  #
  # This will allow shorthanding of a numeric value to act as a size
  # to bound the cache to. This will provide defaults for all other
  # fields in the limit structure.
  defp setup_limit(_name, options) do
    limit =
      case Keyword.get(options, :limit) do
        limit() = limit -> limit
        size -> limit(size: size)
      end

    case Validator.valid?(:limit, limit) do
      false -> error(:invalid_limit)
      true  -> { :ok, limit }
    end
  end

  # Configures any warmers assigned to the cache.
  #
  # This will return a list of warmer records to be associated to the
  # cache at startup in the incubator service. All warmer records are
  # passed through validation beforehand in order to ensure correctness.
  defp setup_warmers(_name, options) do
    # pull warmers
    warmers =
      options
      |> Keyword.get(:warmers, [])
      |> List.wrap

    # validation of all warmer records
    case validated?(warmers, :warmer) do
      false -> error(:invalid_warmer)
      true  -> { :ok, warmers }
    end
  end

  # Shorthand validation of a record type.
  #
  # This just iterates and ensures all elements in the provided enum
  # are validated using the specification validation for the given type.
  defp validated?(enum, type),
    do: Enum.all?(enum, &Validator.valid?(type, &1))
end
