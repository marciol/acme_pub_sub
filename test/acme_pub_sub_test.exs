defmodule AcmePubSubTest do
  use ExUnit.Case
  doctest AcmePubSub

  @socket_options [:binary, packet: :line, active: false]

  @tag capture_log: true
  test "it broadcasts to all listeners except the producer" do
    {:ok, producer} = :gen_tcp.connect('localhost', 4040, @socket_options)
    send_message = "hello from client\n"

    allowed_receivers =
      for _ <- 1..3, into: [] do
        {:ok, receiver} = :gen_tcp.connect('localhost', 4040, @socket_options)

        Task.async(fn ->
          {:ok, received_message} = :gen_tcp.recv(receiver, 0)
          received_message
        end)
      end

    unallowed_receiver =
      Task.async(fn ->
        {:ok, received_message} = :gen_tcp.recv(producer, 0)
        received_message
      end)

    Task.start_link(fn ->
      Process.send_after(self(), :ok, 50)

      receive do
        :ok ->
          :gen_tcp.send(producer, send_message)
      end
    end)

    for %{ref: ref} <- allowed_receivers do
      assert_receive {^ref, ^send_message}
    end

    with %{ref: ref} <- unallowed_receiver do
      refute_receive {^ref, ^send_message}
    end
  end

  @tag capture_log: true
  test "it closes the connection without errors" do
    {:ok, receiver} = :gen_tcp.connect('localhost', 4040, @socket_options)

    %{ref: ref} =
      Task.async(fn ->
        {:ok, message} = :gen_tcp.recv(receiver, 0)
        :gen_tcp.close(receiver)
        message
      end)

    {:ok, producer} = :gen_tcp.connect('localhost', 4040, @socket_options)

    Task.start_link(fn ->
      Process.send_after(self(), :ok, 50)

      receive do
        :ok ->
          :gen_tcp.send(producer, "ping\n")
      end
    end)

    assert_receive {^ref, "ping\n"}

    {:ok, another_receiver} = :gen_tcp.connect('localhost', 4040, @socket_options)

    %{ref: ref} =
      Task.async(fn ->
        {:ok, message} = :gen_tcp.recv(another_receiver, 0)
        :gen_tcp.close(another_receiver)
        message
      end)

    Task.start_link(fn ->
      Process.send_after(self(), :ok, 50)

      receive do
        :ok ->
          :gen_tcp.send(producer, "pong\n")
      end
    end)

    assert_receive {^ref, "pong\n"}
  end
end
