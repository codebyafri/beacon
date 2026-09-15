defmodule Beacon.StorageTest do
  use ExUnit.Case, async: false

  defmodule Provider do
    @behaviour Beacon.Storage
    def call(site, context, operation, args), do: {:provider, site, context, operation, args}
  end

  test "an explicit provider permits a configuration without an Ecto repo" do
    config =
      Beacon.Config.new(
        site: :provider_test,
        endpoint: :endpoint,
        router: :router,
        storage: Provider
      )

    assert config.repo == nil
    assert config.storage == Provider
  end

  test "operations and default arities dispatch through the site provider" do
    site = :not_booted
    old = Beacon.Config.fetch!(site).storage
    Beacon.Config.update_value(site, :storage, Provider)
    on_exit(fn -> Beacon.Config.update_value(site, :storage, old) end)

    assert {:provider, ^site, Beacon.Content, :list_pages, [^site, []]} =
             Beacon.Content.list_pages(site)

    assert {:provider, ^site, Beacon.Content, :create_page, [%{site: ^site}]} =
             Beacon.Content.create_page(%{site: site})

    assert {:provider, ^site, Beacon.MediaLibrary, :list_assets, [^site, []]} =
             Beacon.MediaLibrary.list_assets(site)
  end
end
