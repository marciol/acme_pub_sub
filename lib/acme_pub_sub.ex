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
    {:ok, client_socket} = :gen_tcp.accept(socket)
    Logger.info("Accepted new connection")

    {:ok, output_pid} =
      Task.Supervisor.start_child(
        AcmePubSub.TaskSupervisor,
        fn ->
          output_server(client_socket)
        end
      )

    {:ok, input_pid} =
      Task.Supervisor.start_child(
        AcmePubSub.TaskSupervisor,
        fn ->
          input_server({client_socket, output_pid})
        end
      )

    Agent.update(AcmePubSub.ConnectedClients, fn clients ->
      [{input_pid, output_pid} | clients]
    end)

    loop_acceptor(socket)
  end

  defp input_server({client_socket, output_pid}) do
    case read_line(client_socket) do
      {:ok, data} ->
        dispatch(data)
        input_server({client_socket, output_pid})

      {:error, :closed} ->
        Agent.update(
          AcmePubSub.ConnectedClients,
          fn clients ->
            List.delete(clients, {self(), output_pid})
          end
        )

        send(output_pid, :close)

        :ok
    end
  end

  defp output_server(client_socket) do
    receive do
      :close ->
        :ok

      data ->
        write_line(data, client_socket)
        output_server(client_socket)
    end
  end

  defp dispatch(data) do
    clients = Agent.get(AcmePubSub.ConnectedClients, &Function.identity/1)

    for {input_pid, output_pid} <- clients,
        input_pid != self() do
      send(output_pid, data)
    end
  end

  defp read_line(socket) do
    :gen_tcp.recv(socket, 0)
  end

  defp write_line(line, socket) do
    :gen_tcp.send(socket, line)
  end
end
