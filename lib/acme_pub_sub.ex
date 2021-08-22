defmodule AcmePubSub do
  require Logger

  def setup_clients_storage do
    Agent.start_link(fn -> [] end)
  end

  @doc """
  Starts accepting connections on the given `port`.
  """
  def accept(port) do
    {:ok, socket} =
      :gen_tcp.listen(
        port,
        [:binary, packet: :line, active: false, reuseaddr: true]
      )

    Logger.info("Accepting connections on port #{port}")
    loop_acceptor(socket)
  end

  defp loop_acceptor(socket) do
    {:ok, client} = :gen_tcp.accept(socket)
    Logger.info("Accepted new connection")
    {:ok, pid} = Task.Supervisor.start_child(AcmePubSub.TaskSupervisor, fn -> serve(client) end)
    Agent.update(AcmePubSub.ClientStorage, fn clients -> [client | clients] end)
    :ok = :gen_tcp.controlling_process(client, pid)
    loop_acceptor(socket)
  end

  defp serve(socket) do
    received_message = read_line(socket)
    Logger.info("received message #{received_message}")

    clients = Agent.get(AcmePubSub.ClientStorage, &Function.identity/1)

    for client <- clients,
        socket != client do
      write_line(received_message, client)
    end
  after
    serve(socket)
  end

  defp read_line(socket) do
    {:ok, data} = :gen_tcp.recv(socket, 0)
    data
  end

  defp write_line(line, socket) do
    :gen_tcp.send(socket, line)
  end
end
