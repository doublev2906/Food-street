defmodule FoodStreet.SettingsTest do
  use FoodStreet.DataCase, async: true

  alias FoodStreet.Settings

  describe "key-value settings" do
    test "get_value returns default when missing" do
      assert Settings.get_value("nope") == nil
      assert Settings.get_value("nope", "fallback") == "fallback"
    end

    test "put_value inserts then updates (upsert by key)" do
      assert {:ok, _} = Settings.put_value("k", "v1")
      assert Settings.get_value("k") == "v1"

      assert {:ok, _} = Settings.put_value("k", "v2")
      assert Settings.get_value("k") == "v2"
    end
  end

  describe "panchat token" do
    test "not configured by default" do
      refute Settings.panchat_configured?()
      assert Settings.panchat_token() == nil
    end

    test "configured after saving a non-blank token" do
      assert {:ok, _} = Settings.put_panchat_token("abc123")
      assert Settings.panchat_configured?()
      assert Settings.panchat_token() == "abc123"
    end

    test "blank token counts as not configured" do
      assert {:ok, _} = Settings.put_panchat_token("   ")
      refute Settings.panchat_configured?()
    end
  end
end
