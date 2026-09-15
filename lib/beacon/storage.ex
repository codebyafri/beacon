defmodule Beacon.Storage do
  @moduledoc """
  Optional operation-level storage boundary.

  The default (`storage: nil`) retains Beacon's PostgreSQL implementation.
  A custom provider receives named Content/MediaLibrary operations and their
  original arguments. It must preserve structs, changesets, lifecycle effects,
  publication atomicity and return values. It must fail explicitly for an
  unsupported operation; falling back to PostgreSQL is not permitted.

  Providers are integrations, not Ecto query translators. Their network contracts
  should not expose Beacon structs or executable templates as portable content.
  """
  @callback call(site :: atom(), context :: module(), operation :: atom(), args :: list()) ::
              term()

  @doc false
  def dispatch(context, operation, args, default) do
    case site(args) do
      nil ->
        default.()

      site ->
        case Beacon.Config.fetch!(site).storage do
          nil -> default.()
          provider -> provider.call(site, context, operation, args)
        end
    end
  end

  defp site([%{site: site} | _]) when is_atom(site) and not is_nil(site), do: site
  defp site([%{site: site} | _]) when is_binary(site), do: String.to_existing_atom(site)
  defp site([%{"site" => site} | _]) when is_atom(site) and not is_nil(site), do: site
  defp site([%{"site" => site} | _]) when is_binary(site), do: String.to_existing_atom(site)
  defp site([site | _]) when is_atom(site) and not is_nil(site), do: site

  defp site([values | rest]) when is_list(values) do
    site(values) || site(rest)
  end

  defp site([_ | rest]), do: site(rest)
  defp site([]), do: nil

  @doc false
  defmacro __using__(opts) do
    quote do
      @beacon_storage_operations unquote(Keyword.fetch!(opts, :operations))
      @before_compile Beacon.Storage
    end
  end

  defmacro __before_compile__(env) do
    names = Module.get_attribute(env.module, :beacon_storage_operations)

    definitions =
      Module.definitions_in(env.module, :def)
      |> Enum.filter(fn {name, _} = key ->
        case Module.get_definition(env.module, key) do
          {:v1, :def, _, [{_, _, _, {:super, metadata, _}}]} ->
            name in names and not metadata[:default]

          _ ->
            name in names
        end
      end)

    wrappers =
      Enum.map(definitions, fn {name, arity} ->
        args = Macro.generate_arguments(arity, env.module)

        quote do
          defoverridable [{unquote(name), unquote(arity)}]

          def unquote(name)(unquote_splicing(args)) do
            Beacon.Storage.dispatch(__MODULE__, unquote(name), [unquote_splicing(args)], fn ->
              super(unquote_splicing(args))
            end)
          end
        end
      end)

    quote do
      unquote_splicing(wrappers)
      @doc false
      def storage_operations, do: unquote(definitions)
    end
  end
end
