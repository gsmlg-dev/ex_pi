defmodule ExPiWeb.HomeLiveIntegrationTest do
  use ExPiWeb.ConnCase, async: true
  import Phoenix.LiveViewTest

  alias ExPiSession.RepoManager

  test "renders home page grid", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/")
    assert html =~ "Repositories"
    assert html =~ "Add Repository"
  end

  test "navigates to add repository page", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/")
    
    {:ok, _view, html} = 
      view 
      |> element("#add-repo-btn") 
      |> render_click()
      |> follow_redirect(conn, "/workdir/new/project")

    assert html =~ "Add Project Repository"
    assert html =~ "Selected Path"
  end

  test "adds valid repo and returns to index", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/workdir/new/project")
    
    # By default browser shows user home
    {:ok, _view, html} = 
      view 
      |> render_click("browser_confirm") 
      |> follow_redirect(conn, "/")
    
    assert html =~ "Repository added successfully."
    home = System.user_home!()
    assert html =~ Path.basename(home)
    
    # Cleanup
    RepoManager.remove_repo(home)
  end

  test "toggles directory browser", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/workdir/new/project")
    
    assert render(view) =~ "Add This Directory"
    home = System.user_home!()
    assert render(view) =~ home
    
    # Navigate up
    render_click(view, "browser_up")
    assert render(view) =~ Path.dirname(home)
  end
end
