defmodule Sigma.Web.Layouts.AppTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  test "renders accessible appbar actions without overflow-prone hint popovers" do
    html =
      render_component(&Sigma.Web.Layouts.app/1, %{
        active_tab: :home,
        flash: %{},
        inner_content: "Content",
        logs_available: true,
        show_logs: false
      })

    document = LazyHTML.from_document(html)

    for label <- ["Home", "Settings", "Debug Logs"] do
      assert document
             |> LazyHTML.query("[aria-label='#{label}'][title='#{label}']")
             |> Enum.count() == 1
    end

    refute document
           |> LazyHTML.query("[popover='hint'], [interestfor]")
           |> Enum.any?()
  end
end
