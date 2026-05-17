defmodule ExPiWeb.CoreComponents do
  use Phoenix.Component

  def header(assigns) do
    ~H"""
    <header>
      <h1>{@title}</h1>
    </header>
    """
  end

  def flash(assigns) do
    assigns = assign(assigns, :message, Phoenix.Flash.get(assigns.flash, assigns.kind))

    ~H"""
    <div :if={@message} class={"flash-#{@kind}"}>{@message}</div>
    """
  end
end
